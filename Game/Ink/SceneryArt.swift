import CoreGraphics
import LongbowCore

/// Code-drawn scenery, in metres. Origins are at the object's base unless noted.
enum SceneryArt {
    static let line: CGFloat = 0.12

    // Tree matching the obstacle hitbox (canopy r 2.3 at 5.6 m, trunk to 4 m).
    static let treeBounds = CGRect(x: -2.9, y: -0.6, width: 5.8, height: 9.2)

    static func drawTree(_ c: inout InkCanvas) {
        c.line([CGPoint(x: 0, y: -0.4), CGPoint(x: 0.05, y: 2), CGPoint(x: 0, y: 4.2)], width: 0.2)
        c.line([CGPoint(x: 0.02, y: 2.6), CGPoint(x: -0.9, y: 3.6), CGPoint(x: -1.1, y: 4.3)], width: 0.16)
        c.line([CGPoint(x: 0.04, y: 3), CGPoint(x: 0.8, y: 3.9), CGPoint(x: 0.9, y: 4.3)], width: 0.16)
        // Bumpy canopy.
        var pts: [CGPoint] = []
        let n = 9
        for i in 0..<n {
            let a0 = CGFloat(i) / CGFloat(n) * 2 * .pi
            let a1 = (CGFloat(i) + 0.5) / CGFloat(n) * 2 * .pi
            pts.append(CGPoint(x: 2.2 * cos(a0), y: 5.6 + 2.2 * sin(a0)))
            pts.append(CGPoint(x: 2.6 * cos(a1), y: 5.6 + 2.6 * sin(a1)))
        }
        c.blob(pts, fill: .light, width: line)
    }

    static let rockBounds = CGRect(x: -1.5, y: -0.6, width: 3, height: 2.2)

    static func drawRock(_ c: inout InkCanvas) {
        c.blob([CGPoint(x: -1.2, y: -0.3), CGPoint(x: -1.05, y: 0.6), CGPoint(x: -0.3, y: 1.3),
                CGPoint(x: 0.6, y: 1.2), CGPoint(x: 1.2, y: 0.4), CGPoint(x: 1.15, y: -0.3)],
               fill: .medium, width: line)
        c.line([CGPoint(x: -0.4, y: 0.9), CGPoint(x: 0.1, y: 0.5), CGPoint(x: 0.5, y: 0.7)], width: line * 0.8)
    }

    static let wallBounds = CGRect(x: -1.0, y: -0.6, width: 2.0, height: 6.8)

    static func drawWall(_ c: inout InkCanvas) {
        let p = c.polygon([CGPoint(x: -0.8, y: -0.5), CGPoint(x: -0.8, y: 6), CGPoint(x: 0.8, y: 6),
                           CGPoint(x: 0.8, y: -0.5)])
        c.fillStroke(p, fill: .medium, width: line)
    }

    /// Cloud centred at the origin, ~6 m wide.
    static let cloudBounds = CGRect(x: -3.4, y: -1.0, width: 6.8, height: 3.2)

    static func drawCloud(_ c: inout InkCanvas, dotted: Bool) {
        let pts = [
            CGPoint(x: -3.0, y: -0.6), CGPoint(x: -3.1, y: 0.1), CGPoint(x: -2.4, y: 0.7),
            CGPoint(x: -1.6, y: 1.5), CGPoint(x: -0.6, y: 1.2), CGPoint(x: 0.4, y: 1.9),
            CGPoint(x: 1.6, y: 1.4), CGPoint(x: 2.2, y: 0.6), CGPoint(x: 3.0, y: 0.2),
            CGPoint(x: 3.0, y: -0.6),
        ]
        c.blob(pts, fill: dotted ? .light : .paper, width: 0.14)
    }

    static let sunBounds = CGRect(x: -4.2, y: -4.2, width: 8.4, height: 8.4)

    static func drawSun(_ c: inout InkCanvas) {
        c.circle(.zero, 4, fill: .medium, width: 0.12, count: 18)
    }

    static let tuftBounds = CGRect(x: -0.4, y: -0.1, width: 0.8, height: 0.7)

    static func drawTuft(_ c: inout InkCanvas) {
        c.line([CGPoint(x: -0.15, y: 0), CGPoint(x: -0.25, y: 0.5)], width: 0.06)
        c.line([CGPoint(x: 0.05, y: 0), CGPoint(x: 0.18, y: 0.45)], width: 0.06)
    }

    static let stoneBounds = CGRect(x: -0.5, y: -0.1, width: 1.0, height: 0.6)

    static func drawStone(_ c: inout InkCanvas) {
        c.blob([CGPoint(x: -0.35, y: 0), CGPoint(x: -0.2, y: 0.32), CGPoint(x: 0.2, y: 0.35),
                CGPoint(x: 0.35, y: 0)], fill: .paper, width: 0.06)
    }
}
