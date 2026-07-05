$ErrorActionPreference = "Stop"
$verify = Join-Path (Split-Path -Parent $PSScriptRoot) "claude-verify.ps1"
$root = Join-Path ([IO.Path]::GetTempPath()) ("claude verify 日本語 " + [Guid]::NewGuid())
$repo = Join-Path $root "repo"
$snap = Join-Path $root "snapshot.json"

function Run-Verify([string[]]$VerifyArgs, [int]$Expected) {
    $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verify @VerifyArgs 2>&1
    if ($LASTEXITCODE -ne $Expected) { throw "expected $Expected, got $LASTEXITCODE`n$($out -join "`n")" }
    return ($out -join "`n")
}

try {
    New-Item -ItemType Directory -Path $repo | Out-Null
    & git -C $repo init -q
    & git -C $repo config user.email test@example.invalid
    & git -C $repo config user.name Test
    Set-Content -LiteralPath (Join-Path $repo "normal.txt") -Value "base" -Encoding UTF8
    & git -C $repo add normal.txt
    & git -C $repo commit -qm initial

    $out = Run-Verify -VerifyArgs @("snapshot", "-Repo", $repo, "-Snapshot", $snap) -Expected 0
    if ($out -notmatch "\[CLAUDE_VERIFY_OK\]") { throw "snapshot sentinel missing" }
    $out = Run-Verify -VerifyArgs @("check", "-Repo", $repo, "-Snapshot", $snap) -Expected 0
    if ($out -notmatch "\[CLAUDE_VERIFY_OK\]") { throw "check sentinel missing" }

    Set-Content -LiteralPath (Join-Path $repo "normal.txt") -Value "changed" -Encoding UTF8
    $out = Run-Verify -VerifyArgs @("check", "-Repo", $repo, "-Snapshot", $snap) -Expected 0
    if ($out -notmatch "\[CLAUDE_VERIFY_OK\].*status") { throw "status comparison missing" }

    Set-Content -LiteralPath (Join-Path $repo ".env") -Value "secret" -Encoding UTF8
    $out = Run-Verify -VerifyArgs @("check", "-Repo", $repo, "-Snapshot", $snap) -Expected 1
    if ($out -notmatch "\[CLAUDE_VERIFY_VIOLATION\].*\.env") { throw "protected violation missing" }
    $out = Run-Verify -VerifyArgs @("check", "-Repo", $repo, "-Snapshot", $snap, "-Allow", ".env") -Expected 0
    if ($out -notmatch "\[CLAUDE_VERIFY_ALLOWED\].*\.env") { throw "allow sentinel missing" }
    $out = Run-Verify -VerifyArgs @("check", "-Repo", $repo, "-Snapshot", $snap, "-Allow", "../.env") -Expected 2
    if ($out -notmatch "\[CLAUDE_VERIFY_ERROR\]") { throw "invalid allow error missing" }

    & git -C $repo add normal.txt
    & git -C $repo commit -qm changed
    $out = Run-Verify -VerifyArgs @("check", "-Repo", $repo, "-Snapshot", $snap, "-Allow", ".env") -Expected 1
    if ($out -notmatch "\[CLAUDE_VERIFY_VIOLATION\].*HEAD") { throw "HEAD violation missing" }
    Write-Output "test-verify.ps1: OK"
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
