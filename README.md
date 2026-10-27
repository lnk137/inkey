<div align="center">

<img src="docs/assets/inkey-logo.png" width="128" height="128" alt="Inkey logo: a handwritten dark green i on warm ivory">

# Inkey

**Type to write. Drag to draw. Let your actions choose the tool.**

A native macOS scratchpad where variables, sketches, and diagrams flow together. Start typing without selecting a text tool.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-303735?style=flat-square)
![Swift 6+](https://img.shields.io/badge/Swift-6%2B-C36A44?style=flat-square)
![AppKit](https://img.shields.io/badge/UI-AppKit-3E795E?style=flat-square)

[Overview](README.md) · [Legacy README address](README.zh-CN.md)

[Usage](#usage) · [Installation](#installation) · [User guide](docs/guide.md) · [Report an issue](https://github.com/lnk137/inkey/issues)

</div>

## Contents

- [Usage](#usage)
- [Features](#features)
- [Installation](#installation)
- [Shortcuts and settings](#shortcuts)
- [FAQ](#faq)
- [Development and contributing](#contributing)

<a id="usage"></a>

## Usage

Inkey brings typing, freehand drawing, and temporary tools into the same interaction. **Start typing without selecting a text tool, then draw without switching back to a pen.** Tool changes follow your actions, keeping writing, drawing, and correcting connected.

| Type directly | Drag to draw | Hold for temporary tools |
| :--- | :--- | :--- |
| Type a variable or note on the canvas. Move the pointer to start text at another position. | Drag to sketch, even over newly typed text. | Shift-drag to draw the selected shape. Option-drag to erase; release Option to return to your previous tool. |

Type `left`, drag a connecting line, move the pointer and type `right`, then hold Option to erase an extra stroke. Keep working through the idea as your hands move between typing and drawing.

Solving a problem in your browser? Press **⌃⌥Space** to bring up the scratchpad, then press it again to return. For precise text changes, click existing text to place the caret, right-click for full editing and selection, or drag its corners to change its size.

![Inkey's native canvas showing a two-pointer algorithm with typed variables, hand-drawn circles, arrows, and a compact color palette.](docs/assets/inkey-canvas.png)

<sub>Example draft rendered with Inkey's native AppKit components.</sub>

<a id="features"></a>

## Features

- **Connected writing and drawing**: type directly, drag to sketch, and use native input methods. New text stays centered on the crosshair through typing and composition.
- **Trackpad controls**: scroll with two fingers to pan and pinch to zoom. Shift-drag arrows, lines, rectangles, or ellipses; Option-drag to erase temporarily.
- **Compact toolbar**: reorder shapes and colors, click **+** to add presets, and move, resize, hide, or collapse the toolbar. Extra colors wrap into rows; the first six keep their shortcuts. Adding and deleting colors smoothly reflows the row and toolbar. Two folding animations respect Reduce Motion.
- **Precise text editing**: pause over text for about 0.45 seconds to edit without a box; drag immediately to draw. Right-click for a box with movement and proportional font resizing.
- **High contrast**: a separate half-black/half-white toolbar switch adds thin black-and-white outlines to colored text, strokes, and shapes, with a fixed screen thickness. High-contrast letter spacing is adjustable live in Settings. Images stay unchanged; exports use the current display setting. An optional setting enables high contrast each time you enter a screen draft.
- **Screen drafts**: press **⌃⌥S** to draw and type on a transparent overlay over the current screen, using the same tools. Press Esc, click Close, or use the shortcut again to exit; screen and paper drafts save separately.
- **Ready when you need it**: menu bar access, floating, pinned, and full-screen windows, plus silent launch at login.
- **Configurable shortcuts**: record, clear, or restore 37 actions, with search, conflict checks, and matching menu shortcuts and toolbar hints.
- **Drafts and references**: local autosave and recent-draft restoration, editable `.inkey` files, PNG/PDF export, and image/PDF reference backgrounds.
- **Paste at the pointer**: paste text at the configured font size or images sized to fit the canvas. Right-click an image to select it, then drag to move it or resize it proportionally with its corner handles.
- **Adjust drawn shapes**: right-click to select. Drag a rectangle or ellipse inside its box to move it, or use its corners to resize and flip across the fixed opposite corner. Arrows and lines use two endpoint handles to change length and direction; drag the shaft to move the whole object. Each gesture is one undo step.
- **Native and local**: Swift + AppKit, with no web view, account, telemetry, or third-party dependencies.

<a id="installation"></a>

## Installation

Build from source to use Inkey. A notarized installer is not available yet.

**Requirements**: macOS 14+, Swift 6+, and the Xcode command line tools.

```sh
git clone https://github.com/lnk137/inkey.git
cd inkey
./scripts/build-app.sh
open build/Inkey.app
```

The locally signed app is created at `build/Inkey.app`. Inkey lives in your menu bar; use its menu or the global shortcut to show and hide the scratchpad.

<a id="shortcuts"></a>

## Shortcuts and settings

These are the default shortcuts. Existing custom bindings are preserved.

| Action | Control |
| :--- | :--- |
| Show / hide the scratchpad | **⌃⌥Space** |
| Enter / exit screen draft | **⌃⌥S**; **Esc** or Close to exit |
| Start text at another position | **Move the pointer → type** |
| Freehand / selected shape | **Drag / ⇧ drag** |
| Edit text precisely | **Right-click text / ⌘Return** |
| Choose shape position 1–4 | **⇧1–4** |
| Choose color position 1–6 | **⌥1–6** |
| Erase temporarily | **⌥ drag** |
| Toggle / resize the eraser | **Click / right-click eraser** |
| Collapse / expand the toolbar | **⌥⌘T** |
| Hide / show the toolbar | **⇧⌘T** |
| Toggle high contrast | **⌥⌘H** |
| Export a draft | **⌘E** |
| Open Settings | **⌘,** |

**Settings → Shortcuts** offers 37 configurable actions for files, editing, canvas tools, the toolbar, windows, and shape/color positions. Click to record; Delete clears a binding while recording, and Esc cancels. Right-click to restore one default, or restore all defaults at once. Shapes and colors follow toolbar positions from left to right, including after reordering. Show/hide Inkey and Screen draft are global.

Choose Simplified Chinese or English using the language menu at the top of Settings. Quit and reopen Inkey to apply the change; existing installations default to Simplified Chinese.

**Settings → General** controls launch at login, text placement, default font size, reusing resized text sizes, crosshair trail, and folding animation. Colors, toolbar size and position, and window preferences are remembered automatically.

See the [user guide](docs/guide.md) for full controls, input behavior, and file details.

Choose Option (the default) or Command in **Settings → Shortcuts → Modifiers → Temporary eraser**. Hold the selected key to erase and release it to restore the previous tool. Selection/moving uses the other key: with Command erasing, Option selects/moves. Releasing the key mid-drag stops erasing immediately without starting a stroke.

Both persistent and temporary erasers show a black-and-white outline matching the on-screen erasing diameter. Its size stays constant while zooming; it hides outside the canvas or on focus loss and never appears in exports.

<a id="faq"></a>

## FAQ

### Does launch at login open a window?

No. With this option enabled, Inkey starts quietly in the menu bar after sign-in, without opening a canvas, Settings, or full-screen window or taking focus. Use the shortcut or menu bar to show the canvas. If macOS requires approval, allow Inkey in System Settings → General → Login Items.

### Do drafts require an internet connection or an account?

No. Drafts are saved locally and automatically. Export an editable `.inkey` file, or share a PNG/PDF export.

### Do shortcuts move with reordered tools?

Shortcuts stay with positions. By default, ⇧1 always selects the first shape position and ⌥1 selects the first preset color position. Reorder tools and colors independently.

<a id="contributing"></a>

## Development and contributing

[Bug reports](https://github.com/lnk137/inkey/issues) and [contributions](CONTRIBUTING.md) are welcome. Include your macOS version, reproduction steps, and screenshots or recordings without private drafts when reporting an interaction issue.

```sh
swift test
```

Tests cover text/drawing transitions, input methods, pointer alignment, vector erasing, persistence, exports, window toggling, and keyboard shortcuts. See the [contributing guide](CONTRIBUTING.md) for development conventions and interface localization.

```sh
./scripts/render-readme.sh
```

This script generates the README logo from the app icon source and updates the native AppKit preview with synthetic content. Images are saved in `docs/assets/`.
