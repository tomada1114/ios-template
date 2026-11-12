/// Why an `Info.plist` value could not become an ``AppConfiguration``.
///
/// Either case is a build misconfiguration, never something a user can cause, so the
/// app fails its launch on it rather than running against no server. The payload is the
/// key only: the value is left out, as every error here leaves out what it was handed.
public enum AppConfigurationError: Error, Equatable, Sendable {
    /// The key holds something other than an absolute web URL with a host.
    case malformed(key: String)

    /// The key is absent, or its value is empty: the build configuration never set it.
    case missing(key: String)
}
