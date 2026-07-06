$ErrorActionPreference = "Stop"
$ErrorActionPreference = "Continue"
$Wrapper = Join-Path (Split-Path $PSScriptRoot -Parent) "claude-wrapper.ps1"
$passed = 0
$failed = 0
$TempRoot = Join-Path ([IO.Path]::GetTempPath()) ("claude_wrapper_test_" + [guid]::NewGuid().ToString("N"))
$WorkDir = Join-Path $TempRoot "work dir"
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
$env:PATH = "$PSScriptRoot;$env:PATH"
$env:FAKE_ARGS = Join-Path $TempRoot "args.txt"
$env:FAKE_STDIN = Join-Path $TempRoot "stdin.txt"
$env:FAKE_CWD = Join-Path $TempRoot "cwd.txt"

function Test-Case {
    param([string]$Name, [scriptblock]$Body)
    try { & $Body; $script:passed++; Write-Host "PASS $Name" }
    catch { $script:failed++; Write-Host "FAIL $Name -- $_" }
}

function Invoke-Wrapper {
    param([string[]]$Arguments)
    $output = & powershell -ExecutionPolicy Bypass -NoProfile -File $Wrapper @Arguments 2>&1
    return @{ Code = $LASTEXITCODE; Output = ($output | Out-String) }
}

Test-Case "missing prompt emits sentinel" {
    $r = Invoke-Wrapper @()
    if ($r.Code -eq 0 -or $r.Output -notmatch '\[CLAUDE_WRAPPER_ERROR\]') { throw $r.Output }
}

Test-Case "unsafe model emits sentinel" {
    $r = Invoke-Wrapper @("-Prompt", "x", "-Model", "bad`nname")
    if ($r.Code -eq 0 -or $r.Output -notmatch '\[CLAUDE_WRAPPER_ERROR\]') { throw $r.Output }
}

Test-Case "missing context file emits sentinel" {
    $r = Invoke-Wrapper @("-Prompt", "x", "-ContextFile", "Z:\missing.txt")
    if ($r.Code -eq 0 -or $r.Output -notmatch 'Context file not found') { throw $r.Output }
}

Test-Case "CLI model overrides environment model" {
    $env:CLAUDE_WRAPPER_MODEL = "env-model"
    $r = Invoke-Wrapper @("-ShowModel", "-Model", "cli-model")
    Remove-Item Env:CLAUDE_WRAPPER_MODEL -ErrorAction SilentlyContinue
    if ($r.Code -ne 0 -or $r.Output -notmatch "model=cli-model \(source: cli\)") { throw $r.Output }
}

Test-Case "success preserves stdin argv and cwd" {
    $env:FAKE_MODE = "success"
    $r = Invoke-Wrapper @("-Prompt", "request text", "-Context", "context text", "-WorkDir", $WorkDir, "-Model", "claude-test")
    if ($r.Code -ne 0 -or $r.Output -notmatch "fake response") { throw $r.Output }
    $stdin = Get-Content -LiteralPath $env:FAKE_STDIN -Raw -Encoding UTF8
    if ($stdin -ne "## Context`n`ncontext text`n`n---`n`n## Request`n`nrequest text") { throw "stdin mismatch" }
    $arguments = Get-Content -LiteralPath $env:FAKE_ARGS -Encoding UTF8
    if ($arguments -notcontains "--tools" -or $arguments -notcontains "claude-test") { throw "argv mismatch: $arguments" }
    if ((Get-Content -LiteralPath $env:FAKE_CWD -Raw -Encoding UTF8) -ne $WorkDir) { throw "cwd mismatch" }
}

Test-Case "ordered media are staged by magic bytes and cleaned" {
    $png = Join-Path $TempRoot "first image.bin"
    $pdf = Join-Path $TempRoot "second document.dat"
    [IO.File]::WriteAllBytes($png, [byte[]](0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a))
    [IO.File]::WriteAllBytes($pdf, [Text.Encoding]::ASCII.GetBytes("%PDF-1.4`n"))
    $list = Join-Path $TempRoot "attachments.txt"
    [IO.File]::WriteAllLines($list, [string[]]@($png, $pdf), (New-Object Text.UTF8Encoding($false)))
    $env:FAKE_MODE = "success"
    $r = Invoke-Wrapper @("-Prompt", "inspect", "-AttachmentList", $list)
    if ($r.Code -ne 0) { throw $r.Output }
    $stdin = Get-Content -LiteralPath $env:FAKE_STDIN -Raw -Encoding UTF8
    if ($stdin -notmatch '1\..*mime=image/png.*support=probe-verified') { throw $stdin }
    if ($stdin -notmatch '2\..*mime=application/pdf.*support=experimental') { throw $stdin }
    $arguments = Get-Content -LiteralPath $env:FAKE_ARGS -Encoding UTF8
    $addDirIndex = [Array]::IndexOf([object[]]$arguments, "--add-dir")
    if ($arguments -notcontains "Read" -or $addDirIndex -lt 0) { throw "media argv mismatch: $arguments" }
    if (Test-Path -LiteralPath $arguments[$addDirIndex + 1]) { throw "media staging directory leaked" }
}

