import CoreGraphics
import LongbowCore

/// The two v1.0 characters (spec A4 "Characters").
enum ArcherLook: String, CaseIterable {
    /// Visor helmet (a hat), bushy brows, big halftone beard, black t-shirt, halftone trousers.
    case bjorn
    /// Egg-shaped head, comb-over, round specs, walrus moustache, striped jumper, black trousers.
    case gus

    var displayName: String { rawValue.capitalized }
    var defaultAvatar: Avatar { self == .bjorn ? .bjorn : .gus }
    var seed: UInt64 { self == .bjorn ? 0xB1 : 0x605 }
}

enum Expression: String, CaseIterable {
    case neutral, focused, hit, relieved, victorious, defeated
    /// Eyes shut for a blink (idle life).
    case blink
}

/// Code-drawn character parts, in metres relative to the feet, facing right.
/// Proportions follow the hitboxes in spec A6.4 (head centre 1.62 m).
enum CharacterArt {
    static let line: CGFloat = 0.026
    static let headCenter = CGPoint(x: 0.02, y: 1.64)
    static let headRadius: CGFloat = 0.25

    // MARK: Legs

    static let legsBounds = CGRect(x: -0.52, y: -0.04, width: 0.86, height: 1.2)

    static func drawLegs(_ c: inout InkCanvas, outfit: Int) {
        if outfit == AvatarArt.tigerFur { TigerArt.drawTail(&c) }
        for (x0, x1) in [(-0.17, -0.015), (0.015, 0.17)] as [(CGFloat, CGFloat)] {
            let leg = c.polygon([
                CGPoint(x: x0, y: 0.92), CGPoint(x: x1, y: 0.92),
                CGPoint(x: x1 - 0.01, y: 0.1), CGPoint(x: x0 + 0.01, y: 0.1),
            ])
            c.fillStroke(leg, fill: AvatarArt.trousers(outfit), width: line)
        }
        let shoe = AvatarArt.shoes(outfit)
        c.blob(InkCanvas.ellipsePoints(center: CGPoint(x: -0.08, y: 0.055), rx: 0.13, ry: 0.055, count: 10),
               fill: shoe, width: line)
        c.blob(InkCanvas.ellipsePoints(center: CGPoint(x: 0.13, y: 0.055), rx: 0.13, ry: 0.055, count: 10),
               fill: shoe, width: line)
    }

    // MARK: Body

    static let bodyBounds = CGRect(x: -0.34, y: 0.78, width: 0.68, height: 0.84)

    static func drawBody(_ c: inout InkCanvas, outfit: Int) {
        let pts = [
            CGPoint(x: -0.2, y: 0.88), CGPoint(x: -0.24, y: 1.2), CGPoint(x: -0.22, y: 1.46),
            CGPoint(x: -0.1, y: 1.53), CGPoint(x: 0.1, y: 1.53), CGPoint(x: 0.22, y: 1.46),
            CGPoint(x: 0.24, y: 1.2), CGPoint(x: 0.2, y: 0.88), CGPoint(x: 0, y: 0.86),
        ]
        let torso = c.path(pts, closed: true)
        c.fill(torso, AvatarArt.shirtPaint(outfit))
        AvatarArt.drawOutfitDetail(&c, outfit, torso: torso, top: 1.53, bottom: 0.88, halfWidth: 0.3)
        c.stroke(torso, width: line)
    }

    // MARK: Head

    static let headBounds = CGRect(x: -0.4, y: 0.9, width: 0.8, height: 1.16)

    static func drawHead(_ c: inout InkCanvas, _ look: ArcherLook, _ expr: Expression) {
        AvatarArt.draw(&c, look.defaultAvatar, expr)
    }

    /// Eyes for the expressions that override a face's own.
    static func expressionEyes(_ c: inout InkCanvas, _ e1: CGPoint, _ e2: CGPoint, _ expr: Expression) {
        AvatarArt.expressionEyes(&c, e1, e2, expr)
    }

