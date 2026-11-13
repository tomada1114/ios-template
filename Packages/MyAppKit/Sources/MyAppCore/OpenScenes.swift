import Observation

/// The app's open windows, in the order they last came to the foreground, and the one
/// decision Core makes across them: which window presents a failure.
///
/// The only state shared between scenes besides the models they all show, and only this
/// decision reads it: a refresh is still decided per scene, by ``SceneLifecycleModel``
/// alone. ``AppModel`` owns the one instance and hands it to every scene model and every
/// shared model it builds. A scene joins on its first reported phase, never when it is
/// built, since the scene root builds a spare model on every re-render, and leaves when
/// it closes.
///
/// A reported failure claims one presenting window (``claim(forFailureFrom:)``) and keeps
/// it — the presenter is sticky — until that window closes, or goes to the background
/// while another window is in the foreground. Nothing else moves the alert.
///
/// Observable, so a window re-renders — and takes or gives up the alert — when a claim
/// changes hands.
@MainActor
@Observable
final class OpenScenes {
    /// One reported failure's hold on a presenting window.
    struct Claim: Hashable, Sendable {
        let number: Int
    }

    private struct Entry {
        /// Weak, so a window that went without closing is not kept alive. It is dropped at
        /// the next change; ``close(_:)`` is what a window's going normally arrives as.
        weak var scene: SceneLifecycleModel?
        var isInForeground: Bool
    }

    private struct Holder {
        /// The scene whose action caused the failure, or `nil`.
        let origin: SceneID?
        /// The window presenting it, or `nil` while no window is open.
        var presenter: SceneID?
    }

    private var entries: [Entry] = []
    private var holders: [Claim: Holder] = [:]
    private var claimCount = 0

    /// Claims a presenting window for a failure the scene `origin` caused (`nil`: no
    /// scene did): `origin` if it is in the foreground, otherwise the window that has
    /// been in the foreground longest, otherwise — none is — the first open window. With
    /// no window open the claim waits, and the first window to open takes it.
    func claim(forFailureFrom origin: SceneID?) -> Claim {
        claimCount += 1
        let claim = Claim(number: claimCount)
        holders[claim] = Holder(origin: origin, presenter: choosePresenter(for: origin))
        return claim
    }

    /// Gives `claim` up: its failure was dismissed or replaced.
    func release(_ claim: Claim) {
        holders[claim] = nil
    }

    /// The window presenting the failure that holds `claim`, or `nil`.
    func presenter(of claim: Claim) -> SceneID? {
        holders[claim]?.presenter
    }

    /// Whether `scene` presents any failure at all, whichever shared model reported it:
    /// every failure holds a claim here, so none can be left out.
    func presentsAnyFailure(_ scene: SceneID) -> Bool {
        holders.values.contains { $0.presenter == scene }
    }

    /// Records whether `scene` is in the foreground. A scene that comes to it — for the
    /// first time or back from the background — goes last, behind every window already
    /// there; one that leaves, or reports what is already recorded, keeps its place.
    ///
    /// A scene that leaves the foreground while another window is in it hands on the
    /// failures it presents; one that leaves last keeps them, so an alert is still where
    /// it was when the app comes back. Coming to the foreground takes nothing.
    func record(_ scene: SceneLifecycleModel, isInForeground: Bool) {
        var open = entries.filter { $0.scene != nil }
        let index = open.firstIndex { $0.scene === scene }
        if let index, open[index].isInForeground == isInForeground {
            // Nothing new about this scene; only a window that went without closing may
            // have to be dropped, and what it presented handed on.
            if open.count != entries.count {
                entries = open
                settleClaims(leaving: nil)
            }
            return
        }
        if let index, !isInForeground {
            open[index].isInForeground = false
        } else {
            if let index {
                open.remove(at: index)
            }
            open.append(Entry(scene: scene, isInForeground: isInForeground))
        }
        entries = open
        let handsOn = !isInForeground && open.contains(where: \.isInForeground)
        settleClaims(leaving: handsOn ? scene.id : nil)
    }

    /// Removes `scene`: its window closed. The failures it presented go to another open
    /// window at once, since this is an observed change.
    func close(_ scene: SceneLifecycleModel) {
        entries.removeAll { $0.scene == nil || $0.scene === scene }
        settleClaims(leaving: scene.id)
    }

    /// Chooses a presenter again for every claim whose presenter is `leaving`, is no
    /// longer open, or was never found.
    private func settleClaims(leaving: SceneID?) {
        let open = Set(entries.compactMap { $0.scene?.id })
        for (claim, holder) in holders {
            if let presenter = holder.presenter, presenter != leaving, open.contains(presenter) {
                continue
            }
            holders[claim]?.presenter = choosePresenter(for: holder.origin)
        }
    }

    private func choosePresenter(for origin: SceneID?) -> SceneID? {
        let open = entries.filter { $0.scene != nil }
        let inForeground = open.filter(\.isInForeground)
        let candidates = (inForeground.isEmpty ? open : inForeground).compactMap { $0.scene?.id }
        if let origin, candidates.contains(origin) {
            return origin
        }
        return candidates.first
    }
}
