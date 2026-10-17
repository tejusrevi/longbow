import SpriteKit

/// Drives the `SKCameraNode` (spec A6.8). Works in world metres: `center` is the
/// point at the middle of the screen and `viewWidth` the visible world width.
@MainActor
final class GameCameraController {
    let node = SKCameraNode()
    private(set) var center = CGPoint.zero
    private(set) var viewWidth: CGFloat = 24
    private var velocity = (x: CGFloat(0), y: CGFloat(0), w: CGFloat(0))

    var targetCenter = CGPoint.zero
    var targetWidth: CGFloat = 24
    var smoothTime: CGFloat = 0.25

    /// Screen size in points.
    var viewSize = CGSize(width: 844, height: 390)
    private var shakeTime: CGFloat = 0
    private var shakeAmplitude: CGFloat = 0

    var viewHeight: CGFloat { viewWidth * viewSize.height / max(viewSize.width, 1) }
    /// Metres per point.
    var metresPerPoint: CGFloat { viewWidth / max(viewSize.width, 1) }

    func snap(center: CGPoint, width: CGFloat) {
        self.center = center
        viewWidth = width
        targetCenter = center
        targetWidth = width
        velocity = (0, 0, 0)
        apply()
    }

    func shake(points: CGFloat, duration: CGFloat) {
        shakeAmplitude = points
        shakeTime = duration
    }

    func update(dt: CGFloat) {
        center.x = Self.smoothDamp(center.x, targetCenter.x, &velocity.x, smoothTime, dt)
        center.y = Self.smoothDamp(center.y, targetCenter.y, &velocity.y, smoothTime, dt)
        viewWidth = Self.smoothDamp(viewWidth, targetWidth, &velocity.w, smoothTime * 1.8, dt)
        if shakeTime > 0 { shakeTime -= dt }
        apply()
    }

    private func apply() {
        var p = center
        if shakeTime > 0 {
            let s = shakeAmplitude * metresPerPoint
            p.x += CGFloat.random(in: -s...s)
            p.y += CGFloat.random(in: -s...s)
        }
        node.position = p
        node.setScale(metresPerPoint)
    }

    /// World point → camera-local (HUD) point, in screen points.
    func hudPoint(world: CGPoint) -> CGPoint {
        CGPoint(x: (world.x - node.position.x) / metresPerPoint, y: (world.y - node.position.y) / metresPerPoint)
    }

    func isVisible(world: CGPoint, margin: CGFloat = 0) -> Bool {
        let p = hudPoint(world: world)
        return abs(p.x) < viewSize.width / 2 - margin && abs(p.y) < viewSize.height / 2 - margin
    }

    /// Unity-style critically damped smoothing.
    static func smoothDamp(_ current: CGFloat, _ target: CGFloat, _ velocity: inout CGFloat,
                           _ smoothTime: CGFloat, _ dt: CGFloat) -> CGFloat {
        let st = max(0.0001, smoothTime)
        let omega = 2 / st
        let x = omega * dt
        let e = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
        let change = current - target
        let temp = (velocity + omega * change) * dt
        velocity = (velocity - omega * temp) * e
        return target + (change + temp) * e
    }
}
