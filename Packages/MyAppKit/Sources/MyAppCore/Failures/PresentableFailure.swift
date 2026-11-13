import Foundation

/// A failure a person is told about: the wording of the one failure alert `RootView`
/// presents, over whichever screen is on top.
///
/// A view model's failure type adopts it (``TodoListFailure`` is the worked example), so
/// the alert in `MyAppUI` renders any feature's failure without knowing the feature, and
/// every word it shows stays in Core's String Catalog. What failed, and why, belongs in
/// the log, never here: both strings are shown as they are.
public protocol PresentableFailure: Sendable {
    /// The alert's headline.
    var title: LocalizedStringResource { get }
    /// The sentence under the headline: what did not happen.
    var message: LocalizedStringResource { get }
}
