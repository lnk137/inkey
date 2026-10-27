import AppKit

extension InkeyApp {
    @objc func toggleScreenDraft(_ sender: Any?) {
        if isScreenDraft { exitScreenDraft() }
        else { enterScreenDraft() }
    }

    func enterScreenDraft(on targetScreen: NSScreen? = nil) {
        guard !isScreenDraft, window.attachedSheet == nil,
              let screen = targetScreen ?? NSScreen.screens.first(where: {
                  NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
              }) ?? window.screen ?? NSScreen.main else { return }
        palette.cancelInteractions(); palette.closePicker(accept: true); canvas.flush()
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }

        if screenCanvas == nil {
            let overlayCanvas = CanvasView(frame: NSRect(origin: .zero, size: screen.frame.size), preferences: preferences)
            overlayCanvas.transparentBackground = true
            overlayCanvas.setHighContrast(preferences.screenHighContrast, animated: false)
            configureCanvas(overlayCanvas)
            if let id = preferences.defaults.string(forKey: "screenDraft"),
               let draft = store.recent().first(where: { $0.1.id.uuidString == id })?.1 {
                overlayCanvas.install(draft)
            } else {
                overlayCanvas.draft.background = isDark ? InkColor("202322") : InkColor("FAF9F6")
                overlayCanvas.draft.anchor = InkPoint(NSPoint(x: screen.frame.width / 2, y: screen.frame.height / 2))
            }
            screenCanvas = overlayCanvas
            let overlay = InkeyWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            overlay.title = "Inkey · 屏幕草稿"
            overlay.isOpaque = false; overlay.backgroundColor = .clear; overlay.hasShadow = false
            overlay.isReleasedWhenClosed = false; overlay.isMovable = false
            overlay.acceptsMouseMovedEvents = true; overlay.ignoresMouseEvents = false
            overlay.level = .statusBar
            overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            overlay.delegate = self
            overlay.contentView?.addSubview(overlayCanvas)
            overlayCanvas.autoresizingMask = [.width, .height]
            overlay.onResize = { [weak self] in self?.layoutPalette(initial: false) }
            screenWindow = overlay
        }
        guard let screenCanvas, let screenWindow, let content = screenWindow.contentView else { return }
        canvasPresentation = CanvasPresentation(window: window, canvas: canvas, fileURL: fileURL,
                                               wasVisible: window.isVisible && !window.isMiniaturized)
        window.orderOut(nil)
        window = screenWindow; canvas = screenCanvas; fileURL = screenFileURL
        if preferences.autoHighContrastOnScreen {
            canvas.setHighContrast(true, animated: false)
            preferences.screenHighContrast = true
        }
        screenWindow.setFrame(screen.frame, display: true)
        palette.removeFromSuperview(); content.addSubview(palette)
        updateScreenControls(in: content, screen: screen)
        syncPaletteToPaper(); syncCanvasTools(); layoutPalette(initial: false)
        refreshHighContrastUI()
        if let settings { settings.level = NSWindow.Level(rawValue: screenWindow.level.rawValue + 1) }
        showWindow()
    }

    private func updateScreenControls(in content: NSView, screen: NSScreen) {
        content.subviews.compactMap { $0 as? NSButton }.forEach { $0.removeFromSuperview() }
        let top = screen.visibleFrame.maxY - screen.frame.minY - 36
        for (symbol, label, action, x) in [
            ("ellipsis", "更多", #selector(showMore(_:)), content.bounds.width - 80),
            ("xmark", "退出屏幕草稿", #selector(toggleScreenDraft(_:)), content.bounds.width - 44)
        ] {
            let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label)!, target: self, action: action)
            button.frame = NSRect(x: x, y: top, width: 28, height: 28)
            button.bezelStyle = .regularSquare; button.isBordered = true
            button.autoresizingMask = [.minXMargin, .minYMargin]
            button.toolTip = label == "更多" ? label : "退出屏幕草稿 · Esc · \(shortcuts.label(for: .screenDraft))"
            content.addSubview(button)
        }
    }

    func exitScreenDraft(restoreWindow: Bool? = nil, activatePrevious: Bool = true) {
        guard let presentation = canvasPresentation else { return }
        palette.cancelInteractions(); palette.closePicker(accept: true); canvas.flush()
        screenFileURL = fileURL
        window.orderOut(nil)
        settings?.orderOut(nil); settings?.level = .normal
        window = presentation.window; canvas = presentation.canvas; fileURL = presentation.fileURL
        canvasPresentation = nil
        palette.removeFromSuperview(); window.contentView?.addSubview(palette)
        syncPaletteToPaper(); syncCanvasTools(); layoutPalette(initial: false)
        refreshHighContrastUI()
        statusLabel.stringValue = canvas.draft.name + (pinned ? " · 常驻" : "")
        if restoreWindow ?? presentation.wasVisible { showWindow() }
        else if activatePrevious { previousApp?.activate() }
    }

    private func syncCanvasTools() {
        canvas.ink = palette.current; canvas.shiftShape = preferences.shiftShape
        canvas.eraserDiameter = preferences.eraserDiameter
        canvas.cursorTrailEnabled = preferences.cursorTrail
        canvas.setEraserEnabled(preferences.tool == .eraser)
    }

    @discardableResult
    func handleScreenDraftEscape(_ event: NSEvent) -> Bool {
        guard isScreenDraft, event.keyCode == 53, window.attachedSheet == nil else { return false }
        if palette.hasPopover { palette.closePicker(accept: false) }
        else if !palette.cancelActiveGesture() { exitScreenDraft() }
        return true
    }
}
