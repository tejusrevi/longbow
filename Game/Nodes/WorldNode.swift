import LongbowCore
import SpriteKit

/// The arena for one round: terrain, scenery, obstacles (spec A6.7, A13 Hills).
@MainActor
final class WorldNode: SKNode {
    let conditions: RoundConditions
    private let groundLine = InkShape()
    private var lines: [(InkShape, CGFloat)] = []
    private let boil: Bool

    init(conditions: RoundConditions, boil: Bool) {
        self.conditions = conditions
        self.boil = boil
        super.init()
        buildTerrain()
        buildScenery()
        buildObstacles()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func groundPoints(offset: CGFloat = 0) -> [CGPoint] {
        let t = conditions.terrain
        let d = conditions.distance
        // Fine detail near the archers; coarser far out, where only long shots
        // ever land. Wide enough for the longest possible flight.
        let far = 820.0
        let xs = Array(stride(from: -far, to: -150, by: 2.0)) + Array(stride(from: -150.0, through: d + 150, by: 0.4))
            + Array(stride(from: d + 152, through: d + far, by: 2.0))
        return Self.simplified(xs.map { CGPoint(x: $0, y: t.height(at: $0) + offset) })
    }

    /// Drops points that lie on a straight run. SKShapeNode draws thick lines
    /// through many collinear points with little gaps (the flat pads the
    /// archers stand on looked broken), so flat stretches become one segment.
    static func simplified(_ pts: [CGPoint], tolerance: CGFloat = 0.004) -> [CGPoint] {
        guard pts.count > 2 else { return pts }
        var out: [CGPoint] = [pts[0]]
        for i in 1..<(pts.count - 1) {
            let a = out[out.count - 1], b = pts[i], c = pts[i + 1]
            // Distance of b from the line a→c.
            let dx = c.x - a.x, dy = c.y - a.y
            let len = max(hypot(dx, dy), 0.0001)
            let dist = abs((b.x - a.x) * dy - (b.y - a.y) * dx) / len
            if dist > tolerance { out.append(b) }
        }
        out.append(pts[pts.count - 1])
        return out
    }

    private func buildTerrain() {
        let pts = groundPoints()
        let bottom: CGFloat = -400

        let paperPath = CGMutablePath()
        paperPath.addLines(between: pts)
        paperPath.addLine(to: CGPoint(x: pts.last!.x, y: bottom))
        paperPath.addLine(to: CGPoint(x: pts.first!.x, y: bottom))
        paperPath.closeSubpath()
        let paper = InkShape(metres: paperPath)
        paper.fillColor = .paper
        paper.strokeColor = .clear
        paper.zPosition = 4
        addChild(paper)

        // Dots start a little below the ground line, like the mockups.
        let dotted = groundPoints(offset: -1.4)
        let dotsPath = CGMutablePath()
        dotsPath.addLines(between: dotted)
        dotsPath.addLine(to: CGPoint(x: dotted.last!.x, y: bottom))
        dotsPath.addLine(to: CGPoint(x: dotted.first!.x, y: bottom))
        dotsPath.closeSubpath()
        let dots = InkShape(metres: dotsPath)
        dots.fillColor = .white
        dots.fillShader = HalftoneShader.fill(density: 0.1)
        dots.strokeColor = .clear
        dots.zPosition = 5
        addChild(dots)

        let line = CGMutablePath()
        line.addLines(between: pts)
        groundLine.metresPath = line
        groundLine.strokeColor = .ink
        groundLine.lineCap = .round
        groundLine.lineJoin = .round
        groundLine.zPosition = 6
        addChild(groundLine)
        lines.append((groundLine, 2.6))
    }

    private func buildScenery() {
        var rng = SplitMix64(seed: SplitMix64.hash(conditions.seed, 0x5CE7E))
        let d = conditions.distance
        let lib = ArtLibrary.shared
        // Grass tufts and stones (visual only), mirrored like the terrain.
        for _ in 0..<Int(d / 18) {
            let x = rng.nextDouble(-60, d / 2)
            let art = rng.nextUnit() < 0.7 ? lib.tuft : lib.stone
            for xx in [x, d - x] {
                if abs(xx) < 2.5 || abs(xx - d) < 2.5 { continue }
                let s = art.makeSprite()
                s.position = CGPoint(x: xx, y: conditions.terrain.height(at: xx) - 0.05)
                s.setScale(0.6)
                s.xScale = xx > d / 2 ? -0.6 : 0.6
                s.zPosition = 7
                s.startBoil(art.textures, enabled: boil)
                addChild(s)
                if boil && art.bounds == lib.tuft.bounds {
                    // Grass sways in a breeze that never quite agrees with the wind flag.
                    let sway = SKAction.rotate(byAngle: 0.12, duration: .random(in: 1.2...1.8))
                    sway.timingMode = .easeInEaseOut
                    s.run(.repeatForever(.sequence([sway, sway.reversed()])))
                }
            }
        }
        // Clouds.
        for i in 0..<Int(d / 40 + 4) {
            let art = lib.cloud(dotted: i % 4 == 3)
            let s = art.makeSprite()
            let scale = CGFloat(rng.nextDouble(0.7, 1.6))
            s.setScale(scale)
            s.position = CGPoint(x: rng.nextDouble(-40, d + 40), y: rng.nextDouble(14, 48))
            s.zPosition = 1
            s.startBoil(art.textures, enabled: boil)
            addChild(s)
            if boil {
                // Clouds drift lazily.
                let drift = SKAction.moveBy(x: .random(in: 8...16), y: 0, duration: .random(in: 40...70))
                drift.timingMode = .easeInEaseOut
                s.run(.repeatForever(.sequence([drift, drift.reversed()])))
            }
        }
    }

    private func buildObstacles() {
        let lib = ArtLibrary.shared
        for o in conditions.obstacles {
            let art: ArtLibrary.Art
            switch o.kind {
            case .tree: art = lib.tree
            case .rock: art = lib.rock
            case .wall: art = lib.wall
            }
            let s = art.makeSprite()
            s.position = CGPoint(x: o.x, y: o.baseY)
            s.zPosition = 8
            s.startBoil(art.textures, enabled: boil)
            addChild(s)
        }
    }

    /// Keeps hairlines a constant on-screen width while the camera zooms.
    func updateLineWidths(metresPerPoint: CGFloat) {
        for (node, points) in lines {
            let w = points * metresPerPoint
            if abs(node.metresLineWidth - w) / max(w, 0.0001) > 0.04 { node.metresLineWidth = w }
        }
    }
}
