import Foundation

/// The checkout root, for the Core suites that hold Core to a file outside the package:
/// `project.yml` (`AppLogTests`, `DeepLinkTests`, `AppConfigurationTests`) and
/// `App/PrivacyInfo.xcprivacy` (`PrivacyManifestTests`). One definition, so moving this
/// directory breaks one place rather than each suite's own path arithmetic.
enum RepositoryRoot {
    /// Resolved from this file's path:
    /// `Packages/MyAppKit/Tests/MyAppCoreTests/<this file>`, five levels up.
    static let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// The file at `path`, relative to the checkout root.
    static func file(_ path: String) -> URL {
        url.appendingPathComponent(path)
    }
}
