/// A sheet a window can present over its navigation stack, named by what it shows.
///
/// Like ``AppRoute``, a case carries at most an identifier, never a copy of the value it
/// shows, so a sheet presented from a test or a future deep link is the same value as one
/// a button presented. A new sheet adds a case here and its branch in `RootView`'s sheet
/// switch; one presents at a time (``NavigationModel/present(_:)``).
public enum AppSheet: Hashable, Identifiable, Sendable {
    /// What the app is, with a Done button that dismisses it.
    case about

    /// The sheet itself, so `.sheet(item:)` presents a new sheet when the case changes
    /// and keeps it when the same case is presented again.
    public var id: Self {
        self
    }
}
