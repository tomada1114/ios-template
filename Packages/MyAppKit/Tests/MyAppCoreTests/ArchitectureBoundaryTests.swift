import Foundation
import Testing

/// The second enforcement of the module boundaries (`AGENTS.md` › Architecture).
///
/// `MyAppCore` never imports a UI, persistence, or OS-integration framework —
/// `.swiftlint.yml`'s `no_ui_import_in_core` is the first enforcement, this suite the
/// second; the lint rule runs in the `lint` job and the pre-commit hook, this suite in the
/// `test` job, so removing either one still leaves the other catching a regression.
///
/// Core also never names a Foundation type an adapter owns (`URLSession`, `UserDefaults`):
/// Core imports Foundation, so no import ban can see one, and this suite is the only
/// enforcement.
///
/// `MyAppUI` and `MyAppPlatform` are siblings over Core and never import each other.
/// SwiftPM's target graph already withholds the modules, but only until someone adds a
/// dependency edge; this suite is what makes that edit fail a check rather than compile.
///
/// `MyAppTestSupport` is test code (the fakes and the port contracts), so no shipped
/// module imports it. It is no product, so `App/` cannot link it; inside the package the
/// target graph alone would allow a dependency edit, and this suite is what refuses it.
@Suite("Architecture boundary")
struct ArchitectureBoundaryTests {
    /// Frameworks `MyAppCore` must not import: the UI frameworks (`Cocoa` re-exports
    /// AppKit), the persistence frameworks a repository adapter wraps, and the iOS
    /// services an adapter reaches for first (notifications, location, photos, purchases,
    /// widgets). Each belongs in `MyAppPlatform`, behind a Core-declared port.
    ///
    /// `os` and `OSLog` are deliberately absent: logging is not a UI or OS-integration
    /// framework, so Core logs directly through ``MyAppCore/AppLog``
    /// (`docs/architecture.md` › Logging). The "ignores other modules" case below pins
    /// that, so narrowing the list to ban them would fail a test rather than pass.
    ///
    /// Must match `.swiftlint.yml`'s `no_ui_import_in_core`: change both lists together.
    static let forbiddenModules = [
        "SwiftUI", "UIKit", "AppKit", "Cocoa",
        "SwiftData", "CoreData", "CloudKit",
        "UserNotifications", "CoreLocation", "Photos", "PhotosUI", "StoreKit", "WidgetKit",
    ]

    /// Foundation types `MyAppCore` must not name: Core imports Foundation, so no import
    /// ban can see them, yet each belongs to an adapter — `URLSession` to
    /// `URLSessionHTTPClient`, behind the ``MyAppCore/HTTPClient`` port, and `UserDefaults`
    /// to `UserDefaultsPreferences`, behind ``MyAppCore/PreferencesStoring``.
    /// `.swiftlint.yml` has no twin rule, so this list and the test that reads it are the
    /// only enforcement.
    static let forbiddenFoundationTypes = ["URLSession", "UserDefaults"]

    /// `Sources/MyAppCore`, the directory the Core ban list applies to.
    static let coreSourcesDirectory = sourcesDirectory(of: "MyAppCore")

    // MARK: - Helpers

    /// The same pattern as the lint rule: any attributes (`@preconcurrency`, `@_exported`)
    /// and an optional kind keyword (`import struct SwiftUI.Color`) before the module.
    /// The `^\s*` anchor keeps a commented-out `// import SwiftUI` from matching.
    static func pattern(forAnyOf modules: [String]) -> String {
        #"^\s*(@[\w()]+\s+)*import\s+((typealias|struct|class|enum|protocol|let|var|func)\s+)?("#
            + modules.joined(separator: "|")
            + #")\b"#
    }

    /// `Sources/<module>`, resolved from this file's path:
    /// `Tests/MyAppCoreTests/<this file>` up to the package root, then down.
    static func sourcesDirectory(of module: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent(module, isDirectory: true)
    }

    /// The compiled pattern. Simple (ICU-style) word boundaries, as in the lint rule:
    /// Swift's default Unicode boundaries treat `SwiftUI.Color` as one word, so `\b`
    /// would never match after the module in a kind-qualified import.
    static func importRegex(forAnyOf modules: [String]) throws -> Regex<AnyRegexOutput> {
        try Regex(pattern(forAnyOf: modules)).wordBoundaryKind(.simple)
    }

    static func importRegex() throws -> Regex<AnyRegexOutput> {
        try importRegex(forAnyOf: forbiddenModules)
    }

    /// Whether `line` names one of the types `regex` matches, outside a comment: a line
    /// whose first non-space characters are `//` (a comment or a `///` doc comment) may
    /// mention a type, since explaining why Core does not use it is how the rule is
    /// taught.
    static func namesType(_ line: String, matching regex: Regex<AnyRegexOutput>) -> Bool {
        !line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
            && line.firstMatch(of: regex) != nil
    }

