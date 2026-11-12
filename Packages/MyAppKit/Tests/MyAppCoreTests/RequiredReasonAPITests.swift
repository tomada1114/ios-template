import Foundation
import Testing

/// Ties `App/PrivacyInfo.xcprivacy` to the code: every required-reason API category the
/// shipped sources (`Packages/MyAppKit/Sources/` and `App/`, Swift and any C or
/// Objective-C) call must be declared in the manifest with at least one reason.
/// `PrivacyManifestTests` keeps the declared entries in place; this suite makes a new
/// call to, say, `ProcessInfo.systemUptime` without a matching entry a failing test
/// instead of an App Store Connect rejection.
///
/// The scan is textual (``RequiredReasonAPIScan``): code outside comments and simple
/// string literals that names a listed symbol counts as a use. So it cannot see a call
/// made inside a binary dependency or through a renamed alias, and it cannot judge
/// whether the declared reason is the right one; a domain identifier that shares a
/// symbol's name (a property called `creationDate`) is reported too, and the fix is to
/// rename it or declare the category.
@Suite("Required-reason API scan")
struct RequiredReasonAPITests {
    typealias Scan = RequiredReasonAPIScan
    typealias Use = RequiredReasonAPIScan.Use

    /// Each line paired with the categories it uses, worked out by hand from Apple's
    /// list. An explicit type keeps the `@Test` expansion cheap to type-check.
    static let scanCases: [(line: String, expected: [String])] = [
        ("let uptime = ProcessInfo.processInfo.systemUptime", [Scan.systemBootTime]),
        ("let start = mach_absolute_time()", [Scan.systemBootTime]),
        ("let clock: () -> UInt64 = mach_absolute_time", [Scan.systemBootTime]),
        ("let date = attributes[.modificationDate] as? Date", [Scan.fileTimestamp]),
        ("let keys: Set<URLResourceKey> = [.contentModificationDateKey]", [Scan.fileTimestamp]),
        ("    if stat(path, &info) == 0 {", [Scan.fileTimestamp]),
        ("if (lstat (path, &info) == 0) {", [Scan.fileTimestamp]),
        (
            "let keys: [URLResourceKey] = [.volumeAvailableCapacityForImportantUsageKey]",
            [Scan.diskSpace],
        ),
        ("NSNumber *free = attributes[NSFileSystemFreeSize];", [Scan.diskSpace]),
        ("guard statfs(path, &info) == 0 else { return }", [Scan.diskSpace]),
        ("_ = getattrlist(path, &list, &buffer, size, 0)", [Scan.fileTimestamp, Scan.diskSpace]),
        ("let modes = UITextInputMode.activeInputModes", [Scan.activeKeyboards]),
        ("let defaults = UserDefaults.standard // the app's own", [Scan.userDefaults]),
        ("NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];", [Scan.userDefaults]),
        ("@AppStorage(\"sort\") private var sort = 0", [Scan.userDefaults]),
        ("// ProcessInfo.processInfo.systemUptime is a required-reason API", []),
        ("    /// `UserDefaults` stores it natively.", []),
        ("let total = count // systemUptime would need a manifest entry", []),
        ("let sum = 1 /* UserDefaults */ + 2", []),
        ("let key = \"systemUptime\"", []),
        ("let label = \"say \\\"stat(\\\" here\"", []),
        ("let preferences: UserDefaultsPreferences", []),
        ("let probe = model.stat", []),
        ("let status = statusCode", []),
        ("let createdAt = item.createdAt", []),
        ("let entries = getattrlistbulkCount", []),
    ]

    // MARK: - The real sources

    @Test
    func `every required-reason API the shipped code calls is declared in the manifest`() throws {
        var files: [URL] = []
        for directory in Scan.sourceDirectories {
            let found = Scan.sourceFiles(in: directory)
            try #require(
                found.contains { $0.pathExtension == "swift" },
                "no .swift files found under \(directory.path) — is the path resolution wrong?",
            )
            files += found
        }

        let missing = try Scan.undeclared(
            Scan.uses(in: files),
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
    func `the scan maps each symbol to its category and skips comments and strings`(
        line: String,
        expected: [String],
    ) throws {
        #expect(try Scan.categories(usedBy: line) == expected)
    }

    @Test
    func `a block comment hides every line it spans, doc lines included`() throws {
        let text = [
            "/*",
            " * ProcessInfo.processInfo.systemUptime",
            " /* nested: UserDefaults */",
            " still a comment: stat(path, &info)",
            " */",
            "let uptime = ProcessInfo.processInfo.systemUptime",
            "/** UserDefaults */ let defaults = UserDefaults.standard",
        ].joined(separator: "\n")
        #expect(try Scan.Matcher().uses(inText: text, path: "Probe.swift") == [
            Use(location: "Probe.swift:6", category: Scan.systemBootTime),
            Use(location: "Probe.swift:7", category: Scan.userDefaults),
        ])
    }

    @Test
    func `a CRLF file reports the line an editor shows`() throws {
        let text = "import Foundation\r\n// comment\r\nlet uptime = ProcessInfo.processInfo.systemUptime\r\n"
        #expect(try Scan.Matcher().uses(inText: text, path: "Probe.swift") == [
            Use(location: "Probe.swift:3", category: Scan.systemBootTime),
        ])
    }

    @Test
    func `the scan reads Swift, C, and Objective-C files and reports each use's file and line`(
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MyAppTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let swift = directory.appending(path: "Probe.swift")
        try """
        import Foundation
        // systemUptime, in a comment
        let uptime = ProcessInfo.processInfo.systemUptime
        """.write(to: swift, atomically: true, encoding: .utf8)
        let objectiveC = directory.appending(path: "Probe.m")
        try "NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];\n"
            .write(to: objectiveC, atomically: true, encoding: .utf8)
        try "systemUptime\n".write(
            to: directory.appending(path: "Notes.txt"),
            atomically: true,
            encoding: .utf8,
        )

        let files = Scan.sourceFiles(in: directory)
        #expect(files.map(\.lastPathComponent) == ["Probe.m", "Probe.swift"])
        // The enumerator may resolve the temporary directory's symlink, so the expected
        // locations use the paths it returned.
        let paths = files.map(\.path)
        try #require(paths.count == 2)
        #expect(try Scan.uses(in: files) == [
            Use(location: "\(paths[0]):1", category: Scan.userDefaults),
            Use(location: "\(paths[1]):3", category: Scan.systemBootTime),
        ])
    }

    @Test
    func `file discovery finds nothing in a directory that does not exist`() {
        let missing = FileManager.default.temporaryDirectory
            .appending(path: "MyAppTests-missing-\(UUID().uuidString)")
        #expect(Scan.sourceFiles(in: missing).isEmpty)
    }

    @Test
    func `a use whose category the manifest does not declare is undeclared`() throws {
        let manifest = try PrivacyManifestTests.manifest(declaring: PrivacyManifestTests.entry(
            Scan.userDefaults,
            reasons: ["CA92.1"],
        ))
        let defaults = Use(location: "A.swift:1", category: Scan.userDefaults)
        let uptime = Use(location: "B.swift:2", category: Scan.systemBootTime)
        #expect(try Scan.undeclared([defaults, uptime], in: manifest) == [uptime])
    }

    @Test
    func `an entry with no reasons does not declare its category`() throws {
        let manifest = try PrivacyManifestTests.manifest(declaring: PrivacyManifestTests.entry(
            Scan.systemBootTime,
            reasons: [],
        ))
        let uptime = Use(location: "B.swift:2", category: Scan.systemBootTime)
        #expect(try Scan.undeclared([uptime], in: manifest) == [uptime])
    }
}
