import Foundation

/// Every fixed piece of wording the to-do detail screen shows, from Core's String Catalog.
///
/// The detail screen's own wording, beside ``TodoListStrings`` rather than inside it; the
/// done toggle's label is the list's (``TodoListViewModel/toggleLabel(for:)``).
public enum TodoDetailStrings {
    /// The label beside the item's creation date.
    public static var created: LocalizedStringResource {
        LocalizedStringResource(
            "todoDetail.created",
            defaultValue: "Created",
            bundle: .module,
            comment: "Label beside the date a to-do item was created, on its detail screen.",
        )
    }

    /// The headline shown when the item a link or a row named no longer exists.
    public static var notFoundTitle: LocalizedStringResource {
        LocalizedStringResource(
            "todoDetail.notFound.title",
            defaultValue: "Item Not Found",
            bundle: .module,
            comment: "Headline on the detail screen when the to-do item it should show does not exist.",
        )
    }

    /// The explanation under the not-found headline.
    public static var notFoundDescription: LocalizedStringResource {
        LocalizedStringResource(
            "todoDetail.notFound.description",
            defaultValue: "It may have been deleted.",
            bundle: .module,
            comment: "Explanation under the item-not-found headline on the detail screen.",
        )
    }
}
