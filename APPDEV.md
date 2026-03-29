# macOS App Development 

## Project Overview

This is a native macOS application built with Swift and SwiftUI. Claude Code
operates as the primary development agent, using MCP servers, subagents, and
agent teams to build, test, and iterate on the app autonomously.

## Environment Detection

Detect the current environment before choosing a workflow:

- If `CLAUDE_CONFIG_DIR` contains `Xcode/CodingAssistant` → you are running inside **Xcode 26.3+ Claude Agent SDK**. Use Xcode's built-in MCP tools (`BuildProject`, `RunAllTests`, `RenderPreview`, `DocumentationSearch`). Do NOT shell out to `xcodebuild` directly.
- Otherwise → you are running in **Claude Code CLI/Desktop**. Use XcodeBuildMCP and Apple's Xcode MCP bridge tools described below.

## MCP Servers

### XcodeBuildMCP (primary — works without Xcode running)

Provides 59 tools for builds, tests, simulator control, device deployment, LLDB debugging, and UI automation. Install globally:

```
claude mcp add XcodeBuildMCP -s user -- npx -y xcodebuildmcp@latest mcp
```

Key tools: `simulator/build`, `simulator/build-and-run`, `simulator/test`, `simulator/screenshot`, `debugging/attach`, `debugging/breakpoint`, `ui-automation/tap`, `ui-automation/swipe`.

### Apple Xcode MCP Bridge (supplemental — requires Xcode running)

Exposes 20 tools via XPC into a running Xcode process: file operations, live diagnostics, documentation search, Swift REPL, and SwiftUI Preview rendering. Install:

```
claude mcp add --transport stdio xcode -- xcrun mcpbridge
```

Key tools: `BuildProject`, `RunAllTests`, `RunSomeTests`, `RenderPreview`, `DocumentationSearch`, `SwiftREPL`, `XcodeListWindows`. Requires Xcode 26.3+ with MCP enabled in Settings → Intelligence.

### When to use which

- **XcodeBuildMCP** for headless CI-style work, simulator builds, device deployment, and debugging without Xcode open.
- **Apple Xcode MCP** when you need SwiftUI Preview rendering, Apple documentation semantic search (includes WWDC transcripts), or real-time Xcode diagnostics.
- **Both together** for full coverage: XcodeBuildMCP handles the build/test/debug loop, Apple MCP handles preview verification and doc lookup.

## Agent Workflow

### Default: Single-agent loop

For most tasks, work in a single session following this loop:

1. Read relevant source files to understand context.
2. Plan the change (state the plan before writing code).
3. Implement the change.
4. Build using XcodeBuildMCP `simulator/build` — fix all compiler errors before proceeding.
5. Run tests using `simulator/test` — fix failures.
6. If the change is visual, capture a `simulator/screenshot` and verify the UI.
7. Commit with a descriptive message.

### Subagents

Use subagents for focused, isolated tasks that report results back. Spawn a subagent when you need to:

- **Research**: look up Apple API documentation or search the codebase for patterns before implementing.
- **Security review**: audit a module after implementing it — use a separate context to avoid anchoring bias.
- **Test generation**: write unit/UI tests for code you just implemented.
- **Build verification**: compile and run tests in isolation while you continue planning.

Subagents cannot message each other. They return results to you. Prefer subagents over agent teams for sequential, dependency-heavy work.

### Agent Teams

Enable with: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in settings.json.

Use agent teams when multiple areas of the app need parallel, coordinated work. Good scenarios:

- **Feature implementation**: spawn teammates for `frontend` (SwiftUI views), `backend` (data layer/networking), and `tests` (test coverage) — each owns their layer.
- **Refactoring**: teammates each own a module, coordinate to keep interfaces consistent.
- **Debugging competing hypotheses**: spawn 3+ investigators to test different theories in parallel, have them challenge each other's findings.

