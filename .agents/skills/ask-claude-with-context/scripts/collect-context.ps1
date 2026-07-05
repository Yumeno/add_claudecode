# collect-context.ps1 — Emit context (git diff / log / files) to stdout
# Usage: powershell -File collect-context.ps1 "<user arguments>"
#
# Recognizes (case-insensitive):
#   review | レビュー | diff       → git diff + git diff --staged
#   security | セキュリティ | 監査 | audit → git diff + changed files
#   log | 履歴 | history            → git log --oneline -20
# Tokens that resolve to existing files → that file's contents

param(
    [Parameter(Position=0)]
    [string]$ArgString = "",
    [ValidateSet("auto", "review", "security", "log", "none")]
    [string]$Mode = "auto",
    [string[]]$Path = @()
)

function Emit-Section {
    param([string]$Title, [scriptblock]$Cmd)
    Write-Output ""
    Write-Output "### $Title"
    Write-Output ""
    Write-Output '```'
    try {
        & $Cmd 2>&1 | Out-String -Stream
    } catch {
        Write-Output "(error: $_)"
    }
    Write-Output '```'
}

function Emit-File {
    param([string]$Path)
    Write-Output ""
    Write-Output "### File: $Path"
    Write-Output ""
    Write-Output '```'
    try {
        Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    } catch {
        Write-Output "(error: $_)"
    }
    Write-Output '```'
}

# Whole-word match for English keywords (avoid catching "catalog" → "log",
# "different" → "diff"). Japanese keywords use simple substring match because
# CJK has no word-boundary concept.
$didAny = $false
$didDiff = $false

$wantReview = $Mode -eq "review" -or ($Mode -eq "auto" -and ($ArgString -imatch '\b(review|diff)\b' -or $ArgString -match 'レビュー'))
$wantSecurity = $Mode -eq "security" -or ($Mode -eq "auto" -and ($ArgString -imatch '\b(security|audit)\b' -or $ArgString -match 'セキュリティ|監査'))
$wantLog = $Mode -eq "log" -or ($Mode -eq "auto" -and ($ArgString -imatch '\b(log|history)\b' -or $ArgString -match '履歴'))

if ($wantReview) {
    Emit-Section "git diff (working tree)" { git diff }
    Emit-Section "git diff --staged" { git diff --staged }
    $didAny = $true
    $didDiff = $true
}

if ($wantSecurity) {
    if (-not $didDiff) {
        Emit-Section "git diff (working tree)" { git diff }
        Emit-Section "git diff --staged" { git diff --staged }
        $didDiff = $true
    }
    Emit-Section "Changed files (working tree)" { git diff --name-only }
    Emit-Section "Changed files (staged)" { git diff --staged --name-only }
    Emit-Section "Untracked files" { git ls-files --others --exclude-standard }
    $didAny = $true
}

if ($wantLog) {
    Emit-Section "git log --oneline -20" { git log --oneline -20 }
    $didAny = $true
}

# Explicit paths are the reliable interface and support spaces.
foreach ($filePath in $Path) {
    if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
        [Console]::Error.WriteLine("(file not found: $filePath)")
        exit 1
    }
    Emit-File $filePath
    $didAny = $true
}

# Keep best-effort token detection for backward compatibility.
if ($Mode -eq "auto") {
    foreach ($tok in ($ArgString -split '\s+')) {
        if ($tok -and (Test-Path -LiteralPath $tok -PathType Leaf)) {
            Emit-File $tok
            $didAny = $true
        }
    }
}

if (-not $didAny) {
    [Console]::Error.WriteLine("(no context selected; use -Mode or -Path)")
    exit 3
}

exit 0
