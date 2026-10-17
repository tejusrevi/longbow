import LongbowCore
import SpriteKit

/// Quiet ambient life during a match: now and then a small flock of birds
/// crosses the sky, and a few leaves tumble along on the wind — which also
/// shows the wind's strength and direction at a glance. Purely visual, never
/// collides. Disabled under Reduce Motion.
@MainActor
final class AmbientLayer: SKNode {
    private var flockTimer: Double = .random(in: 8...14)
    private var leafTimer: Double = 0.5
    private var leaves: [WindLeaf] = []

    override init() {
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// - Parameters:
    ///   - view: visible world rectangle.
    ///   - wind: world-space wind in m/s² (positive blows right); 0 = no leaves.
    func update(dt: Double, view: CGRect, wind: Double, ground: (CGFloat) -> CGFloat, metresPerPoint: CGFloat) {
        flockTimer -= dt
        if flockTimer <= 0 {
            flockTimer = .random(in: 20...35)
            Self.spawnFlock(into: self, in: view, scale: max(1, metresPerPoint * 26))
        }
        // More wind, a few more leaves — never a blizzard.
        leafTimer -= dt
        let cap = wind == 0 ? 0 : min(6, 2 + Int(abs(wind)))
        if leafTimer <= 0 {
            leafTimer = .random(in: 0.9...1.8)
            if leaves.count < cap {
                leaves.append(WindLeaf(into: self, view: view, wind: wind, ground: ground,
                                       scale: max(1, metresPerPoint * 30)))
            }
        }
        leaves.removeAll { !$0.step(dt: dt, view: view, wind: wind, ground: ground) }
    }

    /// A loose V of 2–4 flapping birds crossing `view` (world coordinates).
    static func spawnFlock(into parent: SKNode, in view: CGRect, scale: CGFloat,
                           band: ClosedRange<CGFloat> = 0.55...0.75) {
        let lib = ArtLibrary.shared
        let fromLeft = Bool.random()
        let count = Int.random(in: 2...4)
        let s = min(scale, 3)
        // Spacing comes from the bird's own size, so the V never overlaps itself.
        let birdWidth = PropsArt.birdBounds.width * s
        let y = view.minY + view.height * CGFloat.random(in: band)
        let speed = view.width / CGFloat.random(in: 7...10)
        let dir: CGFloat = fromLeft ? 1 : -1
        let margin = birdWidth * 4
        let startX = fromLeft ? view.minX - margin : view.maxX + margin
        let endX = fromLeft ? view.maxX + margin : view.minX - margin
        let duration = Double(abs(endX - startX) / speed)
        let phase = CGFloat.random(in: 0...6)
        for i in 0..<count {
            let b = lib.bird.makeSprite()
            b.setScale(s)
            b.xScale = dir * s
            // Leader in front, then pairs behind on alternating sides.
            let row = CGFloat((i + 1) / 2)
            let side: CGFloat = i % 2 == 0 ? 1 : -1
            let start = CGPoint(x: startX - dir * row * birdWidth * 1.6,
                                y: y + (i == 0 ? 0 : side * row * birdWidth * 0.9))
            b.position = start
            b.zPosition = 3
            parent.addChild(b)
            b.run(.repeatForever(.animate(with: lib.birdFrames, timePerFrame: 0.14 + Double(i) * 0.01)))
            // The whole flock bobs together, so birds keep their places.
            let bob = SKAction.customAction(withDuration: duration) { node, t in
                node.position.y = start.y + sin(t * 1.8 + phase) * birdWidth * 0.15
            }
            b.run(.sequence([.group([.moveTo(x: endX - dir * row * birdWidth * 1.6, duration: duration), bob]),
                             .removeFromParent()]))
        }
    }
}

/// One leaf riding the wind: drifts at wind speed, flutters, tumbles, and skims
/// up off the ground instead of sticking to it.
@MainActor
final class WindLeaf {
    let node: SKSpriteNode
    private var vx: CGFloat
    private var vy: CGFloat
    private var phase = CGFloat.random(in: 0...6)
    private let spin = CGFloat.random(in: -3.5...3.5)
    private let size: CGFloat

    init(into parent: SKNode, view: CGRect, wind: Double, ground: (CGFloat) -> CGFloat, scale: CGFloat) {
        size = min(scale, 4) * 1.3
        node = ArtLibrary.shared.leaf.makeSprite()
        node.setScale(size)
        let fromLeft = wind >= 0
        let x = fromLeft ? view.minX - 1 : view.maxX + 1
        let floor = max(ground(x) + size * 0.4, view.minY)
        node.position = CGPoint(x: x, y: floor + (view.maxY - floor) * CGFloat.random(in: 0.05...0.55))
        // Behind the archers, so a leaf never sits on someone's face.
        node.zPosition = -1
        vx = CGFloat(wind) * 1.6
        vy = .random(in: -0.3...0.2)
        parent.addChild(node)
    }

    /// Returns false once the leaf has left the view.
    func step(dt: Double, view: CGRect, wind: Double, ground: (CGFloat) -> CGFloat) -> Bool {
        let t = CGFloat(dt)
        let target = CGFloat(wind) * 1.6 + (wind >= 0 ? 0.6 : -0.6)
        vx += (target - vx) * t * 0.7
        vy += (-0.25 - vy) * t * 0.5
        phase += t * 3
        node.position.x += vx * t
        node.position.y += (vy + sin(phase) * 0.8) * t
        node.zRotation += spin * t
        node.yScale = size * cos(phase * 0.6)
        let floor = ground(node.position.x) + size * 0.3
        if node.position.y < floor {
            node.position.y = floor
            vy = abs(vy) + 0.8
        }
        if !view.insetBy(dx: -4, dy: -4).contains(node.position) {
            node.removeFromParent()
            return false
        }
        return true
    }
}
