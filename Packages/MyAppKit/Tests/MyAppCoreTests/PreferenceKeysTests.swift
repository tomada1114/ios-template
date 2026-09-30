import MyAppCore
import Testing

/// Pins every stored preference's key name and default, in the manner of `AppLogTests`:
/// a literal a user's device depends on.
///
/// A failure here means someone renamed a key or changed a default. A renamed key reads
/// as unset, so every user's saved value silently resets to the default on the next
/// launch. Do not edit this test to match: keep the old name, or write a migration in
/// Core that reads the old key, with a test that starts from the old value
/// (`docs/architecture.md` › What is contract and what is private).
@Suite("PreferenceKeys")
struct PreferenceKeysTests {
    @Test
    func `stored key names never change`() {
        #expect(PreferenceKeys.hideCompleted.name == "todoList.hideCompleted")
        #expect(PreferenceKeys.hideCompleted.defaultValue == false)
    }
}
