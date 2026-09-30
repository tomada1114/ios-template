import Foundation
import MyAppCore
import Testing

/// ``DeepLink``: the one URL shape the app opens, and the scheme it is registered under.
///
/// The URLs below spell the scheme as a literal on purpose — an oracle independent of
/// ``DeepLink/scheme``. `scripts/bootstrap.sh` rewrites that literal here, in
/// `DeepLink.swift`, and in `project.yml` together; only the upper-cased spelling is
/// derived, because the rename does not rewrite an upper-cased placeholder.
@Suite("DeepLink")
struct DeepLinkTests {
    static let id = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301") ?? UUID()

    /// The key in `project.yml`'s `info:` block that lists the URL schemes the app claims.
    static let schemesKey = "CFBundleURLSchemes:"

    // MARK: - Helpers

    /// The URL schemes a `project.yml` registers: the value after ``schemesKey``, as a
    /// flow list on the same line (`[a, b]`) or, when that line holds nothing more, as
    /// the block list (`- a`) on the lines after it. Each element is compared whole, so
    /// `my-app-dev` does not count as `my-app`.
    static func registeredSchemes(inManifest manifest: String) -> [String] {
        let lines = manifest.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let keyLine = lines.firstIndex(where: { $0.hasPrefix(schemesKey) }) else {
            return []
        }
        let inline = lines[keyLine].dropFirst(schemesKey.count)
            .trimmingCharacters(in: .whitespaces)
        let elements: [String] = if inline.isEmpty {
            Array(lines[(keyLine + 1)...].prefix { $0.hasPrefix("- ") }.map { $0.dropFirst(2) })
                .map(String.init)
        } else {
            inline.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                .split(separator: ",")
                .map(String.init)
        }
        return elements
            .map { AppLogTests.unquoted($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Parsing

    @Test
    func `a to-do link opens that item's detail`() throws {
        let url = try #require(URL(string: "my-app://todo/\(Self.id.uuidString)"))
        #expect(DeepLink.route(for: url) == .todoDetail(Self.id))
    }

    @Test
    func `a lower-cased identifier parses to the same item`() throws {
        let url = try #require(URL(string: "my-app://todo/\(Self.id.uuidString.lowercased())"))
        #expect(DeepLink.route(for: url) == .todoDetail(Self.id))
    }

    @Test
    func `the scheme is compared without regard to case`() throws {
        let url = try #require(
            URL(string: "\(DeepLink.scheme.uppercased())://todo/\(Self.id.uuidString)"),
        )
        #expect(url.scheme != DeepLink.scheme, "the fixture must really be upper-cased")
        #expect(DeepLink.route(for: url) == .todoDetail(Self.id))
    }

    // MARK: - Rejecting

    /// Every shape other than exactly `my-app://todo/<uuid>`, each with its own reason.
    @Test(arguments: [
        ("another scheme", "https://todo/3F2504E0-4F89-11D3-9A0C-0305E82C3301"),
        ("another host", "my-app://item/3F2504E0-4F89-11D3-9A0C-0305E82C3301"),
        ("the host in another case", "my-app://TODO/3F2504E0-4F89-11D3-9A0C-0305E82C3301"),
        ("no host", "my-app:/todo/3F2504E0-4F89-11D3-9A0C-0305E82C3301"),
        ("no identifier", "my-app://todo"),
        ("an empty identifier", "my-app://todo/"),
        ("a malformed identifier", "my-app://todo/not-a-uuid"),
        ("a truncated identifier", "my-app://todo/3F2504E0-4F89-11D3-9A0C-0305E82C330"),
        ("a percent-encoded identifier", "my-app://todo/3F2504E0%2D4F89-11D3-9A0C-0305E82C3301"),
        ("an extra path component", "my-app://todo/3F2504E0-4F89-11D3-9A0C-0305E82C3301/edit"),
        ("a trailing slash", "my-app://todo/3F2504E0-4F89-11D3-9A0C-0305E82C3301/"),
        ("a query string", "my-app://todo/3F2504E0-4F89-11D3-9A0C-0305E82C3301?edit=1"),
        ("an empty query string", "my-app://todo/3F2504E0-4F89-11D3-9A0C-0305E82C3301?"),
        ("a fragment", "my-app://todo/3F2504E0-4F89-11D3-9A0C-0305E82C3301#title"),
        ("a user", "my-app://me@todo/3F2504E0-4F89-11D3-9A0C-0305E82C3301"),
        ("a port", "my-app://todo:80/3F2504E0-4F89-11D3-9A0C-0305E82C3301"),
    ])
    func `a link of any other shape opens nothing`(reason: String, link: String) throws {
        let url = try #require(URL(string: link), "\(reason): the fixture must be a URL")
        #expect(DeepLink.route(for: url) == nil, "\(reason): \(link)")
    }

    // MARK: - Building

    @Test
    func `a route's link is the documented shape`() {
        let url = DeepLink.url(for: .todoDetail(Self.id))
        #expect(url.absoluteString == "my-app://todo/\(Self.id.uuidString)")
    }

    @Test(arguments: [
        UUID(uuidString: "00000000-0000-0000-0000-000000000000") ?? UUID(),
        UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301") ?? UUID(),
        UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF") ?? UUID(),
    ])
    func `a route survives a round trip through its link`(id: UUID) {
        let route = AppRoute.todoDetail(id)
        #expect(DeepLink.route(for: DeepLink.url(for: route)) == route)
    }

    // MARK: - The registered scheme

    @Test
    func `the scheme Core parses is the one project yml registers`() throws {
        let manifest = AppLogTests.repositoryRoot.appendingPathComponent("project.yml")
        let schemes = try Self.registeredSchemes(
            inManifest: String(contentsOf: manifest, encoding: .utf8),
        )
        #expect(
            schemes.contains(DeepLink.scheme),
            """
            \(manifest.path) registers \(schemes) under \(Self.schemesKey).
            DeepLink.scheme and project.yml must name the same URL scheme, or the system
            never hands the app the links Core knows how to open.
            """,
        )
    }

    @Test
    func `the scheme reader reads a flow list and a block list`() {
        let read = Self.registeredSchemes(inManifest:)
        #expect(read("            CFBundleURLSchemes: [my-app]\n") == ["my-app"])
        #expect(read("CFBundleURLSchemes: [\"a\", 'b']\n") == ["a", "b"])
        #expect(read("CFBundleURLSchemes:\n  - a\n  - b\nnext: 1\n") == ["a", "b"])
        #expect(read("CFBundleURLSchemes: [my-app-dev]\n") != ["my-app"])
        #expect(read("name: MyApp\n").isEmpty)
    }
}
