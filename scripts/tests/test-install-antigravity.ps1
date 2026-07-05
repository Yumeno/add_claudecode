$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$target = Join-Path ([IO.Path]::GetTempPath()) ("claude-agy-" + [guid]::NewGuid().ToString("N"))
try {
    New-Item -ItemType Directory -Force -Path (Join-Path $target "skills\unrelated"), (Join-Path $target "skills\ask-claude") | Out-Null
    Set-Content -LiteralPath (Join-Path $target "skills\ask-claude\stale") -Value stale
    & (Join-Path $root "scripts\install-for-antigravity.ps1") `
        -DestinationRoot $target -ScriptsRoot (Join-Path $target "scripts") | Out-Null
    foreach ($source in Get-ChildItem -LiteralPath (Join-Path $root ".agents\skills") -Directory) {
        if (-not (Test-Path -LiteralPath (Join-Path $target ("skills\" + $source.Name + "\SKILL.md")))) { throw "missing $($source.Name)" }
    }
    if (Test-Path -LiteralPath (Join-Path $target "skills\ask-claude\stale")) { throw "stale file remained" }
    if (-not (Test-Path -LiteralPath (Join-Path $target "skills\unrelated"))) { throw "unrelated skill removed" }
    if (-not (Test-Path -LiteralPath (Join-Path $target "scripts\claude-wrapper.ps1"))) { throw "scripts missing" }
    Write-Output "PASS: Antigravity CLI installer"
} finally {
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
}
