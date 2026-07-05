# claude-implement.ps1 - Run Claude Code with narrowly scoped file-edit tools.
param(
    [Parameter(Mandatory=$true)][string]$SpecFile,
    [Parameter(Mandatory=$true)][string]$Repo,
    [string]$Model = "",
    [int]$Timeout = 600,
    [decimal]$MaxBudgetUsd = 1.00
)

[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding
$Sentinel = "[CLAUDE_IMPLEMENT_ERROR]"

function Fail {
    param([int]$Code, [string]$Message)
    Write-Output "$Sentinel $Message"
    [Console]::Error.WriteLine("Error: $Message")
    exit $Code
}

if (-not (Test-Path -LiteralPath $SpecFile -PathType Leaf)) { Fail 1 "Spec file not found: $SpecFile" }
if (-not (Test-Path -LiteralPath $Repo -PathType Container)) { Fail 1 "Repository not found: $Repo" }
if ($Timeout -le 0 -or $MaxBudgetUsd -le 0) { Fail 1 "Timeout and budget must be greater than zero." }
if ($Model -and $Model -notmatch '^[A-Za-z0-9._:/-]+$') { Fail 1 "Model name contains unsafe characters." }

try {
    & git -C $Repo rev-parse --is-inside-work-tree *> $null
    if ($LASTEXITCODE -ne 0) { Fail 1 "Target is not a Git working tree: $Repo" }
    $dirty = & git -C $Repo status --porcelain=v1 --untracked-files=all
    if ($LASTEXITCODE -ne 0) { Fail 1 "Could not read Git status." }
    if ($dirty) { Fail 1 "Working tree is not clean. Commit or stash changes before delegation." }
    $claudeExe = (Get-Command claude -ErrorAction Stop).Source
} catch {
    Fail 1 $_.Exception.Message
}

$verify = Join-Path $PSScriptRoot "claude-verify.ps1"
$snapshot = Join-Path $env:TEMP ("claude-verify-" + [guid]::NewGuid().ToString("N") + ".json")
if (-not (Test-Path -LiteralPath $verify -PathType Leaf)) { Fail 1 "Verification helper not found: $verify" }
& powershell -ExecutionPolicy Bypass -NoProfile -File $verify snapshot -Repo $Repo -Snapshot $snapshot
if ($LASTEXITCODE -ne 0) { Fail 1 "Could not create pre-execution snapshot." }

$spec = Get-Content -LiteralPath $SpecFile -Raw -Encoding UTF8
$fixedSafety = @"
# Mandatory safety constraints

- Modify only files inside the target repository.
- Never modify `.git/`, Git configuration, hooks, refs, branches, tags, submodules, credentials, keys, or `.env` files.
- Do not run git add, commit, checkout, switch, reset, clean, config, branch, tag, worktree, or submodule commands.
- Do not use network tools or spawn subagents.
- Do not make unrelated changes.
- At the end, list every created, modified, or deleted file and report tests run.
- If the task conflicts with these constraints, stop and report the conflict.

---

$spec
"@

function Quote-Arg {
    param([string]$Value)
    if ($Value -notmatch '[\s"]' -and $Value -ne "") { return $Value }
    return '"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

$argsList = @(
    "-p", "--output-format", "text", "--safe-mode",
    "--tools", "Read,Edit,Write,Glob,Grep",
    "--permission-mode", "dontAsk",
    "--disallowedTools", "Bash,WebFetch,WebSearch,Task",
    "--no-session-persistence",
    "--max-budget-usd", ([string]::Format([Globalization.CultureInfo]::InvariantCulture, "{0}", $MaxBudgetUsd))
)
if ($Model) { $argsList += @("--model", $Model) }
$argString = ($argsList | ForEach-Object { Quote-Arg $_ }) -join " "

try {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $claudeExe
    $info.Arguments = $argString
    $info.WorkingDirectory = (Resolve-Path -LiteralPath $Repo).Path
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($info)
    $writer = New-Object IO.StreamWriter($process.StandardInput.BaseStream, (New-Object Text.UTF8Encoding($false)))
    $writer.Write($fixedSafety)
    $writer.Close()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $timedOut = -not $process.WaitForExit($Timeout * 1000)
    if ($timedOut) {
        & taskkill /T /F /PID $process.Id 2>$null | Out-Null
        $process.WaitForExit()
    }
    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    $claudeExit = $process.ExitCode
    & powershell -ExecutionPolicy Bypass -NoProfile -File $verify check -Repo $Repo -Snapshot $snapshot
    $verifyExit = $LASTEXITCODE
    Remove-Item -LiteralPath $snapshot -Force -ErrorAction SilentlyContinue
    if ($verifyExit -ne 0) { Fail $verifyExit "Post-execution verification failed." }
    if ($timedOut) { Fail 2 "Claude Code timed out after ${Timeout}s" }
    if ($claudeExit -ne 0) { Fail $claudeExit "Claude Code exited ${claudeExit}: $($stderr.Trim())" }
    if ([string]::IsNullOrWhiteSpace($stdout)) { Fail 1 "Claude Code returned empty output." }
    Write-Output $stdout.TrimEnd()
} catch {
    Remove-Item -LiteralPath $snapshot -Force -ErrorAction SilentlyContinue
    Fail 1 $_.Exception.Message
}
