import CoreGraphics

/// Hats (spec A14). Cosmetic only, never gameplay.
enum Hat: String, CaseIterable, Codable, Identifiable {
    case none, visor, featherCap, hornedHelmet, cookingPot, topHat, crown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "No hat"
        case .visor: return "Visor helmet"
        case .featherCap: return "Feather cap"
        case .hornedHelmet: return "Horned helmet"
        case .cookingPot: return "Cooking pot"
        case .topHat: return "Top hat"
        case .crown: return "Crown"
        }
    }

    /// How it's earned (A12.3 levels; the crown is a challenge reward).
    enum Unlock: Equatable {
        case level(Int)
        case beatHardGus(times: Int)
    }

    var unlock: Unlock {
        switch self {
        case .none: return .level(1)
        case .visor: return .level(2)
        case .featherCap: return .level(3)
        case .hornedHelmet: return .level(7)
        case .cookingPot: return .level(9)
        case .topHat: return .level(20)
        case .crown: return .beatHardGus(times: 3)
        }
    }

    var unlockText: String {
        switch unlock {
        case let .level(l): return l <= 1 ? "" : "level \(l)"
        case let .beatHardGus(t): return "beat hard Gus \(t)×"
        }
    }

    /// Sound when an arrow hits it.
    var isMetal: Bool { self == .visor || self == .hornedHelmet || self == .cookingPot || self == .crown }
}

/// Quirky real-world props, drawn in metres. Origins noted per item.
enum PropsArt {
    static let line: CGFloat = 0.032

    // MARK: Hats — drawn in head coordinates (same space as `CharacterArt.drawHead`).

    static let hatBounds = CGRect(x: -0.55, y: 1.45, width: 1.1, height: 0.95)

