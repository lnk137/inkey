# Inkey user guide

[Back to the overview](../README.md)

Inkey supports Simplified Chinese and English. Choose a language at the top of Settings, then quit and reopen Inkey to apply it. The default is Simplified Chinese. This guide uses the English interface labels.

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
| Control + Option + S | Enter or exit a transparent screen draft on the pointer’s screen |
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
editing. A subtle outline marks that state. The entire editor interior selects
text normally, including empty space to the right of short lines. Drag the outer
border to move the label, or start a drag beyond the box to commit and draw.
Return or Escape ends editing, while Shift + Return inserts a newline.

Pause over text for about **0.45 seconds** to enter quiet editing. Small pointer jitter is tolerated; moving more than four screen points restarts the wait. The pointer becomes an I-beam, with no box, handles, automatic selection, or insertion caret until you click or type. Click to place the caret or drag to select characters anywhere within the text view. Leaving its bounds restores drawing; dragging immediately before the dwell completes still draws. Hover activation is suspended during mouse gestures, erasing, modifier-key actions, input-method composition, or window focus loss. Right-click or Command-Return still enters explicit editing with movement and resize handles.

Leaving the text view clears quiet editing even during native selection drags. Returning always starts a fresh dwell; dragging immediately after returning draws.

Images do not activate text editing on hover. An image covering saved text blocks hover editing of that text; text drawn above an image remains editable.

Movable text borders and selected images show an open hand; dragging shows a closed hand. Text and image corner handles show the corresponding diagonal resize cursor, which stays visible throughout resizing. Modifier-assisted object movement also shows a hand. Drawing and erasing use the crosshair, while quiet hover editing uses the I-beam. Only the active native text editor displays an insertion caret. Moving the mouse hides that caret immediately, even for a small movement or during precise editing; typing or correcting text shows it again. There are no extra anchor markers or pointer carets. An optional translucent trail follows the crosshair hotspot and fades within 0.18 seconds. It stops during typing, drawing, and erasing and never appears in exports. Toggle **Crosshair trail** in Settings; its preference is remembered.

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

Enable **Launch at login** in Settings for silent startup after macOS login. Inkey registers its main app with the native `SMAppService` API; it does not register until you enable the switch. The switch reads the system state and refreshes when Settings is opened or Inkey becomes active, including changes made in System Settings. If approval is required, macOS Login Items settings opens; allow Inkey there or turn the switch off to cancel. Failures are reported and the switch returns to the actual system state.

The **General** page of Settings contains three groups: **General** (login startup and the global shortcut), **Text Input** (placement, default size, and reusing a resized size), and **Canvas & Toolbar** (crosshair trail, folding animation, and resetting preset colors). Descriptions sit beside the corresponding option. Controls align on the right, Boolean settings use native switches, and all changes save automatically. The layout follows the system appearance and fits without scrolling.

Login startup initializes the menu bar, draft, and global shortcut without showing any window, restoring full screen, or activating Inkey. A conflicting shortcut is reported only after you explicitly show the canvas. A second login launch leaves an existing instance hidden. Manual opening, the menu bar, and the global shortcut still show the canvas normally. Developers can use `--background` to exercise the same silent path; `--smoke-test` and `--ui-test` retain their visible test behavior.

## Screen drafts

Press **Control + Option + S** from any app, or choose **Enter / exit screen draft** in the menu bar or View menu. Inkey hides its paper window and opens a transparent overlay across the screen containing the pointer, including above full-screen apps. The content underneath stays live; Inkey does not take a screenshot or request screen recording permission. While active, the overlay receives pointer and keyboard input for annotations.

Typing, drawing, shapes, erasing, text and image editing, clipboard paste, undo/redo, panning, zooming, and the existing toolbar work just as on paper. The overlay uses a nearly invisible 1% tint to keep transparent areas interactive and the pointer stable as its trail fades. The top-right ellipsis provides the usual file and tool actions. Screen annotations have their own draft and undo history, separate from the paper draft. Both survive switching modes; screen annotations also autosave and return the next time you enter screen mode, including after relaunch. New, open, save, recent drafts, and export act on the active draft.

