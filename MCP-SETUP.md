# MCP Server Setup for macOS Development

Run these commands **once** before your first Claude Code session. They register the servers in your Claude Code configuration so they start automatically every session.

## 1. XcodeBuildMCP

Build, test, simulator, device deployment, LLDB debugging, UI automation. Works without Xcode running.

```bash
claude mcp add XcodeBuildMCP -s user -- npx -y xcodebuildmcp@latest mcp
```

- `-s user` makes it global (available in every project)
- Requires Node.js / npx
- 59 tools available after registration
- Source: https://github.com/getsentry/XcodeBuildMCP

### Optional: disable telemetry

```bash
claude mcp add XcodeBuildMCP -s user -e XCODEBUILDMCP_SENTRY_DISABLED=true -- npx -y xcodebuildmcp@latest mcp
```

### Alternative: install via Homebrew first

```bash
brew tap getsentry/xcodebuildmcp
brew install xcodebuildmcp
claude mcp add XcodeBuildMCP -s user -- xcodebuildmcp mcp
```

---

## 2. Apple Xcode MCP Bridge

File operations, live diagnostics, documentation search (including WWDC transcripts), Swift REPL, SwiftUI Preview rendering. Requires a running Xcode instance with your project open.

```bash
claude mcp add --transport stdio xcode -- xcrun mcpbridge
```

### Prerequisites

- Xcode 26.3 or later
- Enable MCP in Xcode: Settings → Intelligence → enable MCP server
- Xcode must be running with your project open during the session

---

## 3. Xcode Agent Config (inside Xcode only)

If you're using Claude Agent **inside Xcode** (not from the CLI), MCP servers are configured in a separate file. Xcode does not inherit your CLI MCP settings.

Config path:
```
~/Library/Developer/Xcode/CodingAssistant/ClaudeAgentConfig/.claude.json
```

Example adding XcodeBuildMCP to Xcode's agent:
```json
{
  "mcpServers": {
    "XcodeBuildMCP": {
      "command": "/bin/zsh",
      "args": [
        "-lc",
        "PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin; export NVM_DIR=\"$HOME/.nvm\"; [ -s \"$NVM_DIR/nvm.sh\" ] && . \"$NVM_DIR/nvm.sh\"; nvm use --silent >/dev/null 2>&1 || true; npx -y xcodebuildmcp@latest mcp"
      ]
    }
  }
}
```

Note the explicit PATH setup — Xcode's agent runs in a restricted environment that does not inherit your shell config.

---

## 4. CLI Tools for Asset Pipeline

These are not MCP servers — they are command-line tools that Claude Code calls directly via bash for SVG processing, icon generation, and landing page asset creation. Install them once.

### Required

**librsvg** — SVG to PNG conversion (handles Illustrator SVGs reliably):
```bash
brew install librsvg
```
Provides `rsvg-convert`. This is the primary SVG renderer. `sips` (built into macOS) does NOT support SVG input.

**svgo** — SVG optimizer (strips Illustrator metadata, reduces file size):
```bash
npm install -g svgo
```
Cleans `xmlns:i`, `xmlns:x`, `i:pgf`, embedded Illustrator data, and other bloat from exported SVGs before rendering or web embedding.

### Built into macOS (no install needed)

- **`sips`** — resizes PNGs to icon sizes (16×16 through 512×512@2x)
- **`iconutil`** — packages a `.iconset` folder into a `.icns` file

### Optional

**ImageMagick** — advanced image manipulation (compositing, backgrounds, shadows, format conversion):
```bash
brew install imagemagick
```
Only needed if you want to composite SVGs onto backgrounds, add effects, or create marketing mockup images. Not required for the basic SVG → icon pipeline.

### Verify all tools

Run this after installing:
```bash
echo "--- Asset Pipeline Tools ---"
which rsvg-convert && echo "rsvg-convert: OK" || echo "rsvg-convert: MISSING (brew install librsvg)"
which svgo && echo "svgo: OK" || echo "svgo: MISSING (npm install -g svgo)"
which sips && echo "sips: OK" || echo "sips: MISSING (should be built into macOS)"
which iconutil && echo "iconutil: OK" || echo "iconutil: MISSING (should be built into macOS)"
which magick && echo "ImageMagick: OK (optional)" || echo "ImageMagick: not installed (optional)"
```

---

## Verification

After registering, confirm your servers are active:

```bash
# List all registered MCP servers
claude mcp list

# Start a session and check available tools
# Type /mcp inside a Claude Code session to see connected servers and their tools
```

---

## Summary

| Server | Command | Requires Xcode Running | Scope | Tools |
|---|---|---|---|---|
| XcodeBuildMCP | `claude mcp add XcodeBuildMCP -s user -- npx -y xcodebuildmcp@latest mcp` | No | User (global) | 59 |
| Apple Xcode MCP | `claude mcp add --transport stdio xcode -- xcrun mcpbridge` | Yes | Project | 20 |
| Xcode-internal config | Edit `~/Library/.../ClaudeAgentConfig/.claude.json` | N/A (runs inside Xcode) | Per-project | Varies |

| CLI Tool | Install | Purpose |
|---|---|---|
| rsvg-convert | `brew install librsvg` | SVG → PNG rendering (required) |
| svgo | `npm install -g svgo` | Strip Illustrator metadata from SVGs (required) |
| sips | Built into macOS | Resize PNGs to icon sizes |
| iconutil | Built into macOS | Package .iconset → .icns |
| ImageMagick | `brew install imagemagick` | Compositing, effects, format conversion (optional) |