    static func sweat(_ c: inout InkCanvas, _ p: CGPoint) {
        for (dx, dy, s) in [(0.0, 0.0, 1.0), (-0.05, -0.1, 0.75)] as [(CGFloat, CGFloat, CGFloat)] {
            let q = CGPoint(x: p.x + dx, y: p.y + dy)
            c.blob([CGPoint(x: q.x, y: q.y + 0.05 * s), CGPoint(x: q.x + 0.022 * s, y: q.y),
                    CGPoint(x: q.x, y: q.y - 0.022 * s), CGPoint(x: q.x - 0.022 * s, y: q.y)],
                   fill: .ink, width: 0)
        }
    }

    // MARK: Bow and arrow

    /// Bow in the bow-arm frame: grip at the origin, arm along +x.
    static let bowBounds = CGRect(x: -0.12, y: -0.68, width: 0.34, height: 1.36)
    static let bowTip = CGPoint(x: -0.06, y: 0.6)

    static func drawBow(_ c: inout InkCanvas) {
        c.line([CGPoint(x: bowTip.x, y: bowTip.y), CGPoint(x: 0.08, y: 0.38), CGPoint(x: 0.13, y: 0),
                CGPoint(x: 0.08, y: -0.38), CGPoint(x: bowTip.x, y: -bowTip.y)], width: 0.045)
    }

    /// Arrow pointing +x, tail at x = 0.
    static let arrowLength: CGFloat = 1.0
    static let arrowBounds = CGRect(x: -0.04, y: -0.09, width: 1.1, height: 0.18)

    static func drawArrow(_ c: inout InkCanvas) {
        c.line([CGPoint(x: 0.02, y: 0), CGPoint(x: 0.9, y: 0)], width: 0.03)
        c.blob([CGPoint(x: 1.0, y: 0), CGPoint(x: 0.86, y: 0.055), CGPoint(x: 0.89, y: 0),
                CGPoint(x: 0.86, y: -0.055)], fill: .ink, width: 0.012)
        for s in [1.0, -1.0] as [CGFloat] {
            let f = c.polygon([CGPoint(x: 0.0, y: 0), CGPoint(x: 0.06, y: 0.07 * s),
                               CGPoint(x: 0.2, y: 0.07 * s), CGPoint(x: 0.15, y: 0)], wobble: 0.003)
            c.fillStroke(f, fill: .medium, width: 0.014)
        }
    }

    // MARK: Portrait (front view in a circle) for menus

    static let portraitBounds = CGRect(x: -0.52, y: 1.08, width: 1.04, height: 1.04)
    /// Tight crop on the face, for small tiles in the face editor.
    static let faceBounds = CGRect(x: -0.37, y: 1.26, width: 0.78, height: 0.78)

    static func drawPortrait(_ c: inout InkCanvas, _ look: ArcherLook, _ expr: Expression, background: InkPaint?,
                             hat: Hat = .none, avatar: Avatar? = nil, bounds: CGRect = portraitBounds) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let rr = bounds.width / 2 - 0.03
        let clip = CGPath(ellipseIn: CGRect(x: center.x - rr, y: center.y - rr, width: rr * 2, height: rr * 2),
                          transform: nil)
        c.clipped(to: clip) { c in
            if let background { c.fill(clip, background) }
            // Shoulders in the chosen outfit.
            let face = avatar ?? look.defaultAvatar
            let shoulders = c.path(InkCanvas.ellipsePoints(center: CGPoint(x: 0, y: 1.06), rx: 0.33, ry: 0.36, count: 14),
                                   closed: true)
            c.fill(shoulders, AvatarArt.shirtPaint(face.wardrobe))
            AvatarArt.drawOutfitDetail(&c, face.wardrobe, torso: shoulders, top: 1.42, bottom: 0.84, halfWidth: 0.4)
            c.brushLoop(InkCanvas.ellipsePoints(center: CGPoint(x: 0, y: 1.06), rx: 0.33, ry: 0.36, count: 14), width: line * 0.9)
            AvatarArt.draw(&c, face, expr)
            PropsArt.drawHat(&c, hat)
        }
        c.brushLoop(InkCanvas.ellipsePoints(center: center, rx: rr, ry: rr, count: 20), width: 0.03)
    }
}
