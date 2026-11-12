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
    /// cannot read — a screen a later build added, a damaged identifier — ends the path
    /// there instead of failing all of it.
    private struct ReadableRoute: Decodable {
        let route: AppRoute?

        init(from decoder: any Decoder) {
            route = try? AppRoute(from: decoder)
        }
    }

    /// Why data did not yield a path.
    enum ReadFailure: Error, Equatable {
        /// The data is not a stored path at all: damaged, or something else's bytes.
        case notAStoredPath
        /// A stored path of a version this build does not read — what a build finds after
        /// a newer one stored its path, so expected after a downgrade.
        case unknownVersion(Int)
    }

    /// The version this build writes, and the only one it reads.
    static let version = 1

    /// `routes` in the stored form. Sorted keys make the same path the same bytes.
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

    /// The routes `data` stores, root first, up to the first one this build cannot read:
    /// the screens above an unreadable one were pushed from it, so restoring them
    /// without it would build a stack the person never saw.
    static func routes(from data: Data) throws(ReadFailure) -> [AppRoute] {
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: data) else {
            throw .notAStoredPath
        }
        guard header.version == version else {
            throw .unknownVersion(header.version)
        }
        guard let stored = try? decoder.decode(Routes.self, from: data) else {
            throw .notAStoredPath
        }
        var routes: [AppRoute] = []
        for element in stored.routes {
            guard let route = element.route else {
                break
            }
            routes.append(route)
        }
        return routes
    }
}
