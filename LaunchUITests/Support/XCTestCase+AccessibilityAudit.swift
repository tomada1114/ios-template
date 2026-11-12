import XCTest

extension XCTestCase {
    /// Whether the audit should let `issue` pass. Each case is a named, reasoned exception
    /// matched on the audit type and the element it reports, never on the type alone,
    /// and is reviewed like a lint disable: matching a whole audit type would switch that
    /// check off for every view the app adds (`AGENTS.md` › Security and human approval).
    /// An issue with no element is never accepted.
    @MainActor
    private static func isAcceptedAuditIssue(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        guard let element = issue.element else {
            return false
        }
        switch issue.auditType {
        case .contrast:
            // A disabled button: the system's button style draws its dimmed disabled
            // state, and WCAG 1.4.3 exempts an inactive control from the contrast minimum
            // (the empty field's Add button).
            if element.elementType == .button, !element.isEnabled {
                return true
            }
            // The detail screen's created date: `LabeledContent` in a `Form` draws its
            // value in the system's secondary label color, which the audit reports as
            // "nearly passed" at body size. Recoloring it would depart from the system
            // style (`.claude/rules/ui.md` › System first).
            return element.identifier == "createdDate"

        case .textClipped:
            // A single-line `TextField` is a UIKit text field that scrolls its text
            // sideways instead of wrapping, and the audit reports every one as "may be
            // clipped at larger Dynamic Type sizes" — an unstyled default field included.
            // A multi-line field would clear it, but there Return inserts a newline
            // instead of submitting (the add bar's `newItemField`).
            return element.elementType == .textField

        default:
            return false
        }
    }

    /// Runs Xcode's accessibility audit on whatever `app` shows now, and fails the test for
    /// every issue it finds — an element with no label, a hit region under 44 pt, text
    /// that clips at a large Dynamic Type size, low contrast, a trait that misdescribes a
    /// control — except one ``isAcceptedAuditIssue(_:)`` names.
    ///
    /// The audit sees the rendered screen, which SwiftLint's accessibility rules cannot: a
    /// glyph-only text button, a contrast pair, a control drawn smaller than its token.
    @MainActor
    func auditAccessibility(of app: XCUIApplication) throws {
        try app.performAccessibilityAudit { issue in
            Self.isAcceptedAuditIssue(issue)
        }
    }
}
