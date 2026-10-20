import LongbowCore
import SpriteKit

/// An archer built from separate parts so it can animate (spec A4):
/// legs, body, head (expressions), back arm, bow arm + bow, string, arrow.
/// Local coordinates are metres with the feet at the origin; the `figure`
/// is mirrored for the archer facing left.
///
/// Personality lives here: idle breathing and blinks, a head that looks up
/// along the aim, arm tremble at full draw, bow recoil, and cartoon reactions
/// to being hit or nearly hit. All motion is skipped when `lively` is false
/// (Reduce Motion).
@MainActor
final class ArcherNode: SKNode {
    let look: ArcherLook
    let facing: CGFloat
    private let boil: Bool
    private let lively: Bool

    let figure = SKNode()
    /// Squash, stretch and knockback are applied here.
    private let rig = SKNode()
    /// Everything above the hips; pivots at the hips and bobs while breathing.
    private let upper = SKNode()
    private let upperContent = SKNode()
    static let hips = CGPoint(x: 0, y: 0.88)
    private let legs: SKSpriteNode
    private let body: SKSpriteNode
    private let headPivot = SKNode()
    private let head: SKSpriteNode
    private let hatSprite: SKSpriteNode
    private(set) var hat: Hat
    private(set) var avatar: Avatar
    private let bowArm = SKNode()
    private let armLine = InkShape()
    private let bow: SKSpriteNode
    private let hand = InkShape(circleOfRadiusMetres: 0.045)
    private let string = InkShape()
    private let backArm = InkShape()
    private let nocked: SKSpriteNode
    private let stuckLayer = SKNode()
    private var stuck: [SKNode] = []

    /// Shoulders sit at the top corners of the torso, below the chin, so the
    /// arms never start inside the (enlarged) head.
    static let shoulder = CGPoint(x: 0.1, y: 1.3)
    static let backShoulder = CGPoint(x: -0.1, y: 1.3)
    static let neck = CGPoint(x: 0.02, y: 1.45)
    static let armLength: CGFloat = 0.42
    /// Relaxed pose: arm hanging down, bow held along it like a walking stick.
    static let restAngle: CGFloat = -78
    /// Caricature: the drawn head is a bit bigger than its hitbox.
    static let headScale: CGFloat = 1.18

    private(set) var angleDegrees: CGFloat = -55
    private(set) var power: CGFloat = 0
    private(set) var expression: Expression = .neutral
    /// The resting face. Matches use `.angry`: everyone means business.
    private(set) var calmExpression: Expression = .neutral
    private var stringPluck: CGFloat = 0

