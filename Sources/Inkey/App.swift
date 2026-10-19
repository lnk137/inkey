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
    var reference: EventHotKeyRef?
    var handler: EventHandlerRef?
    var onTrigger: (() -> Void)?
    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context -> OSStatus in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let hotkey = Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { hotkey.onTrigger?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func register(keyCode: UInt32, modifiers: UInt32) -> Bool {
        if let reference { UnregisterEventHotKey(reference); self.reference = nil }
        let id = EventHotKeyID(signature: 0x494E4B59, id: 1)
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
    func finishRecording() { recording = false; title = savedLabel }
    var onRecord: ((UInt32, UInt32, String) -> Bool)?
    override var acceptsFirstResponder: Bool { true }
    @objc func beginRecording() {
        recording = true; title = "按下快捷键…"; window?.makeFirstResponder(self)
    }
    override func mouseDown(with event: NSEvent) { beginRecording() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { finishRecording(); return }
        guard recording else { super.keyDown(with: event); return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.control) || flags.contains(.option) || flags.contains(.command) else { NSSound.beep(); return }
        var modifiers: UInt32 = 0
        var label = ""
        if flags.contains(.control) { modifiers |= UInt32(controlKey); label += "⌃" }
        if flags.contains(.option) { modifiers |= UInt32(optionKey); label += "⌥" }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey); label += "⇧" }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey); label += "⌘" }
        let names: [UInt16: String] = [49: "Space", 36: "Return", 48: "Tab", 123: "←", 124: "→", 125: "↓", 126: "↑"]
        label += names[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
        if onRecord?(UInt32(event.keyCode), modifiers, label) == true { savedLabel = label; finishRecording() }
    }
}

@main
final class InkeyApp: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextFieldDelegate {
    var window: InkeyWindow!
    let canvas = CanvasView(frame: .zero)
    let palette: PaletteView
    let preferences: UserPreferences
    let store = DraftStore()
    let hotkey = HotKey()
    var statusItem: NSStatusItem!
    var previousApp: NSRunningApplication?
    var fontSizeField: NSTextField?
    var fontSizeStepper: NSStepper?
    var shortcutRecorder: ShortcutRecorder?
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
    init(preferences: UserPreferences) {
        self.preferences = preferences
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
        buildMenu()
        buildWindow()
        buildStatusItem()
        hotkey.onTrigger = { [weak self] in
            guard let self else { return }
            if self.settings?.isKeyWindow == true, self.shortcutRecorder?.recording == true {
                self.shortcutRecorder?.finishRecording()
            } else { self.toggleWindow() }
        }
        if !ProcessInfo.processInfo.arguments.contains("--smoke-test") && !registerSavedHotkey() {
            hotkeyNeedsAttention = true
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.settings?.isKeyWindow == true, let recorder = self.shortcutRecorder, recorder.recording {
                recorder.keyDown(with: event); return nil
            }
            guard !self.canvas.isDrawing else { return event }
            if (self.window.isVisible || self.palette.hasPopover), self.handleToolbarVisibilityShortcut(event) { return nil }
            if self.palette.hasPopover && event.keyCode == 53 { self.palette.closePicker(accept: false); return nil }
            guard self.window.isKeyWindow else { return event }
            if event.keyCode == 53, self.palette.cancelActiveGesture() { return nil }
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if !self.palette.hasPopover, let shape = ShiftShape.shortcut(event, order: self.preferences.shapeOrder),
               (self.window.firstResponder as? NSTextView)?.hasMarkedText() != true {
                self.palette.chooseShape(shape); return nil
            }
            if modifiers == [.option], let char = event.charactersIgnoringModifiers, let number = Int(char), (1...6).contains(number) {
                self.palette.choose(number - 1); return nil
            }
            return event
        }
        let restored = UserDefaults.standard.string(forKey: "currentDraft").flatMap { id in store.recent().first { $0.1.id.uuidString == id }?.1 } ?? store.recent().first?.1
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
        canvas.onDefaultFontSizeChange = { [weak self] _ in self?.syncFontSizeControls() }
        canvas.onChange = { [weak self] in self?.saveAutomatically() }
        canvas.onEscape = { [weak self] in self?.hideWindow() }
        canvas.onInteraction = { [weak self] in self?.palette.closePicker(accept: true) }
        canvas.isCanvasLocation = { [weak self] point in
            guard let self else { return false }
            let canvasPoint = self.canvas.convert(point, from: nil)
            let palettePoint = self.palette.convert(point, from: nil)
            return canvasPoint.y > 40 && (self.palette.isHidden || !self.palette.bounds.contains(palettePoint))
        }
        canvas.shiftShape = preferences.shiftShape
        palette.onShape = { [weak self] shape in self?.canvas.shiftShape = shape }
        palette.onColor = { [weak self] color in self?.canvas.applyColor(color) }
        palette.onRestoredColor = { [weak self] color in self?.canvas.ink = color }
        palette.onBeginPreview = { [weak self] in self?.canvas.beginColorPreview() }
        palette.onEndPreview = { [weak self] accept, original in self?.canvas.finishColorPreview(accept: accept, original: original) }
        palette.onRestoreFocus = { [weak self] in self?.canvas.restoreFocus() }
        palette.onEraser = { [weak self] enabled in self?.canvas.setEraserEnabled(enabled) }
        palette.onEraserSize = { [weak self] size in self?.setEraserSize(size) }
        canvas.onToolChange = { [weak self] enabled in
            self?.palette.eraserEnabled = enabled
            self?.preferences.tool = enabled ? .eraser : .pen
        }
        canvas.ink = palette.current
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
        menu.addItem(item); return item
    }

