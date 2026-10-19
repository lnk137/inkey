import AppKit

/// Shared spacing and native surfaces for the compact, single-page settings window.
enum SettingsLayout {
    static func row(_ title: String, detail: NSTextField? = nil, control: NSView) -> NSView {
        let row = NSView()
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        let labels = NSStackView(views: [label] + (detail.map { [$0] } ?? []))
        labels.orientation = .vertical; labels.alignment = .leading; labels.spacing = 3
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if let detail {
            detail.font = .systemFont(ofSize: 11)
            detail.textColor = .secondaryLabelColor
            detail.maximumNumberOfLines = 2
            detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            detail.widthAnchor.constraint(equalTo: labels.widthAnchor).isActive = true
        }
        for view in [labels, control] {
            view.translatesAutoresizingMaskIntoConstraints = false; row.addSubview(view)
        }
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        let preferredHeight = row.heightAnchor.constraint(equalToConstant: detail == nil ? 44 : 62)
        preferredHeight.priority = .defaultHigh
        preferredHeight.isActive = true
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: detail == nil ? 44 : 62),
            labels.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
            labels.trailingAnchor.constraint(equalTo: control.leadingAnchor, constant: -20),
            labels.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            labels.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor, constant: 10),
            labels.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -10),
            control.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14),
            control.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        return row
    }

    static func section(_ title: String, rows: [NSView]) -> NSView {
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 12, weight: .semibold)
        heading.textColor = .secondaryLabelColor
        let group = SettingsGroupView()
        let list = NSStackView()
        list.orientation = .vertical; list.alignment = .leading; list.spacing = 0
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let line = NSBox(); line.boxType = .separator
                let inset = NSView()
                line.translatesAutoresizingMaskIntoConstraints = false; inset.addSubview(line)
                NSLayoutConstraint.activate([
                    inset.heightAnchor.constraint(equalToConstant: 1),
                    line.leadingAnchor.constraint(equalTo: inset.leadingAnchor, constant: 14),
                    line.trailingAnchor.constraint(equalTo: inset.trailingAnchor, constant: -14),
                    line.centerYAnchor.constraint(equalTo: inset.centerYAnchor)
                ])
                list.addArrangedSubview(inset)
                inset.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
            }
            list.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
        }
        list.translatesAutoresizingMaskIntoConstraints = false; group.addSubview(list)
        NSLayoutConstraint.activate([
            list.leadingAnchor.constraint(equalTo: group.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: group.trailingAnchor),
            list.topAnchor.constraint(equalTo: group.topAnchor),
            list.bottomAnchor.constraint(equalTo: group.bottomAnchor)
        ])
        let section = NSStackView(views: [heading, group])
        section.orientation = .vertical; section.alignment = .leading; section.spacing = 8
        group.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        return section
    }

    static func window(sections: [NSView]) -> NSWindow {
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Inkey 设置"; panel.isReleasedWhenClosed = false
        let stack = NSStackView(views: sections)
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = panel.contentView!
        content.addSubview(stack)
        for section in sections { section.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 22)
        ])
        let footer = NSTextField(labelWithString: "所有更改自动保存")
        footer.font = .systemFont(ofSize: 11); footer.textColor = .tertiaryLabelColor
        footer.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(footer)
        NSLayoutConstraint.activate([
            footer.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 16),
            footer.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 2)
        ])
        content.layoutSubtreeIfNeeded()
        panel.setContentSize(NSSize(width: 520, height: stack.fittingSize.height + 22 + 16 + footer.fittingSize.height + 18))
        content.layoutSubtreeIfNeeded(); panel.center()
        return panel
    }
}

private final class SettingsGroupView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25), xRadius: 8, yRadius: 8)
        NSColor.controlBackgroundColor.setFill(); outline.fill()
        NSColor.separatorColor.setStroke(); outline.lineWidth = 0.5; outline.stroke()
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); needsDisplay = true
    }
}
