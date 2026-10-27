import AppKit
import Carbon.HIToolbox
import UniformTypeIdentifiers
import PDFKit
import ServiceManagement

final class InkeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    var onResize: (() -> Void)?
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        onResize?()
    }
}

final class HotKey {
    let identifier: UInt32
    var reference: EventHotKeyRef?
    var handler: EventHandlerRef?
    var onTrigger: (() -> Void)?
    init(identifier: UInt32 = 1) {
        self.identifier = identifier
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context -> OSStatus in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            let hotkey = Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue()
            var eventID = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                    MemoryLayout<EventHotKeyID>.size, nil, &eventID) == noErr,
                  eventID.signature == 0x494E4B59, eventID.id == hotkey.identifier else { return OSStatus(eventNotHandledErr) }
            DispatchQueue.main.async { hotkey.onTrigger?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func unregister() {
        if let reference { UnregisterEventHotKey(reference); self.reference = nil }
    }
    func register(keyCode: UInt32, modifiers: UInt32) -> Bool {
        if let reference { UnregisterEventHotKey(reference); self.reference = nil }
        let id = EventHotKeyID(signature: 0x494E4B59, id: identifier)
        return RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &reference) == noErr
    }
    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}

final class ShortcutRecorder: NSButton {
    var recording = false
    var savedLabel = UserDefaults.standard.string(forKey: "shortcutLabel") ?? "⌃⌥Space"
    var onRecord: ((UInt32, UInt32, String) -> Bool)?
    var onChange: ((KeyBinding?) -> Bool)?
    var onBegin: (() -> Void)?
    var onReset: (() -> Void)?
    var allowsShiftNumbers = false
    func finishRecording() { recording = false; title = savedLabel }
    override var acceptsFirstResponder: Bool { true }
    override func resignFirstResponder() -> Bool { finishRecording(); return super.resignFirstResponder() }
    @objc func beginRecording() {
        onBegin?(); recording = true; title = "按下快捷键…"; window?.makeFirstResponder(self)
    }
    override func mouseDown(with event: NSEvent) { beginRecording() }
    override func rightMouseDown(with event: NSEvent) {
        guard onChange != nil else { return }
        finishRecording()
        let menu = NSMenu()
        for (title, action) in [("清除快捷键", #selector(clearShortcut)), ("恢复此项默认", #selector(resetShortcut))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    @objc func clearShortcut() { accept(nil) }
    @objc func resetShortcut() { finishRecording(); onReset?() }
    func accept(_ binding: KeyBinding?) {
        let accepted: Bool
        if let onChange { accepted = onChange(binding) }
        else if let binding { accepted = onRecord?(UInt32(binding.keyCode), binding.modifiers, binding.label) == true }
        else { accepted = false }
        if accepted { savedLabel = binding?.label ?? "未设置"; finishRecording() }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { finishRecording(); return }
        guard recording else { super.keyDown(with: event); return }
        let binding = KeyBinding(event: event)
        if [UInt16(51),117].contains(event.keyCode), binding.flags.isEmpty { accept(nil); return }
        guard binding.isFunctionKey || !binding.flags.intersection([.command,.control,.option]).isEmpty || (allowsShiftNumbers && binding.flags == .shift) else { NSSound.beep(); return }
        accept(binding)
    }
}

@main
final class InkeyApp: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextFieldDelegate {
    var window: InkeyWindow!
    var canvas: CanvasView
    let palette: PaletteView
    let preferences: UserPreferences
    let store: DraftStore
    let hotkey = HotKey()
    let screenHotkey = HotKey(identifier: 2)
    var screenCanvas: CanvasView?
    var screenWindow: InkeyWindow?
    var screenFileURL: URL?
    struct CanvasPresentation {
        let window: InkeyWindow
        let canvas: CanvasView
        let fileURL: URL?
        let wasVisible: Bool
    }
    var canvasPresentation: CanvasPresentation?
    var isScreenDraft: Bool { canvasPresentation != nil }
    var statusItem: NSStatusItem!
    var previousApp: NSRunningApplication?
    var fontSizeField: NSTextField?
    var fontSizeStepper: NSStepper?
    var shortcutRecorder: ShortcutRecorder?
    var shortcutRecorders: [ShortcutAction: [ShortcutRecorder]] = [:]
    var shortcutPage: ShortcutSettingsView?
    var settingsTab: NSSegmentedControl?
    var generalSettingsView: NSView?
    var shortcutsSettingsView: NSView?
    var shortcuts: ShortcutSettings { preferences.shortcuts }
    var activeShortcutRecorder: ShortcutRecorder? { shortcutRecorders.values.flatMap { $0 }.first { $0.recording } }
    var settings: NSWindow?
    var keyMonitor: Any?
    var pinned = false
    var suppressAutoHide = false
    var fileURL: URL?
    var statusLabel: NSTextField!
    var errorShown = false
    var fullScreen = false
    let loginLaunch = LoginLaunch()
    var loginLaunchSwitch: NSSwitch?
    var loginLaunchHint: NSTextField?
    var hotkeyNeedsAttention = false

    override convenience init() { self.init(preferences: UserPreferences()) }
    init(preferences: UserPreferences, store: DraftStore = DraftStore()) {
        self.preferences = preferences
        self.store = store
        canvas = CanvasView(frame: .zero, preferences: preferences)
        palette = PaletteView(frame: NSRect(x: 0, y: 0, width: PaletteView.preferredWidth, height: 80), preferences: preferences)
        super.init()
    }

    static func main() {
#if README_ASSETS
        DocumentationRenderer.render()
#else
        let application = NSApplication.shared
        let delegate = InkeyApp()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
        _ = delegate
#endif
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let silentLaunch = LoginLaunch.isSilentLaunch(event: NSAppleEventManager.shared().currentAppleEvent,
                                                      arguments: ProcessInfo.processInfo.arguments)
        if !ProcessInfo.processInfo.arguments.contains("--smoke-test"),
           let identifier = Bundle.main.bundleIdentifier,
           let existing = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == identifier && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            if !silentLaunch {
                DistributedNotificationCenter.default().postNotificationName(.init("com.lnk137.inkey.show"), object: nil, userInfo: nil, deliverImmediately: true)
                existing.activate()
            }
            NSApp.terminate(nil)
            return
        }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(reopenFromAnotherInstance(_:)), name: .init("com.lnk137.inkey.show"), object: nil)
        preferences.migrateInteractionDefaults()
        shortcuts.preserveExistingBindingsForScreenDraft()
        buildMenu()
        buildWindow()
        buildStatusItem()
        hotkey.onTrigger = { [weak self] in self?.handleGlobalShortcut(.toggleWindow) }
        screenHotkey.onTrigger = { [weak self] in self?.handleGlobalShortcut(.screenDraft) }
        if !ProcessInfo.processInfo.arguments.contains("--smoke-test") && !registerSavedHotkeys() {
            hotkeyNeedsAttention = true
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.settings?.isKeyWindow == true, let recorder = self.activeShortcutRecorder {
                recorder.keyDown(with: event); return nil
            }
            if self.window.isKeyWindow, self.handleScreenDraftEscape(event) { return nil }
            if self.window.isKeyWindow, self.shortcuts.binding(for: .highContrast)?.matches(event) == true {
                self.toggleHighContrast(nil); return nil
            }
            guard !self.canvas.isDrawing else { return event }
            if (self.window.isKeyWindow || self.palette.hasPopover), self.handleToolbarVisibilityShortcut(event) { return nil }
            if self.palette.hasPopover && event.keyCode == 53 { self.palette.closePicker(accept: false); return nil }
            guard self.window.isKeyWindow else { return event }
            if event.keyCode == 53, self.palette.cancelActiveGesture() { return nil }
            if self.handleConfiguredShortcut(event) { return nil }
            return event
        }
        let recent = store.recent().filter { $0.1.id.uuidString != preferences.defaults.string(forKey: "screenDraft") }
        let restored = preferences.defaults.string(forKey: "currentDraft").flatMap { id in recent.first { $0.1.id.uuidString == id }?.1 } ?? recent.first?.1
        if let restored { canvas.install(restored) }
        else { canvas.draft.background = isDark ? InkColor("202322") : InkColor("FAF9F6") }
        syncPaletteToPaper()
        canvas.eraserDiameter = preferences.eraserDiameter
        palette.eraserDiameter = preferences.eraserDiameter
        canvas.cursorTrailEnabled = preferences.cursorTrail
        canvas.setEraserEnabled(preferences.tool == .eraser)
        let isSmoke = ProcessInfo.processInfo.arguments.contains("--smoke-test")
        let isUITest = ProcessInfo.processInfo.arguments.contains("--ui-test")
        setPinned(preferences.pinned || isUITest, remember: false)
        if !silentLaunch { showWindow() }
        if preferences.fullScreen && !isSmoke && !isUITest && !silentLaunch {
            DispatchQueue.main.async { self.window.toggleFullScreen(nil) }
        }
        if ProcessInfo.processInfo.arguments.contains("--smoke-test") {
            DispatchQueue.main.async { self.runSmokeTest() }
        }
    }

    var isDark: Bool { NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }

    func syncPaletteToPaper() {
        let paper = canvas.draft.background
        palette.paperIsDark = paper.red * 0.299 + paper.green * 0.587 + paper.blue * 0.114 < 0.5
        palette.refreshAppearance()
    }

    func buildWindow() {
        window = InkeyWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 560), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Inkey"; window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true; window.isMovableByWindowBackground = false
        window.backgroundColor = .windowBackgroundColor; window.minSize = NSSize(width: 420, height: 320)
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false; window.delegate = self
        window.acceptsMouseMovedEvents = true
        window.center(); window.setFrameAutosaveName("InkeyWindow")
        guard let content = window.contentView else { return }
        content.wantsLayer = true
        canvas.frame = content.bounds; canvas.autoresizingMask = [.width, .height]
        content.addSubview(canvas)
        statusLabel = NSTextField(labelWithString: "Inkey")
        statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.frame = NSRect(x: 88, y: content.bounds.height - 29, width: 350, height: 18)
        statusLabel.autoresizingMask = [.minYMargin]
        content.addSubview(statusLabel)
        let more = NSButton(image: NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "More")!, target: self, action: #selector(showMore(_:)))
        more.isBordered = false; more.frame = NSRect(x: content.bounds.width - 43, y: content.bounds.height - 31, width: 30, height: 24)
        more.autoresizingMask = [.minXMargin, .minYMargin]; more.toolTip = "更多"
        content.addSubview(more)
        content.addSubview(palette)
        palette.onLayoutChange = { [weak self] in self?.layoutPalette(initial: false) }
        layoutPalette(initial: true)
        window.onResize = { [weak self] in self?.layoutPalette(initial: false) }
        configureCanvas(canvas)
        canvas.setHighContrast(preferences.highContrast, animated: false)
        palette.highContrastEnabled = canvas.highContrastEnabled
        palette.onHighContrast = { [weak self] in self?.toggleHighContrast(nil) }
        canvas.shiftShape = preferences.shiftShape
        palette.onShape = { [weak self] shape in self?.canvas.shiftShape = shape }
        palette.onColor = { [weak self] color in self?.canvas.applyColor(color) }
        palette.onRestoredColor = { [weak self] color in self?.canvas.ink = color }
        palette.onBeginPreview = { [weak self] in self?.canvas.beginColorPreview() }
        palette.onEndPreview = { [weak self] accept, original in self?.canvas.finishColorPreview(accept: accept, original: original) }
        palette.onRestoreFocus = { [weak self] in self?.canvas.restoreFocus() }
        palette.onEraser = { [weak self] enabled in self?.canvas.setEraserEnabled(enabled) }
        palette.onEraserSize = { [weak self] size in self?.setEraserSize(size) }
        canvas.ink = palette.current
        refreshHighContrastUI()
    }

