import Foundation

/// A screen the navigation stack can push, named by the value it shows.
///
/// A route carries an identifier, never the item itself: the destination looks the item
/// up in its view model when it renders, so a pushed screen shows the current state
/// rather than a copy taken when the link was tapped, and a route parsed from a deep link
/// (``DeepLink``) is the same value as one a row pushed. A new screen adds a case here,
/// its branch in `RootView`'s `navigationDestination(for:)` switch, its stored name
/// (below), and — when the screen needs a view model of its own — an ``AppModel``
/// factory that builds it.
///
/// `Codable` so a scene's path outlives its process (``NavigationModel/encodedPath``).
/// The coding is written by hand, never synthesized: a route is stored as
/// `{"id":"<uuid>","screen":"todoDetail"}`, and those strings are contract once a build
/// has left your machine — the next build reads what this one stored. Synthesized coding
/// would take them from the Swift case and label names, so a rename here would silently
/// stop every stored path from restoring. A case's Swift name is free to change; its
/// stored name is not. Nothing but review holds the next rule, so follow it: a case that
/// gains a value reads it with `decodeIfPresent` and a default, so the form stored
/// without it still decodes, and the literal test of the old form stays beside the new
/// one (`NavigationModelRestorationTests`).
public enum AppRoute: Hashable, Sendable {
    /// The detail screen of one to-do item.
    case todoDetail(TodoItem.ID)
}

extension AppRoute: Codable {
    private enum CodingKeys: String, CodingKey {
        case screen
        case id
    }

    /// The stored name of each case, under the `screen` key.
    private enum Screen {
        static let todoDetail = "todoDetail"
    }

    /// Reads a route from its stored form, throwing a `DecodingError` for a screen name
    /// this build does not know or an identifier that is not a `UUID`: the caller decides
    /// what an unreadable route means (``NavigationModel/restore(from:)`` ends the path there).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let screen = try container.decode(String.self, forKey: .screen)
        switch screen {
        case Screen.todoDetail:
            let text = try container.decode(String.self, forKey: .id)
            guard let id = UUID(uuidString: text) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .id,
                    in: container,
                    debugDescription: "The identifier is not a UUID.",
                )
            }
            self = .todoDetail(id)

        default:
            throw DecodingError.dataCorruptedError(
                forKey: .screen,
                in: container,
                debugDescription: "This build has no screen with that stored name.",
            )
        }
    }

    /// Writes the route in its stored form: the case's stored name under `screen`, and
    /// the identifier as its `uuidString` rather than through `UUID`'s own coding, so the
    /// bytes are this file's decision and no one else's.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .todoDetail(id):
            try container.encode(Screen.todoDetail, forKey: .screen)
            try container.encode(id.uuidString, forKey: .id)
        }
    }
}
