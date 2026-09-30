import Foundation

extension LocalizedStringResource {
    /// The string this resource renders as in English, the catalog's source language.
    /// Expectations resolve in it explicitly, so a test's expected string does not depend
    /// on the language of the machine running it.
    var english: String {
        var resource = self
        resource.locale = Locale(identifier: "en")
        return String(localized: resource)
    }
}
