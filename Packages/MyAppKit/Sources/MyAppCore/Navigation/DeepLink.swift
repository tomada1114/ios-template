import Foundation

/// The app's custom URL scheme: which links open which ``AppRoute``, and the inverse.
///
/// Parsing lives in Core, not in the view that receives the URL, so every accepted and
/// rejected shape is a unit test. The one shape accepted is `my-app://todo/<uuid>`.
public enum DeepLink {
    /// The URL scheme the app registers and parses.
    ///
    /// Contract once an app ships: links to it live in messages, notes, and other apps,
    /// and a renamed scheme breaks every one of them. `project.yml` registers the same
    /// string (`CFBundleURLTypes`), and `DeepLinkTests` fails when the two differ.
    /// `scripts/bootstrap.sh` rewrites this placeholder and that registration together,
    /// so keep it one unsplit literal.
    public static let scheme = "my-app"

    /// The host of a link to one to-do item.
    private static let todoHost = "todo"

    /// The route `url` names, or `nil` when it is not exactly `my-app://todo/<uuid>`.
    ///
    /// The scheme compares without regard to case, as URL schemes do; the host must be
    /// `todo` exactly, followed by one path component that parses as a `UUID`. A query, a
    /// fragment, a user, a port, or any further path component rejects the link rather
    /// than being ignored, so a link that says more than this version understands opens
    /// nothing instead of opening something else.
    public static func route(for url: URL) -> AppRoute? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == scheme,
              components.host == todoHost,
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.query == nil,
              components.fragment == nil
        else {
            return nil
        }
        // The encoded path, so a percent-escaped character is not decoded into a match.
        // Everything after the leading slash must be one UUID: a further component or a
        // trailing slash is not one.
        let path = components.percentEncodedPath
        guard path.hasPrefix("/"), let id = UUID(uuidString: String(path.dropFirst())) else {
            return nil
        }
        return .todoDetail(id)
    }

    /// The link that opens `route` — what ``route(for:)`` parses back to the same route.
    public static func url(for route: AppRoute) -> URL {
        switch route {
        case let .todoDetail(id):
            var components = URLComponents()
            components.scheme = scheme
            components.host = todoHost
            components.path = "/\(id.uuidString)"
            guard let url = components.url else {
                // Unreachable: the scheme, the host, and a UUID's characters are all
                // valid unescaped in a URL, so the components always form one.
                preconditionFailure("DeepLink could not form a URL for \(route)")
            }
            return url
        }
    }
}
