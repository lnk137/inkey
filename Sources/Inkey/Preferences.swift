import Foundation

enum InkTool: String { case pen, eraser }

struct SavedInk: Codable, Equatable {
    var color: InkColor
    var slot: Int
    var isPreset: Bool
}

final class UserPreferences {
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
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
