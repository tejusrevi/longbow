import SpriteKit

/// Builds and caches line-boil textures for every drawn part (spec A4: three
/// slightly different hand-drawn versions, cycled at 8 fps).
@MainActor
final class ArtLibrary {
    static let shared = ArtLibrary()
    static let boilFrames = 3
    static let boilFPS: Double = 8

    struct Art {
        let textures: [SKTexture]
        let bounds: CGRect

        /// Sprite size in metres with the anchor at the art's local origin.
        func makeSprite() -> SKSpriteNode {
            let node = SKSpriteNode(texture: textures[0], size: bounds.size)
            node.anchorPoint = CGPoint(x: -bounds.minX / bounds.width, y: -bounds.minY / bounds.height)
            node.shader = HalftoneShader.sprite
            return node
        }
    }

    private var cache: [String: Art] = [:]

    func art(_ key: String, bounds: CGRect, pixelsPerMetre: CGFloat, wobble: CGFloat, seed: UInt64,
             draw: (inout InkCanvas) -> Void) -> Art {
        if let hit = cache[key] { return hit }
        let textures = (0..<Self.boilFrames).map { frame -> SKTexture in
            let image = InkRenderer.image(bounds: bounds, pixelsPerMetre: pixelsPerMetre, frame: frame,
                                          seed: seed, wobble: wobble, draw: draw)
            let t = SKTexture(cgImage: image)
            t.filteringMode = .linear
            return t
        }
        let art = Art(textures: textures, bounds: bounds)
        cache[key] = art
        return art
    }

    /// Renders the textures a match needs a few at a time while you're on the
    /// title screen, so the first match starts without a hitch.
    func prewarm(avatar: Avatar, hat: Hat) async {
        var jobs: [() -> Void] = [
            { _ = self.legs(outfit: avatar.wardrobe) }, { _ = self.body(outfit: avatar.wardrobe) },
            { _ = self.legs(outfit: Avatar.gus.wardrobe) }, { _ = self.body(outfit: Avatar.gus.wardrobe) },
            { _ = self.bow }, { _ = self.arrow }, { _ = self.hat(hat) }, { _ = self.hat(.none) },
            { _ = self.tree }, { _ = self.rock }, { _ = self.cloud(dotted: true) }, { _ = self.cloud(dotted: false) },
            { _ = self.tuft }, { _ = self.stone }, { _ = self.birdFrames }, { _ = self.leaf },
            { _ = self.feather },
        ]
        for pose in ChickenArt.Pose.allCases { jobs.append { _ = self.chicken(pose) } }
        for expr in Expression.allCases {
            jobs.append { _ = self.head(avatar, expr) }
            jobs.append { _ = self.head(.gus, expr) }
        }
        for job in jobs {
            job()
            // Yield a frame between renders to keep the UI smooth.
            try? await Task.sleep(for: .milliseconds(12))
        }
    }

    // MARK: Characters

    private static let characterPPM: CGFloat = 260

    func legs(outfit: Int) -> Art {
        art("legs.o\(outfit)", bounds: CharacterArt.legsBounds, pixelsPerMetre: Self.characterPPM,
            wobble: 0.006, seed: 0xB2) { CharacterArt.drawLegs(&$0, outfit: outfit) }
    }

    func body(outfit: Int) -> Art {
        art("body.o\(outfit)", bounds: CharacterArt.bodyBounds, pixelsPerMetre: Self.characterPPM,
            wobble: 0.006, seed: 0xB3) { CharacterArt.drawBody(&$0, outfit: outfit) }
    }

    func head(_ avatar: Avatar, _ expr: Expression) -> Art {
        art("head.\(avatar.key).\(expr)", bounds: CharacterArt.headBounds, pixelsPerMetre: Self.characterPPM,
            wobble: 0.005, seed: 0xA7A) { AvatarArt.draw(&$0, avatar, expr) }
    }

    var bow: Art {
        art("bow", bounds: CharacterArt.bowBounds, pixelsPerMetre: Self.characterPPM, wobble: 0.006, seed: 4) {
            CharacterArt.drawBow(&$0)
        }
    }

    var arrow: Art {
        art("arrow", bounds: CharacterArt.arrowBounds, pixelsPerMetre: 320, wobble: 0.003, seed: 5) {
            CharacterArt.drawArrow(&$0)
        }
    }

    func hat(_ hat: Hat) -> Art {
        art("hat.\(hat.rawValue)", bounds: PropsArt.hatBounds, pixelsPerMetre: Self.characterPPM,
            wobble: 0.005, seed: 30 &+ UInt64(Hat.allCases.firstIndex(of: hat) ?? 0)) { PropsArt.drawHat(&$0, hat) }
    }

