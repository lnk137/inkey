# Inkey user guide

[Back to the overview](../README.md)

A quiet, native macOS scratchpad for thinking through algorithms.
Type variable names, drag to sketch relationships, then return to your browser.
Built with Swift and AppKit. No web view, account, network service, or external dependency.

## Run

Requires macOS 14 or later and Xcode command line tools with Swift 6 or later.

```sh
./scripts/build-app.sh
open build/Inkey.app
```

The application lives in this repository's ignored `build/` directory. It runs
from the menu bar without adding a Dock icon. Closing its window keeps the app
running. Use the menu bar menu to quit. The bundle is ad hoc signed for local use;
it is not a notarized distribution build.

## Interaction

| Action | Result |
| --- | --- |
| Control + Option + Space | Show or hide Inkey; return focus to the previous app |
| Move pointer, then type | Create a variable at the pointer, without clicking |
| Click blank canvas | Place the next text insertion marker |
| Drag | Draw, including a drag that starts on newly typed text |
| Shift + drag | Draw a straight arrow |
| Click current text | Position the text caret without selecting by drag |
| Double-click text / Command + Return | Enter precise text editing with native drag selection |
| Command + click | Select the topmost object |
| Command + drag | Move an object |
| Delete | Delete the selected object; delete characters while editing |
| Return / Shift + Return | Commit text / insert a newline |
| Escape | Commit text, deselect an object, or hide the window |
| Two-finger scroll / pinch | Pan / zoom |
| Command + 0 | Fit all content |
| Command + Z / Shift + Command + Z | Undo / redo |
| Option + 1 through 6 | Choose a preset color |
| Shift + Command + C | Open the custom color picker |
| Option + Command + E | Toggle eraser mode |
| Option + drag | Erase temporarily without changing the selected tool |
| Option + Command + [ / ] | Decrease / increase eraser diameter |
| Shift + Command + P | Toggle persistent, floating mode |
| Control + Command + F | Toggle native full screen |
| Command + N | Start a new draft, preserving the previous one |
| Command + O | Open a draft or import an image/PDF |
| Shift + Command + O | Browse recent local drafts |
| Command + S | Save an editable `.inkey` file |
| Shift + Command + S | Save a copy to a new location |
| Command + E | Export PNG, PDF, or Inkey |
| Command + comma | Open settings |

Drawing uses the standard macOS click-and-drag interaction. You can also enable
macOS trackpad dragging in system accessibility settings. It does not capture raw
finger motion or require private multitouch APIs. Normal text input keeps native
keyboard corrections and input methods, while mouse drags go to the canvas. A
single click on the current word positions the caret; moving at least 3 screen
points starts a stroke at the original press location. This also works directly
over the word, without losing the beginning of the stroke.

Double-click a word, or press Command + Return while typing, to enter precise
editing. A subtle outline marks that state. Dragging inside actual text lines
selects text normally; dragging outside commits the text and starts drawing in
the same gesture. Empty space to the right of short lines remains canvas. Return
or Escape ends editing, while Shift + Return inserts a newline. There are no
idle timeouts or pointer-hover rules that unexpectedly commit text.

Pointer placement is the default. Moving at least 12 screen points from the last
typing position previews a blinking caret at the pointer hotspot; the next printable
key commits the current variable and starts another at that exact position,
including after pan and zoom. The caret and trail use the same hotspot without
a right/down offset. Small
trackpad jitter keeps typing in the same variable. Backspace and arrow keys keep
correcting the current variable, and precise editing or active input-method
composition stays at its existing location. Hover alone never commits text.

Settings also offer click placement. This update enables pointer placement once;
later manual changes to that preference are preserved. Moving the pointer outside
the canvas or over the palette keeps the current text location. An optional,
ink-colored translucent cursor trail fades within 0.18 seconds and runs animation
only while visible; turn it off using **Cursor trail / 光标轨迹** in settings. It
does not appear while drawing, erasing, or precisely editing text, or in exports.

You can also record a global shortcut;
registration failure is reported and the previous binding is restored. Some
shortcuts intercepted by system gestures may require a different combination.

Normal floating windows hide when focus leaves Inkey. Persistent mode stays above
other windows, while full screen remains visible until explicitly hidden or left.
Window geometry is remembered between launches.
The same shortcut always hides a visible canvas, including when a color popover,
settings, or another app has focus. Press it again to restore the canvas. Hiding
also hides settings and commits pending text. A minimized canvas is restored.
Inkey keeps one running application instance; opening another copy brings the
existing instance forward rather than competing for the global shortcut.

