import AppKit

private final class ShortcutDocumentView: NSView {
    override var isFlipped: Bool { true }
}

final class ShortcutSettingsView: NSView, NSSearchFieldDelegate {
    let searchField = NSSearchField()
    let message = NSTextField(wrappingLabelWithString: localized("仅“呼出／收起”为全局快捷键，其余在 Inkey 内使用。", "Show/hide and Screen Draft are global shortcuts; the others work within Inkey."))
    private let scroll = NSScrollView()
    private let document = ShortcutDocumentView()
    private let list = NSStackView()
    private var groups: [(String, [(ShortcutAction, NSView)])] = []
    var onResetAll: (() -> Void)?
    private var query = ""
    let temporaryEraserPicker = NSPopUpButton()
    private let modifierHint = NSTextField(wrappingLabelWithString: "")
    private let preferences: UserPreferences
    private var modifierSection: NSView!
    var onModifierChange: (() -> Void)?

    init(preferences: UserPreferences, makeRecorder: (ShortcutAction) -> ShortcutRecorder, title: (ShortcutAction) -> String) {
        self.preferences = preferences
        super.init(frame: .zero)
        temporaryEraserPicker.widthAnchor.constraint(equalToConstant: 156).isActive = true
        temporaryEraserPicker.addItems(withTitles: TemporaryEraserModifier.allCases.map(\.label))
        temporaryEraserPicker.selectItem(at: preferences.temporaryEraserModifier == .option ? 0 : 1)
        temporaryEraserPicker.target = self; temporaryEraserPicker.action = #selector(changeTemporaryEraser(_:))
        temporaryEraserPicker.setAccessibilityLabel(localized("临时橡皮修饰键", "Temporary eraser modifier"))
        updateModifierHint()
        modifierSection = SettingsLayout.section(localized("修饰键", "Modifiers"), rows: [SettingsLayout.row(localized("临时橡皮", "Temporary eraser"), detail: modifierHint, control: temporaryEraserPicker)])
        searchField.placeholderString = localized("搜索操作或分组", "Search actions or groups"); searchField.delegate = self
        searchField.setAccessibilityLabel(localized("搜索快捷键", "Search shortcuts"))
        let instructions = NSTextField(labelWithString: localized("点击录制 · Delete 清除 · Esc 取消 · 右键恢复此项默认", "Click to record · Delete to clear · Esc to cancel · Right-click to restore default"))
        instructions.font = .systemFont(ofSize: 11); instructions.textColor = .secondaryLabelColor
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.drawsBackground = false; scroll.borderType = .noBorder
        document.frame = NSRect(x: 0, y: 0, width: 472, height: 600)
        scroll.documentView = document
        list.orientation = .vertical; list.alignment = .leading; list.spacing = 16
        list.translatesAutoresizingMaskIntoConstraints = false; document.addSubview(list)
        NSLayoutConstraint.activate([
            list.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -8),
            list.topAnchor.constraint(equalTo: document.topAnchor, constant: 4)
        ])
        for (name, actions) in ShortcutAction.groups {
            groups.append((name, actions.map { action in
                let recorder = makeRecorder(action)
                let detail = action == .toggleWindow ? NSTextField(wrappingLabelWithString: localized("在其他应用中也可呼出", "Available from other apps")) : nil
                return (action, SettingsLayout.row(title(action), detail: detail, control: recorder))
            }))
        }
        message.font = .systemFont(ofSize: 11); message.textColor = .secondaryLabelColor
        let reset = NSButton(title: localized("恢复全部默认", "Restore All Defaults"), target: self, action: #selector(resetAll))
        reset.bezelStyle = .rounded
        for view in [searchField, instructions, scroll, message, reset] {
            view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view)
        }
        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            searchField.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            searchField.heightAnchor.constraint(equalToConstant: 28),
            instructions.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
            instructions.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 9),
            scroll.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: searchField.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: instructions.bottomAnchor, constant: 12),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -68),
            message.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
            message.trailingAnchor.constraint(equalTo: reset.leadingAnchor, constant: -12),
            message.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 12),
            message.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -14),
            reset.trailingAnchor.constraint(equalTo: searchField.trailingAnchor),
            reset.centerYAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 27)
        ])
        rebuild()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func resetAll() { onResetAll?() }
    @objc func changeTemporaryEraser(_ sender: NSPopUpButton) {
        guard TemporaryEraserModifier.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
        preferences.temporaryEraserModifier = TemporaryEraserModifier.allCases[sender.indexOfSelectedItem]
        updateModifierHint(); rebuild(); onModifierChange?()
        showMessage(localized("临时橡皮已设为 \(preferences.temporaryEraserModifier.label)，松开恢复原工具。", "Temporary eraser set to \(preferences.temporaryEraserModifier.label). Release to restore the previous tool."))
    }
    private func updateModifierHint() {
        let modifier = preferences.temporaryEraserModifier
        modifierHint.stringValue = localized("按住 \(modifier.symbol) 擦除，松开恢复；\(modifier.moveSymbol) 拖动选择／移动", "Hold \(modifier.symbol) to erase; release to restore. \(modifier.moveSymbol)-drag to select or move.")
    }
    func controlTextDidChange(_ obj: Notification) {
        query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        rebuild()
    }
    private func rebuild() {
        for view in list.arrangedSubviews { list.removeArrangedSubview(view); view.removeFromSuperview() }
        var found = false
        if query.isEmpty || localized("修饰键 临时橡皮 选择 移动 Option Command", "Modifiers Temporary eraser Select Move Option Command").localizedCaseInsensitiveContains(query) {
            found = true; list.addArrangedSubview(modifierSection)
            modifierSection.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
        }
        for (name, entries) in groups {
            let rows = entries.filter { query.isEmpty || name.localizedCaseInsensitiveContains(query) || $0.0.title.localizedCaseInsensitiveContains(query) }.map(\.1)
            guard !rows.isEmpty else { continue }
            found = true
            let group = SettingsLayout.section(name, rows: rows)
            list.addArrangedSubview(group); group.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
        }
        if !found {
            let empty = NSTextField(labelWithString: localized("没有匹配的操作", "No matching actions"))
            empty.textColor = .secondaryLabelColor; list.addArrangedSubview(empty)
        } else if query.isEmpty {
            let fixed = NSTextField(wrappingLabelWithString: localized("固定操作：Enter 提交，Shift＋Enter 换行，Esc 取消／收起。Shift 拖动绘制形状；双指平移、捏合缩放。临时擦除修饰键可在本页设置。", "Fixed controls: Enter commits, Shift+Enter inserts a line, and Esc cancels or closes. Shift-drag draws shapes; pan with two fingers and pinch to zoom. Configure the temporary eraser modifier here."))
            fixed.font = .systemFont(ofSize: 11); fixed.textColor = .secondaryLabelColor
            list.addArrangedSubview(fixed); fixed.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
        }
        needsLayout = true
        scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView)
    }
    override func layout() {
        super.layout()
        document.setFrameSize(NSSize(width: max(300, scroll.contentSize.width), height: document.frame.height))
        document.layoutSubtreeIfNeeded()
        document.setFrameSize(NSSize(width: document.frame.width, height: max(scroll.contentSize.height, list.fittingSize.height + 8)))
        document.layoutSubtreeIfNeeded()
    }
    func showMessage(_ text: String, error: Bool = false) {
        message.stringValue = text; message.textColor = error ? .systemRed : .secondaryLabelColor
    }
}

