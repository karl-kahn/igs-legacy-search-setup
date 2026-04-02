#Requires -Version 5.1
# IGS Legacy Search Bootstrap - Windows
# One-command setup: installs dependencies, configures Claude Code + MCP server.
# Safe to re-run — skips anything already installed.
#
# Failure modes handled:
#   - No winget (falls back to direct download / npm)
#   - No Git (installs via winget or direct download)
#   - Git installed without bash.exe (exhaustive search + clear instructions)
#   - WSL bash.exe shadowing Git bash (explicitly excluded)
#   - Claude Code can't find bash.exe (writes to settings.json, not env vars)
#   - PATH not updated after install (refreshes from registry)
#   - HOME not set (sets it)
#   - Existing .claude.json malformed (backs up and recreates)
#   - PowerShell execution policy (handled by irm|iex invocation pattern)
#   - Spaces in Git path (quoted everywhere)

$ErrorActionPreference = "Stop"

$McpUrl = "https://malone.taildf301e.ts.net:8443/mcp"
$McpToken = "2KL2PzA9eKNSFdmsDY1j0aB5R_aEBMFM8arFCJicgxg"
$Step = 0
$TotalSteps = 5

# --- Helpers ---

function Refresh-Path {
    $machinePath = [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
    $env:PATH = "$userPath;$machinePath"
}

function Show-Step {
    param([string]$Label)
    $script:Step++
    Write-Host ""
    Write-Host "  [$Step/$TotalSteps] $Label" -ForegroundColor Cyan
    Start-Sleep -Milliseconds 300
}

function Show-OK    { param([string]$M) Write-Host "         $M" -ForegroundColor Green }
function Show-Action{ param([string]$M) Write-Host "         $M" -ForegroundColor White }
function Show-Warn  { param([string]$M) Write-Host "         $M" -ForegroundColor Yellow }
function Show-Error { param([string]$M) Write-Host "         $M" -ForegroundColor Red }

function Find-GitBash {
    # Search every reasonable location for bash.exe from Git for Windows.
    # Returns the full path or $null.
    # Explicitly excludes WSL's bash.exe (System32) which is NOT Git Bash.

    $candidates = @(
        # Standard installs
        "$env:ProgramFiles\Git\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
        # User-scoped installs
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe",
        "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe",
        # Chocolatey
        "$env:ProgramData\chocolatey\lib\git\tools\cmd\..\bin\bash.exe",
        # GitHub Desktop bundles Git
        "$env:LOCALAPPDATA\GitHubDesktop\app-*\resources\app\git\cmd\..\bin\bash.exe"
    )

    foreach ($c in $candidates) {
        # Resolve wildcards (GitHub Desktop version glob)
        $resolved = Resolve-Path $c -ErrorAction SilentlyContinue
        if ($resolved) {
            foreach ($r in $resolved) {
                if (Test-Path $r) { return $r.Path }
            }
        }
    }

    # Fallback: find git.exe on PATH and derive bash.exe location
    # Claude Code does: git.exe path -> ../../bin/bash.exe
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if ($gitCmd -and $gitCmd.Source) {
        $gitExePath = $gitCmd.Source
        # git.exe is typically in Git\cmd\git.exe — bash is in Git\bin\bash.exe
        $gitRoot = Split-Path (Split-Path $gitExePath)
        $derivedBash = Join-Path $gitRoot "bin\bash.exe"
        if (Test-Path $derivedBash) { return $derivedBash }

        # Some installs put git.exe directly in Git\bin
        $siblingBash = Join-Path (Split-Path $gitExePath) "bash.exe"
        if (Test-Path $siblingBash) { return $siblingBash }
    }

    # Last resort: search common drive roots (slow but thorough)
    $drives = @("C:\")
    foreach ($drive in $drives) {
        $found = Get-ChildItem -Path "${drive}Program Files","${drive}Program Files (x86)" `
            -Filter "bash.exe" -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notlike "*System32*" -and $_.FullName -like "*Git*" } |
            Select-Object -First 1
        if ($found) { return $found.FullName }
    }

    return $null
}

function Write-JsonFile {
    # ConvertTo-Json on PS 5.1 has quirks with depth and encoding.
    # This helper ensures clean UTF-8 without BOM.
    param([string]$Path, [object]$Object)
    $json = $Object | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

# --- Banner ---
Write-Host ""
Write-Host "  ========================================" -ForegroundColor Cyan
Write-Host "  IGS Legacy Project Search - Setup" -ForegroundColor Cyan
Write-Host "  ========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  This will install and configure everything" -ForegroundColor White
Write-Host "  you need. Takes about 5 minutes." -ForegroundColor White
Start-Sleep -Milliseconds 500

# ===================================================================
# STEP 1: Node.js
# ===================================================================
Show-Step "Node.js"
Refresh-Path
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if ($nodeCmd) {
    $nodeVersion = (node --version 2>$null) -replace '^v',''
    $nodeMajor = [int]($nodeVersion -split '\.')[0]
    if ($nodeMajor -ge 18) {
        Show-OK "Ready (v$nodeVersion)."
    } else {
        Show-Action "Found v$nodeVersion but need v18+. Upgrading..."
        $hasWinget = Get-Command winget -ErrorAction SilentlyContinue
        if ($hasWinget) {
            winget install OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements 2>$null
            Refresh-Path
        }
        $nodeCmd2 = Get-Command node -ErrorAction SilentlyContinue
        if (-not $nodeCmd2) {
            Show-Warn "Could not upgrade Node.js automatically."
            Show-Warn "Please install from https://nodejs.org (LTS version) and run this script again."
            exit 1
        }
        Show-OK "Upgraded."
    }
} else {
    Show-Action "Installing Node.js..."
    $installed = $false
    $hasWinget = Get-Command winget -ErrorAction SilentlyContinue
    if ($hasWinget) {
        winget install OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements 2>$null
        Refresh-Path
        if (Get-Command node -ErrorAction SilentlyContinue) { $installed = $true }
    }
    if (-not $installed) {
        # Direct download fallback
        Show-Action "Trying direct download..."
        $nodeInstaller = "$env:TEMP\node-setup.msi"
        try {
            Invoke-WebRequest -Uri "https://nodejs.org/dist/v22.15.0/node-v22.15.0-x64.msi" -OutFile $nodeInstaller -UseBasicParsing
            Start-Process msiexec.exe -ArgumentList "/i `"$nodeInstaller`" /qn" -Wait -NoNewWindow
            Remove-Item $nodeInstaller -ErrorAction SilentlyContinue
            Refresh-Path
            if (Get-Command node -ErrorAction SilentlyContinue) { $installed = $true }
        } catch {
            # Silent — fall through to error
        }
    }
    if (-not $installed) {
        Show-Error "Could not install Node.js."
        Show-Warn "Please install manually from https://nodejs.org (LTS version)"
        Show-Warn "then run this script again."
        exit 1
    }
    Show-OK "Installed."
}

# ===================================================================
# STEP 2: Git + Git Bash
# ===================================================================
Show-Step "Git Bash"
$gitBashPath = Find-GitBash

if (-not $gitBashPath) {
    Show-Action "Git Bash not found. Installing Git for Windows..."
    $installed = $false
    $hasWinget = Get-Command winget -ErrorAction SilentlyContinue
    if ($hasWinget) {
        winget install Git.Git --accept-source-agreements --accept-package-agreements 2>$null
        Refresh-Path
        $gitBashPath = Find-GitBash
        if ($gitBashPath) { $installed = $true }
    }
    if (-not $installed) {
        # Direct download fallback
        Show-Action "Trying direct download..."
        $gitInstaller = "$env:TEMP\git-setup.exe"
        try {
            # Git for Windows latest release redirect
            Invoke-WebRequest -Uri "https://github.com/git-for-windows/git/releases/latest/download/Git-2.49.0-64-bit.exe" -OutFile $gitInstaller -UseBasicParsing
            Start-Process $gitInstaller -ArgumentList "/VERYSILENT /NORESTART /COMPONENTS=gitlfs,assoc,assoc_sh,bash" -Wait -NoNewWindow
            Remove-Item $gitInstaller -ErrorAction SilentlyContinue
            Refresh-Path
            $gitBashPath = Find-GitBash
            if ($gitBashPath) { $installed = $true }
        } catch {
            # Silent — fall through to error
        }
    }
    if (-not $gitBashPath) {
        Show-Error "Could not install Git Bash automatically."
        Write-Host ""
        Show-Warn "Please install Git manually:"
        Show-Warn "  1. Go to https://git-scm.com/downloads/win"
        Show-Warn "  2. Download and run the installer"
        Show-Warn "  3. IMPORTANT: Make sure 'Git Bash' is checked (it's on by default)"
        Show-Warn "  4. Finish the install, then run this script again"
        exit 1
    }
    Show-OK "Installed."
} else {
    Show-OK "Found: $gitBashPath"
}

# Verify it's actually Git Bash, not WSL
$bashContent = & cmd /c "echo." 2>$null
$isWSL = $gitBashPath -like "*System32*" -or $gitBashPath -like "*WindowsApps*"
if ($isWSL) {
    Show-Warn "Found bash.exe at $gitBashPath but this is WSL, not Git Bash."
    Show-Warn "Please install Git for Windows from https://git-scm.com/downloads/win"
    Show-Warn "then run this script again."
    exit 1
}

# ===================================================================
# STEP 3: Claude Code
# ===================================================================
Show-Step "Claude Code"
Refresh-Path
if (Get-Command claude -ErrorAction SilentlyContinue) {
    Show-OK "Ready."
} else {
    Show-Action "Installing Claude Code..."
    $installed = $false

    # Try winget first
    $hasWinget = Get-Command winget -ErrorAction SilentlyContinue
    if ($hasWinget) {
        winget install Anthropic.ClaudeCode --accept-source-agreements --accept-package-agreements 2>$null
        Refresh-Path
        if (Get-Command claude -ErrorAction SilentlyContinue) { $installed = $true }
    }

    # Fallback: npm global install
    if (-not $installed) {
        Show-Action "Trying npm install..."
        npm install -g @anthropic-ai/claude-code 2>$null
        Refresh-Path
        if (Get-Command claude -ErrorAction SilentlyContinue) { $installed = $true }
    }

    if (-not $installed) {
        Show-Error "Could not install Claude Code."
        Show-Warn "Please try manually in a NEW PowerShell window:"
        Show-Warn "  npm install -g @anthropic-ai/claude-code"
        Show-Warn "then run this script again."
        exit 1
    }
    Show-OK "Installed."
}

# ===================================================================
# STEP 4: Configure Claude Code (settings.json + .claude.json)
# ===================================================================
Show-Step "Configuration"

# --- Ensure HOME is set ---
if (-not $env:HOME) {
    $env:HOME = $env:USERPROFILE
    [System.Environment]::SetEnvironmentVariable("HOME", $env:USERPROFILE, "User")
}

# --- 4a: Write CLAUDE_CODE_GIT_BASH_PATH to settings.json ---
# This is the RELIABLE way — Claude Code reads this file on startup,
# completely bypassing OS env var propagation issues.
$claudeDir = "$env:USERPROFILE\.claude"
if (-not (Test-Path $claudeDir)) {
    New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
}

$settingsPath = "$claudeDir\settings.json"
if (Test-Path $settingsPath) {
    try {
        $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
    } catch {
        Copy-Item $settingsPath "$settingsPath.bak"
        Show-Warn "Existing settings.json was malformed -- backed up."
        $settings = [PSCustomObject]@{}
    }
} else {
    $settings = [PSCustomObject]@{}
}

# Ensure env block exists
if (-not $settings.PSObject.Properties['env']) {
    $settings | Add-Member -NotePropertyName 'env' -NotePropertyValue ([PSCustomObject]@{})
}

# Write the bash path
$settings.env | Add-Member -NotePropertyName 'CLAUDE_CODE_GIT_BASH_PATH' -NotePropertyValue $gitBashPath -Force
Write-JsonFile -Path $settingsPath -Object $settings
Show-OK "Git Bash path written to settings.json"

# Also set as env var (belt and suspenders — helps if Claude Code
# is launched from a different context like VS Code)
$env:CLAUDE_CODE_GIT_BASH_PATH = $gitBashPath
[System.Environment]::SetEnvironmentVariable("CLAUDE_CODE_GIT_BASH_PATH", $gitBashPath, "User")

# --- 4b: Configure MCP server in .claude.json ---
$configPath = "$env:USERPROFILE\.claude.json"
$mcpEntry = @{
    type = "http"
    url = $McpUrl
    headers = @{
        Authorization = "Bearer $McpToken"
    }
}

if (Test-Path $configPath) {
    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
    } catch {
        Copy-Item $configPath "$configPath.bak"
        Show-Warn "Existing .claude.json was malformed -- backed up."
        $config = [PSCustomObject]@{}
    }
} else {
    $config = [PSCustomObject]@{}
}

