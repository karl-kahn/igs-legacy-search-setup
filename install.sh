#!/usr/bin/env bash
# IGS Legacy Search -- Claude Desktop one-liner installer (macOS)
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/karl-kahn/igs-legacy-search-setup/main/install.sh | bash
#   curl -sSL https://raw.githubusercontent.com/karl-kahn/igs-legacy-search-setup/main/install.sh | bash -s -- -t <BEARER_TOKEN>
#   IGS_BEARER_TOKEN=xxx ./install.sh
#
# What it does:
#   1. Verifies Node.js >= 18.
#   2. Prompts (masked) for the bearer token if not supplied.
#   3. Verifies the token against the MCP server (HTTP 200 = good, 401 = bad).
#   4. Merges an "igs-legacy-search" entry into ~/Library/Application Support/Claude/claude_desktop_config.json
#      preserving any other mcpServers entries already there.
#   5. Verifies "npx mcp-remote --help" runs (dry-run of the bridge).
#   6. Prints the next-steps message.
#
# Exit codes:
#   0 success; 1 user/environment error; 2 token rejected by server; 3 unexpected.

set -eu

# Cross-shell tty redirect. When installed via `curl ... | bash`, stdin is the
# pipe so we have to talk to the terminal directly for prompts.
if [ -t 0 ]; then
  TTY_IN=/dev/stdin
else
  TTY_IN=/dev/tty
fi

MCP_URL="https://igs-legacy-search-app.calmrock-c14844e2.eastus.azurecontainerapps.io/mcp"

color() { printf '\033[%sm%s\033[0m' "$1" "$2"; }
cyan()  { color "0;36" "$1"; }
green() { color "0;32" "$1"; }
yellow(){ color "0;33" "$1"; }
red()   { color "0;31" "$1"; }

say()  { printf '%s\n' "$*"; }
ok()   { say "$(green "OK")   $*"; }
warn() { say "$(yellow "WARN") $*"; }
err()  { say "$(red "ERR")  $*" >&2; }

# Parse args. -t/--token <value>.
BEARER_TOKEN="${IGS_BEARER_TOKEN:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    -t|--token)
      BEARER_TOKEN="${2:-}"; shift 2 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)
      err "Unknown arg: $1"; exit 1 ;;
  esac
done

say ""
say "$(cyan "=== IGS Legacy Search -- Claude Desktop Setup ===")"
say ""

# --- 1. Node.js check ------------------------------------------------------
if ! command -v node >/dev/null 2>&1; then
  err "Node.js is not installed."
  say "Install the LTS build from $(cyan https://nodejs.org/), then re-run this command."
  exit 1
fi
NODE_VERSION_RAW="$(node --version)"
NODE_MAJOR="$(printf '%s' "$NODE_VERSION_RAW" | sed -E 's/^v([0-9]+).*/\1/')"
if [ -z "$NODE_MAJOR" ] || [ "$NODE_MAJOR" -lt 18 ] 2>/dev/null; then
  err "Node.js $NODE_VERSION_RAW is too old. Need v18 or newer."
  say "Install the LTS build from $(cyan https://nodejs.org/), then re-run."
  exit 1
fi
ok "Node.js $NODE_VERSION_RAW"

# --- 2. mcp-remote reachability check (dry run) ----------------------------
# `mcp-remote` has no `--help` flag (it treats argv[0] as a URL and crashes
# with "Invalid URL" if you try). Instead resolve the package against the
# npm registry -- catches "registry blocked" / "no network" failures here
# instead of the first time Claude Desktop tries to spawn the bridge.
say ""
say "$(cyan "Confirming mcp-remote is reachable on npm...")"
if MCP_REMOTE_VER="$(npm view mcp-remote version 2>/tmp/igs-npm-view.log)"; then
  ok "mcp-remote $MCP_REMOTE_VER available via npm"
else
  warn "npm view mcp-remote failed. Log: /tmp/igs-npm-view.log"
  warn "Setup will continue, but if Claude Desktop fails to launch the tool, this is the first place to look."
fi

# --- 3. Token acquisition --------------------------------------------------
if [ -z "$BEARER_TOKEN" ]; then
  say ""
  say "$(yellow "Paste the bearer token your team admin sent you, then press Enter.")"
  say "(Input is masked -- you won't see characters as you type.)"
  printf "  Token: "
  # bash 3.2 (macOS stock) supports `read -s`.
  IFS= read -rs BEARER_TOKEN < "$TTY_IN" || true
  printf '\n'
fi
# Strip whitespace + trailing newlines.
BEARER_TOKEN="$(printf '%s' "$BEARER_TOKEN" | tr -d '[:space:]')"
if [ -z "$BEARER_TOKEN" ]; then
  err "No bearer token entered. Cannot continue."
  exit 1
