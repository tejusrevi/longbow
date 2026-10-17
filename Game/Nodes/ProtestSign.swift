import SpriteKit
import UIKit

/// A chicken's protest placard: hand-lettered on scrap card, nailed to an
/// arrow it found in the field. The card is sized to its slogan (long ones
/// wrap onto two lines), and it grows when the camera pulls back so the
/// words stay readable.
@MainActor
final class ProtestSign: SKNode {
    static let slogans = [
        "Make Cluck, Not War", "Fowl Play!", "Cluck Around, Find Out", "Don’t Be Fowl",
        "Chickens Against Archery", "Stop Shooting Poultry", "Hit Targets, Not Chickens",
        "This Is Eggregious", "Henough Is Henough!", "I Demand Egguality",
    ]
    private static var recent: [String] = []

    /// A slogan nobody has waved this match yet, if possible.
    static func nextSlogan() -> String {
        let fresh = slogans.filter { !recent.contains($0) }
        let pick = (fresh.isEmpty ? slogans : fresh).randomElement()!
        recent.append(pick)
        if recent.count > 6 { recent.removeFirst() }
        return pick
    }

    let text: String
    private let board = SKNode()
    /// Text height in metres at scale 1 (chicken-local).
    private static let letterHeight: CGFloat = 0.075
    private static let fontPoints: CGFloat = 64

    init(text: String) {
        self.text = text
        super.init()

        // The pole: a stray arrow, point stuck in the dirt, fletching just
        // under the card.
        let arrow = ArtLibrary.shared.arrow.makeSprite()
        arrow.zRotation = -.pi / 2
        arrow.position = CGPoint(x: 0, y: 0.82)
        arrow.setScale(0.87)
        arrow.zPosition = 0
        addChild(arrow)

        board.position = CGPoint(x: 0, y: 0.92)
        board.zPosition = 1
        addChild(board)

        // Lettering, rendered big and scaled down so it stays crisp.
        let label = SKLabelNode()
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineSpacing = -6
        label.attributedText = NSAttributedString(string: text, attributes: [
            .font: UIFont(name: GameFont.hand, size: Self.fontPoints) ?? .systemFont(ofSize: Self.fontPoints, weight: .bold),
            .foregroundColor: UIColor.ink,
            .paragraphStyle: para,
        ])
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.preferredMaxLayoutWidth = Self.fontPoints * 9.5
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        let s = Self.letterHeight / Self.fontPoints
        label.setScale(s)
        label.zPosition = 2

        let size = CGSize(width: label.frame.width + 0.09, height: label.frame.height + 0.07)
        // A slightly wonky card, cut by hand.
        let w = size.width / 2, h = size.height / 2
        let card = CGMutablePath()
        card.move(to: CGPoint(x: -w - 0.01, y: -h + 0.01))
        card.addLine(to: CGPoint(x: w + 0.012, y: -h - 0.008))
        card.addLine(to: CGPoint(x: w - 0.006, y: h + 0.01))
        card.addLine(to: CGPoint(x: -w + 0.008, y: h - 0.006))
        card.closeSubpath()
        let shape = InkShape(metres: card)
        shape.fillColor = .paper
        shape.strokeColor = .ink
        shape.metresLineWidth = 0.018
        shape.lineJoin = .round
        shape.zPosition = 1
        board.addChild(shape)
        board.addChild(label)
        // Two nails where it's fixed to the arrow.
        for y in [h * 0.55, -h * 0.55] {
            let nail = InkShape(circleOfRadiusMetres: 0.009)
            nail.fillColor = .ink
            nail.strokeColor = .clear
            nail.position = CGPoint(x: 0, y: y)
            nail.zPosition = 3
            board.addChild(nail)
        }
        board.zRotation = CGFloat.random(in: -0.06...0.06)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Waving the sign up and down, like a chant.
    func startChanting() {
        guard action(forKey: "chant") == nil else { return }
        let up = SKAction.group([.moveBy(x: 0, y: 0.08, duration: 0.22), .rotate(byAngle: 0.05, duration: 0.22)])
        up.timingMode = .easeOut
        let down = up.reversed()
        down.timingMode = .easeIn
        run(.repeatForever(.sequence([up, down, up, down, .wait(forDuration: .random(in: 0.8...1.6))])), withKey: "chant")
    }

    func stopChanting() {
        removeAction(forKey: "chant")
    }

    /// Keeps the words at least `minPoints` tall on screen.
    func keepReadable(metresPerPoint m: CGFloat, worldScale: CGFloat, minPoints: CGFloat = 8) {
        let onScreen = Self.letterHeight * worldScale / max(m, 0.0001)
        let k = min(2, max(1, minPoints / max(onScreen, 0.01)))
        if abs(board.xScale - k) > 0.03 { board.setScale(k) }
    }

    /// Shot down with the chicken: the sign topples.
    func topple(direction: CGFloat) {
        stopChanting()
        run(.group([.rotate(toAngle: -direction * 1.35, duration: 0.45, shortestUnitArc: true),
                    .moveBy(x: direction * 0.4, y: -0.3, duration: 0.45)]))
    }
}
