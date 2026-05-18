# IGS Legacy Search - Setup

One-command setup for searching IGS Engineering's historical project archive using Claude.

## Prerequisites

Install these in order. Default settings are fine for all three.

- **Git for Windows** — https://git-scm.com/download/win
- **Node.js (LTS)** — https://nodejs.org/
- **Claude Desktop** — https://claude.ai/download

After installing, open a fresh **PowerShell** and confirm:

```powershell
git --version    # expect: git version 2.x.x
node --version   # expect: v20.x.x or v22.x.x
```

If either reports "command not found," close the PowerShell window and open a new one — the PATH update doesn't apply to a window that was open during install.

## Bearer token

Your team admin will share a bearer token with you. Keep it handy — `setup.ps1` will prompt for it. The token authenticates your Claude Desktop against the Legacy Search MCP server in Azure. Don't share it; if you suspect it's been exposed, ask your team admin to rotate it.

## Run the setup

```powershell
cd $env:USERPROFILE
git clone https://github.com/karl-kahn/igs-legacy-search-setup.git
cd igs-legacy-search-setup
.\setup.ps1
```

When prompted, paste the bearer token and press Enter.

The script will:

1. Prompt for the bearer token (or accept it via `-BearerToken "..."` if you'd rather pass it on the command line)
2. Verify Node.js is installed
3. Install the `mcp-remote` bridge globally
4. Configure Claude Desktop to connect to the Legacy Search server
5. Print the list of available tools

## After setup

1. Right-click the **Claude Desktop** icon in the system tray and choose **Quit** (a full quit, not just closing the window).
2. Reopen Claude Desktop.
3. Try:
   - "Search for projects involving sulfuric acid"
   - "List all indexed projects"
   - "Summarize project P-1074"
   - "Find images of erosion test coupons" *(filename search, new)*
   - "Write a technical memo about dew point corrosion findings"

## Troubleshooting

- **`git: command not found`** — you have a PowerShell window that was open before Git for Windows finished installing. Close it and open a new one.
- **`Claude Desktop config directory not found`** — Claude Desktop hasn't been opened yet. Open it once (sign in), close it, then re-run `.\setup.ps1`.
- **Setup said success but Claude Desktop shows no tools** — quit Claude Desktop from the system tray (not just close the window) and reopen.
- **Re-running** `.\setup.ps1` is safe — it'll update the Claude Desktop config in place. Pass `-BearerToken "..."` to skip the prompt.
- Anything else: email Karl at `karl@gsdat.work`.