    func configureCanvas(_ canvas: CanvasView) {
        canvas.onDefaultFontSizeChange = { [weak self] _ in self?.syncFontSizeControls() }
        canvas.onChange = { [weak self] in self?.saveAutomatically() }
        canvas.onEscape = { [weak self] in self?.hideWindow() }
        canvas.onInteraction = { [weak self] in self?.palette.closePicker(accept: true) }
        canvas.isCanvasLocation = { [weak self] point in
            guard let self else { return false }
            let canvasPoint = self.canvas.convert(point, from: nil)
            let palettePoint = self.palette.convert(point, from: nil)
            return (self.isScreenDraft || canvasPoint.y > 40) && (self.palette.isHidden || !self.palette.bounds.contains(palettePoint))
        }
        canvas.onToolChange = { [weak self] enabled in
            self?.palette.eraserEnabled = enabled
            self?.preferences.tool = enabled ? .eraser : .pen
        }
    }

    func layoutPalette(initial: Bool) {
        palette.layoutInContainer(initial: initial)
    }

    func buildMenu() {
        let menu = NSMenu()
        let app = NSMenu(); add("关于 Inkey", #selector(about(_:)), "", to: app)
        add("设置…", #selector(showSettings(_:)), ",", to: app)
        app.addItem(.separator()); add("退出 Inkey", #selector(quit(_:)), "q", to: app)
        let file = NSMenu(); add("新建草稿", #selector(newDraft(_:)), "n", to: file)
        add("打开或导入…", #selector(openDraft(_:)), "o", to: file)
        add("最近草稿…", #selector(showRecent(_:)), "o", modifiers: [.command, .shift], to: file)
        add("保存…", #selector(saveDraft(_:)), "s", to: file)
        add("另存为…", #selector(saveAs(_:)), "s", modifiers: [.command, .shift], to: file)
        add("导出…", #selector(exportDraft(_:)), "e", to: file)
        let edit = NSMenu()
        add("撤销", Selector(("undo:")), "z", to: edit, target: nil)
        add("重做", Selector(("redo:")), "z", modifiers: [.command, .shift], to: edit, target: nil)
        edit.addItem(.separator())
        add("剪切", #selector(NSText.cut(_:)), "x", to: edit, target: nil)
        add("复制", #selector(NSText.copy(_:)), "c", to: edit, target: nil)
        add("粘贴", #selector(NSText.paste(_:)), "v", to: edit, target: nil)
        add("全选", #selector(NSText.selectAll(_:)), "a", to: edit, target: nil)
        let view = NSMenu(); add("适配全部内容", #selector(fit(_:)), "0", to: view)
        add("进入／退出屏幕草稿", #selector(toggleScreenDraft(_:)), "", to: view)
        add("高对比", #selector(toggleHighContrast(_:)), "", to: view)
        add("完整编辑文字", #selector(editTextPrecisely(_:)), "\r", to: view)
        add("橡皮擦", #selector(toggleEraser(_:)), "e", modifiers: [.command, .option], to: view)
        add("缩小橡皮擦", #selector(smallerEraser(_:)), "[", modifiers: [.command, .option], to: view)
        add("放大橡皮擦", #selector(largerEraser(_:)), "]", modifiers: [.command, .option], to: view)
        add("自定义颜色…", #selector(pickColor(_:)), "c", modifiers: [.command, .shift], to: view)
        add("折叠／展开工具栏", #selector(toggleToolbarCollapsed(_:)), "t", modifiers: [.command, .option], to: view)
        add("置顶常驻", #selector(togglePinned(_:)), "p", modifiers: [.command, .shift], to: view)
        add("进入／退出全屏", #selector(toggleFullScreen(_:)), "f", modifiers: [.command, .control], to: view)
        let help = NSMenu(); add("快捷键与使用说明", #selector(help(_:)), "", to: help)
        for (title, submenu) in [("Inkey", app), ("文件", file), ("编辑", edit), ("视图", view), ("帮助", help)] {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: ""); item.submenu = submenu; menu.addItem(item)
        }
        NSApp.mainMenu = menu
    }

    @discardableResult
    func add(_ title: String, _ action: Selector, _ key: String, modifiers: NSEvent.ModifierFlags = .command, to menu: NSMenu, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target ?? ((["undo:", "redo:", "cut:", "copy:", "paste:", "selectAll:"].contains(NSStringFromSelector(action))) ? nil : self)
        if let action = ShortcutAction.allCases.first(where: { $0.selectorName == NSStringFromSelector(action) }), !action.isGlobal {
            applyShortcut(action, to: item)
        }
        menu.addItem(item); return item
    }

    func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pencil.tip.crop.circle", accessibilityDescription: "Inkey")
        statusItem.button?.toolTip = "Inkey · \(shortcuts.label(for: .toggleWindow))"
        let menu = NSMenu()
        add("呼出／收起 Inkey", #selector(toggleAction(_:)), "", to: menu)
        add("进入／退出屏幕草稿", #selector(toggleScreenDraft(_:)), "", to: menu)
        add("新建草稿", #selector(newDraft(_:)), "", to: menu)
        add("最近草稿…", #selector(showRecent(_:)), "", to: menu)
        menu.addItem(.separator()); add("设置…", #selector(showSettings(_:)), "", to: menu)
        add("退出 Inkey", #selector(quit(_:)), "", to: menu)
        statusItem.menu = menu
    }

    func registerSavedHotkey(for action: ShortcutAction = .toggleWindow) -> Bool {
        let hotkey = globalHotkey(for: action)
        guard let binding = shortcuts.binding(for: action) else { hotkey.unregister(); return true }
        return hotkey.register(keyCode: UInt32(binding.keyCode), modifiers: binding.modifiers)
    }
    func globalHotkey(for action: ShortcutAction) -> HotKey { action == .screenDraft ? screenHotkey : hotkey }
    func registerSavedHotkeys() -> Bool {
        let normal = registerSavedHotkey()
        let screen = registerSavedHotkey(for: .screenDraft)
        return normal && screen
    }
    func handleGlobalShortcut(_ action: ShortcutAction) {
        if settings?.isKeyWindow == true, let recorder = activeShortcutRecorder {
            recorder.accept(shortcuts.binding(for: action))
        } else if action == .screenDraft { toggleScreenDraft(nil) }
        else { toggleWindow() }
    }

    func showWindow() {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier,
           front.bundleIdentifier == nil || front.bundleIdentifier != Bundle.main.bundleIdentifier { previousApp = front }
        if !isScreenDraft, !window.isVisible, let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }), !screen.frame.intersects(window.frame) {
            let area = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: area.midX - window.frame.width / 2, y: area.midY - window.frame.height / 2))
        }
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil); canvas.restoreFocus()
        if hotkeyNeedsAttention {
            hotkeyNeedsAttention = false
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.alert("快捷键已被占用", "请在设置中检查全局快捷键，并为不可用的项目选择其他组合。")
                self.showSettings(nil)
            }
        }
    }
    func hideWindow() {
        if isScreenDraft { exitScreenDraft(); return }
        palette.cancelInteractions(); palette.closePicker(accept: true); canvas.flush(); window.orderOut(nil)
        settings?.orderOut(nil)
        previousApp?.activate()
    }
    func toggleWindow() {
        if isScreenDraft { exitScreenDraft(restoreWindow: true); return }
        if window.isVisible && !window.isMiniaturized { hideWindow() } else { showWindow() }
    }
    @objc func reopenFromAnotherInstance(_ notification: Notification) { showWindow() }
    @objc func toggleAction(_ sender: Any?) { toggleWindow() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { hideWindow(); return false }
    func windowDidResignKey(_ notification: Notification) {
        let resignedWindow = notification.object as? NSWindow
        DispatchQueue.main.async { [weak self] in
            guard let self, resignedWindow === self.window, !self.suppressAutoHide, !self.palette.hasPopover,
                  self.window.attachedSheet == nil, !self.window.isKeyWindow,
                  self.settings?.isVisible != true else { return }
            if self.isScreenDraft { self.exitScreenDraft(restoreWindow: false, activatePrevious: false); return }
            guard !self.pinned, !self.fullScreen else { return }
            self.canvas.flush(); self.window.orderOut(nil)
        }
    }
    func windowWillEnterFullScreen(_ notification: Notification) { fullScreen = true; window.level = .normal }
    func windowDidEnterFullScreen(_ notification: Notification) { preferences.fullScreen = true }
    func windowDidExitFullScreen(_ notification: Notification) { fullScreen = false; preferences.fullScreen = false; window.level = pinned ? .floating : .normal }
    @objc func togglePinned(_ sender: Any?) {
        setPinned(!pinned)
        if let item = sender as? NSMenuItem { item.state = pinned ? .on : .off }
    }
    func setPinned(_ value: Bool, remember: Bool = true) {
        pinned = value
        if remember { preferences.pinned = value }
        if !fullScreen && !isScreenDraft { window.level = pinned ? .floating : .normal }
        statusLabel.stringValue = pinned ? "\(canvas.draft.name) · 常驻" : canvas.draft.name
    }
    @objc func editTextPrecisely(_ sender: Any?) { canvas.promoteTextEditing() }
    @objc func toggleEraser(_ sender: Any?) { palette.toggleEraser() }
    @objc func smallerEraser(_ sender: Any?) { setEraserSize(preferences.eraserDiameter - 4) }
    @objc func largerEraser(_ sender: Any?) { setEraserSize(preferences.eraserDiameter + 4) }
    func setEraserSize(_ size: Double) {
        preferences.eraserDiameter = size
        canvas.eraserDiameter = preferences.eraserDiameter
        palette.eraserDiameter = preferences.eraserDiameter
    }
    @objc func toggleFullScreen(_ sender: Any?) {
        if isScreenDraft { exitScreenDraft(restoreWindow: true) }
        palette.closePicker(accept: true); canvas.commitText(); window.toggleFullScreen(nil)
    }
    @objc func fit(_ sender: Any?) { palette.closePicker(accept: true); canvas.fit() }
    @objc func pickColor(_ sender: Any?) { palette.togglePicker() }

    func saveAutomatically() {
        do {
            if canvas.draft.name == "Untitled", let text = canvas.draft.items.first(where: { $0.kind == .text })?.text, !text.isEmpty {
                canvas.draft.name = String(text.prefix(36)).replacingOccurrences(of: "\n", with: " ")
            }
            try store.save(canvas.draft)
            preferences.defaults.set(canvas.draft.id.uuidString, forKey: isScreenDraft ? "screenDraft" : "currentDraft")
            if !isScreenDraft { statusLabel.stringValue = canvas.draft.name + (pinned ? " · 常驻" : "") }
            window.isDocumentEdited = false; errorShown = false
        } catch {
            window.isDocumentEdited = true
            if !errorShown { errorShown = true; alert("草稿尚未保存", error.localizedDescription) }
        }
    }

    @objc func newDraft(_ sender: Any?) {
        palette.closePicker(accept: true); canvas.flush()
        var draft = Draft(); draft.background = isDark ? InkColor("202322") : InkColor("FAF9F6")
        canvas.install(draft); syncPaletteToPaper(); fileURL = nil; saveAutomatically(); showWindow()
    }

    @objc func openDraft(_ sender: Any?) {
        showWindow(); palette.closePicker(accept: true); canvas.commitText()
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "inkey") ?? .data, .png, .jpeg, .tiff, .pdf]
        panel.message = "打开草稿，或导入图片／PDF 作为参考背景。"
        suppressAutoHide = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }; self.suppressAutoHide = false
            guard response == .OK, let url = panel.url else { self.canvas.restoreFocus(); return }
            self.importURL(url)
        }
    }

    func importURL(_ url: URL) {
        do {
            if url.pathExtension.lowercased() == "inkey" {
                var draft = try store.load(url)
                canvas.flush()
                // Import a copy so opening a shared file cannot replace an existing autosave.
                draft.id = UUID(); draft.modified = Date()
                canvas.install(draft); syncPaletteToPaper(); fileURL = url
            } else if url.pathExtension.lowercased() == "pdf" {
                guard let document = PDFDocument(url: url), document.pageCount > 0 else { throw CocoaError(.fileReadCorruptFile) }
                guard document.pageCount <= 100 else { throw NSError(domain: "Inkey", code: 1, userInfo: [NSLocalizedDescriptionKey: "请导入不超过 100 页的 PDF。"] ) }
                var items: [InkItem] = []; var y = canvas.draft.anchor.y
                for index in 0..<document.pageCount {
                    guard let page = document.page(at: index) else { continue }
                    let size = page.bounds(for: .mediaBox).size
                    guard size.width > 0 && size.height > 0 else { continue }
                    let scale = min(1, 1000 / size.width)
                    let image = page.thumbnail(of: NSSize(width: size.width * scale * 2, height: size.height * scale * 2), for: .mediaBox)
                    if let data = image.tiffRepresentation {
                        items.append(InkItem(kind: .image, points: [InkPoint(NSPoint(x: canvas.draft.anchor.x, y: y))], color: canvas.ink, imageData: data, imageWidth: size.width * scale, imageHeight: size.height * scale))
                        y += size.height * scale + 24
                    }
                }
                guard !items.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
                canvas.replaceItems(items + canvas.draft.items, name: "Import PDF"); canvas.fit()
            } else {
                guard let image = NSImage(contentsOf: url), let data = image.tiffRepresentation, image.size.width > 0, image.size.height > 0 else { throw CocoaError(.fileReadCorruptFile) }
                let scale = min(1, 700 / image.size.width)
                let item = InkItem(kind: .image, points: [canvas.draft.anchor], color: canvas.ink, imageData: data, imageWidth: image.size.width * scale, imageHeight: image.size.height * scale)
                canvas.replaceItems([item] + canvas.draft.items, name: "Import Image"); canvas.fit()
            }
            saveAutomatically(); showWindow()
        } catch { alert("无法打开文件", error.localizedDescription) }
    }

    @objc func saveDraft(_ sender: Any?) {
        palette.closePicker(accept: true); canvas.flush(); showWindow()
        if let fileURL {
            do { try store.save(canvas.draft, to: fileURL) }
            catch { alert("无法保存文件", error.localizedDescription) }
            return
        }
        presentSavePanel()
    }

    @objc func saveAs(_ sender: Any?) {
        palette.closePicker(accept: true); canvas.flush(); showWindow()
        presentSavePanel()
    }

    func presentSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "inkey") ?? .data]
        panel.nameFieldStringValue = canvas.draft.name + ".inkey"
        suppressAutoHide = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }; self.suppressAutoHide = false
            if response == .OK, let url = panel.url {
                do { try self.store.save(self.canvas.draft, to: url); self.fileURL = url }
                catch { self.alert("无法保存文件", error.localizedDescription) }
            }
            self.canvas.restoreFocus()
        }
    }

    @objc func exportDraft(_ sender: Any?) {
        palette.closePicker(accept: true); canvas.flush(); showWindow()
        let panel = NSSavePanel()
        let format = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 28))
        format.addItems(withTitles: ["PNG", "PDF", "Inkey"])
        let accessory = ExportAccessory(format: format, panel: panel)
        panel.accessoryView = accessory; panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = canvas.draft.name + ".png"
        suppressAutoHide = true
        panel.beginSheetModal(for: window) { [weak self, accessory] response in
            guard let self else { return }; self.suppressAutoHide = false
            if response == .OK, let url = panel.url {
                do {
                    if accessory.format.indexOfSelectedItem == 2 { try self.store.save(self.canvas.draft, to: url) }
                    else {
                        guard let data = self.canvas.exportData(pdf: accessory.format.indexOfSelectedItem == 1) else { throw NSError(domain: "Inkey", code: 2, userInfo: [NSLocalizedDescriptionKey: "画布过大，无法导出。请先删除远离内容的笔迹，或保存为 Inkey 文件。"] ) }
                        try data.write(to: url, options: .atomic)
                    }
                } catch { self.alert("无法导出", error.localizedDescription) }
            }
            self.canvas.restoreFocus()
        }
    }

    @objc func showRecent(_ sender: Any?) {
        canvas.flush(); showWindow()
        let menu = NSMenu()
        let recent = store.recent()
        if recent.isEmpty { menu.addItem(withTitle: "暂无草稿", action: nil, keyEquivalent: "") }
        let formatter = DateFormatter(); formatter.dateFormat = "MM-dd HH:mm"
        for (url, draft) in recent.prefix(30) {
            let item = NSMenuItem(title: "\(draft.name)   ·   \(formatter.string(from: draft.modified))", action: #selector(loadRecent(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = url
            item.state = draft.id == canvas.draft.id ? .on : .off
            menu.addItem(item)
        }
        if let content = window.contentView { menu.popUp(positioning: nil, at: NSPoint(x: 90, y: content.bounds.height - 38), in: content) }
    }
    @objc func loadRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        do { let draft = try store.load(url); canvas.flush(); canvas.install(draft); syncPaletteToPaper(); fileURL = nil; saveAutomatically(); showWindow() }
        catch { alert("无法读取草稿", error.localizedDescription) }
    }

    @objc func toggleToolbarCollapsed(_ sender: Any?) {
        if palette.isHidden { palette.setToolbarHidden(false) }
        palette.toggleCollapsed()
    }
    @objc func toggleToolbarHidden(_ sender: Any?) { palette.setToolbarHidden(!palette.isHidden) }
    func handleToolbarVisibilityShortcut(_ event: NSEvent) -> Bool {
        guard shortcuts.binding(for: .hideToolbar)?.matches(event) == true else { return false }
        toggleToolbarHidden(nil); return true
    }

    @objc func showMore(_ sender: NSButton) {
        moreMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: sender)
    }
    func moreMenu() -> NSMenu {
        let menu = NSMenu()
        add(isScreenDraft ? "退出屏幕草稿" : "进入屏幕草稿", #selector(toggleScreenDraft(_:)), "", to: menu)
        let contrast = add("高对比", #selector(toggleHighContrast(_:)), "", to: menu)
        contrast.state = canvas.highContrastEnabled ? .on : .off
        add("新建草稿", #selector(newDraft(_:)), "n", to: menu)
        add("最近草稿…", #selector(showRecent(_:)), "", to: menu)
        menu.addItem(.separator())
        add(palette.isCollapsed ? "展开工具栏" : "折叠工具栏", #selector(toggleToolbarCollapsed(_:)), "t", modifiers: [.command, .option], to: menu)
        add(palette.isHidden ? "显示工具栏" : "隐藏工具栏", #selector(toggleToolbarHidden(_:)), "t", modifiers: [.command, .shift], to: menu)
        let sizeItem = NSMenuItem(title: "工具栏大小", action: nil, keyEquivalent: "")
        sizeItem.submenu = toolbarSizeMenu(); menu.addItem(sizeItem)
        let pin = add("置顶常驻", #selector(togglePinned(_:)), "p", modifiers: [.command, .shift], to: menu); pin.state = pinned ? .on : .off
        add("进入／退出全屏", #selector(toggleFullScreen(_:)), "f", modifiers: [.command, .control], to: menu)
        add("适配全部内容", #selector(fit(_:)), "0", to: menu)
        menu.addItem(.separator())
        add("打开或导入…", #selector(openDraft(_:)), "o", to: menu)
        add("保存…", #selector(saveDraft(_:)), "s", to: menu)
        add("另存为…", #selector(saveAs(_:)), "s", modifiers: [.command, .shift], to: menu)
        add("导出…", #selector(exportDraft(_:)), "e", to: menu)
        menu.addItem(.separator()); add("设置…", #selector(showSettings(_:)), ",", to: menu)
        return menu
    }

    @objc func showSettings(_ sender: Any?) {
        palette.closePicker(accept: true); canvas.commitText()
        refreshLoginLaunchControls()
        if let settings {
            settings.level = isScreenDraft ? NSWindow.Level(rawValue: window.level.rawValue + 1) : .normal
            NSApp.activate(ignoringOtherApps: true); settings.makeKeyAndOrderFront(nil); return
        }
        let panel = makeSettingsWindow()
        if isScreenDraft { panel.level = NSWindow.Level(rawValue: window.level.rawValue + 1) }
        settings = panel; NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil)
    }

    func makeSettingsWindow() -> NSWindow {
        let loginSwitch = NSSwitch()
        loginSwitch.target = self; loginSwitch.action = #selector(changeLoginLaunch(_:))
        loginSwitch.setAccessibilityLabel("开机自启动（静默）")
        loginLaunchSwitch = loginSwitch
        let loginHint = NSTextField(wrappingLabelWithString: "")
        loginLaunchHint = loginHint
        refreshLoginLaunchControls()

        let recorder = makeShortcutRecorder(for: .toggleWindow)
        shortcutRecorder = recorder
        let general = SettingsLayout.section("通用", rows: [
            SettingsLayout.row("开机自启动", detail: loginHint, control: loginSwitch),
            SettingsLayout.row("呼出／收起快捷键", detail: NSTextField(wrappingLabelWithString: "点击录制，Esc 取消"), control: recorder)
        ])

        let placement = NSPopUpButton()
        placement.widthAnchor.constraint(equalToConstant: 156).isActive = true
        placement.addItems(withTitles: ["单击定位", "跟随指针"])
        placement.selectItem(at: UserDefaults.standard.bool(forKey: "pointerPlacement") ? 1 : 0)
        placement.target = self; placement.action = #selector(changePlacement(_:))
        placement.setAccessibilityLabel("文字落点")
        let formatter = NumberFormatter(); formatter.minimum = 6; formatter.maximum = 200
        formatter.maximumFractionDigits = 1; formatter.numberStyle = .decimal
        let size = NSTextField()
        size.widthAnchor.constraint(equalToConstant: 64).isActive = true
        size.alignment = .right
        size.formatter = formatter; size.delegate = self; size.target = self; size.action = #selector(changeDefaultFontSize(_:))
        size.setAccessibilityLabel("Default typing font size"); fontSizeField = size
        let unit = NSTextField(labelWithString: "pt")
        unit.font = .systemFont(ofSize: 12); unit.textColor = .secondaryLabelColor
        let stepper = NSStepper()
        stepper.minValue = 6; stepper.maxValue = 200; stepper.increment = 1; stepper.valueWraps = false
        stepper.target = self; stepper.action = #selector(stepDefaultFontSize(_:))
        stepper.setAccessibilityLabel("Adjust default typing font size"); fontSizeStepper = stepper
        let sizeControls = NSStackView(views: [size, unit, stepper])
        sizeControls.orientation = .horizontal; sizeControls.alignment = .centerY; sizeControls.spacing = 8
        syncFontSizeControls()
        let follow = NSSwitch()
        follow.state = preferences.resizeUpdatesDefaultFont ? .on : .off
        follow.target = self; follow.action = #selector(changeResizeDefault(_:))
        follow.setAccessibilityLabel("沿用缩放后的字号")
        let typing = SettingsLayout.section("文字输入", rows: [
            SettingsLayout.row("文字落点", control: placement),
            SettingsLayout.row("默认字号", control: sizeControls),
            SettingsLayout.row("沿用缩放后的字号", detail: NSTextField(wrappingLabelWithString: "拖动文字改字号后，用于下次输入"), control: follow)
        ])

        let trail = NSSwitch()
        trail.state = preferences.cursorTrail ? .on : .off
        trail.target = self; trail.action = #selector(changeCursorTrail(_:)); trail.setAccessibilityLabel("Crosshair trail")
        let animation = NSPopUpButton()
        animation.widthAnchor.constraint(equalToConstant: 156).isActive = true
        for style in ToolbarAnimationStyle.allCases {
            animation.addItem(withTitle: style.label)
            animation.lastItem?.representedObject = style.rawValue
        }
        animation.selectItem(at: ToolbarAnimationStyle.allCases.firstIndex(of: preferences.toolbarAnimationStyle) ?? 0)
        animation.target = self; animation.action = #selector(changeToolbarAnimation(_:))
        animation.setAccessibilityLabel("工具栏折叠动画")
        let reset = NSButton(title: "恢复默认", target: self, action: #selector(resetColors(_:)))
        reset.bezelStyle = .rounded
        reset.setAccessibilityLabel("恢复默认色板")
        let autoContrast = NSSwitch()
        autoContrast.state = preferences.autoHighContrastOnScreen ? .on : .off
        autoContrast.target = self; autoContrast.action = #selector(changeAutoHighContrast(_:))
        autoContrast.setAccessibilityLabel("进入屏幕草稿时自动开启高对比")
        let canvas = SettingsLayout.section("画布与工具栏", rows: [
            SettingsLayout.row("进入屏幕草稿时自动开启高对比", control: autoContrast),
            SettingsLayout.row("十字指针轨迹", control: trail),
            SettingsLayout.row("折叠动画", control: animation),
            SettingsLayout.row("预设颜色", control: reset)
        ])
        let panel = SettingsLayout.window(sections: [general, typing, canvas])
        installShortcutSettings(in: panel)
        return panel
    }
    func applicationDidBecomeActive(_ notification: Notification) { refreshLoginLaunchControls() }

    func refreshLoginLaunchControls() {
        loginLaunchSwitch?.state = loginLaunch.isEnabled || loginLaunch.needsApproval ? .on : .off
        loginLaunchHint?.stringValue = loginLaunch.needsApproval
            ? "请在系统“登录项”中允许，或关闭此开关取消"
            : "登录后静默运行，不弹出草稿窗口"
    }

    @objc func changeLoginLaunch(_ sender: NSSwitch) {
        do {
            // A pending registration needs approval rather than another registration.
            if loginLaunch.needsApproval {
                if sender.state == .off { try loginLaunch.setEnabled(false) }
                else { SMAppService.openSystemSettingsLoginItems() }
            } else {
                try loginLaunch.setEnabled(sender.state == .on)
                if loginLaunch.needsApproval { SMAppService.openSystemSettingsLoginItems() }
            }
        } catch {
            alert("无法更改开机自启动", error.localizedDescription)
        }
        refreshLoginLaunchControls()
    }
    func controlTextDidEndEditing(_ notification: Notification) {
        if let field = notification.object as? NSTextField, field === fontSizeField { changeDefaultFontSize(field) }
    }
    func syncFontSizeControls() {
        fontSizeField?.doubleValue = preferences.defaultFontSize
        fontSizeStepper?.doubleValue = preferences.defaultFontSize
    }
    @objc func changeDefaultFontSize(_ sender: NSTextField) {
        guard let formatter = sender.formatter as? NumberFormatter,
              let number = formatter.number(from: sender.stringValue), number.doubleValue.isFinite,
              (6...200).contains(number.doubleValue) else { NSSound.beep(); syncFontSizeControls(); return }
        preferences.defaultFontSize = number.doubleValue; syncFontSizeControls()
    }
    @objc func stepDefaultFontSize(_ sender: NSStepper) { preferences.defaultFontSize = sender.doubleValue; syncFontSizeControls() }
    @objc func changeResizeDefault(_ sender: NSSwitch) { preferences.resizeUpdatesDefaultFont = sender.state == .on }
    @objc func changeToolbarAnimation(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let style = ToolbarAnimationStyle(rawValue: raw) else { return }
        preferences.toolbarAnimationStyle = style
    }
    @objc func changePlacement(_ sender: NSPopUpButton) { UserDefaults.standard.set(sender.indexOfSelectedItem == 1, forKey: "pointerPlacement") }

    func toolbarSizeMenu() -> NSMenu {
        let menu = NSMenu()
        for (title, percent) in [("小 · 85%", 85), ("标准 · 100%", 100), ("大 · 125%", 125), ("特大 · 150%", 150)] {
            let item = add(title, #selector(changeToolbarSize(_:)), "", to: menu)
            item.tag = percent
            item.state = abs(palette.toolbarScale - CGFloat(percent) / 100) < 0.005 ? .on : .off
        }
        return menu
    }
    @objc func changeToolbarSize(_ sender: NSMenuItem) { palette.setToolbarScale(CGFloat(sender.tag) / 100) }
    @objc func changeCursorTrail(_ sender: NSSwitch) { preferences.cursorTrail = sender.state == .on; canvas.cursorTrailEnabled = preferences.cursorTrail }
    @objc func resetColors(_ sender: Any?) { palette.resetPresets() }
    @objc func help(_ sender: Any?) {
        showSettings(nil)
        settingsTab?.selectedSegment = 1
        if let settingsTab { changeSettingsTab(settingsTab) }
    }
    @objc func about(_ sender: Any?) { NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Inkey", .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.5.1", .credits: NSAttributedString(string: "A quiet place to think.")]) }
    @objc func quit(_ sender: Any?) { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { palette.closePicker(accept: true); canvas.flush(); return .terminateNow }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }
    func application(_ sender: NSApplication, openFile filename: String) -> Bool { importURL(URL(fileURLWithPath: filename)); return true }
    func alert(_ title: String, _ message: String) {
        let previous = suppressAutoHide; suppressAutoHide = true
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message
        if isScreenDraft { alert.window.level = NSWindow.Level(rawValue: window.level.rawValue + 1) }
        alert.addButton(withTitle: "好"); alert.runModal()
        suppressAutoHide = previous
    }

    func runSmokeTest() {
        // The smoke test operates on a temporary draft and never overwrites the restored one.
        let restored = canvas.draft
        canvas.install(Draft())
        let text = InkItem(kind: .text, points: [InkPoint(NSPoint(x: 120, y: 100))], color: InkColor.light[0], text: "left")
        let arrow = InkItem(kind: .arrow, points: [InkPoint(NSPoint(x: 190, y: 115)), InkPoint(NSPoint(x: 350, y: 115))], color: InkColor.light[4])
        canvas.replaceItems([text, arrow], name: "Smoke")
        canvas.selection = text.id; canvas.applyColor(InkColor.light[1])
        precondition(canvas.draft.items[0].color == InkColor.light[1])
        canvas.beginColorPreview(); canvas.applyColor(InkColor.light[2]); canvas.finishColorPreview(accept: false, original: InkColor.light[1])
        precondition(canvas.draft.items[0].color == InkColor.light[1])
        precondition(canvas.exportData(pdf: false)?.count ?? 0 > 100)
        precondition(canvas.exportData(pdf: true)?.count ?? 0 > 100)
        canvas.undo(nil); precondition(canvas.draft.items[0].color == InkColor.light[0])
        canvas.redo(nil); precondition(canvas.draft.items[0].color == InkColor.light[1])
        canvas.install(restored)
        print("Inkey smoke test passed: color preview, undo, redo, PNG, PDF")
        NSApp.terminate(nil)
    }
}

final class ExportAccessory: NSView {
    let format: NSPopUpButton
    weak var panel: NSSavePanel?
    init(format: NSPopUpButton, panel: NSSavePanel) {
        self.format = format; self.panel = panel
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 36))
        addSubview(format); format.target = self; format.action = #selector(changed)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc func changed() {
        let types: [UTType] = [.png, .pdf, UTType(filenameExtension: "inkey") ?? .data]
        let extensions = ["png", "pdf", "inkey"]
        let index = format.indexOfSelectedItem
        panel?.allowedContentTypes = [types[index]]
        if let panel { panel.nameFieldStringValue = (panel.nameFieldStringValue as NSString).deletingPathExtension + "." + extensions[index] }
    }
}
