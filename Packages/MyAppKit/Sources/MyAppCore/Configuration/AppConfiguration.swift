import Foundation

/// The values that differ between builds — staging in Debug, production in Release —
/// parsed once from the app's `Info.plist`.
///
/// Each value starts as a build setting in `Config/Debug.xcconfig` and
/// `Config/Release.xcconfig`, which `project.yml`'s `info.properties` expands into the
/// built `Info.plist` under one key; `App/` hands this initializer
/// `Bundle.main.infoDictionary` at launch. Parsing here rather than in `App/` puts every
/// accepted and rejected value under a unit test, and keeps Core free of `Bundle.main`.
///
/// Never a secret: an xcconfig is committed and an `Info.plist` ships readable inside
/// every copy of the app. A secret goes through the ``SecureStoring`` port.
public struct AppConfiguration: Equatable, Sendable {
    /// The `Info.plist` key the API base URL arrives under. `project.yml` expands
    /// `$(API_BASE_URL)` under the same key, and `AppConfigurationTests` fails when the
    /// two differ.
    public static let apiBaseURLKey = "APIBaseURL"

    /// The one scheme a base URL may use: App Transport Security refuses plain `http`
    /// on a device, so an `http` value would only fail later, at the first request.
    private static let scheme = "https"

    /// The URL every ``Endpoint`` is resolved below (``APIClient``).
    public let apiBaseURL: URL

    /// Parses the configuration out of an `Info.plist` dictionary.
    ///
    /// Surrounding whitespace and newlines are ignored. Throws
    /// ``AppConfigurationError/missing(key:)`` when the key is absent or blank — an empty
    /// value is what an xcconfig that never sets the build setting leaves — and
    /// ``AppConfigurationError/malformed(key:)`` when the value is not an absolute
    /// `https` URL with a host and nothing else: no user or password, which would ship
    /// a credential in `Info.plist`, and no query or fragment, which every request's
    /// path would be resolved after. That includes `https:`, which is what an xcconfig
    /// leaves of `https://…` when the `//` is not escaped as `/$()/`.
    public init(infoDictionary: [String: Any]) throws(AppConfigurationError) {
        apiBaseURL = try Self.webURL(infoDictionary, key: Self.apiBaseURLKey)
    }

    private static func webURL(
        _ info: [String: Any],
        key: String,
    ) throws(AppConfigurationError) -> URL {
        guard let raw = info[key] else {
            throw .missing(key: key)
        }
        guard let text = raw as? String else {
            throw .malformed(key: key)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw .missing(key: key)
        }
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == scheme,
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              let url = components.url
        else {
            throw .malformed(key: key)
        }
        return url
    }
}
