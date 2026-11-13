import MyAppCore
import Testing

/// Pins every stored secret's key name, in the manner of `PreferenceKeysTests`: a literal
/// a user's device depends on.
///
/// A failure here means someone renamed a key. A renamed key reads as absent, so every
/// user is signed out on the next launch — and the secret stored under the old name stays
/// in the Keychain, which outlives even the app's deletion. Do not edit this test to
/// match: keep the old name, or write a migration in Core that reads the old key, writes
/// the new one, and deletes the old, with a test that starts from the old key
/// (`AGENTS.md` › What is contract and what is private).
@Suite("SecureKeys")
struct SecureKeysTests {
    @Test
    func `stored key names never change`() {
        #expect(SecureKeys.authToken.name == "auth.token")
    }

    @Test
    func `keys are told apart by name alone`() {
        #expect(SecureKey(name: "auth.token") == SecureKeys.authToken)
        #expect(SecureKey(name: "auth.other") != SecureKeys.authToken)
    }
}
