import Foundation

/// How long a UI test waits for the app, in one place for every test file: a wait is
/// always a predicate with one of these timeouts, never a `sleep`.
enum Timeout {
    static let launch: TimeInterval = 20
    static let elementAppears: TimeInterval = 5
    static let keyboardFocus: TimeInterval = 3
    /// How long a system prompt ("Open in …?") gets to show before a test goes on.
    static let systemPrompt: TimeInterval = 3
}