Press the screen shortcut again, click the top-right Close button, or press **Esc** to save pending text and leave the overlay. Esc first cancels an open color picker or toolbar gesture; otherwise it exits even during text editing or object selection. Exit restores the paper window if it was previously visible, or returns to the previous app if it was hidden. **Control + Option + Space** switches directly back to the paper window. Switching to another app dismisses the overlay without stealing focus. The full-screen command returns to paper and uses its existing native full-screen behavior; pinning retains its paper-window preference while the overlay stays above the screen.

Screen drafts save and export annotation objects using the same `.inkey`, PNG, and PDF formats as paper drafts. PNG/PDF use the draft’s saved paper color and do not capture the apps underneath. The close button remains available when the toolbar is hidden.

## High contrast

Click the half-black/half-white circle in the toolbar, choose **High contrast** in View or More, or press **Option + Command + H**. If its default combination is already assigned to one of your customized actions, that action is preserved and High contrast starts unassigned; record another combination in Settings. It is an independent display toggle, shown by the button highlight and menu checkmark. It works with any ink, shape, eraser, native text selection, IME composition, or active drawing gesture. A short 0.16-second fade changes only the outlines and respects Reduce Motion; it does not commit text, change tools, or add an undo step.

In **Settings → General → Canvas & Toolbar**, the **High-contrast letter spacing** slider adjusts extra letter spacing from **0–12 pt**, in 0.5 pt steps, with a **4 pt** default. It previews immediately and saves automatically. The spacing is measured in screen points, so adjacent outlines remain separated at different zooms. It applies only while high contrast is enabled; native editing, text selection, resize handles, and PNG/PDF exports all use the same spacing. Text keeps its original center, and `.inkey` content keeps its original text, position, and font size. IME composition and native undo remain active while adjusting.

Existing and new text, strokes, and shapes retain their original colors with a thin white outer rim and black inner rim. The rims stay 2 pt and 1 pt outside the original content at every canvas zoom. Images remain unchanged. Paper and screen canvases remember their display states independently, so leaving a screen draft restores the paper canvas’s previous state.

Settings → General → Canvas & Toolbar adds one optional switch, **Enable high contrast in screen drafts** (off by default). When enabled, every entry into screen mode starts with high contrast on. You can turn it off during that session; the next entry turns it on again. Leaving screen mode restores the paper canvas’s independent state. Changing the automatic option applies on the next entry.

PNG and PDF use the active high-contrast setting, including when exported during a transition. Editable `.inkey` files keep the original colors, line widths, font sizes, and objects; the display toggle never alters draft content. It can be switched off at any time.

## Eraser



In **Settings → Shortcuts → Modifiers → Temporary eraser**, choose Option (the default) or Command for hold-to-erase. Releasing the modifier restores the previous tool without changing the persistent tool preference. With Command selected, Option-click/drag selects and moves; with Option selected, Command-click/drag selects and moves. Release during an erasing drag stops it immediately; the remaining mouse movement is ignored until mouse-up, so it cannot erase further or create an unintended stroke. Focus loss also ends temporary erasing. Each erase gesture remains one undo step.

The crosshair is accompanied by a black-and-white circular outline for both persistent and temporary erasing. Its center follows the latest canvas mouse event, and its diameter matches the screen-space erasing footprint at every zoom and eraser size. The outline stays above text without intercepting mouse events, hides over toolbar controls, outside the canvas, or on focus loss, and is excluded from PNG/PDF exports.

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
Transient state such as a text selection, temporary modifier erasing, and an open
popover is not restored. Preferences are saved locally in macOS UserDefaults;
there is no Apply button. Invalid stored values fall back to safe defaults.

## Color

Editable presets sit in a compact, draggable bottom palette. Click **+** after the colors, choose a color or enter its HEX value, then click **Add** (or press Return) to save and select it. Esc, Cancel, or clicking outside cancels the addition and restores the previous ink. There is no six-preset limit: colors wrap into rows of six, and the toolbar grows or shrinks as needed. Option + 1–6 still selects the first six positions. Drag presets between rows to reorder them; additional positions are selected by clicking. Adding an existing color selects its preset without creating a duplicate.

