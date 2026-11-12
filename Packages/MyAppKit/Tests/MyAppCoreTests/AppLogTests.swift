import Foundation
import MyAppCore
import Testing

/// ``AppLog/subsystem`` is the only place this app's unified-log subsystem is spelled,
/// and it has to stay the bundle identifier `project.yml` declares: `just logs` streams
/// `subsystem == "$(scripts/bundle-id.sh)"`, which reads that manifest. Both spellings
/// are placeholder literals `scripts/bootstrap.sh` rewrites together, so they can only
/// drift when someone edits one by hand — this suite is what makes that a failing test
/// instead of a log stream that silently shows nothing.
@Suite("AppLog")
struct AppLogTests {
    /// The `project.yml` key that declares the app target's bundle identifier.
    static let settingKey = "PRODUCT_BUNDLE_IDENTIFIER"

    /// The checkout root, resolved from this file's path:
    /// `Packages/MyAppKit/Tests/MyAppCoreTests/<this file>`, five levels up.
    static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    // MARK: - Helpers

    /// The bundle identifier a `project.yml` declares, read by ``ProjectManifest`` with
    /// `scripts/bundle-id.sh`'s rules so this test and that script can never disagree
    /// about one manifest. The value is compared for equality rather than containment,
    /// so `com.example.MyApp.Helper` is not `com.example.MyApp`.
    static func declaredBundleIdentifier(inManifest manifest: String) -> String? {
        ProjectManifest.value(of: settingKey, inManifest: manifest)
    }

    // MARK: - The real manifest

    @Test
    func `the log subsystem is the bundle identifier project yml declares`() throws {
        let manifest = Self.repositoryRoot.appendingPathComponent("project.yml")
        let declared = try Self.declaredBundleIdentifier(
            inManifest: String(contentsOf: manifest, encoding: .utf8),
        )
        #expect(
            declared == AppLog.subsystem,
            """
            \(manifest.path) declares \(declared ?? "no bundle identifier").
            AppLog.subsystem and project.yml must name the same bundle identifier, or
            `just logs` filters on a subsystem nothing in the app logs to.
            """,
        )
    }

    @Test
    func `the log subsystem is a well formed bundle identifier`() {
        // The same shape scripts/bundle-id.sh accepts: alphanumerics, hyphens, and
        // periods, dot-separated, with no leading or trailing period.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-."))
        #expect(AppLog.subsystem.unicodeScalars.allSatisfy(allowed.contains))
        #expect(!AppLog.subsystem.hasPrefix("."))
        #expect(!AppLog.subsystem.hasSuffix("."))
        #expect(AppLog.subsystem.split(separator: ".").count >= 2)
    }

    // MARK: - The reader itself

    /// The spellings `scripts/bundle-id.sh` accepts and a substring check would reject.
    @Test
    func `the reader accepts every spelling bundle-id sh accepts`() {
        let subsystem = AppLog.subsystem
        let read = Self.declaredBundleIdentifier(inManifest:)
        #expect(read("        PRODUCT_BUNDLE_IDENTIFIER: \(subsystem)\n") == subsystem)
        #expect(read("PRODUCT_BUNDLE_IDENTIFIER: \"\(subsystem)\"\n") == subsystem)
        #expect(read("PRODUCT_BUNDLE_IDENTIFIER: '\(subsystem)'\n") == subsystem)
        #expect(read("PRODUCT_BUNDLE_IDENTIFIER: \(subsystem) # the app target\n") == subsystem)
        #expect(read("PRODUCT_BUNDLE_IDENTIFIER:\t\(subsystem)\t# tab-separated\n") == subsystem)
        #expect(read("PRODUCT_BUNDLE_IDENTIFIER: \(subsystem)\r\n") == subsystem)
    }

    /// A substring check would pass on this: the value merely *starts with* the
    /// subsystem. Equality is what makes a helper or extension target fail the drift
    /// test instead of standing in for the app.
    @Test
    func `an identifier that only starts with the subsystem is not a match`() {
        let manifest = "        PRODUCT_BUNDLE_IDENTIFIER: \(AppLog.subsystem).Helper\n"
        #expect(Self.declaredBundleIdentifier(inManifest: manifest) == "\(AppLog.subsystem).Helper")
        #expect(Self.declaredBundleIdentifier(inManifest: manifest) != AppLog.subsystem)
    }

    /// Only the first declaration counts, exactly as `scripts/bundle-id.sh`'s
    /// `head -n 1` does: a target added below the app target never shadows it.
    @Test
    func `only the first declaration counts`() {
        let manifest = """
        PRODUCT_BUNDLE_IDENTIFIER: \(AppLog.subsystem)
        PRODUCT_BUNDLE_IDENTIFIER: \(AppLog.subsystem).LaunchUITests
        """
        #expect(Self.declaredBundleIdentifier(inManifest: manifest) == AppLog.subsystem)
    }

    @Test
    func `a manifest that declares no identifier has no answer`() {
        #expect(Self.declaredBundleIdentifier(inManifest: "name: MyApp\n") == nil)
        #expect(Self.declaredBundleIdentifier(inManifest: "PRODUCT_BUNDLE_IDENTIFIER:\n") == nil)
        #expect(Self
            .declaredBundleIdentifier(inManifest: "PRODUCT_BUNDLE_IDENTIFIER: #TBD\n") == nil)
    }
}
