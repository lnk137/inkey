import AppKit

private final class ShortcutDocumentView: NSView {
    override var isFlipped: Bool { true }
}

final class ShortcutSettingsView: NSView, NSSearchFieldDelegate {
    let searchField = NSSearchField()
    let message = NSTextField(wrappingLabelWithString: localized("ui.show_hide_and_screen_draft_are_global_shortcuts_the_others_work_within"))
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
        temporaryEraserPicker.setAccessibilityLabel(localized("ui.temporary_eraser_modifier"))
        updateModifierHint()
        modifierSection = SettingsLayout.section(localized("ui.modifiers"), rows: [SettingsLayout.row(localized("ui.temporary_eraser"), detail: modifierHint, control: temporaryEraserPicker)])
        searchField.placeholderString = localized("ui.search_actions_or_groups"); searchField.delegate = self
        searchField.setAccessibilityLabel(localized("ui.search_shortcuts"))
        let instructions = NSTextField(labelWithString: localized("ui.click_to_record_delete_to_clear_esc_to_cancel_right_click_to_restore_d"))
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
                let detail = action == .toggleWindow ? NSTextField(wrappingLabelWithString: localized("ui.available_from_other_apps")) : nil
                return (action, SettingsLayout.row(title(action), detail: detail, control: recorder))
            }))
        }
        message.font = .systemFont(ofSize: 11); message.textColor = .secondaryLabelColor
        let reset = NSButton(title: localized("ui.restore_all_defaults"), target: self, action: #selector(resetAll))
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
        showMessage(localized("ui.temporary_eraser_set_to_value_release_to_restore_the_previous_tool", arguments: [String(describing: preferences.temporaryEraserModifier.label)]))
    }
    private func updateModifierHint() {
        let modifier = preferences.temporaryEraserModifier
        modifierHint.stringValue = localized("ui.hold_value_to_erase_release_to_restore_value_drag_to_select_or_move", arguments: [String(describing: modifier.symbol), String(describing: modifier.moveSymbol)])
    }
    func controlTextDidChange(_ obj: Notification) {
        query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        rebuild()
    }
    private func rebuild() {
        for view in list.arrangedSubviews { list.removeArrangedSubview(view); view.removeFromSuperview() }
        var found = false
        if query.isEmpty || localized("ui.modifiers_temporary_eraser_select_move_option_command").localizedCaseInsensitiveContains(query) {
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
            let empty = NSTextField(labelWithString: localized("ui.no_matching_actions"))
            empty.textColor = .secondaryLabelColor; list.addArrangedSubview(empty)
        } else if query.isEmpty {
            let fixed = NSTextField(wrappingLabelWithString: localized("ui.fixed_controls_enter_commits_shift_enter_inserts_a_line_and_esc_cancel"))
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
        let tabs = NSSegmentedControl(labels: [localized("ui.general"), localized("ui.shortcuts")], trackingMode: .selectOne, target: self, action: #selector(changeSettingsTab(_:)))
        tabs.selectedSegment = 0; tabs.setAccessibilityLabel(localized("ui.settings_category")); settingsTab = tabs
        let language = NSPopUpButton()
        language.addItems(withTitles: InterfaceLanguage.allCases.map(\.displayName))
        language.selectItem(at: InterfaceLanguage.allCases.firstIndex(of: InterfaceLanguage.selected(in: preferences.defaults)) ?? 0)
        language.target = self; language.action = #selector(changeInterfaceLanguage(_:))
        language.setAccessibilityLabel(localized("ui.language"))
        language.toolTip = localized("ui.restart_inkey_to_apply")
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
        recorder.toolTip = localized("ui.click_to_record_delete_clears_esc_cancels_right_click_restores_default")
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
                    shortcutError(hotkeyNeedsAttention ? localized("ui.this_shortcut_and_the_previous_one_are_unavailable_choose_another") : localized("ui.this_global_shortcut_is_in_use_the_previous_setting_was_preserved"))
                    return false
                }
            } else { hotkey.unregister() }
            hotkeyNeedsAttention = false
        }
        shortcuts.set(binding, for: action)
        refreshShortcutUI()
        shortcutPage?.showMessage(localized(binding == nil ? "ui.saved_action_menu_available" : "ui.saved_action", arguments: [action.title]))
        return true
    }
    private func shortcutError(_ message: String) {
        if shortcutsSettingsView?.isHidden == false { shortcutPage?.showMessage(message, error: true); NSSound.beep() }
        else { alert(localized("ui.shortcut_unavailable"), message) }
    }
    func resetAllShortcuts() {
        for action in ShortcutAction.allCases.filter(\.isGlobal) { globalHotkey(for: action).unregister() }
        for action in ShortcutAction.allCases.filter(\.isGlobal) {
            let binding = action.defaultBinding
            guard globalHotkey(for: action).register(keyCode: UInt32(binding.keyCode), modifiers: binding.modifiers) else {
                hotkeyNeedsAttention = !registerSavedHotkeys()
                shortcutError(localized("ui.a_default_global_shortcut_is_in_use_settings_were_not_restored"))
                return
            }
        }
        shortcuts.resetAll(); hotkeyNeedsAttention = false
        refreshShortcutUI(); shortcutPage?.showMessage(localized("ui.all_default_shortcuts_restored"))
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