Example spawn prompt:
```
Create an agent team with 3 teammates:
1. "views" — implements the SwiftUI views and navigation for the feature
2. "data" — implements the data models, persistence, and networking
3. "tests" — writes unit tests and UI tests as the other agents build

All agents should use XcodeBuildMCP to verify their work compiles. The tests agent should run the full test suite after each major change.
```

Teammates load this CLAUDE.md automatically but do NOT inherit conversation history. Include task-specific context in spawn prompts.

### Computer Use

For visual verification and GUI testing when screenshots alone aren't enough, enable Computer Use (requires Screen Recording + Accessibility permissions on the terminal app). Use it to:

- Interact with the running app in Simulator to reproduce bugs.
- Verify complex UI flows that require multiple taps/gestures.
- Test accessibility and VoiceOver behavior.

Computer Use is expensive (screenshot tokens). Prefer `simulator/screenshot` from XcodeBuildMCP for simple visual checks.

## Asset Pipeline — SVG to Icons and Landing Pages

Source artwork is provided as SVG files exported from Adobe Illustrator. These are the single source of truth for all visual assets. Do not modify the source SVGs — always work from copies.

### Illustrator SVG handling

Illustrator SVGs contain extra metadata, namespaces (`i:`, `x:`), embedded fonts, and clipping masks that can break CLI renderers. Before any conversion, clean the SVG:

```bash
# Clean Illustrator metadata and optimize for rendering
svgo --config='{"plugins":["preset-default",{"name":"removeAttrs","params":{"attrs":"(xmlns:i|xmlns:x|i:pgf|i:layer)"}}]}' -i source.svg -o cleaned.svg
```

If `svgo` is not installed, fall back to a minimal sed cleanup:
```bash
sed -e 's/ xmlns:i="[^"]*"//g' -e 's/ xmlns:x="[^"]*"//g' -e 's/ i:[a-zA-Z]*="[^"]*"//g' source.svg > cleaned.svg
```

Always verify the cleaned SVG renders correctly before proceeding.

### Icon generation from SVG

Generate the complete macOS icon set from a single SVG source:

1. **Convert SVG → 1024×1024 PNG** (the master raster):
   ```bash
   rsvg-convert -w 1024 -h 1024 cleaned.svg -o icon_1024x1024.png
   ```

2. **Generate all required sizes** using `sips` (built into macOS):
   ```bash
   mkdir AppIcon.iconset
   sips -z 1024 1024 icon_1024x1024.png --out AppIcon.iconset/icon_512x512@2x.png
   sips -z 512 512   icon_1024x1024.png --out AppIcon.iconset/icon_512x512.png
   sips -z 512 512   icon_1024x1024.png --out AppIcon.iconset/icon_256x256@2x.png
   sips -z 256 256   icon_1024x1024.png --out AppIcon.iconset/icon_256x256.png
   sips -z 256 256   icon_1024x1024.png --out AppIcon.iconset/icon_128x128@2x.png
   sips -z 128 128   icon_1024x1024.png --out AppIcon.iconset/icon_128x128.png
   sips -z 64 64     icon_1024x1024.png --out AppIcon.iconset/icon_32x32@2x.png
   sips -z 32 32     icon_1024x1024.png --out AppIcon.iconset/icon_32x32.png
   sips -z 32 32     icon_1024x1024.png --out AppIcon.iconset/icon_16x16@2x.png
   sips -z 16 16     icon_1024x1024.png --out AppIcon.iconset/icon_16x16.png
   ```

3. **Package as .icns**:
   ```bash
   iconutil -c icns AppIcon.iconset -o AppIcon.icns
   ```

4. **Place into Asset Catalog**: copy the sized PNGs into `Assets.xcassets/AppIcon.appiconset/` and update `Contents.json` to reference each file. If an `AppIcon.appiconset` already exists, match its `Contents.json` structure.

