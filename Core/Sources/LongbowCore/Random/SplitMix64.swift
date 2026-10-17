/// Seeded RNG shared with the server (spec A6.6, A3 `Random/`).
///
/// SplitMix64 is used because it is tiny, has no state beyond one UInt64 and is
/// trivial to port bit-for-bit to TypeScript with BigInt. Every random decision
/// that affects shared match state goes through this type.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    public private(set) var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        return SplitMix64.mix(state)
    }

    /// The SplitMix64 finaliser. Also used on its own as a 64-bit hash.
    @inlinable
    public static func mix(_ value: UInt64) -> UInt64 {
        var z = value
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Order-dependent hash of a seed and extra values, e.g. `hash(matchSeed, roundNumber)`.
    public static func hash(_ seed: UInt64, _ values: UInt64...) -> UInt64 {
        var h = mix(seed)
        for v in values {
            h = mix(h ^ (v &+ 0x9E37_79B9_7F4A_7C15))
        }
        return h
    }

    /// Uniform Double in [0, 1) built from the top 53 bits (exact, portable).
    public mutating func nextUnit() -> Double {
        Double(next() >> 11) * 0x1.0p-53
    }

    /// Uniform integer in `range` (inclusive). Uses modulo; bias is negligible for
    /// the small ranges used in game rules, and the formula is easy to port.
    public mutating func nextInt(in range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % span)
    }

    /// Uniform Double in `[lower, upper)`.
    public mutating func nextDouble(_ lower: Double, _ upper: Double) -> Double {
        lower + (upper - lower) * nextUnit()
    }

    public mutating func nextBool() -> Bool {
        next() & 1 == 1
    }
}