extension InkeyApp {
    func installShortcutSettings(in panel: NSWindow) {
        let general = panel.contentView!
        generalSettingsView = general
        let root = NSView(); panel.contentView = root
        let tabs = NSSegmentedControl(labels: [localized("常规", "General"), localized("快捷键", "Shortcuts")], trackingMode: .selectOne, target: self, action: #selector(changeSettingsTab(_:)))
        tabs.selectedSegment = 0; tabs.setAccessibilityLabel(localized("设置分类", "Settings category")); settingsTab = tabs
        let language = NSPopUpButton()
        language.addItems(withTitles: ["简体中文", "English"])
        language.selectItem(at: InterfaceLanguage.selected(in: preferences.defaults) == .english ? 1 : 0)
        language.target = self; language.action = #selector(changeInterfaceLanguage(_:))
        language.setAccessibilityLabel(localized("语言", "Language"))
        language.toolTip = localized("重启应用后生效", "Restart Inkey to apply")
        let page = ShortcutSettingsView(preferences: preferences, makeRecorder: { self.makeShortcutRecorder(for: $0) }, title: { $0.title })
        page.onModifierChange = { [weak self] in self?.canvas.resetTemporaryEraser() }
        page.onResetAll = { [weak self] in self?.resetAllShortcuts() }
        shortcutPage = page; shortcutsSettingsView = page; page.isHidden = true
        for view in [tabs, language, general, page] { view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view) }
        NSLayoutConstraint.activate([
            language.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            language.centerYAnchor.constraint(equalTo: tabs.centerYAnchor),
            tabs.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            tabs.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            tabs.widthAnchor.constraint(equalToConstant: 224),
            general.topAnchor.constraint(equalTo: root.topAnchor, constant: 48),
            general.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            general.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            general.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            page.topAnchor.constraint(equalTo: general.topAnchor), page.leadingAnchor.constraint(equalTo: general.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: general.trailingAnchor), page.bottomAnchor.constraint(equalTo: general.bottomAnchor)
        ])
        panel.setContentSize(NSSize(width: 520, height: general.bounds.height + 48))
        root.layoutSubtreeIfNeeded(); panel.center()
    }
    @objc func changeSettingsTab(_ sender: NSSegmentedControl) {
        shortcutRecorders.values.flatMap { $0 }.forEach { $0.finishRecording() }
        generalSettingsView?.isHidden = sender.selectedSegment != 0
        shortcutsSettingsView?.isHidden = sender.selectedSegment != 1
        sender.window?.makeFirstResponder(sender.selectedSegment == 1 ? shortcutPage?.searchField : sender)
    }
    func makeShortcutRecorder(for action: ShortcutAction) -> ShortcutRecorder {
        let recorder = ShortcutRecorder(title: shortcuts.label(for: action), target: nil, action: nil)
        recorder.savedLabel = recorder.title; recorder.bezelStyle = .rounded
        recorder.widthAnchor.constraint(equalToConstant: 156).isActive = true
        recorder.setAccessibilityLabel(action.title)
        recorder.toolTip = localized("点击录制；Delete 清除；Esc 取消；右键恢复默认", "Click to record; Delete clears; Esc cancels; right-click restores default")
        recorder.allowsShiftNumbers = ShortcutAction.shapes.contains(action)
        recorder.target = recorder; recorder.action = #selector(ShortcutRecorder.beginRecording)
        recorder.onBegin = { [weak self, weak recorder] in
            self?.shortcutRecorders.values.flatMap { $0 }.filter { $0 !== recorder }.forEach { $0.finishRecording() }
        }
        recorder.onChange = { [weak self] binding in self?.updateShortcut(action, binding: binding) ?? false }
        recorder.onReset = { [weak self] in _ = self?.updateShortcut(action, binding: action.defaultBinding) }
        shortcutRecorders[action, default: []].append(recorder)
        return recorder
    }
    @discardableResult
    func updateShortcut(_ action: ShortcutAction, binding: KeyBinding?) -> Bool {
        if let binding, let error = shortcuts.validationMessage(binding, for: action) { shortcutError(error); return false }
        if action.isGlobal {
            let hotkey = globalHotkey(for: action)
            if let binding {
                guard hotkey.register(keyCode: UInt32(binding.keyCode), modifiers: binding.modifiers) else {
                    hotkeyNeedsAttention = !registerSavedHotkey(for: action)
                    shortcutError(hotkeyNeedsAttention ? localized("该组合不可用，原快捷键也无法注册，请另选组合。", "This shortcut and the previous one are unavailable. Choose another.") : localized("该全局快捷键已被占用，已保留原设置。", "This global shortcut is in use; the previous setting was preserved."))
                    return false
                }
            } else { hotkey.unregister() }
            hotkeyNeedsAttention = false
        }
        shortcuts.set(binding, for: action)
        refreshShortcutUI()
        shortcutPage?.showMessage(localized("已保存“\(action.title)”", "Saved “\(action.title)”") + (binding == nil ? localized("，可通过菜单操作。", "; available from the menu.") : "。"))
        return true
    }
    private func shortcutError(_ message: String) {
        if shortcutsSettingsView?.isHidden == false { shortcutPage?.showMessage(message, error: true); NSSound.beep() }
        else { alert(localized("快捷键不可用", "Shortcut Unavailable"), message) }
    }
    func resetAllShortcuts() {
        for action in ShortcutAction.allCases.filter(\.isGlobal) { globalHotkey(for: action).unregister() }
        for action in ShortcutAction.allCases.filter(\.isGlobal) {
            let binding = action.defaultBinding
            guard globalHotkey(for: action).register(keyCode: UInt32(binding.keyCode), modifiers: binding.modifiers) else {
                hotkeyNeedsAttention = !registerSavedHotkeys()
                shortcutError(localized("默认全局快捷键已被占用，未恢复设置。", "A default global shortcut is in use; settings were not restored."))
                return
            }
        }
        shortcuts.resetAll(); hotkeyNeedsAttention = false
        refreshShortcutUI(); shortcutPage?.showMessage(localized("已恢复全部默认快捷键。", "All default shortcuts restored."))
    }
    func refreshShortcutUI() {
        for (action, recorders) in shortcutRecorders {
            for recorder in recorders { recorder.savedLabel = shortcuts.label(for: action); recorder.finishRecording() }
        }
        statusItem?.button?.toolTip = "Inkey · \(shortcuts.label(for: .toggleWindow))"
        func update(_ menu: NSMenu) {
            for item in menu.items {
                if let selector = item.action, let action = ShortcutAction.allCases.first(where: { $0.selectorName == NSStringFromSelector(selector) }), !action.isGlobal { applyShortcut(action, to: item) }
                if let submenu = item.submenu { update(submenu) }
            }
        }
        if let menu = NSApp.mainMenu { update(menu) }
        if let menu = statusItem?.menu { update(menu) }
        palette.refreshShortcutHints()
    }
    func applyShortcut(_ action: ShortcutAction, to item: NSMenuItem) {
        let binding = shortcuts.binding(for: action)
        item.keyEquivalent = binding?.key ?? ""
        item.keyEquivalentModifierMask = binding?.flags ?? []
    }
    @discardableResult
    func handleConfiguredShortcut(_ event: NSEvent) -> Bool {
        if shortcuts.binding(for: .highContrast)?.matches(event) == true { toggleHighContrast(nil); return true }
        guard !canvas.isDrawing, let action = ShortcutAction.allCases.first(where: { !$0.isGlobal && shortcuts.binding(for: $0)?.matches(event) == true }) else { return false }
        if let index = ShortcutAction.shapes.firstIndex(of: action) {
            guard !palette.hasPopover, (window.firstResponder as? NSTextView)?.hasMarkedText() != true else { return false }
            palette.chooseShape(preferences.shapeOrder[index]); return true
        }
        if let index = ShortcutAction.colors.firstIndex(of: action) {
            guard (window.firstResponder as? NSTextView)?.hasMarkedText() != true else { return false }
            palette.choose(index); return true
        }
        guard let selector = action.selectorName else { return false }
        NSApp.sendAction(Selector(selector), to: action.isResponderAction ? nil : self, from: self)
        return true
    }
}
