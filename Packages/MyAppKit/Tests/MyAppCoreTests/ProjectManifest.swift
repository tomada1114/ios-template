import Foundation

/// The one reader of `project.yml` scalar values the Core suites hold Core to:
/// `AppLogTests` (the bundle identifier), `AppConfigurationTests` (the `Info.plist`
/// key), and `DeepLinkTests` (unquoting a scheme). One reader, so the suites cannot
/// disagree about how a manifest line is read.
enum ProjectManifest {
    /// The value the first line starting with `key:` (once trimmed) gives `key`, read
    /// with `scripts/bundle-id.sh`'s rules: a YAML trailing comment (whitespace, then
    /// `#`) and one surrounding pair of single or double quotes are stripped, and the
    /// rest is taken literally.
    ///
    /// Only the first line counts, so a later target never shadows the app target's.
    /// Answers `nil` when no line sets `key`, or sets it to nothing or only a comment.
    static func value(of key: String, inManifest manifest: String) -> String? {
        let prefix = "\(key):"
        // components(separatedBy: .newlines) splits on CR as well as LF, so a CRLF
        // manifest leaves no stray carriage return behind — bundle-id.sh's `tr -d '\r'`.
        let declaration = manifest
            .components(separatedBy: .newlines)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix(prefix) }
        guard let declaration else {
            return nil
        }
        var value = String(declaration.dropFirst(prefix.count))
        // A `#` only starts a YAML comment when whitespace precedes it, so everything
        // from there on is not the value. A value that is only a comment is no value.
        if let comment = value.range(of: #"\s#"#, options: .regularExpression) {
            value = String(value[value.startIndex ..< comment.lowerBound])
        }
        value = value.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") {
            return nil
        }
        value = unquoted(value)
        return value.isEmpty ? nil : value
    }

    /// Strips one surrounding pair of matching single or double quotes, as
    /// `scripts/bundle-id.sh` does; any other value is returned untouched.
    static func unquoted(_ value: String) -> String {
        for quote in ["\"", "'"] {
            if value.count > 1, value.hasPrefix(quote), value.hasSuffix(quote) {
                return String(value.dropFirst().dropLast())
            }
        }
        return value
    }
}
