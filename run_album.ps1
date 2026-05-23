# ============================================================
# Album-Level AI FLAC Metadata Pipeline
# With:
# - prompts_album auto loading
# - album-level metadata normalization
# - album_profile.json support
# - multi-disc folder support
# - rsgain ReplayGain album scan
# ============================================================

# Force UTF-8 console I/O
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

# Root = folder where this script is located
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = $scriptDir

# Required paths
$extractAlbumPy = Join-Path $scriptDir "extract_album.py"
$writeAlbumPy   = Join-Path $scriptDir "write_album.py"
$promptDir      = Join-Path $scriptDir "prompts_album"

# Debug folder
$debugDir = Join-Path $scriptDir "_debug_album"

if (-not (Test-Path -LiteralPath $debugDir)) {
    New-Item -ItemType Directory -Path $debugDir | Out-Null
}

# Log file
$logFile = Join-Path $debugDir "run-album-log.txt"


# ============================================================
# Helper: write UTF-8 without BOM
# ============================================================

function Write-Utf8NoBom {
    param (
        [string]$Path,
        [string]$Content
    )

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}


# ============================================================
# Helper: normalize Windows extended paths
# Converts:
#   \\?\D:\path      -> D:\path
#   \\?\UNC\a\b     -> \\a\b
# ============================================================

