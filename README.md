# IGS Legacy Search - Setup

One-command setup for searching IGS Engineering's historical project archive using Claude.

## Windows

Open **PowerShell** (click Start, type "PowerShell", click it) and paste:

```powershell
$env:CLAUDE_SETUP_CONFIG="https://raw.githubusercontent.com/karl-kahn/igs-legacy-search-setup/main/claude-setup.json"; irm https://raw.githubusercontent.com/karl-kahn/claude-setup/main/setup.ps1 | iex
```

## Mac

Open **Terminal** (search for "Terminal" in Spotlight) and paste:

```bash
CLAUDE_SETUP_CONFIG="https://raw.githubusercontent.com/karl-kahn/igs-legacy-search-setup/main/claude-setup.json" bash -c "$(curl -fsSL https://raw.githubusercontent.com/karl-kahn/claude-setup/main/setup.sh)"
```

## After setup

Type `claude` in the terminal, then try:

- "Search for projects involving sulfuric acid"
- "List all indexed projects"
- "Summarize project P-1074"
- "Find projects related to corrosion testing on steel pipelines"

## Troubleshooting

Re-running the setup command is safe — it skips anything already installed. If something goes wrong, close the terminal, open a new one, and run the command again.
