import Foundation
import MyAppCore
import Testing

/// The English each fixed piece of list wording renders as.
///
/// A stand-in until the String Catalog harness (`LocalizationTests`, which holds every
/// `LocalizedStringResource` key in Core to the catalog) is ported from the macOS
/// template; that suite supersedes this one.
@Suite("TodoListStrings")
struct TodoListStringsTests {
    @Test(arguments: [
        (TodoListStrings.title, "To-Do"),
        (TodoListStrings.draftPlaceholder, "New Item"),
        (TodoListStrings.add, "Add"),
        (TodoListStrings.emptyTitle, "No Items"),
        (TodoListStrings.emptyDescription, "Items you add appear here."),
        (TodoListStrings.failureTitle, "Something Went Wrong"),
        (TodoListStrings.dismiss, "OK"),
        (TodoListStrings.retry, "Try Again"),
        (TodoListStrings.markDone, "Mark as Done"),
        (TodoListStrings.markNotDone, "Mark as Not Done"),
    ])
    func `each string renders its English`(resource: LocalizedStringResource, english: String) {
        #expect(resource.english == english)
    }
}
