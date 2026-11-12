import Foundation

/// The textual scan `RequiredReasonAPITests` runs over the shipped sources: Apple's
/// required-reason API symbols, by category, and the matcher that finds them in code
/// once comments and simple string literals are stripped.
enum RequiredReasonAPIScan {
    /// One `NSPrivacyAccessedAPICategory*` and the symbols that put an app in it.
    struct Category: Sendable {
        /// The manifest's `NSPrivacyAccessedAPIType` value.
        let name: String
        /// Names matched as whole words wherever they appear in code: Swift and
        /// Objective-C spellings, and C functions no other name shares
        /// (`mach_absolute_time`), so a function reference counts as well as a call.
        let identifiers: [String]
        /// C functions whose name is also an everyday word or a prefix (`stat`), matched
        /// only as a call: the name, optional spaces, then `(` on the same line. A
        /// reference to one (`let probe = stat`) or a call whose `(` starts the next line
        /// is not seen.
        let functions: [String]
    }

    /// A line in a scanned file that uses a category's symbol.
    struct Use: Equatable, CustomStringConvertible {
        let location: String
        let category: String

        var description: String {
            "\(location): calls a \(category) API"
        }
    }

    /// The categories' regexes, compiled once and shared by every line a scan reads.
    /// Simple word boundaries, as in `ArchitectureBoundaryTests.typeRegex(forAnyOf:)`, so
    /// `UserDefaults.standard` matches and `UserDefaultsPreferences` does not.
    struct Matcher {
        private let compiled: [(category: String, regex: Regex<AnyRegexOutput>)]

