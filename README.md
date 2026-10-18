<div align="center">

# Inkey

**Type where you point. Drag to draw. Keep thinking.**

A native macOS scratchpad for variables, diagrams, and the next step in your algorithm.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-303735?style=flat-square)
![Swift 6+](https://img.shields.io/badge/Swift-6%2B-C36A44?style=flat-square)
![AppKit](https://img.shields.io/badge/UI-AppKit-3E795E?style=flat-square)

[简体中文](README.zh-CN.md) · [User guide](docs/guide.md) · [Report an issue](https://github.com/lnk137/inkey/issues)

</div>

![Inkey's native canvas showing a two-pointer algorithm with typed variables, hand-drawn circles, arrows, and a compact color palette.](docs/assets/inkey-canvas.png)

<sub>Example draft rendered with Inkey's native AppKit components.</sub>

## A scratchpad that follows your thinking

Solving a problem in your browser? Press **⌃⌥Space**, sketch the idea, and press it again to return. No text tool to hunt for. No drawing mode to get stuck in.

- **Type, then draw.** Move the pointer to start another variable. Drag to sketch—even over newly typed text. Right-click a word for precise editing.
- **Made for a trackpad.** Shift-drag arrows, lines, rectangles, or ellipses, pinch to zoom, or Option-drag to erase. Single-click the eraser to toggle it; right-click to resize it.
- **Only what you need.** Editable color presets, a custom color picker, a resizable, draggable, collapsible toolbar, an optional crosshair trail, and floating, pinned, or full-screen windows.
- **Pick up where you left off.** Local autosave, remembered preferences, editable `.inkey` drafts, and PNG/PDF export.

Swift + AppKit. No web view, account, telemetry, or third-party dependencies.

## Get started

Requires **macOS 14+**, **Swift 6+**, and the Xcode command line tools.

```sh
git clone https://github.com/lnk137/inkey.git
cd inkey
./scripts/build-app.sh
open build/Inkey.app
```

Inkey lives in your menu bar. The current build is signed locally for development; a notarized download is not available yet.

## A few gestures to remember

| Action | Result |
| :--- | :--- |
| **⌃⌥Space** | Show / hide the scratchpad |
| **Move → type** | Start text at the pointer |
| **Drag / ⇧ drag** | Freehand / selected shape |
| **Right-click text / ⌘Return** | Edit and select text precisely |
| **⇧1–4** | Choose Shift tool in toolbar order (default: arrow, line, rectangle, ellipse) |
| **⌥1–6** | Pick a preset color |
| **Click / right-click eraser** | Toggle / adjust size |
| **⌥ drag** | Erase temporarily |
| **⌘E** | Export PNG, PDF, or an editable draft |

The global shortcut is customizable. Text placement, toolbar visibility, colors, eraser size, and window preferences are remembered. [See all controls →](docs/guide.md)

## Built to stay small

```sh
swift test
```

Tests cover text/drawing transitions, input methods, pointer alignment, vector erasing, persistence, exports, and window toggling. To regenerate the native preview, run `./scripts/render-readme.sh`.

[Contributions](CONTRIBUTING.md) and [thoughtful bug reports](https://github.com/lnk137/inkey/issues) are welcome.

Drag shape buttons or preset colors within their row to reorder them. Shortcuts stay with positions: ⇧1–4 for shapes, ⌥1–6 for colors. The order is saved; the selected tool and ink stay unchanged. Right-click a color preset to edit or delete it. Add colors in the custom picker (up to six); restore defaults in Settings.

The canvas uses a crosshair; only typing shows an insertion caret, which disappears on mouse movement. Collapse the toolbar with its chevron; drag any blank area to move it, including when collapsed. Drag the upper-right size handle horizontally to resize it (85–150%); double-click it to reset. More (···) also offers size presets. Use ⌥⌘T to collapse/expand; hide or restore the toolbar only through More or ⇧⌘T. Size, position, and visibility are remembered.

Right-click text and drag a corner to resize it. The resized font becomes the next typing size by default; disable this in Settings or set a default directly (6–200 pt). Click the show/hide shortcut recorder in Settings to choose another global combination.

New text boxes stay centered on the crosshair while typing, composing, and committing.
