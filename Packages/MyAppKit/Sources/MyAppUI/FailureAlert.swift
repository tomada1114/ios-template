import MyAppCore
import SwiftUI

/// Presents a ``MyAppCore/PresentableFailure`` as an alert while one is set.
///
/// The app's only alert. `RootView` applies it to each presentation layer — outside its
/// `NavigationStack`, and on its sheet's content — and hands the failure only to the
/// topmost (`failureAlerts(on:isTopmost:)`). Attached to the root screen inside the stack
/// instead, a failure on a pushed screen showed nothing until the user went back (#78);
/// attached only outside the stack, a failure while a sheet was up did not show over it
/// (#124). Which window is handed a shared model's failure at all is Core's
/// (`SceneLifecycleModel.todoListFailure`, #133).
private struct FailureAlert<Failure: PresentableFailure>: ViewModifier {
    let failure: Failure?
    let dismiss: () -> Void

    /// Derived from `failure`, so a new failure presents the alert. Only the alert's button
    /// clears the failure: SwiftUI also writes `false` when it tears the presentation down
    /// — the sheet under the alert closed by code, or the failure handed to another layer
    /// or another window — and the failure must survive that to present again where it is
    /// handed next.
    private var isPresented: Binding<Bool> {
        Binding(
            get: { failure != nil },
            set: { _ in
                // Not a dismissal by the person: theirs is the button's `dismiss`.
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
    /// person taps its button — the view model's action that clears the failure.
    ///
    /// Applied only by `RootView`'s `failureAlerts(on:isTopmost:)`, to each presentation
    /// layer, never to a screen inside the stack: an alert on a screen that is not on top
    /// does not present. Internal: `RootView` is the one caller.
    func failureAlert(
        _ failure: (some PresentableFailure)?,
        dismiss: @escaping () -> Void,
    ) -> some View {
        modifier(FailureAlert(failure: failure, dismiss: dismiss))
    }
}
