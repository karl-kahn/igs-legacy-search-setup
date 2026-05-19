# Known Limitations

Environment + corporate-IT edge cases the installer can't fully paper over.

## 1. Corporate proxies / TLS interception

Both installers fetch from `raw.githubusercontent.com` and the Azure Container App. If your corp proxy intercepts TLS without a trusted root cert in the user's trust store, the one-liner will fail at the `curl` / `irm` step before any user-visible progress.

**Workaround:** clone the repo over SSH/HTTPS instead, then run `./install.sh` or `.\install.ps1` locally. Either entry point accepts the same flags.

## 2. `npm install --global mcp-remote` permissions

The new one-liner installer uses `npx -y mcp-remote` (per-user cache), avoiding the `--global` install entirely. If a user has an old version of the legacy `setup.ps1` configured, it may still attempt `npm i -g` which can fail on locked-down Windows. Direct them to the new `install.ps1` one-liner.

## 3. PowerShell execution policy

`iex (irm ...)` does not write a file to disk, so it isn't subject to `Set-ExecutionPolicy`-style script-signing checks on Win10/11 in their default `RemoteSigned` state. Some hardened corporate machines run `AllSigned` policy, which **will** block this. In that case: download the script manually, sign with the org's code-signing cert, or run with `-ExecutionPolicy Bypass` in a one-shot:

```powershell
powershell -ExecutionPolicy Bypass -Command "iex (irm https://raw.githubusercontent.com/karl-kahn/igs-legacy-search-setup/main/install.ps1)"
```

## 4. Antivirus quarantine

Some Windows AV products (notably Sophos, Trend) flag arbitrary `iex`-from-URL patterns as suspicious. The script doesn't do anything questionable, but the heuristic won't know that. If the AV blocks, fall back to the legacy `git clone + setup.ps1` flow, which downloads a file the AV can inspect statically.

## 5. macOS Catalina (10.15) and older

The Mac installer relies on `/usr/bin/python3`, which ships with the Xcode Command Line Tools on macOS 10.15+. On a truly stock 10.15 box with no developer tools the first invocation pops a GUI prompt asking to install CLT, which can confuse end users. macOS 11+ ships `python3` reliably.

## 6. Node.js installed via `nvm` (Mac)

If the user installed Node.js via `nvm` and the installer runs in a non-login shell (e.g. some IDE terminals), `node` may not be on PATH despite being installed. `which node` from a fresh Terminal.app window is the diagnostic. The fix is for the user to open a normal Terminal.app and re-run.

## 7. Token verify uses live MCP server

The `initialize` probe makes a real round-trip to the Azure Container App. If the app is cold-starting or scaled to zero, the first POST can take up to ~10 s. The installer doesn't retry; if it times out the user can re-run safely.

## 8. No automatic mcp-remote pinning

The installer writes `"npx", "-y", "mcp-remote"` which resolves to the latest published version every time Claude Desktop spawns the bridge. If a future `mcp-remote` release introduces a breaking change, all installs pick it up simultaneously. We'll add explicit pinning (`mcp-remote@x.y.z`) if/when that becomes a problem.
