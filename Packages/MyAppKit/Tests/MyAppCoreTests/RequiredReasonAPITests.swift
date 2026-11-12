import Foundation
import Testing

/// Ties `App/PrivacyInfo.xcprivacy` to the code: every required-reason API category the
/// shipped sources (`Packages/MyAppKit/Sources/` and `App/`) call must be declared in the
/// manifest with at least one reason. `PrivacyManifestTests` keeps the declared entries
/// in place; this suite makes a new call to, say, `ProcessInfo.systemUptime` without a
/// matching entry a failing test instead of an App Store Connect rejection.
///
/// The scan is textual, in the style of `ArchitectureBoundaryTests`: a line outside a
/// `//` comment that names one of ``categories``' symbols counts as a use. So it cannot
/// see a call made inside a binary dependency or through a renamed alias, and it cannot
/// judge whether the declared reason is the right one; a domain identifier that shares a
/// symbol's name (a property called `creationDate`) is reported too, and the fix is to
/// rename it or declare the category.
@Suite("Required-reason API scan")
struct RequiredReasonAPITests {
    /// One `NSPrivacyAccessedAPICategory*` and the symbols that put an app in it.
    struct Category: Sendable {
        /// The manifest's `NSPrivacyAccessedAPIType` value.
        let name: String
        /// Swift names matched as whole words (`systemUptime`, `.modificationDate`).
        let identifiers: [String]
        /// C functions matched only as a call, the name followed by `(`, so a word like
        /// `stat` in an identifier or a string does not count.
        let functions: [String]
    }

    /// A line in a scanned file that names a category's symbol.
    struct Use: Equatable, CustomStringConvertible {
        let location: String
        let category: String

        var description: String {
            "\(location): calls a \(category) API"
        }
    }

    static let fileTimestamp = "NSPrivacyAccessedAPICategoryFileTimestamp"
    static let systemBootTime = "NSPrivacyAccessedAPICategorySystemBootTime"
    static let diskSpace = "NSPrivacyAccessedAPICategoryDiskSpace"
    static let activeKeyboards = "NSPrivacyAccessedAPICategoryActiveKeyboards"
    static let userDefaults = PrivacyManifestTests.userDefaultsCategory

