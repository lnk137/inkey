import AppKit

final class HueSliderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let track = NSRect(x: rect.minX, y: rect.midY - 3, width: rect.width, height: 6)
        let colors = (0...12).map { NSColor(hue: Double($0) / 12, saturation: 0.85, brightness: 0.95, alpha: 1) }
        NSGradient(colors: colors)?.draw(in: NSBezierPath(roundedRect: track, xRadius: 3, yRadius: 3), angle: 0)
    }
    override func drawKnob(_ knobRect: NSRect) {
        let rect = NSRect(x: knobRect.midX - 7, y: knobRect.midY - 7, width: 14, height: 14)
        NSColor.white.setFill(); NSBezierPath(ovalIn: rect).fill()
        NSColor.black.withAlphaComponent(0.2).setStroke()
        let border = NSBezierPath(ovalIn: rect); border.lineWidth = 1; border.stroke()
        NSColor(hue: doubleValue, saturation: 0.85, brightness: 0.95, alpha: 1).setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3)).fill()
    }
}

final class SwatchButton: ReorderButton {
    var inkColor = InkColor("303735") { didSet { needsDisplay = true } }
    var selected = false { didSet { needsDisplay = true } }
    var isCustom = false
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?
    var hovering = false
    private var hoverArea: NSTrackingArea?
    override var acceptsFirstResponder: Bool { false }
    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false; title = ""
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverArea = area
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard onEdit != nil else { return nil }
        let menu = NSMenu()
        if isCustom {
            let item = NSMenuItem(title: "自定义颜色…", action: #selector(editColor), keyEquivalent: "")
            item.target = self; menu.addItem(item); return menu
        }
        for (title, action) in [("编辑颜色…", #selector(editColor)), ("删除颜色", #selector(deleteColor))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        return menu
    }
    @objc private func editColor() { onEdit?() }
    @objc private func deleteColor() { onDelete?() }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        if isCustom {
            NSColor.secondaryLabelColor.setStroke()
            let circle = NSBezierPath(ovalIn: NSRect(x: bounds.midX - 10, y: bounds.midY - 10, width: 20, height: 20))
            circle.lineWidth = 1
            if hovering { NSColor.labelColor.withAlphaComponent(0.06).setFill(); circle.fill() }
            circle.stroke()
            let plus = NSBezierPath(); plus.lineWidth = 1.3; plus.lineCapStyle = .round
            plus.move(to: NSPoint(x: bounds.midX - 4, y: bounds.midY)); plus.line(to: NSPoint(x: bounds.midX + 4, y: bounds.midY))
            plus.move(to: NSPoint(x: bounds.midX, y: bounds.midY - 4)); plus.line(to: NSPoint(x: bounds.midX, y: bounds.midY + 4)); plus.stroke()
            return
        }
        let diameter: CGFloat = hovering ? 19 : 17
        let circle = NSRect(x: (bounds.width - diameter) / 2, y: (bounds.height - diameter) / 2, width: diameter, height: diameter)
        inkColor.nsColor.setFill(); NSBezierPath(ovalIn: circle).fill()
        if selected {
            inkColor.nsColor.withAlphaComponent(0.65).setStroke()
            let outline = NSBezierPath(ovalIn: circle.insetBy(dx: -4, dy: -4)); outline.lineWidth = 1.3; outline.stroke()
        }
    }
}

final class ColorSquare: NSView {
    var hue: CGFloat = 0 { didSet { needsDisplay = true } }
    var saturation: CGFloat = 0.5
    var brightness: CGFloat = 0.7
    var onChange: ((NSColor) -> Void)?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).addClip()
        NSGradient(starting: .white, ending: NSColor(hue: hue, saturation: 1, brightness: 1, alpha: 1))?.draw(in: bounds, angle: 0)
        NSGradient(starting: NSColor.black.withAlphaComponent(0), ending: .black)?.draw(in: bounds, angle: 90)
        let p = NSPoint(x: saturation * bounds.width, y: (1 - brightness) * bounds.height)
        NSColor.black.withAlphaComponent(0.4).setStroke()
        let outer = NSBezierPath(ovalIn: NSRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)); outer.lineWidth = 3; outer.stroke()
        NSColor.white.setStroke(); outer.lineWidth = 1.8; outer.stroke()
    }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); update(event) }
    override func mouseDragged(with event: NSEvent) { update(event) }
    private func update(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        saturation = min(1, max(0, p.x / bounds.width)); brightness = min(1, max(0, 1 - p.y / bounds.height))
        needsDisplay = true
        onChange?(NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1))
    }
    override func keyDown(with event: NSEvent) {
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 0.1 : 0.01
        switch event.keyCode {
        case 123: saturation = max(0, saturation - step)
        case 124: saturation = min(1, saturation + step)
        case 125: brightness = max(0, brightness - step)
        case 126: brightness = min(1, brightness + step)
        default: super.keyDown(with: event); return
        }
        needsDisplay = true
        onChange?(NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1))
    }
}

