import XCTest

/// One look at the keyboard and the control above it, kept to compare with the next.
private struct KeyboardSample {
    let takenAt: Date
    let keyboard: CGRect
    let control: CGRect
}

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
    /// non-zero height, with `control` above it, and with both frames unchanged across two
    /// samples at least `Timeout.poll` apart, so neither a keyboard still sliding in nor a
    /// bar still rising passes. The full software keyboard is required: a hardware
    /// keyboard minimizes it to a bar of no height, which never passes, rather than
    /// passing before the full keyboard comes. `just uitest-run` turns minimization off.
    @MainActor
    func waitForTheKeyboardToPresent(below control: XCUIElement, in app: XCUIApplication) {
        let keyboard = app.keyboards.firstMatch
        var last: KeyboardSample?
        // XCTNSPredicateExpectation re-evaluates on the main run loop at its own interval;
        // the sample gap below bounds the stability window whatever that interval is.
        let presented = NSPredicate { _, _ in
            MainActor.assumeIsolated {
                guard keyboard.exists else {
                    last = nil
                    return false
                }
                let now = Date.now
                if let last, now.timeIntervalSince(last.takenAt) < Timeout.poll {
                    return false
                }
                let sample = KeyboardSample(
                    takenAt: now,
                    keyboard: keyboard.frame,
                    control: control.frame,
                )
                defer { last = sample }
                return sample.keyboard.height > 0
                    && sample.control.maxY <= sample.keyboard.minY
                    && sample.keyboard == last?.keyboard
                    && sample.control == last?.control
            }
        }
        let expectation = XCTNSPredicateExpectation(predicate: presented, object: nil)
        XCTAssertEqual(
            XCTWaiter().wait(for: [expectation], timeout: Timeout.keyboardPresents),
            .completed,
            """
            the full software keyboard should present below \(control.identifier); a \
            hardware keyboard minimizes it, and `just uitest-run` turns that off
            """,
        )
    }

    /// Waits until `element` exists, and reports whether it came, asking again as soon as
    /// each answer is in: `waitForExistence(timeout:)` asks about once a second, so what a
    /// test does next lands up to a second after the element appeared. For a step whose
    /// next action must land while the element is still arriving — a link opened as an
    /// alert presents (#140). Each question is a round trip to the app, never a spin.
    @MainActor
    func waitForExistenceWithoutDelay(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if element.exists {
                return true
            }
        }
        return false
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