if (-not $config.PSObject.Properties['mcpServers']) {
    $config | Add-Member -NotePropertyName 'mcpServers' -NotePropertyValue ([PSCustomObject]@{})
}

$config.mcpServers | Add-Member -NotePropertyName 'igs-legacy-search' -NotePropertyValue ([PSCustomObject]$mcpEntry) -Force
Write-JsonFile -Path $configPath -Object $config
Show-OK "MCP server configured."

# ===================================================================
# STEP 5: Verify everything
# ===================================================================
Show-Step "Verification"
$allGood = $true

# Check Node
$v = node --version 2>$null
if ($v) { Show-OK "Node.js $v" } else { Show-Error "Node.js: NOT FOUND"; $allGood = $false }

# Check bash.exe exists at the path we wrote
if (Test-Path $gitBashPath) {
    Show-OK "Git Bash: $gitBashPath"
} else {
    Show-Error "Git Bash: path was set but file not found at $gitBashPath"
    $allGood = $false
}

# Check settings.json has the path
try {
    $checkSettings = Get-Content $settingsPath -Raw | ConvertFrom-Json
    $checkBash = $checkSettings.env.CLAUDE_CODE_GIT_BASH_PATH
    if ($checkBash -and (Test-Path $checkBash)) {
        Show-OK "settings.json: CLAUDE_CODE_GIT_BASH_PATH verified"
    } else {
        Show-Error "settings.json: CLAUDE_CODE_GIT_BASH_PATH missing or invalid"
        $allGood = $false
    }
} catch {
    Show-Error "settings.json: could not read"
    $allGood = $false
}

