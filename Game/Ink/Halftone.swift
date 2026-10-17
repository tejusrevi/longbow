import CoreGraphics
import SpriteKit
import UIKit

/// Turns encoded ink artwork (see `InkPaint`) into the final paper/ink look.
enum Halftone {
    static let paper = (r: 0xF3, g: 0xF0, b: 0xE8)
    static let ink = (r: 0x11, g: 0x11, b: 0x11)
    /// Dot grid spacing in points (matches the mockups' dot pitch).
    static let spacingPoints: CGFloat = 4.5

    /// Ink share of a pixel for a dot grid. `x`, `y` and `spacing` in pixels.
    @inline(__always)
    static func dotMask(x: Double, y: Double, density: Double, spacing: Double) -> Double {
        guard density > 0.02 else { return 0 }
        let px = x / spacing, py = y / spacing
        let cx = (px - px.rounded(.down) - 0.5) * spacing
        let cy = (py - py.rounded(.down) - 0.5) * spacing
        let d = (cx * cx + cy * cy).squareRoot()
        let r = (density / .pi).squareRoot() * spacing
        let t = min(max((d - (r - 0.6)) / 1.2, 0), 1)
        return 1 - t * t * (3 - 2 * t)
    }

    /// CPU decode for SwiftUI images (portraits, title art).
    /// - Parameter inverted: Moon arena look (black sky, paper ink).
    /// - Parameter spacing: dot pitch in points; smaller images want finer dots.
    static func decode(_ image: CGImage, scale: CGFloat, inverted: Bool = false,
                       spacing spacingPts: CGFloat = spacingPoints) -> CGImage {
        let w = image.width, h = image.height
        let bytesPerRow = w * 4
        var src = [UInt8](repeating: 0, count: h * bytesPerRow)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        let ctx = CGContext(data: &src, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                            space: space, bitmapInfo: info)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var out = [UInt8](repeating: 0, count: h * bytesPerRow)
        let spacing = Double(spacingPts * scale)
        let inkC = inverted ? paper : ink
        let paperC = inverted ? ink : paper
        for y in 0..<h {
            for x in 0..<w {
                let i = y * bytesPerRow + x * 4
                let a = Double(src[i + 3]) / 255
                guard a > 0.004 else { continue }
                let r = Double(src[i]) / 255 / a
                let g = Double(src[i + 1]) / 255 / a
                let b = Double(src[i + 2]) / 255 / a
                let density = b > 0.002 ? min(max(g / b, 0), 1) : 0
                let inkAmt = min(1, r + b * dotMask(x: Double(x), y: Double(y), density: density, spacing: spacing))
                func mix(_ p: Int, _ k: Int) -> UInt8 {
                    UInt8(min(255, max(0, (Double(p) * (1 - inkAmt) + Double(k) * inkAmt) * a)))
                }
                out[i] = mix(paperC.r, inkC.r)
                out[i + 1] = mix(paperC.g, inkC.g)
                out[i + 2] = mix(paperC.b, inkC.b)
                out[i + 3] = src[i + 3]
            }
        }
        let provider = CGDataProvider(data: Data(out) as CFData)!
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: info), provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    }
}

/// GPU halftone for SpriteKit (spec A4 "Halftone shader"). Dots are drawn in
/// screen space so their size stays constant while the camera zooms; the grid is
/// anchored to the world origin (`u_origin`) so it moves with camera pans.
enum HalftoneShader {
    /// Ink share of the fragment for a dot grid, inlined into each `main`
    /// because SpriteKit only exposes uniforms there.
    private static func dotMask(density: String, out: String) -> String {
        """
            vec2 p_ = (gl_FragCoord.xy - u_origin) / u_spacing;
            vec2 c_ = (fract(p_) - 0.5) * u_spacing;
            float r_ = sqrt(max(\(density), 0.0) / 3.14159) * u_spacing;
            float \(out) = (\(density) <= 0.02) ? 0.0 : 1.0 - smoothstep(r_ - 0.6, r_ + 0.6, length(c_));

        """
    }

    /// For sprites drawn with `InkPaint`.
    static let sprite: SKShader = {
        let s = SKShader(source: """
        void main() {
            vec4 t = texture2D(u_texture, v_tex_coord);
            vec3 c = t.rgb / max(t.a, 0.003);
            float fill = c.b;
            float density = fill > 0.002 ? clamp(c.g / fill, 0.0, 1.0) : 0.0;
        \(dotMask(density: "density", out: "dm"))
            float inkAmt = clamp(c.r + fill * dm, 0.0, 1.0);
            vec3 col = mix(u_paper, u_ink, inkAmt);
            float a = t.a * v_color_mix.a;
            gl_FragColor = vec4(col * a, a);
        }
        """)
        s.uniforms = baseUniforms()
        return s
    }()

    /// Characters: the same, with a finer dot grid so faces keep their detail.
    static let spriteFine: SKShader = {
        let s = SKShader(source: """
        void main() {
            vec4 t = texture2D(u_texture, v_tex_coord);
            vec3 c = t.rgb / max(t.a, 0.003);
            float fill = c.b;
            float density = fill > 0.002 ? clamp(c.g / fill, 0.0, 1.0) : 0.0;
        \(dotMask(density: "density", out: "dm"))
            float inkAmt = clamp(c.r + fill * dm, 0.0, 1.0);
            vec3 col = mix(u_paper, u_ink, inkAmt);
            float a = t.a * v_color_mix.a;
            gl_FragColor = vec4(col * a, a);
        }
        """)
        s.uniforms = baseUniforms(spacing: Halftone.spacingPoints * 0.38)
        return s
    }()

    /// Flat halftone fill for shape nodes (terrain). Density per node.
    static func fill(density: Float) -> SKShader {
        let s = SKShader(source: """
        void main() {
        \(dotMask(density: "u_density", out: "inkAmt"))
            gl_FragColor = vec4(mix(u_paper, u_ink, inkAmt), 1.0) * v_color_mix.a;
        }
        """)
        s.uniforms = baseUniforms() + [SKUniform(name: "u_density", float: density)]
        fillShaders.append(s)
        return s
    }

    private static var fillShaders: [SKShader] = []

    private static func baseUniforms(spacing: CGFloat = Halftone.spacingPoints) -> [SKUniform] {
        let scale = Float(UIScreen.main.scale)
        return [
            SKUniform(name: "u_spacing", float: Float(spacing) * scale),
            SKUniform(name: "u_origin", vectorFloat2: .zero),
            SKUniform(name: "u_paper", vectorFloat3: SIMD3(0xF3, 0xF0, 0xE8) / 255),
            SKUniform(name: "u_ink", vectorFloat3: SIMD3(0x11, 0x11, 0x11) / 255),
        ]
    }

    /// Call every frame with the world origin's position in view pixels.
    static func setOrigin(_ origin: SIMD2<Float>) {
        sprite.uniformNamed("u_origin")?.vectorFloat2Value = origin
        spriteFine.uniformNamed("u_origin")?.vectorFloat2Value = origin
        for s in fillShaders { s.uniformNamed("u_origin")?.vectorFloat2Value = origin }
    }

    /// Swaps paper and ink (Moon arena look).
    static func setInverted(_ inverted: Bool) {
        let paper = SIMD3<Float>(0xF3, 0xF0, 0xE8) / 255
        let ink = SIMD3<Float>(0x11, 0x11, 0x11) / 255
        for s in [sprite, spriteFine] + fillShaders {
            s.uniformNamed("u_paper")?.vectorFloat3Value = inverted ? ink : paper
            s.uniformNamed("u_ink")?.vectorFloat3Value = inverted ? paper : ink
        }
    }
}
