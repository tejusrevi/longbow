import SpriteKit
import UIKit

/// Fonts for SpriteKit labels; falls back to system fonts until the Google
/// Fonts are bundled (see Resources/Fonts/README.md).
enum GameFont {
    static var display: String { available("ArchivoBlack-Regular") ?? "AvenirNext-Heavy" }
    static var mono: String { available("SpaceMono-Bold") ?? "Menlo-Bold" }
    static var hand: String { available("ShantellSansNormal-Medium") ?? "ChalkboardSE-Bold" }

    private static func available(_ name: String) -> String? {
        UIFont(name: name, size: 12) != nil ? name : nil
    }
}

@MainActor
enum HUD {
    static func label(_ text: String, font: String, size: CGFloat, color: UIColor = .ink) -> SKLabelNode {
        let l = SKLabelNode(text: text)
        l.fontName = font
        l.fontSize = size
        l.fontColor = color
        l.verticalAlignmentMode = .center
        l.horizontalAlignmentMode = .center
        return l
    }

    /// Black circle sticker with the damage (e.g. "−50"), slightly rotated.
    static func damageSticker(_ damage: Int) -> SKNode {
        let n = SKNode()
        let l = label("−\(damage)", font: GameFont.display, size: 18, color: .paper)
        // Grows with the text so "−100" never spills out.
        let r = max(24, l.frame.width / 2 + 9)
        let c = SKShapeNode(circleOfRadius: r)
        c.fillColor = .ink
        c.strokeColor = .clear
        n.addChild(c)
        n.addChild(l)
        n.zRotation = 0.18
        return n
    }

    /// Ring around the finger showing draw power (no number, spec A6.2).
    final class PowerRing: SKNode {
        private let track = SKShapeNode(circleOfRadius: 34)
        private let fill = SKShapeNode()
        private let center = SKShapeNode(circleOfRadius: 30)

        override init() {
            super.init()
            track.strokeColor = UIColor.ink.withAlphaComponent(0.25)
            track.lineWidth = 3
            addChild(track)
            fill.strokeColor = .ink
            fill.lineWidth = 4
            fill.lineCap = .round
            addChild(fill)
            // A paper disc so the angle number reads over anything behind it.
            center.fillColor = UIColor.paper.withAlphaComponent(0.92)
            center.strokeColor = .clear
            center.zPosition = -1
            addChild(center)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        func set(power: CGFloat) {
            let p = CGMutablePath()
            p.addArc(center: .zero, radius: 34, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi * max(0.001, power),
                     clockwise: true)
            fill.path = p
        }
    }
}

/// Dotted world-space polyline whose dot size stays constant on screen.
@MainActor
final class DottedPath: InkShape {
    var points: [CGPoint] = [] { didSet { rebuild() } }
    var dotPoints: CGFloat = 3
    var gapPoints: CGFloat = 9
    private var metresPerPoint: CGFloat = 0.03

    func update(metresPerPoint m: CGFloat) {
        guard abs(m - metresPerPoint) / m > 0.04 else { return }
        metresPerPoint = m
        rebuild()
    }

    private func rebuild() {
        guard points.count > 1 else { metresPath = nil; return }
        let base = CGMutablePath()
        base.addLines(between: points)
        let m = metresPerPoint
        metresPath = base.copy(dashingWithPhase: 0, lengths: [0.001, gapPoints * m])
        metresLineWidth = dotPoints * m
        lineCap = .round
    }
}

/// Shape node for world-space (metre) geometry. SpriteKit's antialiasing feather
/// is about one node unit wide, so tiny metre-sized strokes come out blurry; this
/// node stores geometry `k`× larger and scales itself down by `k`.
@MainActor
class InkShape: SKShapeNode {
    static let k: CGFloat = 64

    override init() {
        super.init()
        setScale(1 / Self.k)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    convenience init(metres path: CGPath) {
        self.init()
        setMetresPath(path)
    }

    convenience init(circleOfRadiusMetres r: CGFloat) {
        self.init()
        setMetresPath(CGPath(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r), transform: nil))
    }

    /// Geometry in metres. (A method backs it because `didSet` does not run
    /// from the class's own initialisers.)
    var metresPath: CGPath? {
        get { storedPath }
        set { setMetresPath(newValue) }
    }

    private var storedPath: CGPath?

    private func setMetresPath(_ p: CGPath?) {
        storedPath = p
        var t = CGAffineTransform(scaleX: Self.k, y: Self.k)
        path = p.flatMap { $0.copy(using: &t) }
    }

    /// Stroke width in metres.
    var metresLineWidth: CGFloat {
        get { lineWidth / Self.k }
        set { lineWidth = newValue * Self.k }
    }

    /// Positions are in the parent's (metre) space; nothing to convert.
}
