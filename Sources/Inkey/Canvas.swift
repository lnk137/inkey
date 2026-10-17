import AppKit

final class InlineTextView: NSTextView {
    private let textHistory = UndoManager()
    weak var canvas: CanvasView?
    var allowsMouseSelection = false
    override var undoManager: UndoManager? { textHistory }

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
        guard allowsMouseSelection, canvas?.eraserEnabled != true,
              !NSEvent.modifierFlags.contains(.option), !NSEvent.modifierFlags.contains(.command) else { return nil }
        let windowPoint = superview?.convert(point, to: nil) ?? point
        return containsText(at: windowPoint) ? super.hitTest(point) : nil
    }

    override func resetCursorRects() {
        guard allowsMouseSelection, canvas?.eraserEnabled != true, !NSEvent.modifierFlags.contains(.option),
              let layoutManager, let textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)
        layoutManager.enumerateLineFragments(forGlyphRange: layoutManager.glyphRange(for: textContainer)) { _, used, _, _, _ in
            self.addCursorRect(used.offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y), cursor: .iBeam)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 && event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command {
            canvas?.promoteTextEditing(); return
        }
        if [UInt16(51), 117, 123, 124, 125, 126].contains(event.keyCode) {
            canvas?.keepCurrentTextForCorrection()
        } else if canvas?.retargetTypingIfNeeded(event, from: self) == true { return }
        super.keyDown(with: event)
    }
    func acceptRoutedKey(_ event: NSEvent) { super.keyDown(with: event) }
    override func flagsChanged(with event: NSEvent) { canvas?.flagsChanged(with: event); super.flagsChanged(with: event) }
}

final class CanvasView: NSView, NSTextViewDelegate {
    var draft = Draft() { didSet { needsDisplay = true } }
    var ink = InkColor.light[0]
    var selection: UUID? { didSet { needsDisplay = true } }
    var onChange: (() -> Void)?
    var onEscape: (() -> Void)?
    var onInteraction: (() -> Void)?
    var pointPlacement: Bool { UserDefaults.standard.bool(forKey: "pointerPlacement") }
    private var active: InkItem?
    private var editor: InlineTextView?
    private var editingID: UUID?
    private var editingColor: InkColor?
    private var previewItems: [InkItem]?
    private var previewTextColor: InkColor?
    private var moveStart: NSPoint?
    private var moveOriginal: [InkItem]?
    private struct PointerIntent {
        var start: NSPoint
        var viewStart: NSPoint
        var arrow: Bool
        var textClick: Bool
    }
    private var pendingPointer: PointerIntent?
    private var pointerPreview: NSPoint?
    private var typingPointerReference: NSPoint?
    private var caretVisible = true
    private var caretTimer: Timer?
    private struct CaretSample { var point: NSPoint; var time: TimeInterval }
    private var caretTrail: [CaretSample] = []
    private var trailTimer: Timer?
    var cursorTrailEnabled = true {
        didSet { if !cursorTrailEnabled { clearCaretTrail() } }
    }
    var isCanvasLocation: ((NSPoint) -> Bool)?
    private var eraseOriginal: [InkItem]?
    private var erasePrevious: InkPoint?
    private(set) var eraserEnabled = false
    var eraserDiameter: Double = 24 {
        didSet { window?.invalidateCursorRects(for: self) }
    }
    var onToolChange: ((Bool) -> Void)?
    private let history = UndoManager()
    private var imageCache: [UUID: NSImage] = [:]
    private var saveTimer: Timer?
    private var hintVisible = !UserDefaults.standard.bool(forKey: "didShowHint")
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var undoManager: UndoManager? { history }
    var isEditing: Bool { editor != nil }
    var isPrecisionEditing: Bool { editor?.allowsMouseSelection == true }
    var isDrawing: Bool { active != nil || moveStart != nil || pendingPointer != nil || eraseOriginal != nil }

