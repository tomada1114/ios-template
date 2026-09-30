import Foundation

/// One `LocalizedStringResource(…)` call found in a Swift source file.
struct ResourceDeclaration {
    /// The file it is in, relative to `Sources/MyAppCore`, for a failure message.
    let file: String
    /// The first argument when it is a plain string literal, or `nil` when it is not —
    /// an interpolated or computed first argument is not a catalog key.
    let key: String?
    /// Everything between the call's parentheses.
    let arguments: Substring

    /// Whether the call follows `localizing-the-app`'s declaration: an explicit key, a
    /// `defaultValue`, and Core's own bundle.
    var followsTheConvention: Bool {
        key != nil && arguments.contains("defaultValue:") && arguments.contains("bundle: .module")
    }
}

/// Where a scan stands inside a call's argument list: how many parentheses are open,
/// whether it is inside a string literal, and at which depth each open `\(` began.
private struct CallCursor {
    private var depth = 1
    private var inString = false
    private var escaping = false
    private var interpolationDepths: [Int] = []

    /// Moves past `character`; `true` when it was the `)` that closes the call.
    mutating func consume(_ character: Character) -> Bool {
        if inString {
            consumeInString(character)
            return false
        }
        switch character {
        case "\"":
            inString = true

        case "(":
            depth += 1

        case ")":
            return close()

        default:
            break
        }
        return false
    }

    private mutating func consumeInString(_ character: Character) {
        if escaping {
            escaping = false
            if character == "(" {
                interpolationDepths.append(depth)
                depth += 1
                inString = false
            }
        } else if character == "\\" {
            escaping = true
        } else if character == "\"" {
            inString = false
        }
    }

    private mutating func close() -> Bool {
        depth -= 1
        if let opened = interpolationDepths.last, depth == opened {
            interpolationDepths.removeLast()
            inString = true
            return false
        }
        return depth == 0
    }
}

/// Finds `LocalizedStringResource(…)` calls in Swift source text, so `LocalizationTests`
/// learns Core's keys from the code rather than from a hand-kept list.
///
/// A text scan, not a parser — the same trade `ArchitectureBoundaryTests` makes. It
/// follows string literals and their `\(…)` interpolations, so a parenthesis inside
/// either does not end the call, and it skips a call on a `//` line. It does not see a
/// resource made from a bare literal (`let title: LocalizedStringResource = "Reset"`),
/// and a `"` inside a comment within the call's arguments would mislead it.
enum ResourceDeclarationScan {
    static let callPrefix = "LocalizedStringResource("

    /// Every call in `Sources/MyAppCore/**/*.swift`.
    static func declarations(inSourcesAt root: URL) throws -> [ResourceDeclaration] {
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        return try files.flatMap { url in
            let relative = String(url.path.dropFirst(root.path.count + 1))
            return try declarations(in: String(contentsOf: url, encoding: .utf8), file: relative)
        }
    }

    /// Every call in `text`, which came from `file`.
    static func declarations(in text: String, file: String) -> [ResourceDeclaration] {
        text.ranges(of: callPrefix).compactMap { range in
            let lineStart = text[..<range.lowerBound].lastIndex(of: "\n") ?? text.startIndex
            guard !text[lineStart ..< range.lowerBound].contains("//"),
                  let arguments = argumentList(of: text, from: range.upperBound)
            else {
                return nil
            }
            return ResourceDeclaration(
                file: file,
                key: leadingStringLiteral(of: arguments),
                arguments: arguments,
            )
        }
    }

    /// The text from `start`, just after a call's `(`, up to its matching `)`.
    static func argumentList(of text: String, from start: String.Index) -> Substring? {
        var cursor = CallCursor()
        for index in text[start...].indices where cursor.consume(text[index]) {
            return text[start ..< index]
        }
        return nil
    }

    /// The first argument's value when it is a plain string literal with no escape or
    /// interpolation.
    static func leadingStringLiteral(of arguments: Substring) -> String? {
        let trimmed = arguments.drop(while: \.isWhitespace)
        guard trimmed.first == "\"" else {
            return nil
        }
        let body = trimmed.dropFirst().prefix { $0 != "\"" }
        return body.contains("\\") ? nil : String(body)
    }
}
