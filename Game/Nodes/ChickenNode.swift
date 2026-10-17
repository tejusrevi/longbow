import SpriteKit

/// A wandering chicken: pecks, potters about, panics when an arrow lands close,
/// and — if one actually hits it — keels over. Purely cosmetic: it never
/// changes a shot (the physics stays deterministic).
@MainActor
final class ChickenNode: SKNode {
    private let sprite: SKSpriteNode
    private let boil: Bool
    private(set) var isDead = false
    private var pose: ChickenArt.Pose?
    private var timer: Double = .random(in: 0.5...2)
    private var walkTarget: CGFloat?
    private var walkSpeed: CGFloat = 0.5
    private var stepClock: Double = 0
    private var panicTime: Double = 0
    /// Where it's allowed to wander (world x).
    var range: ClosedRange<CGFloat>
    var facing: CGFloat = 1 {
        didSet {
            sprite.xScale = facing
            sign?.position = CGPoint(x: -facing * 0.03, y: 0.0)
        }
    }
    /// A protest placard, if this chicken has had enough.
    private(set) var sign: ProtestSign?
    /// Off while a scene is directing the chicken itself.
    var wanders = true
    private var onArrive: (() -> Void)?

    init(range: ClosedRange<CGFloat>, boil: Bool) {
        self.range = range
        self.boil = boil
        sprite = ArtLibrary.shared.chicken(.stand).makeSprite()
        super.init()
        addChild(sprite)
        facing = Bool.random() ? 1 : -1
        setPose(.stand)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Hit box in world space.
    var hitFrame: CGRect {
        let b = ChickenArt.hitBox
        let s = abs(xScale)
        return CGRect(x: position.x + (facing > 0 ? b.minX : -b.maxX) * s, y: position.y + b.minY * s,
                      width: b.width * s, height: b.height * s)
    }

    private func setPose(_ p: ChickenArt.Pose) {
        guard p != pose else { return }
        pose = p
        sprite.startBoil(ArtLibrary.shared.chicken(p).textures, enabled: boil)
    }

    func update(dt: Double, ground: (CGFloat) -> CGFloat) {
        defer { position.y = ground(position.x) }
        guard !isDead else { return }
        if panicTime > 0 {
            panicTime -= dt
            stepToward(dt: dt)
            if panicTime <= 0 { walkTarget = nil; setPose(.stand) }
            return
        }
        if walkTarget != nil {
            stepToward(dt: dt)
            return
        }
        guard wanders else { return }
        timer -= dt
        guard timer <= 0 else { return }
        if let sign {
            // Protesters march up and down and wave their sign.
            if Bool.random() {
                let to = min(max(position.x + .random(in: -2...2), range.lowerBound), range.upperBound)
                walkTarget = to
                walkSpeed = .random(in: 0.4...0.6)
                facing = to >= position.x ? 1 : -1
            } else {
                setPose(.stand)
                timer = .random(in: 1.5...3)
            }
            sign.startChanting()
            return
        }
        switch Int.random(in: 0..<5) {
        case 0, 1: // peck, peck
            setPose(.peck)
            timer = .random(in: 0.35...0.6)
            run(.sequence([.wait(forDuration: timer * 0.9), .run { [weak self] in self?.setPose(.stand) }]))
            timer += .random(in: 0.2...0.8)
        case 2, 3: // potter somewhere nearby
            let to = min(max(position.x + .random(in: -2.5...2.5), range.lowerBound), range.upperBound)
            walkTarget = to
            walkSpeed = .random(in: 0.5...0.9)
            facing = to >= position.x ? 1 : -1
        default: // stare into space
            setPose(.stand)
            timer = .random(in: 1...2.5)
        }
    }

    private func stepToward(dt: Double) {
        guard let to = walkTarget else { return }
        let dx = to - position.x
        let move = walkSpeed * CGFloat(dt)
        if abs(dx) <= move {
            position.x = to
            walkTarget = nil
            panicTime = 0
            sprite.position = .zero
            setPose(.stand)
            timer = .random(in: 0.5...1.5)
            let done = onArrive
            onArrive = nil
            done?()
            return
        }
        position.x += dx > 0 ? move : -move
        stepClock += dt
        let period = panicTime > 0 ? 0.09 : 0.2
        if stepClock > period {
            stepClock = 0
            if panicTime > 0 {
                setPose(.panic)
                sprite.position.y = sprite.position.y == 0 ? 0.05 : 0
            } else {
                setPose(pose == .step ? .stand : .step)
            }
        }
    }

    /// Picks up a placard (nailed to a stray arrow) and starts protesting.
    func holdSign(_ text: String) {
        sign?.removeFromParent()
        let s = ProtestSign(text: text)
        s.zPosition = -1 // held up behind the chicken
        addChild(s)
        sign = s
        s.position = CGPoint(x: -facing * 0.03, y: 0.0)
        s.startChanting()
    }

    // MARK: Directed moves (the toss)

    func look(_ direction: CGFloat) {
        facing = direction
        setPose(.stand)
    }

    func peck() {
        setPose(.peck)
        run(.sequence([.wait(forDuration: 0.3), .run { [weak self] in self?.setPose(.stand) }]))
    }

    /// Dash flapping to `x`, then call `arrived`.
    func dash(to x: CGFloat, speed: CGFloat, arrived: @escaping () -> Void) {
        removeAllActions()
        facing = x >= position.x ? 1 : -1
        walkTarget = x
        walkSpeed = speed
        panicTime = 60
        onArrive = arrived
        setPose(.panic)
    }

    /// An arrow landed close: flap and run the other way.
    func panic(awayFrom x: CGFloat) {
        guard !isDead else { return }
        removeAllActions()
        facing = position.x >= x ? 1 : -1
        walkTarget = min(max(position.x + facing * .random(in: 2...3.5), range.lowerBound), range.upperBound)
        walkSpeed = 3
        panicTime = 1.1
        setPose(.panic)
    }

    /// Shot. Keels over in a puff of feathers.
    func die(arrowFrom direction: CGFloat) {
        guard !isDead else { return }
        isDead = true
        removeAllActions()
        sprite.position = .zero
        facing = direction
        sign?.topple(direction: direction)
        setPose(.dead)
        sprite.run(.sequence([.moveBy(x: 0, y: 0.25, duration: 0.12), .moveBy(x: 0, y: -0.25, duration: 0.18)]))
        let lib = ArtLibrary.shared
        for _ in 0..<9 {
            let f = lib.feather.makeSprite()
            f.position = CGPoint(x: .random(in: -0.15...0.15), y: .random(in: 0.2...0.4))
            f.zRotation = .random(in: 0...(2 * .pi))
            f.zPosition = 1
            addChild(f)
            let drift = CGVector(dx: .random(in: -0.8...0.8), dy: .random(in: 0.3...0.9))
            f.run(.sequence([
                .group([.moveBy(x: drift.dx, y: drift.dy, duration: 0.5), .rotate(byAngle: .random(in: -3...3), duration: 0.5)]),
                .group([.moveBy(x: drift.dx * 0.4, y: -drift.dy - 0.3, duration: 1.8), .fadeOut(withDuration: 1.8),
                        .rotate(byAngle: .random(in: -2...2), duration: 1.8)]),
                .removeFromParent(),
            ]))
        }
    }
}
