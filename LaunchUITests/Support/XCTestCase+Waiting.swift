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

    /// Waits until the software keyboard has presented and `control` sits above it, then
    /// asserts that it has: only then are typing and a tap on `control` safe.
    ///
    /// A field takes keyboard focus before the keyboard, another process's scene, presents,
    /// and on a cold-booted simulator that presentation can come seconds later. The add bar
    /// is pinned above the keyboard, so its arrival moves `control`; a tap resolved before
    /// it lands on the keyboard instead (#137). So this waits for the keyboard itself: of
    /// non-zero height, with `control` above it, and with the same frame on two checks in a
    /// row, so a keyboard still sliding in does not pass. A keyboard of no height is the
    /// minimized one a hardware keyboard brings, which `just uitest-run` turns off; it never
    /// passes, rather than passing before the full keyboard comes.
    @MainActor
    func waitForTheKeyboardToPresent(below control: XCUIElement, in app: XCUIApplication) {
        let keyboard = app.keyboards.firstMatch
        var lastFrame: CGRect?
        // XCTNSPredicateExpectation re-evaluates on the main run loop at its own bounded
        // interval, so this neither spins nor sleeps.
        let presented = NSPredicate { _, _ in
            MainActor.assumeIsolated {
                guard keyboard.exists else {
                    lastFrame = nil
                    return false
                }
                let frame = keyboard.frame
                defer { lastFrame = frame }
                return frame.height > 0
                    && control.frame.maxY <= frame.minY
                    && frame == lastFrame
            }
        }
        let expectation = XCTNSPredicateExpectation(predicate: presented, object: nil)
        XCTAssertEqual(
            XCTWaiter().wait(for: [expectation], timeout: Timeout.keyboardPresents),
            .completed,
            "the software keyboard should present below \(control.identifier)",
        )
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

    /// Waits until the list's new-item field is no longer hittable, which is when a
    /// pushed screen has covered the list, so an audit judges the pushed screen settled
    /// rather than mid-transition.
    @MainActor
    func waitForThePushToSettle(in app: XCUIApplication) {
        let covered = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false OR hittable == false"),
            object: app.textFields["newItemField"],
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [covered], timeout: Timeout.elementAppears),
            .completed,
            "the pushed screen should cover the list",
        )
    }
}
