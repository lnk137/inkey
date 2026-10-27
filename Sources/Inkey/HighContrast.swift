import AppKit

extension InkeyApp {
    @objc func toggleHighContrast(_ sender: Any?) {
        canvas.setHighContrast(!canvas.highContrastEnabled)
        if isScreenDraft { preferences.screenHighContrast = canvas.highContrastEnabled }
        else { preferences.highContrast = canvas.highContrastEnabled }
        refreshHighContrastUI()
    }

    func refreshHighContrastUI() {
        palette.highContrastEnabled = canvas.highContrastEnabled
        func update(_ menu: NSMenu) {
            for item in menu.items {
                if item.action == #selector(toggleHighContrast(_:)) { item.state = canvas.highContrastEnabled ? .on : .off }
                if let submenu = item.submenu { update(submenu) }
            }
        }
        if let menu = NSApp.mainMenu { update(menu) }
    }
}
