# wrap skill — SessionEnd reminder hook (Windows).
# Prints a one-line nudge if the current cwd has wrap-worthy state.
# Rate-limited to once per 5 minutes via ~/.claude/wrap-nudge-last-fired.
# Must exit 0 always. Never blocks or invokes wrap.

$ErrorActionPreference = 'SilentlyContinue'

$Marker = Join-Path $HOME '.claude/wrap-nudge-last-fired'
$RateLimitSeconds = 300

# Rate limit
if (Test-Path $Marker) {
    $last = (Get-Item $Marker).LastWriteTime
    $age = (Get-Date) - $last
    if ($age.TotalSeconds -lt $RateLimitSeconds) {
        exit 0
    }
}

# Must be in a git repo
git rev-parse --is-inside-work-tree 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { exit 0 }

$repoRoot = git rev-parse --show-toplevel 2>$null
$repoName = Split-Path -Leaf $repoRoot
$signals = @()

# 1. Dirty working tree?
$dirty = git status --porcelain 2>$null
$dirtyCount = if ($dirty) { ($dirty -split "`n" | Where-Object { $_.Trim() }).Count } else { 0 }
if ($dirtyCount -gt 0) {
    $signals += "$dirtyCount dirty files"
}

# 2. Unpushed commits?
git rev-parse --abbrev-ref '@{u}' 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
    $unpushed = git log --oneline '@{u}..HEAD' 2>$null
    $unpushedCount = if ($unpushed) { ($unpushed -split "`n" | Where-Object { $_.Trim() }).Count } else { 0 }
    if ($unpushedCount -gt 0) {
        $signals += "$unpushedCount unpushed commits"
    }
}

# 3. Files in .claude/scripts/?
if (Test-Path '.claude/scripts') {
    $scripts = Get-ChildItem '.claude/scripts' -File -ErrorAction SilentlyContinue
    $scriptCount = if ($scripts) { $scripts.Count } else { 0 }
    if ($scriptCount -gt 0) {
        $signals += "$scriptCount script(s) in .claude/scripts"
    }
}

# Print and mark
if ($signals.Count -gt 0) {
    $msg = "⚠ wrap-worthy state: " + ($signals -join ', ') + " in $repoName. Consider /wrap next session."
    Write-Host $msg
    $markerDir = Split-Path -Parent $Marker
    if (-not (Test-Path $markerDir)) { New-Item -ItemType Directory -Path $markerDir | Out-Null }
    New-Item -ItemType File -Path $Marker -Force | Out-Null
}

exit 0
