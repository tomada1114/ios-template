import SwiftUI

/// The presentation values every screen draws from: a spacing scale, corner radii, the
/// minimum hit target, and the motion rule.
///
/// Tokens are a scale, not a style. Color and type are deliberately absent: they come from
/// the system (semantic colors, text styles, Dynamic Type), so a screen is correct in
/// light, dark, every text size, and Increase Contrast without a token for it. An app's
/// design-lock ADR may change these values; it never moves them into `MyAppCore`, which
/// does not import SwiftUI. The research behind each value is `docs/design-system.md`.
public enum DesignTokens {
    /// Gaps between elements, in points. The inset from the screen edge is not one of
    /// these: it is the system's (`List` and `Form` insets, `.padding()`), so it follows
    /// the device, the size class, and the platform.
    public enum Spacing {
        /// Between a glyph and a tightly bound caption.
        public static let xxSmall: CGFloat = 2
        /// Between lines of one grouped block (a title and its subtitle).
        public static let xSmall: CGFloat = 4
        /// Between related controls in one row.
        public static let small: CGFloat = 8
        /// Between a field and the action that submits it (the to-do list's add bar).
        public static let medium: CGFloat = 12
        /// Inside a custom container, from its edge to its content.
        public static let large: CGFloat = 16
        /// Between groups of content.
        public static let xLarge: CGFloat = 24
        /// Between sections that stand apart.
        public static let xxLarge: CGFloat = 32
    }

    /// Corner radii, in points, for a custom container the system does not draw. Always
    /// used as `RoundedRectangle(cornerRadius:style: .continuous)`, the shape the system's
    /// own containers use; a standard component keeps the radius it comes with.
    public enum Radius {
        /// A small element: a tag, a thumbnail.
        public static let small: CGFloat = 8
        /// A control-sized container: a custom field, a tile.
        public static let medium: CGFloat = 12
        /// A card or grouped container.
        public static let large: CGFloat = 20
    }

    /// Fixed sizes that are guarantees rather than style.
    public enum Size {
        /// The smallest hit region a tappable element may have, in both dimensions — the
        /// HIG's 44x44 pt for iOS. Reach it with a frame and `contentShape` around a small
        /// glyph, never by enlarging the glyph.
        public static let minimumHitTarget: CGFloat = 44
    }

    /// The motion rule: the system's own animation, or none.
    public enum Motion {
        /// The animation for a state change: `nil` when Reduce Motion is on, so the change
        /// happens without movement, and the system default otherwise. No custom durations —
        /// motion personality is an app's design-lock decision.
        ///
        /// Pass `@Environment(\.accessibilityReduceMotion)`:
        /// `withAnimation(DesignTokens.Motion.animation(reduceMotion: reduceMotion)) { … }`.
        public static func animation(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .default
        }
    }
}
