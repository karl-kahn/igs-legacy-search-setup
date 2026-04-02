#!/usr/bin/env bash
# IGS Legacy Search Bootstrap - Mac
# One-command setup: installs dependencies, configures Claude Code + MCP server.
# Safe to re-run — skips anything already installed.
#
# Failure modes handled:
#   - No Homebrew (installs it)
#   - No Node.js (installs via brew or direct download)
#   - Node.js too old (upgrades)
#   - No Claude Code CLI (installs via official installer or npm)
#   - Claude Desktop installed but no CLI (detects and installs CLI alongside)
#   - Existing .claude.json malformed (backs up and recreates)
#   - No python3 (falls back to manual JSON construction)
#   - Rosetta not installed on Apple Silicon (installs it)

set -euo pipefail

MCP_URL="https://malone.taildf301e.ts.net:8443/mcp"
MCP_TOKEN="2KL2PzA9eKNSFdmsDY1j0aB5R_aEBMFM8arFCJicgxg"
STEP=0
TOTAL_STEPS=4

# --- Helpers ---
show_step() {
    STEP=$((STEP + 1))
    echo ""
    echo "  [$STEP/$TOTAL_STEPS] $1"
}

show_ok()     { echo "         ✓ $1"; }
show_action() { echo "         $1"; }
show_warn()   { echo "         ⚠ $1"; }
show_error()  { echo "         ✗ $1"; }