    /// Apple's required-reason APIs, by category, as listed under `NSPrivacyAccessedAPIType`,
    /// the key https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
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
            ],
            functions: [
                "getattrlist", "getattrlistbulk", "fgetattrlist", "getattrlistat",
                "stat", "fstat", "fstatat", "lstat",
            ],
        ),
        Category(
            name: systemBootTime,
            identifiers: ["systemUptime"],
            functions: ["mach_absolute_time"],
        ),
        Category(
            name: diskSpace,
            identifiers: [
                "volumeAvailableCapacityKey", "volumeAvailableCapacityForImportantUsageKey",
                "volumeAvailableCapacityForOpportunisticUsageKey", "volumeTotalCapacityKey",
                "systemFreeSize", "systemSize",
            ],
            functions: [
                "statfs", "statvfs", "fstatfs", "fstatvfs",
                "getattrlist", "fgetattrlist", "getattrlistat",
            ],
        ),
        Category(name: activeKeyboards, identifiers: ["activeInputModes"], functions: []),
        Category(name: userDefaults, identifiers: ["UserDefaults", "AppStorage"], functions: []),
    ]

    /// The package's `Sources/`, resolved from this file's path like
    /// `ArchitectureBoundaryTests.sourcesDirectory(of:)`.
    static let packageSourcesDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources", isDirectory: true)

    /// The app shell, whose sources ship in the same bundle as the package's.
    static let appDirectory = RepositoryRoot.file("App")

    /// Each line paired with the categories it uses, worked out by hand from Apple's
    /// list. An explicit type keeps the `@Test` expansion cheap to type-check.
    static let scanCases: [(line: String, expected: [String])] = [
        ("let uptime = ProcessInfo.processInfo.systemUptime", [Self.systemBootTime]),
        ("let start = mach_absolute_time()", [Self.systemBootTime]),
        ("let date = attributes[.modificationDate] as? Date", [Self.fileTimestamp]),
        ("let keys: Set<URLResourceKey> = [.contentModificationDateKey]", [Self.fileTimestamp]),
        ("    if stat(path, &info) == 0 {", [Self.fileTimestamp]),
        ("_ = lstat (path, &info)", [Self.fileTimestamp]),
        (
            "let keys: [URLResourceKey] = [.volumeAvailableCapacityForImportantUsageKey]",
            [Self.diskSpace],
        ),
        ("let free = attributes[.systemFreeSize] as? Int64", [Self.diskSpace]),
        ("guard statfs(path, &info) == 0 else { return }", [Self.diskSpace]),
        ("_ = getattrlist(path, &list, &buffer, size, 0)", [Self.fileTimestamp, Self.diskSpace]),
        ("let modes = UITextInputMode.activeInputModes", [Self.activeKeyboards]),
        ("let defaults = UserDefaults.standard", [Self.userDefaults]),
        ("@AppStorage(\"sort\") private var sort = 0", [Self.userDefaults]),
        ("// ProcessInfo.processInfo.systemUptime is a required-reason API", []),
        ("    /// `UserDefaults` stores it natively.", []),
        ("let preferences: UserDefaultsPreferences", []),
        ("let statistics = model.stat", []),
        ("let status = statusCode", []),
        ("let createdAt = item.createdAt", []),
        ("let entries = getattrlistbulkCount", []),
    ]

    // MARK: - Helpers

    /// One regex per category: its identifiers as whole words, its functions as calls.
    /// Simple word boundaries, as in `ArchitectureBoundaryTests.typeRegex(forAnyOf:)`, so
    /// `UserDefaults.standard` matches and `UserDefaultsPreferences` does not.
    static func compiledCategories() throws -> [(name: String, regex: Regex<AnyRegexOutput>)] {
        try categories.map { category in
            var alternatives: [String] = []
            if !category.identifiers.isEmpty {
                alternatives.append(#"\b("# + category.identifiers.joined(separator: "|") + #")\b"#)
            }
            if !category.functions.isEmpty {
                alternatives
                    .append(#"\b("# + category.functions.joined(separator: "|") + #")\s*\("#)
            }
            let regex = try Regex(alternatives.joined(separator: "|")).wordBoundaryKind(.simple)
            return (category.name, regex)
        }
    }

    /// The categories `line` uses, in table order, outside a `//` comment.
    static func categories(usedBy line: String) throws -> [String] {
        try compiledCategories()
            .filter { ArchitectureBoundaryTests.namesType(line, matching: $0.regex) }
            .map(\.name)
    }

    /// Every use in `files`, one per line and category, labelled `path:line`.
    static func uses(in files: [URL]) throws -> [Use] {
        let compiled = try compiledCategories()
        var found: [Use] = []
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8)
                .components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() {
                let matched = compiled.filter { category in
                    ArchitectureBoundaryTests.namesType(line, matching: category.regex)
                }
                found += matched.map { category in
                    Use(location: "\(file.path):\(index + 1)", category: category.name)
                }
            }
        }
        return found
    }

    /// The uses whose category `manifest` declares no reason for: no entry, or an entry
    /// with an empty reason list, both of which App Store Connect rejects.
    static func undeclared(_ uses: [Use], in manifest: [String: Any]) throws -> [Use] {
        try uses.filter { use in
            try PrivacyManifestTests.declaredReasons(for: use.category, in: manifest).isEmpty
        }
    }

    // MARK: - The real sources

    @Test
    func `every required-reason API the shipped code calls is declared in the manifest`() throws {
        var files: [URL] = []
        for directory in [Self.packageSourcesDirectory, Self.appDirectory] {
            let found = ArchitectureBoundaryTests.swiftFiles(in: directory)
            try #require(
                !found.isEmpty,
                "no .swift files found under \(directory.path) — is the path resolution wrong?",
            )
            files += found
        }

        let missing = try Self.undeclared(
            Self.uses(in: files),
            in: PrivacyManifestTests.shippedManifest(),
        )
        for use in missing {
            Issue.record("""
            \(use): \(PrivacyManifestTests.manifestPath) declares no reason for \
            \(use.category). Add an NSPrivacyAccessedAPITypes entry with Apple's reason \
            for this use (integrating-system-apis › references/permissions.md).
            """)
        }
    }

    // MARK: - The scan itself

    @Test(arguments: scanCases)
    func `the scan maps each symbol to its category and skips comments`(
        line: String,
        expected: [String],
    ) throws {
        #expect(try Self.categories(usedBy: line) == expected)
    }

    @Test
    func `the scan reports each use with its file and line`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MyAppTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "Probe.swift")
        try """
        import Foundation
        // systemUptime, in a comment
        let uptime = ProcessInfo.processInfo.systemUptime
        let defaults = UserDefaults.standard
        """.write(to: file, atomically: true, encoding: .utf8)

        #expect(try Self.uses(in: [file]) == [
            Use(location: "\(file.path):3", category: Self.systemBootTime),
            Use(location: "\(file.path):4", category: Self.userDefaults),
        ])
    }

    @Test
    func `a use whose category the manifest does not declare is undeclared`() throws {
        let manifest = try PrivacyManifestTests.manifest(declaring: PrivacyManifestTests.entry(
            Self.userDefaults,
            reasons: ["CA92.1"],
        ))
        let defaults = Use(location: "A.swift:1", category: Self.userDefaults)
        let uptime = Use(location: "B.swift:2", category: Self.systemBootTime)
        #expect(try Self.undeclared([defaults, uptime], in: manifest) == [uptime])
    }

    @Test
    func `an entry with no reasons does not declare its category`() throws {
        let manifest = try PrivacyManifestTests.manifest(declaring: PrivacyManifestTests.entry(
            Self.systemBootTime,
            reasons: [],
        ))
        let uptime = Use(location: "B.swift:2", category: Self.systemBootTime)
        #expect(try Self.undeclared([uptime], in: manifest) == [uptime])
    }
}
