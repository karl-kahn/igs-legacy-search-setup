#Requires -Version 5.1
# IGS Legacy Search Bootstrap - Windows
# One-command setup: installs Node.js + Claude Code, configures MCP server.
$ErrorActionPreference = "Stop"

$McpUrl = "https://malone.taildf301e.ts.net:8443/mcp"
$McpToken = "2KL2PzA9eKNSFdmsDY1j0aB5R_aEBMFM8arFCJicgxg"
$Step = 0
$TotalSteps = 4

# --- Helpers ---
function Refresh-Path {
    $machinePath = [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
    $env:PATH = "$machinePath;$userPath"
}

function Show-Step {
    param([string]$Label)
    $script:Step++
    Write-Host ""
    Write-Host "  [$Step/$TotalSteps] $Label" -ForegroundColor Cyan
    Start-Sleep -Milliseconds 300
}

function Show-OK {
    param([string]$Message)
    Write-Host "         $Message" -ForegroundColor Green
}

function Show-Action {
    param([string]$Message)
    Write-Host "         $Message" -ForegroundColor White
}

function Show-Warn {
    param([string]$Message)
    Write-Host "         $Message" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  ========================================" -ForegroundColor Cyan
Write-Host "  IGS Legacy Project Search - Setup" -ForegroundColor Cyan
Write-Host "  ========================================" -ForegroundColor Cyan
Write-Host ""
Start-Sleep -Milliseconds 500

# --- Step 1: Node.js ---
Show-Step "Node.js"
$nodeInstalled = Get-Command node -ErrorAction SilentlyContinue
if ($nodeInstalled) {
    $nodeVersion = (node --version 2>$null) -replace '^v',''
    $nodeMajor = [int]($nodeVersion -split '\.')[0]
    if ($nodeMajor -ge 18) {
        Show-OK "Ready (v$nodeVersion)."
    } else {
        Show-Warn "Found v$nodeVersion but need v18+. Upgrading..."
        $hasWinget = Get-Command winget -ErrorAction SilentlyContinue
        if ($hasWinget) {
            winget install OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements
            Refresh-Path
        } else {
            Show-Warn "Please update Node.js from https://nodejs.org (LTS version) and run this script again."
            exit 1
        }
        Show-OK "Upgraded."
    }
} else {
    Show-Action "Installing..."
    $hasWinget = Get-Command winget -ErrorAction SilentlyContinue
    if ($hasWinget) {
        winget install OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements
        Refresh-Path
    }
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        Show-Warn "Could not install Node.js automatically."
        Show-Warn "Please install from https://nodejs.org (LTS version) and run this script again."
        exit 1
    }
    Show-OK "Installed."
}

# --- Step 2: Git Bash (required by Claude Code on Windows) ---
Show-Step "Git Bash"
$gitBashPath = $null
$gitBashCandidates = @(
    "$env:ProgramFiles\Git\bin\bash.exe",
    "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
    "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
)
foreach ($candidate in $gitBashCandidates) {
    if (Test-Path $candidate) {
        $gitBashPath = $candidate
        break
    }
}

if (-not $gitBashPath) {
    # Git might be installed but Git\bin not in PATH -- check if git.exe is findable
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if ($gitCmd) {
        # git.exe is usually in Git\cmd -- bash.exe is in Git\bin
        $gitDir = Split-Path (Split-Path $gitCmd.Source)
        $candidate = Join-Path $gitDir "bin\bash.exe"
        if (Test-Path $candidate) {
            $gitBashPath = $candidate
        }
    }
}

if (-not $gitBashPath) {
    Show-Action "Installing Git (includes Git Bash)..."
    $hasWinget = Get-Command winget -ErrorAction SilentlyContinue
    if ($hasWinget) {
        winget install Git.Git --accept-source-agreements --accept-package-agreements
        Refresh-Path
    } else {
        Show-Warn "Could not install Git automatically (winget not available)."
        Show-Warn "Please install from https://git-scm.com/downloads"
        Show-Warn "IMPORTANT: During install, keep 'Git Bash' checked."
        Show-Warn "Then run this script again."
        exit 1
    }
    foreach ($candidate in $gitBashCandidates) {
        if (Test-Path $candidate) {
            $gitBashPath = $candidate
            break
        }
    }
    # Also re-check via git.exe in case winget put it somewhere unexpected
    if (-not $gitBashPath) {
        $gitCmd = Get-Command git -ErrorAction SilentlyContinue
        if ($gitCmd) {
            $gitDir = Split-Path (Split-Path $gitCmd.Source)
            $candidate = Join-Path $gitDir "bin\bash.exe"
            if (Test-Path $candidate) {
                $gitBashPath = $candidate
            }
        }
    }
    if (-not $gitBashPath) {
        Show-Warn "Git installed but Git Bash (bash.exe) not found."
        Show-Warn "This can happen if Git was installed without the Bash component."
        Show-Warn ""
        Show-Warn "To fix: uninstall Git, then reinstall from https://git-scm.com/downloads"
        Show-Warn "During install, make sure 'Git Bash' is checked (it's on by default)."
        Show-Warn "Then run this script again."
        exit 1
    }
    Show-OK "Installed."
} else {
    Show-OK "Found."
}

# Ensure Git\bin is in PATH so Claude Code can find bash.exe
$gitBinDir = Split-Path $gitBashPath
if ($env:PATH -notlike "*$gitBinDir*") {
    $env:PATH = "$gitBinDir;$env:PATH"
    # Persist for future sessions
    $userPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
    if ($userPath -notlike "*$gitBinDir*") {
        [System.Environment]::SetEnvironmentVariable("PATH", "$gitBinDir;$userPath", "User")
    }
    Show-OK "Added to PATH: $gitBinDir"
} else {
    Show-OK "Already in PATH."
}

# Set CLAUDE_CODE_GIT_BASH_PATH so Claude Code finds bash.exe regardless of PATH
$env:CLAUDE_CODE_GIT_BASH_PATH = $gitBashPath
[System.Environment]::SetEnvironmentVariable("CLAUDE_CODE_GIT_BASH_PATH", $gitBashPath, "User")
Show-OK "CLAUDE_CODE_GIT_BASH_PATH = $gitBashPath"

# --- Step 3: Claude Code ---
Show-Step "Claude Code"
if (Get-Command claude -ErrorAction SilentlyContinue) {
    Show-OK "Ready."
} else {
    Show-Action "Installing..."
    $hasWinget = Get-Command winget -ErrorAction SilentlyContinue
    if ($hasWinget) {
        winget install Anthropic.ClaudeCode --accept-source-agreements --accept-package-agreements
    } else {
        npm install -g @anthropic-ai/claude-code
    }

    Refresh-Path

    if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
        Show-Warn "Installation completed but 'claude' command not found."
        Show-Warn "Please close this window, open a new PowerShell, and run this script again."
        exit 1
    }
    Show-OK "Installed."
}

