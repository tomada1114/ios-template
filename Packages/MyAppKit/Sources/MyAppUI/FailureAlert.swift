import MyAppCore
import SwiftUI

/// Presents a ``MyAppCore/PresentableFailure`` as an alert while one is set.
///
/// The app's only alert. `RootView` applies it once, outside its `NavigationStack`, so a
/// failure presents over whichever screen is on top. Attached to the root screen inside
/// the stack instead, a failure on a pushed screen showed nothing until the user went
/// back (#78).
private struct FailureAlert<Failure: PresentableFailure>: ViewModifier {
    let failure: Failure?
    let dismiss: () -> Void

    /// Derived from `failure`, so a new failure presents the alert, and every way it is
    /// dismissed — the button, or the system — goes through `dismiss`.
    private var isPresented: Binding<Bool> {
        Binding(
            get: { failure != nil },
            set: { isPresented in
                if !isPresented {
                    dismiss()
                }
            },
        )
    }

    func body(content: Content) -> some View {
        content.alert(
            // Read only while a failure is set; the blank title is never on screen.
            failure.map { Text($0.title) } ?? Text(verbatim: ""),
            isPresented: isPresented,
            presenting: failure,
        ) { _ in
            Button(FailureStrings.dismiss, action: dismiss)
        } message: { failure in
            Text(failure.message)
        }
    }
}

extension View {
    /// Presents `failure` as an alert while it is non-`nil`, and calls `dismiss` when the
    /// person dismisses it — the view model's action that clears the failure.
    ///
    /// Apply it once per navigation root, outside the stack, never on a screen inside it:
    /// an alert on a screen that is not on top does not present. Internal: `RootView` is
    /// the one caller.
    func failureAlert(
        _ failure: (some PresentableFailure)?,
        dismiss: @escaping () -> Void,
    ) -> some View {
        modifier(FailureAlert(failure: failure, dismiss: dismiss))
    }
}
