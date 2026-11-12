import Foundation

/// Where one scene stands in its lifecycle: Core's mirror of SwiftUI's `ScenePhase`,
/// which Core may not import. `App/` maps each value it observes to one of these and
/// hands it to ``AppModel/sceneDidEnter(_:scene:)``.
public enum LifecyclePhase: Equatable, Sendable {
    /// In the foreground and receiving events.
    case active
    /// Not visible: the user switched away, or the window closed.
    case background
    /// Visible but not receiving events — Control Center, a system alert, the app
    /// switcher — and every step between the background and active.
    case inactive
}
