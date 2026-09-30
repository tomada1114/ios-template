import MyAppCore
import SwiftUI

/// The done toggle a to-do row and the detail screen share: a glyph with a full-size hit
/// region and a spoken label.
///
/// Borderless, so only the glyph toggles: in a list row that is also a navigation link, a
/// default-styled button would take the whole row's tap and follow the link instead. The
/// caller adds the accessibility identifier, which differs per screen.
struct TodoDoneToggle: View {
    let isDone: Bool
    let label: LocalizedStringResource
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .imageScale(.large)
                .foregroundStyle(isDone ? Color.accentColor : Color.secondary)
                // The glyph is smaller than a fingertip; the hit region is not.
                .frame(
                    minWidth: DesignTokens.Size.minimumHitTarget,
                    minHeight: DesignTokens.Size.minimumHitTarget,
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text(label))
    }
}
