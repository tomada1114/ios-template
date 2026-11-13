/// A seeded random number generator: the same seed draws the same sequence on every run
/// and every machine, so a test of anything that draws — a jittered backoff, a shuffle —
/// asserts exact values (`.claude/rules/core.md` › Inject what Core would read from the
/// world).
///
/// SplitMix64 (Steele, Lea, and Flood, 2014): small enough to read, and its output for a
/// seed is published, so `SplitMix64Tests` holds it to reference values. The standard
/// library ships no seeded generator, and this one lives under `Tests/`: shipped code
/// draws from `SystemRandomNumberGenerator`.
package struct SplitMix64: RandomNumberGenerator, Sendable {
    private static let increment: UInt64 = 0x9E37_79B9_7F4A_7C15
    private static let firstMultiplier: UInt64 = 0xBF58_476D_1CE4_E5B9
    private static let secondMultiplier: UInt64 = 0x94D0_49BB_1331_11EB
    private static let firstShift: UInt64 = 30
    private static let secondShift: UInt64 = 27
    private static let finalShift: UInt64 = 31

    private var state: UInt64

    /// A generator whose whole sequence `seed` decides.
    package init(seed: UInt64) {
        state = seed
    }

    package mutating func next() -> UInt64 {
        state &+= Self.increment
        var mixed = state
        mixed = (mixed ^ (mixed >> Self.firstShift)) &* Self.firstMultiplier
        mixed = (mixed ^ (mixed >> Self.secondShift)) &* Self.secondMultiplier
        return mixed ^ (mixed >> Self.finalShift)
    }
}
