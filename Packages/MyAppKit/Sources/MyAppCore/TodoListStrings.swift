import Foundation

/// Every fixed piece of wording the to-do list shows, from Core's String Catalog.
///
/// Wording lives in Core rather than in the view: a `Text("…")` literal in `MyAppUI`
/// would be looked up in the app's main bundle, not the package's catalog, and would sit
/// outside the tests. A view renders these; it never carries a literal a reader sees.
public enum TodoListStrings {
    /// The navigation title.
    public static var title: LocalizedStringResource {
        LocalizedStringResource(
            "todoList.title",
            defaultValue: "To-Do",
            bundle: .module,
            comment: "Navigation title of the to-do list screen.",
        )
    }

    /// The new-item field's placeholder.
    public static var draftPlaceholder: LocalizedStringResource {
        LocalizedStringResource(
            "todoList.draftPlaceholder",
            defaultValue: "New Item",
            bundle: .module,
            comment: "Placeholder in the text field where a new to-do item is typed.",
        )
    }

    /// The button that stores the draft.
    public static var add: LocalizedStringResource {
        LocalizedStringResource(
            "todoList.add",
            defaultValue: "Add",
            bundle: .module,
            comment: "Button that adds the typed text as a new to-do item.",
        )
    }

    /// The empty state's headline.
    public static var emptyTitle: LocalizedStringResource {
        LocalizedStringResource(
            "todoList.empty.title",
            defaultValue: "No Items",
            bundle: .module,
            comment: "Headline shown when the to-do list has no items.",
        )
    }

    /// The empty state's explanation.
    public static var emptyDescription: LocalizedStringResource {
        LocalizedStringResource(
            "todoList.empty.description",
            defaultValue: "Items you add appear here.",
            bundle: .module,
            comment: "Explanation under the empty-list headline.",
        )
    }

    /// The failure alert's title.
    public static var failureTitle: LocalizedStringResource {
        LocalizedStringResource(
            "todoList.failure.title",
            defaultValue: "Something Went Wrong",
            bundle: .module,
            comment: "Title of the alert shown when loading or saving to-do items fails.",
        )
    }

    /// The button that dismisses the failure alert.
    public static var dismiss: LocalizedStringResource {
        LocalizedStringResource(
            "todoList.failure.dismiss",
            defaultValue: "OK",
            bundle: .module,
            comment: "Button that dismisses the failure alert.",
        )
    }

    /// The button that retries a failed load.
    public static var retry: LocalizedStringResource {
        LocalizedStringResource(
            "todoList.retry",
            defaultValue: "Try Again",
            bundle: .module,
            comment: "Button that retries loading the to-do items after a failure.",
        )
    }

    /// VoiceOver's name for the toggle of an item that is not done yet.
    public static var markDone: LocalizedStringResource {
        LocalizedStringResource(
            "todoList.markDone",
            defaultValue: "Mark as Done",
            bundle: .module,
            comment: "Accessibility label for the circle that checks off a to-do item.",
        )
    }

    /// VoiceOver's name for the toggle of an item that is done.
    public static var markNotDone: LocalizedStringResource {
        LocalizedStringResource(
            "todoList.markNotDone",
            defaultValue: "Mark as Not Done",
            bundle: .module,
            comment: "Accessibility label for the checkmark that un-checks a to-do item.",
        )
    }
}
