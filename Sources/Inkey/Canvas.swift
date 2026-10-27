import AppKit

final class InlineTextView: NSTextView {
    private let textHistory = UndoManager()
    weak var canvas: CanvasView?
    var allowsMouseSelection = false
    override var undoManager: UndoManager? { canvas?.isEditing == false ? canvas?.undoManager : textHistory }

    func resetTextUndo() { textHistory.removeAllActions() }

    override var layer: CALayer? {
        get { super.layer }
        set {
            super.layer = newValue
            // NSTextView rounds its frame when AppKit first installs a layer.
            // Restore the exact canvas transform before that layer is displayed.
            canvas?.refreshTextLayout()
        }
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        canvas?.cancelTextHover()
        canvas?.prepareInputSession()
        canvas?.showTypingCaret()
        super.insertText(insertString, replacementRange: replacementRange)
        canvas?.refreshTextLayout()
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        canvas?.cancelTextHover()
        canvas?.prepareInputSession()
        canvas?.showTypingCaret()
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        canvas?.refreshTextLayout()
    }

    override func unmarkText() { super.unmarkText(); canvas?.refreshTextLayout() }

    func containsText(at windowPoint: NSPoint) -> Bool {
        guard let layoutManager, let textContainer else { return false }
        layoutManager.ensureLayout(for: textContainer)
        let point = convert(windowPoint, from: nil)
        if string.isEmpty { return NSRect(x: 0, y: 0, width: 16, height: font?.pointSize ?? 24).contains(point) }
        var contains = false
        layoutManager.enumerateLineFragments(forGlyphRange: layoutManager.glyphRange(for: textContainer)) { _, used, _, _, _ in
            let rect = used.offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y).insetBy(dx: -4, dy: -3)
            if rect.contains(point) { contains = true }
        }
        return contains
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let windowPoint = superview?.convert(point, to: nil) ?? point
        if canvas?.textResizeHandle(at: windowPoint) != nil || canvas?.canMoveText(at: windowPoint) == true { return nil }
        guard allowsMouseSelection, canvas?.eraserEnabled != true,
              !NSEvent.modifierFlags.contains(.option), !NSEvent.modifierFlags.contains(.command) else { return nil }
        // The whole native editor owns selection, including the empty ends of
        // shorter lines. Only the outside border belongs to box movement.
        return super.hitTest(point)
    }

    override func rightMouseDown(with event: NSEvent) { canvas?.rightMouseDown(with: event) }
    override func paste(_ sender: Any?) { canvas?.paste(sender) }
    override func mouseDown(with event: NSEvent) {
        canvas?.cancelTextHover()
        if event.modifierFlags.contains(.control) { canvas?.rightMouseDown(with: event) }
        else { super.mouseDown(with: event) }
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: canvas?.isHoverEditing == true ? .iBeam : .crosshair) }
    override func cursorUpdate(with event: NSEvent) { canvas?.interactionCursor(at: event.locationInWindow, modifiers: event.modifierFlags).set() }
    override func mouseMoved(with event: NSEvent) { canvas?.mouseMoved(with: event) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeInKeyWindow, .mouseEnteredAndExited, .enabledDuringMouseDrag], owner: self))
    }
    override func mouseExited(with event: NSEvent) { canvas?.textEditorPointerExited() }
    override func mouseEntered(with event: NSEvent) { canvas?.mouseMoved(with: event) }

    override func keyDown(with event: NSEvent) {
        canvas?.cancelTextHover()
        if let canvas, !canvas.isEditing {
            canvas.keyDown(with: event)
            return
        }
        if canvas?.preferences.shortcuts.binding(for: .preciseEdit)?.matches(event) == true {
            canvas?.promoteTextEditing(); return
        }
        if [UInt16(51), 117, 123, 124, 125, 126].contains(event.keyCode) {
            canvas?.keepCurrentTextForCorrection()
        } else if canvas?.retargetTypingIfNeeded(event, from: self) == true { return }
        canvas?.showTypingCaret()
        super.keyDown(with: event)
    }
    func acceptRoutedKey(_ event: NSEvent) { super.keyDown(with: event) }
    override func flagsChanged(with event: NSEvent) { canvas?.flagsChanged(with: event); super.flagsChanged(with: event) }
}

final class CanvasView: NSView, NSTextViewDelegate {
    let preferences: UserPreferences
    var onDefaultFontSizeChange: ((Double) -> Void)?
    var draft = Draft() { didSet { needsDisplay = true } }
    var ink = InkColor.light[0]
    var shiftShape: ShiftShape = .arrow
    var selection: UUID? { didSet { needsDisplay = true; window?.invalidateCursorRects(for: self) } }
    var onChange: (() -> Void)?
    var onEscape: (() -> Void)?
    var transparentBackground = false { didSet { needsDisplay = true } }
    private(set) var highContrastEnabled = false
    private(set) var contrastStrength: CGFloat = 0
    private var contrastTimer: Timer?

