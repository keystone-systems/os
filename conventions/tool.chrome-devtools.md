## Chrome DevTools MCP

## MCP Server Configuration

1. The `chrome-devtools` MCP server is provisioned automatically by the keystone agent home-manager module when `chrome.mcp.enable = true` — no manual `.mcp.json` edits are required.
2. The server MUST use the Nix-built `chrome-devtools-mcp` binary directly. The binary is added to the agent's PATH via `home.packages` and its absolute store path is written into the global MCP configs (`~/.claude.json`, `~/.gemini/settings.json`, `~/.config/opencode/opencode.json`).
3. The `--browserUrl` argument MUST point to `http://127.0.0.1:<debugPort>` where `<debugPort>` is the agent's auto-assigned or explicit Chrome debug port (default: 9222).
4. When manually adding a `chrome-devtools` entry (e.g. per-project `.mcp.json` override), use the binary name directly — do NOT use `npx`:
   ```json
   {
     "chrome-devtools": {
       "command": "chrome-devtools-mcp",
       "args": ["--browserUrl", "http://127.0.0.1:9222"]
     }
   }
   ```

## Chrome Remote Debugging

5. The host system MUST provision a Chromium instance with `--remote-debugging-port=9222`.
6. Agents SHOULD use the Chrome DevTools MCP for web browsing, page inspection, and screenshot capture.
7. Agents MUST NOT launch their own browser instances — they MUST use the pre-provisioned Chromium.

## Usage

8. Agents MAY use Chrome DevTools to navigate to URLs, inspect page content, and take screenshots.
9. Agents SHOULD prefer Chrome DevTools over `WebFetch` when full page rendering or JavaScript execution is required.
10. Agents MUST NOT use Chrome DevTools to access authenticated services unless credentials are provided via their own vault.
