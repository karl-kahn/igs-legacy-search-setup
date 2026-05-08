# IGS Legacy Search - Claude Desktop Setup
# Configures Claude Desktop to connect to the IGS Legacy Search MCP server (Azure).
# Requires: Node.js (for the mcp-remote stdio<->HTTP bridge)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "=== IGS Legacy Search - Claude Desktop Setup ===" -ForegroundColor Cyan
Write-Host ""

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
Write-Host "Installing mcp-remote bridge..." -ForegroundColor Yellow
npm install --global mcp-remote 2>$null | Out-Null
Write-Host "mcp-remote ready" -ForegroundColor Green

# Read existing config, merge in our server, write back
# Using node to handle JSON properly (PowerShell mangles nested objects)
$jsScript = @'
const fs = require("fs");
const configPath = process.argv[2];
let config = {};
try { config = JSON.parse(fs.readFileSync(configPath, "utf-8")); } catch {}
if (!config.mcpServers) config.mcpServers = {};
config.mcpServers["igs-legacy-search"] = {
  command: "mcp-remote",
  args: [
    "https://igs-legacy-search-app.calmrock-c14844e2.eastus.azurecontainerapps.io/mcp",
    "--header",
    "Authorization: Bearer J8Mf3bjU62gGgOV7DTKuuEPgPQaKKxqYCwzMYj0X/D4"
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
$result = node $jsPath $configPath
if ($result -ne "OK") {
    Write-Host "ERROR: Config write failed. Please contact Karl." -ForegroundColor Red
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