fi

# --- 4. Verify token against MCP server ------------------------------------
say ""
say "$(cyan "Verifying token against the MCP server...")"
TMP_BODY="$(mktemp -t igs-mcp-XXXXXX)"
trap 'rm -f "$TMP_BODY"' EXIT
HTTP_CODE="$(
  curl -sS -o "$TMP_BODY" -w '%{http_code}' \
    "$MCP_URL" \
    -X POST \
    -H "Authorization: Bearer $BEARER_TOKEN" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"igs-setup","version":"0"}}}' \
    || echo "000"
)"
case "$HTTP_CODE" in
  200)
    ok "Token verified (HTTP 200)."
    ;;
  401|403)
    err "Server rejected the token (HTTP $HTTP_CODE). It's wrong, expired, or copy-paste truncated."
    say "Ask your team admin for a fresh token, then re-run."
    exit 2
    ;;
  000)
    err "Could not reach the MCP server. Check internet/VPN/firewall."
    exit 1
    ;;
  *)
    err "Unexpected HTTP $HTTP_CODE from the MCP server. Body saved to $TMP_BODY for debugging."
    trap - EXIT
    exit 3
    ;;
esac

# --- 5. Merge into Claude Desktop config -----------------------------------
CLAUDE_DIR="${IGS_CLAUDE_DIR:-$HOME/Library/Application Support/Claude}"
CONFIG_PATH="$CLAUDE_DIR/claude_desktop_config.json"

if [ ! -d "$CLAUDE_DIR" ]; then
  say ""
  warn "Claude Desktop config directory not found at:"
  say "  $CLAUDE_DIR"
  say "That usually means Claude Desktop hasn't been launched yet."
  say "Install/open Claude Desktop once ($(cyan https://claude.ai/download)), sign in, quit, then re-run this command."
  exit 1
fi

# Back up existing config (if any) before mutating.
if [ -f "$CONFIG_PATH" ]; then
  BACKUP_PATH="${CONFIG_PATH}.bak.$(date +%Y%m%d-%H%M%S)"
  cp "$CONFIG_PATH" "$BACKUP_PATH"
  ok "Backed up existing config to $BACKUP_PATH"
fi

# JSON-aware merge in python3 (always present on macOS). Token comes through
# the environment, NOT argv -- avoids both shell-escape gymnastics and
# leaking via `ps`.
export IGS_BEARER_TOKEN_PY="$BEARER_TOKEN"
/usr/bin/python3 - "$CONFIG_PATH" "$MCP_URL" <<'PY'
import json, os, sys

config_path, mcp_url = sys.argv[1], sys.argv[2]
token = os.environ.get("IGS_BEARER_TOKEN_PY", "")
if not token:
    print("FAIL: no token in env", file=sys.stderr)
    sys.exit(1)

config = {}
if os.path.exists(config_path):
    try:
        with open(config_path, "r", encoding="utf-8") as f:
            raw = f.read().strip()
        if raw:
            config = json.loads(raw)
    except Exception as e:
        print(f"FAIL: existing config at {config_path} is not valid JSON ({e}). "
              "Open it, fix or empty it, then re-run.", file=sys.stderr)
        sys.exit(2)

if not isinstance(config, dict):
    print("FAIL: top-level config is not a JSON object", file=sys.stderr)
    sys.exit(2)

servers = config.get("mcpServers")
if not isinstance(servers, dict):
    servers = {}

servers["igs-legacy-search"] = {
    "command": "npx",
    "args": [
        "-y",
        "mcp-remote",
        mcp_url,
        "--header",
        "Authorization: Bearer " + token,
    ],
}
config["mcpServers"] = servers

tmp_path = config_path + ".tmp"
with open(tmp_path, "w", encoding="utf-8") as f:
    json.dump(config, f, indent=2)
    f.write("\n")
os.replace(tmp_path, config_path)
print("OK")
PY
unset IGS_BEARER_TOKEN_PY
ok "Wrote $CONFIG_PATH"

# Quick sanity: confirm our entry survived the write.
if ! /usr/bin/python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if 'igs-legacy-search' in d.get('mcpServers',{}) else 1)" "$CONFIG_PATH"; then
  err "Post-write check failed -- igs-legacy-search entry is not in the config."
  exit 3
fi

say ""
say "$(green "Setup complete.")"
say ""
say "$(cyan "Next steps:")"
say "  1. Quit Claude Desktop completely (Cmd+Q -- closing the window isn't enough)."
say "  2. Reopen Claude Desktop."
say "  3. Try: \"Search for projects involving sulfuric acid corrosion testing\""
say ""
say "Re-running this command is safe -- it overwrites the igs-legacy-search entry in place."
say ""
