import AppKit

extension InkeyApp {
    @objc func changeHighContrastSpacing(_ sender: NSSlider) {
        preferences.highContrastTextSpacing = (sender.doubleValue * 2).rounded() / 2
        sender.doubleValue = preferences.highContrastTextSpacing
        contrastSpacingLabel?.stringValue = String(format: "%.1f pt", preferences.highContrastTextSpacing)
        canvas.refreshHighContrastSpacing()
        if let screenCanvas, screenCanvas !== canvas { screenCanvas.refreshHighContrastSpacing() }
        canvasPresentation?.canvas.refreshHighContrastSpacing()
    }
    @objc func changeAutoHighContrast(_ sender: NSSwitch) {
        preferences.autoHighContrastOnScreen = sender.state == .on
    }
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
