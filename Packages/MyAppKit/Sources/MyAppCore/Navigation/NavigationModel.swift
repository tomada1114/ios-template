import Foundation
import Observation

/// Which screens are pushed, and which sheet is presented over them: the navigation path
/// and the sheet as Core state.
///
/// The root view binds its `NavigationStack(path:)` to ``path`` and its `.sheet(item:)` to
/// ``sheet``, so a row's link, a button, a deep link, and a test all move through the same
/// values — deep links and state restoration have something to hold on to, and a test
/// drives navigation without a view. One model per navigation stack: a tab-based app
/// keeps one per tab.
///
/// The sheet sits over the stack, so anything that moves the stack dismisses it: a write
/// to ``path`` that changes it, and the actions ``show(_:)``, ``popToRoot()``, and a link
/// ``open(_:)`` accepts. The screen asked for would otherwise change out of sight, under
/// the sheet.
///
/// Owned per scene, in `@State` on `App/`'s scene root, and handed to the root view: the
/// app supports multiple windows, and each navigates on its own. The shared view models
/// it routes between stay app-level, in ``AppModel`` — which is why this model never
/// moves there.
@MainActor
@Observable
public final class NavigationModel {
    /// The pushed routes, root first. Settable because `NavigationStack(path:)` writes it
    /// back when the user goes back; every other change goes through an action below.
    ///
    /// A write that changes it dismisses any sheet, as the actions do, so no path of
    /// change leaves a sheet over a stack that moved under it. A write of the same routes
    /// (a binding writing back what it read) keeps the sheet.
    public var path: [AppRoute] = [] {
        didSet {
            if path != oldValue {
                sheet = nil
            }
        }
    }

    /// The sheet presented over the stack, or `nil` when none is. Read-only: the root
    /// view binds `.sheet(item:)` through ``dismissSheet(_:)``, so a swipe down and the
    /// sheet's system close button (`Button(role: .close)`) both go through the action,
    /// and ``path`` stays the one property a view writes.
    public private(set) var sheet: AppSheet?

    /// Creates a model at the root, with nothing pushed.
    public init() {
        // Nothing to set up: `path` starts empty, no sheet is up, and nothing is read
        // until a route arrives.
    }

    /// Pushes `route` on top of whatever is pushed, dismissing any sheet so the pushed
    /// screen is the one on top.
    public func show(_ route: AppRoute) {
        sheet = nil
        path.append(route)
    }

    /// Returns to the root screen, dismissing any sheet.
    public func popToRoot() {
        sheet = nil
        path.removeAll()
    }

    /// Presents `sheet` over the stack, leaving the path as it is. A sheet already up is
    /// replaced, never stacked: one sheet presents at a time.
    public func present(_ sheet: AppSheet) {
        self.sheet = sheet
    }

    /// Dismisses whatever sheet is up, if one is.
    public func dismissSheet() {
        sheet = nil
    }

    /// Dismisses `sheet` if it is still the one up, and otherwise does nothing: what the
    /// sheet's close button and the root view's sheet binding call, each naming the sheet
    /// that closed. A dismissal that arrives after another sheet was presented names the
    /// old one, so it cannot close the new one.
    public func dismissSheet(_ sheet: AppSheet) {
        if self.sheet == sheet {
            self.sheet = nil
        }
    }

    /// Opens the screen a deep link names (``DeepLink/route(for:)``), replacing whatever
    /// is pushed and dismissing any sheet, so the link lands on its screen one step from
    /// the root rather than on top of an unrelated stack or under a sheet.
    ///
    /// A link the app does not understand leaves the path and the sheet alone and is
    /// logged with its scheme and host only: its path and query can carry anything.
    ///
    /// - Returns: whether the link named a route.
    @discardableResult
    public func open(_ url: URL) -> Bool {
        guard let route = DeepLink.route(for: url) else {
            let scheme = url.scheme ?? "none"
            let host = url.host() ?? "none"
            AppLog.navigation.error(
                "open: rejected scheme=\(scheme, privacy: .public) host=\(host, privacy: .public)",
            )
            return false
        }
        sheet = nil
        path = [route]
        return true
    }
}
