/// Every secret the app stores, in one place.
///
/// These names are contract, and a harder one than ``PreferenceKeys``: a secret outlives
/// the build that wrote it and, in the Keychain, even the app's deletion. A renamed key
/// reads as absent — every user is signed out — while the secret under the old name stays
/// on the device. A rename is therefore a migration in Core that reads the old key,
/// writes the new one, and deletes the old, with a test that starts from the old key
/// (`AGENTS.md` › What is contract and what is private). `SecureKeysTests` pins each
/// name.
public enum SecureKeys {
    /// The credential the app presents to its backend. The template stores nothing under
    /// it: it is the worked example of a key, here so the first app that signs a user in
    /// reaches for ``SecureStoring`` rather than for a preference.
    public static let authToken = SecureKey(name: "auth.token")
}
