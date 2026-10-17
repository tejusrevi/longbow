import LongbowCore
import SpriteKit

/// The title-screen illustration: a William Tell gag. Bjorn takes careful aim
/// at an apple balanced on Gus's head; Gus sweats. Now and then a few birds
/// cross the sky, and leaves blow through. The scene fills the whole screen;
/// the menu sits on top of its left side.
@MainActor
final class HomeScene: SKScene {
    private let cam = SKCameraNode()
    private let boil: Bool
    private var built = false
    private var lines: [(InkShape, CGFloat)] = []
    private var bjorn: ArcherNode?
    private var hat: Hat
    private var flockTimer: Double = 3.0
    private var leafTimer: Double = 0.3
    private var leaves: [WindLeaf] = []
    /// A steady breeze from the left on the title screen.
    private let breeze = 2.5
    private var lastTime: TimeInterval?

    private var avatar: Avatar
    private var chicken: ChickenNode?
    /// Someone poked the chicken (for a haptic flutter).
    var onChickenPoked: (() -> Void)?

    init(size: CGSize, boil: Bool, hat: Hat, avatar: Avatar) {
        self.boil = boil
        self.hat = hat
        self.avatar = avatar
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .paper
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        camera = cam
        addChild(cam)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Visible world across the full screen; Bjorn at x = 0 sits a little left
    /// of centre, Gus well inside the right edge.
    private let viewWidth: CGFloat = 24
    private let scale: CGFloat = 1.3

    func setHat(_ newHat: Hat) {
        hat = newHat
        bjorn?.setHat(newHat)
    }

    func setAvatar(_ newAvatar: Avatar) {
        avatar = newAvatar
        bjorn?.setAvatar(newAvatar)
    }

    override func didMove(to view: SKView) {
        build()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        layoutCamera()
    }

    private var viewRect: CGRect {
        let h = viewWidth * size.height / max(size.width, 1)
        return CGRect(x: cam.position.x - viewWidth / 2, y: cam.position.y - h / 2, width: viewWidth, height: h)
    }

    private func layoutCamera() {
        guard size.width > 0 else { return }
        let m = viewWidth / size.width
        cam.setScale(m)
        let h = viewWidth * size.height / size.width
        // Bjorn just right of the menu column (~54 % across), Gus well clear of
        // the right edge and its safe area.
        cam.position = CGPoint(x: -viewWidth * 0.04, y: h * 0.5 - 1.6)
        for (n, pts) in lines { n.metresLineWidth = pts * m }
    }

    private func ground(_ x: CGFloat) -> CGFloat {
        0.35 * cos(x * 0.33) + 0.08 * sin(x * 1.3) - 0.25 + (x > 7 ? (x - 7) * 0.05 : 0)
    }

    private func build() {
        guard !built else { return }
        built = true
        let lib = ArtLibrary.shared

        let pts = stride(from: -20.0, through: 24.0, by: 0.2).map { CGPoint(x: $0, y: ground($0)) }
        let fill = CGMutablePath()
        fill.addLines(between: pts.map { CGPoint(x: $0.x, y: $0.y - 0.7) })
        fill.addLine(to: CGPoint(x: 24, y: -30)); fill.addLine(to: CGPoint(x: -20, y: -30)); fill.closeSubpath()
        let dots = InkShape(metres: fill)
        dots.fillColor = .white
        dots.fillShader = HalftoneShader.fill(density: 0.1)
        dots.strokeColor = .clear
        dots.zPosition = 1
        addChild(dots)

        let line = CGMutablePath()
        line.addLines(between: WorldNode.simplified(pts))
        let gl = InkShape(metres: line)
        gl.strokeColor = .ink
        gl.lineCap = .round
        gl.zPosition = 2
        addChild(gl)
        lines.append((gl, 3))

        let gusX: CGFloat = 7.6
        let b = ArcherNode(look: .bjorn, facing: 1, boil: boil, lively: boil, hat: hat, avatar: avatar)
        b.setScale(scale)
        b.position = CGPoint(x: 0, y: ground(0))
        b.zPosition = 5
        addChild(b)
        bjorn = b
        // Careful aim, half drawn, with the occasional nervous re-aim.
        b.setAim(angleDegrees: 12, power: 0.75, nockedArrow: true)
        b.setExpression(.focused)
        if boil {
            let reaim = SKAction.customAction(withDuration: 2.4) { _, t in
                let k = t / 2.4
                b.setAim(angleDegrees: 12 + 2 * sin(k * .pi * 2), power: 0.7 + 0.12 * sin(k * .pi), nockedArrow: true)
            }
            b.run(.repeatForever(.sequence([reaim, .wait(forDuration: 1.2)])))
        }

        let gus = ArcherNode(look: .gus, facing: -1, boil: boil, lively: boil)
        gus.setScale(scale)
        gus.position = CGPoint(x: gusX, y: ground(gusX))
        gus.zPosition = 5
        gus.relieved()
        gus.setExpression(.relieved)
        addChild(gus)

        // The apple, balanced on Gus's hood, wobbling a little.
        let appleArt = lib.apple(pierced: false)
        let apple = appleArt.makeSprite()
        apple.setScale(1.1)
        apple.position = CGPoint(x: gusX, y: ground(gusX) + 2.05 * scale)
        apple.zPosition = 6
        apple.startBoil(appleArt.textures, enabled: boil)
        addChild(apple)

        // Dotted arc from bow to apple: a real ballistic curve that leaves the
        // bow at its aim angle and drops gently onto the apple.
        let arc = DottedPath()
        let a = CGPoint(x: 1.3, y: ground(0) + 1.95), z = CGPoint(x: gusX - 0.25, y: apple.position.y + 0.25)
        let span = z.x - a.x
        let slope = tan(12 * CGFloat.pi / 180)
        let drop = (slope * span - (z.y - a.y)) / (span * span)
        arc.points = (0...40).map { i in
            let dx = span * CGFloat(i) / 40
            return CGPoint(x: a.x + dx, y: a.y + slope * dx - drop * dx * dx)
        }
        arc.strokeColor = .ink
        arc.zPosition = 4
        arc.dotPoints = 3.2
        arc.gapPoints = 9
        addChild(arc)
        arc.update(metresPerPoint: viewWidth / max(size.width, 1))

        let sun = lib.sun.makeSprite()
        sun.setScale(0.18)
        sun.position = CGPoint(x: 4.6, y: 6.6)
        addChild(sun)

        for (x, y, s) in [(1.2, 6.2, 0.24), (9.6, 4.4, 0.16)] as [(CGFloat, CGFloat, CGFloat)] {
            let art = lib.cloud(dotted: s < 0.2)
            let cloud = art.makeSprite()
            cloud.setScale(s)
            cloud.position = CGPoint(x: x, y: y)
            cloud.startBoil(art.textures, enabled: boil)
            addChild(cloud)
            if boil {
                let drift = SKAction.moveBy(x: 1.6, y: 0, duration: .random(in: 14...22))
                drift.timingMode = .easeInEaseOut
                cloud.run(.repeatForever(.sequence([drift, drift.reversed()])))
            }
        }

        let target = lib.target.makeSprite()
        target.setScale(0.9)
        target.position = CGPoint(x: 3.9, y: ground(3.9) - 0.05)
        target.zPosition = 3
        target.startBoil(lib.target.textures, enabled: boil)
        addChild(target)
        // Two arrows already in the target: practice went "fine".
        for (dx, dy, ang) in [(-0.15, 1.3, 0.35), (0.25, 0.85, -0.2)] as [(CGFloat, CGFloat, CGFloat)] {
            let s = StuckArrow.make(tip: CGPoint(x: target.position.x + dx, y: target.position.y + dy),
                                    angle: ang, wobble: false)
            s.xScale = 0.8; s.yScale = 0.8
            s.zPosition = 4
            addChild(s)
        }

        // The chicken, pottering about between the target and Gus, oblivious.
        let ch = ChickenNode(range: 4.9...6.6, boil: boil)
        ch.setScale(1.75)
        ch.position = CGPoint(x: 5.6, y: ground(5.6))
        ch.zPosition = 4.5
        addChild(ch)
        chicken = ch

        for x in [-8.0, -4.4, 2.2, 5.8, 10.2] as [CGFloat] {
            let tuft = lib.tuft.makeSprite()
            tuft.setScale(0.7)
            tuft.position = CGPoint(x: x, y: ground(x))
            tuft.startBoil(lib.tuft.textures, enabled: boil)
            addChild(tuft)
            if boil {
                let sway = SKAction.rotate(byAngle: 0.15, duration: .random(in: 1.1...1.6))
                sway.timingMode = .easeInEaseOut
                tuft.run(.repeatForever(.sequence([sway, sway.reversed()])))
            }
        }

        layoutCamera()
    }

    /// Poke the chicken.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let chicken, let t = touches.first else { return }
        let p = t.location(in: self)
        if hypot(p.x - chicken.position.x, p.y - (chicken.position.y + 0.4)) < 1.0 {
            chicken.panic(awayFrom: p.x + (p.x < chicken.position.x ? -0.1 : 0.1))
            onChickenPoked?()
        }
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = min(0.1, currentTime - (lastTime ?? currentTime))
        lastTime = currentTime
        let origin = CGPoint(x: (0 - cam.position.x) / cam.xScale, y: (0 - cam.position.y) / cam.yScale)
        let screenScale = view?.contentScaleFactor ?? 2
        HalftoneShader.setOrigin(SIMD2(Float((origin.x + size.width / 2) * screenScale),
                                       Float((size.height / 2 - origin.y) * screenScale)))
        guard built else { return }
        chicken?.update(dt: dt, ground: { [unowned self] x in self.ground(x) })
        guard boil else { return }
        flockTimer -= dt
        if flockTimer <= 0 {
            flockTimer = .random(in: 12...20)
            AmbientLayer.spawnFlock(into: self, in: viewRect, scale: 0.6, band: 0.6...0.72)
        }
        leafTimer -= dt
        if leafTimer <= 0 {
            leafTimer = .random(in: 1.0...2.2)
            if leaves.count < 5 {
                leaves.append(WindLeaf(into: self, view: viewRect, wind: breeze, ground: { [unowned self] x in self.ground(x) },
                                       scale: 0.7))
            }
        }
        let view = viewRect
        leaves.removeAll { !$0.step(dt: dt, view: view, wind: breeze, ground: { [unowned self] x in self.ground(x) }) }
    }
}