    func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pencil.tip.crop.circle", accessibilityDescription: "Inkey")
        statusItem.button?.toolTip = "Inkey · \(UserDefaults.standard.string(forKey: "shortcutLabel") ?? "⌃⌥Space")"
        let menu = NSMenu()
        add("呼出／收起 Inkey", #selector(toggleAction(_:)), "", to: menu)
        add("新建草稿", #selector(newDraft(_:)), "", to: menu)
        add("最近草稿…", #selector(showRecent(_:)), "", to: menu)
        menu.addItem(.separator()); add("设置…", #selector(showSettings(_:)), "", to: menu)
        add("退出 Inkey", #selector(quit(_:)), "", to: menu)
        statusItem.menu = menu
    }

    func registerSavedHotkey() -> Bool {
        let defaults = UserDefaults.standard
        let key = defaults.object(forKey: "shortcutCode") as? UInt32 ?? 49
        let modifiers = defaults.object(forKey: "shortcutModifiers") as? UInt32 ?? UInt32(controlKey | optionKey)
        return hotkey.register(keyCode: key, modifiers: modifiers)
    }

    func showWindow() {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier,
           front.bundleIdentifier == nil || front.bundleIdentifier != Bundle.main.bundleIdentifier { previousApp = front }
        if !window.isVisible, let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }), !screen.frame.intersects(window.frame) {
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
                self.alert("快捷键已被占用", "请在设置中重新录制呼出快捷键。")
                self.showSettings(nil)
            }
        }
    }
    func hideWindow() {
        palette.cancelInteractions(); palette.closePicker(accept: true); canvas.flush(); window.orderOut(nil)
        settings?.orderOut(nil)
        previousApp?.activate()
    }
    func toggleWindow() { if window.isVisible && !window.isMiniaturized { hideWindow() } else { showWindow() } }
    @objc func reopenFromAnotherInstance(_ notification: Notification) { showWindow() }
    @objc func toggleAction(_ sender: Any?) { toggleWindow() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { hideWindow(); return false }
    func windowDidResignKey(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.pinned, !self.suppressAutoHide, !self.palette.hasPopover,
                  self.window.attachedSheet == nil, !self.window.isKeyWindow,
                  self.settings?.isVisible != true, !self.fullScreen else { return }
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
        if !fullScreen { window.level = pinned ? .floating : .normal }
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
    @objc func toggleFullScreen(_ sender: Any?) { palette.closePicker(accept: true); canvas.commitText(); window.toggleFullScreen(nil) }
    @objc func fit(_ sender: Any?) { palette.closePicker(accept: true); canvas.fit() }
    @objc func pickColor(_ sender: Any?) { palette.togglePicker() }

    func saveAutomatically() {
        do {
            if canvas.draft.name == "Untitled", let text = canvas.draft.items.first(where: { $0.kind == .text })?.text, !text.isEmpty {
                canvas.draft.name = String(text.prefix(36)).replacingOccurrences(of: "\n", with: " ")
            }
            try store.save(canvas.draft)
            UserDefaults.standard.set(canvas.draft.id.uuidString, forKey: "currentDraft")
            statusLabel.stringValue = canvas.draft.name + (pinned ? " · 常驻" : "")
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
        guard event.keyCode == 17,
              event.modifierFlags.intersection([.command, .option, .control, .shift]) == [.command, .shift] else { return false }
        toggleToolbarHidden(nil); return true
    }

    @objc func showMore(_ sender: NSButton) {
        moreMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: sender)
    }
    func moreMenu() -> NSMenu {
        let menu = NSMenu()
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
        if let settings { NSApp.activate(ignoringOtherApps: true); settings.makeKeyAndOrderFront(nil); return }
        let panel = makeSettingsWindow()
        settings = panel; NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil)
    }

    func makeSettingsWindow() -> NSWindow {
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 530), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Inkey 设置"; panel.isReleasedWhenClosed = false; panel.center()
        guard let content = panel.contentView else { return panel }
        let label = NSTextField(labelWithString: "呼出／收起快捷键")
        label.frame = NSRect(x: 28, y: 364, width: 140, height: 20); content.addSubview(label)
        let recorder = ShortcutRecorder(title: UserDefaults.standard.string(forKey: "shortcutLabel") ?? "⌃⌥Space", target: nil, action: nil)
        recorder.target = recorder; recorder.action = #selector(ShortcutRecorder.beginRecording)
        recorder.bezelStyle = .rounded; recorder.frame = NSRect(x: 196, y: 358, width: 190, height: 32)
        recorder.onRecord = { [weak self] key, modifiers, label in
            guard let self else { return false }
            if self.hotkey.register(keyCode: key, modifiers: modifiers) {
                UserDefaults.standard.set(Int(key), forKey: "shortcutCode")
                UserDefaults.standard.set(Int(modifiers), forKey: "shortcutModifiers")
                UserDefaults.standard.set(label, forKey: "shortcutLabel")
                self.statusItem.button?.toolTip = "Inkey · \(label)"; return true
            }
            _ = self.registerSavedHotkey()
            self.alert("快捷键不可用", "该组合可能已被其他应用使用，请更换。")
            return false
        }
        shortcutRecorder = recorder
        content.addSubview(recorder)
        let shortcutHint = NSTextField(labelWithString: "点击后按下新组合，Esc 取消")
        shortcutHint.font = .systemFont(ofSize: 11); shortcutHint.textColor = .secondaryLabelColor
        shortcutHint.frame = NSRect(x: 196, y: 335, width: 200, height: 18); content.addSubview(shortcutHint)
        let placementLabel = NSTextField(labelWithString: "文字落点")
        placementLabel.frame = NSRect(x: 28, y: 301, width: 140, height: 20); content.addSubview(placementLabel)
        let placement = NSPopUpButton(frame: NSRect(x: 196, y: 296, width: 190, height: 28))
        placement.addItems(withTitles: ["单击定位", "跟随指针"])
        placement.selectItem(at: UserDefaults.standard.bool(forKey: "pointerPlacement") ? 1 : 0)
        placement.target = self; placement.action = #selector(changePlacement(_:)); content.addSubview(placement)
        let sizeLabel = NSTextField(labelWithString: "默认输入字号")
        sizeLabel.frame = NSRect(x: 28, y: 251, width: 150, height: 20); content.addSubview(sizeLabel)
        let formatter = NumberFormatter(); formatter.minimum = 6; formatter.maximum = 200
        formatter.maximumFractionDigits = 1; formatter.numberStyle = .decimal
        let size = NSTextField(frame: NSRect(x: 258, y: 246, width: 78, height: 26))
        size.formatter = formatter; size.delegate = self; size.target = self; size.action = #selector(changeDefaultFontSize(_:))
        size.setAccessibilityLabel("Default typing font size"); content.addSubview(size); fontSizeField = size
        let stepper = NSStepper(frame: NSRect(x: 344, y: 243, width: 20, height: 28))
        stepper.minValue = 6; stepper.maxValue = 200; stepper.increment = 1; stepper.valueWraps = false
        stepper.target = self; stepper.action = #selector(stepDefaultFontSize(_:)); stepper.setAccessibilityLabel("Adjust default typing font size")
        content.addSubview(stepper); fontSizeStepper = stepper; syncFontSizeControls()
        let follow = NSButton(checkboxWithTitle: "拖拽缩放后，设为下次输入字号", target: self, action: #selector(changeResizeDefault(_:)))
        follow.frame = NSRect(x: 28, y: 207, width: 356, height: 24)
        follow.state = preferences.resizeUpdatesDefaultFont ? .on : .off; content.addSubview(follow)
        let trailLabel = NSTextField(labelWithString: "十字指针轨迹")
        trailLabel.frame = NSRect(x: 28, y: 151, width: 140, height: 20); content.addSubview(trailLabel)
        let trail = NSSwitch(frame: NSRect(x: 343, y: 145, width: 42, height: 26))
        trail.state = preferences.cursorTrail ? .on : .off
        trail.target = self; trail.action = #selector(changeCursorTrail(_:)); trail.setAccessibilityLabel("Crosshair trail")
        content.addSubview(trail)
        let reset = NSButton(title: "恢复默认色板", target: self, action: #selector(resetColors(_:)))
        reset.bezelStyle = .rounded; reset.frame = NSRect(x: 22, y: 81, width: 160, height: 30); content.addSubview(reset)
        let help = NSTextField(wrappingLabelWithString: "移动指针后打字，即可在新位置输入。\n右键文字精修，拖动边框四角改字号，⌥ 拖动临时擦除。\n颜色、尺寸与窗口偏好会自动记住。")
        help.font = .systemFont(ofSize: 11); help.textColor = .secondaryLabelColor
        help.frame = NSRect(x: 28, y: 10, width: 360, height: 56); content.addSubview(help)
        for control in content.subviews where control !== reset && control !== help {
            control.frame.origin.y += 50
        }
        let animationLabel = NSTextField(labelWithString: "工具栏折叠动画")
        animationLabel.frame = NSRect(x: 28, y: 151, width: 150, height: 20); content.addSubview(animationLabel)
        let animation = NSPopUpButton(frame: NSRect(x: 196, y: 146, width: 190, height: 28))
        for style in ToolbarAnimationStyle.allCases {
            animation.addItem(withTitle: style.label)
            animation.lastItem?.representedObject = style.rawValue
        }
        animation.selectItem(at: ToolbarAnimationStyle.allCases.firstIndex(of: preferences.toolbarAnimationStyle) ?? 0)
        animation.target = self; animation.action = #selector(changeToolbarAnimation(_:))
        animation.setAccessibilityLabel("工具栏折叠动画"); content.addSubview(animation)
        let loginLabel = NSTextField(labelWithString: "开机自启动")
        loginLabel.frame = NSRect(x: 28, y: 480, width: 150, height: 20); content.addSubview(loginLabel)
        let loginSwitch = NSSwitch(frame: NSRect(x: 343, y: 474, width: 42, height: 26))
        loginSwitch.target = self; loginSwitch.action = #selector(changeLoginLaunch(_:))
        loginSwitch.setAccessibilityLabel("开机自启动（静默）")
        content.addSubview(loginSwitch); loginLaunchSwitch = loginSwitch
        let loginHint = NSTextField(labelWithString: "")
        loginHint.font = .systemFont(ofSize: 11); loginHint.textColor = .secondaryLabelColor
        loginHint.frame = NSRect(x: 28, y: 454, width: 360, height: 18)
        content.addSubview(loginHint); loginLaunchHint = loginHint
        refreshLoginLaunchControls()
        return panel
    }
    func applicationDidBecomeActive(_ notification: Notification) { refreshLoginLaunchControls() }

    func refreshLoginLaunchControls() {
        loginLaunchSwitch?.state = loginLaunch.isEnabled || loginLaunch.needsApproval ? .on : .off
        loginLaunchHint?.stringValue = loginLaunch.needsApproval
            ? "请在系统“登录项”中允许，或关闭此开关取消"
            : "登录后静默运行，不弹窗口；用快捷键或菜单栏呼出"
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
    @objc func changeResizeDefault(_ sender: NSButton) { preferences.resizeUpdatesDefaultFont = sender.state == .on }
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
        alert("Inkey", "直接打字，拖动绘画。\n单击当前文字：移动光标\n右键文字／⌘Return：完整编辑，可拖选\nShift＋拖动：当前形状　⇧1—4：切换形状\n⌘＋单击／拖动：选择／移动\n⌥＋拖动：临时擦除　⌥⌘E：切换橡皮\n右键橡皮：调节尺寸　⌥⌘[ / ]：缩小／放大橡皮\nEnter：提交　Shift＋Enter：换行\n⌥1—6：换色　⇧⌘C：调色盘\n⌥⌘T：折叠工具栏　⇧⌘T：显示／隐藏\n双指滚动：平移　捏合：缩放\n⌘0：适配内容\n⇧⌘P：常驻　⌃⌘F：全屏\n⌘O：导入　⌘S：保存　⇧⌘S：另存为\n⌘E：导出\nEsc：结束编辑／取消选择／收起\n偏好自动保存，重启后恢复。")
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
