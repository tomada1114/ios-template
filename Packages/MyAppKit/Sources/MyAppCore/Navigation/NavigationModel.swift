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
/// moves when the view reports the stack uncovered: ``sheetDidLeave()`` and
/// ``failureAlertDidLeave()``. Until then ``path`` stays what the screen shows. A link
/// whose alert goes away unanswered (``failureAlertsDidChange()``), or that the person
/// navigates past, is dropped rather than left to surface later.
///
/// Owned per scene, in `@State` on `App/`'s scene root, and handed to the root view: the
/// app supports multiple windows, and each navigates on its own. The shared view models
/// it routes between stay app-level, in ``AppModel`` — which is why this model never
/// moves there. ``AppModel/makeNavigationModel(for:)`` builds it, over the window whose
/// failure alerts it waits on.
@MainActor
@Observable
public final class NavigationModel {
    /// A link held back while something covers the stack.
    private struct WaitingLink {
        /// The route the link asked for.
        let route: AppRoute
        /// Whether it waits for the answer to a failure alert, which only that alert's
        /// button gives: a link whose alert goes away unanswered is dropped.
        var awaitsAlertAnswer: Bool
    }

    /// Why a waiting link never showed its screen, as the log words it.
    private enum DropReason: String {
        case replacedByNewerLink = "a newer link replaced it"
        case pathMoved = "the path moved first"
        case alertLeftUnanswered = "its alert left unanswered"
    }

    /// The pushed routes, root first. Settable because `NavigationStack(path:)` writes it
    /// back when the user goes back; every other change goes through an action below.
    ///
    /// A write that changes it dismisses any sheet, as the actions do, so no path of
    /// change leaves a sheet over a stack that moved under it, and drops a link that
    /// still waits: the person went somewhere since, and a screen arriving later would
    /// replace the one they chose. A write of the same routes (a binding writing back
    /// what it read) keeps both.
    public var path: [AppRoute] = [] {
        didSet {
            if path != oldValue {
                sheet = nil
                awaitsRestoration = false
                dropWaitingLink(because: .pathMoved)
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

    /// Whether a link is held back, waiting for the stack to be uncovered. Nothing in
    /// the shipped UI shows it — by design nothing moves under an alert — so it is what
    /// a UI test waits on to know its link arrived before it answers the alert
    /// (`App/`'s Debug-only marker).
    public var hasWaitingLink: Bool {
        waitingLink != nil
    }

    /// The newest link that arrived while something covered the stack, until the stack
    /// is uncovered. Never stored (``encodedPath``): it is not a screen the person saw.
    private var waitingLink: WaitingLink?

    /// Whether this window presents a failure alert, or is about to: asked when a link
    /// arrives and when the view reports a presentation gone or changed, never observed.
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
    /// At once when nothing covers the stack. Under a failure alert in this window nothing
    /// moves, a sheet included, until the person answers the alert
    /// (``failureAlertDidLeave()``); under a sheet on screen the sheet is dismissed and
    /// the path moves once it has left (``sheetDidLeave()``). A link that arrives while
    /// one waits replaces it. A link is newer than a stored path either way, so
    /// ``restore(from:)`` does nothing after one. A link that never shows its screen is
    /// logged with the reason, never with what it named.
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
        dropWaitingLink(because: .replacedByNewerLink)
        let isUnderAlert = presentsFailureAlert()
        waitingLink = WaitingLink(route: route, awaitsAlertAnswer: isUnderAlert)
        if !isUnderAlert {
            sheet = nil
            showWaitingLinkIfNoSheetIsOnScreen()
        }
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
    /// for meanwhile, which replaces it rather than uncovering the stack — and shows a
    /// waiting link's screen if the stack is now uncovered.
    ///
    /// It never dismisses a sheet itself. One asked for since the link arrived is newer
    /// than the link, which goes on waiting until that sheet has left too; and clearing
    /// a sheet the view has not presented yet would leave ``isSheetOnScreen`` set with no
    /// sheet ever leaving to clear it.
    ///
    /// If a failure arrived while the sheet was leaving, its alert presents over the
    /// stack now, and the link waits for its answer instead: a push must not land on an
    /// alert that is coming up. A link that was already waiting for an answer, whose
    /// alert is gone without one, is dropped.
    public func sheetDidLeave() {
        isSheetOnScreen = sheet != nil
        guard let link = waitingLink else {
            return
        }
        if presentsFailureAlert() {
            waitingLink?.awaitsAlertAnswer = true
        } else if link.awaitsAlertAnswer {
            dropWaitingLink(because: .alertLeftUnanswered)
        } else {
            showWaitingLinkIfNoSheetIsOnScreen()
        }
    }

    /// Records that the person answered a failure alert in this window, and moves on
    /// with a link that waited for the answer: its sheet is dismissed, and its screen
    /// shows once no sheet is on screen. If another alert is up by now, the link waits
    /// for that one's answer.
    ///
    /// Called from the alert button's action, and the path may move in the same turn:
    /// UIKit has finished taking an alert down when it runs a button's action. SwiftUI
    /// reports no later moment, and the five prototype runs of #140 that pushed straight
    /// from this call pushed without UIKit's "navigation stack will not be updated".
    public func failureAlertDidLeave() {
        guard waitingLink != nil, !presentsFailureAlert() else {
            return
        }
        waitingLink?.awaitsAlertAnswer = false
        sheet = nil
        showWaitingLinkIfNoSheetIsOnScreen()
    }

    /// Records that the failure alerts this window presents changed. A link waiting for
    /// an alert's answer is dropped if the window now presents none: its alert was taken
    /// down by code — the failure went to another window, or was cleared — and no button
    /// was tapped.
    ///
    /// Dropped, not shown: the alert is still on its way out when this is called, SwiftUI
    /// does not say when it has gone, and a push into a presentation in flight is what
    /// UIKit drops (#140). Kept for some later moment instead, the link would replace
    /// whatever the person was looking at by then. ``failureAlertDidLeave()`` runs first
    /// when a button caused the change, so an answered alert's link is never dropped.
    public func failureAlertsDidChange() {
        guard let link = waitingLink, link.awaitsAlertAnswer, !presentsFailureAlert() else {
            return
        }
        dropWaitingLink(because: .alertLeftUnanswered)
    }

    /// Shows the waiting link's screen unless a sheet is still on screen, whose leaving
    /// (``sheetDidLeave()``) comes back here.
    private func showWaitingLinkIfNoSheetIsOnScreen() {
        guard let link = waitingLink, !isSheetOnScreen else {
            return
        }
        waitingLink = nil
        path = [link.route]
    }

    /// Forgets the waiting link, if there is one, and logs why: a link the person opened
    /// that never showed its screen should not vanish without a trace. Only the reason is
    /// logged, never the route.
    private func dropWaitingLink(because reason: DropReason) {
        guard waitingLink != nil else {
            return
        }
        waitingLink = nil
        let why = reason.rawValue
        AppLog.navigation.notice("open: waiting link dropped: \(why, privacy: .public)")
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
