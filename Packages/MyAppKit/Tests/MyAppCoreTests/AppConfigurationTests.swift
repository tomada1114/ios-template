import Foundation
import MyAppCore
import Testing

/// ``AppConfiguration``: the per-build values the app's `Info.plist` carries, parsed once.
///
/// The URLs below are literals worked out by hand, an oracle independent of the parser.
/// The last section reads the real `project.yml` and the two committed xcconfigs, as
/// `DeepLinkTests` does for the URL scheme, so Core's key and the build's cannot drift.
@Suite("AppConfiguration")
struct AppConfigurationTests {
    /// The build setting `project.yml`'s `info.properties` expands under Core's key.
    static let buildSetting = "API_BASE_URL"

    /// The committed xcconfigs, named one by one: `Config/Local.xcconfig` is a person's
    /// signing identity and is never read, so the directory is never listed.
    static let xcconfigs = ["Config/Debug.xcconfig", "Config/Release.xcconfig"]

    // MARK: - Helpers

    /// The value a `project.yml` gives `key`: the rest of the first line that starts with
    /// `key:` once trimmed, unquoted, or `nil` when no line does.
    static func value(of key: String, inManifest manifest: String) -> String? {
        let prefix = "\(key):"
        return manifest.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix(prefix) }
            .map { line in
                AppLogTests
                    .unquoted(line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces))
            }
    }

    /// The value an xcconfig assigns `setting`, as the build reads it: everything from a
    /// `//` on is a comment, and an empty `$()` expands to nothing — the escape that lets
    /// a URL keep its `//`. `nil` when the file assigns no value.
    static func value(of setting: String, inXcconfig xcconfig: String) -> String? {
        xcconfig.components(separatedBy: .newlines)
            .map { line -> String in
                let code = line.range(of: "//").map { String(line[..<$0.lowerBound]) } ?? line
                return code.trimmingCharacters(in: .whitespaces)
            }
            .compactMap { line -> String? in
                let parts = line.split(separator: "=", maxSplits: 1)
                guard parts.count == 2,
                      parts[0].trimmingCharacters(in: .whitespaces) == setting
                else {
                    return nil
                }
                return parts[1].trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "$()", with: "")
            }
            .last
    }

    // MARK: - Parsing

    @Test(arguments: [
        "https://api.staging.invalid/v1",
        "https://api.invalid",
        "http://localhost:8080/api",
        "HTTPS://api.invalid/v1",
    ])
    func `a well formed base URL is the API base URL`(text: String) throws {
        let configuration = try AppConfiguration(
            infoDictionary: [AppConfiguration.apiBaseURLKey: text, "CFBundleName": "App"],
        )
        #expect(configuration.apiBaseURL.absoluteString == text)
    }

    @Test
    func `a dictionary without the key reports it missing`() {
        #expect(throws: AppConfigurationError.missing(key: "APIBaseURL")) {
            try AppConfiguration(infoDictionary: ["CFBundleName": "App"])
        }
    }

    /// What an unset `$(API_BASE_URL)` leaves in the built `Info.plist`: the key, with an
    /// empty value — a build configuration that never set it, not a typo in one.
    @Test(arguments: ["", "   "])
    func `an empty value reports the key missing`(text: String) {
        #expect(throws: AppConfigurationError.missing(key: "APIBaseURL")) {
            try AppConfiguration(infoDictionary: [AppConfiguration.apiBaseURLKey: text])
        }
    }

    /// Every value that is there but is not an absolute web URL with a host, each with
    /// its own reason.
    @Test(arguments: [
        ("the `//` comment trap", "https:"),
        ("no host", "https:///v1"),
        ("no scheme", "api.invalid/v1"),
        ("a relative path", "/v1"),
        ("another scheme", "ftp://api.invalid"),
        ("an unexpanded build setting", "$(API_BASE_URL)"),
        ("not a URL at all", "https://api invalid"),
    ])
    func `a malformed value reports the key malformed`(reason: String, text: String) {
        #expect(throws: AppConfigurationError.malformed(key: "APIBaseURL"), "\(reason): \(text)") {
            try AppConfiguration(infoDictionary: [AppConfiguration.apiBaseURLKey: text])
        }
    }

    @Test
    func `a value that is not a string reports the key malformed`() {
        #expect(throws: AppConfigurationError.malformed(key: "APIBaseURL")) {
            try AppConfiguration(infoDictionary: [AppConfiguration.apiBaseURLKey: 42])
        }
    }

    // MARK: - The build that supplies it

    @Test
    func `the key Core reads is the one project yml expands the build setting under`() throws {
        let manifest = AppLogTests.repositoryRoot.appendingPathComponent("project.yml")
        let value = try Self.value(
            of: AppConfiguration.apiBaseURLKey,
            inManifest: String(contentsOf: manifest, encoding: .utf8),
        )
        #expect(
            value == "$(\(Self.buildSetting))",
            """
            \(manifest.path) sets \(AppConfiguration.apiBaseURLKey) to \(value ?? "nothing").
            project.yml's info.properties must expand $(\(Self.buildSetting)) under
            AppConfiguration.apiBaseURLKey, or the app launches without a base URL.
            """,
        )
    }

    @Test(arguments: xcconfigs)
    func `each configuration sets a base URL the parser accepts`(path: String) throws {
        let file = AppLogTests.repositoryRoot.appendingPathComponent(path)
        let xcconfig = try String(contentsOf: file, encoding: .utf8)
        let value = try #require(
            Self.value(of: Self.buildSetting, inXcconfig: xcconfig),
            "\(path) must set \(Self.buildSetting)",
        )
        let configuration = try AppConfiguration(
            infoDictionary: [AppConfiguration.apiBaseURLKey: value],
        )
        // A template placeholder never names a host that resolves (RFC 6761).
        #expect(configuration.apiBaseURL.host()?.hasSuffix(".invalid") == true, "\(path): \(value)")
    }

    @Test
    func `the xcconfig reader applies the comment rule and the escape`() {
        let read = { Self.value(of: "API_BASE_URL", inXcconfig: $0) }
        #expect(read("API_BASE_URL = https:/$()/api.invalid/v1\n") == "https://api.invalid/v1")
        #expect(read("API_BASE_URL = https://api.invalid/v1\n") == "https:")
        #expect(read("// API_BASE_URL = https:/$()/a.invalid\nAPI_BASE_URL=x\n") == "x")
        #expect(read("API_BASE_URL_V2 = x\n") == nil)
        #expect(read("#include? \"Local.xcconfig\"\n") == nil)
    }

    @Test
    func `the manifest reader reads the first line that sets the key`() {
        let read = { Self.value(of: "APIBaseURL", inManifest: $0) }
        #expect(read("        APIBaseURL: $(API_BASE_URL)\n") == "$(API_BASE_URL)")
        #expect(read("APIBaseURL: \"$(API_BASE_URL)\"\n") == "$(API_BASE_URL)")
        #expect(read("APIBaseURLV2: x\n") == nil)
        #expect(read("name: MyApp\n") == nil)
    }
}
