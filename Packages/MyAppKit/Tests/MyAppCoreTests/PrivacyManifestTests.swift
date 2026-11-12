import Foundation
import Testing

/// `App/PrivacyInfo.xcprivacy` has to declare every required-reason API the shipped code
/// calls, or App Store Connect rejects the upload — and nothing in a Debug build, a
/// simulator run, or `just check` notices a missing entry. `UserDefaultsPreferences`
/// reads and writes the app's own defaults, so the manifest declares the `UserDefaults`
/// category with reason `CA92.1`; this suite makes deleting that entry a failing test
/// instead of a rejected upload.
@Suite("PrivacyManifest")
struct PrivacyManifestTests {
    /// Why data is not a manifest: it parses, but its root is not a dictionary.
    struct NotADictionary: Error, Equatable {}

    /// The manifest's path from the checkout root.
    static let manifestPath = "App/PrivacyInfo.xcprivacy"

    static let userDefaultsCategory = "NSPrivacyAccessedAPICategoryUserDefaults"

    /// Apple's reason for reading and writing defaults only the app itself can access.
    static let appOnlyDefaultsReason = "CA92.1"

    // MARK: - Helpers

    /// The manifest's top-level dictionary. Throws the parser's error when the data is
    /// not a property list, and ``NotADictionary`` when its root is something else.
    static func manifest(from data: Data) throws -> [String: Any] {
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let root = plist as? [String: Any] else {
            throw NotADictionary()
        }
        return root
    }

    /// The reasons the manifest declares for `category`: empty when no
    /// `NSPrivacyAccessedAPITypes` entry names it, or the entry lists none — either way
    /// App Store Connect sees no declared reason.
    static func declaredReasons(for category: String, in manifest: [String: Any]) -> [String] {
        let entries = manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? []
        let entry = entries.first { $0["NSPrivacyAccessedAPIType"] as? String == category }
        return entry?["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? []
    }

    static func shippedManifest() throws -> [String: Any] {
        let url = AppLogTests.repositoryRoot.appendingPathComponent(manifestPath)
        return try manifest(from: Data(contentsOf: url))
    }

    /// A minimal manifest whose accessed-API array holds `entries`, for the reader's tests.
    static func manifest(declaring entries: String) throws -> [String: Any] {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>NSPrivacyAccessedAPITypes</key><array>\(entries)</array>
        </dict></plist>
        """
        return try manifest(from: Data(xml.utf8))
    }

    // MARK: - The shipped manifest

    @Test
    func `the manifest declares the UserDefaults category with the app-only reason`() throws {
        let reasons = try Self.declaredReasons(
            for: Self.userDefaultsCategory,
            in: Self.shippedManifest(),
        )
        #expect(
            reasons == [Self.appOnlyDefaultsReason],
            """
            \(Self.manifestPath) declares reasons \(reasons) for \
            \(Self.userDefaultsCategory). UserDefaultsPreferences reads and writes the \
            app's own defaults, so App Store Connect needs exactly CA92.1 declared.
            """,
        )
    }

    @Test
    func `the manifest declares no tracking and no collected data`() throws {
        let manifest = try Self.shippedManifest()
        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect((manifest["NSPrivacyTrackingDomains"] as? [Any])?.isEmpty == true)
        #expect((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)
    }

    // MARK: - The reader itself

    @Test
    func `a manifest without the category has no reasons for it`() throws {
        let manifest = try Self.manifest(declaring: """
        <dict><key>NSPrivacyAccessedAPIType</key>\
        <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>\
        <key>NSPrivacyAccessedAPITypeReasons</key><array><string>C617.1</string></array></dict>
        """)
        #expect(Self.declaredReasons(for: Self.userDefaultsCategory, in: manifest).isEmpty)
        #expect(Self.declaredReasons(for: Self.userDefaultsCategory, in: [:]).isEmpty)
    }

    @Test
    func `an entry without reasons declares none`() throws {
        let manifest = try Self.manifest(declaring: """
        <dict><key>NSPrivacyAccessedAPIType</key>\
        <string>NSPrivacyAccessedAPICategoryUserDefaults</string></dict>
        """)
        #expect(Self.declaredReasons(for: Self.userDefaultsCategory, in: manifest).isEmpty)
    }

    @Test
    func `data that is not a property list is no manifest`() {
        #expect(throws: (any Error).self) {
            try Self.manifest(from: Data("not a plist".utf8))
        }
    }

    @Test
    func `a property list whose root is not a dictionary is no manifest`() {
        #expect(throws: NotADictionary()) {
            try Self.manifest(from: Data("<plist version=\"1.0\"><array/></plist>".utf8))
        }
    }
}
