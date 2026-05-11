# IGS Legacy Search - Setup

One-command setup for searching IGS Engineering's historical project archive using Claude.

This repository is **private**. To use the setup script you need a GitHub account and to be added as a collaborator (ask Karl). The `gh` GitHub CLI handles authentication so that you can download the script from this private repo without juggling personal access tokens.

## Prerequisites

Install these in order. Default settings are fine for all four.

- **GitHub account** — sign up at https://github.com/signup, then send Karl your GitHub username. Karl will add you as a collaborator on this repo.
- **Git for Windows** (includes the `gh` GitHub CLI) — https://git-scm.com/download/win
- **Node.js (LTS)** — https://nodejs.org/
- **Claude Desktop** — https://claude.ai/download

After installing, open a fresh **PowerShell** and confirm:

```powershell
gh --version    # expect: gh version 2.x.x
node --version  # expect: v20.x.x or v22.x.x
```

If either reports "command not found," close the PowerShell window and open a new one — the PATH update doesn't apply to a window that was open during install.

## Authenticate the GitHub CLI

The setup script lives in a private repo. PowerShell needs to authenticate as you before it can fetch the script.

```powershell
gh auth login
```

Choose: `GitHub.com` -> `HTTPS` -> authenticate Git: `Y` -> `Login with a web browser`. Paste the one-time code into the browser when prompted. When the terminal reports `Logged in as your-username`, you're done.

Confirm:

```powershell
gh auth status
```

## Run the setup

Once you've been added as a collaborator (Karl will confirm) and `gh auth status` reports you're logged in:

```powershell
cd $env:USERPROFILE
gh repo clone karl-kahn/igs-legacy-search-setup
cd igs-legacy-search-setup
.\setup.ps1
```

This will:

1. Verify Node.js is installed
2. Install the `mcp-remote` bridge globally
3. Configure Claude Desktop to connect to the Legacy Search server
4. Print the list of available tools

## After setup

1. Right-click the **Claude Desktop** icon in the system tray and choose **Quit** (a full quit, not just closing the window).
2. Reopen Claude Desktop.
3. Try:
   - "Search for projects involving sulfuric acid"
   - "List all indexed projects"
   - "Summarize project P-1074"
   - "Find images of erosion test coupons" *(filename search, new)*
   - "Write a technical memo about dew point corrosion findings"

## CLI setup (advanced)

If you prefer the terminal interface, after `gh auth login`:

```powershell
$env:CLAUDE_SETUP_CONFIG="$env:USERPROFILE\igs-legacy-search-setup\claude-setup.json"
irm https://raw.githubusercontent.com/karl-kahn/claude-setup/main/setup.ps1 | iex
```

(The `claude-setup` repo is public, so `irm` works directly there. The path above points at the local copy of `claude-setup.json` you got from `gh repo clone`.)

Then type `claude` in the terminal to start.

## Troubleshooting

- **`irm` returns 404** — the old README suggested fetching `setup.ps1` directly via `irm`. That fails on this private repo. Use `gh repo clone` (as above) instead.
- **`gh: command not found`** — you have a PowerShell window that was open before Git for Windows finished installing. Close it and open a new one.
- **`Claude Desktop config directory not found`** — Claude Desktop hasn't been opened yet. Open it once (sign in), close it, then re-run `.\setup.ps1`.
- **Setup said success but Claude Desktop shows no tools** — quit Claude Desktop from the system tray (not just close the window) and reopen.
- Anything else: email Karl at `karl@gsdat.work`.

Re-running `.\setup.ps1` is safe — it'll update the Claude Desktop config in place.
