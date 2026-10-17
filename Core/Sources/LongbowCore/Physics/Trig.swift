/// Lookup-table trigonometry (spec A6.3). Never call `sin`/`cos` in the simulation.
public enum Trig {
    /// sin of `index / 10` degrees, index 0...3600.
    public static let sinTable: [Double] = sinTableBits.map(Double.init(bitPattern:))
    /// cos of `index / 10` degrees, index 0...3600.
    public static let cosTable: [Double] = cosTableBits.map(Double.init(bitPattern:))

    /// Wraps any tenths-of-a-degree value into 0..<3600.
    @inlinable
    public static func wrap(_ tenths: Int) -> Int {
        let m = tenths % 3600
        return m < 0 ? m + 3600 : m
    }

    public static func sin(tenths: Int) -> Double { sinTable[wrap(tenths)] }
    public static func cos(tenths: Int) -> Double { cosTable[wrap(tenths)] }

    /// Linearly interpolated sine for a continuous angle in degrees. Used by the
    /// terrain noise (A6.7). Only floor, multiply and add — portable bit for bit.
    public static func sinLerp(degrees: Double) -> Double {
        let t = degrees * 10.0
        let f = t.rounded(.down)
        let frac = t - f
        // f can be large; reduce via Int arithmetic which is exact for our ranges.
        let i = wrap(Int(f))
        let a = sinTable[i]
        let b = sinTable[i + 1]
        return a + (b - a) * frac
    }
}
