# claude-wrapper.ps1 - Claude Code CLI non-interactive wrapper (PowerShell 5.1+)
param(
    [string]$Prompt = "",
    [string]$Model = "",
    [int]$Timeout = 180,
    [decimal]$MaxBudgetUsd = 0.25,
    [string]$WorkDir = "",
    [string]$Cd = "",
    [string]$Context = "",
    [string]$ContextFile = "",
    [string]$SetModel = "",
    [switch]$ShowModel
)

[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding
$ErrorSentinel = "[CLAUDE_WRAPPER_ERROR]"
$ConfigFile = Join-Path $PSScriptRoot "claude-wrapper.conf"
$ModelNameRegex = '^[A-Za-z0-9._:/-]+$'
$MaxContextChars = 102400
$OwnedWorkDir = ""

function Fail {
    param([int]$Code, [string]$Message)
    if (-not [string]::IsNullOrWhiteSpace($script:OwnedWorkDir)) {
        Remove-Item -LiteralPath $script:OwnedWorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Output ("{0} {1}" -f $ErrorSentinel, $Message)
    [Console]::Error.WriteLine("Error: $Message")
    exit $Code
}

function Format-ChildError {
    param([string]$Value)
    $trimmed = $Value.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) { return "(no stderr output)" }
    return $trimmed
}

function Test-ModelName {
    param([string]$Value, [string]$Source)
    if ($Value -notmatch $ModelNameRegex) {
        Fail 1 ("model name from {0} contains unsafe characters: '{1}'" -f $Source, $Value)
    }
}

function Read-ConfigModel {
    if (-not (Test-Path -LiteralPath $ConfigFile -PathType Leaf)) { return "" }
    foreach ($line in (Get-Content -LiteralPath $ConfigFile -Encoding UTF8)) {
        $trimmed = $line.Trim()
        if ($trimmed -eq "" -or $trimmed.StartsWith("#")) { continue }
        if ($trimmed -match '^model\s*=\s*(.*?)\s*$') { return $matches[1] }
    }
    return ""
}

if (-not [string]::IsNullOrWhiteSpace($SetModel)) {
    Test-ModelName $SetModel "-SetModel"
    $content = "# claude-wrapper.conf`r`n# Model priority: CLI > CLAUDE_WRAPPER_MODEL > this file > Claude default`r`nmodel=$SetModel`r`n"
    [IO.File]::WriteAllText($ConfigFile, $content, (New-Object Text.UTF8Encoding($false)))
    Write-Output "Saved model='$SetModel' to $ConfigFile"
    exit 0
}

$ModelSource = ""
if (-not [string]::IsNullOrWhiteSpace($Model)) {
    Test-ModelName $Model "-Model"
    $ModelSource = "cli"
} elseif (-not [string]::IsNullOrWhiteSpace($env:CLAUDE_WRAPPER_MODEL)) {
    $Model = $env:CLAUDE_WRAPPER_MODEL
    Test-ModelName $Model '$env:CLAUDE_WRAPPER_MODEL'
    $ModelSource = "env"
} else {
    $Model = Read-ConfigModel
    if (-not [string]::IsNullOrWhiteSpace($Model)) {
        Test-ModelName $Model $ConfigFile
        $ModelSource = "config"
    }
}

if ($ShowModel) {
    if ([string]::IsNullOrWhiteSpace($Model)) {
        Write-Output "model=(unset; Claude Code default will be used)"
    } else {
        Write-Output "model=$Model (source: $ModelSource)"
    }
    Write-Output "config_file=$ConfigFile"
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Prompt)) { Fail 1 "-Prompt is required." }
if ($Timeout -le 0) { Fail 1 "-Timeout must be greater than zero." }
if ($MaxBudgetUsd -le 0) { Fail 1 "-MaxBudgetUsd must be greater than zero." }
if (-not [string]::IsNullOrWhiteSpace($Cd) -and -not [string]::IsNullOrWhiteSpace($WorkDir)) {
    Fail 1 "-Cd and -WorkDir are aliases; pass only one."
}
if (-not [string]::IsNullOrWhiteSpace($Cd)) { $WorkDir = $Cd }

if (-not [string]::IsNullOrWhiteSpace($ContextFile)) {
    if (-not (Test-Path -LiteralPath $ContextFile -PathType Leaf)) {
        Fail 1 "Context file not found: $ContextFile"
    }
    $Context = Get-Content -LiteralPath $ContextFile -Raw -Encoding UTF8
}
if ($Context.Length -gt $MaxContextChars) {
    [Console]::Error.WriteLine("Warning: Context is large (~$([math]::Floor($Context.Length / 1024))K chars).")
}

if ([string]::IsNullOrWhiteSpace($WorkDir)) {
    $WorkDir = Join-Path $env:TEMP ("claude-wrapper-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $WorkDir -ErrorAction Stop | Out-Null
    $OwnedWorkDir = $WorkDir
}
if (-not (Test-Path -LiteralPath $WorkDir -PathType Container)) {
    Fail 1 "workdir does not exist: $WorkDir"
}

$fullPrompt = if ([string]::IsNullOrWhiteSpace($Context)) {
    $Prompt
} else {
    "## Context`n`n$Context`n`n---`n`n## Request`n`n$Prompt"
}

try {
    $claudeExe = (Get-Command claude -ErrorAction Stop).Source
} catch {
    Fail 1 "'claude' CLI not found in PATH."
}

function Quote-Arg {
    param([string]$Value)
    if ($Value -notmatch '[\s"]' -and $Value -ne "") { return $Value }
    return '"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

$argsList = @(
    "-p",
    "--output-format", "text",
    "--safe-mode",
    "--tools", "",
    "--no-session-persistence",
    "--max-budget-usd", ([string]::Format([Globalization.CultureInfo]::InvariantCulture, "{0}", $MaxBudgetUsd))
)
if (-not [string]::IsNullOrWhiteSpace($Model)) {
    $argsList += @("--model", $Model)
    [Console]::Error.WriteLine("MODEL: $Model")
}
$argString = ($argsList | ForEach-Object { Quote-Arg $_ }) -join " "

$process = $null
try {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $claudeExe
    $info.Arguments = $argString
    $info.WorkingDirectory = $WorkDir
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($info)

    $writer = New-Object IO.StreamWriter($process.StandardInput.BaseStream, (New-Object Text.UTF8Encoding($false)))
    $writer.Write($fullPrompt)
    $writer.Close()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()

    if (-not $process.WaitForExit($Timeout * 1000)) {
        & taskkill /T /F /PID $process.Id 2>$null | Out-Null
        $process.WaitForExit()
        Fail 2 "Claude Code CLI timed out after ${Timeout}s"
    }
    $exitCode = $process.ExitCode
    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    if ($exitCode -ne 0) {
        Fail $exitCode ("Claude Code CLI exited with status {0}. {1}" -f $exitCode, (Format-ChildError $stderr))
    }
    if ([string]::IsNullOrWhiteSpace($stdout)) { Fail 1 "Claude Code CLI returned empty output." }

    Write-Output $stdout.TrimEnd()
    if (-not [string]::IsNullOrWhiteSpace($OwnedWorkDir)) {
        Remove-Item -LiteralPath $OwnedWorkDir -Recurse -Force -ErrorAction SilentlyContinue
        $OwnedWorkDir = ""
    }
} catch {
    if ($_.Exception.Message -like "$ErrorSentinel*") { throw }
    Fail 1 $_.Exception.Message
}

exit 0
