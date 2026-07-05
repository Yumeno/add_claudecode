param()
$ErrorActionPreference = "Stop"
$ErrorActionPreference = "Continue"
$collector = Resolve-Path "$PSScriptRoot\..\..\.agents\skills\ask-claude-with-context\scripts\collect-context.ps1"
$tmp = Join-Path $env:TEMP ("claude context test {0}.txt" -f ([guid]::NewGuid()))
try {
    [IO.File]::WriteAllText($tmp, "space path content", (New-Object Text.UTF8Encoding($false)))
    $result = & powershell -NoProfile -ExecutionPolicy Bypass -File $collector -Mode none -Path $tmp
    if ($LASTEXITCODE -ne 0) { throw "collector failed: $LASTEXITCODE" }
    if (($result -join "`n") -notmatch "space path content") { throw "space-containing path was not collected" }

    & powershell -NoProfile -ExecutionPolicy Bypass -File $collector -Mode none 2>$null | Out-Null
    if ($LASTEXITCODE -ne 3) { throw "empty selection must exit 3, got $LASTEXITCODE" }
    Write-Output "PASS: context collector (PowerShell)"
} finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}