Right-click a preset to edit or delete it. Editing offers Cancel and Done; accepting the picker saves the edit, and Escape cancels it. Deleting a preset shifts remaining colors and adjacent controls together, removes empty rows, and shrinks the toolbar to fit, with a compact minimum width for the shape controls. New swatches gently fade and scale in; buttons and the toolbar shell expand or contract with a short 0.22-second ease-out transition. Rapid deletions continue from their current on-screen positions; dragging, resizing, collapsing, hiding, or losing focus ends the transition. The animation respects macOS Reduce Motion. All presets may be deleted without losing the current ink color. Restore the default palette in Settings.

For a custom color without adding a preset, right-click **+** and choose **Custom color…**, or use **Shift + Command + C**. The picker includes a saturation/brightness surface, hue slider, six-digit HEX input, screen eyedropper, and six recent custom colors. Its **Replace current preset** and **Add** actions remain available. Hover over presets to see their names and available shortcuts.

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

Click the chevron to collapse or expand. Drag the chevron itself to move the toolbar in either state; dragging never triggers a collapse or expansion. The collapsed toolbar is a compact 36 × 36 pt chevron, with no reserved blank drag area. Its hit area and vector glyph keep the same size in both states, including in narrow windows; pressing it adds no blue selection background. A short transition (up to 0.4 seconds) gathers each tool, color, picker, and separator into the fixed-size chevron as the shell contracts. Pieces remain visible while converging and shrink into the chevron before disappearing; expansion unfolds them back to their original slots. The chevron rotates independently. Rapid reversals resume from the current presentation; dragging, resizing, changing appearance, hiding, or losing focus safely ends the transition. In Settings, “Toolbar folding animation” offers “Gather” (the default described above) and “Shrink & Fade” (the earlier animation). Shrink & Fade keeps the controls in their slots, fades them before the shell closes, and fades them in after opening begins (up to 0.32 seconds). The choice is saved and applies to the next toggle without restarting. Both use the corrected display path and keep rapid reversals continuous. The animation respects macOS Reduce Motion. Empty background also remains draggable. Drag the upper-right size handle horizontally to resize the expanded toolbar from 85% to 150%, or double-click it to restore 100%. More (···) offers the same size presets. Resizing previews immediately and saves on release; Escape or losing focus cancels. When the window is too small, the toolbar fits temporarily and restores the requested size as space returns. **Option + Command + T** toggles collapse (also in View and More); hiding or restoring is available only in More and through **Shift + Command + T**. There is no hide button on the toolbar. Collapse and visibility are remembered separately across launches. Color and shape shortcuts still work while hidden; opening a color or size picker reveals and expands its toolbar anchor.

## Text size and keyboard shortcuts

### Shape transforms

Right-click (or Control-click) a tool-drawn rectangle, ellipse, arrow, or line to select it. Closed shapes can be selected from their outline or interior. Drag inside a selected rectangle or ellipse's box to move it; drag one of its four corner handles to resize width and height while keeping the opposite corner fixed. Legacy square objects retain their square proportions. Small closed shapes keep a minimum 36 pt selection box so the movement area stays separate from the corner handles.

Rectangle and ellipse corners can pass across either axis through the fixed opposite corner, flipping horizontally, vertically, or both. Dragging can continue through zero width or height and back again without changing into a move operation. The diagonal resize cursor follows the active corner after a flip. Legacy squares can flip through their fixed corner while preserving square proportions. A flip remains part of the same undo step and preserves color and line width; returning to the starting position creates no undo step.

Arrows and straight lines have **two endpoint handles**, without a rectangular resize box. Drag either endpoint to change its length and direction while the other endpoint stays fixed. Drag the shaft away from the handles to move the entire object. Endpoint handles take priority over moving, with a hit radius of up to 8 pt; short lines reduce this radius to keep a separate movement area between their endpoints. Corner handles use diagonal resize cursors, endpoints use a crosshair, and movement uses an open hand followed by a closed hand while dragging. The operation is locked on mouse-down: crossing a handle or the shape interior mid-drag never switches between moving and resizing.

Click blank canvas or press Escape to deselect. Dragging on an unselected shape still draws; existing drawing tools, erasing, text editing, and image controls retain their behavior. Each move or resize is one undo step and preserves original color and line width. Transforms save in `.inkey` and appear in PNG/PDF exports. The same controls apply in screen drafts and with high contrast enabled.

