/// A type a preference can hold: one `UserDefaults` stores natively, so the adapter reads
/// it back with a plain `as?` and a stored value survives a round trip unchanged.
///
/// Only `Bool`, `Int`, `Double`, and `String` conform. A richer value (a date, an enum, a
/// small struct) is stored as one of these and converted in Core, where a test sees the
/// conversion — never as an archived blob only the adapter can read.
public protocol PreferenceValue: Sendable, Equatable {}

extension Bool: PreferenceValue {}

extension Int: PreferenceValue {}

extension Double: PreferenceValue {}

extension String: PreferenceValue {}