    static func drawHat(_ c: inout InkCanvas, _ hat: Hat) {
        let h = CharacterArt.headCenter, r = CharacterArt.headRadius
        switch hat {
        case .none:
            break // your own hair shows (hair is part of your face)

        case .visor:
            // Round helmet down to the nose, with a barred visor slit and a plume.
            let dome = c.path([
                CGPoint(x: h.x - r - 0.02, y: h.y - 0.03), CGPoint(x: h.x - r - 0.01, y: h.y + 0.12),
                CGPoint(x: h.x - 0.14, y: h.y + r + 0.02), CGPoint(x: h.x + 0.06, y: h.y + r + 0.05),
                CGPoint(x: h.x + r - 0.02, y: h.y + 0.16), CGPoint(x: h.x + r + 0.02, y: h.y - 0.03),
            ], closed: true)
            c.fillStroke(dome, fill: .paper, width: line)
            let vx0 = h.x - 0.13, vx1 = h.x + r + 0.02, vy0 = h.y + 0.0, vy1 = h.y + 0.09
            let visor = c.polygon([CGPoint(x: vx0, y: vy0), CGPoint(x: vx1, y: vy0),
                                   CGPoint(x: vx1, y: vy1), CGPoint(x: vx0, y: vy1)], wobble: 0.004)
            c.fillStroke(visor, fill: .ink, width: line * 0.6)
            var x = vx0 + 0.035
            while x < vx1 - 0.02 {
                c.line([CGPoint(x: x, y: vy0 + 0.015), CGPoint(x: x, y: vy1 - 0.015)], width: line * 0.5, paint: .paper)
                x += 0.04
            }
            c.dot(CGPoint(x: h.x - 0.19, y: h.y + 0.05), 0.016) // rivet
            // Plume.
            c.blob([CGPoint(x: h.x - 0.02, y: h.y + r + 0.03), CGPoint(x: h.x - 0.12, y: h.y + r + 0.2),
                    CGPoint(x: h.x - 0.3, y: h.y + r + 0.22), CGPoint(x: h.x - 0.2, y: h.y + r + 0.12),
                    CGPoint(x: h.x - 0.08, y: h.y + r + 0.02)], fill: .dense, width: line * 0.8)

        case .featherCap:
            // Robin Hood cap with a long feather.
            let cap = c.path([
                CGPoint(x: h.x - r - 0.03, y: h.y + 0.08), CGPoint(x: h.x - 0.36, y: h.y + 0.28),
                CGPoint(x: h.x - 0.12, y: h.y + r + 0.08), CGPoint(x: h.x + 0.16, y: h.y + r + 0.02),
                CGPoint(x: h.x + r + 0.08, y: h.y + 0.12), CGPoint(x: h.x + 0.05, y: h.y + 0.07),
            ], closed: true)
            c.fillStroke(cap, fill: .medium, width: line)
            c.line([CGPoint(x: h.x - r - 0.02, y: h.y + 0.09), CGPoint(x: h.x + r + 0.07, y: h.y + 0.12)], width: line)
            let quill = [CGPoint(x: h.x - 0.05, y: h.y + 0.16), CGPoint(x: h.x - 0.2, y: h.y + 0.42),
                         CGPoint(x: h.x - 0.42, y: h.y + 0.6)]
            c.blob([quill[0], CGPoint(x: h.x - 0.08, y: h.y + 0.36), CGPoint(x: h.x - 0.32, y: h.y + 0.62),
                    quill[2], CGPoint(x: h.x - 0.3, y: h.y + 0.42)], fill: .paper, width: line * 0.8)
            c.line(quill, width: line * 0.6)

        case .hornedHelmet:
            for s in [-1.0, 1.0] as [CGFloat] {
                c.blob([CGPoint(x: h.x + s * 0.17, y: h.y + 0.12), CGPoint(x: h.x + s * 0.33, y: h.y + 0.2),
                        CGPoint(x: h.x + s * 0.4, y: h.y + 0.42), CGPoint(x: h.x + s * 0.3, y: h.y + 0.3),
                        CGPoint(x: h.x + s * 0.18, y: h.y + 0.22)], fill: .paper, width: line)
            }
            let dome = c.path(InkCanvas.ellipsePoints(center: CGPoint(x: h.x, y: h.y + 0.06), rx: r + 0.03, ry: r + 0.02,
                                                      count: 12, from: 0, to: .pi), closed: true)
            c.fillStroke(dome, fill: .ink, width: line)
            c.line([CGPoint(x: h.x - r - 0.04, y: h.y + 0.06), CGPoint(x: h.x + r + 0.04, y: h.y + 0.06)], width: line * 2)

        case .cookingPot:
            // Upside-down pot, handle sticking out the back.
            let pot = c.polygon([CGPoint(x: h.x - r - 0.03, y: h.y + 0.04), CGPoint(x: h.x - r + 0.01, y: h.y + r + 0.1),
                                 CGPoint(x: h.x + r - 0.01, y: h.y + r + 0.1), CGPoint(x: h.x + r + 0.03, y: h.y + 0.04)],
                                wobble: 0.006)
            c.fillStroke(pot, fill: .dense, width: line)
            c.line([CGPoint(x: h.x - r - 0.06, y: h.y + 0.04), CGPoint(x: h.x + r + 0.06, y: h.y + 0.04)], width: line * 1.6)
            let handle = c.polygon([CGPoint(x: h.x - r + 0.02, y: h.y + 0.17), CGPoint(x: h.x - r - 0.32, y: h.y + 0.13),
                                    CGPoint(x: h.x - r - 0.32, y: h.y + 0.2), CGPoint(x: h.x - r + 0.02, y: h.y + 0.23)],
                                   wobble: 0.004)
            c.fillStroke(handle, fill: .ink, width: line * 0.6)
            c.circle(CGPoint(x: h.x - r - 0.27, y: h.y + 0.165), 0.018, fill: .paper, width: 0, count: 8)

        case .topHat:
            let crown = c.polygon([CGPoint(x: h.x - 0.17, y: h.y + 0.14), CGPoint(x: h.x - 0.19, y: h.y + 0.58),
                                   CGPoint(x: h.x + 0.19, y: h.y + 0.6), CGPoint(x: h.x + 0.17, y: h.y + 0.14)],
                                  wobble: 0.005)
            c.fillStroke(crown, fill: .ink, width: line)
            let band = c.polygon([CGPoint(x: h.x - 0.175, y: h.y + 0.17), CGPoint(x: h.x - 0.18, y: h.y + 0.25),
                                  CGPoint(x: h.x + 0.18, y: h.y + 0.25), CGPoint(x: h.x + 0.175, y: h.y + 0.17)],
                                 wobble: 0.003)
            c.fill(band, .paper)
            c.line([CGPoint(x: h.x - 0.32, y: h.y + 0.14), CGPoint(x: h.x + 0.33, y: h.y + 0.15)], width: line * 2.2)

        case .crown:
            let pts: [CGPoint] = [
                CGPoint(x: h.x - 0.22, y: h.y + 0.16), CGPoint(x: h.x - 0.25, y: h.y + 0.44),
                CGPoint(x: h.x - 0.12, y: h.y + 0.3), CGPoint(x: h.x, y: h.y + 0.48),
                CGPoint(x: h.x + 0.12, y: h.y + 0.3), CGPoint(x: h.x + 0.25, y: h.y + 0.44),
                CGPoint(x: h.x + 0.22, y: h.y + 0.16),
            ]
            c.fillStroke(c.polygon(pts, wobble: 0.004), fill: .paper, width: line)
            for x in [-0.25, 0.0, 0.25] as [CGFloat] {
                c.circle(CGPoint(x: h.x + x, y: h.y + (x == 0 ? 0.5 : 0.46)), 0.03, fill: .dense, width: line * 0.6, count: 8)
            }
            c.line([CGPoint(x: h.x - 0.22, y: h.y + 0.21), CGPoint(x: h.x + 0.22, y: h.y + 0.21)], width: line * 0.7)
        }
    }