# Check Claude Code
if (Get-Command claude -ErrorAction SilentlyContinue) {
    Show-OK "Claude Code: installed"
} else {
    Show-Error "Claude Code: NOT FOUND"
    $allGood = $false
}

# Check MCP config
try {
    $checkConfig = Get-Content $configPath -Raw | ConvertFrom-Json
    if ($checkConfig.mcpServers.'igs-legacy-search'.url -eq $McpUrl) {
        Show-OK "MCP server: configured"
    } else {
        Show-Error "MCP server: config missing or wrong"
        $allGood = $false
    }
} catch {
    Show-Error "MCP server: could not read .claude.json"
    $allGood = $false
}

# --- Result ---
Write-Host ""
if ($allGood) {
    Write-Host "  ========================================" -ForegroundColor Green
    Write-Host "  Setup complete! Everything looks good." -ForegroundColor Green
    Write-Host "  ========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  To start searching, type:" -ForegroundColor White
    Write-Host ""
    Write-Host "    claude" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  It will ask you to log in on first launch." -ForegroundColor White
    Write-Host "  Sign in with your Anthropic account in the" -ForegroundColor White
    Write-Host "  browser, then come back to the terminal." -ForegroundColor White
    Write-Host ""
    Write-Host "  Then try:" -ForegroundColor White
    Write-Host '    "Search for projects involving sulfuric acid"' -ForegroundColor White
    Write-Host '    "List all indexed projects"' -ForegroundColor White
    Write-Host '    "Summarize project P-1074"' -ForegroundColor White
    Write-Host ""
} else {
    Write-Host "  ========================================" -ForegroundColor Red
    Write-Host "  Setup had issues (see above)." -ForegroundColor Red
    Write-Host "  ========================================" -ForegroundColor Red
    Write-Host ""
    Show-Warn "Try closing this window, opening a new PowerShell,"
    Show-Warn "and running the setup command again."
    Show-Warn ""
    Show-Warn "If it still fails, send a screenshot to your contact"
    Show-Warn "and we'll get it sorted out."
    Write-Host ""
}