    init(look: ArcherLook, facing: CGFloat, boil: Bool, lively: Bool = true, hat: Hat = .none, avatar: Avatar? = nil) {
        self.look = look
        self.hat = hat
        self.avatar = avatar ?? look.defaultAvatar
        self.facing = facing
        self.boil = boil
        self.lively = lively
        let lib = ArtLibrary.shared
        legs = lib.legs(outfit: self.avatar.wardrobe).makeSprite()
        body = lib.body(outfit: self.avatar.wardrobe).makeSprite()
        head = lib.head(self.avatar, .neutral).makeSprite()
        hatSprite = lib.hat(hat).makeSprite()
        bow = lib.bow.makeSprite()
        nocked = lib.arrow.makeSprite()
        super.init()
        // People get the finer dot grid.
        for sp in [legs, body, head, hatSprite] { sp.shader = HalftoneShader.spriteFine }

        figure.xScale = facing
        addChild(figure)
        figure.addChild(rig)

        for s in [backArm, armLine, string] {
            s.strokeColor = .ink
            s.lineCap = .round
            s.lineJoin = .round
        }
        backArm.metresLineWidth = 0.066
        armLine.metresLineWidth = 0.066
        string.metresLineWidth = 0.016
        hand.fillColor = .paper
        hand.strokeColor = .ink
        hand.metresLineWidth = 0.022

        legs.zPosition = 1
        rig.addChild(legs)
        upper.zPosition = 2
        upper.position = Self.hips
        rig.addChild(upper)
        upperContent.position = CGPoint(x: -Self.hips.x, y: -Self.hips.y)
        upper.addChild(upperContent)

        backArm.zPosition = 0
        body.zPosition = 2
        // The bow arm passes behind the head, so the face is never covered.
        bowArm.zPosition = 2.5
        headPivot.zPosition = 3
        stuckLayer.zPosition = 5
        upperContent.addChild(backArm)
        upperContent.addChild(body)
        upperContent.addChild(headPivot)
        upperContent.addChild(bowArm)
        rig.addChild(stuckLayer)

        headPivot.position = Self.neck
        headPivot.setScale(Self.headScale)
        head.position = CGPoint(x: -Self.neck.x, y: -Self.neck.y)
        headPivot.addChild(head)
        hatSprite.position = head.position
        hatSprite.zPosition = 1
        headPivot.addChild(hatSprite)
        hatSprite.startBoil(lib.hat(hat).textures, enabled: boil)

        bowArm.position = Self.shoulder
        let armPath = CGMutablePath()
        armPath.move(to: .zero)
        armPath.addLine(to: CGPoint(x: Self.armLength, y: 0))
        armLine.metresPath = armPath
        bowArm.addChild(armLine)
        bow.position = CGPoint(x: Self.armLength, y: 0)
        bow.zPosition = 1
        bowArm.addChild(bow)
        string.zPosition = 0.5
        bowArm.addChild(string)
        nocked.zPosition = 2
        bowArm.addChild(nocked)
        hand.position = CGPoint(x: Self.armLength, y: 0)
        hand.zPosition = 3
        bowArm.addChild(hand)

        legs.startBoil(lib.legs(outfit: self.avatar.wardrobe).textures, enabled: boil)
        body.startBoil(lib.body(outfit: self.avatar.wardrobe).textures, enabled: boil)
        head.startBoil(lib.head(self.avatar, .neutral).textures, enabled: boil)
        bow.startBoil(lib.bow.textures, enabled: boil)
        setAim(angleDegrees: ArcherNode.restAngle, power: 0, nockedArrow: false)
        startIdle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Idle life

    private func startIdle() {
        guard lively else { return }
        // Breathing: the upper body rises and falls a touch.
        let period = Double.random(in: 1.6...2.0)
        let up = SKAction.moveBy(x: 0, y: 0.018, duration: period / 2)
        up.timingMode = .easeInEaseOut
        upperContent.run(.repeatForever(.sequence([up, up.reversed()])), withKey: "breathe")

        // Blinks and the odd glance around.
        let blink = SKAction.run { [weak self] in self?.blinkOnce() }
        let wait = SKAction.wait(forDuration: 3.2, withRange: 2.8)
        run(.repeatForever(.sequence([wait, blink])), withKey: "blink")
    }

    private func blinkOnce() {
        guard expression == calmExpression, power == 0 else { return }
        if look.hasBlink {
            let lib = ArtLibrary.shared
            head.removeAction(forKey: "boil")
            head.texture = lib.head(avatar, .blink).textures[0]
            run(.wait(forDuration: 0.13)) { [weak self] in
                guard let self, self.expression == self.calmExpression else { return }
                self.head.startBoil(lib.head(self.avatar, self.calmExpression).textures, enabled: self.boil)
            }
        }
        // Every so often, a little head tilt instead of (or as well as) a blink.
        if Int.random(in: 0..<3) == 0 {
            let tilt = CGFloat.random(in: -0.12...0.12)
            headPivot.run(.sequence([
                .rotate(toAngle: tilt, duration: 0.25, shortestUnitArc: true),
                .wait(forDuration: 0.6),
                .rotate(toAngle: 0, duration: 0.3, shortestUnitArc: true),
            ]), withKey: "glance")
        }
    }

    // MARK: - Aiming

    /// Angle above horizontal toward the opponent, power 0...1. `raise` blends
    /// the bow from resting along the arm (0) to the shooting grip (1); by
    /// default it follows the pose.
    func setAim(angleDegrees: CGFloat, power: CGFloat, nockedArrow: Bool, raise: CGFloat? = nil) {
        self.angleDegrees = angleDegrees
        self.power = power
        bowArm.zRotation = angleDegrees * .pi / 180
        // At rest the bow turns to lie along the arm instead of across the legs.
        let k = raise ?? ((!nockedArrow && angleDegrees < -40) ? 0 : 1)
        bow.zRotation = (1 - k) * .pi / 2
        bow.position = CGPoint(x: Self.armLength - 0.02 * (1 - k), y: 0.05 * (1 - k))
        string.isHidden = k < 0.75
        redrawString(pullPower: power, pluck: 0)
        nocked.isHidden = !nockedArrow || k < 0.75

        // The head follows the aim a little, and the body leans back as you draw.
        if nockedArrow {
            headPivot.removeAction(forKey: "glance")
            headPivot.zRotation = min(0.32, max(-0.12, angleDegrees * .pi / 180 * 0.3))
            rig.zRotation = power * 0.06
        } else {
            rig.zRotation = 0
        }
        setTremble(lively && nockedArrow && power > 0.85)
    }

    private func redrawString(pullPower: CGFloat, pluck: CGFloat) {
        let grip = Self.armLength
        let tipX = grip + CharacterArt.bowTip.x
        let tipY = CharacterArt.bowTip.y
        let pullX = tipX - (0.06 + 0.42 * pullPower)
        let s = CGMutablePath()
        s.move(to: CGPoint(x: tipX, y: tipY))
        if pluck != 0 {
            // A vibrating string: a quick S-curve through the middle.
            s.addQuadCurve(to: CGPoint(x: pullX, y: 0), control: CGPoint(x: pullX + pluck, y: tipY * 0.5))
            s.addQuadCurve(to: CGPoint(x: tipX, y: -tipY), control: CGPoint(x: pullX - pluck, y: -tipY * 0.5))
        } else {
            s.addLine(to: CGPoint(x: pullX, y: 0))
            s.addLine(to: CGPoint(x: tipX, y: -tipY))
        }
        string.metresPath = s
        nocked.position = CGPoint(x: pullX, y: 0)

        // Back arm reaches the string's pull point (or hangs loose at rest).
        let pull = string.isHidden ? CGPoint(x: -0.13, y: 0.92)
            : bowArm.convert(CGPoint(x: pullX, y: 0), to: upperContent)
        let b = CGMutablePath()
        b.move(to: Self.backShoulder)
        // Drawing the string, the elbow cocks out behind, level with the hand.
        let elbow = string.isHidden
            ? CGPoint(x: Self.backShoulder.x - 0.05, y: (Self.backShoulder.y + pull.y) / 2)
            : CGPoint(x: min(Self.backShoulder.x, pull.x) - 0.16, y: pull.y + 0.03)
        b.addQuadCurve(to: pull, control: elbow)
        backArm.metresPath = b
    }

    /// Picks the bow up from the resting pose into a shooting stance: the arm
    /// swings up from the hip, the bow turns upright, an arrow is nocked.
    func pickUp(to angle: CGFloat, duration: Double, completion: (() -> Void)? = nil) {
        removeAction(forKey: "pickup")
        let start = angleDegrees < -40 ? angleDegrees : Self.restAngle
        guard lively else {
            setAim(angleDegrees: angle, power: 0, nockedArrow: true)
            completion?()
            return
        }
        let action = SKAction.customAction(withDuration: duration) { [weak self] _, t in
            guard let self else { return }
            let k = min(1, t / CGFloat(duration))
            // Ease out with a small overshoot, like a real swing.
            let e = 1 - pow(1 - k, 3) + sin(k * .pi) * 0.08
            let a = start + (angle - start) * e
            self.setAim(angleDegrees: a, power: 0, nockedArrow: k > 0.7, raise: min(1, k * 1.4))
        }
        run(.sequence([action, .run { [weak self] in
            self?.setAim(angleDegrees: angle, power: 0, nockedArrow: true)
            completion?()
        }]), withKey: "pickup")
    }

    private var trembling = false

    /// Straining at full draw: the arms shake a little.
    private func setTremble(_ on: Bool) {
        guard on != trembling else { return }
        trembling = on
        if on {
            let shake = SKAction.customAction(withDuration: 0.05) { [weak self] _, _ in
                self?.bowArm.position = CGPoint(x: Self.shoulder.x + .random(in: -0.008...0.008),
                                                y: Self.shoulder.y + .random(in: -0.008...0.008))
            }
            bowArm.run(.repeatForever(shake), withKey: "tremble")
        } else {
            bowArm.removeAction(forKey: "tremble")
            bowArm.position = Self.shoulder
        }
    }

    /// Release: the bow kicks, the string twangs, the body follows through.
    func releaseShot() {
        setTremble(false)
        let base = bowArm.zRotation
        nocked.isHidden = true
        guard lively else {
            redrawString(pullPower: 0, pluck: 0)
            return
        }
        bowArm.run(.sequence([
            .rotate(toAngle: base + 0.14, duration: 0.05),
            .rotate(toAngle: base, duration: 0.3),
        ]))
        let twang = SKAction.customAction(withDuration: 0.35) { [weak self] _, t in
            let k = t / 0.35
            let pluck = 0.07 * (1 - k) * (Int(t * 40) % 2 == 0 ? 1 : -1)
            self?.redrawString(pullPower: 0, pluck: pluck)
        }
        string.run(.sequence([twang, .run { [weak self] in self?.redrawString(pullPower: 0, pluck: 0) }]))
        rig.run(.sequence([.rotate(toAngle: -0.05, duration: 0.08), .rotate(toAngle: 0, duration: 0.3)]))
        headPivot.run(.rotate(toAngle: 0.15, duration: 0.2))
    }

    // MARK: - Expressions and reactions

    /// Sets the face to rest in (`.neutral` maps to it from then on).
    func setCalmExpression(_ expr: Expression) {
        calmExpression = expr
        let current = expression
        expression = .blink // force a refresh
        setExpression(current == .neutral ? expr : current)
    }

    func setExpression(_ requested: Expression) {
        let expr = requested == .neutral ? calmExpression : requested
        guard expr != expression else { return }
        expression = expr
        head.startBoil(ArtLibrary.shared.head(avatar, expr).textures, enabled: boil)
    }

    /// Back to a calm stance between turns.
    func settle() {
        setExpression(.neutral)
        rig.removeAllActions()
        rig.run(.group([.move(to: .zero, duration: 0.25), .rotate(toAngle: 0, duration: 0.25),
                        .scaleX(to: 1, y: 1, duration: 0.25)]))
        upper.run(.rotate(toAngle: 0, duration: 0.25))
        headPivot.run(.rotate(toAngle: 0, duration: 0.3, shortestUnitArc: true))
        childNode(withName: "dizzy")?.removeFromParent()
        hatSprite.isHidden = false
    }

    /// Cartoon reaction to an arrow. Squash, stagger back, and a part-specific
    /// flourish: dizzy stars for the head, an "oof" fold for the body, a hop for
    /// the legs.
    func react(to part: BodyPart) {
        setExpression(.hit)
        guard lively else { return }
        let back: CGFloat = -0.28 // away from the shooter (local x is toward them)
        let squash = SKAction.scaleX(to: 1.22, y: 0.78, duration: 0.05)
        let stretch = SKAction.scaleX(to: 0.9, y: 1.12, duration: 0.09)
        let settle = SKAction.scaleX(to: 1, y: 1, duration: 0.18)
        settle.timingMode = .easeOut
        let stagger = SKAction.moveBy(x: back, y: 0, duration: 0.14)
        stagger.timingMode = .easeOut
        rig.run(.group([.sequence([squash, stretch, settle]), stagger,
                        .sequence([.rotate(toAngle: 0.22, duration: 0.08), .rotate(toAngle: 0.06, duration: 0.4)])]))

        switch part {
        case .head:
            knockHatOff()
            headPivot.run(.sequence([.rotate(toAngle: -0.45, duration: 0.07),
                                     .rotate(toAngle: 0.2, duration: 0.18),
                                     .rotate(toAngle: -0.08, duration: 0.25)]))
            addDizzyStars()
        case .body:
            // Fold over like the wind was knocked out of him.
            upper.run(.sequence([.rotate(toAngle: -0.35, duration: 0.1), .wait(forDuration: 0.3),
                                 .rotate(toAngle: 0, duration: 0.4)]))
        case .legs:
            // "Ow ow ow": hop on the spot.
            let hop = SKAction.sequence([.moveBy(x: 0, y: 0.35, duration: 0.14),
                                         .moveBy(x: 0, y: -0.35, duration: 0.12)])
            hop.timingMode = .easeOut
            figure.run(.sequence([.wait(forDuration: 0.12), hop, hop]))
        }
    }

    private func addDizzyStars() {
        childNode(withName: "dizzy")?.removeFromParent()
        let ring = SKNode()
        ring.name = "dizzy"
        ring.position = CGPoint(x: 0, y: 2.05)
        ring.zPosition = 10
        addChild(ring)
        // Little cartoon birds circling the head, flapping as they go.
        let lib = ArtLibrary.shared
        let frames = lib.birdFrames
        let birds = (0..<3).map { _ -> SKSpriteNode in
            let s = lib.bird.makeSprite()
            s.setScale(0.32)
            s.run(.repeatForever(.animate(with: frames, timePerFrame: 0.09)))
            ring.addChild(s)
            return s
        }
        let orbit = SKAction.customAction(withDuration: 2.4) { _, t in
            for (i, s) in birds.enumerated() {
                let a = t * 5 + CGFloat(i) * 2 * .pi / 3
                s.position = CGPoint(x: cos(a) * 0.36, y: sin(a) * 0.1)
                // Face the direction of travel around the ring.
                s.xScale = (sin(a) > 0 ? -0.32 : 0.32)
                s.zPosition = sin(a) > 0 ? -1 : 1
            }
        }
        ring.run(.sequence([orbit, .fadeOut(withDuration: 0.2), .removeFromParent()]))
    }

    func setAvatar(_ newAvatar: Avatar) {
        avatar = newAvatar
        let lib = ArtLibrary.shared
        head.startBoil(lib.head(newAvatar, expression).textures, enabled: boil)
        body.startBoil(lib.body(outfit: newAvatar.wardrobe).textures, enabled: boil)
        legs.startBoil(lib.legs(outfit: newAvatar.wardrobe).textures, enabled: boil)
    }

    func setHat(_ newHat: Hat) {
        hat = newHat
        hatSprite.startBoil(ArtLibrary.shared.hat(newHat).textures, enabled: boil)
    }

    /// A headshot sends the hat spinning off; it lands back on when things settle.
    private func knockHatOff() {
        guard hat != .none, hatSprite.parent != nil, let parent else { return }
        let flying = ArtLibrary.shared.hat(hat).makeSprite()
        flying.size = CGSize(width: hatSprite.size.width * Self.headScale * xScale,
                             height: hatSprite.size.height * Self.headScale * yScale)
        flying.position = convert(CGPoint(x: Self.neck.x * facing, y: Self.neck.y), to: parent)
        flying.xScale = facing
        flying.zPosition = zPosition + 1
        parent.addChild(flying)
        hatSprite.isHidden = true
        let dx = -facing * CGFloat.random(in: 1.2...2.2) * xScale
        let up = CGFloat.random(in: 1.4...2.0) * xScale
        let start = flying.position
        let fall = SKAction.customAction(withDuration: 0.9) { node, t in
            let k = t / 0.9
            node.position = CGPoint(x: start.x + dx * k, y: start.y + up * 4 * k * (1 - k) - 1.6 * k * k * self.yScale)
            node.zRotation = -self.facing * 7 * k
        }
        flying.run(.sequence([fall, .fadeOut(withDuration: 0.25), .removeFromParent()]))
    }

    /// Knocked back by a hit: three stumbling hops away from the shooter,
    /// following the ground, arms flailing a little.
    func stagger(to target: CGPoint, ground: @escaping (CGFloat) -> CGFloat, delay: Double) {
        let start = position
        let hops = 3
        let duration = 0.75
        let move = SKAction.customAction(withDuration: duration) { node, t in
            let k = min(1, t / CGFloat(duration))
            let ease = 1 - (1 - k) * (1 - k)
            let x = start.x + (target.x - start.x) * ease
            let phase = (k * CGFloat(hops)).truncatingRemainder(dividingBy: 1)
            let hop = 0.28 * (1 - k * 0.6) * sin(phase * .pi)
            node.position = CGPoint(x: x, y: ground(x) + hop)
        }
        let wobble = SKAction.sequence([.rotate(toAngle: 0.18 * facing, duration: 0.12),
                                        .rotate(toAngle: -0.1 * facing, duration: 0.25),
                                        .rotate(toAngle: 0, duration: 0.3)])
        run(.sequence([.wait(forDuration: delay), .group([move, .run { [weak self] in self?.rig.run(wobble) }]),
                       .run { [weak self] in self?.position = target }]), withKey: "stagger")
    }

    /// Phew: lean away, sweat, and a big exhale.
    func relieved() {
        setExpression(.relieved)
        guard lively else { return }
        rig.run(.sequence([.rotate(toAngle: 0.16, duration: 0.15), .wait(forDuration: 0.5),
                           .rotate(toAngle: 0, duration: 0.5)]))
    }

    /// A smug little hop when the other archer's arrow lands nowhere near.
    func taunt() {
        setExpression(.victorious)
        guard lively else { return }
        let hop = SKAction.sequence([.moveBy(x: 0, y: 0.22, duration: 0.12), .moveBy(x: 0, y: -0.22, duration: 0.12)])
        figure.run(.sequence([hop, hop]))
        headPivot.run(.sequence([.rotate(toAngle: 0.15, duration: 0.12), .rotate(toAngle: -0.15, duration: 0.2),
                                 .rotate(toAngle: 0, duration: 0.15)]))
    }

    /// The shooter's celebration after a hit.
    func celebrate() {
        setExpression(.victorious)
        guard lively else { return }
        setAim(angleDegrees: 70, power: 0, nockedArrow: false)
        let hop = SKAction.sequence([.moveBy(x: 0, y: 0.3, duration: 0.15), .moveBy(x: 0, y: -0.3, duration: 0.15)])
        hop.timingMode = .easeInEaseOut
        figure.run(hop)
    }

    // MARK: - Stuck arrows

    /// Sticks an arrow into the archer: `point` and `angle` are in the parent's
    /// (world) coordinates; the arrow stays for the rest of the round (cap 12).
    func addStuckArrow(at point: CGPoint, angle: CGFloat) {
        let local = convert(point, from: parent ?? self)
        var a = angle
        if facing < 0 { a = .pi - angle }
        let tip = CGPoint(x: local.x * facing + cos(a) * 0.14, y: local.y + sin(a) * 0.14)
        let arrow = StuckArrow.make(tip: tip, angle: a, wobble: lively)
        stuckLayer.addChild(arrow)
        stuck.append(arrow)
        if stuck.count > 12 { stuck.removeFirst().removeFromParent() }
    }

    func clearStuckArrows() {
        stuck.forEach { $0.removeFromParent() }
        stuck.removeAll()
    }

    var stuckArrowCount: Int { stuck.count }
}

/// An arrow embedded at its tip, which can "boing" back and forth.
@MainActor
enum StuckArrow {
    static func make(tip: CGPoint, angle: CGFloat, wobble: Bool) -> SKNode {
        let pivot = SKNode()
        pivot.position = tip
        pivot.zRotation = angle
        let arrow = ArtLibrary.shared.arrow.makeSprite()
        arrow.position = CGPoint(x: -CharacterArt.arrowLength, y: 0)
        pivot.addChild(arrow)
        if wobble {
            let boing = SKAction.customAction(withDuration: 0.7) { node, t in
                let k = t / 0.7
                node.zRotation = angle + 0.16 * (1 - k) * (1 - k) * sin(t * 48)
            }
            pivot.run(.sequence([boing, .rotate(toAngle: angle, duration: 0.05)]))
        }
        return pivot
    }
}

extension ArcherLook {
    /// Only faces with visible eyes blink.
    var hasBlink: Bool { true }
}

extension UIColor {
    static let paper = UIColor(red: 0xF3 / 255, green: 0xF0 / 255, blue: 0xE8 / 255, alpha: 1)
    static let ink = UIColor(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255, alpha: 1)
    static let inkQuiet = UIColor(red: 0x55 / 255, green: 0x55 / 255, blue: 0x55 / 255, alpha: 1)
}
