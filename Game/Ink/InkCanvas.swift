import CoreGraphics
import LongbowCore
import UIKit

/// Paint used by the ink artwork. Artwork is drawn in an *encoded* colour space
/// and turned into the final black-and-white look by the halftone pass
/// (`HalftoneShader` in SpriteKit, `Halftone.decode` for SwiftUI images):
///
/// - red   = ink coverage (lines and solid black fills)
/// - blue  = "filled" coverage (paper or dots)
/// - green = halftone density × blue
///
/// Encoding density separately from ink means antialiased line edges never turn
/// into stray dots (spec A4: shading only with halftone dots, no grey fills).
enum InkPaint: Equatable {
    case paper
    case ink
    /// Halftone dots; density 0...1 is the share of the area covered by ink.
    case dots(Double)

    /// Built in Device RGB, the same space as the bitmap, so no colour
    /// management leaks into the encoded channels.
    var cgColor: CGColor {
        let c: [CGFloat]
        switch self {
        case .paper: c = [0, 0, 1, 1]
        case .ink: c = [1, 0, 0, 1]
        case let .dots(d): c = [0, CGFloat(min(max(d, 0), 1)), 1, 1]
        }
        return CGColor(colorSpace: InkPaint.space, components: c)!
    }

    static let space = CGColorSpaceCreateDeviceRGB()

    // Named densities matching the mockups.
    static let light = InkPaint.dots(0.12)
    static let medium = InkPaint.dots(0.22)
    static let dense = InkPaint.dots(0.36)
}

/// Hand-drawn drawing helpers in world metres, y up. Every call jitters its
/// points with a seeded RNG so each line-boil frame (A4) differs slightly.
struct InkCanvas {
    let ctx: CGContext
    let frame: Int
    /// Jitter amplitude in metres.
    var wobble: CGFloat
    var rng: SplitMix64

    init(ctx: CGContext, frame: Int, seed: UInt64, wobble: CGFloat) {
        self.ctx = ctx
        self.frame = frame
        self.wobble = wobble
        rng = SplitMix64(seed: SplitMix64.hash(seed, UInt64(frame)))
    }

    private mutating func jitter(_ p: CGPoint, _ amount: CGFloat) -> CGPoint {
        guard amount > 0 else { return p }
        let dx = CGFloat(rng.nextDouble(-1, 1)) * amount
        let dy = CGFloat(rng.nextDouble(-1, 1)) * amount
        return CGPoint(x: p.x + dx, y: p.y + dy)
    }

    /// Smooth Catmull-Rom path through jittered points.
    mutating func path(_ points: [CGPoint], closed: Bool, wobble: CGFloat? = nil) -> CGPath {
        let w = wobble ?? self.wobble
        var pts = points.map { jitter($0, w) }
        let path = CGMutablePath()
        guard pts.count > 1 else { return path }
        if pts.count == 2 {
            path.move(to: pts[0]); path.addLine(to: pts[1]); return path
        }
        if closed { pts.append(pts[0]) }
        path.move(to: pts[0])
        let n = pts.count
        for i in 0..<(n - 1) {
            let p0 = i > 0 ? pts[i - 1] : (closed ? pts[n - 2] : pts[i])
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = i + 2 < n ? pts[i + 2] : (closed ? pts[1] : p2)
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        if closed { path.closeSubpath() }
        return path
    }

    /// Straight-edged path (for shapes with corners), still jittered.
    mutating func polygon(_ points: [CGPoint], closed: Bool = true, wobble: CGFloat? = nil) -> CGPath {
        let w = wobble ?? self.wobble
        let path = CGMutablePath()
        let pts = points.map { jitter($0, w) }
        guard let first = pts.first else { return path }
        path.move(to: first)
        for p in pts.dropFirst() { path.addLine(to: p) }
        if closed { path.closeSubpath() }
        return path
    }

    static func ellipsePoints(center: CGPoint, rx: CGFloat, ry: CGFloat, count: Int = 14,
                              from: CGFloat = 0, to: CGFloat = 2 * .pi) -> [CGPoint] {
        let full = abs(to - from - 2 * .pi) < 0.001
        let n = full ? count : count + 1
        return (0..<n).map { i in
            let t = from + (to - from) * CGFloat(i) / CGFloat(count)
            return CGPoint(x: center.x + rx * cos(t), y: center.y + ry * sin(t))
        }
    }

    // MARK: Drawing

    func fill(_ path: CGPath, _ paint: InkPaint) {
        ctx.addPath(path)
        ctx.setFillColor(paint.cgColor)
        ctx.fillPath()
    }

    func stroke(_ path: CGPath, width: CGFloat, paint: InkPaint = .ink) {
        ctx.addPath(path)
        ctx.setStrokeColor(paint.cgColor)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()
    }

    func fillStroke(_ path: CGPath, fill paint: InkPaint?, width: CGFloat) {
        if let paint { fill(path, paint) }
        if width > 0 { stroke(path, width: width) }
    }

    mutating func blob(_ points: [CGPoint], fill paint: InkPaint?, width: CGFloat) {
        fillStroke(path(points, closed: true), fill: paint, width: width)
    }

    mutating func line(_ points: [CGPoint], width: CGFloat, paint: InkPaint = .ink) {
        stroke(path(points, closed: false), width: width, paint: paint)
    }

    mutating func circle(_ c: CGPoint, _ r: CGFloat, fill paint: InkPaint?, width: CGFloat, count: Int = 12) {
        blob(InkCanvas.ellipsePoints(center: c, rx: r, ry: r, count: count), fill: paint, width: width)
    }

    mutating func ellipse(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat, fill paint: InkPaint?, width: CGFloat) {
        blob(InkCanvas.ellipsePoints(center: c, rx: rx, ry: ry), fill: paint, width: width)
    }

    mutating func dot(_ c: CGPoint, _ r: CGFloat) {
        fill(CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r), transform: nil), .ink)
    }

    /// Clips subsequent drawing to `path` while running `body`.
    mutating func clipped(to path: CGPath, _ body: (inout InkCanvas) -> Void) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        body(&self)
        ctx.restoreGState()
    }
}

/// Renders artwork into images in the encoded paint space.
enum InkRenderer {
    /// - Parameters:
    ///   - bounds: drawing area in metres (y up).
    ///   - pixelsPerMetre: raster resolution.
    static func image(bounds: CGRect, pixelsPerMetre: CGFloat, frame: Int, seed: UInt64,
                      wobble: CGFloat, draw: (inout InkCanvas) -> Void) -> CGImage {
        let w = max(1, Int((bounds.width * pixelsPerMetre).rounded(.up)))
        let h = max(1, Int((bounds.height * pixelsPerMetre).rounded(.up)))
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: InkPaint.space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // CGBitmapContext is y-up already: map metres → pixels.
        ctx.scaleBy(x: pixelsPerMetre, y: pixelsPerMetre)
        ctx.translateBy(x: -bounds.minX, y: -bounds.minY)
        ctx.interpolationQuality = .high
        ctx.setShouldAntialias(true)
        var canvas = InkCanvas(ctx: ctx, frame: frame, seed: seed, wobble: wobble)
        draw(&canvas)
        return ctx.makeImage()!
    }
}