final class ColorPanelController: NSViewController, NSTextFieldDelegate {
    enum Purpose { case custom, add, edit }
    var purpose: Purpose = .custom
    let square = ColorSquare(frame: .zero)
    let hueSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    let hexField = NSTextField()
    let preview = SwatchButton(frame: .zero)
    var color: InkColor
    var onPreview: ((InkColor) -> Void)?
    var onReplace: ((InkColor) -> Void)?
    var onAdd: ((InkColor) -> Void)?
    var canReplace = true
    var onClose: ((Bool) -> Void)?
    var recent: [InkColor]
    var recentButtons: [SwatchButton] = []
    init(color: InkColor, recent: [InkColor]) {
        self.color = color; self.recent = recent
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 264, height: 304))
        square.frame = NSRect(x: 16, y: 140, width: 232, height: 148)
        square.setAccessibilityElement(true)
        square.setAccessibilityRole(.slider)
        square.setAccessibilityLabel("Color surface: left and right adjust saturation; up and down adjust brightness")
        view.addSubview(square)
        square.onChange = { [weak self] color in self?.update(InkColor(color), syncSquare: false) }
        hueSlider.frame = NSRect(x: 14, y: 108, width: 236, height: 20)
        hueSlider.cell = HueSliderCell()
        hueSlider.minValue = 0; hueSlider.maxValue = 1
        hueSlider.target = self; hueSlider.action = #selector(hueChanged)
        hueSlider.isContinuous = true; hueSlider.toolTip = "Hue"; hueSlider.setAccessibilityLabel("Hue")
        view.addSubview(hueSlider)
        preview.frame = NSRect(x: 12, y: 68, width: 36, height: 32); view.addSubview(preview)
        hexField.frame = NSRect(x: 52, y: 72, width: 134, height: 25)
        hexField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        hexField.delegate = self; hexField.target = self
        hexField.action = purpose == .add ? #selector(addPreset) : purpose == .edit ? #selector(done) : #selector(hexChanged)
        hexField.setAccessibilityLabel("Hex color"); view.addSubview(hexField)
        let dropper = NSButton(image: NSImage(systemSymbolName: "eyedropper", accessibilityDescription: "Pick screen color")!, target: self, action: #selector(sample))
        dropper.frame = NSRect(x: 202, y: 70, width: 40, height: 28); dropper.bezelStyle = .texturedRounded
        view.addSubview(dropper)
        for (index, item) in recent.prefix(6).enumerated() {
            let button = SwatchButton(frame: NSRect(x: 16 + index * 38, y: 32, width: 32, height: 32))
            button.inkColor = item; button.tag = index; button.target = self; button.action = #selector(recentClicked(_:))
            button.toolTip = item.hex; button.setAccessibilityLabel("Recent color \(item.hex)")
            recentButtons.append(button); view.addSubview(button)
        }
        if purpose == .custom {
            let replace = NSButton(title: "替换当前预设", target: self, action: #selector(replacePreset))
            replace.isBordered = false; replace.font = .systemFont(ofSize: 11)
            replace.frame = NSRect(x: 14, y: 5, width: 108, height: 23); replace.isEnabled = canReplace; view.addSubview(replace)
            let add = NSButton(title: "添加", target: self, action: #selector(addPreset))
            add.isBordered = false; add.font = .systemFont(ofSize: 11)
            add.frame = NSRect(x: 126, y: 5, width: 48, height: 23); view.addSubview(add)
        } else {
            let cancel = NSButton(title: "取消", target: self, action: #selector(cancel))
            cancel.isBordered = false; cancel.frame = NSRect(x: 14, y: 5, width: 56, height: 23); view.addSubview(cancel)
        }
        let done = NSButton(title: purpose == .add ? "添加" : "完成", target: self, action: purpose == .add ? #selector(addPreset) : #selector(done))
        done.keyEquivalent = "\r"
        done.bezelStyle = .rounded; done.frame = NSRect(x: 183, y: 4, width: 66, height: 25)
        view.addSubview(done)
        update(color, syncSquare: true, emit: false)
    }
    func update(_ value: InkColor, syncSquare: Bool, emit: Bool = true) {
        color = value; preview.inkColor = value; hexField.stringValue = value.hex
        if syncSquare, let rgb = value.nsColor.usingColorSpace(.deviceRGB) {
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            square.hue = h; square.saturation = s; square.brightness = b; square.needsDisplay = true; hueSlider.doubleValue = Double(h)
        }
        if emit { onPreview?(value) }
    }
    @objc func hueChanged() {
        square.hue = hueSlider.doubleValue
        update(InkColor(NSColor(hue: square.hue, saturation: square.saturation, brightness: square.brightness, alpha: 1)), syncSquare: false)
    }
    @objc func hexChanged() {
        _ = acceptHex()
    }
    @discardableResult func acceptHex() -> Bool {
        guard let value = InkColor.parse(hexField.stringValue) else { NSSound.beep(); hexField.stringValue = color.hex; return false }
        update(value, syncSquare: true)
        return true
    }
    func controlTextDidChange(_ obj: Notification) {
        if let value = InkColor.parse(hexField.stringValue) { update(value, syncSquare: true) }
    }
    @objc func sample() {
        NSColorSampler().show { [weak self] value in
            guard let value else { return }
            self?.update(InkColor(value), syncSquare: true)
        }
    }
    @objc func recentClicked(_ sender: NSButton) { update(recent[sender.tag], syncSquare: true) }
    @objc func replacePreset() { if acceptHex() { onReplace?(color); onClose?(true) } }
    @objc func addPreset() { if acceptHex() { onAdd?(color); onClose?(true) } }
    @objc func done() { if acceptHex() { onClose?(true) } }
    @objc func cancel() { onClose?(false) }
    override func cancelOperation(_ sender: Any?) { onClose?(false) }
}

final class PaletteView: NSView, NSPopoverDelegate {
    static let preferredWidth: CGFloat = 320
    let preferences: UserPreferences
    var colors: [InkColor] = InkColor.light
    var current = InkColor.light[0]
    var slot = 0
    var onShape: ((ShiftShape) -> Void)?
    var onLayoutChange: (() -> Void)?
    private(set) var isCollapsed = false
    private var collapseButton: CollapseButton!
    private let collapseAnimation = ToolbarCollapseAnimation()
    private let layoutAnimation = ToolbarLayoutAnimation()
    private let resizeHandle = ToolbarResizeHandle(frame: NSRect(x: 294, y: 57, width: 22, height: 20))
    private(set) var toolbarScale: CGFloat = 1
    private(set) var effectiveScale: CGFloat = 1
    private var resizeStart: (point: NSPoint, scale: CGFloat, width: CGFloat)?
    private var resizedToolbar = false
    private var shapeButtons: [ToolButton] = []
    var onColor: ((InkColor) -> Void)?
    var onRestoredColor: ((InkColor) -> Void)?
    var onBeginPreview: (() -> Void)?
    var onEndPreview: ((Bool, InkColor) -> Void)?
    var onRestoreFocus: (() -> Void)?
    var onEraser: ((Bool) -> Void)?
    var onEraserSize: ((Double) -> Void)?
    var eraserEnabled = false { didSet { updateToolButton() } }
    var eraserDiameter: Double = 24 {
        didSet { eraserController?.update(eraserDiameter) }
    }
    var paperIsDark: Bool?
    var popover: NSPopover?
    var eraserPopover: NSPopover?
    var hasPopover: Bool { popover != nil || eraserPopover != nil }
    private var eraserController: EraserPanelController?
    private var eraserButton: ToolButton!
    private var buttons: [SwatchButton] = []
    private var custom: SwatchButton!
    private var contrastButton: ToolButton!
    var onHighContrast: (() -> Void)?
    var highContrastEnabled = false {
        didSet {
            contrastButton?.state = highContrastEnabled ? .on : .off
            contrastButton?.setAccessibilityValue(highContrastEnabled ? "开启" : "关闭")
        }
    }
    private var dragOrigin: NSPoint?
    private var originalFrame: NSPoint?
    private var movedToolbar = false
    private var desiredOrigin: NSPoint?
    private var windowObservers: [NSObjectProtocol] = []
    private var editingPreset: Int?
    private var initialColor: InkColor?
    private var acceptPreview = true
    private var previewController: ColorPanelController?
    private var pickerPurpose: ColorPanelController.Purpose = .custom
    private var pendingPresetAddition: InkColor?
    private var dark = false
    private var previousPaper: Bool?
    private struct ReorderGesture {
        let source: ReorderButton
        let originalButtons: [ReorderButton]
        let originalIndex: Int
        let frames: [NSRect]
        let offset: NSPoint
        let row: NSRect
        var ordered: [ReorderButton]
    }
    private var reorderGesture: ReorderGesture?
    private var recentColors: [InkColor] {
        get { (preferences.defaults.stringArray(forKey: "recentColors") ?? []).map(InkColor.init) }
        set { preferences.defaults.set(newValue.map(\.hex), forKey: "recentColors") }
    }
    override var acceptsFirstResponder: Bool { false }
    init(frame: NSRect, preferences: UserPreferences = UserPreferences()) {
        self.preferences = preferences
        super.init(frame: frame)
        toolbarScale = preferences.toolbarScale
        wantsLayer = true
        setAccessibilityRole(.toolbar); setAccessibilityLabel("工具栏，拖动箭头或空白处移动")
        for index in 0..<6 {
            appendColorButton(at: index)
        }
        custom = SwatchButton(frame: NSRect(x: 233, y: 4, width: 34, height: 36))
        custom.isCustom = true; custom.target = self; custom.action = #selector(addColor)
        custom.onEdit = { [weak self] in self?.togglePicker() }
        custom.toolTip = "添加预设颜色 · 右键自定义颜色\(shortcutHint(.colorPicker))"; custom.setAccessibilityLabel("添加预设颜色")
        addSubview(custom)
        eraserButton = ToolButton(image: NSImage(systemSymbolName: "eraser", accessibilityDescription: "Eraser")!, target: self, action: #selector(toggleEraser))
        eraserButton.onRightClick = { [weak self] in self?.openEraserSizing() }
        eraserButton.frame = NSRect(x: 275, y: 4, width: 34, height: 36)
        eraserButton.isBordered = false
        eraserButton.toolTip = "单击切换橡皮，右键调节尺寸\(shortcutHint(.eraser))"
        addSubview(eraserButton)
        for (index, shape) in preferences.shapeOrder.enumerated() {
            let button = ToolButton(image: NSImage(systemSymbolName: shape.symbol, accessibilityDescription: shape.label)!, target: self, action: #selector(shapeClicked(_:)))
            button.tag = index; button.isBordered = false
            button.reorderGroup = "shapes"
            configureReordering(button)
            button.frame = NSRect(x: 54 + index * 36, y: 43, width: 34, height: 32)
            button.toolTip = "\(shape.label)\(shortcutHint(ShortcutAction.shapes[index])) · Shift 拖动"
            button.setAccessibilityLabel(button.toolTip)
            shapeButtons.append(button); addSubview(button)
        }
        collapseButton = CollapseButton(frame: .zero)
        contrastButton = ToolButton(image: NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: "高对比")!, target: self, action: #selector(toggleHighContrast))
        contrastButton.isBordered = false
        contrastButton.frame = NSRect(x: 208, y: 43, width: 30, height: 32)
        contrastButton.toolTip = "高对比\(shortcutHint(.highContrast))"
        contrastButton.setAccessibilityLabel("高对比")
        addSubview(contrastButton)
        collapseButton.title = ""
        collapseButton.wantsLayer = true
        collapseButton.target = self; collapseButton.action = #selector(toggleCollapsed)
        collapseButton.isBordered = false; collapseButton.contentTintColor = .secondaryLabelColor; addSubview(collapseButton)
        collapseButton.onToolbarMouseEvent = { [weak self] event in
            switch event.type {
            case .leftMouseDown: self?.mouseDown(with: event)
            case .leftMouseDragged: self?.mouseDragged(with: event)
            case .leftMouseUp: self?.mouseUp(with: event)
            default: break
            }
        }
        addSubview(resizeHandle)
        resizeHandle.onBegin = { [weak self] in self?.beginResizing(at: $0) }
        resizeHandle.onDrag = { [weak self] in self?.updateResizing(at: $0) }
        resizeHandle.onEnd = { [weak self] in self?.endResizing() }
        resizeHandle.onReset = { [weak self] in self?.setToolbarScale(1) }
        isCollapsed = preferences.toolbarCollapsed
        isHidden = preferences.toolbarHidden
        updateToolbarLayout()
        updateShapeButtons()
        refreshAppearance()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func appendColorButton(at index: Int) {
        let button = SwatchButton(frame: .zero)
        button.tag = index; button.target = self; button.action = #selector(chosen(_:))
        button.reorderGroup = "colors"; configureReordering(button)
        button.onEdit = { [weak self, weak button] in if let button { self?.editPreset(button.tag) } }
        button.onDelete = { [weak self, weak button] in if let button { self?.deletePreset(button.tag) } }
        buttons.append(button); addSubview(button)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers = []
        guard let window else { cancelInteractions(); return }
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.cancelInteractions()
            })
        }
    }
    deinit { windowObservers.forEach(NotificationCenter.default.removeObserver) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refreshAppearance() }
    private func shortcutHint(_ action: ShortcutAction) -> String {
        preferences.shortcuts.binding(for: action).map { " · " + $0.label } ?? ""
    }
    func refreshShortcutHints() {
        updateButtons(); updateShapeButtons()
        custom.toolTip = "添加预设颜色 · 右键自定义颜色\(shortcutHint(.colorPicker))"
        contrastButton.toolTip = "高对比\(shortcutHint(.highContrast))"
        eraserButton.toolTip = "单击切换橡皮，右键调节尺寸\(shortcutHint(.eraser))"
        collapseButton.toolTip = (isCollapsed ? "展开工具栏" : "折叠工具栏") + shortcutHint(.collapseToolbar) + " · 拖动移动"
        collapseButton.setAccessibilityLabel(collapseButton.toolTip)
    }
    func refreshAppearance() {
        cancelInteractions()
        let newDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let previous = colors
        dark = paperIsDark ?? newDark
        let key = dark ? "darkPresets" : "lightPresets"
        let saved = preferences.defaults.stringArray(forKey: key)
        colors = saved.map { $0.compactMap(InkColor.parse) } ?? (dark ? InkColor.dark : InkColor.light)
        if previousPaper != dark {
            if let saved = preferences.ink(dark: dark) {
                slot = saved.slot; current = saved.isPreset && colors.indices.contains(slot) ? colors[slot] : saved.color
            } else { slot = 0; current = colors.first ?? (dark ? InkColor.dark[0] : InkColor.light[0]) }
        } else if let index = previous.firstIndex(of: current), colors.indices.contains(index) { current = colors[index] }
        previousPaper = dark
        onRestoredColor?(current)
        layer?.backgroundColor = (newDark ? NSColor(calibratedWhite: 0.18, alpha: 1) : NSColor(calibratedWhite: 0.998, alpha: 1)).cgColor
        layer?.cornerRadius = 14
        layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.09).cgColor; layer?.borderWidth = 1
        layer?.shadowColor = NSColor.black.cgColor; layer?.shadowOpacity = 0.08; layer?.shadowRadius = 12; layer?.shadowOffset = NSSize(width: 0, height: -3)
        updateButtons()
    }
    override func draw(_ dirtyRect: NSRect) {
        guard !isCollapsed else { return }
        NSColor.separatorColor.setFill(); NSRect(x: 20, y: 41 + extraColorHeight, width: bounds.width - 40, height: 1).fill()
        NSColor.separatorColor.setFill()
        NSRect(x: eraserButton.frame.minX - 3, y: 13, width: 1, height: 18).fill()
    }
    func updateButtons() {
        cancelInteractions()
        while buttons.count < colors.count { appendColorButton(at: buttons.count) }
        let previousSize = frame.size
        applyToolbarGeometry()
        let lastRowCount = colorsInRow(colorRowCount - 1)
        let rowOffset = colorRowOffset(colorRowCount - 1)
        let names = ["石墨", "朱红", "琥珀", "苔绿", "湖蓝", "鸢紫"]
        let defaults = dark ? InkColor.dark : InkColor.light
        for (index, button) in buttons.enumerated() {
            button.tag = index
            button.frame = colorButtonFrame(at: index)
            button.isHidden = isCollapsed || !colors.indices.contains(index)
            guard colors.indices.contains(index) else { continue }
            button.inkColor = colors[index]; button.selected = !eraserEnabled && colors[index] == current
            let name = defaults.firstIndex(of: colors[index]).map { names[$0] } ?? colors[index].hex
            let shortcut = ShortcutAction.colors.indices.contains(index) ? shortcutHint(ShortcutAction.colors[index]) : ""
            button.toolTip = "\(name)\(shortcut) · 拖动排序 · 右键编辑或删除"
            button.setAccessibilityLabel("Preset \(index + 1), \(colors[index].hex)\(button.selected ? ", selected" : "")")
        }
        custom?.frame.origin.x = rowOffset + 29 + CGFloat(lastRowCount) * 34
        eraserButton?.frame.origin.x = rowOffset + 71 + CGFloat(lastRowCount) * 34
        custom?.inkColor = current
        needsDisplay = true
        if previousSize != frame.size { onLayoutChange?() }
    }
    private func updateToolButton() {
        eraserButton?.state = eraserEnabled ? .on : .off
        eraserButton?.contentTintColor = eraserEnabled ? .controlAccentColor : .secondaryLabelColor
        eraserButton?.setAccessibilityLabel(eraserEnabled ? "Eraser, selected" : "Eraser")
        eraserButton?.needsDisplay = true
        updateButtons(); updateShapeButtons()
    }
    func saveCurrentColor() {
        let index = colors.firstIndex(of: current)
        preferences.saveInk(SavedInk(color: current, slot: index ?? slot, isPreset: index != nil), dark: dark)
    }
    func choose(_ index: Int) {
        guard colors.indices.contains(index) else { return }
        closePicker(accept: true)
        slot = index; current = colors[index]; eraserEnabled = false
        onEraser?(false); updateButtons(); onColor?(current); saveCurrentColor(); onRestoreFocus?()
    }
    @objc func chosen(_ sender: NSButton) { choose(sender.tag) }
    @objc func addColor() { openPicker(purpose: .add) }
    @objc func togglePicker() { openPicker(purpose: .custom) }
    private func openPicker(purpose: ColorPanelController.Purpose) {
        revealForPicker()
        if popover != nil { closePicker(accept: true); return }
        let popup = makeColorPopover(purpose: purpose)
        popup.show(relativeTo: custom.bounds, of: custom, preferredEdge: .maxY)
    }
    func makeColorPopover(purpose: ColorPanelController.Purpose) -> NSPopover {
        closePicker(accept: true)
        eraserEnabled = false; onEraser?(false)
        initialColor = current; acceptPreview = true; pickerPurpose = purpose
        pendingPresetAddition = nil; onBeginPreview?()
        let controller = ColorPanelController(color: current, recent: recentColors)
        controller.purpose = purpose
        controller.canReplace = colors.indices.contains(slot)
        controller.onAdd = { [weak self] color in self?.editingPreset = nil; self?.pendingPresetAddition = color }
        controller.onPreview = { [weak self] color in self?.current = color; self?.updateButtons(); self?.onColor?(color) }
        controller.onReplace = { [weak self] color in
            guard let self else { return }
            self.replacePreset(color)
        }
        controller.onClose = { [weak self] accept in self?.closePicker(accept: accept) }
        let popup = NSPopover(); popup.contentViewController = controller
        popup.behavior = .semitransient; popup.delegate = self
        popover = popup; previewController = controller
        return popup
    }
    @objc func toggleEraser() {
        closePicker(accept: true)
        eraserEnabled.toggle(); onEraser?(eraserEnabled); onRestoreFocus?()
    }
    func openEraserSizing() {
        closePicker(accept: true); eraserEnabled = true; onEraser?(true)
        toggleEraserSize()
    }
    @objc func toggleEraserSize() {
        revealForPicker()
        if eraserPopover != nil { closePicker(accept: true); return }
        closePicker(accept: true)
        let controller = EraserPanelController(diameter: eraserDiameter)
        controller.onChange = { [weak self] size in
            guard let self else { return }
            self.eraserDiameter = size; self.onEraserSize?(size)
        }
        let popup = NSPopover(); popup.behavior = .semitransient; popup.delegate = self
        popup.contentViewController = controller
        eraserPopover = popup; eraserController = controller
        popup.show(relativeTo: eraserButton.bounds, of: eraserButton, preferredEdge: .maxY)
    }
    func closePicker(accept: Bool) {
        acceptPreview = accept
        let closingColor = popover, closingEraser = eraserPopover
        closingColor?.close()
        // Finish the color transaction before another tool or draft can change its state.
        if closingColor != nil, popover === closingColor { finishColorPicker() }
        closingEraser?.close()
        if closingEraser != nil, eraserPopover === closingEraser {
            eraserPopover = nil; eraserController = nil; onRestoreFocus?()
        }
    }
    func popoverDidClose(_ notification: Notification) {
        if let closed = notification.object as? NSPopover, closed === eraserPopover {
            eraserPopover = nil; eraserController = nil; onRestoreFocus?(); return
        }
        guard let closed = notification.object as? NSPopover, closed === popover else { return }
        finishColorPicker()
    }
    private func finishColorPicker() {
        guard let initialColor else { return }
        previewController?.onPreview = nil
        let accepted = acceptPreview && (pickerPurpose != .add || pendingPresetAddition != nil)
        let before = accepted && pendingPresetAddition != nil && !isCollapsed ? layoutAnimation.capture(in: self) : nil
        if accepted {
            if let color = pendingPresetAddition { addPreset(color, animated: false) }
            if let index = editingPreset, colors.indices.contains(index) { colors[index] = current; persistPresets() }
            var recent = recentColors.filter { $0 != current }; recent.insert(current, at: 0)
            recentColors = Array(recent.prefix(6))
            saveCurrentColor()
        } else { current = initialColor }
        onEndPreview?(accepted, initialColor)
        editingPreset = nil
        pendingPresetAddition = nil
        self.initialColor = nil; popover = nil; previewController = nil
        updateButtons(); onRestoreFocus?()
        if let before { layoutAnimation.animate(from: before, in: self) }
    }
    @objc func toggleCollapsed() {
        let animated = window?.isVisible == true && !isHidden && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let before = animated ? collapseAnimation.capture(in: self, button: collapseButton, collapsed: isCollapsed) : nil
        cancelInteractions()
        closePicker(accept: true)
        isCollapsed.toggle(); preferences.toolbarCollapsed = isCollapsed
        updateToolbarLayout(); onLayoutChange?(); onRestoreFocus?()
        if let before { collapseAnimation.animate(from: before, in: self, button: collapseButton, collapsed: isCollapsed, style: preferences.toolbarAnimationStyle) }
    }
    func setToolbarHidden(_ hidden: Bool) {
        cancelInteractions()
        closePicker(accept: true)
        isHidden = hidden; preferences.toolbarHidden = hidden
        onLayoutChange?(); onRestoreFocus?()
    }
    private func updateToolbarLayout() {
        applyToolbarGeometry()
        for child in subviews { child.isHidden = isCollapsed && child !== collapseButton }
        collapseButton.frame = NSRect(x: isCollapsed ? 0 : 15, y: isCollapsed ? 0 : 41 + extraColorHeight, width: 36, height: 36)
        collapseButton.collapsed = isCollapsed
        collapseButton.toolTip = isCollapsed ? "展开工具栏\(shortcutHint(.collapseToolbar)) · 拖动移动" : "折叠工具栏\(shortcutHint(.collapseToolbar)) · 拖动移动"
        collapseButton.setAccessibilityLabel(collapseButton.toolTip)
        updateButtons(); needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }
    private var colorRowCount: Int { max(1, (colors.count + 5) / 6) }
    private var extraColorHeight: CGFloat { CGFloat(colorRowCount - 1) * 38 }
    private func colorsInRow(_ row: Int) -> Int { min(6, max(0, colors.count - row * 6)) }
    private func colorRowOffset(_ row: Int) -> CGFloat { max(0, (expandedSize.width - (116 + CGFloat(colorsInRow(row)) * 34)) / 2) }
    private func colorButtonFrame(at index: Int) -> NSRect {
        NSRect(x: colorRowOffset(index / 6) + 20 + CGFloat(index % 6) * 34,
               y: 4 + extraColorHeight - CGFloat(index / 6) * 38, width: 34, height: 36)
    }
    private var expandedSize: NSSize { NSSize(width: max(272, 116 + CGFloat(min(6, colors.count)) * 34), height: 80 + extraColorHeight) }
    private var logicalSize: NSSize { isCollapsed ? NSSize(width: 36, height: 36) : expandedSize }
    private func applyToolbarGeometry() {
        let size = logicalSize
        let available = superview?.bounds.size
        // Use the same scale in both states, including when a narrow window limits it.
        let fit = available.map { min(max(1, $0.width - 16) / expandedSize.width, max(1, $0.height - 16) / expandedSize.height) } ?? toolbarScale
        effectiveScale = min(toolbarScale, fit)
        setFrameSize(NSSize(width: size.width * effectiveScale, height: size.height * effectiveScale))
        setBoundsSize(size)
        resizeHandle.frame.origin.x = expandedSize.width - 26
        resizeHandle.frame.origin.y = 57 + extraColorHeight
        if !isCollapsed { collapseButton?.frame.origin.y = 41 + extraColorHeight }
        for button in shapeButtons { button.frame.origin.y = 43 + extraColorHeight }
        contrastButton?.frame.origin.y = 43 + extraColorHeight
    }
    func setToolbarScale(_ value: CGFloat) {
        cancelInteractions(); closePicker(accept: true)
        preferences.toolbarScale = value
        toolbarScale = preferences.toolbarScale
        applyToolbarGeometry(); onLayoutChange?(); onRestoreFocus?()
    }
    func beginResizing(at point: NSPoint) {
        guard !isCollapsed, !isHidden, let superview else { return }
        cancelInteractions(); closePicker(accept: true)
        resizeStart = (superview.convert(point, from: nil), toolbarScale, frame.width)
        resizedToolbar = false
    }
    func updateResizing(at point: NSPoint) {
        guard let start = resizeStart, let superview else { return }
        let delta = superview.convert(point, from: nil).x - start.point.x
        guard resizedToolbar || abs(delta) >= 2 else { return }
        resizedToolbar = true
        let availableWidth = max(1, superview.bounds.maxX - frame.minX - 8)
        toolbarScale = min(1.5, max(0.85, min(start.width + delta, availableWidth) / expandedSize.width))
        applyToolbarGeometry(); needsDisplay = true
    }
    func endResizing() {
        guard resizeStart != nil else { return }
        resizeStart = nil
        if resizedToolbar { preferences.toolbarScale = toolbarScale }
        resizedToolbar = false
        window?.invalidateCursorRects(for: self); onRestoreFocus?()
    }
    private func revealForPicker() {
        if isHidden { setToolbarHidden(false) }
        if isCollapsed { toggleCollapsed() }
    }
    func chooseShape(_ shape: ShiftShape) {
        closePicker(accept: true)
        preferences.shiftShape = shape; updateShapeButtons(); onShape?(shape)
        eraserEnabled = false; onEraser?(false); onRestoreFocus?()
    }
    @objc private func shapeClicked(_ sender: NSButton) { chooseShape(preferences.shapeOrder[sender.tag]) }
    @objc func toggleHighContrast() { onHighContrast?() }
    private func updateShapeButtons() {
        cancelInteractions()
        for (index, button) in shapeButtons.enumerated() {
            button.tag = index
            button.frame = NSRect(x: 54 + CGFloat(index) * 36, y: 43 + extraColorHeight, width: 34, height: 32)
            let shape = preferences.shapeOrder[index]
            button.image = NSImage(systemSymbolName: shape.symbol, accessibilityDescription: shape.label)
            button.toolTip = "\(shape.label)\(shortcutHint(ShortcutAction.shapes[index])) · Shift 拖动 · 拖动按钮排序"
            button.setAccessibilityLabel(button.toolTip)
            button.state = !eraserEnabled && shape == preferences.shiftShape ? .on : .off
            button.contentTintColor = button.state == .on ? .controlAccentColor : .secondaryLabelColor
        }
    }
    func editPreset(_ index: Int) { choose(index); if colors.indices.contains(index) { openPicker(purpose: .edit); editingPreset = index } }
    func replacePreset(_ color: InkColor) {
        guard colors.indices.contains(slot) else { return }
        colors[slot] = color; persistPresets()
    }
    func addPreset(_ color: InkColor, animated: Bool = true) {
        let before = animated && !isCollapsed && !colors.contains(color) ? layoutAnimation.capture(in: self) : nil
        if let index = colors.firstIndex(of: color) { slot = index }
        else { colors.append(color); slot = colors.count - 1 }
        current = color; persistPresets()
        if let before { layoutAnimation.animate(from: before, in: self) }
    }
    func deletePreset(_ index: Int) {
        guard colors.indices.contains(index) else { return }
        closePicker(accept: true)
        let before = isCollapsed ? nil : layoutAnimation.capture(in: self)
        // Keep surviving swatches attached to their colors so they visibly slide
        // into the gap rather than changing color in their old slots.
        buttons.append(buttons.remove(at: index))
        colors.remove(at: index)
        if slot > index { slot -= 1 }
        slot = min(slot, max(0, colors.count - 1))
        persistPresets(); onRestoreFocus?()
        if let before { layoutAnimation.animate(from: before, in: self) }
    }
    private func persistPresets() {
        preferences.defaults.set(colors.map(\.hex), forKey: dark ? "darkPresets" : "lightPresets")
        saveCurrentColor(); updateButtons()
    }
    func resetPresets() {
        closePicker(accept: true)
        preferences.defaults.removeObject(forKey: "lightPresets"); preferences.defaults.removeObject(forKey: "darkPresets")
        refreshAppearance()
    }
    func moveShape(from source: Int, to destination: Int) {
        var order = preferences.shapeOrder
        guard source != destination, order.indices.contains(source), order.indices.contains(destination) else { return }
        closePicker(accept: true)
        order.insert(order.remove(at: source), at: destination)
        preferences.shapeOrder = order; updateShapeButtons()
    }
    func moveColor(from source: Int, to destination: Int) {
        guard source != destination, colors.indices.contains(source), colors.indices.contains(destination) else { return }
        closePicker(accept: true)
        // Move the remembered preset slot as well, including when custom ink is active.
        var slots = Array(colors.indices)
        slots.insert(slots.remove(at: source), at: destination)
        slot = slots.firstIndex(of: slot) ?? slot
        colors.insert(colors.remove(at: source), at: destination)
        persistPresets()
    }
    func reorderDestination(for source: ReorderButton, at point: NSPoint) -> ReorderButton? {
        guard source.superview === self, !isCollapsed, !isHidden, !source.isHidden else { return nil }
        let candidates: [ReorderButton]
        switch source.reorderGroup {
        case "colors": candidates = buttons.filter { !$0.isHidden }
        case "shapes": candidates = shapeButtons
        default: return nil
        }
        return candidates.first { $0.frame.contains(point) }
    }
    private func configureReordering(_ button: ReorderButton) {
        button.wantsLayer = true
        button.onReorderBegin = { [weak self, weak button] point in
            guard let self, let button else { return }
            self.beginReordering(button, at: self.convert(point, from: nil))
        }
        button.onReorderMove = { [weak self] point in
            guard let self else { return }
            self.updateReordering(at: self.convert(point, from: nil))
        }
        button.onReorderEnd = { [weak self] point in
            guard let self else { return }
            self.endReordering(at: self.convert(point, from: nil))
        }
    }
    func beginReordering(_ source: ReorderButton, at point: NSPoint) {
        collapseAnimation.finish()
        cancelReordering()
        guard reorderDestination(for: source, at: point) != nil else { return }
        closePicker(accept: true)
        let rowButtons: [ReorderButton] = source.reorderGroup == "colors" ? buttons.filter { !$0.isHidden } : shapeButtons
        guard let index = rowButtons.firstIndex(where: { $0 === source }) else { return }
        let row = rowButtons.reduce(NSRect.null) { $0.union($1.frame) }
        reorderGesture = ReorderGesture(source: source, originalButtons: rowButtons, originalIndex: index,
                                        frames: rowButtons.map(\.frame),
                                        offset: NSPoint(x: point.x - source.frame.minX, y: point.y - source.frame.minY),
                                        row: row, ordered: rowButtons)
        addSubview(source, positioned: .above, relativeTo: nil)
        source.alphaValue = 0.8
    }
    func updateReordering(at point: NSPoint) {
        guard var gesture = reorderGesture else { return }
        let source = gesture.source
        var ordered = gesture.ordered
        guard let currentIndex = ordered.firstIndex(where: { $0 === source }) else { return }
        let x = min(gesture.row.maxX - source.frame.width, max(gesture.row.minX, point.x - gesture.offset.x))
        let y = min(gesture.row.maxY - source.frame.height, max(gesture.row.minY, point.y - gesture.offset.y))
        source.move(to: NSPoint(x: x, y: y), animated: false)
        let center = NSPoint(x: source.frame.midX, y: source.frame.midY)
        func distance(_ frame: NSRect) -> CGFloat { hypot(center.x - frame.midX, center.y - frame.midY) }
        let destination = gesture.frames.indices.min { distance(gesture.frames[$0]) < distance(gesture.frames[$1]) } ?? currentIndex
        guard destination != currentIndex else { return }
        guard distance(gesture.frames[destination]) + 4 < distance(gesture.frames[currentIndex]) else { return }
        ordered.insert(ordered.remove(at: currentIndex), at: destination)
        gesture.ordered = ordered; reorderGesture = gesture
        // Only displaced neighbors animate. The dragged button follows every event directly.
        for (index, button) in ordered.enumerated() where button !== source {
            button.move(to: gesture.frames[index].origin, animated: true)
        }
    }
    func endReordering(at point: NSPoint) {
        updateReordering(at: point)
        guard let gesture = reorderGesture else { return }
        let isColor = gesture.source.reorderGroup == "colors"
        let ordered = gesture.ordered
        let destination = ordered.firstIndex(where: { $0 === gesture.source }) ?? gesture.originalIndex
        let accepted = gesture.row.insetBy(dx: -8, dy: -8).contains(point)
        let finalButtons = accepted ? ordered : gesture.originalButtons
        if isColor { buttons = finalButtons.compactMap { $0 as? SwatchButton } + buttons.filter { $0.isHidden } }
        else { shapeButtons = finalButtons.compactMap { $0 as? ToolButton } }
        for (index, button) in finalButtons.enumerated() {
            button.tag = index
            button.move(to: gesture.frames[index].origin, animated: false)
        }
        gesture.source.alphaValue = 1
        reorderGesture = nil
        if accepted {
            if isColor { moveColor(from: gesture.originalIndex, to: destination) }
            else { moveShape(from: gesture.originalIndex, to: destination) }
        }
        updateButtons(); updateShapeButtons(); onRestoreFocus?()
    }
    func cancelReordering() {
        guard let gesture = reorderGesture else { return }
        reorderGesture = nil
        for (index, button) in gesture.originalButtons.enumerated() {
            button.move(to: gesture.frames[index].origin, animated: false)
            button.alphaValue = 1; button.cancelTracking()
        }
    }
    @discardableResult func cancelActiveGesture() -> Bool {
        let active = collapseAnimation.isAnimating || reorderGesture != nil || dragOrigin != nil || resizeStart != nil || collapseButton.isTracking || ((buttons as [ReorderButton]) + shapeButtons).contains { $0.isTracking }
        cancelInteractions()
        return active
    }
    func cancelInteractions(finishTransition: Bool = true) {
        layoutAnimation.finish()
        if finishTransition { collapseAnimation.finish() }
        cancelReordering()
        for button in (buttons as [ReorderButton]) + shapeButtons where button.isTracking { button.cancelTracking() }
        collapseButton?.cancelTracking()
        if movedToolbar, let originalFrame { setFrameOrigin(originalFrame) }
        dragOrigin = nil; originalFrame = nil; movedToolbar = false
        if let start = resizeStart {
            resizeStart = nil; toolbarScale = start.scale; applyToolbarGeometry()
        }
        resizeHandle.cancelTracking()
        resizedToolbar = false
    }
    /// Clamping is temporary; growing the window restores the user's chosen location.
    func layoutInContainer(initial: Bool = false) {
        guard let superview else { return }
        cancelInteractions()
        applyToolbarGeometry()
        if initial {
            let saved = preferences.defaults.array(forKey: "palettePosition") as? [Double]
            if let saved, saved.count == 2, saved.allSatisfy(\.isFinite) {
                desiredOrigin = NSPoint(x: saved[0], y: saved[1])
            } else { desiredOrigin = NSPoint(x: (superview.bounds.width - frame.width) / 2, y: 18) }
        }
        setFrameOrigin(clampedOrigin(desiredOrigin ?? frame.origin))
    }
    private func clampedOrigin(_ origin: NSPoint) -> NSPoint {
        guard let superview else { return origin }
        let area = superview.bounds
        let marginX = min(8, max(0, (area.width - frame.width) / 2))
        let marginY = min(8, max(0, (area.height - frame.height) / 2))
        return NSPoint(x: min(max(area.minX + marginX, origin.x), max(area.minX + marginX, area.maxX - frame.width - marginX)),
                       y: min(max(area.minY + marginY, origin.y), max(area.minY + marginY, area.maxY - frame.height - marginY)))
    }
    override func mouseDown(with event: NSEvent) {
        guard let superview, !event.modifierFlags.contains(.control) else { super.mouseDown(with: event); return }
        cancelInteractions(finishTransition: false); closePicker(accept: true)
        dragOrigin = superview.convert(event.locationInWindow, from: nil); originalFrame = frame.origin
    }
    override func mouseDragged(with event: NSEvent) {
        guard let dragOrigin, let originalFrame, let superview else { return }
        let point = superview.convert(event.locationInWindow, from: nil)
        let dx = point.x - dragOrigin.x, dy = point.y - dragOrigin.y
        guard movedToolbar || hypot(dx, dy) >= 4 else { return }
        collapseAnimation.finish()
        movedToolbar = true
        setFrameOrigin(clampedOrigin(NSPoint(x: originalFrame.x + dx, y: originalFrame.y + dy)))
    }
    override func mouseUp(with event: NSEvent) {
        if movedToolbar {
            desiredOrigin = frame.origin
            preferences.defaults.set([frame.origin.x, frame.origin.y], forKey: "palettePosition")
        }
        dragOrigin = nil; originalFrame = nil; movedToolbar = false
    }
}
