# AI FLAC Metadata Pipeline

這個專案會掃描音樂根目錄下的 FLAC 檔，依專輯分批呼叫 Copilot 產生正規化 metadata，最後把結果寫回檔案並重新命名。

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