    /// `\b<Type>\b` for any of `types`, with simple word boundaries so `URLSession.shared`
    /// matches and `URLSessionHTTPClient` does not.
    static func typeRegex(forAnyOf types: [String]) throws -> Regex<AnyRegexOutput> {
        try Regex(#"\b("# + types.joined(separator: "|") + #")\b"#).wordBoundaryKind(.simple)
    }

    /// Every `.swift` file under `directory`, recursively; empty if it does not exist.
    static func swiftFiles(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
        ) else {
            return []
        }
        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.path < $1.path }
    }

    /// Records an issue for every line in `module`'s sources that imports one of
    /// `modules`. Requires the module to have sources, so a wrong path fails here
    /// rather than passing on zero files.
    static func expectNoImports(of modules: [String], in module: String) throws {
        let directory = sourcesDirectory(of: module)
        let files = swiftFiles(in: directory)
        try #require(
            !files.isEmpty,
            "no .swift files found under \(directory.path) — is the path resolution wrong?",
        )

        let regex = try importRegex(forAnyOf: modules)
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8)
                .components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() where line.firstMatch(of: regex) != nil {
                Issue.record("\(file.path):\(index + 1): forbidden import in \(module): \(line)")
            }
        }
    }

    // MARK: - The real sources

    @Test
    func `no MyAppCore source file imports a UI, persistence, or OS-integration framework`() throws {
        try Self.expectNoImports(of: Self.forbiddenModules, in: "MyAppCore")
    }

    /// Foundation types an adapter owns never appear in Core outside a comment
    /// (``forbiddenFoundationTypes``).
    @Test
    func `no MyAppCore source file names a Foundation type an adapter owns`() throws {
        let files = Self.swiftFiles(in: Self.coreSourcesDirectory)
        try #require(
            !files.isEmpty,
            "no .swift files found under \(Self.coreSourcesDirectory.path)",
        )

        let regex = try Self.typeRegex(forAnyOf: Self.forbiddenFoundationTypes)
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8)
                .components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() where Self.namesType(line, matching: regex) {
                Issue.record(
                    "\(file.path):\(index + 1): MyAppCore names a type its adapter owns: \(line)",
                )
            }
        }
    }

    @Test
    func `no MyAppUI source file imports MyAppPlatform`() throws {
        try Self.expectNoImports(of: ["MyAppPlatform"], in: "MyAppUI")
    }

    @Test
    func `no MyAppPlatform source file imports MyAppUI`() throws {
        try Self.expectNoImports(of: ["MyAppUI"], in: "MyAppPlatform")
    }

    @Test(arguments: ["MyAppCore", "MyAppUI", "MyAppPlatform"])
    func `no shipped source file imports MyAppTestSupport`(module: String) throws {
        try Self.expectNoImports(of: ["MyAppTestSupport"], in: module)
    }

    // MARK: - The pattern itself

    @Test(arguments: [
        "import SwiftUI",
        "import UIKit",
        "import AppKit",
        "import Cocoa",
        "import SwiftData",
        "import CoreData",
        "import CloudKit",
        "import UserNotifications",
        "import CoreLocation",
        "import Photos",
        "import PhotosUI",
        "import StoreKit",
        "import WidgetKit",
        "  import SwiftUI",
        "@preconcurrency import AppKit",
        "@_exported import SwiftUI",
        "@testable @preconcurrency import UIKit",
        "import struct SwiftUI.Color",
        "import class AppKit.NSView",
        "import func Cocoa.NSApplicationMain",
        "import class SwiftData.ModelContext",
        "@preconcurrency import UserNotifications",
    ])
    func `pattern matches every spelling of a forbidden import`(line: String) throws {
        let regex = try Self.importRegex()
        #expect(line.firstMatch(of: regex) != nil)
    }

    @Test(arguments: [
        "// import SwiftUI",
        "/// import AppKit",
        "import Foundation",
        "import Observation",
        // Logging is allowed in Core — see `forbiddenModules` above.
        "import os",
        "import OSLog",
        "@preconcurrency import os",
        "import struct os.Logger",
        "import SwiftUIExtras",
        "import SwiftDataExtras",
        "import PhotosKit",
        "@preconcurrency import Combine",
        "let text = \"import SwiftUI\"",
    ])
    func `pattern ignores comments and other modules`(line: String) throws {
        let regex = try Self.importRegex()
        #expect(line.firstMatch(of: regex) == nil)
    }

    @Test(arguments: [
        ("let probe = URLSession.shared", true),
        ("    private let session: URLSession", true),
        ("// URLSession is the adapter's", false),
        ("    /// Wraps `URLSession` in MyAppPlatform.", false),
        ("let client: URLSessionHTTPClient", false),
        ("let defaults = UserDefaults.standard", true),
        ("/// `UserDefaults` stores it natively.", false),
        ("let preferences: UserDefaultsPreferences", false),
    ])
    func `the Foundation type scan catches code and skips comments`(
        line: String,
        caught: Bool,
    ) throws {
        let regex = try Self.typeRegex(forAnyOf: Self.forbiddenFoundationTypes)
        #expect(Self.namesType(line, matching: regex) == caught)
    }

    @Test
    func `file discovery finds nothing in a directory that does not exist`() {
        let missing = Self.coreSourcesDirectory.appendingPathComponent(
            "does-not-exist",
            isDirectory: true,
        )
        #expect(Self.swiftFiles(in: missing).isEmpty)
    }
}
