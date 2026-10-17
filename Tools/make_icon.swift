// Draws a placeholder 1024 px app icon: paper background, ink target, arrow.
// Run: swift Tools/make_icon.swift Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let paper = CGColor(red: 0xF3 / 255, green: 0xF0 / 255, blue: 0xE8 / 255, alpha: 1)
let ink = CGColor(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255, alpha: 1)
ctx.setFillColor(paper)
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

let c = CGPoint(x: 560, y: 470)
// Halftone ring.
ctx.setFillColor(ink)
var y = 0.0
while y < Double(size) {
    var x = 0.0
    while x < Double(size) {
        let d = hypot(x - c.x, y - c.y)
        if d > 230 && d < 330 {
            ctx.fillEllipse(in: CGRect(x: x - 5, y: y - 5, width: 10, height: 10))
        }
        x += 26
    }
    y += 26
}
ctx.setStrokeColor(ink)
ctx.setLineWidth(26)
ctx.strokeEllipse(in: CGRect(x: c.x - 230, y: c.y - 230, width: 460, height: 460))
ctx.fillEllipse(in: CGRect(x: c.x - 95, y: c.y - 95, width: 190, height: 190))

// Arrow stuck in the centre, coming from the upper left.
ctx.setLineCap(.round)
ctx.setLineWidth(30)
let tail = CGPoint(x: 170, y: 860)
ctx.move(to: tail)
ctx.addLine(to: CGPoint(x: c.x - 20, y: c.y + 20))
ctx.strokePath()
for s in [-1.0, 1.0] {
    ctx.setLineWidth(18)
    ctx.move(to: CGPoint(x: tail.x + 40, y: tail.y - 40))
    ctx.addLine(to: CGPoint(x: tail.x + 40 + 70 * s, y: tail.y - 40 + 70))
    ctx.strokePath()
}

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
print("wrote \(url.path)")
