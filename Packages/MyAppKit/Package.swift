// swift-tools-version: 6.4
import PackageDescription

/// Strictness from day one: Swift 6 language mode (data-race safety as errors)
/// and every warning treated as an error. There is never a "legacy" codebase.
let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "MyAppKit",
    // The language the String Catalog is written in, and the one a reader falls back to
    // when the catalog lacks theirs. A second shipped language is an app's decision.
    defaultLocalization: "en",
    // iOS is the product. macOS is listed only so `swift test` can build and run the
    // package on the host Mac — seconds instead of a simulator boot, and the only way
    // scripts/coverage.sh can read coverage. Every target therefore has to compile for
    // both; an iOS-only API in MyAppUI or MyAppPlatform sits behind `#if os(iOS)`
    // (docs/architecture.md › Why the package also builds for macOS).
    platforms: [.iOS(.v27), .macOS(.v27)],
    products: [
        .library(name: "MyAppCore", targets: ["MyAppCore"]),
        .library(name: "MyAppUI", targets: ["MyAppUI"]),
        .library(name: "MyAppPlatform", targets: ["MyAppPlatform"]),
    ],
    targets: [
        // Core owns the user-facing wording (it returns `LocalizedStringResource`), so the
        // one String Catalog lives here. xcodebuild compiles it into Core's resource
        // bundle; `swift build` only copies it, so tests read English from `defaultValue`.
        .target(
            name: "MyAppCore",
            resources: [.process("Resources/Localizable.xcstrings")],
            swiftSettings: strictSettings,
        ),
        .target(name: "MyAppUI", dependencies: ["MyAppCore"], swiftSettings: strictSettings),
        // Adapters behind Core-declared ports: persistence (SwiftData) and OS services.
        // Depends on MyAppCore only: it must not see MyAppUI, and MyAppUI must not see it
        // (enforced by ArchitectureBoundaryTests, since SwiftPM cannot stop a system
        // framework import and this graph alone would not stop a later dependency edit).
        .target(name: "MyAppPlatform", dependencies: ["MyAppCore"], swiftSettings: strictSettings),
        // Test code both test targets share: the fake of each Core port and the contract
        // function every implementation of that port must pass. It is a library target
        // only because a test target cannot be depended on, and it is test code all the
        // same: no product exports it, so `App/` cannot link it, ArchitectureBoundaryTests
        // fails if a shipped module imports it, and its sources sit under Tests/ — outside
        // scripts/coverage.sh's Sources/MyAppCore filter, so it is never counted as Core.
        .target(
            name: "MyAppTestSupport",
            dependencies: ["MyAppCore"],
            path: "Tests/MyAppTestSupport",
            swiftSettings: strictSettings,
        ),
        .testTarget(
            name: "MyAppCoreTests",
            dependencies: ["MyAppCore", "MyAppTestSupport"],
            swiftSettings: strictSettings,
        ),
        // The adapters against the real frameworks they wrap. SwiftData runs on the host
        // with an in-memory store, so unlike an adapter that needs a device or a
        // permission grant, these run under plain `swift test` and in CI. Linking
        // MyAppPlatform does not put it inside the coverage floor: scripts/coverage.sh
        // measures Sources/MyAppCore and nothing else.
        .testTarget(
            name: "MyAppPlatformTests",
            dependencies: ["MyAppPlatform", "MyAppCore", "MyAppTestSupport"],
            swiftSettings: strictSettings,
        ),
    ],
)