function Normalize-WindowsPath {
    param (
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $Path
    }

    if ($Path.StartsWith("\\?\UNC\")) {
        return "\\" + $Path.Substring(8)
    }

    if ($Path.StartsWith("\\?\")) {
        return $Path.Substring(4)
    }

    return $Path
}


# ============================================================
# Helper: extract valid JSON from Copilot output
# Supports:
# 1. Pure JSON
# 2. Markdown code block:
#    ```json
#    {...}
#    ```
# 3. Text mixed with JSON
# ============================================================

function Get-ValidJsonFromText {
    param (
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    $trimmed = $Text.Trim()

    # 1. Try whole text directly
    try {
        $trimmed | ConvertFrom-Json | Out-Null
        return $trimmed
    }
    catch {}

    # 2. Try JSON inside markdown code blocks
    $codeBlockMatches = [regex]::Matches(
        $Text,
        '(?s)```(?:json)?\s*(.*?)\s*```'
    )

    foreach ($m in $codeBlockMatches) {
        $candidate = $m.Groups[1].Value.Trim()

        try {
            $candidate | ConvertFrom-Json | Out-Null
            return $candidate
        }
        catch {}
    }

    # 3. Try from first { to last }
    $firstBrace = $Text.IndexOf("{")
    $lastBrace = $Text.LastIndexOf("}")

    if ($firstBrace -ge 0 -and $lastBrace -gt $firstBrace) {
        $candidate = $Text.Substring($firstBrace, $lastBrace - $firstBrace + 1).Trim()

        try {
            $candidate | ConvertFrom-Json | Out-Null
            return $candidate
        }
        catch {}
    }

    # 4. Try from first [ to last ]
    $firstBracket = $Text.IndexOf("[")
    $lastBracket = $Text.LastIndexOf("]")

    if ($firstBracket -ge 0 -and $lastBracket -gt $firstBracket) {
        $candidate = $Text.Substring($firstBracket, $lastBracket - $firstBracket + 1).Trim()

        try {
            $candidate | ConvertFrom-Json | Out-Null
            return $candidate
        }
        catch {}
    }

    return $null
}


# ============================================================
# Helper: identify album root from a FLAC file path
# Handles:
#   Album\01.flac              -> Album
#   Album\CD1\01.flac          -> Album
#   Album\CD 1\01.flac         -> Album
#   Album\Disc 1\01.flac       -> Album
#   Album\Disk 1\01.flac       -> Album
# ============================================================

function Get-AlbumRootFromFlacFile {
    param (
        [System.IO.FileInfo]$File
    )

    $parent = $File.Directory

    if ($null -eq $parent) {
        return $null
    }

    $parentName = $parent.Name

    $isDiscFolder =
        $parentName -match '^(?i)(cd|disc|disk)\s*\d+$' -or
        $parentName -match '^(?i)(cd|disc|disk)\s*[-_]\s*\d+$'

    if ($isDiscFolder -and $null -ne $parent.Parent) {
        return (Normalize-WindowsPath $parent.Parent.FullName)
    }

    return (Normalize-WindowsPath $parent.FullName)
}


# ============================================================
# Helper: find album folders
# Strategy:
# - Find all FLAC files under root
# - If FLAC is inside CD1/CD2/Disc 1 folders, use parent folder as album
# - Otherwise use direct parent folder
# ============================================================

function Get-AlbumFolders {
    param (
        [string]$Root,
        [string]$DebugDir,
        [string]$PromptDir
    )

    $flacFiles = Get-ChildItem -LiteralPath $Root -Recurse -File -Filter "*.flac" |
        Where-Object {
            $_.FullName -notlike "$DebugDir*" -and
            $_.FullName -notlike "$PromptDir*" -and
            $_.FullName -notlike "*_debug_json*" -and
            $_.FullName -notlike "*_debug_album*" -and
            $_.FullName -notlike "*prompts_album*" -and
            $_.FullName -notlike "*prompts*"
        }

    $albumPaths = @()

    foreach ($f in $flacFiles) {
        $albumRoot = Get-AlbumRootFromFlacFile -File $f

        if (-not [string]::IsNullOrWhiteSpace($albumRoot)) {
            $albumPaths += $albumRoot
        }
    }

    $uniquePaths = $albumPaths | Sort-Object -Unique

    $albumDirs = @()

    foreach ($p in $uniquePaths) {
        if (Test-Path -LiteralPath $p) {
            $albumDirs += Get-Item -LiteralPath $p
        }
    }

    return $albumDirs
}


# ============================================================
# Helper: ReplayGain album scan using rsgain
# ============================================================

function Invoke-AlbumReplayGain {
    param (
        [string]$AlbumPath,
        [string]$LogFile
    )

    Write-Host "Step 5: Running album ReplayGain scan..."
    "Step 5: Running album ReplayGain scan..." | Add-Content -LiteralPath $LogFile -Encoding utf8

    $normalizedAlbumPath = Normalize-WindowsPath $AlbumPath

    $flacFiles = Get-ChildItem -LiteralPath $normalizedAlbumPath -Recurse -File -Filter "*.flac" |
        Where-Object {
            $_.FullName -notlike "*_debug_album*" -and
            $_.FullName -notlike "*_debug_json*"
        } |
        Sort-Object FullName

    if ($flacFiles.Count -eq 0) {
        Write-Host "WARNING: No FLAC files found for ReplayGain."
        "WARNING: No FLAC files found for ReplayGain." | Add-Content -LiteralPath $LogFile -Encoding utf8
        return
    }

    $rsgainCmd = Get-Command "rsgain" -ErrorAction SilentlyContinue

    if (-not $rsgainCmd) {
        Write-Host "WARNING: rsgain was not found. ReplayGain skipped."
        "WARNING: rsgain was not found. ReplayGain skipped." | Add-Content -LiteralPath $LogFile -Encoding utf8
        return
    }

    Write-Host "Using rsgain for ReplayGain."
    "Using rsgain for ReplayGain." | Add-Content -LiteralPath $LogFile -Encoding utf8

    $args = @(
        "custom",
        "--album",
        "--tagmode=i"
    )

    foreach ($f in $flacFiles) {
        $args += (Normalize-WindowsPath $f.FullName)
    }

    $rgResult = & rsgain @args 2>&1
    $rgText = ($rgResult | ForEach-Object { $_.ToString() }) -join "`n"

    Write-Host $rgText
    $rgText | Add-Content -LiteralPath $LogFile -Encoding utf8

    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: rsgain failed."
        "ERROR: rsgain failed." | Add-Content -LiteralPath $LogFile -Encoding utf8
    }
    else {
        Write-Host "ReplayGain completed with rsgain."
        "ReplayGain completed with rsgain." | Add-Content -LiteralPath $LogFile -Encoding utf8
    }
}


# ============================================================
# Initialize log
# ============================================================

Write-Utf8NoBom -Path $logFile -Content "=== Album run started: $(Get-Date) ===`n"

"Root: $root" | Add-Content -LiteralPath $logFile -Encoding utf8
"ScriptDir: $scriptDir" | Add-Content -LiteralPath $logFile -Encoding utf8
"PromptDir: $promptDir" | Add-Content -LiteralPath $logFile -Encoding utf8
"DebugDir: $debugDir" | Add-Content -LiteralPath $logFile -Encoding utf8

Write-Host "Root: $root"
Write-Host "Script directory: $scriptDir"
Write-Host "Prompt directory: $promptDir"
Write-Host "Debug directory: $debugDir"


# ============================================================
# Required file checks
# ============================================================

if (-not (Test-Path -LiteralPath $extractAlbumPy)) {
    Write-Host "ERROR: extract_album.py not found: $extractAlbumPy"
    "ERROR: extract_album.py not found: $extractAlbumPy" | Add-Content -LiteralPath $logFile -Encoding utf8
    exit 1
}

if (-not (Test-Path -LiteralPath $writeAlbumPy)) {
    Write-Host "ERROR: write_album.py not found: $writeAlbumPy"
    "ERROR: write_album.py not found: $writeAlbumPy" | Add-Content -LiteralPath $logFile -Encoding utf8
    exit 1
}

if (-not (Test-Path -LiteralPath $promptDir)) {
    Write-Host "ERROR: prompts_album folder not found: $promptDir"
    "ERROR: prompts_album folder not found: $promptDir" | Add-Content -LiteralPath $logFile -Encoding utf8
    exit 1
}


# ============================================================
# Load prompt files from prompts_album
# ============================================================

$promptFiles = Get-ChildItem -LiteralPath $promptDir -File -Filter "*.txt" |
    Sort-Object Name

if ($promptFiles.Count -eq 0) {
    Write-Host "ERROR: No prompt files found in prompts_album."
    "ERROR: No prompt files found in prompts_album." | Add-Content -LiteralPath $logFile -Encoding utf8
    exit 1
}

Write-Host "Prompt files loaded:"
"Prompt files loaded:" | Add-Content -LiteralPath $logFile -Encoding utf8

$promptParts = @()

foreach ($pf in $promptFiles) {
    Write-Host " - $($pf.Name)"
    " - $($pf.Name)" | Add-Content -LiteralPath $logFile -Encoding utf8

    $content = Get-Content -LiteralPath $pf.FullName -Raw -Encoding utf8

    $promptParts += @"
===== PROMPT FILE: $($pf.Name) =====

$content
"@
}

$prompt = $promptParts -join "`n`n"


# ============================================================
# Find album folders
# ============================================================

$albumDirs = Get-AlbumFolders -Root $root -DebugDir $debugDir -PromptDir $promptDir

Write-Host "Album folders found: $($albumDirs.Count)"
"Album folders found: $($albumDirs.Count)" | Add-Content -LiteralPath $logFile -Encoding utf8

if ($albumDirs.Count -eq 0) {
    Write-Host "ERROR: No album folders found."
    "ERROR: No album folders found." | Add-Content -LiteralPath $logFile -Encoding utf8
    exit 1
}


# ============================================================
# Main album loop
# ============================================================

$albumIndex = 0

foreach ($album in $albumDirs) {

    $albumIndex++
    $albumPath = Normalize-WindowsPath $album.FullName

    Write-Host "======================"
    Write-Host "Processing album [$albumIndex/$($albumDirs.Count)]: $albumPath"

    "======================" | Add-Content -LiteralPath $logFile -Encoding utf8
    "Processing album [$albumIndex/$($albumDirs.Count)]: $albumPath" | Add-Content -LiteralPath $logFile -Encoding utf8

    try {
        $albumDebugName = "album-{0:D3}" -f $albumIndex
        $albumDebugDir = Join-Path $debugDir $albumDebugName

        if (-not (Test-Path -LiteralPath $albumDebugDir)) {
            New-Item -ItemType Directory -Path $albumDebugDir | Out-Null
        }

        $input     = Join-Path $albumDebugDir "album-input.json"
        $taskFile  = Join-Path $albumDebugDir "album-task.txt"
        $rawOutput = Join-Path $albumDebugDir "album-raw-output.txt"
        $output    = Join-Path $albumDebugDir "album-output.json"

        # ====================================================
        # Step 1: Extract album metadata
        # ====================================================

        Write-Host "Step 1: Extracting album metadata..."
        "Step 1: Extracting album metadata..." | Add-Content -LiteralPath $logFile -Encoding utf8

        $extractResult = & python $extractAlbumPy "$albumPath" 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: extract_album.py failed."
            "ERROR: extract_album.py failed." | Add-Content -LiteralPath $logFile -Encoding utf8

            $extractText = ($extractResult | ForEach-Object { $_.ToString() }) -join "`n"
            $extractText | Add-Content -LiteralPath $logFile -Encoding utf8

            continue
        }

        $extractText = ($extractResult | ForEach-Object { $_.ToString() }) -join "`n"
        Write-Utf8NoBom -Path $input -Content $extractText

        Write-Host "Album input JSON created: $input"
        "Album input JSON created: $input" | Add-Content -LiteralPath $logFile -Encoding utf8

        # Verify track_count
        try {
            $inputObj = Get-Content -LiteralPath $input -Raw -Encoding utf8 | ConvertFrom-Json

            if ($inputObj.track_count -eq 0) {
                Write-Host "WARNING: album-input.json contains zero tracks. Skipping album."
                "WARNING: album-input.json contains zero tracks. Skipping album." | Add-Content -LiteralPath $logFile -Encoding utf8
                continue
            }
        }
        catch {
            Write-Host "WARNING: Could not parse album-input.json."
            "WARNING: Could not parse album-input.json." | Add-Content -LiteralPath $logFile -Encoding utf8
        }

        # ====================================================
        # Step 2: Build Copilot task file
        # ====================================================

        Write-Host "Step 2: Building album task file..."
        "Step 2: Building album task file..." | Add-Content -LiteralPath $logFile -Encoding utf8

        $inputJson = Get-Content -LiteralPath $input -Raw -Encoding utf8

        $taskContent = @"
$prompt

===== ALBUM INPUT JSON =====

$inputJson

===== TASK =====

Convert the ALBUM INPUT JSON into the required album-level metadata JSON.

Final output requirements:
1. Return exactly one JSON object.
2. The JSON object must contain:
   - album
   - tracks
3. tracks must contain one item for each input track.
4. Each output track must preserve the original file path.
5. Return JSON only. No explanations. No markdown code blocks.
"@

        Write-Utf8NoBom -Path $taskFile -Content $taskContent

        Write-Host "Album task file created: $taskFile"
        "Album task file created: $taskFile" | Add-Content -LiteralPath $logFile -Encoding utf8

        # ====================================================
        # Step 3: Run Copilot metadata normalization
        # ====================================================

        Write-Host "Step 3: Running Copilot album normalization..."
        "Step 3: Running Copilot album normalization..." | Add-Content -LiteralPath $logFile -Encoding utf8

        $taskRelative = "_debug_album/$albumDebugName/album-task.txt"

        Push-Location $scriptDir

        try {
            $copilotPrompt = "Read @$taskRelative. Follow the instructions inside exactly. Return only the final JSON object."
            $result = & copilot -sp "$copilotPrompt" 2>&1
        }
        finally {
            Pop-Location
        }

        $rawText = ($result | ForEach-Object { $_.ToString() }) -join "`n"
        Write-Utf8NoBom -Path $rawOutput -Content $rawText

        Write-Host "Raw Copilot output saved: $rawOutput"
        "Raw Copilot output saved: $rawOutput" | Add-Content -LiteralPath $logFile -Encoding utf8

        $json = Get-ValidJsonFromText -Text $rawText

        if ([string]::IsNullOrWhiteSpace($json)) {
            Write-Host "ERROR: No valid JSON found in Copilot output."
            "ERROR: No valid JSON found in Copilot output." | Add-Content -LiteralPath $logFile -Encoding utf8
            continue
        }

        try {
            $jsonObj = $json | ConvertFrom-Json

            if (-not ($jsonObj.PSObject.Properties.Name -contains "tracks")) {
                Write-Host "ERROR: JSON missing key: tracks"
                "ERROR: JSON missing key: tracks" | Add-Content -LiteralPath $logFile -Encoding utf8
                continue
            }

            if ($jsonObj.tracks.Count -eq 0) {
                Write-Host "ERROR: Copilot returned zero tracks. Skipping album."
                "ERROR: Copilot returned zero tracks. Skipping album." | Add-Content -LiteralPath $logFile -Encoding utf8
                continue
            }

            Write-Utf8NoBom -Path $output -Content $json

            Write-Host "Clean album JSON created: $output"
            "Clean album JSON created: $output" | Add-Content -LiteralPath $logFile -Encoding utf8
        }
        catch {
            Write-Host "ERROR: Extracted album JSON is invalid."
            "ERROR: Extracted album JSON is invalid." | Add-Content -LiteralPath $logFile -Encoding utf8
            "JSON parse error: $_" | Add-Content -LiteralPath $logFile -Encoding utf8
            continue
        }

        # ====================================================
        # Step 4: Write metadata back to FLAC
        # ====================================================

        Write-Host "Step 4: Writing album metadata back to FLAC..."
        "Step 4: Writing album metadata back to FLAC..." | Add-Content -LiteralPath $logFile -Encoding utf8

        # album_profile.json priority:
        # 1. album folder\album_profile.json
        # 2. script root\album_profile.json
        $albumProfile = $null

        $albumProfileLocal = Join-Path $albumPath "album_profile.json"
        $albumProfileRoot  = Join-Path $scriptDir "album_profile.json"

        if (Test-Path -LiteralPath $albumProfileLocal) {
            $albumProfile = $albumProfileLocal
        }
        elseif (Test-Path -LiteralPath $albumProfileRoot) {
            $albumProfile = $albumProfileRoot
        }

        if ($albumProfile) {
            Write-Host "Using album profile: $albumProfile"
            "Using album profile: $albumProfile" | Add-Content -LiteralPath $logFile -Encoding utf8

            $writeResult = & python $writeAlbumPy "$output" "$albumProfile" 2>&1
        }
        else {
            Write-Host "No album_profile.json found. Writing AI output directly."
            "No album_profile.json found. Writing AI output directly." | Add-Content -LiteralPath $logFile -Encoding utf8

            $writeResult = & python $writeAlbumPy "$output" 2>&1
        }

        $writeText = ($writeResult | ForEach-Object { $_.ToString() }) -join "`n"

        Write-Host $writeText
        $writeText | Add-Content -LiteralPath $logFile -Encoding utf8

        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: write_album.py failed."
            "ERROR: write_album.py failed." | Add-Content -LiteralPath $logFile -Encoding utf8
            continue
        }

        # ====================================================
        # Step 5: ReplayGain album scan
        # ====================================================

        Invoke-AlbumReplayGain -AlbumPath $albumPath -LogFile $logFile

        Write-Host "Album done."
        "Album done." | Add-Content -LiteralPath $logFile -Encoding utf8
    }
    catch {
        Write-Host "ERROR: $_"
        "ERROR: $_" | Add-Content -LiteralPath $logFile -Encoding utf8
        continue
    }
}


# ============================================================
# Finish
# ============================================================

Write-Host "======================"
Write-Host "All albums processed."
Write-Host "Please check:"
Write-Host $debugDir

"=== Album run finished: $(Get-Date) ===" | Add-Content -LiteralPath $logFile -Encoding utf8