        init() throws {
            compiled = try RequiredReasonAPIScan.categories.map { category in
                var alternatives: [String] = []
                if !category.identifiers.isEmpty {
                    alternatives
                        .append(#"\b("# + category.identifiers.joined(separator: "|") + #")\b"#)
                }
                if !category.functions.isEmpty {
                    alternatives
                        .append(#"\b("# + category.functions.joined(separator: "|") + #")\s*\("#)
                }
                let regex = try Regex(alternatives.joined(separator: "|")).wordBoundaryKind(.simple)
                return (category.name, regex)
            }
        }

        /// Every use in `text`, one per line and category in table order, labelled
        /// `path:line`. Lines split on `\n` once every `\r` is gone, so a CRLF file
        /// numbers its lines as an editor does.
        func uses(inText text: String, path: String) -> [Use] {
            var extractor = CodeExtractor()
            let lines = text.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n")
            var found: [Use] = []
            for (index, line) in lines.enumerated() {
                let code = extractor.code(of: line)
                found += compiled
                    .filter { code.firstMatch(of: $0.regex) != nil }
                    .map { Use(location: "\(path):\(index + 1)", category: $0.category) }
            }
            return found
        }
    }

    /// The code on each line once comments and string literals are removed: a `//` to the
    /// end of the line, a `/* … */` block across lines (nested, as Swift allows, so a
    /// `*`-prefixed doc line inside one is skipped), and the text between a `"` and the
    /// next unescaped `"` on the same line. A multi-line `"""` string is not tracked: its
    /// inner lines read as code, so a listed name inside one is reported.
    struct CodeExtractor {
        /// The length of every delimiter the extractor skips: `/*`, `*/`, and an escape.
        private static let pairLength = 2

        private var commentDepth = 0

        /// One step inside a string literal: an escape skips two characters, and the
        /// closing quote ends the literal.
        private static func consumeString(_ rest: Substring) -> (Substring, Bool) {
            if rest.hasPrefix("\\") {
                return (rest.dropFirst(pairLength), true)
            }
            return (rest.dropFirst(), rest.first != "\"")
        }

        mutating func code(of line: String) -> String {
            var code = ""
            var inString = false
            var rest = Substring(line)
            while !rest.isEmpty {
                if commentDepth > 0 {
                    rest = consumeComment(rest)
                } else if inString {
                    (rest, inString) = Self.consumeString(rest)
                } else if rest.hasPrefix("//") {
                    break
                } else if rest.hasPrefix("/*") {
                    commentDepth += 1
                    code.append(" ")
                    rest = rest.dropFirst(Self.pairLength)
                } else {
                    inString = rest.first == "\""
                    code.append(rest.removeFirst())
                }
            }
            return code
        }

        private mutating func consumeComment(_ rest: Substring) -> Substring {
            if rest.hasPrefix("*/") {
                commentDepth -= 1
                return rest.dropFirst(Self.pairLength)
            }
            if rest.hasPrefix("/*") {
                commentDepth += 1
                return rest.dropFirst(Self.pairLength)
            }
            return rest.dropFirst()
        }
    }

    static let fileTimestamp = "NSPrivacyAccessedAPICategoryFileTimestamp"
    static let systemBootTime = "NSPrivacyAccessedAPICategorySystemBootTime"
    static let diskSpace = "NSPrivacyAccessedAPICategoryDiskSpace"
    static let activeKeyboards = "NSPrivacyAccessedAPICategoryActiveKeyboards"
    static let userDefaults = PrivacyManifestTests.userDefaultsCategory

    /// Apple's required-reason APIs, by category, in their Swift and Objective-C
    /// spellings, as listed under `NSPrivacyAccessedAPIType`, the key
    /// https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
    /// documents (checked on 2026-11-11). Apple lists `getattrlist`, `fgetattrlist`, and
    /// `getattrlistat` under both file timestamp and disk space, so a call to one needs
    /// both. `AppStorage` is not on Apple's list: it is SwiftUI's wrapper over
    /// `UserDefaults`, so it reads and writes defaults all the same.
    static let categories = [
        Category(
            name: fileTimestamp,
            identifiers: [
                "creationDate", "modificationDate", "fileModificationDate",
                "contentModificationDateKey", "creationDateKey",
                "NSFileCreationDate", "NSFileModificationDate",
                "NSURLContentModificationDateKey", "NSURLCreationDateKey",
            ],
            functions: [
                "getattrlist", "getattrlistbulk", "fgetattrlist", "getattrlistat",
                "stat", "fstat", "fstatat", "lstat",
            ],
        ),
        Category(
            name: systemBootTime,
            identifiers: ["systemUptime", "mach_absolute_time"],
            functions: [],
        ),
        Category(
            name: diskSpace,
            identifiers: [
                "volumeAvailableCapacityKey", "volumeAvailableCapacityForImportantUsageKey",
                "volumeAvailableCapacityForOpportunisticUsageKey", "volumeTotalCapacityKey",
                "systemFreeSize", "systemSize",
                "NSURLVolumeAvailableCapacityKey",
                "NSURLVolumeAvailableCapacityForImportantUsageKey",
                "NSURLVolumeAvailableCapacityForOpportunisticUsageKey",
                "NSURLVolumeTotalCapacityKey",
                "NSFileSystemFreeSize", "NSFileSystemSize",
            ],
            functions: [
                "statfs", "statvfs", "fstatfs", "fstatvfs",
                "getattrlist", "fgetattrlist", "getattrlistat",
            ],
        ),
        Category(name: activeKeyboards, identifiers: ["activeInputModes"], functions: []),
        Category(
            name: userDefaults,
            identifiers: ["UserDefaults", "NSUserDefaults", "AppStorage"],
            functions: [],
        ),
    ]

    /// The source files a scan reads: Swift, and the C and Objective-C a target could add
    /// beside it, so a `.m` file calling `NSUserDefaults` is held to the manifest too.
    static let sourceExtensions: Set = ["swift", "c", "h", "m", "mm"]

    /// The package's sources and the app shell, which ship in the same bundle.
    static let sourceDirectories = [
        RepositoryRoot.file("Packages/MyAppKit/Sources"),
        RepositoryRoot.file("App"),
    ]

    /// Every file under `directory` with one of ``sourceExtensions``, recursively; empty
    /// if it does not exist.
    static func sourceFiles(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
        ) else {
            return []
        }
        return enumerator
            .compactMap { $0 as? URL }
            .filter { sourceExtensions.contains($0.pathExtension) }
            .sorted { $0.path < $1.path }
    }

    /// Every use in `files`, through one ``Matcher``.
    static func uses(in files: [URL]) throws -> [Use] {
        let matcher = try Matcher()
        return try files.flatMap { file in
            try matcher.uses(inText: String(contentsOf: file, encoding: .utf8), path: file.path)
        }
    }

    /// The categories one line of code uses, in table order, as a file scan reads it.
    static func categories(usedBy line: String) throws -> [String] {
        try Matcher().uses(inText: line, path: "line").map(\.category)
    }

    /// The uses whose category `manifest` declares no reason for: no entry, or an entry
    /// with an empty reason list, both of which App Store Connect rejects.
    static func undeclared(_ uses: [Use], in manifest: [String: Any]) throws -> [Use] {
        try uses.filter { use in
            try PrivacyManifestTests.declaredReasons(for: use.category, in: manifest).isEmpty
        }
    }
}
