import SwiftUI

/// Design tokens (spec A4). The game is black and white; flags are the only
/// colour in v1.0, and `premiumAccent` is PART B only.
extension Color {
    static let paper = Color("Paper")
    static let ink = Color("Ink")
    static let inkQuiet = Color("InkQuiet")
}

/// Fonts (spec A4 "Type"), with system fallbacks until the Google Fonts are
/// bundled. All sizes scale with Dynamic Type relative to the given style.
enum Theme {
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        custom("ArchivoBlack-Regular", size, style) ?? .system(size: size, weight: .black, design: .default)
    }

    /// The wordmark face: chunky, bouncy, a little silly.
    static func wordmark(_ size: CGFloat) -> Font {
        custom("LuckiestGuy-Regular", size, .largeTitle) ?? .system(size: size, weight: .black, design: .rounded)
    }

    static func mono(_ size: CGFloat, bold: Bool = false, relativeTo style: Font.TextStyle = .body) -> Font {
        custom(bold ? "SpaceMono-Bold" : "SpaceMono-Regular", size, style)
            ?? .system(size: size, weight: bold ? .bold : .regular, design: .monospaced)
    }

    static func hand(_ size: CGFloat, relativeTo style: Font.TextStyle = .title2) -> Font {
        custom("ShantellSansNormal-Medium", size, style) ?? .custom("ChalkboardSE-Bold", size: size, relativeTo: style)
    }

    private static func custom(_ name: String, _ size: CGFloat, _ style: Font.TextStyle) -> Font? {
        UIFont(name: name, size: size) != nil ? .custom(name, size: size, relativeTo: style) : nil
    }

    static let line: CGFloat = 3
    static let minTouch: CGFloat = 44
}
