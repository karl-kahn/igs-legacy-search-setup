# IGS Legacy Search - Setup

One-command setup for searching IGS Engineering's historical project archive using Claude.

## Prerequisites

- **Node.js** — download from https://nodejs.org/ (LTS version)
- **Claude Desktop** — download from https://claude.ai/download

## Windows — Claude Desktop (recommended)

Open **PowerShell** and paste:

```powershell
irm https://raw.githubusercontent.com/karl-kahn/igs-legacy-search-setup/main/setup.ps1 | iex
```

This will:
1. Verify Node.js is installed
2. Download the mcp-remote bridge
3. Configure Claude Desktop to connect to the Legacy Search server
4. Tell you to restart Claude Desktop

## After Setup

1. Close and reopen Claude Desktop
2. Switch to the **Code** pane (not Chat)
3. Try:
   - "Search for projects involving sulfuric acid"
   - "List all indexed projects"
   - "Summarize project P-1074"
   - "Write a technical memo about dew point corrosion findings"

## CLI Setup (advanced)

If you prefer the terminal interface, open PowerShell and paste:

```powershell
$env:CLAUDE_SETUP_CONFIG="https://raw.githubusercontent.com/karl-kahn/igs-legacy-search-setup/main/claude-setup.json"; irm https://raw.githubusercontent.com/karl-kahn/claude-setup/main/setup.ps1 | iex
```

Then type `claude` in the terminal to start.

## Troubleshooting

Re-running the setup command is safe. If something goes wrong, close the terminal, open a new one, and run the command again.
