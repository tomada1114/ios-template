#if DEBUG
    import MyAppCore
    import SwiftUI

    /// Adds an invisible accessibility element that exists while the window's
    /// ``MyAppCore/NavigationModel`` holds a link back, for `LaunchUITests` alone.
    ///
    /// A link that arrives under a failure alert moves nothing until the alert is
    /// answered, so nothing on screen tells a UI test that its link has arrived and is
    /// waiting, rather than still on its way or already shown. This element is that
    /// signal: the test waits for it before it taps the alert's button (#140). Debug-only,
    /// and `App/`'s scene root applies it only under `-uiTesting`, so no person and no
    /// Release build ever meets it.
    public struct WaitingLinkMarker: ViewModifier {
        /// What `LaunchUITests` looks the element up by.
        private static let identifier = "waitingLinkMarker"

        private let navigation: NavigationModel

        /// Marks the link `navigation` holds back, for as long as it does.
        public init(navigation: NavigationModel) {
            self.navigation = navigation
        }

        public func body(content: Content) -> some View {
            content.overlay(alignment: .topLeading) {
                if navigation.hasWaitingLink {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityIdentifier(Self.identifier)
                        .allowsHitTesting(false)
                }
            }
        }
    }
#endif