### Clipboard

Use the configured Paste shortcut (Command-V by default) to paste a new text or image object centered on the canvas pointer, even while editing text. Text is pasted as plain text using the default typing font size and current ink. Images keep their aspect ratio and natural screen size, shrinking as needed to fit within 60% of the visible canvas width and height. If the pointer is outside the canvas, pasting uses the viewport center. Each paste is one undo step; existing text edits are committed separately.

Right-click (or Control-click) an image to select it and show its four corner handles. Drag the selected image to move it; drag a corner to resize proportionally while keeping the opposite corner fixed. Each move or resize is one undo step. Click blank canvas or press Escape to deselect. Hovering and double-clicking do not select images or enter text editing. Unselected images still allow freehand drawing over them. The original image data is preserved through resizing and draft saves. These controls also work on imported images and PDF page images.

Right-click text to enter precise editing and reveal its resize box. Drag the outer box border to move the entire label without holding a modifier. The entire editor interior belongs to native text selection, including empty areas after short lines and between lines; dragging there never starts a box move. Moving commits the current edit and keeps the label selected; the selected label can then be dragged anywhere inside its box to move it again. Each move is one undo step and keeps the font size and color unchanged. Ordinary dragging over unselected text still draws.

Drag any corner to scale the font uniformly while keeping the opposite corner fixed. One drag creates one undo step. Sizes range from **6–200 pt**. By default, the resized size becomes the default for the next text label; turn off **Use resized size for subsequent typing** in Settings to keep these independent. Set the default directly with the **Default typing font size** field or stepper. Existing labels keep their own size; changes to the default apply to newly created labels.

Settings → **Shortcuts** offers 37 configurable actions, searchable by action or group:

| Group | Actions |
| --- | --- |
| Global | Show/hide Inkey, enter/exit screen draft |
| File | New, open/import, recent drafts, save, save as, export |
| Editing | Undo, redo, cut, copy, paste, select all |
| Canvas & tools | Fit content, precise text editing, eraser, smaller/larger eraser, color picker, high contrast |
| Toolbar & window | Collapse/expand, hide/show toolbar, pin, full screen |
| Shape positions | Positions 1–4, from left to right |
| Color positions | Presets 1–6, from left to right |
| App | Settings, quit |

Click a shortcut to record it. Use Control, Option, or Command, or a function key; shape positions also accept Shift-number combinations. Ordinary typing keys are protected. Esc cancels recording; unmodified Delete clears the binding. Right-click a recorder to clear or restore that action's default. **Restore all defaults** restores all 37 bindings, including both global shortcuts. A per-action default that conflicts with another customized action is rejected until that conflict is cleared. Disabling a shortcut leaves its menu or toolbar action available.

Show/hide Inkey and Screen draft are global. Other shortcuts work within Inkey; text editing actions follow the focused native text editor and its undo history. The recorder consumes commands such as Command-Q and Command-S while recording, so they cannot quit or save accidentally. Existing app-level conflicts and reserved macOS combinations are rejected without changing the old binding. Global registration failure restores the previous registration when available. Shortcuts intercepted by macOS may require choosing another combination.

Changes apply immediately to event handling, menus, and toolbar hints and persist across launches. Existing customized global shortcuts are preserved automatically. Shapes and colors stay bound to toolbar **positions**, including after drag reordering. Shape/color shortcuts do not interrupt marked input-method text. Enter/Shift-Enter, Esc, deletion/navigation, Shift-drag shapes, scrolling, and pinching remain fixed to preserve native text input and gestures. The shortcut combinations elsewhere in this guide are defaults. Help → Keyboard shortcuts opens the same searchable settings page.

New text boxes keep their geometric center at the crosshair location throughout typing, Pinyin composition, deletion, and line breaks. Committing saves the corresponding top-left drawing origin so the center remains unchanged. Existing text boxes keep their stored position when reopened for editing. Live and saved text use the same canvas-space font metrics, line grid, and explicit character spacing; zoom scales the editor rather than changing its font size. Starting another label therefore keeps the previous label's position and layout unchanged, including at fractional zoom levels.