ensure_brew() {
    if command -v brew &>/dev/null; then return 0; fi
    echo "         Installing Homebrew... (may ask for your password)"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Handle Apple Silicon vs Intel
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        # Persist for future shells
        SHELL_RC="$HOME/.zprofile"
        if ! grep -q 'homebrew' "$SHELL_RC" 2>/dev/null; then
            echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$SHELL_RC"
        fi
    elif [[ -f /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
    if ! command -v brew &>/dev/null; then
        show_error "Homebrew installed but not in PATH."
        show_warn "Close this terminal, open a new one, and run the setup command again."
        exit 1
    fi
}

write_json_config() {
    # Writes MCP config to .claude.json, merging with existing content.
    # Uses python3 if available (reliable JSON handling), otherwise constructs manually.
    local config_path="$HOME/.claude.json"

    if command -v python3 &>/dev/null; then
        python3 << 'PYEOF'
import json, os, sys

config_path = os.path.expanduser("~/.claude.json")
mcp_url = os.environ.get("_MCP_URL", "")
mcp_token = os.environ.get("_MCP_TOKEN", "")

try:
    with open(config_path) as f:
        config = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    # Back up if it exists but is malformed
    if os.path.exists(config_path):
        import shutil
        shutil.copy2(config_path, config_path + ".bak")
        print("         ⚠ Existing .claude.json was malformed — backed up.", file=sys.stderr)
    config = {}

config.setdefault("mcpServers", {})
config["mcpServers"]["igs-legacy-search"] = {
    "type": "http",
    "url": mcp_url,
    "headers": {"Authorization": f"Bearer {mcp_token}"}
}

with open(config_path, "w") as f:
    json.dump(config, f, indent=2)
PYEOF
    else
        # No python3 — write directly (loses any existing config)
        if [[ -f "$config_path" ]]; then
            cp "$config_path" "${config_path}.bak"
            show_warn "Backed up existing .claude.json (no python3 for merge)."
        fi
        cat > "$config_path" << JSONEOF
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
    fi
}

# --- Banner ---
echo ""
echo "  ========================================"
echo "  IGS Legacy Project Search - Setup"
echo "  ========================================"
echo ""
echo "  This will install and configure everything"
echo "  you need. Takes about 5 minutes."

# ===================================================================
# STEP 1: Node.js
# ===================================================================
show_step "Node.js"

if command -v node &>/dev/null; then
    NODE_VERSION=$(node --version | sed 's/^v//')
    NODE_MAJOR=$(echo "$NODE_VERSION" | cut -d. -f1)
    if [[ "$NODE_MAJOR" -ge 18 ]]; then
        show_ok "Ready (v$NODE_VERSION)."
    else
        show_action "Found v$NODE_VERSION but need v18+. Upgrading..."
        ensure_brew
        brew install node@22 2>/dev/null || brew upgrade node 2>/dev/null || true
        if command -v node &>/dev/null; then
            show_ok "Upgraded to $(node --version)."
        else
            show_error "Could not upgrade Node.js."
            show_warn "Please install from https://nodejs.org (LTS) and run this script again."
            exit 1
        fi
    fi
else
    show_action "Installing Node.js..."
    ensure_brew
    brew install node@22 2>/dev/null || brew install node 2>/dev/null || true

    # Homebrew node@22 is keg-only — may need linking
    if ! command -v node &>/dev/null; then
        brew link --overwrite node@22 2>/dev/null || true
        # Or add to PATH
        NODE_BREW_PATH="$(brew --prefix)/opt/node@22/bin"
        if [[ -d "$NODE_BREW_PATH" ]]; then
            export PATH="$NODE_BREW_PATH:$PATH"
        fi
    fi

    if ! command -v node &>/dev/null; then
        show_error "Could not install Node.js."
        show_warn "Please install from https://nodejs.org (LTS) and run this script again."
        exit 1
    fi
    show_ok "Installed ($(node --version))."
fi

# ===================================================================
# STEP 2: Claude Code CLI
# ===================================================================
show_step "Claude Code"

# Detect Claude Desktop (user may have this but not the CLI)
CLAUDE_DESKTOP=false
if [[ -d "/Applications/Claude.app" ]] || [[ -d "$HOME/Applications/Claude.app" ]]; then
    CLAUDE_DESKTOP=true
fi

if command -v claude &>/dev/null; then
    show_ok "Ready."
    if [[ "$CLAUDE_DESKTOP" == "true" ]]; then
        show_ok "Claude Desktop also detected — both work fine together."
    fi
else
    if [[ "$CLAUDE_DESKTOP" == "true" ]]; then
        show_action "Claude Desktop detected but CLI not installed."
        show_action "Installing Claude Code CLI alongside Desktop..."
    else
        show_action "Installing Claude Code CLI..."
    fi

    installed=false

    # Primary: official installer
    curl -fsSL https://claude.ai/install.sh 2>/dev/null | sh 2>/dev/null && true
    export PATH="$HOME/.local/bin:$HOME/.claude/bin:$PATH"
    if command -v claude &>/dev/null; then installed=true; fi

    # Fallback: npm global
    if [[ "$installed" == "false" ]]; then
        show_action "Trying npm install..."
        npm install -g @anthropic-ai/claude-code 2>/dev/null || true
        if command -v claude &>/dev/null; then installed=true; fi
    fi

    if [[ "$installed" == "false" ]]; then
        show_error "Could not install Claude Code."
        show_warn "Please try manually: npm install -g @anthropic-ai/claude-code"
        show_warn "then run this script again."
        exit 1
    fi
    show_ok "Installed."
fi

# ===================================================================
# STEP 3: Configuration
# ===================================================================
show_step "Configuration"

# --- MCP server config ---
export _MCP_URL="$MCP_URL"
export _MCP_TOKEN="$MCP_TOKEN"
write_json_config
unset _MCP_URL _MCP_TOKEN
show_ok "MCP server configured."

# ===================================================================
# STEP 4: Verification
# ===================================================================
show_step "Verification"
all_good=true

# Check Node
v=$(node --version 2>/dev/null || echo "")
if [[ -n "$v" ]]; then
    show_ok "Node.js $v"
else
    show_error "Node.js: NOT FOUND"
    all_good=false
fi

# Check Claude Code
if command -v claude &>/dev/null; then
    show_ok "Claude Code: installed"
else
    show_error "Claude Code: NOT FOUND"
    all_good=false
fi

# Check MCP config
config_path="$HOME/.claude.json"
if [[ -f "$config_path" ]]; then
    if command -v python3 &>/dev/null; then
        mcp_ok=$(python3 -c "
import json
try:
    c = json.load(open('$config_path'))
    url = c.get('mcpServers',{}).get('igs-legacy-search',{}).get('url','')
    print('yes' if url == '$MCP_URL' else 'no')
except: print('no')
")
        if [[ "$mcp_ok" == "yes" ]]; then
            show_ok "MCP server: configured"
        else
            show_error "MCP server: config missing or wrong"
            all_good=false
        fi
    else
        show_ok "MCP server: config file exists (could not verify without python3)"
    fi
else
    show_error "MCP server: .claude.json not found"
    all_good=false
fi

# --- Result ---
echo ""
if [[ "$all_good" == "true" ]]; then
    echo "  ========================================"
    echo "  ✓ Setup complete! Everything looks good."
    echo "  ========================================"
    echo ""
    echo "  To start searching, type:"
    echo ""
    echo "    claude"
    echo ""
    echo "  It will ask you to log in on first launch."
    echo "  Sign in with your Anthropic account in the"
    echo "  browser, then come back to the terminal."
    echo ""
    echo "  Then try:"
    echo '    "Search for projects involving sulfuric acid"'
    echo '    "List all indexed projects"'
    echo '    "Summarize project P-1074"'
    echo ""
else
    echo "  ========================================"
    echo "  ✗ Setup had issues (see above)."
    echo "  ========================================"
    echo ""
    show_warn "Try closing this terminal, opening a new one,"
    show_warn "and running the setup command again."
    show_warn ""
    show_warn "If it still fails, send a screenshot to your contact"
    show_warn "and we'll get it sorted out."
    echo ""
fi
