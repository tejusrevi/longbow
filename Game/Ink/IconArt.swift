import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The app icon: a big close-up of the chicken — googly eyes, beak open,
/// tongue out — with an arrow stuck in the top of its head. Few, big shapes
/// so it still reads at home-screen size. The arrow comes out of the picture
/// toward you (thickening shaft, fletching growing, the nock seen end-on), so
/// a flat ink drawing reads as 3D. Inked with the same brush as the game.
enum IconArt {
    static let bounds = CGRect(x: 0, y: 0, width: 1, height: 1)

    static func draw(_ c: inout InkCanvas) {
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        c.fill(CGPath(rect: bounds.insetBy(dx: -0.05, dy: -0.05), transform: nil), .paper)
        // A dotted sun behind the head for contrast.
        c.fill(c.path(InkCanvas.ellipsePoints(center: P(0.6, 0.52), rx: 0.42, ry: 0.42, count: 24), closed: true), .dots(0.22))

        // Neck, out of the bottom of the frame.
        let neck = [P(0.3, -0.1), P(0.34, 0.25), P(0.4, 0.38), P(0.66, 0.36), P(0.72, 0.2), P(0.78, -0.1)]
        _ = c.mass(neck, paint: .paper)
        c.brush([P(0.32, -0.08), P(0.35, 0.22), P(0.4, 0.36)], width: 0.032, start: 0.9, end: 0.5)
        c.brush([P(0.76, -0.08), P(0.72, 0.18), P(0.67, 0.34)], width: 0.032, start: 0.9, end: 0.5)

        // Comb: three fat blobs.
        for (x, y, r) in [(0.38, 0.86, 0.062), (0.47, 0.905, 0.07), (0.565, 0.875, 0.062)] as [(CGFloat, CGFloat, CGFloat)] {
            _ = c.mass(InkCanvas.ellipsePoints(center: P(x, y), rx: r, ry: r * 0.95, count: 12))
        }
        // Head.
        let head = InkCanvas.ellipsePoints(center: P(0.5, 0.57), rx: 0.27, ry: 0.3, count: 16)
        _ = c.mass(head, paint: .paper)
        c.brushLoop(head, width: 0.034)

        // Beak: a hand-drawn curve, hooked a little at the tip, mouth open.
        let upper = [P(0.7, 0.565), P(0.8, 0.548), P(0.9, 0.51), P(0.96, 0.465), P(0.88, 0.448), P(0.78, 0.452), P(0.69, 0.44)]
        let mouth = [P(0.7, 0.45), P(0.84, 0.448), P(0.9, 0.445), P(0.82, 0.39), P(0.7, 0.39)]
        _ = c.mass(mouth)
        _ = c.mass(upper, paint: .paper)
        c.brushLoop(upper, width: 0.026)
        let lower = [P(0.69, 0.41), P(0.78, 0.4), P(0.86, 0.385), P(0.84, 0.35), P(0.76, 0.33), P(0.67, 0.33)]
        _ = c.mass(lower, paint: .paper)
        c.brushLoop(lower, width: 0.024)
        c.brush([P(0.75, 0.515), P(0.79, 0.52)], width: 0.016, start: 0.8, end: 0.4)
        // Wattle.
        _ = c.mass([P(0.66, 0.31), P(0.68, 0.2), P(0.62, 0.17), P(0.6, 0.27)])

        // Googly eyes, pupils off in different directions.
        for (cx, cy, r, px, py) in [(0.42, 0.6, 0.095, 0.385, 0.565), (0.61, 0.625, 0.105, 0.65, 0.665)]
            as [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] {
            let eye = InkCanvas.ellipsePoints(center: P(cx, cy), rx: r, ry: r, count: 14)
            _ = c.mass(eye, paint: .paper)
            c.brushLoop(eye, width: 0.026)
            _ = c.mass(InkCanvas.ellipsePoints(center: P(px, py), rx: 0.04, ry: 0.042, count: 10))
        }

        // The arrow: stuck in the top of the head, coming out toward you.
        let e = P(0.31, 0.75), t = P(0.15, 0.89)
        let len = hypot(t.x - e.x, t.y - e.y)
        let d = P((t.x - e.x) / len, (t.y - e.y) / len)
        let n = P(-d.y, d.x)
        func at(_ k: CGFloat, _ off: CGFloat) -> CGPoint {
            P(e.x + d.x * len * k + n.x * off, e.y + d.y * len * k + n.y * off)
        }
        _ = c.mass(InkCanvas.ellipsePoints(center: e, rx: 0.03, ry: 0.022, count: 8))
        for a in [-0.5, 0.2, 2.4, 3.1] as [CGFloat] {
            c.brush([P(e.x + cos(a) * 0.06, e.y + sin(a) * 0.05), P(e.x + cos(a) * 0.1, e.y + sin(a) * 0.085)], width: 0.016,
                    start: 0.9, end: 0.2)
        }
        _ = c.mass([at(0, 0.012), at(1, 0.03), at(1, -0.03), at(0, -0.012)], angular: true)
        for side in [1.0, -1.0] as [CGFloat] {
            let vane = [at(0.55, side * 0.018), at(0.62, side * 0.085), at(0.98, side * 0.13), at(0.99, side * 0.035)]
            _ = c.mass(vane, paint: .dots(0.3), angular: true)
            c.brushLoop(vane, width: 0.018, angular: true)
        }
        let nock = InkCanvas.ellipsePoints(center: t, rx: 0.04, ry: 0.034, count: 10)
        _ = c.mass(nock, paint: .paper)
        c.brushLoop(nock, width: 0.016)
        c.dot(t, 0.014)
    }

    /// Writes the 1024 px icon PNG.
    @MainActor
    static func write(to path: String) {
        let px: CGFloat = 1024
        let raw = InkRenderer.image(bounds: bounds, pixelsPerMetre: px / bounds.width, frame: 0, seed: 0x1C0,
                                    wobble: 0.003, draw: draw)
        let img = Halftone.decode(raw, scale: 1, spacing: 20)
        // Flatten onto opaque paper (icons can't have alpha).
        let ctx = CGContext(data: nil, width: Int(px), height: Int(px), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0xF3 / 255, green: 0xF0 / 255, blue: 0xE8 / 255, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: px, height: px))
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: px, height: px))
        let url = URL(fileURLWithPath: path)
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
        print("icon written to \(path)")
    }
}
