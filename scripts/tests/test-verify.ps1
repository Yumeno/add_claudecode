$ErrorActionPreference = "Stop"
$verify = Join-Path (Split-Path -Parent $PSScriptRoot) "claude-verify.ps1"
$root = Join-Path ([IO.Path]::GetTempPath()) ("claude verify 日本語 " + [Guid]::NewGuid())
$repo = Join-Path $root "repo"
$snap = Join-Path $root "snapshot.json"
$hookSnap = Join-Path $root "hook-snapshot.json"
$externalSnap = Join-Path $root "external-snapshot.json"
$submoduleSnap = Join-Path $root "submodule-snapshot.json"

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

    $hook = Join-Path $repo ".git\hooks\test-hook"
    $hookCreated = $false
    try {
        New-Item -ItemType SymbolicLink -Path $hook -Target (Join-Path $repo "normal.txt") -ErrorAction Stop | Out-Null
        $hookCreated = $true
        [void](Run-Verify -VerifyArgs @("snapshot", "-Repo", $repo, "-Snapshot", $hookSnap) -Expected 0)
        Remove-Item -LiteralPath $hook -Force
        $out = Run-Verify -VerifyArgs @("check", "-Repo", $repo, "-Snapshot", $hookSnap) -Expected 1
        if ($out -notmatch "\[CLAUDE_VERIFY_VIOLATION\].*\.git/hooks/test-hook") { throw "symlink hook violation missing" }
    } catch {
        if ($hookCreated) { throw }
        Write-Output "SKIP: symlink hook test ($($_.Exception.Message))"
    } finally {
        Remove-Item -LiteralPath $hook -Force -ErrorAction SilentlyContinue
    }

    $outside = Join-Path $root "outside.txt"
    Set-Content -LiteralPath $outside -Value "outside" -Encoding UTF8
    $externalLink = Join-Path $repo "external-link"
    $externalLinkCreated = $false
    try {
        New-Item -ItemType SymbolicLink -Path $externalLink -Target $outside -ErrorAction Stop | Out-Null
        $externalLinkCreated = $true
        $out = Run-Verify -VerifyArgs @("snapshot", "-Repo", $repo, "-Snapshot", $externalSnap) -Expected 2
        if ($out -notmatch "\[CLAUDE_VERIFY_ERROR\] symlink escapes repository: external-link ->") { throw "escaping symlink error missing" }
    } catch {
        if ($externalLinkCreated) { throw }
        Write-Output "SKIP: escaping symlink test ($($_.Exception.Message))"
    } finally {
        Remove-Item -LiteralPath $externalLink -Force -ErrorAction SilentlyContinue
    }

    Set-Content -LiteralPath (Join-Path $repo ".gitmodules") -Value "[submodule `"sample`"]`n`tpath = sample`n`turl = local" -Encoding UTF8
    $out = Run-Verify -VerifyArgs @("snapshot", "-Repo", $repo, "-Snapshot", $submoduleSnap) -Expected 2
    if ($out -notmatch "\[CLAUDE_VERIFY_ERROR\] repository contains submodules; not supported by claude-verify") { throw "submodule rejection missing" }

    Remove-Item -LiteralPath (Join-Path $repo ".gitmodules") -Force
    $repoFile = Join-Path $root "repo-file.txt"
    [IO.File]::WriteAllText($repoFile, $repo, (New-Object Text.UTF8Encoding($false)))
    $repoFileSnap = Join-Path $root "repofile-snapshot.json"
    $out = Run-Verify -VerifyArgs @("snapshot", "-RepoFile", $repoFile, "-Snapshot", $repoFileSnap) -Expected 0
    if ($out -notmatch "\[CLAUDE_VERIFY_OK\] snapshot created") { throw "RepoFile snapshot failed on Japanese repo path" }
    $out = Run-Verify -VerifyArgs @("snapshot", "-Repo", $repo, "-RepoFile", $repoFile, "-Snapshot", $repoFileSnap) -Expected 2
    if ($out -notmatch "mutually exclusive") { throw "RepoFile + Repo conflict not caught" }
    $out = Run-Verify -VerifyArgs @("snapshot", "-Snapshot", $repoFileSnap) -Expected 2
    if ($out -notmatch "Either -Repo or -RepoFile is required") { throw "missing Repo/RepoFile not caught" }
    $missingFile = Join-Path $root "does-not-exist.txt"
    $out = Run-Verify -VerifyArgs @("snapshot", "-RepoFile", $missingFile, "-Snapshot", $repoFileSnap) -Expected 2
    if ($out -notmatch "RepoFile not found") { throw "missing RepoFile not caught" }
    $emptyFile = Join-Path $root "empty.txt"
    Set-Content -LiteralPath $emptyFile -Value "" -NoNewline
    $out = Run-Verify -VerifyArgs @("snapshot", "-RepoFile", $emptyFile, "-Snapshot", $repoFileSnap) -Expected 2
    if ($out -notmatch "empty") { throw "empty RepoFile not caught" }
    Write-Output "test-verify.ps1: OK"
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