    private var wantsNewTextAtPointer: Bool {
        guard pointPlacement, !isPrecisionEditing, let point = pointerPreview, let reference = typingPointerReference else { return false }
        return hypot(point.x - reference.x, point.y - reference.y) >= 12
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        caretTimer?.invalidate()
        if window != nil {
            caretTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.caretVisible.toggle()
                if self.window?.isKeyWindow == true { self.needsDisplay = true }
            }
        }
    }

    deinit { caretTimer?.invalidate(); trailTimer?.invalidate(); saveTimer?.invalidate() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited], owner: self))
    }

    override func mouseMoved(with event: NSEvent) { updatePointerLocation(event.locationInWindow) }
    override func mouseEntered(with event: NSEvent) { updatePointerLocation(event.locationInWindow) }
    override func mouseExited(with event: NSEvent) { pointerPreview = nil; clearCaretTrail(); updateInsertionPreview() }

    func updatePointerLocation(_ windowPoint: NSPoint) {
        let point = convert(windowPoint, from: nil)
        pointerPreview = containsCanvasPoint(point) && (isCanvasLocation?(windowPoint) ?? true) ? point : nil
        caretVisible = true
        if cursorTrailEnabled, pointerPreview != nil, pointPlacement, !isDrawing, !eraserEnabled, !isPrecisionEditing,
           editor == nil || wantsNewTextAtPointer {
            let now = ProcessInfo.processInfo.systemUptime
            caretTrail.removeAll { now - $0.time > 0.18 }
            if let last = caretTrail.last, hypot(point.x - last.point.x, point.y - last.point.y) > 160 { clearCaretTrail() }
            if caretTrail.last.map({ hypot(point.x - $0.point.x, point.y - $0.point.y) >= 2 }) ?? true {
                caretTrail.append(CaretSample(point: point, time: now))
                if caretTrail.count > 24 { caretTrail.removeFirst() }
            }
            if trailTimer == nil {
                trailTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                    guard let self else { return }
                    let now = ProcessInfo.processInfo.systemUptime
                    self.caretTrail.removeAll { now - $0.time > 0.18 }
                    self.needsDisplay = true
                    if self.caretTrail.isEmpty { self.clearCaretTrail() }
                }
            }
        } else { clearCaretTrail() }
        updateInsertionPreview()
    }

    private func clearCaretTrail() {
        caretTrail.removeAll(); trailTimer?.invalidate(); trailTimer = nil; needsDisplay = true
    }

    private func updateInsertionPreview() {
        if let editor {
            editor.insertionPointColor = wantsNewTextAtPointer ? .clear : (editingColor ?? ink).nsColor
            editor.needsDisplay = true
        }
        needsDisplay = true
    }

    func keepCurrentTextForCorrection(at windowPoint: NSPoint? = nil) {
        if let location = windowPoint ?? window?.mouseLocationOutsideOfEventStream { updatePointerLocation(location) }
        typingPointerReference = pointerPreview
        updateInsertionPreview()
    }

    @discardableResult
    func retargetTypingIfNeeded(_ event: NSEvent, from text: InlineTextView, at windowPoint: NSPoint? = nil) -> Bool {
        guard editor === text, pointPlacement, !text.allowsMouseSelection, !text.hasMarkedText(),
              !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.control),
              ![UInt16(36), 48, 51, 53, 76, 117, 123, 124, 125, 126].contains(event.keyCode),
              let characters = event.characters, !characters.isEmpty,
              !characters.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || (0xF700...0xF8FF).contains($0.value) }) else { return false }
        if let location = windowPoint ?? window?.mouseLocationOutsideOfEventStream { updatePointerLocation(location) }
        guard wantsNewTextAtPointer, let point = pointerPreview else { return false }
        commitText()
        selection = nil
        beginText(at: world(NSPoint(x: point.x + 3, y: point.y + 4)))
        editor?.acceptRoutedKey(event)
        return true
    }

    func setEraserEnabled(_ enabled: Bool) {
        clearCaretTrail()
        finishPointerGesture()
        if enabled { commitText(); selection = nil }
        eraserEnabled = enabled
        onToolChange?(enabled)
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    func promoteTextEditing() {
        guard let editor else { return }
        editor.allowsMouseSelection = true
        clearCaretTrail()
        updateInsertionPreview()
        needsDisplay = true
        window?.invalidateCursorRects(for: editor)
    }

    override func flagsChanged(with event: NSEvent) {
        window?.invalidateCursorRects(for: self)
        if let editor { window?.invalidateCursorRects(for: editor) }
    }

    override func resetCursorRects() {
        if eraserEnabled || NSEvent.modifierFlags.contains(.option) {
            let diameter = min(120, max(4, eraserDiameter))
            let size = NSSize(width: diameter + 6, height: diameter + 6)
            let image = NSImage(size: size)
            image.lockFocus()
            let circle = NSBezierPath(ovalIn: NSRect(x: 3, y: 3, width: diameter, height: diameter))
            NSColor.white.setStroke(); circle.lineWidth = 3; circle.stroke()
            NSColor.black.withAlphaComponent(0.75).setStroke(); circle.lineWidth = 1; circle.stroke()
            image.unlockFocus()
            addCursorRect(bounds, cursor: NSCursor(image: image, hotSpot: NSPoint(x: size.width / 2, y: size.height / 2)))
        } else { addCursorRect(bounds, cursor: .crosshair) }
    }

    func restoreFocus() { window?.makeFirstResponder(editor ?? self) }

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

    override init(frame: NSRect) {
        super.init(frame: frame)
        history.groupsByEvent = false
        wantsLayer = true
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
        draft.items.reversed().first { $0.hit(point, tolerance: 7 / draft.zoom) }
    }

    override func draw(_ dirtyRect: NSRect) {
        draft.background.nsColor.setFill(); bounds.fill()
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: draft.offset.x, y: draft.offset.y)
        context.scaleBy(x: draft.zoom, y: draft.zoom)
        for item in draft.items where item.id != editingID { render(item) }
        if let active { render(active) }
        if let selection, let item = draft.items.first(where: { $0.id == selection }) {
            let rect = item.bounds.insetBy(dx: -6 / draft.zoom, dy: -6 / draft.zoom)
            NSColor.controlAccentColor.withAlphaComponent(0.65).setStroke()
            let border = NSBezierPath(roundedRect: rect, xRadius: 4 / draft.zoom, yRadius: 4 / draft.zoom)
            border.lineWidth = 1 / draft.zoom; border.setLineDash([4 / draft.zoom, 3 / draft.zoom], count: 2, phase: 0); border.stroke()
        }
        if editor == nil && active == nil && selection == nil && !eraserEnabled && eraseOriginal == nil && (!pointPlacement || pointerPreview == nil) && caretVisible {
            let p = draft.anchor.point
            ink.nsColor.withAlphaComponent(0.35).setStroke()
            let mark = NSBezierPath(); mark.move(to: p); mark.line(to: NSPoint(x: p.x, y: p.y + 22)); mark.lineWidth = 1 / draft.zoom; mark.stroke()
        }
        context.restoreGState()
        if cursorTrailEnabled, pointPlacement, !isDrawing, !eraserEnabled, !isPrecisionEditing, selection == nil,
           pointerPreview != nil, editor == nil || wantsNewTextAtPointer {
            let now = ProcessInfo.processInfo.systemUptime
            for (a, b) in zip(caretTrail, caretTrail.dropFirst()) {
                let remaining = max(0, 1 - (now - a.time) / 0.18)
                ink.nsColor.withAlphaComponent(0.16 * remaining * remaining).setStroke()
                let trail = NSBezierPath(); trail.lineWidth = 1.5; trail.lineCapStyle = .round
                let dy = 4 + 12 * draft.zoom
                trail.move(to: NSPoint(x: a.point.x + 3, y: a.point.y + dy))
                trail.line(to: NSPoint(x: b.point.x + 3, y: b.point.y + dy)); trail.stroke()
            }
        }
        if pointPlacement, !isDrawing, !eraserEnabled, selection == nil, caretVisible,
           let point = pointerPreview, editor == nil || wantsNewTextAtPointer {
            ink.nsColor.withAlphaComponent(0.75).setStroke()
            let marker = NSBezierPath()
            marker.move(to: NSPoint(x: point.x + 3, y: point.y + 4))
            marker.line(to: NSPoint(x: point.x + 3, y: point.y + 4 + 24 * draft.zoom))
            marker.lineWidth = 1; marker.stroke()
        }
        if let editor, editor.allowsMouseSelection {
            NSColor.controlAccentColor.withAlphaComponent(0.25).setStroke()
            let border = NSBezierPath(roundedRect: editor.frame.insetBy(dx: -5, dy: -4), xRadius: 4, yRadius: 4)
            border.lineWidth = 1; border.stroke()
        }
        if hintVisible && draft.items.isEmpty && editor == nil {
            let text = "直接打字，拖动绘画。" as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor]
            let size = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: bounds.height / 2), withAttributes: attributes)
        }
    }

    func render(_ item: InkItem) {
        guard let first = item.points.first?.point else { return }
        if item.kind == .text {
            (item.text as NSString).draw(at: first, withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: item.fontSize, weight: .regular), .foregroundColor: item.color.nsColor])
            return
        }
        if item.kind == .image {
            let image = imageCache[item.id] ?? item.imageData.flatMap(NSImage.init(data:))
            if let image { imageCache[item.id] = image; image.draw(in: item.bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil) }
            return
        }
        item.color.nsColor.setStroke(); item.color.nsColor.setFill()
        let path = NSBezierPath(); path.lineWidth = item.lineWidth; path.lineCapStyle = .round; path.lineJoinStyle = .round
        path.move(to: first)
        let points = item.points.map(\.point)
        if item.kind == .arrow, let end = points.last {
            path.line(to: end); path.stroke()
            let angle = atan2(end.y - first.y, end.x - first.x)
            let length = min(13.0, max(6.0, hypot(end.x - first.x, end.y - first.y) * 0.25))
            let head = NSBezierPath()
            head.move(to: NSPoint(x: end.x - length * cos(angle - 0.48), y: end.y - length * sin(angle - 0.48)))
            head.line(to: end); head.line(to: NSPoint(x: end.x - length * cos(angle + 0.48), y: end.y - length * sin(angle + 0.48)))
            head.lineWidth = item.lineWidth; head.lineCapStyle = .round; head.lineJoinStyle = .round; head.stroke()
        } else if points.count < 3 {
            if let end = points.last { path.line(to: end) }; path.stroke()
        } else {
            for index in 1..<points.count - 1 {
                let midpoint = NSPoint(x: (points[index].x + points[index + 1].x) / 2, y: (points[index].y + points[index + 1].y) / 2)
                let previous = index == 1 ? points[0] : NSPoint(x: (points[index - 1].x + points[index].x) / 2, y: (points[index - 1].y + points[index].y) / 2)
                let control1 = NSPoint(x: previous.x + (points[index].x - previous.x) * 2 / 3, y: previous.y + (points[index].y - previous.y) * 2 / 3)
                let control2 = NSPoint(x: midpoint.x + (points[index].x - midpoint.x) * 2 / 3, y: midpoint.y + (points[index].y - midpoint.y) * 2 / 3)
                path.curve(to: midpoint, controlPoint1: control1, controlPoint2: control2)
            }
            path.line(to: points.last!); path.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        clearCaretTrail()
        onInteraction?()
        let viewPoint = convert(event.locationInWindow, from: nil)
        let p = world(viewPoint)
        dismissHint()
        if eraserEnabled || event.modifierFlags.contains(.option) {
            commitText(); window?.makeFirstResponder(self); selection = nil
            eraseOriginal = draft.items
            let point = InkPoint(p); erasePrevious = point
            draft.items = InkEraser.erase(draft.items, from: point, to: point, radius: eraserDiameter / (2 * draft.zoom))
            needsDisplay = true; return
        }
        if event.modifierFlags.contains(.command) {
            commitText(); window?.makeFirstResponder(self)
            selection = item(at: p)?.id
            if selection != nil { moveStart = p; moveOriginal = draft.items }
            return
        }
        if let editor, editor.containsText(at: event.locationInWindow), !event.modifierFlags.contains(.shift) {
            if event.clickCount >= 2 {
                promoteTextEditing(); positionTextCaret(at: event.locationInWindow)
                editor.selectWord(nil)
            } else {
                pendingPointer = PointerIntent(start: p, viewStart: viewPoint, arrow: false, textClick: true)
            }
            return
        }
        commitText()
        window?.makeFirstResponder(self)
        if event.clickCount == 2, let hit = item(at: p), hit.kind == .text {
            selection = nil; beginText(at: hit.points[0].point, item: hit)
            promoteTextEditing(); positionTextCaret(at: event.locationInWindow); editor?.selectWord(nil)
            return
        }
        selection = nil
        pendingPointer = PointerIntent(start: p, viewStart: viewPoint, arrow: event.modifierFlags.contains(.shift), textClick: false)
        needsDisplay = true
    }

    private func positionTextCaret(at windowPoint: NSPoint) {
        guard let editor else { return }
        let point = editor.convert(windowPoint, from: nil)
        editor.setSelectedRange(NSRange(location: editor.characterIndexForInsertion(at: point), length: 0))
        window?.makeFirstResponder(editor)
    }

    override func mouseDragged(with event: NSEvent) {
        let p = world(convert(event.locationInWindow, from: nil))
        if let previous = erasePrevious {
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
                commitText(); window?.makeFirstResponder(self)
                draft.anchor = InkPoint(pending.start)
                active = InkItem(kind: pending.arrow ? .arrow : .stroke, points: [InkPoint(pending.start)], color: ink)
                pendingPointer = nil
            }
            guard var drawing = active else { return }
            if drawing.kind == .arrow { drawing.points = [drawing.points[0], InkPoint(p)] }
            else if let last = drawing.points.last, hypot(p.x - last.x, p.y - last.y) * draft.zoom > 0.7 { drawing.points.append(InkPoint(p)) }
            active = drawing
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let pending = pendingPointer {
            if pending.textClick { positionTextCaret(at: event.locationInWindow) }
            else { draft.anchor = InkPoint(pending.start); changed() }
        }
        finishPointerGesture()
    }

    private func finishPointerGesture() {
        if let original = eraseOriginal {
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
        selection = nil
        var anchor = draft.anchor.point
        if pointPlacement, let window {
            let p = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            if containsCanvasPoint(p), isCanvasLocation?(window.mouseLocationOutsideOfEventStream) ?? true {
                updatePointerLocation(window.mouseLocationOutsideOfEventStream)
                anchor = world(NSPoint(x: p.x + 3, y: p.y + 4))
            }
        }
        beginText(at: anchor)
        editor?.keyDown(with: event)
    }

    func beginText(at point: NSPoint, item: InkItem? = nil) {
        if eraserEnabled { setEraserEnabled(false) }
        dismissHint()
        draft.anchor = InkPoint(point)
        editingID = item?.id
        editingColor = item?.color ?? ink
        let origin = screen(point)
        let text = InlineTextView(frame: NSRect(x: origin.x, y: origin.y, width: max(200, bounds.width - origin.x - 16), height: 40 * draft.zoom))
        text.canvas = self
        text.delegate = self; text.isRichText = false; text.drawsBackground = false
        text.font = NSFont.monospacedSystemFont(ofSize: (item?.fontSize ?? 20) * draft.zoom, weight: .regular)
        text.textColor = editingColor!.nsColor; text.insertionPointColor = editingColor!.nsColor
        text.textContainerInset = .zero; text.textContainer?.lineFragmentPadding = 0
        text.isAutomaticQuoteSubstitutionEnabled = false; text.isAutomaticDashSubstitutionEnabled = false
        text.isAutomaticSpellingCorrectionEnabled = false; text.isContinuousSpellCheckingEnabled = false
        text.isAutomaticTextReplacementEnabled = false
        text.isHorizontallyResizable = true; text.isVerticallyResizable = true
        text.maxSize = NSSize(width: 100000, height: 100000)
        text.textContainer?.containerSize = NSSize(width: 100000, height: 100000)
        text.textContainer?.widthTracksTextView = false
        text.allowsUndo = true; text.string = item?.text ?? ""
        editor = text; addSubview(text); window?.makeFirstResponder(text)
        if pointPlacement {
            if pointerPreview == nil, let window { updatePointerLocation(window.mouseLocationOutsideOfEventStream) }
            typingPointerReference = pointerPreview ?? screen(point)
        }
        text.setSelectedRange(NSRange(location: text.string.utf16.count, length: 0))
        resizeEditor()
        needsDisplay = true
    }

    func textDidChange(_ notification: Notification) {
        resizeEditor()
    }

    private func resizeEditor() {
        guard let editor, let manager = editor.layoutManager, let container = editor.textContainer else { return }
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container)
        editor.setFrameSize(NSSize(width: max(16, used.maxX + 4), height: max((editor.font?.pointSize ?? 20) * 1.3, used.maxY + 3)))
        needsDisplay = true
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if textView.hasMarkedText() { return false }
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { textView.insertText("\n", replacementRange: textView.selectedRange()); return true }
            let anchor = draft.anchor.point
            let lines = max(1, textView.string.components(separatedBy: "\n").count)
            commitText()
            draft.anchor = InkPoint(NSPoint(x: anchor.x, y: anchor.y + Double(lines) * 26))
            changed(); return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { commitText(); return true }
        return false
    }

    func commitText() {
        guard let text = editor else { return }
        text.unmarkText()
        let id = editingID
        var items = draft.items
        let content = text.string
        if !content.isEmpty {
            if let id, let index = items.firstIndex(where: { $0.id == id }) {
                items[index].text = content; items[index].color = editingColor ?? ink
            } else {
                items.append(InkItem(kind: .text, points: [draft.anchor], color: editingColor ?? ink, text: content))
            }
        } else if let id { items.removeAll { $0.id == id } }
        editor = nil; editingID = nil; editingColor = nil
        typingPointerReference = nil
        text.removeFromSuperview()
        window?.makeFirstResponder(self)
        if items != draft.items { replaceItems(items, name: "Text") }
        needsDisplay = true
    }

    func escape() {
        if editor != nil { commitText() }
        else if selection != nil { selection = nil }
        else { onEscape?() }
    }

    override func scrollWheel(with event: NSEvent) {
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
        let rect = draft.items.dropFirst().reduce(first.bounds) { $0.union($1.bounds) }
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
        return draft.items.dropFirst().reduce(first.bounds) { $0.union($1.bounds) }.insetBy(dx: -40, dy: -40)
    }

    func exportData(pdf: Bool) -> Data? {
        commitText()
        let rect = exportBounds()
        guard rect.width < 20000, rect.height < 20000, rect.width * rect.height < 80_000_000 else { return nil }
        let export = CanvasView(frame: NSRect(origin: .zero, size: rect.size))
        export.hintVisible = false; export.draft = draft; export.draft.zoom = 1
        export.draft.offset = InkPoint(NSPoint(x: -rect.minX, y: -rect.minY))
        export.draft.anchor = InkPoint(NSPoint(x: -1_000_000, y: -1_000_000))
        if pdf { return export.dataWithPDF(inside: export.bounds) }
        guard let bitmap = export.bitmapImageRepForCachingDisplay(in: export.bounds) else { return nil }
        export.cacheDisplay(in: export.bounds, to: bitmap)
        return bitmap.representation(using: .png, properties: [:])
    }
}
