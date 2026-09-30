/// A screen the navigation stack can push, named by the value it shows.
///
/// A route carries an identifier, never the item itself: the destination looks the item
/// up in its view model when it renders, so a pushed screen shows the current state
/// rather than a copy taken when the link was tapped, and a route parsed from a deep link
/// (``DeepLink``) is the same value as one a row pushed. A new screen adds a case here and
/// its destination in the root view's `navigationDestination(for:)`.
public enum AppRoute: Hashable, Sendable {
    /// The detail screen of one to-do item.
    case todoDetail(TodoItem.ID)
}
