# IGS Legacy Search - Quick Setup

Setup takes about 5 minutes. One command installs everything.

## Windows

Open **PowerShell** (click Start, type "PowerShell", click it) and paste:

```powershell
irm https://raw.githubusercontent.com/karl-kahn/igs-legacy-search-setup/main/bootstrap/setup.ps1 | iex
```

## Mac

Open **Terminal** (search for "Terminal" in Spotlight) and paste:

```bash
curl -fsSL https://raw.githubusercontent.com/karl-kahn/igs-legacy-search-setup/main/bootstrap/setup.sh | bash
```

## What it does

1. Installs Node.js (if needed)
2. Installs Claude Code CLI
3. Configures the IGS search server connection
4. Logs you in to your Anthropic account

## After setup

Type `claude` in the terminal, then try:

- "Search for projects involving sulfuric acid"
- "List all indexed projects"
- "Summarize project P-1074"
- "Find projects related to corrosion testing on steel pipelines"

## If something goes wrong

Re-running the setup command is safe — it skips anything already installed.

If you get stuck, just let us know and we'll walk through it together.