## Eraser

The eraser uses one button next to the colors: single-click to toggle it, and
double-click to enable it and open a live size preview with a continuous
**4–120 pt** diameter slider. There is no separate size button. The circular cursor shows
the actual screen footprint, which remains constant while zooming. Option + drag
temporarily erases; Option + Command + E switches the persistent tool. Typing or
choosing a color returns to the pen automatically.

Freehand strokes are cut into editable vector fragments. Text variables and
arrows are erased as whole objects. Reference images and imported PDF pages are
protected; select them with Command + click and use Delete when removal is
intentional. Fast eraser gestures cover the complete distance between events,
and one gesture creates one undo step. Erasing removes content rather than
painting over it, so exports and paper colors remain correct.

## Remembered preferences

Inkey automatically remembers the active pen/eraser tool, eraser diameter, selected
preset or custom ink, customized presets, recent colors, text placement mode,
global shortcut, cursor trail, palette position, window size/location, persistent mode, and
full-screen mode. Ink preferences are stored separately for light and dark paper.
Transient state such as a text selection, temporary Option erasing, and an open
popover is not restored. Preferences are saved locally in macOS UserDefaults;
there is no Apply button. Invalid stored values fall back to safe defaults.

## Color

Six carefully chosen presets sit in a small, draggable bottom palette. Hover to
see their names and shortcuts. Click the final color button for a saturation /
brightness surface, hue slider, six-digit HEX input, screen eyedropper, and six
recent custom colors. Use **Replace current preset** to customize the last selected
preset slot, and restore the default palette in settings.

Color changes affect new content, or selected objects. While editing text, the
whole variable changes color and keeps its content. Custom colors preview live;
Escape cancels the preview, and clicking Done or outside the picker accepts it.
One accepted object recolor creates one undo step. Clicking presets returns focus
to the canvas or the existing text editor.

The paper background selects a light or dark preset palette to keep new ink
legible. A draft's paper background and existing colors are stored as actual
values and remain unchanged when the system appearance changes, including on
export. New drafts adopt the current system appearance. Custom preset slots are
saved separately for light and dark paper.

## Files and privacy

Drafts autosave after committed changes and when the window hides or the app
quits. Text is committed on Return, drawing, file actions, or hiding the window.
Draft files are stored at:

```text
~/Library/Application Support/Inkey/Drafts/
```

The most recently active draft is restored on launch. Open the recent drafts menu
from the ellipsis or menu bar. Saving writes a portable, editable JSON-based
`.inkey` file. Autosaves remain local; use Save again to update the external file
during the current session, or Save As to choose another location. Restarting the
app restores the local draft; saving it externally then asks for a location again.
Opening an external draft imports a copy, so it does not replace a matching local
autosave. Opening the same file repeatedly creates separate local copies.

PNG and PDF export include all content with a paper margin and the saved paper
background. PNG/PDF exports are flattened. Editable exports preserve individual
text objects, strokes, arrows, colors, image data, and viewport. Images and all
pages of an imported PDF become movable background reference objects, rather
than editable PDF text. PDFs are limited to 100 pages and rendered at a bounded
resolution. Bitmap exports reject excessive canvas dimensions instead of trying
to allocate unlimited memory.

No network access is used by the application. There is no telemetry or sync.
Local builds do not require Accessibility or Input Monitoring permissions for the
global shortcut. macOS may request screen color sampling permission when you use
the system eyedropper.

## Development and verification

```sh
swift build
swift test
./scripts/build-app.sh
build/Inkey.app/Contents/MacOS/Inkey --smoke-test
```

The tests cover document round trips and invalid files, actual text-view hit
testing, pointer-led typing, double-click selection, native keyboard corrections, marked text,
text/drawing transitions, vector eraser clipping and undo, zoom-independent eraser
size, merged eraser controls, repeated window toggling, preference restoration, color preview cancellation, viewport transforms,
and PNG/PDF output. The smoke test
starts AppKit and checks exports, recoloring, and undo/redo against a temporary
draft, then restores the previously loaded draft before exiting. The smoke test
does not register the global shortcut. Close other Inkey instances before running
it to keep autosave verification isolated.

See [CONTRIBUTING.md](../CONTRIBUTING.md) for the English-only emoji commit convention.
