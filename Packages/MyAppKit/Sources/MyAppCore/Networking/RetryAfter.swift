import Foundation

/// Reads an HTTP `Retry-After` header value (RFC 9110 §10.2.3) as a wait.
enum RetryAfter {
    /// The wait `value` asks for, measured from `now`, or `nil` when `value` is neither
    /// form the header allows.
    ///
    /// - Delta-seconds: one or more ASCII digits, nothing else (no sign, no fraction).
    /// - An HTTP-date in the IMF-fixdate form every sender must generate
    ///   (`Sun, 06 Nov 1994 08:49:37 GMT`). A date already past is a wait of zero, never
    ///   a negative one. RFC 850's and asctime's obsolete forms are read as `nil`:
    ///   Foundation's HTTP-date parser does not accept them, and a caller with no delay
    ///   falls back to its own backoff, which is the right answer to an unreadable header
    ///   anyway.
    static func delay(fromHeaderValue value: String, now: Date) -> Duration? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, trimmed.allSatisfy(isASCIIDigit) {
            // `Int(_:)` is nil for a value too large to be a sensible wait.
            return Int(trimmed).map { .seconds($0) }
        }
        guard let date = try? Date(trimmed, strategy: .http) else {
            return nil
        }
        return .seconds(max(0, date.timeIntervalSince(now)))
    }

    /// `0`–`9` only: `isWholeNumber` alone also accepts other scripts' digits, which
    /// delta-seconds does not.
    private static func isASCIIDigit(_ character: Character) -> Bool {
        character.isASCII && character.isWholeNumber
    }
}