    // MARK: Props

    /// Two flap frames (wings up, wings down).
    var birdFrames: [SKTexture] {
        let up = art("bird.up", bounds: PropsArt.birdBounds, pixelsPerMetre: 90, wobble: 0.01, seed: 40) {
            PropsArt.drawBird(&$0, wingsUp: true)
        }
        let down = art("bird.down", bounds: PropsArt.birdBounds, pixelsPerMetre: 90, wobble: 0.01, seed: 41) {
            PropsArt.drawBird(&$0, wingsUp: false)
        }
        return [up.textures[0], down.textures[0]]
    }

    var bird: Art {
        art("bird.up", bounds: PropsArt.birdBounds, pixelsPerMetre: 90, wobble: 0.01, seed: 40) {
            PropsArt.drawBird(&$0, wingsUp: true)
        }
    }

    var leaf: Art {
        art("leaf", bounds: PropsArt.leafBounds, pixelsPerMetre: 160, wobble: 0.006, seed: 44) { PropsArt.drawLeaf(&$0) }
    }

    func apple(pierced: Bool) -> Art {
        art("apple.\(pierced)", bounds: PropsArt.appleBounds, pixelsPerMetre: 220, wobble: 0.005, seed: 45) {
            PropsArt.drawApple(&$0, pierced: pierced)
        }
    }

    var target: Art {
        art("target", bounds: PropsArt.targetBounds, pixelsPerMetre: 120, wobble: 0.01, seed: 46) { PropsArt.drawTarget(&$0) }
    }

    // MARK: Chicken

    func chicken(_ pose: ChickenArt.Pose) -> Art {
        art("chicken.\(pose.rawValue)", bounds: ChickenArt.bounds, pixelsPerMetre: 300, wobble: 0.004, seed: 0xC41C) {
            ChickenArt.draw(&$0, pose)
        }
    }

    var feather: Art {
        art("feather", bounds: ChickenArt.featherBounds, pixelsPerMetre: 300, wobble: 0.002, seed: 0xFE) {
            ChickenArt.drawFeather(&$0)
        }
    }

    // MARK: Scenery

    var tree: Art {
        art("tree", bounds: SceneryArt.treeBounds, pixelsPerMetre: 40, wobble: 0.06, seed: 10) { SceneryArt.drawTree(&$0) }
    }

    var rock: Art {
        art("rock", bounds: SceneryArt.rockBounds, pixelsPerMetre: 60, wobble: 0.04, seed: 11) { SceneryArt.drawRock(&$0) }
    }

    var wall: Art {
        art("wall", bounds: SceneryArt.wallBounds, pixelsPerMetre: 50, wobble: 0.04, seed: 12) { SceneryArt.drawWall(&$0) }
    }

    func cloud(dotted: Bool) -> Art {
        art("cloud.\(dotted)", bounds: SceneryArt.cloudBounds, pixelsPerMetre: 36, wobble: 0.06, seed: dotted ? 13 : 14) {
            SceneryArt.drawCloud(&$0, dotted: dotted)
        }
    }

    var sun: Art {
        art("sun", bounds: SceneryArt.sunBounds, pixelsPerMetre: 30, wobble: 0.06, seed: 15) { SceneryArt.drawSun(&$0) }
    }

    var tuft: Art {
        art("tuft", bounds: SceneryArt.tuftBounds, pixelsPerMetre: 120, wobble: 0.02, seed: 16) { SceneryArt.drawTuft(&$0) }
    }

    var stone: Art {
        art("stone", bounds: SceneryArt.stoneBounds, pixelsPerMetre: 120, wobble: 0.02, seed: 17) { SceneryArt.drawStone(&$0) }
    }

}

extension SKNode {
    /// Cycles line-boil frames at 8 fps unless disabled (Reduce Motion / config).
    func startBoil(_ textures: [SKTexture], enabled: Bool) {
        guard let sprite = self as? SKSpriteNode else { return }
        sprite.removeAction(forKey: "boil")
        sprite.texture = textures[0]
        guard enabled, textures.count > 1 else { return }
        // Start at a random frame so neighbouring parts don't boil in lockstep.
        let offset = Int.random(in: 0..<textures.count)
        let frames = Array(textures[offset...] + textures[..<offset])
        sprite.run(.repeatForever(.animate(with: frames, timePerFrame: 1 / ArtLibrary.boilFPS)), withKey: "boil")
    }
}
