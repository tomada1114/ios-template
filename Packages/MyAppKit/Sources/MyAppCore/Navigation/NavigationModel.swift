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
/// The path outlives the process: the scene root stores ``encodedPath`` in the scene's
/// own storage and hands it back to ``restore(from:)`` when the scene is rebuilt, so a
/// window the system ended in the background comes back on the screen it was showing.
/// The sheet is not stored, so a restored window has none up.
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
                awaitsRestoration = false
            }
        }
    }

    /// The sheet presented over the stack, or `nil` when none is. Read-only: the root
    /// view binds `.sheet(item:)` through ``dismissSheet(_:)``, so a swipe down and the
    /// sheet's system close button (`Button(role: .close)`) both go through the action,
    /// and ``path`` stays the one property a view writes.
    public private(set) var sheet: AppSheet?

    /// Whether ``restore(from:)`` may still set the path: only until the path first
    /// changes, whoever changes it.
    @ObservationIgnored private var awaitsRestoration = true

    /// ``path`` in its stored form, for the scene root to keep in the scene's storage and
    /// hand back to ``restore(from:)`` at the next launch. The same path is always the
    /// same bytes, so observing this sees a change only when the path changed.
    ///
    /// The format is contract (`AGENTS.md` › What is contract and what is private): a
    /// later build reads what this one stored. It holds the routes and nothing else — no
    /// sheet, no draft, no scroll position.
    public var encodedPath: Data {
        StoredNavigationPath.data(for: path)
    }

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

    /// Puts back the path a previous process stored (``encodedPath``), once, and only if
    /// nothing has moved the path yet: a link that opened the window, or a push, is newer
    /// than what was stored and wins, whichever reaches the model first. Every later call
    /// does nothing, so the scene root may call it each time it appears.
    ///
    /// A route this build cannot read — a screen a later build stored, a damaged
    /// identifier — is skipped and the routes around it restore. Data that is not a
    /// stored path at all, or is of a version this build does not know, restores nothing:
    /// the window opens at the root, never a crash. Empty data is a scene that has stored
    /// nothing yet, and is not logged.
    ///
    /// A route is restored whether or not its item still exists — this model holds
    /// routes, not items, and the items have not loaded when a scene is rebuilt — so a
    /// route to an item deleted since shows the detail screen's not-found state, as a
    /// stale deep link does.
    public func restore(from data: Data) {
        guard awaitsRestoration else {
            return
        }
        awaitsRestoration = false
        guard !data.isEmpty else {
            return
        }
        do {
            path = try StoredNavigationPath.routes(from: data)
        } catch {
            // The size only: the bytes are whatever was stored, and name nothing useful.
            let size = data.count
            AppLog.navigation.error("restore: unreadable payload bytes=\(size, privacy: .public)")
        }
    }
}