When generating icons, always verify the output at small sizes (16×16, 32×32). SVGs with fine detail or thin strokes may need manual review at these sizes. Capture a `simulator/screenshot` after setting the icon to confirm it renders correctly in the Dock.

### Landing page generation from SVG

Use provided SVGs as hero artwork, logos, or section illustrations in landing pages:

1. **For web use**: clean with `svgo` (removes Illustrator bloat, reduces file size 40-70%) and embed directly in HTML. Prefer inline `<svg>` over `<img>` tags so colors and sizing can be controlled via CSS.

2. **Generate raster variants** for social/meta tags:
   ```bash
   # OG image (1200×630)
   rsvg-convert -w 1200 -h 630 --keep-aspect-ratio cleaned.svg -o og-image.png

   # Favicon (multiple sizes)
   rsvg-convert -w 180 -h 180 cleaned.svg -o apple-touch-icon.png
   rsvg-convert -w 32 -h 32 cleaned.svg -o favicon-32x32.png
   rsvg-convert -w 16 -h 16 cleaned.svg -o favicon-16x16.png
   ```

3. **Landing page structure**: when asked to create a landing page, build a single self-contained HTML file with inline CSS. Use the cleaned SVG inline for the hero/logo. Ensure responsive layout and dark mode support via `prefers-color-scheme`. Include App Store / download badges where appropriate.

4. **If ImageMagick is available**, use it for more complex operations — compositing SVGs onto backgrounds, adding drop shadows, or creating mockup images:
   ```bash
   magick cleaned.svg -resize 800x800 -gravity center -background '#1a1a2e' -extent 1200x630 hero-banner.png
   ```

### Tool availability check

Before starting any asset work, verify which tools are present:
```bash
which rsvg-convert && echo "librsvg: OK" || echo "librsvg: MISSING — install with: brew install librsvg"
which svgo && echo "svgo: OK" || echo "svgo: MISSING — install with: npm install -g svgo"
which magick && echo "ImageMagick: OK" || echo "ImageMagick: MISSING (optional) — install with: brew install imagemagick"
# sips and iconutil are built into macOS — no install needed
```

If `rsvg-convert` is missing, fall back to ImageMagick (`magick convert`) for SVG→PNG. If neither is available, inform the user that one must be installed before proceeding — do not attempt to use `sips` for SVG input as it does not support SVG.

## Code Standards

- **Language**: Swift 6, strict concurrency enabled.
- **UI Framework**: SwiftUI. Use UIKit only when SwiftUI has no equivalent.
- **Architecture**: follow existing patterns in the codebase. If unclear, check for MVVM or similar in the existing view/model structure before introducing new patterns.
- **Minimum deployment target**: macOS 15.
- **Package manager**: Swift Package Manager. Do not introduce CocoaPods or Carthage.
- **Error handling**: use Swift's typed throws where possible. Never silently discard errors.
- **Concurrency**: use Swift structured concurrency (async/await, TaskGroup, actors). Avoid raw GCD unless wrapping legacy APIs.

## Build & Test Commands (CLI fallback)

If MCP tools are unavailable, use these directly:

```bash
# Build
xcodebuild -scheme <AppScheme> -destination 'platform=macOS' build

# Run tests
xcodebuild -scheme <AppScheme> -destination 'platform=macOS' test

# SwiftUI preview (Xcode must be open)
# Use Apple Xcode MCP RenderPreview instead
```

## Important Notes

- Always build after changes. Do not assume code compiles — verify with the build tool.
- When Apple documentation is needed, use `DocumentationSearch` (Apple MCP) or search Apple's developer docs. Do not guess API signatures.
- For multi-target SPM projects, check the active scheme before building. Use `xcodebuild -list` or XcodeBuildMCP's project inspection tools to identify the correct scheme.
- Keep commits atomic: one logical change per commit.
- If a task would benefit from multiple agents working in parallel, proactively suggest using agent teams rather than working sequentially.


