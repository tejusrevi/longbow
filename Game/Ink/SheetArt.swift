#if DEBUG
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Debug contact sheets for reviewing the avatar art: every preset, and every
/// option of every part, rendered big. `-renderSheet <dir>`.
enum SheetArt {
    @MainActor
    static func write(to dir: String) {
        let tile = 300
        func render(_ a: Avatar, crop: CGRect, expr: Expression = .neutral) -> CGImage {
            let raw = InkRenderer.image(bounds: crop, pixelsPerMetre: CGFloat(tile) / crop.width, frame: 0, seed: 0xB1 &+ 9,
                                        wobble: 0.004) { c in
                CharacterArt.drawPortrait(&c, .bjorn, expr, background: .paper, avatar: a, bounds: crop)
            }
            return Halftone.decode(raw, scale: 1, spacing: 3.6)
        }
        func sheet(_ name: String, _ items: [CGImage], cols: Int) {
            let rows = (items.count + cols - 1) / cols
            let ctx = CGContext(data: nil, width: cols * tile, height: rows * tile, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            ctx.setFillColor(CGColor(red: 0.95, green: 0.94, blue: 0.91, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: cols * tile, height: rows * tile))
            for (i, img) in items.enumerated() {
                let x = (i % cols) * tile, y = (rows - 1 - i / cols) * tile
                ctx.draw(img, in: CGRect(x: x, y: y, width: tile, height: tile))
            }
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
            let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
            CGImageDestinationFinalize(dest)
        }
        let portrait = CharacterArt.portraitBounds
        sheet("presets", Avatar.presets.map { render($0.1, crop: portrait) }, cols: 6)
        let base = Avatar(head: 1, skin: 1, hair: 17, brows: 0, eyes: 1, nose: 0, mouth: 0)
        for part in Avatar.Part.allCases where part != .skin {
            let items = (0..<part.count).map { i -> CGImage in
                var a = base
                if part == .brows || part == .eyes { a.hair = 1 }
                a[part] = i
                return render(a, crop: part == .outfit || part == .hair ? portrait : CharacterArt.faceBounds)
            }
            sheet("part_\(part.rawValue)", items, cols: 6)
        }
        sheet("expressions", Expression.allCases.map { render(.bjorn, crop: CharacterArt.faceBounds, expr: $0) }, cols: 7)
        print("sheets written to \(dir)")
    }
}
#endif
