import XCTest

/// The waits every UI test file shares, so a second file does not copy them.
extension XCTestCase {
    /// Taps `field` until it holds keyboard focus, then asserts that it does.
    ///
    /// On a loaded CI runner the first tap can land before SwiftUI makes the field
    /// first responder, and `typeText` then fails with "Neither element nor any
    /// descendant has keyboard focus" (#32). Re-tapping retries the input, not the
    /// assertion: the test still fails if the field never takes focus.
    @MainActor
    func focus(_ field: XCUIElement) {
        let attempts = 3
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        for _ in 0 ..< attempts {
            field.tap()
            let expectation = XCTNSPredicateExpectation(predicate: focused, object: field)
            if XCTWaiter().wait(for: [expectation], timeout: Timeout.keyboardFocus) == .completed {
                return
            }
        }
        XCTFail("\(field.identifier) never took keyboard focus after \(attempts) taps")
    }

    /// Waits until `element` no longer exists, and reports whether it went.
    @MainActor
    func waitForDisappearance(of element: XCUIElement) -> Bool {
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: element,
        )
        return XCTWaiter().wait(for: [gone], timeout: Timeout.elementAppears) == .completed
    }
}