    // MARK: Birds (origin = body centre, facing +x). Two flap frames.

    static let birdBounds = CGRect(x: -0.6, y: -0.45, width: 1.2, height: 0.9)

    static func drawBird(_ c: inout InkCanvas, wingsUp: Bool) {
        c.blob([CGPoint(x: -0.32, y: 0.02), CGPoint(x: -0.1, y: 0.12), CGPoint(x: 0.18, y: 0.1),
                CGPoint(x: 0.3, y: 0.02), CGPoint(x: 0.12, y: -0.1), CGPoint(x: -0.15, y: -0.08)],
               fill: .paper, width: 0.045)
        c.blob([CGPoint(x: 0.29, y: 0.04), CGPoint(x: 0.45, y: 0.0), CGPoint(x: 0.29, y: -0.02)], fill: .ink, width: 0.02)
        c.dot(CGPoint(x: 0.19, y: 0.05), 0.022)
        // Tail.
        c.blob([CGPoint(x: -0.3, y: 0.02), CGPoint(x: -0.5, y: 0.12), CGPoint(x: -0.46, y: -0.06)], fill: .ink, width: 0.02)
        // Wing.
        let tipY: CGFloat = wingsUp ? 0.42 : -0.36
        c.blob([CGPoint(x: -0.12, y: 0.04), CGPoint(x: -0.2, y: tipY), CGPoint(x: 0.08, y: tipY * 0.6),
                CGPoint(x: 0.1, y: 0.03)], fill: .medium, width: 0.04)
    }

    // MARK: Leaf (origin = centre). Tumbles on the wind.

    static let leafBounds = CGRect(x: -0.24, y: -0.14, width: 0.48, height: 0.28)

    static func drawLeaf(_ c: inout InkCanvas) {
        c.blob([CGPoint(x: -0.19, y: 0), CGPoint(x: -0.05, y: 0.1), CGPoint(x: 0.12, y: 0.08),
                CGPoint(x: 0.19, y: 0), CGPoint(x: 0.1, y: -0.08), CGPoint(x: -0.06, y: -0.09)], fill: .light, width: 0.02)
        c.line([CGPoint(x: -0.22, y: -0.01), CGPoint(x: 0.16, y: 0.0)], width: 0.015)
        c.line([CGPoint(x: -0.05, y: 0), CGPoint(x: 0.02, y: 0.06)], width: 0.01)
        c.line([CGPoint(x: 0.03, y: 0), CGPoint(x: 0.09, y: -0.05)], width: 0.01)
    }

    // MARK: Apple (origin = bottom centre). Optional arrow through it.

    static let appleBounds = CGRect(x: -0.75, y: -0.08, width: 1.5, height: 0.62)

