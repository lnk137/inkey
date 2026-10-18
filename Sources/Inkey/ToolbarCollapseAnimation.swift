import AppKit
import QuartzCore

private final class CollapseHitProxy: NSView {
    var resolveHit: ((NSPoint) -> NSView?)?
    override func hitTest(_ point: NSPoint) -> NSView? { resolveHit?(point) }
}

/// A temporary compositor: native controls keep their final geometry and hit regions.
/// Only a small cached texture, a rounded shell, and a vector chevron animate.
@MainActor
final class ToolbarCollapseAnimation {
    static let duration: CFTimeInterval = 0.32
    struct State {
        var bounds: CGRect
        var position: CGPoint
        var transform: CATransform3D
        var arrowPosition: CGPoint
        var arrowAngle: CGFloat
        var contentOpacity: Float
        var image: CGImage?
        var contentBounds: CGRect
        var arrowFrame: NSRect
    }
    private weak var view: NSView?
    private var shell: CALayer?
    private var arrow: CAShapeLayer?
    private var content: CALayer?
    private var cachedImage: CGImage?
    private var hitProxy: CollapseHitProxy?
    private var start: State?
    private var completion: DispatchWorkItem?
    private var generation = 0
    var isAnimating: Bool { shell != nil }

    func capture(in view: NSView, button: CollapseButton, collapsed: Bool) -> State? {
        guard let layer = view.layer else { return nil }
        view.layoutSubtreeIfNeeded(); layer.layoutIfNeeded()
        if let shell, let arrow, let content, let start {
            return State(bounds: shell.presentation()?.bounds ?? start.bounds,
                         position: shell.presentation()?.position ?? start.position,
                         transform: shell.presentation()?.transform ?? start.transform,
                         arrowPosition: arrow.presentation()?.position ?? start.arrowPosition,
                         arrowAngle: (arrow.presentation()?.value(forKeyPath: "transform.rotation.z") as? NSNumber).map { CGFloat($0.doubleValue) } ?? start.arrowAngle,
                         contentOpacity: content.presentation()?.opacity ?? start.contentOpacity,
                         image: cachedImage, contentBounds: content.bounds,
                         arrowFrame: presentedArrowFrame() ?? start.arrowFrame)
        }
        return State(bounds: layer.bounds, position: layer.position, transform: layer.transform,
                     arrowPosition: arrowCenter(in: view, button: button), arrowAngle: collapsed ? .pi : 0,
                     contentOpacity: collapsed ? 0 : 1,
                     image: collapsed ? nil : snapshot(in: view, excluding: button), contentBounds: layer.bounds,
                     arrowFrame: button.convert(button.bounds, to: view.superview))
    }

