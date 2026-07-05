[CmdletBinding()]
param(
    [string]$DestinationRoot = (Join-Path $env:USERPROFILE ".gemini\antigravity-cli"),
    [string]$ScriptsRoot = ""
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$sourceSkills = Join-Path $root ".agents\skills"
$destinationSkills = Join-Path $DestinationRoot "skills"
$destinationScripts = if ($ScriptsRoot) { $ScriptsRoot } else {
    Join-Path (Split-Path -Parent $DestinationRoot) "scripts"
}
New-Item -ItemType Directory -Force -Path $destinationSkills, $destinationScripts | Out-Null
$stage = Join-Path $DestinationRoot (".add-claudecode-stage-" + [guid]::NewGuid().ToString("N"))
try {
    $stageSkills = Join-Path $stage "skills"
    $stageScripts = Join-Path $stage "scripts"
    New-Item -ItemType Directory -Force -Path $stageSkills, $stageScripts | Out-Null
    foreach ($source in Get-ChildItem -LiteralPath $sourceSkills -Directory) {
        Copy-Item -LiteralPath $source.FullName -Destination (Join-Path $stageSkills $source.Name) -Recurse -Force
    }
    Get-ChildItem -LiteralPath (Join-Path $root "scripts") -File -Filter "claude-*" |
        Where-Object Extension -in @(".ps1", ".sh") |
        Copy-Item -Destination $stageScripts -Force

    Get-ChildItem -LiteralPath $stageScripts -File | Copy-Item -Destination $destinationScripts -Force
    foreach ($source in Get-ChildItem -LiteralPath $stageSkills -Directory) {
        $destination = Join-Path $destinationSkills $source.Name
        if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Recurse -Force }
        Move-Item -LiteralPath $source.FullName -Destination $destination
    }
} finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
Write-Output "Antigravity CLI用Skillをインストールしました: $DestinationRoot"
