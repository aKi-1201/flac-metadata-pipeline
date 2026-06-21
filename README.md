# AI FLAC Metadata Pipeline

這個專案會掃描音樂根目錄下的 FLAC 檔，依專輯分批呼叫 Gemini API 產生正規化 metadata，最後把結果寫回檔案並重新命名。

[Medium 文章](https://medium.com/@duckong/nas-將-cd-收藏數位化-打造私人無損音樂串流平台-特別篇-如何利用-ai-執行元數據正規化-b20d624dae19)

## 需求

- Python 3.10+
- PowerShell 5.1+
- `google-genai` Python 套件
- （選用）`rsgain`，用於寫入 ReplayGain

安裝套件：

```powershell
pip install google-genai
```

## 快速開始

**1. 取得 Gemini API Key**

前往 [ai.google.dev](https://ai.google.dev) 以 Google 帳號登入，免費建立 API Key，無須信用卡。

**2. 建立 `.env` 檔**

在專案根目錄（與 `start_pipeline.bat` 同層）新增 `.env` 檔：

```
GEMINI_API_KEY=你的金鑰貼這裡
```

> ⚠️ `.env` 已列入 `.gitignore`，不會被上傳到 GitHub。請勿將金鑰直接寫進任何腳本。

**3. 放入音樂資料夾，執行 Pipeline**

把要處理的 FLAC 專輯資料夾放在專案根目錄下，執行：

```powershell
.\start_pipeline.bat
```

執行結果與中間檔會輸出到 `scripts\_debug_album`。

## 使用模型

預設使用 `gemini-3.1-flash-lite`，該模型在 Google AI Studio 免費方案下提供每日 500 次請求（RPD），適合批次處理大量專輯。

若需要更高品質的推論（例如作曲家辨識較困難的專輯），可在 `scripts\call_gemini.py` 中改為 `gemini-2.5-flash`（每日 20 次免費額度）。

可在 [aistudio.google.com](https://aistudio.google.com) 的 Rate limits 頁面查看各模型的剩餘免費配額。

## 多片裝跨資料夾分組

Pipeline 會先做自動分群，再決定每一批要送給 Gemini 的「專輯工作單位」。

- 分群依據：既有 tags 的 `album`、`albumartist`、`date`（年份）與資料夾名稱中的 CD/Disc 訊號。
- 合併策略：保守合併，只有高信心才會把多個資料夾合成同一批。
- 低信心案例：會維持分開處理，避免同名不同版本專輯被誤合併。

當 CD 1、CD 2 在不同資料夾，但 tags 與碟號訊號一致時，會在同一次 album-level 正規化中處理，並統一 `album` 與 `albumartist`。

可在 `scripts\_debug_album\run-album-log.txt` 與每批 `album-input.json` 中查看：

- `group_key`
- `group_confidence`
- `group_reason`
- `source_folders`

## Prompt 檔案

| 檔案 | 說明 |
|---|---|
| `prompts\01_album_core_output.txt` | 定義輸出的 JSON 結構與必填欄位 |
| `prompts\02_metadata_rule.txt` | 通用 metadata 正規化規則（composer、artist、albumartist 排列順序等） |
| `prompts\03_classical_rules.txt` | 古典音樂專用規則（作品編號、Title Case、名稱標準化等） |
| `prompts\99_album_hint.txt` | 保留給使用者自行加寫的額外提示 |

## 目錄結構

```
flac-metadata-pipeline/
├── start_pipeline.bat          # 唯一執行入口
├── prompts/                    # Prompt 規則檔
└── scripts/
    ├── .env                    # API Key（不上傳 GitHub）
    ├── .env.example            # 金鑰格式範本
    ├── run_album.ps1           # 主要 Pipeline 流程
    ├── call_gemini.py          # Gemini API 呼叫腳本
    ├── extract_album.py        # 從 FLAC 擷取既有 metadata
    ├── write_album.py          # 將正規化結果寫回 FLAC
    └── _debug_album/           # 執行中間檔與 log 輸出
```
