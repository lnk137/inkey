import AppKit
import Carbon.HIToolbox
import UniformTypeIdentifiers
import PDFKit

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
    var onRecord: ((UInt32, UInt32, String) -> Bool)?
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) {
        recording = true; title = "按下快捷键…"; window?.makeFirstResponder(self)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { recording = false; title = UserDefaults.standard.string(forKey: "shortcutLabel") ?? "⌃⌥Space"; return }
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
        if onRecord?(UInt32(event.keyCode), modifiers, label) == true { recording = false; title = label }
    }
}

@main
final class InkeyApp: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: InkeyWindow!
    let canvas = CanvasView(frame: .zero)
    let palette = PaletteView(frame: NSRect(x: 0, y: 0, width: 280, height: 44))
    let store = DraftStore()
    let hotkey = HotKey()
    var statusItem: NSStatusItem!
    var previousApp: NSRunningApplication?
    var settings: NSWindow?
    var keyMonitor: Any?
    var pinned = false
    var suppressAutoHide = false
    var fileURL: URL?
    var statusLabel: NSTextField!
    var errorShown = false
    var fullScreen = false

    static func main() {
        let application = NSApplication.shared
        let delegate = InkeyApp()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
        _ = delegate
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        buildWindow()
        buildStatusItem()
        hotkey.onTrigger = { [weak self] in self?.toggleWindow() }
        if !ProcessInfo.processInfo.arguments.contains("--smoke-test") && !registerSavedHotkey() {
            showWindow()
            alert("快捷键已被占用", "请在设置中重新录制呼出快捷键。")
            showSettings(nil)
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, !self.canvas.isDrawing else { return event }
            if self.palette.popover != nil && event.keyCode == 53 { self.palette.closePicker(accept: false); return nil }
            guard self.window.isKeyWindow else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if modifiers == [.option], let char = event.charactersIgnoringModifiers, let number = Int(char), (1...6).contains(number) {
                self.palette.choose(number - 1); return nil
            }
            return event
        }
        let restored = UserDefaults.standard.string(forKey: "currentDraft").flatMap { id in store.recent().first { $0.1.id.uuidString == id }?.1 } ?? store.recent().first?.1
        if let restored { canvas.install(restored) }
        else { canvas.draft.background = isDark ? InkColor("202322") : InkColor("FAF9F6") }
        syncPaletteToPaper()
        if ProcessInfo.processInfo.arguments.contains("--ui-test") { togglePinned(nil) }
        showWindow()
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
        window.center(); window.setFrameAutosaveName("InkeyWindow")
        guard let content = window.contentView else { return }
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
        layoutPalette(initial: true)
        window.onResize = { [weak self] in self?.layoutPalette(initial: false) }
        canvas.onChange = { [weak self] in self?.saveAutomatically() }
        canvas.onEscape = { [weak self] in self?.hideWindow() }
        canvas.onInteraction = { [weak self] in self?.palette.closePicker(accept: true) }
        palette.onColor = { [weak self] color in self?.canvas.applyColor(color) }
        palette.onBeginPreview = { [weak self] in self?.canvas.beginColorPreview() }
        palette.onEndPreview = { [weak self] accept, original in self?.canvas.finishColorPreview(accept: accept, original: original) }
        palette.onRestoreFocus = { [weak self] in self?.canvas.restoreFocus() }
        canvas.ink = palette.current
    }

    func layoutPalette(initial: Bool) {
        guard let content = window?.contentView else { return }
        if initial {
            let position = UserDefaults.standard.array(forKey: "palettePosition") as? [Double]
            palette.setFrameOrigin(NSPoint(x: position?.first ?? (content.bounds.width - 280) / 2, y: position?.last ?? 18))
        }
        palette.setFrameOrigin(NSPoint(x: min(max(8, palette.frame.minX), content.bounds.width - 288), y: min(max(8, palette.frame.minY), content.bounds.height - 90)))
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
        add("自定义颜色…", #selector(pickColor(_:)), "c", modifiers: [.command, .shift], to: view)
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
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
        if !window.isVisible, let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }), !screen.frame.intersects(window.frame) {
            let area = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: area.midX - window.frame.width / 2, y: area.midY - window.frame.height / 2))
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil); canvas.restoreFocus()
    }
    func hideWindow() {
        palette.closePicker(accept: true); canvas.flush(); window.orderOut(nil)
        previousApp?.activate()
    }
    func toggleWindow() { if window.isVisible && window.isKeyWindow { hideWindow() } else { showWindow() } }
    @objc func toggleAction(_ sender: Any?) { toggleWindow() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { hideWindow(); return false }
    func windowDidResignKey(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.pinned, !self.suppressAutoHide, self.palette.popover == nil,
                  self.window.attachedSheet == nil, !self.window.isKeyWindow,
                  self.settings?.isVisible != true, !self.fullScreen else { return }
            self.canvas.flush(); self.window.orderOut(nil)
        }
    }
    func windowWillEnterFullScreen(_ notification: Notification) { fullScreen = true; window.level = .normal }
    func windowDidExitFullScreen(_ notification: Notification) { fullScreen = false; window.level = pinned ? .floating : .normal }
    @objc func togglePinned(_ sender: Any?) {
        pinned.toggle(); if !fullScreen { window.level = pinned ? .floating : .normal }
        statusLabel.stringValue = pinned ? "\(canvas.draft.name) · 常驻" : canvas.draft.name
        if let item = sender as? NSMenuItem { item.state = pinned ? .on : .off }
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

    @objc func showMore(_ sender: NSButton) {
        let menu = NSMenu()
        add("新建草稿", #selector(newDraft(_:)), "n", to: menu)
        add("最近草稿…", #selector(showRecent(_:)), "", to: menu)
        menu.addItem(.separator())
        let pin = add("置顶常驻", #selector(togglePinned(_:)), "p", modifiers: [.command, .shift], to: menu); pin.state = pinned ? .on : .off
        add("进入／退出全屏", #selector(toggleFullScreen(_:)), "f", modifiers: [.command, .control], to: menu)
        add("适配全部内容", #selector(fit(_:)), "0", to: menu)
        menu.addItem(.separator())
        add("打开或导入…", #selector(openDraft(_:)), "o", to: menu)
        add("保存…", #selector(saveDraft(_:)), "s", to: menu)
        add("另存为…", #selector(saveAs(_:)), "s", modifiers: [.command, .shift], to: menu)
        add("导出…", #selector(exportDraft(_:)), "e", to: menu)
        menu.addItem(.separator()); add("设置…", #selector(showSettings(_:)), ",", to: menu)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: sender)
    }

    @objc func showSettings(_ sender: Any?) {
        palette.closePicker(accept: true); canvas.commitText()
        if let settings { NSApp.activate(ignoringOtherApps: true); settings.makeKeyAndOrderFront(nil); return }
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 254), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Inkey 设置"; panel.isReleasedWhenClosed = false; panel.center()
        guard let content = panel.contentView else { return }
        let label = NSTextField(labelWithString: "呼出草稿")
        label.frame = NSRect(x: 28, y: 198, width: 140, height: 20); content.addSubview(label)
        let recorder = ShortcutRecorder(title: UserDefaults.standard.string(forKey: "shortcutLabel") ?? "⌃⌥Space", target: nil, action: nil)
        recorder.bezelStyle = .rounded; recorder.frame = NSRect(x: 196, y: 192, width: 190, height: 32)
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
        content.addSubview(recorder)
        let placementLabel = NSTextField(labelWithString: "文字落点")
        placementLabel.frame = NSRect(x: 28, y: 145, width: 140, height: 20); content.addSubview(placementLabel)
        let placement = NSPopUpButton(frame: NSRect(x: 196, y: 140, width: 190, height: 28))
        placement.addItems(withTitles: ["单击定位", "跟随指针"])
        placement.selectItem(at: UserDefaults.standard.bool(forKey: "pointerPlacement") ? 1 : 0)
        placement.target = self; placement.action = #selector(changePlacement(_:)); content.addSubview(placement)
        let reset = NSButton(title: "恢复默认色板", target: self, action: #selector(resetColors(_:)))
        reset.bezelStyle = .rounded; reset.frame = NSRect(x: 22, y: 81, width: 160, height: 30); content.addSubview(reset)
        let help = NSTextField(wrappingLabelWithString: "按住 Shift 拖出箭头。⌥1—6 快速换色。\n内容自动保存在本机，关闭窗口不会丢失草稿。")
        help.font = .systemFont(ofSize: 11); help.textColor = .secondaryLabelColor
        help.frame = NSRect(x: 28, y: 20, width: 360, height: 42); content.addSubview(help)
        settings = panel; NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil)
    }
    @objc func changePlacement(_ sender: NSPopUpButton) { UserDefaults.standard.set(sender.indexOfSelectedItem == 1, forKey: "pointerPlacement") }
    @objc func resetColors(_ sender: Any?) { palette.resetPresets() }
    @objc func help(_ sender: Any?) {
        alert("Inkey", "直接打字，拖动绘画。\nShift＋拖动：箭头\n⌘＋单击／拖动：选择／移动\n双击文字：编辑\nEnter：提交　Shift＋Enter：换行\n⌥1—6：换色　⇧⌘C：调色盘\n双指滚动：平移　捏合：缩放\n⌘0：适配内容\n⇧⌘P：常驻　⌃⌘F：全屏\n⌘O：导入　⌘S：保存　⌘E：导出\nEsc：结束编辑／取消选择／收起")
    }
    @objc func about(_ sender: Any?) { NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Inkey", .applicationVersion: "0.1.0", .credits: NSAttributedString(string: "A quiet place to think.")]) }
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
