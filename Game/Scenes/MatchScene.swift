import LongbowCore
import SpriteKit
import UIKit

/// The match scene: world, archers, aiming input, flight playback, camera and
/// in-world feedback (spec A6.2, A6.8, A6.9). Rules live in `MatchController`
/// and Core; this class only presents.
@MainActor
final class MatchScene: SKScene {
    weak var controller: MatchController?

    let cam = GameCameraController()
    private let appConfig: AppConfig
    private let reduceMotion: Bool
    private var boil: Bool { appConfig.flags.lineBoilEnabled && !reduceMotion }

    private var world: WorldNode?
    private var ambient: AmbientLayer?
    private(set) var archers: [ArcherNode] = []
    private let worldLayer = SKNode()
    private let fxLayer = SKNode()
    private let hud = SKNode()

    // Aiming
    private var aimEnabled = false
    private var touchStart: CGPoint?
    private var currentInput: ShotInput?
    private var lastPowerTick = -1
    private let angleLabel = HUD.label("", font: GameFont.display, size: 20)
    private let powerRing = HUD.PowerRing()
    private let aimGuide = DottedPath()
    private let ghost = DottedPath()
    private let ghostMark = InkShape()
    private let lastBreathLabel = HUD.label("last breath", font: GameFont.hand, size: 20)

    // Flight
    private struct Flight {
        let report: TurnReport
        let path: [Vec2]
        var time: Double = 0
        let arrow: SKSpriteNode
        let trail: DottedPath
        let peakY: Double
        let launch: Vec2
        var frame = 0
        var passedApex = false
        let completion: () -> Void
    }

    private var flight: Flight?
    private var groundArrows: [SKNode] = []
    private var chickens: [ChickenNode] = []
    private var trails: [DottedPath] = []
    /// HUD nodes that follow a world point, with an offset in screen points.
    private var pinned: [(node: SKNode, world: CGPoint, offset: CGPoint)] = []
    private var lastUpdate: TimeInterval?
    /// Playback rate: 0.3 while "hold to slow time" is pressed.
    var playbackRate: Double = 1
    var isGamePaused = false

    private let hats: [Hat]
    private let avatars: [Avatar]
    /// Which archer the person is aiming with (pass and play aims both).
    private var aimShooter = 0
    private var archerScale: CGFloat { CGFloat(appConfig.game.physics.archerScale) }

