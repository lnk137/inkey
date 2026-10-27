import AppKit
import QuartzCore

/// Animate backing layers while native views already use their final hit regions.
@MainActor
final class ToolbarLayoutAnimation {
    static let duration: CFTimeInterval = 0.22
    private static let keys = ["position", "bounds", "transform", "opacity"]
    struct Geometry {
        let position: CGPoint
        let bounds: CGRect
        let transform: CATransform3D
    }
    typealias State = [ObjectIdentifier: Geometry]
    private var layers: [CALayer] = []
    private var completion: DispatchWorkItem?

    func capture(in view: NSView) -> State? {
        guard view.window?.isVisible == true, !view.isHidden,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return nil }
        view.layoutSubtreeIfNeeded(); view.layer?.layoutIfNeeded()
        var state: State = [:]
        for item in [view] + view.subviews where !item.isHidden {
            guard let layer = item.layer else { continue }
            let shown = layer.presentation() ?? layer
            state[ObjectIdentifier(item)] = Geometry(position: shown.position, bounds: shown.bounds, transform: shown.transform)
        }
        return state
    }

    func animate(from state: State, in view: NSView) {
        finish()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        view.layoutSubtreeIfNeeded(); view.layer?.layoutIfNeeded()
        for item in [view] + view.subviews where !item.isHidden {
            guard let layer = item.layer else { continue }
            let old = state[ObjectIdentifier(item)] ?? Geometry(position: layer.position, bounds: layer.bounds,
                                                               transform: CATransform3DScale(layer.transform, 0.85, 0.85, 1))
            var animated = false
            if state[ObjectIdentifier(item)] == nil {
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 0; fade.toValue = layer.opacity; fade.duration = Self.duration
                layer.add(fade, forKey: "toolbarReflow.opacity"); animated = true
            }
            for (key, before, after, changed) in [
                ("position", NSValue(point: old.position), NSValue(point: layer.position), old.position != layer.position),
                ("bounds", NSValue(rect: old.bounds), NSValue(rect: layer.bounds), old.bounds != layer.bounds),
                ("transform", NSValue(caTransform3D: old.transform), NSValue(caTransform3D: layer.transform), !CATransform3DEqualToTransform(old.transform, layer.transform))
            ] where changed {
                let motion = CABasicAnimation(keyPath: key)
                motion.fromValue = before; motion.toValue = after
                motion.duration = Self.duration
                motion.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
                layer.add(motion, forKey: "toolbarReflow.\(key)")
                animated = true
            }
            if animated { layers.append(layer) }
        }
        let work = DispatchWorkItem { [weak self] in self?.finish() }
        completion = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration, execute: work)
    }

    func finish() {
        completion?.cancel(); completion = nil
        for layer in layers {
            for key in Self.keys { layer.removeAnimation(forKey: "toolbarReflow.\(key)") }
        }
        layers.removeAll()
    }
}
