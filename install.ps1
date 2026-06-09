# IGS Legacy Search -- Claude Desktop one-liner installer (Windows)
#
# Usage:
#   iex (irm https://raw.githubusercontent.com/karl-kahn/igs-legacy-search-setup/main/install.ps1)
#
# To pass a token without the interactive prompt:
#   $env:IGS_BEARER_TOKEN = "<paste token>"; iex (irm https://raw.githubusercontent.com/karl-kahn/igs-legacy-search-setup/main/install.ps1)
#
# Or download + run with -BearerToken flag:
#   irm https://raw.githubusercontent.com/karl-kahn/igs-legacy-search-setup/main/install.ps1 -OutFile install.ps1
#   .\install.ps1 -BearerToken "<token>"
#
# What it does:
#   1. Verifies Node.js >= 18.
#   2. Prompts (masked) for the bearer token if not supplied.
#   3. Verifies the token against the MCP server (HTTP 200 = good, 401 = bad).
#   4. Merges an "igs-legacy-search" entry into %APPDATA%\Claude\claude_desktop_config.json
#      preserving any other mcpServers entries already there.
#   5. Confirms `npx -y mcp-remote --help` runs (dry-run of the bridge).
#   6. Prints next-steps.
#
# Exit codes: 0 success; 1 user/environment error; 2 token rejected; 3 unexpected.
# Compatible with Windows PowerShell 5.1+ (default on Win10/11). No PS7 features.

[CmdletBinding()]
param(
    [string]$BearerToken = ""
)

$ErrorActionPreference = "Stop"

$MCP_URL = "https://igs-legacy-search-app.calmrock-c14844e2.eastus.azurecontainerapps.io/mcp"

function Write-Heading($text) { Write-Host "" ; Write-Host $text -ForegroundColor Cyan }
function Write-OK($text)      { Write-Host ("OK   {0}" -f $text) -ForegroundColor Green }
function Write-Warn2($text)   { Write-Host ("WARN {0}" -f $text) -ForegroundColor Yellow }
function Write-Err2($text)    { Write-Host ("ERR  {0}" -f $text) -ForegroundColor Red }

Write-Heading "=== IGS Legacy Search -- Claude Desktop Setup ==="

# --- 1. Token source ---------------------------------------------------------
# Precedence: -BearerToken arg > $env:IGS_BEARER_TOKEN > prompt.
if ([string]::IsNullOrWhiteSpace($BearerToken)) {
    if ($env:IGS_BEARER_TOKEN) {
        $BearerToken = $env:IGS_BEARER_TOKEN
    }
}

# --- 2. Node.js check --------------------------------------------------------
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeCmd) {
    Write-Err2 "Node.js is not installed."
    Write-Host "Install the LTS build from https://nodejs.org/ then close this PowerShell window," -ForegroundColor Yellow
    Write-Host "open a fresh one (so PATH picks up node), and re-run this command." -ForegroundColor Yellow
    exit 1
}
$nodeVersionRaw = (& node --version) 2>$null
$nodeMajor = 0
if ($nodeVersionRaw -match '^v(\d+)') { $nodeMajor = [int]$Matches[1] }
if ($nodeMajor -lt 18) {
    Write-Err2 ("Node.js {0} is too old. Need v18 or newer." -f $nodeVersionRaw)
    Write-Host "Install the LTS build from https://nodejs.org/ then re-run." -ForegroundColor Yellow
    exit 1
}
Write-OK ("Node.js {0}" -f $nodeVersionRaw)

# --- 3. mcp-remote dry-run ---------------------------------------------------
# `mcp-remote` has no --help flag (treats argv[0] as URL and crashes on
# anything else). Instead resolve the package via `npm view` -- catches
# "registry blocked" / "no network" failures here instead of inside
# Claude Desktop's spawn.
Write-Heading "Confirming mcp-remote is reachable on npm..."
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
    $mcpVer = (& npm view mcp-remote version 2>&1) | Select-Object -Last 1
    $npmOK = ($LASTEXITCODE -eq 0 -and $mcpVer -match '^\d+\.\d+')
} catch {
    $npmOK = $false
} finally {
    $ErrorActionPreference = $prevEAP
}
if ($npmOK) {
    Write-OK ("mcp-remote {0} available via npm" -f $mcpVer)
} else {
    Write-Warn2 "npm view mcp-remote failed. Setup continues, but if Claude Desktop fails to launch"
    Write-Warn2 "the tool, npm/network is the first place to look."
}

