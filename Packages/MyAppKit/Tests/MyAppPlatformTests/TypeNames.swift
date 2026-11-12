import Foundation
import MyAppCore
import SwiftData

/// Strips the names a rename changes from a fully qualified type name: the enclosing
/// schema type (`AppSchemaV1.`), then the app's own modules (`MyAppPlatform.`,
/// `MyAppCore.`). Standard-library and Foundation names are left as they are.
struct TypeNames {
    private let prefixes: [String]

    init(_ version: any VersionedSchema.Type) {
        let schemaName = String(reflecting: version)
        let modules = [schemaName, String(reflecting: TodoItem.self)].compactMap { name in
            name.split(separator: ".").first.map { "\($0)." }
        }
        // The qualified schema name first, so its module is not stripped alone and
        // leave the bare schema name behind.
        prefixes = ["\(schemaName)."] + modules
    }

    /// Removes `prefix` wherever it starts a qualified name — at the start, or after `<`,
    /// `,`, ` `, `(`, or `[` — and nowhere inside another identifier.
    private static func removing(_ prefix: String, from name: String) -> String {
        let pattern = "(^|(?<=[<, (\\[]))" + NSRegularExpression.escapedPattern(for: prefix)
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return name
        }
        let range = NSRange(name.startIndex..., in: name)
        return regex.stringByReplacingMatches(in: name, range: range, withTemplate: "")
    }

    func normalized(_ type: any Any.Type) -> String {
        var name = String(reflecting: type)
        for prefix in prefixes {
            name = Self.removing(prefix, from: name)
        }
        return name
    }
}
