# AI FLAC Metadata Pipeline

這個專案會掃描音樂根目錄下的 FLAC 檔，依專輯分批呼叫 Copilot 產生正規化 metadata，最後把結果寫回檔案並重新命名。

## 多片裝跨資料夾分組

Pipeline 會先做自動分群，再決定每一批要送給 Copilot 的「專輯工作單位」。

- 分群依據：既有 tags 的 `album`、`albumartist`、`date`（年份）與資料夾名稱中的 CD/Disc 訊號。
- 合併策略：保守合併，只有高信心才會把多個資料夾合成同一批。
- 低信心案例：會維持分開處理，避免同名不同版本專輯被誤合併。

這代表當 CD 1、CD 2 在不同資料夾，但 tags 與碟號訊號一致時，會在同一次 album-level 正規化中處理，並統一 album 與 albumartist。

可在 `scripts\_debug_album\run-album-log.txt` 與每批 `album-input.json` 中查看：

- `group_key`
- `group_confidence`
- `group_reason`
- `source_folders`

## 使用方式

1. 確認電腦已安裝並可直接使用 `python`、`PowerShell`，以及 Copilot CLI。若要做 ReplayGain，另外需要 `rsgain`。
2. 把要處理的 FLAC 專輯資料夾放在此專案根目錄下，或保留既有的專輯資料夾結構。
3. 執行根目錄的 `start_pipeline.bat`。
4. 執行結果與中間檔會輸出到 `scripts\_debug_album`。

## Prompt 檔案

- `prompts\01_album_core_output.txt`：定義輸出的基本 JSON 結構與必填欄位。
- `prompts\02_metadata_rule.txt`：說明一般 metadata 正規化規則。
- `prompts\03_classical_rules.txt`：補充古典音樂專用的命名與欄位規則。
- `prompts\99_album_hint.txt`：保留給使用者自行加寫的額外提示。

## 目錄說明

- `start_pipeline.bat`：唯一保留在根目錄的執行入口。
- `scripts`：Pipeline 腳本與除錯輸出資料夾。
- `prompts`：可自行調整的 prompt 規則檔。