# --- 4. Prompt for token (masked) -------------------------------------------
if ([string]::IsNullOrWhiteSpace($BearerToken)) {
    Write-Host ""
    Write-Host "Paste the bearer token your team admin sent you, then press Enter." -ForegroundColor Yellow
    Write-Host "(Input is masked -- you won't see characters as you type.)"
    $secure = Read-Host "  Token" -AsSecureString
    if ($secure.Length -eq 0) {
        Write-Err2 "No token entered. Cannot continue."
        exit 1
    }
    # SecureString -> plain (we have to send it over HTTPS as Bearer anyway).
    # Use the BSTR pattern -- works on PS 5.1 and PS 7.
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $BearerToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}
$BearerToken = $BearerToken.Trim()
if ([string]::IsNullOrWhiteSpace($BearerToken)) {
    Write-Err2 "Empty bearer token. Cannot continue."
    exit 1
}

# --- 5. Verify token against MCP server --------------------------------------
Write-Heading "Verifying token against the MCP server..."
$initPayload = @{
    jsonrpc = "2.0"; id = 1; method = "initialize"
    params = @{
        protocolVersion = "2024-11-05"
        capabilities = @{}
        clientInfo = @{ name = "igs-setup"; version = "0" }
    }
} | ConvertTo-Json -Depth 10 -Compress

$headers = @{
    "Authorization" = "Bearer $BearerToken"
    "Content-Type"  = "application/json"
    "Accept"        = "application/json, text/event-stream"
}

# Force TLS 1.2 -- some old PS 5.1 configs default to SSL3/TLS1.0 which Azure rejects.
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

# Use HttpClient directly. Invoke-WebRequest in PS 5.1 buffers the whole body
# before returning, and the MCP server replies with SSE (text/event-stream)
# that keeps the connection open -- so IWR hangs. HttpCompletionOption.
# ResponseHeadersRead returns as soon as headers land, which is all we need
# for status-code verification.
Add-Type -AssemblyName System.Net.Http
$httpStatus = 0
$client = [System.Net.Http.HttpClient]::new()
try {
    $req = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Post, $MCP_URL)
    $req.Headers.TryAddWithoutValidation("Authorization", "Bearer $BearerToken") | Out-Null
    $req.Headers.TryAddWithoutValidation("Accept", "application/json, text/event-stream") | Out-Null
    $content = [System.Net.Http.StringContent]::new($initPayload, [System.Text.Encoding]::UTF8, "application/json")
    $req.Content = $content
    $task = $client.SendAsync($req, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead)
    $completed = $task.Wait(20000)
    if ($completed -and $task.Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion) {
        $httpStatus = [int]$task.Result.StatusCode
        # Dispose response stream early -- we don't need the SSE body.
        try { $task.Result.Dispose() } catch {}
    }
} catch {
    # Leave $httpStatus as 0; the switch below maps to the right user message.
} finally {
    $client.Dispose()
}

switch ($httpStatus) {
    200 { Write-OK "Token verified (HTTP 200)." }
    401 { Write-Err2 "Server rejected the token (HTTP 401). It's wrong, expired, or copy-paste truncated."
          Write-Host "Ask your team admin for a fresh token, then re-run." -ForegroundColor Yellow
          exit 2 }
    403 { Write-Err2 "Server rejected the token (HTTP 403)."
          Write-Host "Ask your team admin for a fresh token, then re-run." -ForegroundColor Yellow
          exit 2 }
    0   { Write-Err2 "Could not reach the MCP server. Check internet/VPN/firewall." ; exit 1 }
    default { Write-Err2 ("Unexpected HTTP {0} from the MCP server." -f $httpStatus) ; exit 3 }
}

# --- 6. Merge into Claude Desktop config -------------------------------------
$configDir  = if ($env:IGS_CLAUDE_DIR) { $env:IGS_CLAUDE_DIR } else { Join-Path $env:APPDATA "Claude" }
$configPath = Join-Path $configDir "claude_desktop_config.json"

if (-not (Test-Path $configDir)) {
    Write-Warn2 ("Claude Desktop config directory not found at: {0}" -f $configDir)
    Write-Host "That usually means Claude Desktop hasn't been launched yet." -ForegroundColor Yellow
    Write-Host "Install/open Claude Desktop once (https://claude.ai/download), sign in, quit, then re-run." -ForegroundColor Yellow
    exit 1
}

