$ErrorActionPreference = "Stop"
$ErrorActionPreference = "Continue"
$Script = Join-Path (Split-Path $PSScriptRoot -Parent) "claude-implement.ps1"
$Root = Join-Path ([IO.Path]::GetTempPath()) ("claude_impl_test_" + [guid]::NewGuid().ToString("N"))
$Repo = Join-Path $Root "repo"
$Spec = Join-Path $Root "spec.txt"
$oldPath = $env:PATH

try {
    New-Item -ItemType Directory -Path $Repo -Force | Out-Null
    Set-Content -LiteralPath $Spec -Value "READMEを作成する" -Encoding UTF8
    & git -C $Repo init -q
    & git -C $Repo config user.email "test@example.invalid"
    & git -C $Repo config user.name "Test"
    Set-Content -LiteralPath (Join-Path $Repo "base.txt") -Value "base" -Encoding UTF8
    & git -C $Repo add base.txt
    & git -C $Repo commit -qm "base"

    $env:PATH = "$PSScriptRoot;$oldPath"
    $env:FAKE_ARGS = Join-Path $Root "args.txt"
    $env:FAKE_STDIN = Join-Path $Root "stdin.txt"
    $env:FAKE_CWD = Join-Path $Root "cwd.txt"
    $env:FAKE_MODE = "success"

    $output = & powershell -ExecutionPolicy Bypass -NoProfile -File $Script -SpecFile $Spec -Repo $Repo 2>&1
    if ($LASTEXITCODE -ne 0 -or ($output | Out-String) -notmatch "fake response") { throw ($output | Out-String) }
    $argsSeen = Get-Content -LiteralPath $env:FAKE_ARGS -Encoding UTF8
    foreach ($required in @("--safe-mode", "--tools", "Read,Edit,Write,Glob,Grep", "--permission-mode", "dontAsk", "--disallowedTools")) {
        if ($argsSeen -notcontains $required) { throw "missing argv: $required" }
    }
    $stdin = Get-Content -LiteralPath $env:FAKE_STDIN -Raw -Encoding UTF8
    if ($stdin -notmatch "Mandatory safety constraints" -or $stdin -notmatch "README") { throw "safety/spec stdin mismatch" }

    Set-Content -LiteralPath (Join-Path $Repo "dirty.txt") -Value "dirty" -Encoding UTF8
    $output = & powershell -ExecutionPolicy Bypass -NoProfile -File $Script -SpecFile $Spec -Repo $Repo 2>&1
    if ($LASTEXITCODE -eq 0 -or ($output | Out-String) -notmatch "not clean") { throw "dirty tree was accepted" }
    Write-Host "test-implement.ps1: OK"
} finally {
    $env:PATH = $oldPath
    Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
}
