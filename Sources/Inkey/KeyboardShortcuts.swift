import AppKit
import Carbon.HIToolbox

struct KeyBinding: Codable, Equatable {
    let keyCode: UInt16
    let modifiers: UInt32
    let key: String

    init(_ keyCode: UInt16, _ flags: NSEvent.ModifierFlags, _ key: String) {
        self.keyCode = keyCode; self.modifiers = Self.carbonFlags(flags); self.key = key
    }
    init(event: NSEvent) {
        self.init(event.keyCode, event.modifierFlags, Self.keyNames[event.keyCode] ?? event.characters(byApplyingModifiers: [])?.lowercased() ?? "")
    }
    var flags: NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        for (carbon, cocoa) in [(controlKey, NSEvent.ModifierFlags.control), (optionKey, .option), (shiftKey, .shift), (cmdKey, .command)] {
            if modifiers & UInt32(carbon) != 0 { result.insert(cocoa) }
        }
        return result
    }
    static func carbonFlags(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        for (cocoa, carbon) in [(NSEvent.ModifierFlags.control, controlKey), (.option, optionKey), (.shift, shiftKey), (.command, cmdKey)] {
            if flags.contains(cocoa) { value |= UInt32(carbon) }
        }
        return value
    }
    var label: String {
        var label = ""
        for (flag, symbol) in [(NSEvent.ModifierFlags.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")] {
            if flags.contains(flag) { label += symbol }
        }
        let names: [UInt16: String] = [49: "Space", 36: "Return", 48: "Tab", 51: "⌫", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑"]
        if let scalar = key.unicodeScalars.first, isFunctionKey {
            return label + "F\(scalar.value - 0xF704 + 1)"
        }
        return label + (names[keyCode] ?? key.uppercased())
    }
    var isFunctionKey: Bool {
        key.unicodeScalars.count == 1 && key.unicodeScalars.first.map { (0xF704...0xF726).contains($0.value) } == true
    }
    func matches(_ event: NSEvent) -> Bool {
        keyCode == event.keyCode && modifiers == Self.carbonFlags(event.modifierFlags)
    }
    func sameCombination(as other: KeyBinding) -> Bool { keyCode == other.keyCode && modifiers == other.modifiers }
    static let keyNames: [UInt16: String] = [
        0:"a", 1:"s", 2:"d", 3:"f", 4:"h", 5:"g", 6:"z", 7:"x", 8:"c", 9:"v", 11:"b", 12:"q", 13:"w", 14:"e", 15:"r", 16:"y", 17:"t",
        18:"1", 19:"2", 20:"3", 21:"4", 22:"6", 23:"5", 24:"=", 25:"9", 26:"7", 27:"-", 28:"8", 29:"0", 30:"]", 31:"o", 32:"u", 33:"[", 34:"i", 35:"p", 36:"\r", 37:"l", 38:"j", 39:"'", 40:"k", 41:";", 42:"\\", 43:",", 44:"/", 45:"n", 46:"m", 47:".", 48:"\t", 49:" ", 50:"`", 51:"\u{08}", 117:"\u{7f}",
        123:"\u{F702}", 124:"\u{F703}", 125:"\u{F701}", 126:"\u{F700}",
        122:"\u{F704}", 120:"\u{F705}", 99:"\u{F706}", 118:"\u{F707}", 96:"\u{F708}", 97:"\u{F709}", 98:"\u{F70A}", 100:"\u{F70B}", 101:"\u{F70C}", 109:"\u{F70D}", 103:"\u{F70E}", 111:"\u{F70F}"
    ]
}

enum ShortcutAction: String, CaseIterable, Codable {
    case toggleWindow, screenDraft, newDraft, open, recent, save, saveAs, export
    case undo, redo, cut, copy, paste, selectAll
    case fit, preciseEdit, eraser, smallerEraser, largerEraser, colorPicker
    case collapseToolbar, hideToolbar, pin, fullScreen
    case shape1, shape2, shape3, shape4
    case color1, color2, color3, color4, color5, color6
    case settings, quit

    static let shapes: [Self] = [.shape1, .shape2, .shape3, .shape4]
    static let colors: [Self] = [.color1, .color2, .color3, .color4, .color5, .color6]
    static let groups: [(String, [Self])] = [
        ("全局", [.toggleWindow, .screenDraft]), ("文件", [.newDraft, .open, .recent, .save, .saveAs, .export]),
        ("编辑", [.undo, .redo, .cut, .copy, .paste, .selectAll]),
        ("画布与工具", [.fit, .preciseEdit, .eraser, .smallerEraser, .largerEraser, .colorPicker]),
        ("工具栏与窗口", [.collapseToolbar, .hideToolbar, .pin, .fullScreen]),
        ("形状位置 · 从左到右", shapes), ("预设颜色位置 · 从左到右", colors), ("应用", [.settings, .quit])
    ]
    var title: String {
        if self == .screenDraft { return "进入／退出屏幕草稿" }
        if let index = Self.shapes.firstIndex(of: self) { return "形状位置 \(index + 1)" }
        if let index = Self.colors.firstIndex(of: self) { return "预设颜色 \(index + 1)" }
        return [Self.toggleWindow:"呼出／收起 Inkey", .newDraft:"新建草稿", .open:"打开或导入", .recent:"最近草稿", .save:"保存", .saveAs:"另存为", .export:"导出", .undo:"撤销", .redo:"重做", .cut:"剪切", .copy:"复制", .paste:"粘贴", .selectAll:"全选", .fit:"适配全部内容", .preciseEdit:"完整编辑文字", .eraser:"切换橡皮擦", .smallerEraser:"缩小橡皮擦", .largerEraser:"放大橡皮擦", .colorPicker:"自定义颜色", .collapseToolbar:"折叠／展开工具栏", .hideToolbar:"显示／隐藏工具栏", .pin:"置顶常驻", .fullScreen:"进入／退出全屏", .settings:"打开设置", .quit:"退出 Inkey"][self]!
    }
    var selectorName: String? {
        [Self.screenDraft:"toggleScreenDraft:", Self.toggleWindow:"toggleAction:", .newDraft:"newDraft:", .open:"openDraft:", .recent:"showRecent:", .save:"saveDraft:", .saveAs:"saveAs:", .export:"exportDraft:", .undo:"undo:", .redo:"redo:", .cut:"cut:", .copy:"copy:", .paste:"paste:", .selectAll:"selectAll:", .fit:"fit:", .preciseEdit:"editTextPrecisely:", .eraser:"toggleEraser:", .smallerEraser:"smallerEraser:", .largerEraser:"largerEraser:", .colorPicker:"pickColor:", .collapseToolbar:"toggleToolbarCollapsed:", .hideToolbar:"toggleToolbarHidden:", .pin:"togglePinned:", .fullScreen:"toggleFullScreen:", .settings:"showSettings:", .quit:"quit:"][self]
    }
    var isGlobal: Bool { self == .toggleWindow || self == .screenDraft }
    var isResponderAction: Bool { [.undo, .redo, .cut, .copy, .paste, .selectAll].contains(self) }
    var defaultBinding: KeyBinding {
        if self == .screenDraft { return KeyBinding(1, [.control, .option], "s") }
        if let index = Self.shapes.firstIndex(of: self) { return KeyBinding([18,19,20,21][index], .shift, "\(index + 1)") }
        if let index = Self.colors.firstIndex(of: self) { return KeyBinding([18,19,20,21,23,22][index], .option, "\(index + 1)") }
        let value: (UInt16, NSEvent.ModifierFlags) = [
            Self.toggleWindow:(49,[.control,.option]), .newDraft:(45,.command), .open:(31,.command), .recent:(31,[.command,.shift]), .save:(1,.command), .saveAs:(1,[.command,.shift]), .export:(14,.command),
            .undo:(6,.command), .redo:(6,[.command,.shift]), .cut:(7,.command), .copy:(8,.command), .paste:(9,.command), .selectAll:(0,.command),
            .fit:(29,.command), .preciseEdit:(36,.command), .eraser:(14,[.command,.option]), .smallerEraser:(33,[.command,.option]), .largerEraser:(30,[.command,.option]), .colorPicker:(8,[.command,.shift]),
            .collapseToolbar:(17,[.command,.option]), .hideToolbar:(17,[.command,.shift]), .pin:(35,[.command,.shift]), .fullScreen:(3,[.command,.control]), .settings:(43,.command), .quit:(12,.command)
        ][self]!
        return KeyBinding(value.0, value.1, KeyBinding.keyNames[value.0]!)
    }
}

struct ShortcutSettings {
    let defaults: UserDefaults
    private struct Override: Codable { let binding: KeyBinding? }
    private var overrides: [String: Override] {
        guard let data = defaults.data(forKey: "keyboardShortcuts"), let value = try? JSONDecoder().decode([String: Override].self, from: data) else { return [:] }
        return value
    }
    func binding(for action: ShortcutAction) -> KeyBinding? {
        if let value = overrides[action.rawValue] { return value.binding }
        if action == .toggleWindow, let code = defaults.object(forKey: "shortcutCode") as? NSNumber {
            let code = code.uint16Value
            let flags = (defaults.object(forKey: "shortcutModifiers") as? NSNumber)?.uint32Value ?? UInt32(controlKey | optionKey)
            // Preserve existing custom global keys without rewriting the user's preference.
            var eventFlags: NSEvent.ModifierFlags = []
            for (carbon, cocoa) in [(controlKey, NSEvent.ModifierFlags.control), (optionKey, .option), (shiftKey, .shift), (cmdKey, .command)] {
                if flags & UInt32(carbon) != 0 { eventFlags.insert(cocoa) }
            }
            return KeyBinding(code, eventFlags, KeyBinding.keyNames[code] ?? "Key \(code)")
        }
        return action.defaultBinding
    }
    func label(for action: ShortcutAction) -> String { binding(for: action)?.label ?? "未设置" }
    func preserveExistingBindingsForScreenDraft() {
        guard overrides[ShortcutAction.screenDraft.rawValue] == nil,
              conflict(for: ShortcutAction.screenDraft.defaultBinding, excluding: .screenDraft) != nil else { return }
        set(nil, for: .screenDraft)
    }
    func conflict(for binding: KeyBinding, excluding action: ShortcutAction) -> ShortcutAction? {
        ShortcutAction.allCases.first { $0 != action && self.binding(for: $0)?.sameCombination(as: binding) == true }
    }
    func validationMessage(_ binding: KeyBinding, for action: ShortcutAction) -> String? {
        guard !binding.key.isEmpty, binding.keyCode != 53 else { return "请选择其他按键" }
        let shapeNumber = ShortcutAction.shapes.contains(action) && binding.flags == .shift && [UInt16(18),19,20,21,23,22,26,28,25,29].contains(binding.keyCode)
        guard binding.isFunctionKey || shapeNumber || !binding.flags.intersection([.command,.control,.option]).isEmpty else { return "请包含 ⌘、⌥ 或 ⌃，或使用功能键；形状可用 ⇧ 数字" }
        if (binding.keyCode == 48 && binding.flags.contains(.command)) || (binding.keyCode == 49 && binding.flags == .command) || (binding.keyCode == 53 && binding.flags == [.command,.option]) {
            return "该组合由 macOS 保留，请选择其他快捷键"
        }
        if let other = conflict(for: binding, excluding: action) { return "已用于“\(other.title)”，请先清除或更改该项" }
        return nil
    }
    func set(_ binding: KeyBinding?, for action: ShortcutAction) {
        var value = overrides; value[action.rawValue] = Override(binding: binding)
        defaults.set(try? JSONEncoder().encode(value), forKey: "keyboardShortcuts")
        if action == .toggleWindow, let binding {
            defaults.set(Int(binding.keyCode), forKey: "shortcutCode")
            defaults.set(Int(binding.modifiers), forKey: "shortcutModifiers")
            defaults.set(binding.label, forKey: "shortcutLabel")
        }
    }
    func resetAll() {
        defaults.removeObject(forKey: "keyboardShortcuts")
        for key in ["shortcutCode", "shortcutModifiers", "shortcutLabel"] { defaults.removeObject(forKey: key) }
    }
}

extension UserPreferences {
    var shortcuts: ShortcutSettings { ShortcutSettings(defaults: defaults) }
}
