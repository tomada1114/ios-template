import Foundation

/// The form a navigation path takes outside the process, for ``NavigationModel``:
/// `{"routes":[<route>,…],"version":1}`, as UTF-8 JSON with sorted keys.
///
/// Contract once a build has left your machine, like a `UserDefaults` key: the system
/// keeps a scene's stored path across launches, so the build that reads one is often not
/// the build that wrote it. `NavigationModelRestorationTests` pins the bytes. A change
/// that keeps old payloads readable — a new ``AppRoute`` case, a new optional field —
/// stays version 1. A change that does not takes a new version number, written from then
/// on, and ``routes(from:)`` keeps reading every earlier version.
enum StoredNavigationPath {
    private struct Payload: Encodable {
        let routes: [AppRoute]
        let version: Int
    }

    /// The envelope alone, read before the routes: a later version may store routes in a
    /// shape this build would misread, so nothing past the number is looked at until the
    /// number is one this build knows.
    private struct Header: Decodable {
        let version: Int
    }

    private struct Routes: Decodable {
        let routes: [ReadableRoute]
    }

    /// One element of `routes` that never fails to decode, so an element this build
    /// cannot read — a screen a later build added, a damaged identifier — costs that
    /// route and not the whole path.
    private struct ReadableRoute: Decodable {
        let route: AppRoute?

        init(from decoder: any Decoder) {
            route = try? AppRoute(from: decoder)
        }
    }

    /// Data that is a stored path of a version this build does not read.
    private struct UnknownVersion: Error {}

    /// The version this build writes, and the only one it reads.
    static let version = 1

    /// `routes` in the stored form. Sorted keys make the same path the same bytes, so
    /// observing the result sees a change only when the path changed.
    static func data(for routes: [AppRoute]) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        do {
            return try encoder.encode(Payload(routes: routes, version: version))
        } catch {
            // Unreachable: a route encodes two strings, which JSON always holds. Empty
            // data restores to the root, so even this is not a crash.
            AppLog.navigation.fault("encodedPath: the path did not encode")
            return Data()
        }
    }

    /// The routes `data` stores, root first, without the ones this build cannot read.
    /// Throws when `data` is not a stored path of a version this build knows.
    static func routes(from data: Data) throws -> [AppRoute] {
        let decoder = JSONDecoder()
        guard try decoder.decode(Header.self, from: data).version == version else {
            throw UnknownVersion()
        }
        return try decoder.decode(Routes.self, from: data).routes.compactMap(\.route)
    }
}
