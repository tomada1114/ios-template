/// Every preference key the app stores, in one place.
///
/// These names are contract: a stored key outlives the build that wrote it. Renaming one
/// resets every user's value to its default, because the new name reads as unset. A
/// rename is therefore a migration in Core that reads the old key and writes the new one,
/// with a test that starts from the old key (`docs/architecture.md` › What is contract
/// and what is private). `PreferenceKeysTests` pins each name and default.
public enum PreferenceKeys {
    /// Whether the to-do list hides items that are done. Off until the user turns it on.
    public static let hideCompleted = PreferenceKey<Bool>(
        name: "todoList.hideCompleted",
        defaultValue: false,
    )
}