if (Test-Path $configPath) {
    $backupPath = "{0}.bak.{1}" -f $configPath, (Get-Date -Format "yyyyMMdd-HHmmss")
    Copy-Item $configPath $backupPath -Force
    Write-OK ("Backed up existing config to {0}" -f $backupPath)
}

# JSON merge via node (always present -- we just verified Node.js >= 18).
# Token via env var, not argv, so it doesn't show up in `tasklist /v` or
# Get-Process. The node script also avoids the PowerShell ConvertTo-Json
# array-flattening footgun (single-element arrays get unwrapped to scalars).
$jsScript = @'
const fs = require("fs");
const configPath = process.argv[2];
const mcpUrl     = process.argv[3];
const token      = process.env.IGS_BEARER_TOKEN_NODE;
if (!token) { console.error("FAIL: token env missing"); process.exit(1); }

let config = {};
try {
  const raw = fs.readFileSync(configPath, "utf-8").trim();
  if (raw) config = JSON.parse(raw);
} catch (e) {
  if (e.code !== "ENOENT") {
    console.error("FAIL: existing config is not valid JSON: " + e.message);
    process.exit(2);
  }
}
if (typeof config !== "object" || config === null || Array.isArray(config)) {
  console.error("FAIL: top-level config is not a JSON object");
  process.exit(2);
}
if (typeof config.mcpServers !== "object" || config.mcpServers === null || Array.isArray(config.mcpServers)) {
  config.mcpServers = {};
}
// On Windows, Claude Desktop resolves "npx" to C:\Program Files\nodejs\npx.cmd
// and runs it via `cmd /C` WITHOUT quoting, so the space in "Program Files"
// makes cmd choke ("'C:\Program' is not recognized") and the bridge dies on
// launch -> "Server disconnected". Spawning cmd explicitly and letting it
// resolve npx from PATH avoids the unquoted-spaced-path failure.
// (Native `type: http` config is NOT a valid claude_desktop_config.json form
// as of 2026-06 — Claude Desktop rejects it with "not a valid MCP server
// configuration and was skipped". The stdio bridge is required.)
config.mcpServers["igs-legacy-search"] = {
  command: "cmd",
  args: [
    "/c",
    "npx",
    "-y",
    "mcp-remote",
    mcpUrl,
    "--header",
    "Authorization: Bearer " + token
  ]
};
const tmp = configPath + ".tmp";
fs.writeFileSync(tmp, JSON.stringify(config, null, 2) + "\n", "utf-8");
fs.renameSync(tmp, configPath);
// Round-trip check.
const written = JSON.parse(fs.readFileSync(configPath, "utf-8"));
if (!written.mcpServers || !written.mcpServers["igs-legacy-search"]) {
  console.error("FAIL: post-write check missing igs-legacy-search");
  process.exit(3);
}
console.log("OK");
'@

$jsPath = Join-Path $env:TEMP ("igs-install-merge-{0}.js" -f ([guid]::NewGuid().ToString("N")))
Set-Content -LiteralPath $jsPath -Value $jsScript -Encoding UTF8

Write-Heading "Writing Claude Desktop config..."
$env:IGS_BEARER_TOKEN_NODE = $BearerToken
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
    $mergeOut = & node $jsPath $configPath $MCP_URL 2>&1
    $mergeExit = $LASTEXITCODE
} finally {
    Remove-Item Env:\IGS_BEARER_TOKEN_NODE -ErrorAction SilentlyContinue
    Remove-Item $jsPath -ErrorAction SilentlyContinue
    $ErrorActionPreference = $prevEAP
}
if ($mergeExit -ne 0 -or ($mergeOut -join "`n") -notmatch "OK") {
    Write-Err2 "Config write failed."
    Write-Host ("  Detail: {0}" -f ($mergeOut -join " | ")) -ForegroundColor Red
    exit 3
}
Write-OK ("Wrote {0}" -f $configPath)

Write-Host ""
Write-Host "Setup complete." -ForegroundColor Green
Write-Host ""
Write-Heading "Next steps:"
Write-Host "  1. Quit Claude Desktop completely (right-click system tray icon -> Quit -- closing the window isn't enough)."
Write-Host "  2. Reopen Claude Desktop."
Write-Host "  3. Try: `"Search for projects involving sulfuric acid corrosion testing`""
Write-Host ""
Write-Host "Re-running this command is safe -- it overwrites the igs-legacy-search entry in place." -ForegroundColor DarkGray
Write-Host ""
