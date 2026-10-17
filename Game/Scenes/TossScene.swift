import SpriteKit

/// "Who shoots first?" The chicken decides. Both archers wait on the hill; the
/// chicken looks from one to the other, has a think (a peck), then dashes over
/// to whoever goes first. The winner is fixed by the match seed — the chicken
/// only delivers the news.
@MainActor
final class TossScene: SKScene {
    private let cam = SKCameraNode()
    private let boil: Bool
    private let fast: Bool
    private let avatars: [Avatar]
    private let hats: [Hat]
    private let winner: Int
    private var archers: [ArcherNode] = []
    private var chicken: ChickenNode?
    private var lines: [(InkShape, CGFloat)] = []
    private var lastTime: TimeInterval?
    private var started = false
    /// Every head-turn (for the tick sound).
    var onLook: (() -> Void)?
    /// The chicken has picked.
    var onDecided: (() -> Void)?

    static let viewWidth: CGFloat = 15
    static let archerX: CGFloat = 4.6

    init(size: CGSize, boil: Bool, fast: Bool, avatars: [Avatar], hats: [Hat], winner: Int) {
        self.boil = boil
        self.fast = fast
        self.avatars = avatars
        self.hats = hats
        self.winner = winner
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .paper
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        camera = cam
        addChild(cam)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func ground(_ x: CGFloat) -> CGFloat {
        0.18 * cos(x * 0.45) + 0.05 * sin(x * 1.7) - 0.18
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard size.width > 0 else { return }
        let m = Self.viewWidth / size.width
        cam.setScale(m)
        let h = Self.viewWidth * size.height / size.width
        // Ground a third of the way up the screen.
        cam.position = CGPoint(x: 0, y: h * 0.5 - h * 0.3)
        for (n, pts) in lines { n.metresLineWidth = pts * m }
    }

    override func didMove(to view: SKView) {
        guard !started else { return }
        started = true
        build()
        perform()
    }

    private func build() {
        let pts = stride(from: -14.0, through: 14.0, by: 0.2).map { CGPoint(x: $0, y: ground($0)) }
        let fill = CGMutablePath()
        fill.addLines(between: pts.map { CGPoint(x: $0.x, y: $0.y - 0.6) })
        fill.addLine(to: CGPoint(x: 14, y: -20)); fill.addLine(to: CGPoint(x: -14, y: -20)); fill.closeSubpath()
        let dots = InkShape(metres: fill)
        dots.fillColor = .white
        dots.fillShader = HalftoneShader.fill(density: 0.1)
        dots.strokeColor = .clear
        addChild(dots)
        let line = CGMutablePath()
        line.addLines(between: WorldNode.simplified(pts))
        let gl = InkShape(metres: line)
        gl.strokeColor = .ink
        gl.lineCap = .round
        gl.zPosition = 2
        addChild(gl)
        lines.append((gl, 3))

        let lib = ArtLibrary.shared
        for x in [-6.6, -2.4, 2.9, 6.8] as [CGFloat] {
            let tuft = lib.tuft.makeSprite()
            tuft.setScale(0.7)
            tuft.position = CGPoint(x: x, y: ground(x))
            tuft.zPosition = 3
            addChild(tuft)
        }
        let cloud = lib.cloud(dotted: true).makeSprite()
        cloud.setScale(0.18)
        cloud.position = CGPoint(x: 2.3, y: 2.6)
        addChild(cloud)

        for i in 0..<2 {
            let x = i == 0 ? -Self.archerX : Self.archerX
            let a = ArcherNode(look: i == 0 ? .bjorn : .gus, facing: i == 0 ? 1 : -1, boil: boil, lively: boil,
                               hat: hats[i], avatar: avatars[i])
            a.setScale(1.3)
            a.position = CGPoint(x: x, y: ground(x))
            a.zPosition = 5
            a.setAim(angleDegrees: ArcherNode.restAngle, power: 0, nockedArrow: false)
            addChild(a)
            archers.append(a)
        }

        let ch = ChickenNode(range: -Self.archerX...Self.archerX, boil: boil)
        ch.wanders = false
        ch.setScale(1.6)
        ch.position = CGPoint(x: 0, y: ground(0))
        ch.zPosition = 6
        addChild(ch)
        chicken = ch
        didChangeSize(size)
    }

    /// Look left, look right (quicker and quicker), a thoughtful peck, then go.
    private func perform() {
        guard let chicken else { return }
        let towardWinner: CGFloat = winner == 0 ? -1 : 1
        var steps: [SKAction] = []
        if !fast {
            steps.append(.wait(forDuration: 0.45))
            let gaps: [Double] = [0.42, 0.36, 0.3, 0.24, 0.2, 0.28, 0.4]
            for (i, gap) in gaps.enumerated() {
                let dir: CGFloat = i % 2 == 0 ? 1 : -1
                steps.append(.run { [weak self] in chicken.look(dir); self?.onLook?() })
                steps.append(.wait(forDuration: gap))
            }
            steps.append(.run { chicken.peck() })
            steps.append(.wait(forDuration: 0.5))
            steps.append(.run { chicken.look(towardWinner) })
            steps.append(.wait(forDuration: 0.25))
        }
        let stopX = towardWinner * (Self.archerX - 1.2)
        steps.append(.run { [weak self] in
            chicken.dash(to: stopX, speed: self?.fast == true ? 40 : 5.5) {
                guard let self else { return }
                self.archers[self.winner].celebrate()
                self.archers[1 - self.winner].relieved()
                self.onDecided?()
            }
        })
        run(.sequence(steps))
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = min(0.1, currentTime - (lastTime ?? currentTime))
        lastTime = currentTime
        chicken?.update(dt: dt, ground: { [unowned self] x in self.ground(x) })
        let origin = CGPoint(x: (0 - cam.position.x) / cam.xScale, y: (0 - cam.position.y) / cam.yScale)
        let screenScale = view?.contentScaleFactor ?? 2
        HalftoneShader.setOrigin(SIMD2(Float((origin.x + size.width / 2) * screenScale),
                                       Float((size.height / 2 - origin.y) * screenScale)))
    }
}
