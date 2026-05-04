# claude-wrapper.ps1 - Invoke Claude Code CLI non-interactively
# Usage: powershell -ExecutionPolicy Bypass -File claude-wrapper.ps1 -Prompt "your question"
#
# Options:
#   -Prompt       (required) The prompt to send to Claude Code
#   -Model        (optional) Model name (e.g. claude-opus-4-7, claude-sonnet-4-6)
#   -Timeout      (optional) Timeout in seconds (default: 180)
#   -WorkDir      (optional) Working directory for claude (default: $env:TEMP)
#   -Context      (optional) Additional context to prepend to the prompt
#   -ContextFile  (optional) Path to a file containing context (avoids cmdline length limits)

param(
    [string]$Prompt = "",
    [string]$Model = "",
    [int]$Timeout = 180,
    [string]$WorkDir = "",
    [string]$Context = "",
    [string]$ContextFile = ""
)

# Approx. 100KB warning threshold (in characters; multibyte content will warn earlier)
$MaxContextChars = 102400

# --- Input validation ---
if ([string]::IsNullOrWhiteSpace($Prompt)) {
    [Console]::Error.WriteLine("Error: -Prompt is required.")
    exit 1
}

# --- Resolve claude executable. npm installs claude.ps1 + claude.cmd. ---
try {
    $claudeSource = (Get-Command claude -ErrorAction Stop).Source
} catch {
    [Console]::Error.WriteLine("Error: 'claude' CLI not found in PATH. Install: npm install -g @anthropic-ai/claude-code")
    exit 1
}
$claudeCmd = $claudeSource -replace '\.ps1$', '.cmd'
if (-not (Test-Path $claudeCmd)) {
    $claudeCmd = $claudeSource
}

# --- Load context from file if specified ---
if (-not [string]::IsNullOrWhiteSpace($ContextFile)) {
    if (-not (Test-Path $ContextFile)) {
        [Console]::Error.WriteLine("Error: Context file not found: $ContextFile")
        exit 1
    }
    $Context = Get-Content $ContextFile -Raw -Encoding UTF8
}

# --- Context size warning ---
if (-not [string]::IsNullOrWhiteSpace($Context)) {
    if ($Context.Length -gt $MaxContextChars) {
        $sizeK = [math]::Floor($Context.Length / 1024)
        [Console]::Error.WriteLine("Warning: Context is large (~${sizeK}K chars). May slow down the request.")
    }
}

# --- Determine working directory ---
if ([string]::IsNullOrWhiteSpace($WorkDir)) {
    $WorkDir = $env:TEMP
}
if (-not (Test-Path -LiteralPath $WorkDir -PathType Container)) {
    [Console]::Error.WriteLine("Error: -WorkDir does not exist: $WorkDir")
    exit 1
}

# --- Build the full prompt ---
if (-not [string]::IsNullOrWhiteSpace($Context)) {
    $fullPrompt = "$Context`n`n---`n`n$Prompt"
} else {
    $fullPrompt = $Prompt
}

# --- Build claude arguments. Prompt is piped via stdin, never as argv. ---
$claudeArgs = @("-p")
if (-not [string]::IsNullOrWhiteSpace($Model)) {
    $claudeArgs += @("--model", $Model)
}

$escapedArgs = ($claudeArgs | ForEach-Object {
    $escaped = $_ -replace '"', '\"'
    "`"$escaped`""
}) -join " "

# --- Execute claude. We launch claude.cmd through Process.Start with
#     UseShellExecute=false. cmd.exe still parses the .cmd batch file
#     internally, so this is NOT a strict guarantee against cmd parsing of
#     argv; we still mitigate risk by passing the prompt via stdin only. ---
try {
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $claudeCmd
    $pinfo.Arguments = $escapedArgs
    $pinfo.WorkingDirectory = $WorkDir
    $pinfo.UseShellExecute = $false
    $pinfo.CreateNoWindow = $true
    $pinfo.RedirectStandardInput = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.RedirectStandardError = $true

    $process = [System.Diagnostics.Process]::Start($pinfo)

    # Write prompt to stdin using BOM-less UTF-8 (PS 5.1 compatible)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $writer = New-Object System.IO.StreamWriter($process.StandardInput.BaseStream, $utf8NoBom)
    $writer.Write($fullPrompt)
    $writer.Close()

    # Read stdout and stderr asynchronously to avoid deadlock
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()

    $exited = $process.WaitForExit($Timeout * 1000)

    if (-not $exited) {
        try { $process.Kill() } catch {}
        [Console]::Error.WriteLine("Error: Claude Code CLI timed out after ${Timeout}s")
        exit 2
    }

    $claudeExit = $process.ExitCode
    $stdoutContent = $stdoutTask.Result
    $stderrContent = $stderrTask.Result

    # Trim only the whole-string ends; .NET String.Trim() does NOT mutate per-line indentation
    $output = if ($stdoutContent) { $stdoutContent.TrimEnd("`r", "`n") } else { "" }

    if ($output -and $output.Trim().Length -gt 0) {
        Write-Output $output
    } else {
        [Console]::Error.WriteLine("Claude Code CLI returned empty output.")
        if ($stderrContent) {
            [Console]::Error.WriteLine("Stderr:")
            [Console]::Error.WriteLine($stderrContent)
        }
        exit 1
    }

    if ($claudeExit -ne 0) {
        exit $claudeExit
    }
} catch {
    [Console]::Error.WriteLine("Error: $_")
    exit 1
}

exit 0
