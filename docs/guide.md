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
| Shift + 1 through 4 | Choose Shift tool by toolbar position (default: arrow, line, rectangle, ellipse) |
| Shift + drag | Draw the selected shape (arrow by default) |
| Click current text | Position the text caret without selecting by drag |
| Right-click text / Command + Return | Enter precise text editing with native drag selection |
| Command + click | Select the topmost object |
| Command + drag | Move an object |
| Delete | Delete the selected object; delete characters while editing |
| Return / Shift + Return | Commit text / insert a newline |
| Escape | Cancel a toolbar gesture; otherwise commit text, deselect, or hide the window |
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

Right-click a word (or Control-click), or press Command + Return while typing, to enter precise
editing. A subtle outline marks that state. Dragging inside actual text lines
selects text normally; dragging outside commits the text and starts drawing in
the same gesture. Empty space to the right of short lines remains canvas. Return
or Escape ends editing, while Shift + Return inserts a newline. There are no
idle timeouts or pointer-hover rules that unexpectedly commit text.

The canvas always uses a crosshair pointer, including over editable text and while erasing. Only the active native text editor displays an insertion caret. Moving the mouse hides that caret immediately, even for a small movement or during precise editing; typing or correcting text shows it again. There are no extra anchor markers or pointer carets. An optional translucent trail follows the crosshair hotspot and fades within 0.18 seconds. It stops during typing, drawing, and erasing and never appears in exports. Toggle **Crosshair trail / 十字指针轨迹** in Settings; its preference is remembered.

Pointer placement is the default. Moving at least 12 screen points from the last typing position makes the next printable key commit the current variable and start another centered on the pointer hotspot, including after pan and zoom. The last canvas mouse event determines this position, so activating the window or starting IME composition cannot replace it with a stale sampled location. Smaller movements keep typing in the same variable. Backspace and arrow keys keep correcting the current variable; precise editing and active input-method composition keep their original location. Hover alone never commits text.

The native text input client remains active between labels and drawing gestures.
Chinese input methods can start composition on the first keystroke without
leaving an extra Latin initial. Deliberate mixed Chinese and English text is preserved. Marked Pinyin, CJK characters, and committed text share a fixed line grid and baseline, including during export, so switching composition stages does not move the text up or down.

Settings also offer click placement. This update enables pointer placement once;
later manual changes to that preference are preserved. Moving the pointer outside
the canvas or over the palette keeps the current text location.

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
right-click to enable it and open a live size preview with a continuous
**4–120 pt** diameter slider. There is no separate size button. The size preview shows the erasing footprint; its screen diameter remains constant while zooming. The canvas pointer stays a crosshair. Option + drag
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
global shortcut, toolbar size/collapse/visibility, palette position, window size/location, persistent mode, and
full-screen mode. Ink preferences are stored separately for light and dark paper.
Transient state such as a text selection, temporary Option erasing, and an open
popover is not restored. Preferences are saved locally in macOS UserDefaults;
there is no Apply button. Invalid stored values fall back to safe defaults.

## Color

Up to six editable presets sit in a small, draggable bottom palette. Hover to
see their names and shortcuts. Click the final color button for a saturation /
brightness surface, hue slider, six-digit HEX input, screen eyedropper, and six
recent custom colors. Use **Replace current preset** to customize the last selected
preset slot. Right-click any preset to edit or delete it; accepting the picker saves an edit, and Escape cancels it. Use **Add** in the picker to add a preset (up to six). All presets may be deleted without losing the current ink color. Restore the default palette in settings.

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
testing, pointer-led typing, right-click selection, native keyboard corrections, marked text,
text/drawing transitions, vector eraser clipping and undo, zoom-independent eraser
size, merged eraser controls, repeated window toggling, preference restoration, color preview cancellation, viewport transforms,
and PNG/PDF output. The smoke test
starts AppKit and checks exports, recoloring, and undo/redo against a temporary
draft, then restores the previously loaded draft before exiting. The smoke test
does not register the global shortcut. Close other Inkey instances before running
it to keep autosave verification isolated.

See [CONTRIBUTING.md](../CONTRIBUTING.md) for the English-only emoji commit convention.

Drag shape buttons or preset colors within their own row to reorder them. The dragged item follows the pointer immediately, neighbors slide aside as you cross their positions, and the new order is saved once on release; drop outside the row or press Escape to cancel. Losing window focus, resizing the window, changing paper or tools, collapsing, and hiding also cancel an unfinished drag. Window resizing temporarily keeps the palette within reach and restores its preferred location when space returns. Shortcuts remain tied to positions (Shift + 1–4 and Option + 1–6), and tooltips update to match. Ordering survives restarts without changing the selected tool or ink. Light and dark paper keep separate color orders. The shape row remembers the selected Shift tool. Shift-drag creates an arrow, straight line, rectangle with independently dragged width and height, or ellipse; ordinary dragging remains freehand. Shapes support selection, movement, recoloring, erasing, undo, editable draft storage, and PNG/PDF export. Right-click (or Control-click) the eraser to adjust its 4–120 pt size; single-click toggles erasing.

The rectangle tool replaces the square tool at **Shift + 3** in the default order. Existing square shapes in saved drafts retain their original geometry; a previously selected square tool now selects the rectangle tool.

## Toolbar visibility

Use the chevron to collapse the tool and color rows into a small handle; click it again to expand. Drag the left grip or empty toolbar background to move it, including when collapsed. Drag the upper-right size handle horizontally to resize the expanded toolbar from 85% to 150%, or double-click it to restore 100%. More (···) offers the same size presets. Resizing previews immediately and saves on release; Escape or losing focus cancels. When the window is too small, the toolbar fits temporarily and restores the requested size as space returns. **Option + Command + T** toggles collapse (also in View and More); hiding or restoring is available only in More and through **Shift + Command + T**. There is no hide button on the toolbar. Collapse and visibility are remembered separately across launches. Color and shape shortcuts still work while hidden; opening a color or size picker reveals and expands its toolbar anchor.

## Text size and global shortcut

Right-click text to enter precise editing and reveal its resize box. Drag any corner to scale the font uniformly while keeping the opposite corner fixed. One drag creates one undo step. Sizes range from **6–200 pt**. By default, the resized size becomes the default for the next text label; turn off **Use resized size for subsequent typing / 拖拽缩放后，设为下次输入字号** in Settings to keep these independent. Set the default directly with the **Default typing font size / 默认输入字号** field or stepper. Existing labels keep their own size; changes to the default apply to newly created labels.

In Settings, click the **Show / hide shortcut / 呼出／收起快捷键** recorder, then press a new combination containing Control, Option, or Command. Esc cancels recording. A conflicting combination leaves the old shortcut active. The same shortcut shows and hides the canvas and is remembered across launches. Pressing the existing shortcut while recording accepts it without hiding Settings.

New text boxes keep their geometric center at the crosshair location throughout typing, Pinyin composition, deletion, and line breaks. Committing saves the corresponding top-left drawing origin so the center remains unchanged. Existing text boxes keep their stored position when reopened for editing. Live and saved text use the same canvas-space font metrics, line grid, and explicit character spacing; zoom scales the editor rather than changing its font size. Starting another label therefore keeps the previous label's position and layout unchanged, including at fractional zoom levels.
