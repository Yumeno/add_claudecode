$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$skillsRoot = Join-Path $root ".agents\skills"

$required = @{
    "ask-claude" = @("claude-wrapper.ps1", "claude-wrapper.sh")
    "ask-claude-with-context" = @("claude-wrapper.ps1", "claude-wrapper.sh", "collect-context.ps1", "collect-context.sh")
    "set-claude-model" = @("claude-wrapper.ps1", "claude-wrapper.sh")
    "list-claude-models" = @("claude-wrapper.ps1", "claude-wrapper.sh")
    "claude-implement" = @("claude-implement.ps1", "claude-implement.sh", "claude-verify.ps1", "claude-verify.sh")
}

foreach ($skill in $required.Keys) {
    foreach ($file in $required[$skill]) {
        $path = Join-Path $skillsRoot "$skill\scripts\$file"
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "missing bundled helper: $skill/scripts/$file" }
        if ($file -like "claude-*") {
            $source = Join-Path $root "scripts\$file"
            $a = [IO.File]::ReadAllBytes($source)
            $b = [IO.File]::ReadAllBytes($path)
            if ($a.Length -ne $b.Length) { throw "helper size mismatch: $skill/scripts/$file" }
            for ($i = 0; $i -lt $a.Length; $i++) {
                if ($a[$i] -ne $b[$i]) { throw "helper content mismatch: $skill/scripts/$file" }
            }
        }
    }
}

Write-Output "PASS: Skill bundled helpers"