    static func drawApple(_ c: inout InkCanvas, pierced: Bool) {
        let ctr = CGPoint(x: 0, y: 0.17)
        c.blob([CGPoint(x: 0, y: 0.31), CGPoint(x: 0.12, y: 0.33), CGPoint(x: 0.19, y: 0.2), CGPoint(x: 0.15, y: 0.05),
                CGPoint(x: 0.06, y: 0.0), CGPoint(x: 0, y: 0.02), CGPoint(x: -0.06, y: 0.0), CGPoint(x: -0.15, y: 0.05),
                CGPoint(x: -0.19, y: 0.2), CGPoint(x: -0.12, y: 0.33)], fill: .medium, width: line)
        c.blob([CGPoint(x: -0.1, y: 0.24), CGPoint(x: -0.05, y: 0.27), CGPoint(x: -0.06, y: 0.2)], fill: .paper, width: 0)
        c.line([CGPoint(x: 0, y: 0.3), CGPoint(x: 0.03, y: 0.42)], width: line * 0.9)
        c.blob([CGPoint(x: 0.03, y: 0.38), CGPoint(x: 0.13, y: 0.46), CGPoint(x: 0.17, y: 0.39), CGPoint(x: 0.08, y: 0.36)],
               fill: .dense, width: line * 0.6)
        if pierced {
            c.line([CGPoint(x: -0.7, y: ctr.y - 0.06), CGPoint(x: 0.62, y: ctr.y + 0.06)], width: 0.03)
            c.blob([CGPoint(x: 0.72, y: ctr.y + 0.07), CGPoint(x: 0.6, y: ctr.y + 0.12), CGPoint(x: 0.62, y: ctr.y + 0.06),
                    CGPoint(x: 0.61, y: ctr.y + 0.0)], fill: .ink, width: 0.01)
            for s in [1.0, -1.0] as [CGFloat] {
                let f = c.polygon([CGPoint(x: -0.7, y: ctr.y - 0.06), CGPoint(x: -0.64, y: ctr.y - 0.06 + 0.07 * s),
                                   CGPoint(x: -0.52, y: ctr.y - 0.05 + 0.07 * s), CGPoint(x: -0.56, y: ctr.y - 0.05)],
                                  wobble: 0.003)
                c.fillStroke(f, fill: .medium, width: 0.012)
            }
        }
    }

    // MARK: Feather (origin = centre), drifting decoration.

    static let featherBounds = CGRect(x: -0.35, y: -0.12, width: 0.7, height: 0.24)

    static func drawFeather(_ c: inout InkCanvas) {
        c.blob([CGPoint(x: -0.3, y: 0), CGPoint(x: -0.1, y: 0.09), CGPoint(x: 0.2, y: 0.07), CGPoint(x: 0.3, y: 0),
                CGPoint(x: 0.18, y: -0.06), CGPoint(x: -0.12, y: -0.07)], fill: .light, width: 0.018)
        c.line([CGPoint(x: -0.33, y: -0.01), CGPoint(x: 0.28, y: 0.0)], width: 0.016)
        for x in stride(from: -0.15 as CGFloat, through: 0.15, by: 0.1) {
            c.line([CGPoint(x: x, y: 0), CGPoint(x: x + 0.06, y: 0.06)], width: 0.01)
        }
    }

    // MARK: Padlock (origin = centre) for locked items.

    static let padlockBounds = CGRect(x: -0.3, y: -0.3, width: 0.6, height: 0.62)

    static func drawPadlock(_ c: inout InkCanvas) {
        c.line(InkCanvas.ellipsePoints(center: CGPoint(x: 0, y: 0.06), rx: 0.12, ry: 0.15, count: 8, from: 0, to: .pi),
               width: 0.05)
        let body = c.polygon([CGPoint(x: -0.2, y: -0.24), CGPoint(x: -0.2, y: 0.07), CGPoint(x: 0.2, y: 0.07),
                              CGPoint(x: 0.2, y: -0.24)], wobble: 0.006)
        c.fillStroke(body, fill: .ink, width: 0.03)
        c.circle(CGPoint(x: 0, y: -0.06), 0.035, fill: .paper, width: 0, count: 8)
    }

    // MARK: Archery target on a stand (origin = feet).

    static let targetBounds = CGRect(x: -0.75, y: -0.05, width: 1.5, height: 1.75)

    static func drawTarget(_ c: inout InkCanvas) {
        c.line([CGPoint(x: -0.4, y: 0), CGPoint(x: 0, y: 0.9)], width: 0.05)
        c.line([CGPoint(x: 0.4, y: 0), CGPoint(x: 0, y: 0.9)], width: 0.05)
        let ctr = CGPoint(x: 0, y: 1.05)
        c.circle(ctr, 0.6, fill: .paper, width: 0.045, count: 16)
        c.circle(ctr, 0.42, fill: .light, width: 0.035, count: 14)
        c.circle(ctr, 0.24, fill: .paper, width: 0.035, count: 12)
        c.circle(ctr, 0.09, fill: .ink, width: 0, count: 10)
    }
}