    func setHighContrast(_ enabled: Bool, animated: Bool = true) {
        highContrastEnabled = enabled
        refreshHighContrastSpacing()
        contrastTimer?.invalidate(); contrastTimer = nil
        let target: CGFloat = enabled ? 1 : 0
        guard animated, window?.isVisible == true, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            contrastStrength = target; needsDisplay = true; editor?.needsDisplay = true; return
        }
        let from = contrastStrength, start = ProcessInfo.processInfo.systemUptime
        contrastTimer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let progress = min(1, (ProcessInfo.processInfo.systemUptime - start) / 0.16)
            let eased = progress * progress * (3 - 2 * progress)
            self.contrastStrength = from + (target - from) * eased
            self.needsDisplay = true; self.editor?.needsDisplay = true
            if progress >= 1 { timer.invalidate(); self.contrastTimer = nil }
        }
        if let contrastTimer { RunLoop.main.add(contrastTimer, forMode: .common) }
    }
    var onInteraction: (() -> Void)?
    var displayTextTracking: CGFloat { highContrastEnabled ? preferences.highContrastTextSpacing / draft.zoom : 0 }
    func displayBounds(for item: InkItem, scale: CGFloat? = nil) -> NSRect {
        let tracking = highContrastEnabled ? preferences.highContrastTextSpacing / (scale ?? draft.zoom) : 0
        return InkTypography.displayBounds(for: item, tracking: tracking)
    }
    func refreshHighContrastSpacing() {
        refreshTextLayout(); needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }
    var pointPlacement: Bool { UserDefaults.standard.bool(forKey: "pointerPlacement") }
    private var active: InkItem?
    private var editor: InlineTextView?
    // Keep the native input client alive between labels so IMEs receive the first key.
    private var inputEditor: InlineTextView?
    private var editingID: UUID?
    private var textCenterAnchor: NSPoint?
    private var editingFontSize: Double = 20
    private var editingColor: InkColor?
    private var previewItems: [InkItem]?
    private var previewTextColor: InkColor?
    private var textResize: TextResizeGesture?
    private var imageResize: ImageResizeGesture?
    private var shapeResize: ShapeResizeGesture?
    private var hoverTimer: Timer?
    private var hoverStart: (point: NSPoint, time: TimeInterval)?
    private(set) var isHoverEditing = false
    private var moveStart: NSPoint?
    private var moveOriginal: [InkItem]?
    private struct PointerIntent {
        var start: NSPoint
        var viewStart: NSPoint
        var shape: InkKind
        var textClick: Bool
    }
    private var pendingPointer: PointerIntent?
    private var pointerPreview: NSPoint?
    private var typingPointerReference: NSPoint?
    private struct PointerSample { var point: NSPoint; var time: TimeInterval }
    private var pointerTrail: [PointerSample] = []
    private var trailTimer: Timer?
    var cursorTrailEnabled = true {
        didSet { if !cursorTrailEnabled { clearPointerTrail() } }
    }
    private var lastPointerLocation: NSPoint?
    private(set) var typingCaretVisible = false
    var isCanvasLocation: ((NSPoint) -> Bool)?
    private var eraseOriginal: [InkItem]?
    private var erasePrevious: InkPoint?
    private var temporaryEraseFlag: NSEvent.ModifierFlags?
    private var heldModifiers: NSEvent.ModifierFlags = []
    private var ignoreDragUntilMouseUp = false
    private var focusObserver: NSObjectProtocol?
    let eraserOutline = EraserOutlineView(frame: .zero)
    private var outlineSuppressed = false
    private(set) var eraserEnabled = false
    var eraserDiameter: Double = 24 {
        didSet { window?.invalidateCursorRects(for: self); updateEraserOutline() }
    }
    var onToolChange: ((Bool) -> Void)?
    private let history = UndoManager()
    private var imageCache: [UUID: NSImage] = [:]
    private var saveTimer: Timer?
    private var hintVisible = !UserDefaults.standard.bool(forKey: "didShowHint")
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var undoManager: UndoManager? { history }
    var isEditing: Bool { editor != nil }
    var isPrecisionEditing: Bool { editor?.allowsMouseSelection == true }
    var isDrawing: Bool { shapeResize != nil || imageResize != nil || textResize != nil || active != nil || moveStart != nil || pendingPointer != nil || eraseOriginal != nil }

    private var wantsNewTextAtPointer: Bool {
        guard pointPlacement, !isPrecisionEditing, let point = pointerPreview, let reference = typingPointerReference else { return false }
        return hypot(point.x - reference.x, point.y - reference.y) >= 12
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let focusObserver { NotificationCenter.default.removeObserver(focusObserver); self.focusObserver = nil }
        if let window {
            focusObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                self?.resetTemporaryEraser()
                self?.cancelTextHover()
                self?.leaveHoverEditing()
                self?.outlineSuppressed = true
                self?.eraserOutline.isHidden = true
            }
        }
        if window != nil { restoreFocus() }
    }

    deinit { contrastTimer?.invalidate(); hoverTimer?.invalidate(); trailTimer?.invalidate(); saveTimer?.invalidate(); if let focusObserver { NotificationCenter.default.removeObserver(focusObserver) } }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate], owner: self))
    }

    override func mouseMoved(with event: NSEvent) { outlineSuppressed = false; heldModifiers = event.modifierFlags; updatePointerLocation(event.locationInWindow); updateTextHover(at: event.locationInWindow); interactionCursor(at: event.locationInWindow, modifiers: event.modifierFlags).set() }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) { cancelTextHover(); leaveHoverEditing(); pointerPreview = nil; clearPointerTrail(); hideTypingCaret(); updateEraserOutline() }

    func cancelTextHover() {
        hoverTimer?.invalidate(); hoverTimer = nil; hoverStart = nil
    }

    func textEditorPointerExited() {
        // NSTextView handles selection drags in its own event loop. Track its
        // boundary directly so leaving and returning cannot reuse editing mode.
        cancelTextHover()
        leaveHoverEditing()
    }

    private func leaveHoverEditing() {
        guard isHoverEditing, editor?.hasMarkedText() != true else { return }
        isHoverEditing = false
        editor?.allowsMouseSelection = false
        if NSEvent.pressedMouseButtons == 0 {
            editor?.setSelectedRange(NSRange(location: editor?.selectedRange().location ?? 0, length: 0))
        }
        hideTypingCaret()
        window?.invalidateCursorRects(for: self)
        if let editor { window?.invalidateCursorRects(for: editor) }
        NSCursor.crosshair.set()
    }

    func updateTextHover(at windowPoint: NSPoint, time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        let point = convert(windowPoint, from: nil)
        if isHoverEditing, let editor, !editor.frame.contains(point) { textEditorPointerExited() }
        guard !isHoverEditing, !isPrecisionEditing, !isDrawing, !effectiveEraserEnabled,
              !canMoveShape(at: windowPoint), shapeEndpointHandle(at: windowPoint) == nil, shapeResizeHandle(at: windowPoint) == nil,
              heldModifiers.intersection([.shift, .command, .option, .control]).isEmpty,
              NSEvent.pressedMouseButtons == 0, window?.isKeyWindow == true,
              containsCanvasPoint(point), isCanvasLocation?(windowPoint) ?? true,
              editor?.hasMarkedText() != true else { cancelTextHover(); return }
        let liveHit = editor.map { !$0.string.isEmpty && $0.frame.contains(point) && $0.containsText(at: windowPoint) } ?? false
        let topContent = textOrImage(at: world(point))
        let saved = topContent?.kind == .text ? topContent : nil
        guard liveHit || saved != nil else { cancelTextHover(); return }
        if let start = hoverStart, hypot(windowPoint.x - start.point.x, windowPoint.y - start.point.y) <= 4 {
            guard time - start.time >= 0.45 else { return }
            cancelTextHover()
            if !liveHit, let saved { commitText(); selection = nil; beginText(at: saved.points[0].point, item: saved, showCaret: false) }
            guard let editor else { return }
            selection = nil
            isHoverEditing = true
            editor.allowsMouseSelection = true
            hideTypingCaret()
            clearPointerTrail()
            window?.invalidateCursorRects(for: editor)
            NSCursor.iBeam.set()
            needsDisplay = true
        } else {
            cancelTextHover()
            hoverStart = (windowPoint, time)
            hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.46, repeats: false) { [weak self] _ in
                self?.updateTextHover(at: self?.lastPointerLocation ?? windowPoint)
            }
        }
    }

    func updatePointerLocation(_ windowPoint: NSPoint) {
        let point = convert(windowPoint, from: nil)
        pointerPreview = containsCanvasPoint(point) && (isCanvasLocation?(windowPoint) ?? true) ? point : nil
        if lastPointerLocation.map({ hypot(windowPoint.x - $0.x, windowPoint.y - $0.y) > 0.1 }) ?? true {
            hideTypingCaret()
        }
        lastPointerLocation = windowPoint
        updateEraserOutline()
        if cursorTrailEnabled, pointerPreview != nil, !isDrawing, !isHoverEditing, !effectiveEraserEnabled, !typingCaretVisible {
            let now = ProcessInfo.processInfo.systemUptime
            pointerTrail.removeAll { now - $0.time > 0.18 }
            if let last = pointerTrail.last, hypot(point.x - last.point.x, point.y - last.point.y) > 160 { clearPointerTrail() }
            if pointerTrail.last.map({ hypot(point.x - $0.point.x, point.y - $0.point.y) >= 2 }) ?? true {
                pointerTrail.append(PointerSample(point: point, time: now))
                if pointerTrail.count > 24 { pointerTrail.removeFirst() }
            }
            if trailTimer == nil {
                trailTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                    guard let self else { return }
                    let now = ProcessInfo.processInfo.systemUptime
                    self.pointerTrail.removeAll { now - $0.time > 0.18 }
                    self.needsDisplay = true
                    if self.pointerTrail.isEmpty { self.clearPointerTrail() }
                }
            }
            needsDisplay = true
        } else { clearPointerTrail() }
    }

    private func clearPointerTrail() {
        pointerTrail.removeAll(); trailTimer?.invalidate(); trailTimer = nil; needsDisplay = true
    }

    func showTypingCaret() {
        clearPointerTrail()
        typingCaretVisible = editor != nil
        if typingCaretVisible { NSCursor.setHiddenUntilMouseMoves(true) }
        updateInsertionPreview()
    }

    private func hideTypingCaret() {
        typingCaretVisible = false
        updateInsertionPreview()
    }

    private func updateInsertionPreview() {
        if let editor {
            editor.insertionPointColor = typingCaretVisible ? (editingColor ?? ink).nsColor : .clear
            editor.needsDisplay = true
        }
        needsDisplay = true
    }

    func keepCurrentTextForCorrection(at windowPoint: NSPoint? = nil) {
        if let windowPoint { updatePointerLocation(windowPoint) }
        else { initializePointerIfNeeded() }
        typingPointerReference = pointerPreview
        showTypingCaret()
    }

    @discardableResult
    func retargetTypingIfNeeded(_ event: NSEvent, from text: InlineTextView, at windowPoint: NSPoint? = nil) -> Bool {
        guard editor === text, pointPlacement, !text.allowsMouseSelection, !text.hasMarkedText(),
              !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.control),
              ![UInt16(36), 48, 51, 53, 76, 117, 123, 124, 125, 126].contains(event.keyCode),
              let characters = event.characters, !characters.isEmpty,
              !characters.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || (0xF700...0xF8FF).contains($0.value) }) else { return false }
        if let windowPoint { updatePointerLocation(windowPoint) }
        else { initializePointerIfNeeded() }
        guard wantsNewTextAtPointer, let point = pointerPreview else { return false }
        commitText()
        selection = nil
        beginText(at: world(point))
        editor?.acceptRoutedKey(event)
        return true
    }

    func setEraserEnabled(_ enabled: Bool) {
        cancelTextHover(); leaveHoverEditing()
        clearPointerTrail()
        hideTypingCaret()
        finishPointerGesture()
        if enabled { commitText(); selection = nil }
        eraserEnabled = enabled
        updateEraserOutline()
        onToolChange?(enabled)
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    func promoteTextEditing() {
        guard let editor else { return }
        cancelTextHover(); isHoverEditing = false
        editor.allowsMouseSelection = true
        showTypingCaret()
        needsDisplay = true
        window?.invalidateCursorRects(for: editor)
    }

    override func flagsChanged(with event: NSEvent) {
        cancelTextHover()
        if !event.modifierFlags.intersection([.shift, .command, .option, .control]).isEmpty { leaveHoverEditing() }
        heldModifiers = event.modifierFlags
        endTemporaryEraseIfReleased(event.modifierFlags)
        if effectiveEraserEnabled { clearPointerTrail(); hideTypingCaret() }
        updateEraserOutline()
        window?.invalidateCursorRects(for: self)
        if let editor { window?.invalidateCursorRects(for: editor) }
        if let lastPointerLocation { interactionCursor(at: lastPointerLocation, modifiers: event.modifierFlags).set() }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
        guard !effectiveEraserEnabled else { return }
        if !heldModifiers.contains(.shift) {
            if let imageBoxFrame { addCursorRect(imageBoxFrame.insetBy(dx: 6, dy: 6), cursor: .openHand) }
            if let rect = textBoxFrame {
                if let editor {
                    addCursorRect(NSRect(x: rect.minX - 3, y: rect.minY - 3, width: rect.width + 6, height: editor.frame.minY - rect.minY + 3), cursor: .openHand)
                    addCursorRect(NSRect(x: rect.minX - 3, y: editor.frame.maxY, width: rect.width + 6, height: rect.maxY - editor.frame.maxY + 3), cursor: .openHand)
                    addCursorRect(NSRect(x: rect.minX - 3, y: editor.frame.minY, width: editor.frame.minX - rect.minX + 3, height: editor.frame.height), cursor: .openHand)
                    addCursorRect(NSRect(x: editor.frame.maxX, y: editor.frame.minY, width: rect.maxX - editor.frame.maxX + 3, height: editor.frame.height), cursor: .openHand)
                } else { addCursorRect(rect.insetBy(dx: -3, dy: -3), cursor: .openHand) }
            }
        }
        for rect in [textBoxFrame, imageBoxFrame].compactMap({ $0 }) {
            for corner in TextResizeCorner.allCases {
                let point = corner.point(in: rect)
                addCursorRect(NSRect(x: point.x - 8, y: point.y - 8, width: 16, height: 16), cursor: corner.resizeCursor)
            }
        }
    }
    override func cursorUpdate(with event: NSEvent) { interactionCursor(at: event.locationInWindow, modifiers: event.modifierFlags).set() }

    func interactionCursor(at windowPoint: NSPoint, modifiers: NSEvent.ModifierFlags = []) -> NSCursor {
        if eraserEnabled || modifiers.contains(preferences.temporaryEraserModifier.flag) { return .crosshair }
        if let resize = imageResize { return resize.corner.resizeCursor }
        if let resize = shapeResize { return resize.endpoint == nil ? resize.corner.resizeCursor : .crosshair }
        if let resize = textResize { return resize.corner.resizeCursor }
        if moveStart != nil { return .closedHand }
        if active != nil || pendingPointer != nil || ignoreDragUntilMouseUp { return .crosshair }
        if shapeEndpointHandle(at: windowPoint) != nil { return .crosshair }
        if let corner = shapeResizeHandle(at: windowPoint) ?? imageResizeHandle(at: windowPoint) ?? textResizeHandle(at: windowPoint) { return corner.resizeCursor }
        if !modifiers.contains(.shift), !modifiers.contains(.control) {
            let hit = item(at: world(convert(windowPoint, from: nil)))
            if modifiers.contains(preferences.temporaryEraserModifier.moveFlag), hit != nil { return .openHand }
            if canMoveText(at: windowPoint) { return .openHand }
            if canMoveShape(at: windowPoint) { return .openHand }
            if let selection, hit?.id == selection, hit?.kind == .image { return .openHand }
        }
        if isHoverEditing, let editor, editor.frame.contains(convert(windowPoint, from: nil)) { return .iBeam }
        return .crosshair
    }

    var effectiveEraserEnabled: Bool { eraserEnabled || heldModifiers.contains(preferences.temporaryEraserModifier.flag) }
    var eraserOutlineRect: NSRect? {
        guard effectiveEraserEnabled, let point = pointerPreview else { return nil }
        return NSRect(x: point.x - eraserDiameter / 2, y: point.y - eraserDiameter / 2, width: eraserDiameter, height: eraserDiameter)
    }
    private func updateEraserOutline() {
        guard !outlineSuppressed, let rect = eraserOutlineRect else { eraserOutline.isHidden = true; return }
        if eraserOutline.superview !== self { addSubview(eraserOutline) }
        else if subviews.last !== eraserOutline { addSubview(eraserOutline, positioned: .above, relativeTo: nil) }
        eraserOutline.frame = rect.insetBy(dx: -2, dy: -2)
        eraserOutline.isHidden = false; eraserOutline.needsDisplay = true
    }
    private func endTemporaryEraseIfReleased(_ flags: NSEvent.ModifierFlags) {
        guard let temporaryEraseFlag, !flags.contains(temporaryEraseFlag) else { return }
        finishPointerGesture()
        ignoreDragUntilMouseUp = true
    }
    func resetTemporaryEraser() {
        if temporaryEraseFlag != nil { finishPointerGesture(); ignoreDragUntilMouseUp = true }
        heldModifiers = []; updateEraserOutline()
    }

    func restoreFocus() {
        guard window != nil else { return }
        window?.makeFirstResponder(ensureInputEditor())
    }

    func beginColorPreview() {
        previewItems = draft.items
        previewTextColor = editingColor
    }

    func finishColorPreview(accept: Bool, original: InkColor) {
        if let previous = previewItems {
            let updated = draft.items
            draft.items = previous
            previewItems = nil
            if accept && updated != previous { replaceItems(updated, name: "Change Color") }
        }
        if !accept {
            ink = original
            editingColor = previewTextColor
            editor?.textColor = (previewTextColor ?? original).nsColor
            editor?.typingAttributes[.foregroundColor] = (previewTextColor ?? original).nsColor
        }
        previewTextColor = nil
        needsDisplay = true
    }

    init(frame: NSRect, preferences: UserPreferences = UserPreferences()) {
        self.preferences = preferences
        super.init(frame: frame)
        history.groupsByEvent = false
        wantsLayer = true
        eraserOutline.isHidden = true
        setAccessibilityLabel("Draft canvas")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func install(_ value: Draft) {
        commitText()
        finishPointerGesture()
        draft = value; selection = nil; active = nil
        history.removeAllActions(); imageCache.removeAll()
    }

    func changed() {
        draft.modified = Date()
        needsDisplay = true
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in self?.onChange?() }
    }

    func flush() { finishPointerGesture(); commitText(); saveTimer?.invalidate(); onChange?() }

    func replaceItems(_ items: [InkItem], name: String) {
        let previous = draft.items
        history.beginUndoGrouping()
        history.registerUndo(withTarget: self) { view in view.replaceItems(previous, name: name) }
        history.setActionName(name)
        history.endUndoGrouping()
        draft.items = items
        changed()
    }

    func applyColor(_ color: InkColor) {
        ink = color
        if let editor {
            editingColor = color
            editor.textColor = color.nsColor
            editor.typingAttributes[.foregroundColor] = color.nsColor
        } else if let selection, let index = draft.items.firstIndex(where: { $0.id == selection }) {
            var items = draft.items; items[index].color = color
            if previewItems != nil { draft.items = items }
            else { replaceItems(items, name: "Change Color") }
        }
        needsDisplay = true
    }

    func world(_ point: NSPoint) -> NSPoint {
        NSPoint(x: (point.x - draft.offset.x) / draft.zoom, y: (point.y - draft.offset.y) / draft.zoom)
    }
    func screen(_ point: NSPoint) -> NSPoint {
        NSPoint(x: point.x * draft.zoom + draft.offset.x, y: point.y * draft.zoom + draft.offset.y)
    }
    func containsCanvasPoint(_ point: NSPoint) -> Bool { bounds.insetBy(dx: 12, dy: 12).contains(point) }
    func item(at point: NSPoint) -> InkItem? {
        draft.items.reversed().first {
            $0.kind == .text ? displayBounds(for: $0).insetBy(dx: -7 / draft.zoom, dy: -7 / draft.zoom).contains(point) : $0.hit(point, tolerance: 7 / draft.zoom)
        }
    }
    private func textOrImage(at point: NSPoint) -> InkItem? {
        draft.items.reversed().first {
            $0.id != editingID && ($0.kind == .text || $0.kind == .image) && displayBounds(for: $0).contains(point)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        if transparentBackground {
            // WindowServer treats zero-alpha pixels as click-through. Keep a
            // uniform, nearly invisible input surface so underlying apps cannot
            // compete for the cursor as the crosshair trail appears and fades.
            context.saveGState()
            context.setBlendMode(.copy)
            context.setFillColor(NSColor.black.withAlphaComponent(0.01).cgColor)
            context.fill(bounds)
            context.restoreGState()
        } else { draft.background.nsColor.setFill(); bounds.fill() }
        context.saveGState()
        context.translateBy(x: draft.offset.x, y: draft.offset.y)
        context.scaleBy(x: draft.zoom, y: draft.zoom)
        for item in draft.items where item.id != editingID { render(item) }
        if let active { render(active) }
        if let selection, let item = draft.items.first(where: { $0.id == selection }), !item.usesEndpointHandles {
            let rect: NSRect
            if let frame = shapeBoxFrame, item.isTransformableShape {
                rect = NSRect(origin: world(frame.origin), size: NSSize(width: frame.width / draft.zoom, height: frame.height / draft.zoom))
            } else {
                rect = item.kind == .text ? displayBounds(for: item).insetBy(dx: -5 / draft.zoom, dy: -4 / draft.zoom) : item.bounds.insetBy(dx: -6 / draft.zoom, dy: -6 / draft.zoom)
            }
            NSColor.controlAccentColor.withAlphaComponent(0.65).setStroke()
            let border = NSBezierPath(roundedRect: rect, xRadius: 4 / draft.zoom, yRadius: 4 / draft.zoom)
            border.lineWidth = 1 / draft.zoom; border.setLineDash([4 / draft.zoom, 3 / draft.zoom], count: 2, phase: 0); border.stroke()
        }
        context.restoreGState()
        if contrastStrength > 0, let editor, let manager = editor.layoutManager as? InkTextLayoutManager, let container = editor.textContainer {
            // The native editor clips at its own bounds; render only the halo
            // outside that rectangle here so glyphs near an edge keep their rim.
            context.saveGState()
            context.addRect(bounds); context.addRect(editor.frame); context.clip(using: .evenOdd)
            context.translateBy(x: editor.frame.minX, y: editor.frame.minY)
            context.scaleBy(x: draft.zoom, y: draft.zoom)
            manager.drawContrast(forGlyphRange: manager.glyphRange(for: container), at: editor.textContainerOrigin)
            context.restoreGState()
        }
        if editor == nil, let selection, let item = draft.items.first(where: { $0.id == selection }), item.kind == .text {
            drawTextResizeHandles(in: viewRect(displayBounds(for: item)).insetBy(dx: -5, dy: -4))
        }
        if let imageBoxFrame { drawTextResizeHandles(in: imageBoxFrame) }
        if let shapeBoxFrame { drawTextResizeHandles(in: shapeBoxFrame) }
        if let selection, let shape = draft.items.first(where: { $0.id == selection && $0.usesEndpointHandles }) {
            for point in [shape.points.first, shape.points.last].compactMap({ $0 }) { drawResizeHandle(at: screen(point.point)) }
        }
        if cursorTrailEnabled, !typingCaretVisible, !isDrawing, !isHoverEditing, !effectiveEraserEnabled {
            let now = ProcessInfo.processInfo.systemUptime
            for (a, b) in zip(pointerTrail, pointerTrail.dropFirst()) {
                let remaining = max(0, 1 - (now - a.time) / 0.18)
                ink.nsColor.withAlphaComponent(0.16 * remaining * remaining).setStroke()
                let trail = NSBezierPath(); trail.lineWidth = 1.5; trail.lineCapStyle = .round
                trail.move(to: a.point); trail.line(to: b.point); trail.stroke()
            }
        }
        if let editor, editor.allowsMouseSelection, !isHoverEditing {
            NSColor.controlAccentColor.withAlphaComponent(0.25).setStroke()
            let border = NSBezierPath(roundedRect: editor.frame.insetBy(dx: -5, dy: -4), xRadius: 4, yRadius: 4)
            border.lineWidth = 1; border.stroke()
            drawTextResizeHandles(in: editor.frame.insetBy(dx: -5, dy: -4))
        }
        if hintVisible && !transparentBackground && draft.items.isEmpty && editor == nil {
            let text = "直接打字，拖动绘画。" as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor]
            let size = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: bounds.height / 2), withAttributes: attributes)
        }
    }

    func render(_ item: InkItem) {
        guard let first = item.points.first?.point else { return }
        if item.kind == .text {
            InkTypography.draw(item.text, at: first, size: item.fontSize, color: item.color, contrast: contrastStrength, scale: draft.zoom, tracking: displayTextTracking)
            return
        }
        if item.kind == .image {
            let image = imageCache[item.id] ?? item.imageData.flatMap(NSImage.init(data:))
            if let image { imageCache[item.id] = image; image.draw(in: item.bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil) }
            return
        }
        let path = NSBezierPath(); path.lineWidth = item.lineWidth; path.lineCapStyle = .round; path.lineJoinStyle = .round
        path.move(to: first)
        let points = item.points.map(\.point)
        if item.kind == .arrow, let end = points.last {
            path.line(to: end)
            let angle = atan2(end.y - first.y, end.x - first.x)
            let length = min(13.0, max(6.0, hypot(end.x - first.x, end.y - first.y) * 0.25))
            let head = NSBezierPath()
            head.move(to: NSPoint(x: end.x - length * cos(angle - 0.48), y: end.y - length * sin(angle - 0.48)))
            head.line(to: end); head.line(to: NSPoint(x: end.x - length * cos(angle + 0.48), y: end.y - length * sin(angle + 0.48)))
            path.append(head)
        } else if item.kind == .ellipse, let end = points.last {
            let oval = NSBezierPath(ovalIn: NSRect(x: min(first.x, end.x), y: min(first.y, end.y), width: abs(end.x - first.x), height: abs(end.y - first.y)))
            path.append(oval)
        } else if [.line, .square, .rectangle].contains(item.kind) {
            let vertices = item.outline.map(\.point)
            path.removeAllPoints()
            if let start = vertices.first { path.move(to: start) }
            for point in vertices.dropFirst() { path.line(to: point) }
        } else if points.count < 3 {
            if let end = points.last { path.line(to: end) }
        } else {
            for index in 1..<points.count - 1 {
                let midpoint = NSPoint(x: (points[index].x + points[index + 1].x) / 2, y: (points[index].y + points[index + 1].y) / 2)
                let previous = index == 1 ? points[0] : NSPoint(x: (points[index - 1].x + points[index].x) / 2, y: (points[index - 1].y + points[index].y) / 2)
                let control1 = NSPoint(x: previous.x + (points[index].x - previous.x) * 2 / 3, y: previous.y + (points[index].y - previous.y) * 2 / 3)
                let control2 = NSPoint(x: midpoint.x + (points[index].x - midpoint.x) * 2 / 3, y: midpoint.y + (points[index].y - midpoint.y) * 2 / 3)
                path.curve(to: midpoint, controlPoint1: control1, controlPoint2: control2)
            }
            path.line(to: points.last!)
        }
        if contrastStrength > 0 {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.cgContext.setAlpha(contrastStrength)
            for (color, width) in [(NSColor.white, CGFloat(4)), (.black, CGFloat(2))] {
                color.setStroke(); path.lineWidth = item.lineWidth + width / draft.zoom; path.stroke()
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        item.color.nsColor.setStroke(); path.lineWidth = item.lineWidth; path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        defer { interactionCursor(at: event.locationInWindow, modifiers: event.modifierFlags).set() }
        cancelTextHover()
        if event.modifierFlags.contains(.control) { rightMouseDown(with: event); return }
        ignoreDragUntilMouseUp = false; heldModifiers = event.modifierFlags
        outlineSuppressed = false
        clearPointerTrail()
        hideTypingCaret()
        onInteraction?()
        if !effectiveEraserEnabled, let endpoint = shapeEndpointHandle(at: event.locationInWindow),
           let selection, let shape = draft.items.first(where: { $0.id == selection }) {
            shapeResize = ShapeResizeGesture(items: draft.items, item: shape, corner: .bottomRight,
                                             start: world(convert(event.locationInWindow, from: nil)), endpoint: endpoint)
            return
        }
        if !effectiveEraserEnabled, let corner = shapeResizeHandle(at: event.locationInWindow),
           let selection, let shape = draft.items.first(where: { $0.id == selection && $0.isTransformableShape }) {
            shapeResize = ShapeResizeGesture(items: draft.items, item: shape, corner: corner, start: world(convert(event.locationInWindow, from: nil)))
            return
        }
        if !effectiveEraserEnabled, let corner = imageResizeHandle(at: event.locationInWindow),
           let selection, let image = draft.items.first(where: { $0.id == selection && $0.kind == .image }) {
            imageResize = ImageResizeGesture(items: draft.items, item: image, corner: corner, start: world(convert(event.locationInWindow, from: nil)))
            return
        }
        if !effectiveEraserEnabled, let corner = textResizeHandle(at: event.locationInWindow) {
            beginTextResize(corner, at: event.locationInWindow); return
        }
        updatePointerLocation(event.locationInWindow)
        let viewPoint = convert(event.locationInWindow, from: nil)
        let p = world(viewPoint)
        dismissHint()
        if effectiveEraserEnabled {
            commitText(); restoreFocus(); selection = nil
            temporaryEraseFlag = eraserEnabled ? nil : preferences.temporaryEraserModifier.flag
            eraseOriginal = draft.items
            let point = InkPoint(p); erasePrevious = point
            draft.items = InkEraser.erase(draft.items, from: point, to: point, radius: eraserDiameter / (2 * draft.zoom))
            needsDisplay = true; return
        }
        if event.modifierFlags.contains(preferences.temporaryEraserModifier.moveFlag) {
            commitText(); restoreFocus()
            selection = item(at: p)?.id
            if selection != nil { moveStart = p; moveOriginal = draft.items }
            return
        }
        if !event.modifierFlags.contains(.shift) {
            if canMoveShape(at: event.locationInWindow) {
                moveStart = p; moveOriginal = draft.items
                return
            }
            let hit = item(at: p)
            if let selection, hit?.id == selection, hit?.kind == .image {
                moveStart = p; moveOriginal = draft.items
                return
            }
        }
        if !event.modifierFlags.contains(.shift), canMoveText(at: event.locationInWindow) {
            beginTextMove(at: p)
            return
        }
        if let editor, editor.containsText(at: event.locationInWindow), !event.modifierFlags.contains(.shift) {
            pendingPointer = PointerIntent(start: p, viewStart: viewPoint, shape: .stroke, textClick: true)
            return
        }
        commitText()
        restoreFocus()
        selection = nil
        pendingPointer = PointerIntent(start: p, viewStart: viewPoint, shape: event.modifierFlags.contains(.shift) ? shiftShape.kind : .stroke, textClick: false)
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        defer { interactionCursor(at: event.locationInWindow, modifiers: event.modifierFlags).set() }
        cancelTextHover()
        onInteraction?()
        if let editor, !editor.string.isEmpty, editor.containsText(at: event.locationInWindow) {
            editor.unmarkText()
            promoteTextEditing(); positionTextCaret(at: event.locationInWindow); editor.selectWord(nil)
            return
        }
        let point = world(convert(event.locationInWindow, from: nil))
        guard let hit = draft.items.reversed().first(where: {
            $0.id != editingID && ($0.isTransformableShape ? $0.containsShape(point, tolerance: 7 / draft.zoom) :
                (($0.kind == .text || $0.kind == .image) && displayBounds(for: $0).contains(point)))
        }) else { return }
        if hit.kind == .image || hit.isTransformableShape {
            commitText(); restoreFocus()
            selection = hit.id
            return
        }
        commitText(); selection = nil
        beginText(at: hit.points[0].point, item: hit)
        promoteTextEditing(); positionTextCaret(at: event.locationInWindow); editor?.selectWord(nil)
    }

    private func viewRect(_ rect: NSRect) -> NSRect {
        NSRect(origin: screen(rect.origin), size: NSSize(width: rect.width * draft.zoom, height: rect.height * draft.zoom))
    }
    var shapeBoxFrame: NSRect? {
        guard let selection, let shape = draft.items.first(where: { $0.id == selection && $0.isTransformableShape && !$0.usesEndpointHandles }) else { return nil }
        let rect = viewRect(shape.bounds).insetBy(dx: -6, dy: -6)
        // Leave a clear movement zone even around a tiny closed shape.
        return NSRect(x: rect.midX - max(36, rect.width) / 2, y: rect.midY - max(36, rect.height) / 2,
                      width: max(36, rect.width), height: max(36, rect.height))
    }
    func shapeResizeHandle(at windowPoint: NSPoint) -> TextResizeCorner? {
        guard let rect = shapeBoxFrame else { return nil }
        let point = convert(windowPoint, from: nil)
        return TextResizeCorner.allCases.first {
            let handle = $0.point(in: rect)
            return hypot(point.x - handle.x, point.y - handle.y) <= 8
        }
    }
    func canMoveShape(at windowPoint: NSPoint) -> Bool {
        if let selection, let shape = draft.items.first(where: { $0.id == selection && $0.usesEndpointHandles }) {
            return shapeEndpointHandle(at: windowPoint) == nil && shape.hit(world(convert(windowPoint, from: nil)), tolerance: 7 / draft.zoom)
        }
        guard let rect = shapeBoxFrame, shapeResizeHandle(at: windowPoint) == nil else { return false }
        return rect.contains(convert(windowPoint, from: nil))
    }
    func shapeEndpointHandle(at windowPoint: NSPoint) -> Int? {
        guard let selection, let shape = draft.items.first(where: { $0.id == selection && $0.usesEndpointHandles }), shape.points.count >= 2 else { return nil }
        let point = convert(windowPoint, from: nil)
        let a = screen(shape.points[0].point), b = screen(shape.points[shape.points.count - 1].point)
        // Keep a movement strip between the endpoints even for short arrows.
        let radius = min(8, hypot(a.x - b.x, a.y - b.y) / 3)
        return [0, shape.points.count - 1].min(by: {
            let a = screen(shape.points[$0].point), b = screen(shape.points[$1].point)
            return hypot(point.x - a.x, point.y - a.y) < hypot(point.x - b.x, point.y - b.y)
        }).flatMap { index in
            let handle = screen(shape.points[index].point)
            return hypot(point.x - handle.x, point.y - handle.y) <= radius ? index : nil
        }
    }
    var imageBoxFrame: NSRect? {
        guard let selection, let image = draft.items.first(where: { $0.id == selection && $0.kind == .image }) else { return nil }
        return viewRect(image.bounds).insetBy(dx: -6, dy: -6)
    }
    func imageResizeHandle(at windowPoint: NSPoint) -> TextResizeCorner? {
        guard let rect = imageBoxFrame else { return nil }
        let point = convert(windowPoint, from: nil)
        return TextResizeCorner.allCases.first {
            let handle = $0.point(in: rect)
            return hypot(point.x - handle.x, point.y - handle.y) <= 8
        }
    }
    var textBoxFrame: NSRect? {
        if isHoverEditing { return nil }
        if let editor, editor.allowsMouseSelection, !editor.string.isEmpty { return editor.frame.insetBy(dx: -5, dy: -4) }
        if let selection, let item = draft.items.first(where: { $0.id == selection }), item.kind == .text {
            return viewRect(displayBounds(for: item)).insetBy(dx: -5, dy: -4)
        }
        return nil
    }
    func textResizeHandle(at windowPoint: NSPoint) -> TextResizeCorner? {
        guard let rect = textBoxFrame else { return nil }
        let point = convert(windowPoint, from: nil)
        if let editor, editor.frame.contains(point) { return nil }
        return TextResizeCorner.allCases.first {
            let handle = $0.point(in: rect)
            return hypot(point.x - handle.x, point.y - handle.y) <= 8
        }
    }
    func canMoveText(at windowPoint: NSPoint) -> Bool {
        guard let rect = textBoxFrame,
              rect.insetBy(dx: -3, dy: -3).contains(convert(windowPoint, from: nil)),
              textResizeHandle(at: windowPoint) == nil else { return false }
        // Never steal a native text drag, even when it starts between lines or
        // beyond the end of a short line. Moving starts outside the editor only.
        if let editor {
            let point = convert(windowPoint, from: nil)
            return !editor.frame.contains(point)
        }
        return true
    }
    private func beginTextMove(at point: NSPoint) {
        let currentID = editor != nil ? editingID : selection
        let wasEditing = editor != nil
        commitText()
        guard let id = currentID ?? (wasEditing ? draft.items.last?.id : nil),
              draft.items.contains(where: { $0.id == id && $0.kind == .text }) else { return }
        selection = id
        moveStart = point
        moveOriginal = draft.items
        restoreFocus()
    }
    private func drawTextResizeHandles(in rect: NSRect) {
        for corner in TextResizeCorner.allCases {
            drawResizeHandle(at: corner.point(in: rect))
        }
    }
    private func drawResizeHandle(at point: NSPoint) {
        let handle = NSBezierPath(ovalIn: NSRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6))
        draft.background.nsColor.setFill(); handle.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.8).setStroke(); handle.lineWidth = 1; handle.stroke()
    }
    private func beginTextResize(_ corner: TextResizeCorner, at windowPoint: NSPoint) {
        let currentID = editor != nil ? editingID : selection
        let wasEditing = editor != nil
        commitText()
        guard let id = currentID ?? (wasEditing ? draft.items.last?.id : nil),
              let item = draft.items.first(where: { $0.id == id }), item.kind == .text else { return }
        selection = id
        textResize = TextResizeGesture(items: draft.items, item: item, corner: corner, start: world(convert(windowPoint, from: nil)), textTracking: displayTextTracking)
    }

    private func positionTextCaret(at windowPoint: NSPoint) {
        guard let editor else { return }
        let point = editor.convert(windowPoint, from: nil)
        editor.setSelectedRange(NSRange(location: editor.characterIndexForInsertion(at: point), length: 0))
        window?.makeFirstResponder(editor)
        showTypingCaret()
    }

    override func mouseDragged(with event: NSEvent) {
        defer { interactionCursor(at: event.locationInWindow, modifiers: event.modifierFlags).set() }
        heldModifiers = event.modifierFlags
        endTemporaryEraseIfReleased(event.modifierFlags)
        if effectiveEraserEnabled || ignoreDragUntilMouseUp { updatePointerLocation(event.locationInWindow) }
        guard !ignoreDragUntilMouseUp else { return }
        let p = world(convert(event.locationInWindow, from: nil))
        if let resize = shapeResize {
            let shape = resize.resized(to: p)
            draft.items = resize.items.map { $0.id == shape.id ? shape : $0 }
        } else if let resize = imageResize {
            let image = resize.resized(to: p)
            draft.items = resize.items.map { $0.id == image.id ? image : $0 }
        } else if let resize = textResize {
            let item = resize.resized(to: p)
            draft.items = resize.items.map { $0.id == item.id ? item : $0 }
        } else if let previous = erasePrevious {
            let point = InkPoint(p)
            draft.items = InkEraser.erase(draft.items, from: previous, to: point, radius: eraserDiameter / (2 * draft.zoom))
            erasePrevious = point
        } else if let start = moveStart, let original = moveOriginal, let selection {
            draft.items = original.map { item in
                guard item.id == selection else { return item }
                var moved = item; moved.translate(x: p.x - start.x, y: p.y - start.y); return moved
            }
        } else {
            if let pending = pendingPointer {
                let current = convert(event.locationInWindow, from: nil)
                guard hypot(current.x - pending.viewStart.x, current.y - pending.viewStart.y) >= 3 else { return }
                commitText(); restoreFocus()
                draft.anchor = InkPoint(pending.start)
                active = InkItem(kind: pending.shape, points: [InkPoint(pending.start)], color: ink)
                pendingPointer = nil
            }
            guard var drawing = active else { return }
            if drawing.kind != .stroke { drawing.points = [drawing.points[0], InkPoint(p)] }
            else if let last = drawing.points.last, hypot(p.x - last.x, p.y - last.y) * draft.zoom > 0.7 { drawing.points.append(InkPoint(p)) }
            active = drawing
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { window?.invalidateCursorRects(for: self); interactionCursor(at: event.locationInWindow, modifiers: event.modifierFlags).set() }
        heldModifiers = event.modifierFlags
        if effectiveEraserEnabled || eraseOriginal != nil || ignoreDragUntilMouseUp { updatePointerLocation(event.locationInWindow) }
        if let pending = pendingPointer {
            if pending.textClick { positionTextCaret(at: event.locationInWindow) }
            else { draft.anchor = InkPoint(pending.start); changed() }
        }
        finishPointerGesture()
        ignoreDragUntilMouseUp = false
    }

    private func finishPointerGesture() {
        if let resize = shapeResize {
            let updated = draft.items
            draft.items = resize.items
            if updated != resize.items { replaceItems(updated, name: "Resize Shape") }
            shapeResize = nil
        } else if let resize = imageResize {
            let updated = draft.items
            draft.items = resize.items
            if updated != resize.items { replaceItems(updated, name: "Resize Image") }
            imageResize = nil
        } else if let resize = textResize {
            let updated = draft.items
            draft.items = resize.items
            if updated != resize.items {
                replaceItems(updated, name: "Resize Text")
                if preferences.resizeUpdatesDefaultFont, let resized = updated.first(where: { $0.id == resize.item.id }) {
                    preferences.defaultFontSize = resized.fontSize
                    onDefaultFontSizeChange?(resized.fontSize)
                }
            }
            textResize = nil
        } else if let original = eraseOriginal {
            let erased = draft.items; draft.items = original
            if erased != original { replaceItems(erased, name: "Erase") }
        } else if let original = moveOriginal {
            let moved = draft.items; draft.items = original
            if moved != original { replaceItems(moved, name: "Move") }
        } else if let active, active.points.count > 1 {
            replaceItems(draft.items + [active], name: active.kind == .arrow ? "Arrow" : "Draw")
        }
        active = nil; moveStart = nil; moveOriginal = nil
        eraseOriginal = nil; erasePrevious = nil; pendingPointer = nil
        temporaryEraseFlag = nil
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { escape(); return }
        if event.keyCode == 51 || event.keyCode == 117 {
            if let selection { replaceItems(draft.items.filter { $0.id != selection }, name: "Delete"); self.selection = nil }
            return
        }
        guard !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.control),
              let characters = event.characters, !characters.isEmpty,
              ![UInt16(36), 48, 76, 123, 124, 125, 126].contains(event.keyCode),
              !characters.unicodeScalars.contains(where: { $0.value >= 0xF700 && $0.value <= 0xF8FF }) else { super.keyDown(with: event); return }
        prepareInputSession()
        editor?.acceptRoutedKey(event)
    }

    func prepareInputSession() {
        guard editor == nil else { return }
        selection = nil
        var anchor = draft.anchor.point
        if pointPlacement {
            initializePointerIfNeeded()
            if let pointerPreview { anchor = world(pointerPreview) }
        }
        beginText(at: anchor)
    }

    private func initializePointerIfNeeded() {
        // Event coordinates are authoritative. Sampling again after activation or IME dispatch
        // can report a different location from the crosshair that the user just moved.
        if lastPointerLocation == nil, let window { updatePointerLocation(window.mouseLocationOutsideOfEventStream) }
    }

    @objc func paste(_ sender: Any?) { pasteContents(from: .general) }

    func pasteContents(from pasteboard: NSPasteboard) {
        initializePointerIfNeeded()
        let center = world(pointerPreview ?? NSPoint(x: bounds.midX, y: bounds.midY))
        var pasted: InkItem
        if let image = (pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage])?.first,
           image.size.width > 0, image.size.height > 0, let data = image.tiffRepresentation {
            // Keep small images at their natural screen size; fit larger ones to
            // 60% of the visible canvas in each direction, preserving aspect ratio.
            let scale = min(1, bounds.width * 0.6 / image.size.width, bounds.height * 0.6 / image.size.height)
            let width = image.size.width * scale / draft.zoom
            let height = image.size.height * scale / draft.zoom
            pasted = InkItem(kind: .image, points: [InkPoint(NSPoint(x: center.x - width / 2, y: center.y - height / 2))], color: ink, imageData: data, imageWidth: width, imageHeight: height)
        } else if let text = pasteboard.string(forType: .string), !text.isEmpty {
            let size = InkTypography.size(text, fontSize: preferences.defaultFontSize)
            pasted = InkItem(kind: .text, points: [InkPoint(NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))], color: ink, text: text, fontSize: preferences.defaultFontSize)
        } else { return }
        finishPointerGesture()
        commitText()
        selection = nil
        dismissHint()
        replaceItems(draft.items + [pasted], name: "Paste")
        restoreFocus()
    }

    private func ensureInputEditor() -> InlineTextView {
        if let inputEditor { return inputEditor }
        let text = InlineTextView(frame: NSRect(origin: screen(draft.anchor.point), size: NSSize(width: 16, height: 26)))
        let manager = InkTextLayoutManager()
        manager.contrastStrength = { [weak self] in self?.contrastStrength ?? 0 }
        manager.renderingScale = { [weak self] in self?.draft.zoom ?? 1 }
        text.textContainer?.replaceLayoutManager(manager)
        text.canvas = self
        text.delegate = self; text.isRichText = false; text.drawsBackground = false
        text.font = InkTypography.font(20)
        text.textColor = ink.nsColor; text.insertionPointColor = .clear
        text.textContainerInset = .zero; text.textContainer?.lineFragmentPadding = 0
        text.isAutomaticQuoteSubstitutionEnabled = false; text.isAutomaticDashSubstitutionEnabled = false
        text.isAutomaticSpellingCorrectionEnabled = false; text.isContinuousSpellCheckingEnabled = false
        text.isAutomaticTextReplacementEnabled = false
        text.isHorizontallyResizable = false; text.isVerticallyResizable = false
        text.maxSize = NSSize(width: 100000, height: 100000)
        text.textContainer?.containerSize = NSSize(width: 100000, height: 100000)
        text.textContainer?.widthTracksTextView = false
        text.textContainer?.heightTracksTextView = false
        text.allowsUndo = true
        inputEditor = text
        addSubview(text)
        return text
    }

    func beginText(at point: NSPoint, item: InkItem? = nil, showCaret: Bool = true) {
        if eraserEnabled { setEraserEnabled(false) }
        dismissHint()
        draft.anchor = InkPoint(point)
        editingID = item?.id
        textCenterAnchor = item == nil ? point : nil
        editingColor = item?.color ?? ink
        editingFontSize = item?.fontSize ?? preferences.defaultFontSize
        let text = ensureInputEditor()
        editor = text
        text.allowsMouseSelection = false
        text.resetTextUndo()
        text.setFrameOrigin(screen(point))
        let pointSize = editingFontSize
        (text.layoutManager as? InkTextLayoutManager)?.pointSize = pointSize
        text.font = InkTypography.font(pointSize)
        let attributes = InkTypography.attributes(size: pointSize, color: editingColor!)
        text.defaultParagraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle
        text.typingAttributes = attributes
        text.markedTextAttributes = [.underlineStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: editingColor!.nsColor, .font: InkTypography.font(pointSize), .paragraphStyle: attributes[.paragraphStyle]!]
        text.textColor = editingColor!.nsColor; text.insertionPointColor = editingColor!.nsColor
        text.textStorage?.setAttributedString(NSAttributedString(string: item?.text ?? "", attributes: attributes))
        text.typingAttributes = attributes
        restoreFocus()
        if pointPlacement {
            initializePointerIfNeeded()
            typingPointerReference = pointerPreview ?? screen(point)
        }
        text.setSelectedRange(NSRange(location: text.string.utf16.count, length: 0))
        refreshTextLayout()
        text.inputContext?.invalidateCharacterCoordinates()
        if showCaret { showTypingCaret() }
        needsDisplay = true
    }

    func textDidChange(_ notification: Notification) {
        refreshTextLayout()
    }

    func refreshTextLayout() {
        guard let editor, let manager = editor.layoutManager, let container = editor.textContainer else { return }
        let tracking = displayTextTracking
        editor.typingAttributes[.kern] = tracking
        editor.markedTextAttributes?[.kern] = tracking
        if let storage = editor.textStorage, storage.length > 0 {
            var needsTracking = false
            storage.enumerateAttribute(.kern, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
                if (value as? NSNumber)?.doubleValue != tracking { needsTracking = true }
            }
            if needsTracking {
                let undo = editor.undoManager
                let enabled = undo?.isUndoRegistrationEnabled == true
                if enabled { undo?.disableUndoRegistration() }
                storage.addAttribute(.kern, value: tracking, range: NSRange(location: 0, length: storage.length))
                if enabled { undo?.enableUndoRegistration() }
            }
        }
        // Lay out in canvas units, then scale the view just like committed text.
        // Laying out a larger font instead changes rounded baselines and glyph metrics.
        let layoutSize = InkTypography.editorSize(manager, container, pointSize: editingFontSize)
        let size = NSSize(width: layoutSize.width * draft.zoom, height: layoutSize.height * draft.zoom)
        let origin: NSPoint
        if let textCenterAnchor {
            let center = screen(textCenterAnchor)
            origin = NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        } else {
            let raw = InkTypography.size(editor.string, fontSize: editingFontSize)
            let anchor = screen(draft.anchor.point)
            origin = NSPoint(x: anchor.x - (layoutSize.width - raw.width) * draft.zoom / 2, y: anchor.y)
        }
        editor.setFrameSize(size)
        editor.setBoundsSize(layoutSize)
        editor.setFrameOrigin(origin)
        editor.inputContext?.invalidateCharacterCoordinates()
        needsDisplay = true
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if textView.hasMarkedText() { return false }
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { textView.insertText("\n", replacementRange: textView.selectedRange()); return true }
            let anchor = draft.anchor.point
            let lines = max(1, textView.string.components(separatedBy: "\n").count)
            commitText()
            draft.anchor = InkPoint(NSPoint(x: anchor.x, y: anchor.y + Double(lines) * InkTypography.lineHeight(editingFontSize)))
            changed(); return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { commitText(); return true }
        return false
    }

    func commitText() {
        cancelTextHover(); isHoverEditing = false
        guard let text = editor else { return }
        window?.invalidateCursorRects(for: text)
        text.unmarkText()
        let id = editingID
        var items = draft.items
        let content = text.string
        if !content.isEmpty {
            if let id, let index = items.firstIndex(where: { $0.id == id }) {
                items[index].text = content; items[index].color = editingColor ?? ink; items[index].fontSize = editingFontSize
            } else {
                let size = InkTypography.size(content, fontSize: editingFontSize)
                let origin = textCenterAnchor.map { NSPoint(x: $0.x - size.width / 2, y: $0.y - size.height / 2) } ?? draft.anchor.point
                items.append(InkItem(kind: .text, points: [InkPoint(origin)], color: editingColor ?? ink, text: content, fontSize: editingFontSize))
            }
        } else if let id { items.removeAll { $0.id == id } }
        text.breakUndoCoalescing()
        text.string = ""
        text.allowsMouseSelection = false
        text.insertionPointColor = .clear
        text.resetTextUndo()
        editor = nil; editingID = nil; editingColor = nil; textCenterAnchor = nil
        typingPointerReference = nil
        typingCaretVisible = false
        restoreFocus()
        if items != draft.items { replaceItems(items, name: "Text") }
        needsDisplay = true
    }

    func escape() {
        if editor != nil { commitText() }
        else if selection != nil { selection = nil }
        else { onEscape?() }
    }

    override func scrollWheel(with event: NSEvent) {
        cancelTextHover()
        guard !isDrawing else { return }
        commitText()
        let multiplier = event.hasPreciseScrollingDeltas ? 1.0 : 15.0
        draft.offset.x += event.scrollingDeltaX * multiplier
        draft.offset.y += event.scrollingDeltaY * multiplier
        changed()
    }
    override func magnify(with event: NSEvent) {
        guard !isDrawing else { return }
        commitText()
        let p = convert(event.locationInWindow, from: nil), fixed = world(p)
        draft.zoom = min(4, max(0.2, draft.zoom * (1 + event.magnification)))
        draft.offset = InkPoint(NSPoint(x: p.x - fixed.x * draft.zoom, y: p.y - fixed.y * draft.zoom))
        changed()
    }

    func fit() {
        commitText()
        guard let first = draft.items.first else { draft.zoom = 1; draft.offset = InkPoint(.zero); changed(); return }
        let rect = draft.items.dropFirst().reduce(displayBounds(for: first)) { $0.union(displayBounds(for: $1)) }
        draft.zoom = min(2, max(0.2, min((bounds.width - 100) / max(1, rect.width), (bounds.height - 140) / max(1, rect.height))))
        draft.offset = InkPoint(NSPoint(x: (bounds.width - rect.width * draft.zoom) / 2 - rect.minX * draft.zoom, y: (bounds.height - rect.height * draft.zoom) / 2 - rect.minY * draft.zoom - 20))
        changed()
    }

    func dismissHint() {
        hintVisible = false; UserDefaults.standard.set(true, forKey: "didShowHint")
    }

    @objc func undo(_ sender: Any?) { commitText(); history.undo(); selection = nil }
    @objc func redo(_ sender: Any?) { commitText(); history.redo(); selection = nil }
    @objc override func selectAll(_ sender: Any?) { }

    func exportBounds() -> NSRect {
        guard let first = draft.items.first else { return NSRect(x: 0, y: 0, width: 820, height: 560) }
        return draft.items.dropFirst().reduce(displayBounds(for: first, scale: 1)) { $0.union(displayBounds(for: $1, scale: 1)) }.insetBy(dx: -40, dy: -40)
    }

    func exportData(pdf: Bool) -> Data? {
        commitText()
        let rect = exportBounds()
        guard rect.width < 20000, rect.height < 20000, rect.width * rect.height < 80_000_000 else { return nil }
        let export = CanvasView(frame: NSRect(origin: .zero, size: rect.size), preferences: preferences)
        export.setHighContrast(highContrastEnabled, animated: false)
        export.hintVisible = false; export.draft = draft; export.draft.zoom = 1
        export.draft.offset = InkPoint(NSPoint(x: -rect.minX, y: -rect.minY))
        export.draft.anchor = InkPoint(NSPoint(x: -1_000_000, y: -1_000_000))
        if pdf { return export.dataWithPDF(inside: export.bounds) }
        guard let bitmap = export.bitmapImageRepForCachingDisplay(in: export.bounds) else { return nil }
        export.cacheDisplay(in: export.bounds, to: bitmap)
        return bitmap.representation(using: .png, properties: [:])
    }
}