# --- Ensure HOME is set ---
if (-not $env:HOME) {
    $env:HOME = $env:USERPROFILE
    [System.Environment]::SetEnvironmentVariable("HOME", $env:USERPROFILE, "User")
}

# --- Step 4: MCP server configuration ---
Show-Step "Search server configuration"
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
        # Malformed JSON -- back up and start fresh
        Copy-Item $configPath "$configPath.bak"
        Show-Warn "Existing config was malformed -- backed up to .claude.json.bak"
        $config = [PSCustomObject]@{}
    }
} else {
    $config = [PSCustomObject]@{}
}

# Ensure mcpServers exists
if (-not $config.PSObject.Properties['mcpServers']) {
    $config | Add-Member -NotePropertyName 'mcpServers' -NotePropertyValue ([PSCustomObject]@{})
}

# Add or update the igs-legacy-search entry
if ($config.mcpServers.PSObject.Properties['igs-legacy-search']) {
    Show-OK "Already configured -- updating."
}
$config.mcpServers | Add-Member -NotePropertyName 'igs-legacy-search' -NotePropertyValue ([PSCustomObject]$mcpEntry) -Force

$config | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8
Show-OK "Server configured."

# --- Done ---
Write-Host ""
Write-Host "  ========================================" -ForegroundColor Green
Write-Host "  Setup complete!" -ForegroundColor Green
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
