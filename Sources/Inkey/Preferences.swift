import AppKit

enum ShiftShape: String, CaseIterable {
    case arrow, line, rectangle, ellipse
    var kind: InkKind { InkKind(rawValue: rawValue)! }
    var symbol: String { ["arrow": "arrow.up.right", "line": "line.diagonal", "rectangle": "rectangle", "ellipse": "oval"][rawValue]! }
    var label: String { ["arrow": "箭头", "line": "直线", "rectangle": "矩形", "ellipse": "椭圆"][rawValue]! }
    static func shortcut(_ event: NSEvent, order: [ShiftShape] = allCases) -> ShiftShape? {
        guard event.modifierFlags.intersection([.command, .option, .control, .shift]) == .shift else { return nil }
        guard let index = [UInt16(18), 19, 20, 21].firstIndex(of: event.keyCode), order.indices.contains(index) else { return nil }
        return order[index]
    }
}

enum InkTool: String { case pen, eraser }

enum ToolbarAnimationStyle: String, CaseIterable {
    case gather, fade
    var label: String { self == .gather ? "聚拢收纳" : "收缩淡出" }
    var duration: CFTimeInterval { self == .gather ? 0.4 : 0.32 }
}

struct SavedInk: Codable, Equatable {
    var color: InkColor
    var slot: Int
    var isPreset: Bool
}

final class UserPreferences {
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var shapeOrder: [ShiftShape] {
        get {
            var result: [ShiftShape] = []
            for raw in defaults.stringArray(forKey: "shapeOrder") ?? [] {
                guard let shape = ShiftShape(rawValue: raw == "square" ? "rectangle" : raw), !result.contains(shape) else { continue }
                result.append(shape)
            }
            return result + ShiftShape.allCases.filter { !result.contains($0) }
        }
        set { defaults.set(newValue.map(\.rawValue), forKey: "shapeOrder") }
    }
    func migrateInteractionDefaults() {
        if defaults.integer(forKey: "pointerInteractionVersion") < 1 {
            defaults.set(true, forKey: "pointerPlacement")
            defaults.set(1, forKey: "pointerInteractionVersion")
        }
    }
    var shiftShape: ShiftShape {
        get {
            let saved = defaults.string(forKey: "shiftShape") ?? ""
            return saved == "square" ? .rectangle : ShiftShape(rawValue: saved) ?? .arrow
        }
        set { defaults.set(newValue.rawValue, forKey: "shiftShape") }
    }
    var defaultFontSize: Double {
        get {
            guard defaults.object(forKey: "defaultFontSize") != nil else { return 20 }
            let value = defaults.double(forKey: "defaultFontSize")
            return value.isFinite ? min(200, max(6, value)) : 20
        }
        set { defaults.set(newValue.isFinite ? min(200, max(6, newValue)) : 20, forKey: "defaultFontSize") }
    }
    var resizeUpdatesDefaultFont: Bool {
        get { defaults.object(forKey: "resizeUpdatesDefaultFont") == nil ? true : defaults.bool(forKey: "resizeUpdatesDefaultFont") }
        set { defaults.set(newValue, forKey: "resizeUpdatesDefaultFont") }
    }
    var cursorTrail: Bool {
        get { defaults.object(forKey: "cursorTrail") == nil ? true : defaults.bool(forKey: "cursorTrail") }
        set { defaults.set(newValue, forKey: "cursorTrail") }
    }
    var toolbarCollapsed: Bool {
        get { defaults.bool(forKey: "toolbarCollapsed") }
        set { defaults.set(newValue, forKey: "toolbarCollapsed") }
    }
    var toolbarAnimationStyle: ToolbarAnimationStyle {
        get { ToolbarAnimationStyle(rawValue: defaults.string(forKey: "toolbarAnimationStyle") ?? "") ?? .gather }
        set { defaults.set(newValue.rawValue, forKey: "toolbarAnimationStyle") }
    }
    var toolbarHidden: Bool {
        get { defaults.bool(forKey: "toolbarHidden") }
        set { defaults.set(newValue, forKey: "toolbarHidden") }
    }
    var toolbarScale: Double {
        get {
            guard defaults.object(forKey: "toolbarScale") != nil else { return 1 }
            let value = defaults.double(forKey: "toolbarScale")
            return value.isFinite ? min(1.5, max(0.85, value)) : 1
        }
        set { defaults.set(newValue.isFinite ? min(1.5, max(0.85, newValue)) : 1, forKey: "toolbarScale") }
    }
    var tool: InkTool {
        get { InkTool(rawValue: defaults.string(forKey: "drawingTool") ?? "") ?? .pen }
        set { defaults.set(newValue.rawValue, forKey: "drawingTool") }
    }
    var eraserDiameter: Double {
        get {
            guard defaults.object(forKey: "eraserDiameter") != nil else { return 24 }
            let value = defaults.double(forKey: "eraserDiameter")
            return value.isFinite ? min(120, max(4, value)) : 24
        }
        set { defaults.set(newValue.isFinite ? min(120, max(4, newValue)) : 24, forKey: "eraserDiameter") }
    }
    var pinned: Bool {
        get { defaults.bool(forKey: "pinnedWindow") }
        set { defaults.set(newValue, forKey: "pinnedWindow") }
    }
    var fullScreen: Bool {
        get { defaults.bool(forKey: "fullScreenWindow") }
        set { defaults.set(newValue, forKey: "fullScreenWindow") }
    }
    func ink(dark: Bool) -> SavedInk? {
        guard let data = defaults.data(forKey: dark ? "lastDarkInk" : "lastLightInk"),
              let saved = try? JSONDecoder().decode(SavedInk.self, from: data),
              (0..<6).contains(saved.slot),
              [saved.color.red, saved.color.green, saved.color.blue].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return nil }
        return saved
    }
    func saveInk(_ saved: SavedInk, dark: Bool) {
        guard (0..<6).contains(saved.slot), let data = try? JSONEncoder().encode(saved) else { return }
        defaults.set(data, forKey: dark ? "lastDarkInk" : "lastLightInk")
    }
}