Test-Case "media rejects explicit workdir" {
    $png = Join-Path $TempRoot "isolated.png"
    [IO.File]::WriteAllBytes($png, [byte[]](0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a))
    $r = Invoke-Wrapper @("-Prompt", "inspect", "-WorkDir", $WorkDir, "-Attachment", $png)
    if ($r.Code -eq 0 -or $r.Output -notmatch "cannot be combined") { throw $r.Output }
}

Test-Case "unsupported media is rejected and staging is cleaned" {
    $mediaTemp = Join-Path $TempRoot "media-temp"
    New-Item -ItemType Directory -Path $mediaTemp | Out-Null
    $bad = Join-Path $TempRoot "audio.wav"
    [IO.File]::WriteAllBytes($bad, [Text.Encoding]::ASCII.GetBytes("RIFFxxxxWAVE"))
    $oldTemp = $env:TEMP
    try {
        $env:TEMP = $mediaTemp
        $r = Invoke-Wrapper @("-Prompt", "inspect", "-Attachment", $bad)
    } finally { $env:TEMP = $oldTemp }
    if ($r.Code -eq 0 -or $r.Output -notmatch "Unsupported media format for Claude Code Read") { throw $r.Output }
    if (Get-ChildItem -LiteralPath $mediaTemp -Force) { throw "temporary media directory leaked" }
}

Test-Case "child exit code and stderr are preserved" {
    $env:FAKE_MODE = "fail"
    $r = Invoke-Wrapper @("-Prompt", "x")
    if ($r.Code -ne 7 -or $r.Output -notmatch "fake failure") { throw "code=$($r.Code) $($r.Output)" }
}

Test-Case "empty output is rejected" {
    $env:FAKE_MODE = "empty"
    $r = Invoke-Wrapper @("-Prompt", "x")
    if ($r.Code -eq 0 -or $r.Output -notmatch "empty output") { throw $r.Output }
}

Test-Case "timeout uses wrapper exit code 2" {
    $env:FAKE_MODE = "sleep"
    $r = Invoke-Wrapper @("-Prompt", "x", "-Timeout", "1")
    if ($r.Code -ne 2 -or $r.Output -notmatch "timed out") { throw "code=$($r.Code) $($r.Output)" }
}

Test-Case "PowerShell source is UTF-8 BOM" {
    $bytes = [IO.File]::ReadAllBytes($Wrapper)
    if ($bytes.Length -lt 3 -or $bytes[0] -ne 0xEF -or $bytes[1] -ne 0xBB -or $bytes[2] -ne 0xBF) {
        throw "UTF-8 BOM is missing"
    }
}

Test-Case "PromptFile reads UTF-8 content and forwards to stdin" {
    $env:FAKE_MODE = "success"
    $promptFile = Join-Path $TempRoot "prompt.txt"
    [IO.File]::WriteAllText($promptFile, "テスト_質問", (New-Object Text.UTF8Encoding($false)))
    $r = Invoke-Wrapper @("-PromptFile", $promptFile, "-WorkDir", $WorkDir)
    if ($r.Code -ne 0) { throw $r.Output }
    $stdin = Get-Content -LiteralPath $env:FAKE_STDIN -Raw -Encoding UTF8
    if ($stdin -ne "テスト_質問") { throw "stdin mismatch: [$stdin]" }
}

Test-Case "Prompt and PromptFile are mutually exclusive" {
    $promptFile = Join-Path $TempRoot "prompt2.txt"
    [IO.File]::WriteAllText($promptFile, "x", (New-Object Text.UTF8Encoding($false)))
    $r = Invoke-Wrapper @("-Prompt", "y", "-PromptFile", $promptFile)
    if ($r.Code -eq 0 -or $r.Output -notmatch "mutually exclusive") { throw $r.Output }
}

Test-Case "Missing PromptFile is rejected" {
    $r = Invoke-Wrapper @("-PromptFile", (Join-Path $TempRoot "missing.txt"))
    if ($r.Code -eq 0 -or $r.Output -notmatch "Prompt file not found") { throw $r.Output }
}

Write-Host "Passed: $passed; Failed: $failed"
Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
if ($failed -gt 0) { exit 1 }
