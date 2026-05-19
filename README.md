# IGS Legacy Search -- Setup

One-command setup to connect Claude Desktop to the IGS Legacy Project Search MCP server.

## Prerequisites

- **Claude Desktop** -- https://claude.ai/download (open it once, sign in, quit, then run the installer).
- **Node.js v18 or newer** -- https://nodejs.org/ (LTS build is fine; needed for the `mcp-remote` bridge).
- A **bearer token** from your team admin (Karl). Paste it when the installer prompts.

The installer checks Node.js for you; if it's missing it tells you where to grab it and exits cleanly.

## Install -- one command

### macOS

```bash
curl -sSL https://raw.githubusercontent.com/karl-kahn/igs-legacy-search-setup/main/install.sh | bash
```

You'll be prompted for the bearer token (input is masked). To skip the prompt:

```bash
curl -sSL https://raw.githubusercontent.com/karl-kahn/igs-legacy-search-setup/main/install.sh | bash -s -- -t "<paste-token-here>"
```

### Windows (PowerShell 5.1+)

```powershell
iex (irm https://raw.githubusercontent.com/karl-kahn/igs-legacy-search-setup/main/install.ps1)
```

You'll be prompted for the bearer token (input is masked). To skip the prompt:

```powershell
$env:IGS_BEARER_TOKEN = "<paste-token-here>"; iex (irm https://raw.githubusercontent.com/karl-kahn/igs-legacy-search-setup/main/install.ps1)
```

## What just happened

The installer:

1. Verified Node.js >= 18 is on your PATH.
2. Ran `npx -y mcp-remote --help` to download/cache the bridge and confirm it works.
3. Asked the MCP server `initialize` with your bearer token -- a 200 means the token is valid, 401 means it isn't.
4. Backed up your existing `claude_desktop_config.json` (if any) with a timestamp suffix.
5. Merged an `igs-legacy-search` entry into `mcpServers`, preserving every other server you already had configured.
6. Verified the entry survived the write.

Config paths:

- macOS: `~/Library/Application Support/Claude/claude_desktop_config.json`
- Windows: `%APPDATA%\Claude\claude_desktop_config.json`

## After install

1. Quit Claude Desktop **completely** -- the config is only re-read on cold launch.
   - macOS: `Cmd+Q` (closing the window with red-dot isn't enough).
   - Windows: right-click the system tray icon -> Quit.
2. Reopen Claude Desktop.
3. Try a query:
   - "Search for projects involving sulfuric acid corrosion testing"
   - "List all indexed projects"
   - "Summarize project P-1074"
   - "What's the status of the most recent ingest run?"

## Re-running

Safe and idempotent. Re-runs overwrite only the `igs-legacy-search` entry; other `mcpServers` and a backup of the previous config are preserved.

## Troubleshooting

- **`401` during token verify** -- token is wrong, expired, or got truncated on copy-paste. Ask your team admin to re-share.
- **`Claude Desktop config directory not found`** -- Claude Desktop hasn't been launched yet on this machine. Open it once, sign in, quit, then re-run the installer.
- **Setup said success but Claude Desktop shows no tools** -- you closed the window instead of quitting. Quit fully (`Cmd+Q` / tray-quit), reopen.
- **`Node.js is not installed`** but you just installed it -- on Windows the new PATH only applies to PowerShell windows opened *after* the Node installer finishes. Close this window and open a fresh one.
- **`Could not reach the MCP server`** -- corporate VPN/firewall is blocking `*.azurecontainerapps.io`. Karl + IT.
- Anything else: email Karl at `karl@gsdat.work`.

## Manual fallback (the long way)

The legacy `setup.ps1` (clone-and-run flow) is still in this repo. The new one-liner is preferred -- the old flow remains as a fallback if your environment blocks `irm` / `iex` against raw.githubusercontent.com.

See `KNOWN_LIMITATIONS.md` for environment caveats we know about.
