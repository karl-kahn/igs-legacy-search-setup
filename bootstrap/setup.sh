#!/usr/bin/env bash
# IGS Legacy Search Bootstrap - Mac
# One-command setup: installs Node.js + Claude Code, configures MCP server.
# Usage: curl ... | bash
set -euo pipefail

MCP_URL="https://malone.taildf301e.ts.net:8443/mcp"
MCP_TOKEN="2KL2PzA9eKNSFdmsDY1j0aB5R_aEBMFM8arFCJicgxg"

echo ""
echo "  IGS Legacy Project Search - Setup"
echo "  Preparing your workspace..."
echo ""

# --- Node.js ---
if command -v node &>/dev/null; then
    NODE_VERSION=$(node --version | sed 's/^v//')
    NODE_MAJOR=$(echo "$NODE_VERSION" | cut -d. -f1)
    if [[ "$NODE_MAJOR" -ge 18 ]]; then
        echo "  Node.js is ready (v$NODE_VERSION)."
    else
        echo "  Found Node.js v$NODE_VERSION but need v18+. Installing..."
        if command -v brew &>/dev/null; then
            brew install node@22
        else
            echo "  Please update Node.js from https://nodejs.org (LTS version) and run this script again."
            exit 1
        fi
        echo "  Node.js updated."
    fi
else
    echo "  Installing Node.js..."
    if command -v brew &>/dev/null; then
        brew install node@22
    else
        # Install Homebrew first
        echo "  Installing Homebrew first... (will ask for your password)"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        if [[ -f /opt/homebrew/bin/brew ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [[ -f /usr/local/bin/brew ]]; then
            eval "$(/usr/local/bin/brew shellenv)"
        fi
        brew install node@22
    fi
    if ! command -v node &>/dev/null; then
        echo ""
        echo "  Could not install Node.js automatically."
        echo "  Please install from https://nodejs.org (LTS version) and run this script again."
        exit 1
    fi
    echo "  Node.js installed."
fi

# --- Claude Code ---
if command -v claude &>/dev/null; then
    echo "  Claude Code is already installed."
else
    echo "  Installing Claude Code..."
    curl -fsSL https://claude.ai/install.sh | sh
    export PATH="$HOME/.local/bin:$HOME/.claude/bin:/usr/local/bin:$PATH"

    if ! command -v claude &>/dev/null; then
        echo ""
        echo "  Installation completed but 'claude' command not found."
        echo "  Please close this terminal, open a new one, and run this script again."
        exit 1
    fi
    echo "  Claude Code installed."
fi

# --- MCP server configuration ---
echo "  Configuring search server..."
CONFIG_PATH="$HOME/.claude.json"
MCP_CONFIG=$(cat <<JSONEOF
{
  "mcpServers": {
    "igs-legacy-search": {
      "type": "http",
      "url": "$MCP_URL",
      "headers": {
        "Authorization": "Bearer $MCP_TOKEN"
      }
    }
  }
}
JSONEOF
)

if [[ -f "$CONFIG_PATH" ]]; then
    # Merge into existing config
    if command -v python3 &>/dev/null; then
        python3 -c "
import json, sys
try:
    with open('$CONFIG_PATH') as f:
        config = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    config = {}
config.setdefault('mcpServers', {})
config['mcpServers']['igs-legacy-search'] = {
    'type': 'http',
    'url': '$MCP_URL',
    'headers': {'Authorization': 'Bearer $MCP_TOKEN'}
}
with open('$CONFIG_PATH', 'w') as f:
    json.dump(config, f, indent=2)
"
    else
        # No python3 -- back up and overwrite
        cp "$CONFIG_PATH" "${CONFIG_PATH}.bak"
        echo "$MCP_CONFIG" > "$CONFIG_PATH"
    fi
else
    echo "$MCP_CONFIG" > "$CONFIG_PATH"
fi
echo "  Server configured."

# --- Login ---
echo ""
echo "  Launching Claude Code login..."
echo "  A browser window will open. Sign in with your Anthropic account."
echo ""
claude login 2>/dev/null || true

# --- Done ---
echo ""
echo "  ======================================================="
echo "  Setup complete!"
echo ""
echo "  To start searching, type:"
echo ""
echo "    claude"
echo ""
echo "  Then try:"
echo '    "Search for projects involving sulfuric acid"'
echo '    "List all indexed projects"'
echo '    "Summarize project P-1074"'
echo "  ======================================================="
echo ""
