import LongbowCore
import SwiftUI

/// Pill buttons (spec A4): primary = black fill / paper text; secondary = 3 pt outline.
struct PillButtonStyle: ButtonStyle {
    var primary = true

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            Spacer(minLength: 8)
            configuration.label
                .font(Theme.display(20, relativeTo: .headline))
                .tracking(2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 28)
        .frame(minHeight: 62)
        .foregroundStyle(primary ? Color.paper : Color.ink)
        .background {
            Capsule().fill(primary ? Color.ink : Color.paper)
            if !primary { Capsule().strokeBorder(Color.ink, lineWidth: Theme.line) }
        }
        .contentShape(Capsule())
        .scaleEffect(configuration.isPressed ? 0.97 : 1)
        .opacity(configuration.isPressed ? 0.9 : 1)
    }
}

/// 44–48 pt icon buttons: rounded square or circle, always labelled.
struct IconButton: View {
    let systemImage: String
    let label: LocalizedStringKey
    var circle = false
    var filled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(filled ? Color.paper : Color.ink)
                .frame(width: 48, height: 48)
                .background {
                    if circle {
                        Circle().fill(filled ? Color.ink : Color.paper)
                        if !filled { Circle().strokeBorder(Color.ink, lineWidth: Theme.line) }
                    } else {
                        RoundedRectangle(cornerRadius: 12).fill(filled ? Color.ink : Color.paper)
                        if !filled { RoundedRectangle(cornerRadius: 12).strokeBorder(Color.ink, lineWidth: Theme.line) }
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

/// Back is always a top-left 48 pt square with a chevron (spec A5).
struct BackButton: View {
    let action: () -> Void
    var body: some View {
        IconButton(systemImage: "chevron.left", label: "Back", action: action)
    }
}

/// Hand-drawn underline under the wordmark.
struct HandUnderline: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY + 2))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.midY - 1),
                   control1: CGPoint(x: r.minX + r.width * 0.35, y: r.midY - 3),
                   control2: CGPoint(x: r.minX + r.width * 0.7, y: r.midY + 3))
        return p
    }
}

/// Dot grid fill, for health bars and SwiftUI decorations.
struct DotPattern: View {
    var spacing: CGFloat = 5
    var radius: CGFloat = 0.9
    var body: some View {
        Canvas { ctx, size in
            var y = spacing / 2
            while y < size.height {
                var x = spacing / 2
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                             with: .color(.ink))
                    x += spacing
                }
                y += spacing
            }
        }
    }
}

/// Thin hand-drawn health bar: black fill, lost health as halftone dots (spec A4).
struct HealthBar: View {
    let value: Int
    var max: Int = 100
    var mirrored = false
    var height: CGFloat = 24

    var body: some View {
        GeometryReader { geo in
            let frac = CGFloat(Swift.max(0, Swift.min(value, max))) / CGFloat(max)
            ZStack(alignment: mirrored ? .trailing : .leading) {
                DotPattern(spacing: 4, radius: 0.8)
                    .padding(3)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.ink)
                    .frame(width: Swift.max(0, (geo.size.width - 6) * frac))
                    .padding(3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: mirrored ? .trailing : .leading)
            .background(Color.paper)
            .overlay(RoundedRectangle(cornerRadius: height / 3).strokeBorder(Color.ink, lineWidth: 2))
            .clipShape(RoundedRectangle(cornerRadius: height / 3))
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel(Text("Health"))
        .accessibilityValue(Text("\(value) of \(max)"))
    }
}

/// Character portrait rendered from the ink artwork with the CPU halftone pass.
struct PortraitView: View {
    let look: ArcherLook
    var expression: Expression = .neutral
    var background: Bool = false
    var hat: Hat = .none
    /// Defaults to your own face for Bjorn's body, and Gus's for Gus.
    var avatar: Avatar? = nil
    /// Close-up on the face (no shoulders), for small tiles.
    var faceOnly = false
    /// A custom close-up (metres, archer space), e.g. just the eyes.
    var crop: CGRect? = nil
    @Environment(\.displayScale) private var scale
    @EnvironmentObject private var progress: ProgressStore

