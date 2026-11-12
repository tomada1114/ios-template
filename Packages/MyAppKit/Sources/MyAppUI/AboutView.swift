import MyAppCore
import SwiftUI

/// The About sheet (``AppSheet/about``): what the app is, in one sentence, and the
/// system's close button.
///
/// The template's worked sheet, over no view model of its own: everything it shows is
/// Core wording (``AboutStrings``), and its one action is `close`, which `RootView` wires
/// to ``NavigationModel/dismissSheet(_:)`` — the same action a swipe down reaches through
/// the sheet's binding. A sheet that edits something takes a view model from `AppModel`
/// the way a pushed screen does.
///
/// It brings a plain `NavigationStack` for its title and toolbar only: it pushes nothing,
/// so it has no path and no `AppRoute` destination.
struct AboutView: View {
    let close: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Text(AboutStrings.description)
            }
            // On the Form, which XCUITest sees as a collection view: on the stack, the
            // identifier would also land on every child that has none of its own.
            .accessibilityIdentifier("aboutSheet")
            .navigationTitle(Text(AboutStrings.title))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        // The system's close button: its glyph, its localized label, and
                        // its hit target, with no wording of the app's own.
                        Button(role: .close, action: close)
                            .accessibilityIdentifier("aboutCloseButton")
                    }
                }
        }
    }
}

#if DEBUG
    #Preview("About") {
        AboutView {
            // Nothing to dismiss: a preview presents no sheet.
        }
    }
#endif
