import Foundation

/// Wording the failure alert shows for every ``PresentableFailure``.
public enum FailureStrings {
    /// The button that dismisses the failure alert.
    public static var dismiss: LocalizedStringResource {
        LocalizedStringResource(
            "failure.dismiss",
            defaultValue: "OK",
            bundle: .module,
            comment: "Button that dismisses the failure alert.",
        )
    }
}
