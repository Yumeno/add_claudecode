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

Write-Host "Passed: $passed; Failed: $failed"
Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
if ($failed -gt 0) { exit 1 }
