param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet("snapshot", "check")]
    [string]$Command,
    [Parameter(Mandatory = $true)]
    [string]$Repo,
    [Parameter(Mandatory = $true)]
    [string]$Snapshot,
    [string[]]$Allow = @()
)

$ErrorActionPreference = "Stop"

function Fail([string]$Message) {
    Write-Output "[CLAUDE_VERIFY_ERROR] $Message"
    exit 2
}

function Invoke-Git([string[]]$Arguments, [switch]$AllowFailure) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $result = & git -C $script:RepoRoot @Arguments 2>&1
    $ErrorActionPreference = $previous
    if ($LASTEXITCODE -ne 0) {
        if ($AllowFailure) { return "" }
        throw ($result -join "`n")
    }
    return (($result | Where-Object { $_ -notmatch '^warning: unable to access .*\.config/git/ignore' }) -join "`n")
}

function Relative-Path([string]$FullName) {
    $root = $script:RepoRoot.TrimEnd("\", "/") + "\"
    if (-not $FullName.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        throw "repository path escape"
    }
    return $FullName.Substring($root.Length).Replace("\", "/")
}

function Is-Protected([string]$Path) {
    $p = $Path.Replace("\", "/")
    $name = [IO.Path]::GetFileName($p)
    if ($p -ieq ".git/config" -or $p -ilike ".git/hooks/*") { return $true }
    if ($name -ieq ".env" -or $name -ilike ".env.*") { return $true }
    return $name -imatch '\.(pem|key|p12|pfx)$'
}

function File-State([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force
    $kind = "file"
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $kind = "reparse" }
    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    $target = $null
    if ($kind -eq "reparse") { $target = [string]$item.Target }
    return [ordered]@{ kind = $kind; target = $target; sha256 = $hash }
}

function Protected-State {
    $state = [ordered]@{}
    $items = @(Get-ChildItem -LiteralPath $script:RepoRoot -Recurse -Force -File -ErrorAction Stop |
        Where-Object { $_.FullName -notlike "$($script:RepoRoot)\.git\*" })
    foreach ($item in $items) {
        $rel = Relative-Path $item.FullName
        if (Is-Protected $rel) { $state[$rel] = File-State $item.FullName }
    }
    $gitConfig = Invoke-Git @("rev-parse", "--path-format=absolute", "--git-path", "config")
    if (Test-Path -LiteralPath $gitConfig -PathType Leaf) { $state[".git/config"] = File-State $gitConfig }
    $hooks = Invoke-Git @("rev-parse", "--path-format=absolute", "--git-path", "hooks")
    if (Test-Path -LiteralPath $hooks -PathType Container) {
        foreach ($item in (Get-ChildItem -LiteralPath $hooks -Recurse -Force -File)) {
            $hookRel = $item.FullName.Substring($hooks.Length).TrimStart("\", "/").Replace("\", "/")
            $state[".git/hooks/$hookRel"] = File-State $item.FullName
        }
    }
    return $state
}

function Current-State {
    return [ordered]@{
        version = 1
        implementation = "powershell"
        repo = $script:RepoRoot
        head = Invoke-Git @("rev-parse", "HEAD")
        branch = Invoke-Git @("symbolic-ref", "--quiet", "--short", "HEAD") -AllowFailure
        status = Invoke-Git @("-c", "core.quotepath=true", "status", "--porcelain=v1", "--untracked-files=all")
        protected = Protected-State
    }
}

function Same-Value($A, $B) {
    return (($A | ConvertTo-Json -Depth 8 -Compress) -ceq ($B | ConvertTo-Json -Depth 8 -Compress))
}

try {
    $script:RepoRoot = (Resolve-Path -LiteralPath $Repo).Path.TrimEnd("\", "/")
    $gitTop = (Resolve-Path -LiteralPath (Invoke-Git @("rev-parse", "--show-toplevel"))).Path.TrimEnd("\", "/")
    if ($gitTop -ine $script:RepoRoot) {
        Fail "Repo must be the Git repository root"
    }
    $snapshotFull = [IO.Path]::GetFullPath($Snapshot)
    if ($snapshotFull.StartsWith($script:RepoRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        Fail "Snapshot must be stored outside the repository"
    }

    if ($Command -eq "snapshot") {
        if ($Allow.Count -gt 0) { Fail "Allow is valid only with check" }
        $parent = Split-Path -Parent $snapshotFull
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) { Fail "Snapshot directory does not exist" }
        Current-State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $snapshotFull -Encoding UTF8
        Write-Output "[CLAUDE_VERIFY_OK] snapshot created"
        exit 0
    }

    if (-not (Test-Path -LiteralPath $snapshotFull -PathType Leaf)) { Fail "Snapshot not found" }
    $before = Get-Content -LiteralPath $snapshotFull -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($before.version -ne 1 -or $before.implementation -cne "powershell" -or $before.repo -ine $script:RepoRoot) {
        Fail "Snapshot format, implementation, or repository mismatch"
    }
    $after = Current-State
    $violations = New-Object Collections.Generic.List[string]
    if ($before.head -cne $after.head) { $violations.Add("HEAD changed") }
    if ($before.branch -cne $after.branch) { $violations.Add("branch changed") }
    if ($before.status -cne $after.status) {
        Write-Output "[CLAUDE_VERIFY_OK] working tree status changed"
    }
    Write-Output "### git status --porcelain=v1 --untracked-files=all"
    Write-Output $after.status
    Write-Output "### git diff HEAD --stat"
    Write-Output (Invoke-Git @("diff", "HEAD", "--stat"))

    $beforeProtected = @{}
    $before.protected.PSObject.Properties | ForEach-Object { $beforeProtected[$_.Name] = $_.Value }
    $afterProtected = $after.protected
    $paths = @($beforeProtected.Keys + $afterProtected.Keys | Sort-Object -Unique)
    $changed = @($paths | Where-Object {
        -not $beforeProtected.ContainsKey($_) -or -not $afterProtected.Contains($_) -or
        -not (Same-Value $beforeProtected[$_] $afterProtected[$_])
    })
    $allowed = New-Object Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
    foreach ($raw in $Allow) {
        $p = $raw.Replace("\", "/")
        if ([IO.Path]::IsPathRooted($raw) -or $p -match '(^|/)\.\.(/|$)' -or
            $p.IndexOfAny([char[]]"*?[]") -ge 0 -or $p.EndsWith("/") -or -not (Is-Protected $p) -or
            -not ($changed -icontains $p)) { Fail "Invalid or overbroad allow path: $raw" }
        [void]$allowed.Add($p)
    }
    foreach ($p in $changed) {
        if ($allowed.Contains($p)) {
            Write-Output "[CLAUDE_VERIFY_ALLOWED] protected change: $p"
        } else {
            $violations.Add("protected change: $p")
        }
    }
    if ($violations.Count -gt 0) {
        $violations | ForEach-Object { Write-Output "[CLAUDE_VERIFY_VIOLATION] $_" }
        exit 1
    }
    Write-Output "[CLAUDE_VERIFY_OK] no unapproved changes"
    exit 0
} catch {
    Fail $_.Exception.Message
}