    var body: some View {
        let face = avatar ?? (look == .bjorn ? progress.avatar : .gus)
        GeometryReader { geo in
            if let image = PortraitCache.shared.image(look: look, expression: expression, background: background,
                                                      hat: hat, avatar: face, faceOnly: faceOnly, crop: crop,
                                                      pointSize: geo.size.width, scale: scale) {
                Image(decorative: image, scale: scale)
                    .resizable()
                    .interpolation(.high)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel(Text(look.displayName))
    }
}

@MainActor
final class PortraitCache {
    static let shared = PortraitCache()
    private var cache: [String: CGImage] = [:]

    func cacheLookup(_ key: String) -> CGImage? { cache[key] }
    func store(_ key: String, _ image: CGImage) { cache[key] = image }

    func image(look: ArcherLook, expression: Expression, background: Bool, hat: Hat = .none, avatar: Avatar,
               faceOnly: Bool = false, crop: CGRect? = nil, pointSize: CGFloat, scale: CGFloat) -> CGImage? {
        guard pointSize > 1 else { return nil }
        let bounds = crop ?? (faceOnly ? CharacterArt.faceBounds : CharacterArt.portraitBounds)
        let key = "\(look).\(avatar.key).\(expression).\(background).\(hat).\(bounds).\(Int(pointSize)).\(scale)"
        if let hit = cache[key] { return hit }
        let ppm = pointSize * scale / bounds.width
        let raw = InkRenderer.image(bounds: bounds, pixelsPerMetre: ppm, frame: 0, seed: look.seed &+ 9,
                                    wobble: 0.004) { c in
            CharacterArt.drawPortrait(&c, look, expression, background: background ? .light : .paper, hat: hat,
                                      avatar: avatar, bounds: bounds)
        }
        // Dot pitch scales with the portrait so small faces stay readable.
        let img = Halftone.decode(raw, scale: scale, spacing: min(2.3, max(1.1, pointSize / 90)))
        cache[key] = img
        return img
    }
}

/// Any ink artwork rendered to a SwiftUI image (cached).
struct InkArtImage: View {
    let key: String
    let bounds: CGRect
    /// Dot pitch in points; nil for the standard screen.
    var dotSpacing: CGFloat? = nil
    let draw: (inout InkCanvas) -> Void
    @Environment(\.displayScale) private var scale

    var body: some View {
        GeometryReader { geo in
            if let image = PortraitCache.shared.art(key: key, bounds: bounds, pointWidth: geo.size.width,
                                                    scale: scale, dotSpacing: dotSpacing, draw: draw) {
                Image(decorative: image, scale: scale).resizable().interpolation(.high)
            }
        }
        .aspectRatio(bounds.width / bounds.height, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

extension PortraitCache {
    func art(key: String, bounds: CGRect, pointWidth: CGFloat, scale: CGFloat, dotSpacing: CGFloat? = nil,
             draw: (inout InkCanvas) -> Void) -> CGImage? {
        guard pointWidth > 1 else { return nil }
        let full = "\(key).\(Int(pointWidth)).\(scale).\(dotSpacing ?? 0)"
        if let hit = cacheLookup(full) { return hit }
        let ppm = pointWidth * scale / bounds.width
        let raw = InkRenderer.image(bounds: bounds, pixelsPerMetre: ppm, frame: 0, seed: 77, wobble: 0.004, draw: draw)
        let img = Halftone.decode(raw, scale: scale, spacing: dotSpacing ?? Halftone.spacingPoints)
        store(full, img)
        return img
    }
}

/// The wordmark: chunky bouncy letters, each tilted a little, with a halftone
/// drop shadow. Letters bob gently unless Reduce Motion is on.
struct Wordmark: View {
    let text: String
    var size: CGFloat = 80
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let tilts: [Double] = [-5, 4, -3, 6, -4, 3, -6, 5, -2, 4]

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: size * 0.02) {
                ForEach(Array(text.enumerated()), id: \.offset) { i, ch in
                    let letter = Text(String(ch)).font(Theme.wordmark(size))
                    ZStack {
                        DotPattern(spacing: 4, radius: 0.95)
                            .mask(letter)
                            .offset(x: size * 0.05, y: size * 0.05)
                        letter.foregroundStyle(Color.ink)
                    }
                    .fixedSize()
                    .rotationEffect(.degrees(Self.tilts[i % Self.tilts.count]))
                    .offset(y: (i % 2 == 0 ? -1 : 1) * size * 0.03
                            + (reduceMotion ? 0 : sin(t * 2.2 + Double(i) * 0.7) * size * 0.025))
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(text))
        .accessibilityAddTraits(.isHeader)
    }
}

/// Thin XP / progress bar in the house style.
struct InkProgressBar: View {
    let fraction: Double
    var height: CGFloat = 12

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 3).fill(Color.paper)
                RoundedRectangle(cornerRadius: 2).fill(Color.ink)
                    .frame(width: max(0, (g.size.width - 6) * min(1, max(0, fraction))))
                    .padding(3)
            }
            .overlay(RoundedRectangle(cornerRadius: height / 3).strokeBorder(Color.ink, lineWidth: 2))
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue(Text("\(Int(fraction * 100)) percent"))
    }
}

/// The app's own alert: a paper card with a thick ink border, tilted a touch
/// like a sticker slapped on the screen. Replaces the system alert so every
/// question looks like part of the game.
struct InkAlert: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    /// The safe choice: drawn filled, on the left.
    let primary: LocalizedStringKey
    let secondary: LocalizedStringKey
    let onPrimary: () -> Void
    let onSecondary: () -> Void
    @State private var shown = false

    var body: some View {
        ZStack {
            Color.paper.opacity(0.82).ignoresSafeArea()
                .onTapGesture(perform: onPrimary)
            VStack(spacing: 14) {
                Text(title).font(Theme.display(30)).multilineTextAlignment(.center)
                Text(message).font(Theme.mono(15)).multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    Button(primary, action: onPrimary).buttonStyle(PillButtonStyle(primary: true))
                    Button(secondary, action: onSecondary).buttonStyle(PillButtonStyle(primary: false))
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 28).padding(.vertical, 24)
            .frame(maxWidth: 480)
            .background(RoundedRectangle(cornerRadius: 26).fill(Color.paper))
            .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Color.ink, lineWidth: 3.5))
            .background(RoundedRectangle(cornerRadius: 26).fill(Color.ink).offset(x: 6, y: 7))
            .rotationEffect(.degrees(shown ? -1.5 : -6))
            .scaleEffect(shown ? 1 : 0.85)
            .opacity(shown ? 1 : 0)
        }
        .onAppear { withAnimation(.spring(response: 0.32, dampingFraction: 0.6)) { shown = true } }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}
