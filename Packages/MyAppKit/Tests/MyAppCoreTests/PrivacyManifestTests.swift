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
    /// Why data cannot be read as a privacy manifest.
    enum ManifestError: Error, Equatable {
        /// The data does not parse as a property list.
        case notAPropertyList
        /// It parses, but its root is not a dictionary.
        case rootNotADictionary
        /// `NSPrivacyAccessedAPITypes` is not an array of dictionaries.
        case malformedAccessedAPITypes
        /// An entry's `NSPrivacyAccessedAPITypeReasons` is not an array of strings.
        case malformedReasons(category: String)
        /// More than one entry names the same category, so which reasons count is
        /// ambiguous.
        case duplicateEntry(category: String)
    }

    /// The manifest's path from the checkout root.
    static let manifestPath = "App/PrivacyInfo.xcprivacy"

    static let userDefaultsCategory = "NSPrivacyAccessedAPICategoryUserDefaults"

    /// Apple's reason for reading and writing defaults only the app itself can access.
    static let appOnlyDefaultsReason = "CA92.1"

    // MARK: - Helpers

    /// The manifest's top-level dictionary.
    static func manifest(from data: Data) throws(ManifestError) -> [String: Any] {
        let plist: Any
        do {
            plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        } catch {
            throw .notAPropertyList
        }
        guard let root = plist as? [String: Any] else {
            throw .rootNotADictionary
        }
        return root
    }

    /// The reasons the manifest declares for `category`: empty when no
    /// `NSPrivacyAccessedAPITypes` entry names it, or the entry lists none — either way
    /// App Store Connect sees no declared reason. A malformed array or a second entry for
    /// the same category throws instead of reading as a missing declaration.
    static func declaredReasons(
        for category: String,
        in manifest: [String: Any],
    ) throws(ManifestError) -> [String] {
        guard let value = manifest["NSPrivacyAccessedAPITypes"] else {
            return []
        }
        guard let entries = value as? [Any] else {
            throw .malformedAccessedAPITypes
        }
        let dictionaries = entries.compactMap { $0 as? [String: Any] }
        guard dictionaries.count == entries.count else {
            throw .malformedAccessedAPITypes
        }
        let matching = dictionaries.filter { entry in
            entry["NSPrivacyAccessedAPIType"] as? String == category
        }
        guard matching.count <= 1 else {
            throw .duplicateEntry(category: category)
        }
        guard let reasons = matching.first?["NSPrivacyAccessedAPITypeReasons"] else {
            return []
        }
        guard let strings = reasons as? [String] else {
            throw .malformedReasons(category: category)
        }
        return strings
    }

    static func shippedManifest() throws -> [String: Any] {
        try manifest(from: Data(contentsOf: RepositoryRoot.file(manifestPath)))
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

    /// One accessed-API entry for `category` with `reasons`, as manifest XML.
    static func entry(_ category: String, reasons: [String]) -> String {
        let strings = reasons.map { "<string>\($0)</string>" }.joined()
        return """
        <dict><key>NSPrivacyAccessedAPIType</key><string>\(category)</string>\
        <key>NSPrivacyAccessedAPITypeReasons</key><array>\(strings)</array></dict>
        """
    }

    // MARK: - The shipped manifest

    @Test
    func `the manifest declares the UserDefaults category with the app-only reason`() throws {
        let reasons = try Self.declaredReasons(
            for: Self.userDefaultsCategory,
            in: Self.shippedManifest(),
        )
        #expect(
            reasons.contains(Self.appOnlyDefaultsReason),
            """
            \(Self.manifestPath) declares reasons \(reasons) for \
            \(Self.userDefaultsCategory). UserDefaultsPreferences reads and writes the \
            app's own defaults, so App Store Connect needs CA92.1 among them.
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
    func `a second reason beside the app-only one still counts`() throws {
        let manifest = try Self.manifest(declaring: Self.entry(
            Self.userDefaultsCategory,
            reasons: ["CA92.1", "1C8F.1"],
        ))
        #expect(try Self.declaredReasons(for: Self.userDefaultsCategory, in: manifest)
            == ["CA92.1", "1C8F.1"])
    }

    @Test
    func `a manifest without the category has no reasons for it`() throws {
        let manifest = try Self.manifest(declaring: Self.entry(
            "NSPrivacyAccessedAPICategoryFileTimestamp",
            reasons: ["C617.1"],
        ))
        #expect(try Self.declaredReasons(for: Self.userDefaultsCategory, in: manifest).isEmpty)
        #expect(try Self.declaredReasons(for: Self.userDefaultsCategory, in: [:]).isEmpty)
    }

    @Test
    func `an entry without reasons declares none`() throws {
        let manifest = try Self.manifest(declaring: """
        <dict><key>NSPrivacyAccessedAPIType</key>\
        <string>NSPrivacyAccessedAPICategoryUserDefaults</string></dict>
        """)
        #expect(try Self.declaredReasons(for: Self.userDefaultsCategory, in: manifest).isEmpty)
    }

    @Test
    func `an accessed-API array holding a non-dictionary is malformed`() throws {
        let manifest = try Self.manifest(declaring: """
        \(Self.entry(Self.userDefaultsCategory, reasons: ["CA92.1"]))\
        <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
        """)
        #expect(throws: ManifestError.malformedAccessedAPITypes) {
            try Self.declaredReasons(for: Self.userDefaultsCategory, in: manifest)
        }
    }

    @Test
    func `an accessed-API value that is not an array is malformed`() {
        let manifest: [String: Any] = ["NSPrivacyAccessedAPITypes": "CA92.1"]
        #expect(throws: ManifestError.malformedAccessedAPITypes) {
            try Self.declaredReasons(for: Self.userDefaultsCategory, in: manifest)
        }
    }

    @Test
    func `reasons that are not an array of strings are malformed`() throws {
        let manifest = try Self.manifest(declaring: """
        <dict><key>NSPrivacyAccessedAPIType</key>\
        <string>NSPrivacyAccessedAPICategoryUserDefaults</string>\
        <key>NSPrivacyAccessedAPITypeReasons</key><string>CA92.1</string></dict>
        """)
        #expect(throws: ManifestError.malformedReasons(category: Self.userDefaultsCategory)) {
            try Self.declaredReasons(for: Self.userDefaultsCategory, in: manifest)
        }
    }

    @Test
    func `two entries for the same category are a duplicate`() throws {
        let manifest = try Self.manifest(declaring: """
        \(Self.entry(Self.userDefaultsCategory, reasons: ["CA92.1"]))\
        \(Self.entry(Self.userDefaultsCategory, reasons: []))
        """)
        #expect(throws: ManifestError.duplicateEntry(category: Self.userDefaultsCategory)) {
            try Self.declaredReasons(for: Self.userDefaultsCategory, in: manifest)
        }
    }

    @Test
    func `data that is not a property list is no manifest`() {
        #expect(throws: ManifestError.notAPropertyList) {
            try Self.manifest(from: Data("not a plist".utf8))
        }
    }

    @Test
    func `a property list whose root is not a dictionary is no manifest`() {
        #expect(throws: ManifestError.rootNotADictionary) {
            try Self.manifest(from: Data("<plist version=\"1.0\"><array/></plist>".utf8))
        }
    }
}
