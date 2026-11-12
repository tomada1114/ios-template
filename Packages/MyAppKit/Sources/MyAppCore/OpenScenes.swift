import Observation

/// The app's open windows, in the order they last came to the foreground, and the one
/// decision Core makes across them: which window presents a failure.
///
/// The only state shared between scenes besides the models they all show, and only this
/// decision reads it: a refresh is still decided per scene, by ``SceneLifecycleModel``
/// alone. ``AppModel`` owns the one instance and hands it to every scene model it builds;
/// a scene model joins on its first reported phase, never when it is built, since the
/// scene root builds a spare one on every re-render.
///
/// Observable, so a window re-renders — and takes or gives up the alert — when another
/// window's phase changes the answer.
@MainActor
@Observable
final class OpenScenes {
    private struct Entry {
        let id: SceneID
        /// Weak, so a window discarded without reporting the background is skipped rather
        /// than left holding a failure nobody can see. Its going is not an observed
        /// change: the next presenter takes over at its next render.
        weak var scene: SceneLifecycleModel?
        var isInForeground: Bool
    }

    private var entries: [Entry] = []
    /// Not observed: building a scene model takes a number, and a view's render that
    /// builds a spare one must not invalidate anything.
    @ObservationIgnored private var issuedIDCount = 0

    /// The identity of the next scene model. A spare model's number is never seen again.
    func makeSceneID() -> SceneID {
        issuedIDCount += 1
        return SceneID(number: issuedIDCount)
    }

    /// Records whether `scene` is in the foreground. A scene that comes to it — for the
    /// first time or back from the background — goes last, behind every window already
    /// there; one that leaves, or reports what is already recorded, keeps its place.
    func record(_ scene: SceneLifecycleModel, isInForeground: Bool) {
        var open = entries.filter { $0.scene != nil }
        let index = open.firstIndex { $0.id == scene.id }
        if let index, open[index].isInForeground == isInForeground {
            return
        }
        if let index, !isInForeground {
            open[index].isInForeground = false
        } else {
            if let index {
                open.remove(at: index)
            }
            open.append(Entry(id: scene.id, scene: scene, isInForeground: isInForeground))
        }
        entries = open
    }

    /// The one window that presents a failure the scene `origin` caused (`nil`: no scene
    /// did), or `nil` while no window is open.
    ///
    /// Among the windows in the foreground — or among every open window while none is —
    /// it is `origin`, and otherwise the first: the one that has been there longest, so a
    /// window arriving later never takes the alert from under the person.
    func presenter(ofFailureFrom origin: SceneID?) -> SceneID? {
        let open = entries.filter { $0.scene != nil }
        let inForeground = open.filter(\.isInForeground)
        let candidates = (inForeground.isEmpty ? open : inForeground).map(\.id)
        if let origin, candidates.contains(origin) {
            return origin
        }
        return candidates.first
    }
}
