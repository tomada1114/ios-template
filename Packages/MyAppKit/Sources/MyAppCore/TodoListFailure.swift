import Foundation

/// A failure the list reports, from whichever screen caused it — the detail screen's
/// toggle is the list's. Which store failed, and why, stays in the log.
public enum TodoListFailure: Equatable, PresentableFailure {
    /// A delete could not be completed.
    case deleteFailed
    /// ``TodoListViewModel/load()`` could not read the repository.
    case loadFailed
    /// An add or a toggle could not be saved.
    case saveFailed

    /// Every case shares one headline; ``message`` says what did not happen.
    public var title: LocalizedStringResource {
        TodoListStrings.failureTitle
    }

    /// The sentence the alert shows for this failure.
    public var message: LocalizedStringResource {
        switch self {
        case .deleteFailed:
            LocalizedStringResource(
                "todoList.failure.delete",
                defaultValue: "The item could not be deleted.",
                bundle: .module,
                comment: "Alert message when deleting a to-do item failed.",
            )

        case .loadFailed:
            LocalizedStringResource(
                "todoList.failure.load",
                defaultValue: "Your items could not be loaded.",
                bundle: .module,
                comment: "Alert message when the saved to-do items could not be read.",
            )

        case .saveFailed:
            LocalizedStringResource(
                "todoList.failure.save",
                defaultValue: "Your change could not be saved.",
                bundle: .module,
                comment: "Alert message when adding or checking off a to-do item could not be saved.",
            )
        }
    }
}
