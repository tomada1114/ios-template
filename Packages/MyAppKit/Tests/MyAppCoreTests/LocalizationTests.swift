import Foundation
import MyAppCore
import Testing

/// The subset of the String Catalog format these tests read: its source language and,
/// per key, each language's single string. A plural or device-varied entry has
/// `variations` instead of a `stringUnit`.
private struct StringCatalog: Decodable {
    let sourceLanguage: String
    let strings: [String: CatalogEntry]
}

/// One key's entry. An entry keyed by its own English text may carry no `localizations`
/// at all, which decodes as none rather than failing the whole catalog.
private struct CatalogEntry: Decodable {
    private enum CodingKeys: String, CodingKey {
        case localizations
    }

    let localizations: [String: CatalogLocalization]

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        localizations = try container.decodeIfPresent(
            [String: CatalogLocalization].self,
            forKey: .localizations,
        ) ?? [:]
    }
}

private struct CatalogLocalization: Decodable {
    struct StringUnit: Decodable {
        let value: String
    }

    let stringUnit: StringUnit?
}

/// The String Catalog plumbing (`Sources/MyAppCore/Resources/Localizable.xcstrings`).
///
/// `swift test` builds with SwiftPM's native build system, which copies the catalog into
/// Core's resource bundle uncompiled, so every English string here comes from a
/// resource's `defaultValue`; only `xcodebuild` compiles the catalog into the app. These
/// tests therefore read the sources and the catalog as text and hold them together:
/// every `LocalizedStringResource(…)` call in `Sources/MyAppCore` declares an explicit
/// key, a `defaultValue`, and `bundle: .module`; the keys those calls declare are exactly
/// the catalog's and exactly ``everyCase()``'s; and the catalog's English is what Core
/// renders. Without them, a key missing from the catalog still reads correctly in
/// English and simply never translates. A resource made from a bare string literal is
/// outside what the scan sees (``ResourceDeclarationScan``).
@MainActor
@Suite("Localization")
struct LocalizationTests {
    /// A resource Core returns, and the arguments its English format takes — a `String`
    /// for `%@`, an `Int` for `%lld`.
    struct Case {
        let resource: LocalizedStringResource
        let arguments: [any CVarArg]
    }

    /// `Sources/MyAppCore`, resolved from this file's path.
    static let coreSources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Sources/MyAppCore")

    /// Every resource Core returns, once per state that picks a different key, with the
    /// arguments its English takes. Adding a key to Core means adding it here: the
    /// source-scan tests fail until this list names every key Core's sources declare.
    static func everyCase() -> [Case] {
        let strings: [LocalizedStringResource] = [
            TodoListStrings.title, TodoListStrings.draftPlaceholder, TodoListStrings.add,
            TodoListStrings.emptyTitle, TodoListStrings.emptyDescription,
            TodoListStrings.failureTitle, TodoListStrings.dismiss, TodoListStrings.retry,
            TodoListStrings.markDone, TodoListStrings.markNotDone,
        ]
        let failures: [TodoListFailure] = [.deleteFailed, .loadFailed, .saveFailed]
        return strings.map { Case(resource: $0, arguments: []) }
            + failures.map { Case(resource: $0.message, arguments: []) }
    }

    /// `Sources/MyAppCore/Resources/Localizable.xcstrings`.
    private static func catalog() throws -> StringCatalog {
        let url = coreSources.appending(path: "Resources/Localizable.xcstrings")
        return try JSONDecoder().decode(StringCatalog.self, from: Data(contentsOf: url))
    }

    /// The keys the `LocalizedStringResource(…)` calls in Core's sources declare.
    static func declaredKeys() throws -> Set<String> {
        try Set(ResourceDeclarationScan.declarations(inSourcesAt: coreSources).compactMap(\.key))
    }

    @Test
    func `every resource is looked up in Core's resource bundle, not the main bundle`() {
        for testCase in Self.everyCase() {
            let resource = testCase.resource
            guard case let .atURL(url) = resource.bundle else {
                Issue.record("\(resource.key) is not looked up in Core's bundle")
                continue
            }
            #expect(url.pathExtension == "bundle", "\(resource.key)")
            #expect(url != Bundle.main.bundleURL, "\(resource.key)")
        }
    }

    @Test
    func `every resource Core's sources declare has a key, a defaultValue, and bundle module`(
    ) throws {
        let declarations = try ResourceDeclarationScan.declarations(inSourcesAt: Self.coreSources)
        #expect(!declarations.isEmpty, "the scan found no LocalizedStringResource call")
        for declaration in declarations {
            #expect(
                declaration.followsTheConvention,
                "\(declaration.file): LocalizedStringResource(\(declaration.arguments.prefix(60))…)",
            )
        }
    }

    @Test
    func `the catalog holds exactly the keys Core's sources declare`() throws {
        let declared = try Self.declaredKeys()
        let catalogued = try Set(Self.catalog().strings.keys)
        #expect(declared.subtracting(catalogued).isEmpty, "missing from Localizable.xcstrings")
        #expect(
            catalogued.subtracting(declared).isEmpty,
            "in Localizable.xcstrings but declared nowhere",
        )
    }

    @Test
    func `every key Core's sources declare has a case here`() throws {
        let declared = try Self.declaredKeys()
        let covered = Set(Self.everyCase().map(\.resource.key))
        #expect(declared.subtracting(covered).isEmpty, "missing from everyCase()")
        #expect(covered.subtracting(declared).isEmpty, "in everyCase() but declared nowhere")
    }

    @Test
    func `the scan reads a key and the whole call across an interpolation`() throws {
        let source = """
        // LocalizedStringResource("commented.out", defaultValue: "No", bundle: .module)
        LocalizedStringResource("a.key", defaultValue: "Hi \\(f(x)) (1)", bundle: .module)
        LocalizedStringResource(computedKey, bundle: .main)
        """
        let found = ResourceDeclarationScan.declarations(in: source, file: "Fixture.swift")
        try #require(found.count == 2)
        #expect(found[0].key == "a.key")
        #expect(found[0].arguments.hasSuffix("bundle: .module"))
        #expect(found[0].followsTheConvention)
        #expect(found[1].key == nil)
        #expect(!found[1].followsTheConvention)
    }

    @Test
    func `the catalog's English is exactly what Core renders in English`() throws {
        let catalog = try Self.catalog()
        for testCase in Self.everyCase() {
            let key = testCase.resource.key
            let english = try #require(
                catalog.strings[key]?.localizations[catalog.sourceLanguage]?.stringUnit?.value,
                "\(key) has no English value",
            )
            let formatted = String(format: english, arguments: testCase.arguments)
            #expect(formatted == testCase.resource.resolved(in: .english), "\(key)")
        }
    }

    @Test
    func `the catalog and Core's bundle both declare English as the development language`() throws {
        #expect(try Self.catalog().sourceLanguage == "en")
        guard case let .atURL(url) = TodoListStrings.title.bundle else {
            Issue.record("TodoListStrings.title is not looked up in Core's bundle")
            return
        }
        #expect(Bundle(url: url)?.developmentLocalization == "en")
    }
}

extension Locale {
    /// The catalog's source language. Expectations resolve in it explicitly, so a test's
    /// expected string does not depend on the language of the machine running it.
    static let english = Locale(identifier: "en")
}

extension LocalizedStringResource {
    /// The string this resource renders as in `locale` — what a view would show a
    /// reader whose language is `locale`.
    func resolved(in locale: Locale) -> String {
        var resource = self
        resource.locale = locale
        return String(localized: resource)
    }
}