    init(size: CGSize, appConfig: AppConfig, reduceMotion: Bool, hats: [Hat] = [.visor, .none],
         avatars: [Avatar] = [.bjorn, .gus]) {
        self.appConfig = appConfig
        self.hats = hats
        self.avatars = avatars
        self.reduceMotion = reduceMotion
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .paper
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        camera = cam.node
        addChild(cam.node)
        addChild(worldLayer)
        fxLayer.zPosition = 30
        worldLayer.addChild(fxLayer)
        cam.node.addChild(hud)
        hud.zPosition = 100

        aimGuide.strokeColor = .ink
        aimGuide.zPosition = 31
        ghost.strokeColor = UIColor.inkQuiet.withAlphaComponent(0.6)
        ghost.dotPoints = 2.5
        ghost.zPosition = 29
        ghostMark.strokeColor = UIColor.inkQuiet.withAlphaComponent(0.8)
        ghostMark.lineCap = .round
        ghostMark.zPosition = 29
        worldLayer.addChild(aimGuide)
        worldLayer.addChild(ghost)
        worldLayer.addChild(ghostMark)

        angleLabel.zPosition = 2
        for n in [angleLabel, powerRing, lastBreathLabel] as [SKNode] {
            n.isHidden = true
            hud.addChild(n)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func didChangeSize(_ oldSize: CGSize) {
        cam.viewSize = size
    }

    // MARK: - Round setup

    func loadRound(_ conditions: RoundConditions) {
        world?.removeFromParent()
        let w = WorldNode(conditions: conditions, boil: boil)
        worldLayer.addChild(w)
        world = w
        ambient?.removeFromParent()
        ambient = nil
        if !reduceMotion {
            let a = AmbientLayer()
            a.zPosition = 15
            worldLayer.addChild(a)
            ambient = a
        }
        groundArrows.forEach { $0.removeFromParent() }
        groundArrows.removeAll()
        trails.forEach { $0.removeFromParent() }
        trails.removeAll()
        clearPinned()
        ghost.points = []
        ghostMark.metresPath = nil

        spawnChickens(conditions)

        if archers.isEmpty {
            archers = [
                ArcherNode(look: .bjorn, facing: 1, boil: boil, lively: !reduceMotion, hat: hats[0], avatar: avatars[0]),
                ArcherNode(look: .gus, facing: -1, boil: boil, lively: !reduceMotion, hat: hats[1], avatar: avatars[1]),
            ]
            for a in archers {
                a.setScale(archerScale)
                a.zPosition = 20
                worldLayer.addChild(a)
            }
        }
        for (i, a) in archers.enumerated() {
            let p = conditions.archerPosition(i)
            a.position = CGPoint(x: p.x, y: p.y)
            a.clearStuckArrows()
            a.settle()
            a.setAim(angleDegrees: ArcherNode.restAngle, power: 0, nockedArrow: false)
        }
    }

    private var conditions: RoundConditions? { world?.conditions }

    /// One or two chickens potter about in the open ground between the archers.
    private func spawnChickens(_ c: RoundConditions) {
        chickens.forEach { $0.removeFromParent() }
        chickens.removeAll()
        // Near an archer, where arrows actually land and the camera looks.
        let d = CGFloat(c.distance)
        guard d > 30 else { return }
        let count = Int.random(in: 0..<3) == 0 ? 2 : 1
        var sides = [0, 1].shuffled()
        for _ in 0..<count {
            let side = sides.removeFirst()
            let toward: CGFloat = side == 0 ? 1 : -1
            let home = CGFloat(c.archerPosition(side).x)
            let x = home + toward * .random(in: 6...14)
            let lo = min(home + toward * 4, home + toward * 18), hi = max(home + toward * 4, home + toward * 18)
            let ch = ChickenNode(range: lo...hi, boil: boil)
            ch.setScale(archerScale)
            ch.position = CGPoint(x: x, y: CGFloat(c.terrain.height(at: Double(x))))
            ch.zPosition = 18
            worldLayer.addChild(ch)
            chickens.append(ch)
        }
        // Now and then the chickens have had enough of arrows: a protester
        // turns up close to one of the players, sign and all.
        var protestChance = 0.55
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "forceProtest") { protestChance = 1 }
        #endif
        if Double.random(in: 0..<1) < protestChance {
            let side = controller?.humans.randomElement() ?? 0
            let toward: CGFloat = side == 0 ? 1 : -1
            let home = CGFloat(c.archerPosition(side).x)
            let x = home + toward * .random(in: 10...15)
            let ch = ChickenNode(range: min(home + toward * 9, home + toward * 18)...max(home + toward * 9, home + toward * 18),
                                 boil: boil)
            ch.setScale(archerScale)
            ch.position = CGPoint(x: x, y: CGFloat(c.terrain.height(at: Double(x))))
            ch.zPosition = 17
            ch.facing = -toward // facing the archer, naturally
            ch.holdSign(ProtestSign.nextSlogan())
            worldLayer.addChild(ch)
            chickens.append(ch)
            protester = ch
        } else {
            protester = nil
        }
        protesterNoticed = false
    }

    /// The chicken with the placard this round, if any.
    private(set) var protester: ChickenNode?
    private var protesterNoticed = false

    /// True the first time a player's turn starts with a protest going on.
    func noticeProtester() -> Bool {
        guard let p = protester, !p.isDead, !protesterNoticed else { return false }
        protesterNoticed = true
        return true
    }

    /// The flying arrow went through a chicken. It doesn't stop the arrow.
    private func checkChickenHit(at pos: CGPoint, vx: Double, shooter: Int) {
        for ch in chickens where !ch.isDead && ch.hitFrame.contains(pos) {
            ch.die(arrowFrom: vx >= 0 ? 1 : -1)
            controller?.chickenDown(shooter: shooter)
            let note = HUD.label("bawk!", font: GameFont.hand, size: 26)
            hud.addChild(note)
            pin(note, at: CGPoint(x: ch.position.x, y: ch.position.y + 1.0 * archerScale), offset: CGPoint(x: 0, y: 10))
            popIn(note)
            note.run(.sequence([.wait(forDuration: 1.6), .fadeOut(withDuration: 0.3), .run { [weak self, weak note] in
                if let note { self?.unpin(note) }
                note?.removeFromParent()
            }]))
        }
    }

    private func framing(shooter i: Int) -> (CGPoint, CGFloat) {
        guard let c = conditions else { return (.zero, 20) }
        let feet = c.archerPosition(i)
        let dir = RoundConditions.facing(i)
        let w = CGFloat(appConfig.camera.aimViewWidth)
        let h = w * size.height / max(size.width, 1)
        return (CGPoint(x: feet.x + dir * 0.3 * w, y: feet.y + 0.3 * h), w)
    }

    /// Opening shot of each round (A6.8): show the whole field once, then glide
    /// down to the shooter.
    func openingPan(to shooter: Int, completion: @escaping () -> Void) {
        let (to, tw) = framing(shooter: shooter)
        guard let c = conditions, !reduceMotion else {
            cam.snap(center: to, width: tw)
            run(.wait(forDuration: 0.4), completion: completion)
            return
        }
        let fieldWidth = min(420, c.distance * 1.18 + 24)
        let fieldHeight = fieldWidth * size.height / max(size.width, 1)
        cam.snap(center: CGPoint(x: c.distance / 2, y: fieldHeight * 0.36), width: fieldWidth)
        let total = appConfig.camera.openingPanSeconds
        run(.sequence([
            .wait(forDuration: total * 0.3),
            .run { [weak self] in
                self?.cam.smoothTime = 0.65
                self?.cam.targetCenter = to
                self?.cam.targetWidth = tw
            },
            .wait(forDuration: total * 0.7),
        ]), completion: completion)
    }

    func panTo(shooter: Int, completion: @escaping () -> Void) {
        let (to, w) = framing(shooter: shooter)
        cam.smoothTime = 0.6
        cam.targetCenter = to
        cam.targetWidth = w
        run(.wait(forDuration: reduceMotion ? 0.3 : appConfig.camera.panSeconds), completion: completion)
    }

    // MARK: - Aiming (human)

    func beginHumanAim(shooter: Int, lastBreath: Bool, ghostShot: ShotOutcome?) {
        aimShooter = shooter
        aimEnabled = true
        touchStart = nil
        archers[aimShooter].pickUp(to: 20, duration: reduceMotion ? 0 : 0.45)
        showLastBreath(lastBreath ? aimShooter : nil)
        if let g = ghostShot {
            ghost.points = stride(from: 0, to: g.path.count, by: 3).map { CGPoint(x: g.path[$0].x, y: g.path[$0].y) }
            let p = g.point
            let s = 0.5
            let m = CGMutablePath()
            m.move(to: CGPoint(x: p.x - s, y: p.y - s)); m.addLine(to: CGPoint(x: p.x + s, y: p.y + s))
            m.move(to: CGPoint(x: p.x - s, y: p.y + s)); m.addLine(to: CGPoint(x: p.x + s, y: p.y - s))
            ghostMark.metresPath = m
        } else {
            ghost.points = []
            ghostMark.metresPath = nil
        }
        #if DEBUG
        // Screenshot helper: hold a sample aim so the gauge can be checked.
        if UserDefaults.standard.bool(forKey: "previewAim") {
            run(.wait(forDuration: 0.6)) { [weak self] in
                guard let self else { return }
                let start = CGPoint(x: self.size.width * 0.6, y: self.size.height * 0.5)
                self.touchStart = start
                self.updateAim(CGPoint(x: start.x - 140 * self.archers[shooter].facing, y: start.y + 70))
            }
        }
        #endif
    }

    func endHumanAim() {
        aimEnabled = false
        touchStart = nil
        angleLabel.isHidden = true
        powerRing.isHidden = true
        unpin(angleLabel)
        unpin(powerRing)
        aimGuide.points = []
    }

    /// Timer ran out (A6.11): auto-shot with power 0.
    func autoShot() {
        guard aimEnabled else { return }
        let angle = currentInput?.angleTenths ?? 200
        release(ShotInput(angleTenths: angle, powerPermille: 0))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard aimEnabled, !isGamePaused, touchStart == nil, let t = touches.first, let view else { return }
        touchStart = t.location(in: view)
        lastPowerTick = -1
        controller?.services.haptics.grab()
        archers[aimShooter].setExpression(.focused)
        updateAim(t.location(in: view))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard aimEnabled, touchStart != nil, let t = touches.first, let view else { return }
        updateAim(t.location(in: view))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard aimEnabled, let start = touchStart, let t = touches.first, let view else { return }
        let p = t.location(in: view)
        let d = hypot(p.x - start.x, p.y - start.y)
        if d < CGFloat(appConfig.game.aim.deadZonePoints) || currentInput == nil {
            cancelAim()
            return
        }
        release(currentInput!)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancelAim()
    }

    private func cancelAim() {
        touchStart = nil
        currentInput = nil
        angleLabel.isHidden = true
        powerRing.isHidden = true
        unpin(angleLabel)
        unpin(powerRing)
        aimGuide.points = []
        archers[aimShooter].setExpression(.neutral)
        archers[aimShooter].setAim(angleDegrees: 20, power: 0, nockedArrow: true)
    }

    private func updateAim(_ p: CGPoint) {
        guard let start = touchStart, let controller else { return }
        // Drag vector in y-up screen space; the shot goes the opposite way.
        let dx = p.x - start.x
        let dy = -(p.y - start.y)
        let facing = archers[aimShooter].facing
        var angle = atan2(-dy, -dx * facing) * 180 / .pi
        let aim = appConfig.game.aim
        angle = min(max(angle, CGFloat(aim.minAngleTenths) / 10), CGFloat(aim.maxAngleTenths) / 10)
        let maxDrag = CGFloat(aim.maxDragFractionOfScreenHeight) * size.height
        let power = min(1, hypot(dx, dy) / maxDrag)
        let input = ShotInput.quantise(angleDegrees: Double(angle), power: Double(power), aim: aim)
        currentInput = input
        archers[aimShooter].setAim(angleDegrees: CGFloat(input.angleDegrees), power: CGFloat(input.power), nockedArrow: true)

        // One gauge — power as the ring, angle in the middle — pinned above and
        // behind the archer, where the arrow never goes (it flies forward).
        angleLabel.text = "\(Int(input.angleDegrees.rounded()))°"
        angleLabel.isHidden = false
        powerRing.isHidden = false
        powerRing.set(power: CGFloat(input.power))
        let feet = archers[aimShooter].position
        let anchor = CGPoint(x: feet.x, y: feet.y + 2.0 * archerScale)
        let gaugeOffset = CGPoint(x: -facing * 78, y: 62)
        pin(powerRing, at: anchor, offset: gaugeOffset)
        pin(angleLabel, at: anchor, offset: CGPoint(x: gaugeOffset.x, y: gaugeOffset.y - 8))

        // Short aim guide: the first part of the real trajectory.
        let percent = appConfig.game.aim.aimGuidePercent
        if percent > 0 {
            let o = controller.preview(input)
            let n = max(2, Int(Double(o.path.count) * percent / 100))
            aimGuide.points = stride(from: 0, to: min(n, o.path.count), by: 2).map { CGPoint(x: o.path[$0].x, y: o.path[$0].y) }
        }

        // Haptic tick and creak every 5 % of power (A6.2, A16).
        let tick = Int(input.power * 20)
        if tick != lastPowerTick {
            if lastPowerTick >= 0 && tick > 0 {
                controller.services.haptics.powerTick()
                if tick % 2 == 0 { controller.services.audio.play(.creak(power: input.power), volume: 0.7) }
            }
            lastPowerTick = tick
        }
    }

    private func release(_ input: ShotInput) {
        endHumanAim()
        unpin(angleLabel)
        unpin(powerRing)
        archers[aimShooter].setExpression(.neutral)
        controller?.humanReleased(input)
    }

    // MARK: - AI drawing animation

    func animateAIDraw(_ input: ShotInput, shooter: Int, duration: Double, completion: @escaping () -> Void) {
        let archer = archers[shooter]
        archer.setExpression(.focused)
        let startAngle: CGFloat = 10
        let target = CGFloat(input.angleDegrees)
        let targetPower = CGFloat(input.power)
        let pickup = min(0.5, duration * 0.35)
        let drawTime = max(0.4, duration - pickup)
        let draw = SKAction.customAction(withDuration: drawTime) { _, t in
            let k = min(1, t / CGFloat(drawTime))
            let e = k * k * (3 - 2 * k)
            // Settle on the angle, then draw the string back.
            let angle = startAngle + (target - startAngle) * min(1, e * 1.4)
            let power = targetPower * max(0, (e - 0.3) / 0.7)
            archer.setAim(angleDegrees: angle, power: power, nockedArrow: true)
        }
        archer.pickUp(to: startAngle, duration: pickup) {
            archer.run(draw) {
                archer.setExpression(.neutral)
                completion()
            }
        }
    }

    // MARK: - Shot playback

    func playShot(_ report: TurnReport, medals: [String] = [], completion: @escaping () -> Void) {
        pendingMedals = medals
        guard let services = controller?.services else { return }
        let shooter = archers[report.shooter]
        shooter.setAim(angleDegrees: CGFloat(report.input.angleDegrees), power: 0, nockedArrow: true)
        shooter.releaseShot()
        services.audio.play(.twang)
        services.audio.play(.whoosh, volume: 0.6)
        if controller?.humans.contains(report.shooter) == true { services.haptics.release() }
        showLastBreath(nil)

        let art = ArtLibrary.shared.arrow
        let arrow = art.makeSprite()
        arrow.zPosition = 25
        worldLayer.addChild(arrow)
        addSpeedLines(to: arrow)
        let trail = DottedPath()
        trail.strokeColor = .ink
        trail.zPosition = 24
        worldLayer.addChild(trail)
        trails.append(trail)
        if trails.count > 1 { trails.removeFirst().removeFromParent() }

        let path = report.outcome.path
        let peak = path.map(\.y).max() ?? 0
        flight = Flight(report: report, path: path, arrow: arrow, trail: trail, peakY: peak,
                        launch: path.first ?? .zero, completion: completion)
        cam.smoothTime = CGFloat(appConfig.camera.followSmoothing)
    }

    private func advanceFlight(dt: Double) {
        guard var f = flight else { return }
        let sps = Double(appConfig.game.physics.stepsPerSecond)
        f.time += dt * playbackRate
        f.frame += 1
        let maxIndex = Double(f.path.count - 1)
        let idx = min(f.time * sps, maxIndex)
        let i = Int(idx)
        let frac = idx - Double(i)
        let a = f.path[i]
        let b = f.path[min(i + 1, f.path.count - 1)]
        let pos = Vec2(a.x + (b.x - a.x) * frac, a.y + (b.y - a.y) * frac)
        let j = max(1, min(i + 1, f.path.count - 1))
        let v = Vec2((f.path[j].x - f.path[j - 1].x) * sps, (f.path[j].y - f.path[j - 1].y) * sps)

        // A light touch at the top of your own arrow's arc.
        if !f.passedApex && v.y < 0 {
            f.passedApex = true
            if controller?.humans.contains(f.report.shooter) == true { controller?.services.haptics.tap() }
        }
        f.arrow.position = CGPoint(x: pos.x, y: pos.y)
        checkChickenHit(at: f.arrow.position, vx: v.x, shooter: f.report.shooter)
        // A little fletching wobble in the first second, like a real arrow.
        let wobble = reduceMotion ? 0 : 0.05 * max(0, 1 - f.time) * sin(f.time * 38)
        f.arrow.zRotation = atan2(v.y, v.x) + wobble
        // Keep the flying arrow readable when zoomed out.
        let minLengthPoints: CGFloat = 64
        f.arrow.setScale(max(1, minLengthPoints * cam.metresPerPoint / CharacterArt.arrowLength))
        if f.frame % 3 == 0 {
            var pts = stride(from: 0, through: i, by: 4).map { CGPoint(x: f.path[$0].x, y: f.path[$0].y) }
            pts.append(CGPoint(x: pos.x, y: pos.y))
            f.trail.points = pts
        }

        // Camera follow (A6.8 state 2).
        let launch = f.launch
        let end = f.path.last ?? pos
        let span = abs(end.x - launch.x)
        let aimW = appConfig.camera.aimViewWidth
        let maxW = min(appConfig.camera.flightMaxViewWidth, max(aimW * 1.4, span * 1.1))
        var width: Double
        let ascending = v.y > 0
        if ascending {
            let k = min(1, max(0, (pos.y - launch.y) / max(1, f.peakY - launch.y)))
            width = aimW + (maxW - aimW) * (k * k * (3 - 2 * k))
            width = max(width, aimW + (maxW - aimW) * min(1, abs(pos.x - launch.x) / max(1, span * 0.5)))
        } else {
            let remaining = abs(end.x - pos.x)
            let k = min(1, remaining / 70)
            width = 34 + (maxW - 34) * k
        }
        let lead = Vec2(pos.x + v.x * 0.25, pos.y + v.y * 0.25)
        let h = width * Double(size.height / max(size.width, 1))
        let ground = conditions?.terrain.height(at: lead.x) ?? 0
        cam.targetWidth = CGFloat(width)
        cam.targetCenter = CGPoint(x: lead.x, y: max(lead.y, ground + 0.3 * h))

        if f.frame % 4 == 0 {
            controller?.updateFlight(path: f.path, index: i, distance: abs(pos.x - launch.x))
        }

        if idx >= maxIndex {
            flight = nil
            impact(f)
        } else {
            flight = f
        }
    }

    private func impact(_ f: Flight) {
        guard let controller, let c = conditions else { return }
        let services = controller.services
        let r = f.report
        let o = r.outcome
        let point = CGPoint(x: o.point.x, y: o.point.y)
        let angle = atan2(o.velocity.y, o.velocity.x)
        let target = 1 - r.shooter
        let targetFeet = c.archerPosition(target)
        let aspect = Double(size.height / max(size.width, 1))
        var hold = appConfig.camera.impactHoldSeconds
        controller.impactBegan()
        f.arrow.removeFromParent()

        // Impact framing (A6.8 state 3). Slow, settling moves: never whip.
        cam.smoothTime = reduceMotion ? 0.2 : 0.7

        switch o.impact {
        case let .archer(index, part):
            let victim = archers[index]
            victim.addStuckArrow(at: point, angle: angle)
            victim.react(to: part)
            controller.applyHealth(r.health)
            switch part {
            case .head: services.audio.play(.clang); services.audio.play(.bonk, volume: 0.6)
            case .body, .legs: services.audio.play(.thwack); services.audio.play(.grunt, volume: 0.8)
            }
            if controller.humans.contains(index) { services.haptics.tookHit() }
            // Your arrow found its mark: feel it land.
            else if controller.humans.contains(r.shooter) { services.haptics.thud() }
            if part == .head { services.haptics.headshot() }
            impactLines(at: point, count: part == .head ? 9 : 7, reach: part == .head ? 0.9 : 0.7)

            // Sticker slaps on beside the head, away from the incoming arrow.
            let behind = -victim.facing
            let sticker = HUD.damageSticker(r.damage)
            hud.addChild(sticker)
            let headTop = CGPoint(x: victim.position.x, y: victim.position.y + 1.9 * archerScale)
            pin(sticker, at: headTop, offset: CGPoint(x: behind * 58, y: 40))
            slap(sticker)
            // Then it zips up into the victim's health bar: the number goes where it counts.
            flyToHealthBar(sticker, player: index, after: 0.85)

            // A hand-written groan in front of the face.
            let groan: String
            switch part {
            case .head: groan = "bonk!"
            case .body: groan = "oof."
            case .legs: groan = "ow ow ow"
            }
            let note = HUD.label(groan, font: GameFont.hand, size: 24)
            hud.addChild(note)
            pin(note, at: headTop, offset: CGPoint(x: victim.facing * 70, y: 22))
            popIn(note)

            if index != target {
                showCallout("OOPS", medals: [])
            } else {
                showCallout(part == .head ? "HEADSHOT" : nil, medals: pendingMedals)
                archers[r.shooter].celebrate()
            }
            if part == .head && !reduceMotion { cam.shake(points: 4, duration: 0.2) }
            // Hits zoom in a little quicker so the reaction reads; still eased.
            cam.smoothTime = reduceMotion ? 0.2 : 0.38
            let width = appConfig.camera.impactViewWidth
            cam.targetWidth = CGFloat(width)
            cam.targetCenter = CGPoint(x: victim.position.x - victim.facing * width * 0.08,
                                       y: victim.position.y + 0.34 * width * aspect)
            hold += 0.5

        case .terrain, .obstacle:
            services.audio.play(o.impact == .terrain ? .thunkDirt : .thunkWood)
            // The arrow stays stuck where it landed (cap 20) and boings.
            let tip = CGPoint(x: point.x + cos(angle) * 0.2, y: point.y + sin(angle) * 0.2)
            let stuck = StuckArrow.make(tip: tip, angle: angle, wobble: !reduceMotion)
            stuck.zPosition = 9
            worldLayer.addChild(stuck)
            groundArrows.append(stuck)
            if groundArrows.count > 20 { groundArrows.removeFirst().removeFromParent() }
            if o.impact == .terrain { dirtPuff(at: point) }
            var startled = false
            for ch in chickens where !ch.isDead && abs(ch.position.x - point.x) < 4 {
                ch.panic(awayFrom: point.x)
                startled = true
            }
            if startled { services.haptics.flutter() }
            services.haptics.landed()
            impactLines(at: point, count: 4, reach: 0.5, upperOnly: true)

            if let near = r.nearMiss {
                showNearMiss(from: point, targetFeet: targetFeet, distance: near, target: target)
                services.audio.play(.ooh)
                if controller.humans.contains(target) { services.haptics.nearMiss() }
                let dx = abs(point.x - targetFeet.x)
                let width = max(appConfig.camera.impactViewWidth, dx * 1.6 + 14)
                cam.targetWidth = CGFloat(width)
                cam.targetCenter = CGPoint(x: (point.x + targetFeet.x) / 2, y: targetFeet.y + 0.34 * width * aspect)
            } else {
                // Settle gently on where it landed; no swing over to the target.
                let width = min(60, max(30, Double(cam.viewWidth) * 0.8))
                let ground = c.terrain.height(at: point.x)
                cam.targetWidth = CGFloat(width)
                cam.targetCenter = CGPoint(x: point.x, y: ground + 0.36 * width * aspect)
                if (r.missDistance ?? 0) > 15, cam.isVisible(world: CGPoint(x: targetFeet.x, y: targetFeet.y + 1)) {
                    archers[target].taunt()
                }
            }

        case .outOfBounds, .timeout:
            // Gone. Hold still for a beat, the target looks smug.
            archers[target].taunt()
            hold -= 0.3
        }

        run(.wait(forDuration: hold + 0.35)) { [weak self] in
            guard let self else { return }
            self.clearPinned()
            for a in self.archers { a.settle() }
            f.completion()
        }
    }

    // MARK: - Feedback

    /// Three little speed lines trailing the flying arrow (Flight mockup).
    private func addSpeedLines(to arrow: SKNode) {
        for (i, y) in [0.09, 0.0, -0.09].enumerated() {
            let l = InkShape()
            let p = CGMutablePath()
            let start = -0.12 - Double(i % 2) * 0.1
            p.move(to: CGPoint(x: start, y: y))
            p.addLine(to: CGPoint(x: start - 0.45, y: y))
            l.metresPath = p
            l.strokeColor = .ink
            l.lineCap = .round
            l.metresLineWidth = 0.022
            arrow.addChild(l)
        }
    }

    /// Short comic strokes radiating from an impact.
    private func impactLines(at p: CGPoint, count: Int, reach: CGFloat, upperOnly: Bool = false) {
        let w = 2.6 * cam.metresPerPoint
        let scale = max(1, cam.metresPerPoint * 40)
        for i in 0..<count {
            var a = CGFloat(i) / CGFloat(count) * 2 * .pi + .random(in: -0.2...0.2)
            if upperOnly { a = .pi * (0.15 + 0.7 * CGFloat(i) / CGFloat(max(1, count - 1))) }
            let r0 = 0.25 * scale, r1 = (0.25 + reach * CGFloat.random(in: 0.7...1)) * scale
            let l = InkShape()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: cos(a) * r0, y: sin(a) * r0))
            path.addLine(to: CGPoint(x: cos(a) * r1, y: sin(a) * r1))
            l.metresPath = path
            l.strokeColor = .ink
            l.lineCap = .round
            l.metresLineWidth = w
            l.position = p
            l.zPosition = 33
            worldLayer.addChild(l)
            let out = SKAction.move(by: CGVector(dx: cos(a) * 0.25 * scale, dy: sin(a) * 0.25 * scale), duration: 0.3)
            out.timingMode = .easeOut
            l.run(.sequence([.group([out, .sequence([.wait(forDuration: 0.18), .fadeOut(withDuration: 0.2)])]),
                             .removeFromParent()]))
        }
    }

    /// A few clods of dirt kicked up where the arrow lands.
    private func dirtPuff(at p: CGPoint) {
        guard !reduceMotion else { return }
        let scale = max(1, cam.metresPerPoint * 40)
        for _ in 0..<6 {
            let r = CGFloat.random(in: 0.05...0.11) * scale
            let clod = InkShape(circleOfRadiusMetres: r)
            clod.fillColor = .ink
            clod.strokeColor = .clear
            clod.position = p
            clod.zPosition = 33
            worldLayer.addChild(clod)
            let dx = CGFloat.random(in: -0.9...0.9) * scale
            let up = CGFloat.random(in: 0.4...0.9) * scale
            let arc = SKAction.customAction(withDuration: 0.45) { node, t in
                let k = t / 0.45
                node.position = CGPoint(x: p.x + dx * k, y: p.y + up * 4 * k * (1 - k))
                node.alpha = 1 - k * k
            }
            clod.run(.sequence([arc, .removeFromParent()]))
        }
    }

    /// Sticker slap: lands big and rotated, settles with a wobble, then drifts up.
    private func slap(_ node: SKNode) {
        guard !reduceMotion else { return }
        node.setScale(1.9)
        node.zRotation = -0.5
        node.alpha = 0
        node.run(.sequence([
            .group([.scale(to: 0.92, duration: 0.1), .rotate(toAngle: 0.22, duration: 0.1), .fadeIn(withDuration: 0.06)]),
            .group([.scale(to: 1, duration: 0.12), .rotate(toAngle: 0.14, duration: 0.12)]),
        ]))
    }

    private var pendingMedals: [String] = []

    /// Moves a pinned HUD node to the given player's health bar and fades it into it.
    private func flyToHealthBar(_ node: SKNode, player: Int, after delay: Double) {
        let insets = view?.safeAreaInsets ?? .zero
        let barX = player == 0
            ? -size.width / 2 + insets.left + 12 + 92
            : size.width / 2 - insets.right - 12 - 92
        let barY = size.height / 2 - insets.top - 10 - 32
        node.run(.sequence([
            .wait(forDuration: delay),
            .run { [weak self] in self?.unpin(node) },
            .group([
                .move(to: CGPoint(x: barX, y: barY), duration: reduceMotion ? 0.01 : 0.4),
                .scale(to: 0.45, duration: 0.4),
                .sequence([.wait(forDuration: 0.3), .fadeOut(withDuration: 0.15)]),
            ]),
            .removeFromParent(),
        ]))
    }

    /// Big word (HEADSHOT) plus rubber-stamped medals ("long shot", "2 in a row"),
    /// top-left, clear of the archers.
    private func showCallout(_ word: String?, medals: [String]) {
        let group = SKNode()
        let insets = view?.safeAreaInsets ?? .zero
        group.position = CGPoint(x: -size.width / 2 + insets.left + 150, y: size.height * 0.2)
        hud.addChild(group)
        var y: CGFloat = 0
        if let word {
            let l = HUD.label(word, font: GameFont.display, size: 56)
            group.addChild(l)
            popIn(l)
            y -= 52
        }
        for (i, medal) in medals.enumerated() {
            let stamp = SKNode()
            let text = HUD.label(medal, font: GameFont.hand, size: 22)
            let w = text.frame.width + 26, h: CGFloat = 36
            let box = SKShapeNode(rect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerRadius: 9)
            box.strokeColor = .ink
            box.lineWidth = 2.5
            box.fillColor = .paper
            stamp.addChild(box)
            stamp.addChild(text)
            stamp.position = CGPoint(x: CGFloat(i % 2 == 0 ? -10 : 14), y: y)
            stamp.zRotation = i % 2 == 0 ? -0.06 : 0.05
            group.addChild(stamp)
            if !reduceMotion {
                stamp.setScale(1.6)
                stamp.alpha = 0
                stamp.run(.sequence([.wait(forDuration: 0.25 + Double(i) * 0.18),
                                     .group([.scale(to: 1, duration: 0.1), .fadeIn(withDuration: 0.06)])]))
            }
            y -= 44
        }
        group.run(.sequence([.wait(forDuration: appConfig.camera.impactHoldSeconds + 0.6), .fadeOut(withDuration: 0.2),
                             .removeFromParent()]))
    }

    private func showNearMiss(from point: CGPoint, targetFeet: Vec2, distance: Double, target: Int) {
        // Hand-drawn measuring line from the arrow to the target (Near miss mockup).
        let y = min(point.y, targetFeet.y) - 0.5
        let edgeX = targetFeet.x + (point.x < targetFeet.x ? -0.2 : 0.2)
        let line = InkShape()
        let p = CGMutablePath()
        p.move(to: CGPoint(x: point.x, y: y)); p.addLine(to: CGPoint(x: edgeX, y: y))
        p.move(to: CGPoint(x: point.x, y: y - 0.25)); p.addLine(to: CGPoint(x: point.x, y: y + 0.25))
        p.move(to: CGPoint(x: edgeX, y: y - 0.25)); p.addLine(to: CGPoint(x: edgeX, y: y + 0.25))
        line.metresPath = p
        line.strokeColor = .ink
        line.metresLineWidth = 2.5 * cam.metresPerPoint
        line.lineCap = .round
        line.zPosition = 32
        worldLayer.addChild(line)
        line.run(.sequence([.wait(forDuration: appConfig.camera.impactHoldSeconds + 0.4), .removeFromParent()]))

        let label = HUD.label(String(format: "%.1f m", distance), font: GameFont.mono, size: 20)
        hud.addChild(label)
        pin(label, at: CGPoint(x: (point.x + edgeX) / 2, y: y), offset: CGPoint(x: 0, y: -18))

        let note = HUD.label(target == 1 ? "so close." : "phew.", font: GameFont.hand, size: 40)
        note.zRotation = 0.04
        note.position = CGPoint(x: -size.width / 2 + (view?.safeAreaInsets.left ?? 0) + 130, y: size.height * 0.16)
        hud.addChild(note)
        popIn(note)
        pinnedExtras.append(note)
        archers[target].relieved()
    }

    private var pinnedExtras: [SKNode] = []

    private func showLastBreath(_ shooter: Int?) {
        guard let shooter else {
            lastBreathLabel.isHidden = true
            unpin(lastBreathLabel)
            return
        }
        lastBreathLabel.isHidden = false
        let feet = archers[shooter].position
        pin(lastBreathLabel, at: CGPoint(x: feet.x, y: feet.y), offset: CGPoint(x: 0, y: -22))
    }

    /// Shows the "last breath" label under the AI when it replies at 0 health.
    func setLastBreath(_ shooter: Int?) { showLastBreath(shooter) }

    private func popIn(_ node: SKNode) {
        guard !reduceMotion else { return }
        node.setScale(0.3)
        node.run(.sequence([.scale(to: 1.12, duration: 0.12), .scale(to: 1, duration: 0.08)]))
    }

    private func pin(_ node: SKNode, at world: CGPoint, offset: CGPoint = .zero) {
        if let i = pinned.firstIndex(where: { $0.node === node }) {
            pinned[i].world = world
            pinned[i].offset = offset
        } else {
            pinned.append((node, world, offset))
        }
        let p = cam.hudPoint(world: world)
        node.position = CGPoint(x: p.x + offset.x, y: p.y + offset.y)
    }

    private func unpin(_ node: SKNode) {
        pinned.removeAll { $0.node === node }
    }

    private func clearPinned() {
        for (node, _, _) in pinned where node !== angleLabel && node !== lastBreathLabel {
            node.removeFromParent()
        }
        pinned.removeAll { $0.node !== angleLabel && $0.node !== lastBreathLabel }
        pinnedExtras.forEach { $0.removeFromParent() }
        pinnedExtras.removeAll()
    }

    // MARK: - Frame update

    override func update(_ currentTime: TimeInterval) {
        let dt = min(1.0 / 20, currentTime - (lastUpdate ?? currentTime))
        lastUpdate = currentTime
        guard !isGamePaused else { return }

        advanceFlight(dt: dt)
        cam.update(dt: CGFloat(dt))
        controller?.tick(dt: dt)

        let m = cam.metresPerPoint
        world?.updateLineWidths(metresPerPoint: m)
        aimGuide.update(metresPerPoint: m)
        ghost.update(metresPerPoint: m)
        ghostMark.metresLineWidth = 2 * m
        for t in trails { t.update(metresPerPoint: m) }
        for (node, w, o) in pinned {
            let p = cam.hudPoint(world: w)
            node.position = CGPoint(x: p.x + o.x, y: p.y + o.y)
        }
        if !chickens.isEmpty, let terrain = conditions?.terrain {
            for ch in chickens {
                ch.update(dt: dt, ground: { x in CGFloat(terrain.height(at: Double(x))) })
                ch.sign?.keepReadable(metresPerPoint: m, worldScale: archerScale)
            }
        }
        if let ambient {
            let view = CGRect(x: cam.center.x - cam.viewWidth / 2, y: cam.center.y - cam.viewHeight / 2,
                              width: cam.viewWidth, height: cam.viewHeight)
            let terrain = conditions?.terrain
            ambient.update(dt: dt, view: view, wind: controller?.windWorld ?? 0,
                           ground: { x in CGFloat(terrain?.height(at: Double(x)) ?? 0) }, metresPerPoint: m)
        }

        // Anchor the halftone grid to the world so dots move with camera pans.
        let origin = cam.hudPoint(world: .zero)
        let scale = view?.contentScaleFactor ?? UIScreen.main.scale
        let px = Float((origin.x + size.width / 2) * scale)
        let py = Float((size.height / 2 - origin.y) * scale)
        HalftoneShader.setOrigin(SIMD2(px, py))
    }
}