    func animate(from old: State, in view: NSView, button: CollapseButton, collapsed: Bool) {
        finish()
        guard let layer = view.layer, let parent = layer.superlayer,
              let image = old.image ?? snapshot(in: view, excluding: button) else { return }
        self.view = view
        view.layoutSubtreeIfNeeded(); layer.layoutIfNeeded()
        let contentBounds = old.image == nil ? layer.bounds : old.contentBounds
        let targetArrow = arrowCenter(in: view, button: button)
        let angle: CGFloat = collapsed ? .pi : 0
        let ratio = layer.bounds.width / view.bounds.width
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let shell = CALayer()
        shell.name = "Inkey.toolbarCollapse"
        shell.bounds = layer.bounds; shell.position = layer.position
        shell.anchorPoint = layer.anchorPoint; shell.transform = layer.transform
        shell.isGeometryFlipped = layer.isGeometryFlipped; shell.contentsScale = layer.contentsScale
        shell.backgroundColor = layer.backgroundColor; shell.borderColor = layer.borderColor
        shell.borderWidth = layer.borderWidth; shell.cornerRadius = layer.cornerRadius
        shell.masksToBounds = layer.masksToBounds
        shell.shadowColor = layer.shadowColor; shell.shadowOpacity = layer.shadowOpacity
        shell.shadowOffset = layer.shadowOffset; shell.shadowRadius = layer.shadowRadius
        shell.shadowPath = CGPath(roundedRect: shell.bounds, cornerWidth: shell.cornerRadius, cornerHeight: shell.cornerRadius, transform: nil)
        let clip = CALayer()
        let border = layer.borderWidth
        func innerBounds(_ bounds: CGRect) -> CGRect {
            CGRect(x: 0, y: 0, width: max(0, bounds.width - 2 * border), height: max(0, bounds.height - 2 * border))
        }
        clip.anchorPoint = .zero; clip.position = CGPoint(x: border, y: border); clip.bounds = innerBounds(layer.bounds)
        clip.cornerRadius = max(0, layer.cornerRadius - border); clip.masksToBounds = true
        let content = CALayer()
        content.anchorPoint = .zero; content.position = CGPoint(x: -border, y: -border); content.bounds = contentBounds
        content.contents = image; content.contentsScale = layer.contentsScale
        content.opacity = collapsed ? 0 : 1
        clip.addSublayer(content); shell.addSublayer(clip)
        let arrow = CAShapeLayer()
        arrow.contentsScale = layer.contentsScale
        var scale = CGAffineTransform(scaleX: ratio, y: ratio)
        arrow.path = CollapseButton.chevronPath().copy(using: &scale)
        view.effectiveAppearance.performAsCurrentDrawingAppearance { arrow.strokeColor = NSColor.secondaryLabelColor.cgColor }
        arrow.fillColor = nil; arrow.lineWidth = 1.5 * ratio
        arrow.lineCap = .round; arrow.lineJoin = .round
        arrow.position = targetArrow; arrow.setValue(angle, forKeyPath: "transform.rotation.z")
        shell.addSublayer(arrow)
        parent.insertSublayer(shell, above: layer)
        let hidden = CABasicAnimation(keyPath: "opacity")
        hidden.fromValue = 0; hidden.toValue = 0; hidden.duration = Self.duration
        layer.add(hidden, forKey: "toolbarCollapseVisibility")
        CATransaction.commit()
        self.shell = shell; self.arrow = arrow; self.content = content; cachedImage = image; start = old
        if let container = view.superview {
            let targetFrame = button.convert(button.bounds, to: container)
            let hit = CollapseHitProxy(frame: old.arrowFrame.union(targetFrame).insetBy(dx: -1, dy: -1))
            hit.resolveHit = { [weak self, weak button] point in
                guard let self, let rect = self.presentedArrowFrame() ?? self.start?.arrowFrame, rect.contains(point) else { return nil }
                return button
            }
            container.addSubview(hit, positioned: .above, relativeTo: view)
            hitProxy = hit
        }
        let bodyDuration: CFTimeInterval = collapsed ? 0.28 : Self.duration
        add(shell, "bounds", NSValue(rect: old.bounds), NSValue(rect: layer.bounds), duration: bodyDuration)
        add(shell, "position", NSValue(point: old.position), NSValue(point: layer.position), duration: bodyDuration)
        add(shell, "transform", NSValue(caTransform3D: old.transform), NSValue(caTransform3D: layer.transform), duration: bodyDuration)
        add(shell, "shadowPath", CGPath(roundedRect: old.bounds, cornerWidth: shell.cornerRadius, cornerHeight: shell.cornerRadius, transform: nil), shell.shadowPath!, duration: bodyDuration)
        add(clip, "bounds", NSValue(rect: innerBounds(old.bounds)), NSValue(rect: innerBounds(layer.bounds)), duration: bodyDuration)
        // Contents leave before the shell closes; on expansion they enter after space opens.
        add(content, "opacity", old.contentOpacity, content.opacity, duration: collapsed ? 0.09 : 0.16, delay: collapsed ? 0 : 0.08)
        add(arrow, "position", NSValue(point: old.arrowPosition), NSValue(point: targetArrow), duration: bodyDuration)
        add(arrow, "transform.rotation.z", old.arrowAngle, angle, duration: 0.26)
        generation += 1
        let token = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == token else { return }
            self.finish()
        }
        completion = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration, execute: work)
    }

    func finish() {
        generation += 1; completion?.cancel(); completion = nil
        CATransaction.begin(); CATransaction.setDisableActions(true)
        view?.layer?.removeAnimation(forKey: "toolbarCollapseVisibility")
        shell?.removeFromSuperlayer()
        hitProxy?.removeFromSuperview(); hitProxy = nil
        CATransaction.commit()
        shell = nil; arrow = nil; content = nil; cachedImage = nil; start = nil; view = nil
    }
    private func add(_ layer: CALayer, _ key: String, _ from: Any, _ to: Any, duration: CFTimeInterval, delay: CFTimeInterval = 0) {
        let motion = CABasicAnimation(keyPath: key)
        motion.fromValue = from; motion.toValue = to; motion.duration = duration
        motion.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0, 0.2, 1)
        if delay > 0 {
            motion.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + delay
            motion.fillMode = .backwards
        }
        layer.add(motion, forKey: key)
    }
    private func presentedArrowFrame() -> NSRect? {
        guard let shown = arrow?.presentation(), let parent = shown.superlayer?.superlayer,
              let start else { return nil }
        let center = shown.convert(CGPoint.zero, to: parent)
        return NSRect(x: center.x - start.arrowFrame.width / 2, y: center.y - start.arrowFrame.height / 2,
                      width: start.arrowFrame.width, height: start.arrowFrame.height)
    }
    private func arrowCenter(in view: NSView, button: CollapseButton) -> CGPoint {
        if let source = button.layer, let target = view.layer {
            return source.convert(CGPoint(x: source.bounds.midX, y: source.bounds.midY), to: target)
        }
        return CGPoint(x: button.frame.midX, y: button.frame.midY)
    }
    private func snapshot(in view: NSView, excluding button: CollapseButton) -> CGImage? {
        guard let layer = view.layer else { return nil }
        let background = layer.backgroundColor, border = layer.borderWidth, shadow = layer.shadowOpacity
        let hidden = button.isHidden
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.backgroundColor = nil; layer.borderWidth = 0; layer.shadowOpacity = 0
        button.isHidden = true
        defer {
            button.isHidden = hidden
            layer.backgroundColor = background; layer.borderWidth = border; layer.shadowOpacity = shadow
            CATransaction.commit()
        }
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap.cgImage
    }
}
