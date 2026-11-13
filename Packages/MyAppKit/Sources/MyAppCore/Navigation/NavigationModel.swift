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
/// A link is the one change that can arrive while something covers the stack — the
/// system delivers it whenever it likes — and UIKit drops a change to a stack while a
/// presentation over it is in flight, leaving the path naming a screen that never showed
/// (#140). So a link that arrives while a sheet is on screen (``isSheetOnScreen``) or
/// while this window presents a failure alert is kept, the newest only, and the path
/// moves when the view reports the stack clear: ``sheetDidLeave()`` and
/// ``failureAlertDidLeave()``. Until then ``path`` stays what the screen shows.
///
/// Owned per scene, in `@State` on `App/`'s scene root, and handed to the root view: the
/// app supports multiple windows, and each navigates on its own. The shared view models
/// it routes between stay app-level, in ``AppModel`` — which is why this model never
/// moves there. ``AppModel/makeNavigationModel(for:)`` builds it, over the window whose
/// failure alerts it waits on.
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

    /// Whether a sheet is on screen, which ``sheet`` alone does not say: from the moment
    /// the root view starts presenting one (``sheetDidStartPresenting()``) until it has
    /// finished leaving (``sheetDidLeave()``) — after its slide-out, whether a swipe, its
    /// close button, or a link dismissed it. Until then UIKit presents nothing from the
    /// stack and drops a change to it, so the root view hands failures to the sheet, and
    /// a link waits.
    public private(set) var isSheetOnScreen = false

    /// The route the newest link asked for while something covered the stack, until the
    /// stack is clear. Never stored (``encodedPath``): it is not a screen the person saw.
    @ObservationIgnored private var waitingRoute: AppRoute?

    /// Whether this window presents a failure alert, or is about to: asked when a link
    /// arrives and when the view reports a presentation gone, never observed.
    @ObservationIgnored private let presentsFailureAlert: @MainActor () -> Bool

    /// Whether ``restore(from:)`` may still set the path: only until the path first
    /// changes, whoever changes it.
    @ObservationIgnored private var awaitsRestoration = true

    /// ``path`` in its stored form, for the scene root to keep in the scene's storage and
    /// hand back to ``restore(from:)`` at the next launch. The same path is always the
    /// same bytes.
    ///
    /// The format is contract (`AGENTS.md` › What is contract and what is private): a
    /// later build reads what this one stored. It holds the routes and nothing else — no
    /// sheet, no draft, no scroll position.
    public var encodedPath: Data {
        StoredNavigationPath.data(for: path)
    }

    /// Creates a model at the root, with nothing pushed, for a window that presents no
    /// failure alert: a preview's, or a test's. A scene's model comes from
    /// ``AppModel/makeNavigationModel(for:)``.
    public init() {
        presentsFailureAlert = { false }
    }

    /// Creates a model at the root for a window, with nothing pushed.
    /// `presentsFailureAlert` answers whether that window presents a failure alert now.
    init(presentsFailureAlert: @escaping @MainActor () -> Bool) {
        self.presentsFailureAlert = presentsFailureAlert
    }

    /// Pushes `route` on top of whatever is pushed, dismissing any sheet so the pushed
    /// screen is the one on top. Newer than a link that still waits, which it drops.
    ///
    /// For a screen's own control, which nothing covers when it is tapped: unlike
    /// ``open(_:)`` it moves the path at once.
    public func show(_ route: AppRoute) {
        waitingRoute = nil
        sheet = nil
        path.append(route)
    }

    /// Returns to the root screen, dismissing any sheet and dropping a link that still
    /// waits. At once, as ``show(_:)`` does.
    public func popToRoot() {
        waitingRoute = nil
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
    /// At once when nothing covers the stack. Under a failure alert in this window nothing
    /// moves, a sheet included, until the person answers the alert
    /// (``failureAlertDidLeave()``); under a sheet on screen the sheet is dismissed and
    /// the path moves once it has left (``sheetDidLeave()``). A link that arrives while
    /// one waits replaces it. A link is newer than a stored path either way, so
    /// ``restore(from:)`` does nothing after one.
    ///
    /// A link the app does not understand leaves the path and the sheet alone, and a
    /// waiting link waiting, and is logged with its scheme and host only: its path and
    /// query can carry anything.
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
        awaitsRestoration = false
        waitingRoute = route
        moveToWaitingRouteIfClear()
        return true
    }

    /// Records that the root view has started presenting a sheet: one is on screen from
    /// now until ``sheetDidLeave()``. The view's to report, not ``present(_:)``'s to
    /// assume: a sheet asked for and dismissed before the view rendered it is never
    /// presented, and so never leaves.
    public func sheetDidStartPresenting() {
        isSheetOnScreen = true
    }

    /// Records that a sheet has finished leaving the screen — unless another was asked
    /// for meanwhile, which replaces it rather than uncovering the stack — and moves the
    /// path to a waiting link's screen if the stack is now clear.
    public func sheetDidLeave() {
        isSheetOnScreen = sheet != nil
        moveToWaitingRouteIfClear()
    }

    /// Records that the person answered a failure alert in this window, which is gone
    /// from the screen by the time its button's action runs, and moves on with a waiting
    /// link: its sheet is dismissed, and the path moves once nothing covers the stack.
    public func failureAlertDidLeave() {
        moveToWaitingRouteIfClear()
    }

    /// Moves the path to the waiting link's route, once neither an alert nor a sheet
    /// covers the stack. An alert comes first: nothing moves under it, so the sheet it
    /// sits on stays up too. Then the sheet is dismissed, and the path waits for it to
    /// have left.
    private func moveToWaitingRouteIfClear() {
        guard let waitingRoute, !presentsFailureAlert() else {
            return
        }
        sheet = nil
        guard !isSheetOnScreen else {
            return
        }
        self.waitingRoute = nil
        path = [waitingRoute]
    }

    /// Puts back the path a previous process stored (``encodedPath``), once, and only if
    /// nothing has moved the path yet: a link that opened the window, or a push, is newer
    /// than what was stored and wins, whichever reaches the model first. Every later call
    /// does nothing, so the scene root may call it each time it appears.
    ///
    /// The path restores up to the first route this build cannot read — a screen a later
    /// build stored, a damaged identifier — and stops there: the screens above it were
    /// pushed from it, and without it they are a stack the person never saw. Data that is
    /// not a stored path at all, or is of a version this build does not know, restores
    /// nothing: the window opens at the root, never a crash. An unknown version is what a
    /// downgrade leaves behind, so it is logged as a notice with its number; bytes that
    /// are not a stored path are logged as an error, by size only. Empty data is a scene
    /// that has stored nothing yet, and is not logged. The scene root stores
    /// ``encodedPath`` again right after this call, so stored bytes that restored
    /// nothing are replaced and are reported once, not at every launch.
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
            switch error {
            case let .unknownVersion(version):
                AppLog.navigation.notice("restore: unknown version=\(version, privacy: .public)")

            case .notAStoredPath:
                // The size only: the bytes are whatever was stored, and name nothing
                // useful.
                let size = data.count
                AppLog.navigation.error("restore: unreadable bytes=\(size, privacy: .public)")
            }
        }
    }
}
