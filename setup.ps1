# IGS Legacy Search - Claude Desktop Setup
# Configures Claude Desktop to connect to the IGS Legacy Search MCP server (Azure).
# Requires: Node.js (for the mcp-remote stdio<->HTTP bridge)
#
# Usage:
#   .\setup.ps1                              # prompts for the bearer token
#   .\setup.ps1 -BearerToken "<paste-token-here>"   # pass it in directly

param(
    [string]$BearerToken = ""
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "=== IGS Legacy Search - Claude Desktop Setup ===" -ForegroundColor Cyan
Write-Host ""

# Bearer token — emailed to you by Karl. Required to authenticate against the
# MCP server. Re-running setup.ps1 to update other things? Pass the token
# again with -BearerToken so you don't have to dig it out of email.
if ([string]::IsNullOrWhiteSpace($BearerToken)) {
    Write-Host "Paste the bearer token Karl emailed you, then press Enter:" -ForegroundColor Yellow
    $BearerToken = Read-Host "  Token"
    if ([string]::IsNullOrWhiteSpace($BearerToken)) {
        Write-Host "ERROR: No token entered. Cannot continue." -ForegroundColor Red
        exit 1
    }
}
$BearerToken = $BearerToken.Trim()

# Check Node.js
$nodePath = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodePath) {
    Write-Host "ERROR: Node.js is not installed." -ForegroundColor Red
    Write-Host "Download and install from: https://nodejs.org/ (LTS version)"
    Write-Host "Then close this window, reopen PowerShell, and run this script again."
    exit 1
}
$nodeVersion = node --version
Write-Host "Node.js found: $nodeVersion" -ForegroundColor Green

# Configure Claude Desktop
$configDir = "$env:APPDATA\Claude"
$configPath = "$configDir\claude_desktop_config.json"

if (-not (Test-Path $configDir)) {
    Write-Host "Claude Desktop config directory not found at $configDir" -ForegroundColor Red
    Write-Host "Install Claude Desktop from https://claude.ai/download first."
    exit 1
}

# Install mcp-remote globally BEFORE writing the config. Claude Desktop's spawn
# environment doesn't reliably handle `npx -y mcp-remote` on first launch — the
# auto-install can fail silently and the bridge child process exits in <100ms.
# Pre-installing globally and invoking `mcp-remote` directly (no `npx`) avoids
# the auto-install path entirely.
#
# npm routinely writes harmless "npm notice" lines to stderr. With the
# script-level `$ErrorActionPreference = "Stop"`, PowerShell treats those
# stderr lines as terminating NativeCommandError and halts execution.
# Suppress by (a) merging stderr into stdout via 2>&1 so PowerShell never
# sees them as error records, and (b) locally relaxing ErrorAction around
# the call so the npm exit code is what we actually check, not stderr chatter.
Write-Host "Installing mcp-remote bridge..." -ForegroundColor Yellow
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
    & npm install --global mcp-remote 2>&1 | Out-Null
} finally {
    $ErrorActionPreference = $prevEAP
}
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: 'npm install --global mcp-remote' failed (exit $LASTEXITCODE)." -ForegroundColor Red
    Write-Host "If this is a corporate-Windows permissions issue, try running PowerShell as administrator" -ForegroundColor Red
    Write-Host "or install mcp-remote without --global by setting npm prefix to a user-writable directory." -ForegroundColor Red
    exit 1
}
Write-Host "mcp-remote ready" -ForegroundColor Green

# Read existing config, merge in our server, write back. Using node so JSON
# survives PowerShell's nested-object mangling. Token comes through via env
# var rather than string-interpolated into the JS source — keeps special
# chars (/ + =) from needing escape gymnastics.
$jsScript = @'
const fs = require("fs");
const configPath = process.argv[2];
const bearerToken = process.env.IGS_BEARER_TOKEN;
if (!bearerToken) {
  console.log("FAIL: IGS_BEARER_TOKEN env var missing");
  process.exit(1);
}
let config = {};
try { config = JSON.parse(fs.readFileSync(configPath, "utf-8")); } catch {}
if (!config.mcpServers) config.mcpServers = {};
config.mcpServers["igs-legacy-search"] = {
  command: "mcp-remote",
  args: [
    "https://igs-legacy-search-app.calmrock-c14844e2.eastus.azurecontainerapps.io/mcp",
    "--header",
    "Authorization: Bearer " + bearerToken
  ]
};
fs.writeFileSync(configPath, JSON.stringify(config, null, 2), "utf-8");
const written = JSON.parse(fs.readFileSync(configPath, "utf-8"));
if (written.mcpServers && written.mcpServers["igs-legacy-search"]) {
  console.log("OK");
} else {
  console.log("FAIL");
  process.exit(1);
}
'@

$jsPath = "$env:TEMP\igs-setup-config.js"
$jsScript | Out-File -FilePath $jsPath -Encoding UTF8

Write-Host "Configuring Claude Desktop..." -ForegroundColor Yellow
$env:IGS_BEARER_TOKEN = $BearerToken
try {
    $result = node $jsPath $configPath
} finally {
    Remove-Item Env:\IGS_BEARER_TOKEN -ErrorAction SilentlyContinue
}
if ($result -ne "OK") {
    Write-Host "ERROR: Config write failed. Please contact Karl." -ForegroundColor Red
    Write-Host "  Detail: $result" -ForegroundColor Red
    Remove-Item $jsPath -ErrorAction SilentlyContinue
    exit 1
}
Write-Host "Config written successfully" -ForegroundColor Green

# Clean up
Remove-Item $jsPath -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Close Claude Desktop completely (right-click system tray icon > Quit)"
Write-Host "  2. Reopen Claude Desktop"
Write-Host "  3. Try asking: What's the status of the most recent ingest?"
Write-Host ""
Write-Host "Available tools:" -ForegroundColor Cyan
Write-Host "  Search & retrieval:"
Write-Host "    - search_projects: Natural language search across all projects"
Write-Host "    - get_document: Pull up a specific document"
Write-Host "    - get_document_chunks: Page through a long document"
Write-Host "    - list_project_documents: See every document in a project"
Write-Host "    - summarize_project: Get final deliverables for a project"
Write-Host "    - list_projects: Browse everything indexed"
Write-Host "    - generate_memo: Export to IGS Word template"
Write-Host "  Operational dashboard:"
Write-Host "    - get_ingest_status: Most recent ingest run status"
Write-Host "    - list_ingest_runs: Recent ingest history"
Write-Host "    - list_ingest_failures: Projects that failed to ingest"
Write-Host "    - get_search_usage: Tool-call statistics"
Write-Host ""
