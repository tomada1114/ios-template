import XCTest

/// The template's launch guarantee: the app starts on a simulator, shows its list, and
/// the core interaction — adding an item — reaches the screen.
///
/// XCTest by necessity — Apple has not ported UI automation to Swift Testing.
/// All other tests use Swift Testing in Packages/MyAppKit.
final class LaunchTests: XCTestCase {
    private enum Timeout {
        static let launch: TimeInterval = 20
        static let elementAppears: TimeInterval = 5
        static let keyboardFocus: TimeInterval = 3
    }

    /// Taps `field` until it holds keyboard focus, then asserts that it does.
    ///
    /// On a loaded CI runner the first tap can land before SwiftUI makes the field
    /// first responder, and `typeText` then fails with "Neither element nor any
    /// descendant has keyboard focus" (#32). Re-tapping retries the input, not the
    /// assertion: the test still fails if the field never takes focus.
    @MainActor
    private func focus(_ field: XCUIElement, attempts: Int = 3) {
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        for _ in 0 ..< attempts {
            field.tap()
            let expectation = XCTNSPredicateExpectation(predicate: focused, object: field)
            if XCTWaiter().wait(for: [expectation], timeout: Timeout.keyboardFocus) == .completed {
                return
            }
        }
        XCTFail("newItemField never took keyboard focus after \(attempts) taps")
    }

    @MainActor
    func testAddingAnItemShowsItInTheList() {
        // A failed launch assertion should end the test immediately instead of
        // cascading through the remaining waits against a dead app.
        continueAfterFailure = false

        let app = XCUIApplication()
        // An in-memory store (App/MyAppApp.swift), so the list starts empty on every run.
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let field = app.textFields["newItemField"]
        XCTAssertTrue(field.waitForExistence(timeout: Timeout.launch))
        focus(field)
        field.typeText("Buy milk")
        app.buttons["addButton"].tap()

        XCTAssertTrue(
            app.staticTexts["Buy milk"].waitForExistence(timeout: Timeout.elementAppears),
            "the added item should appear in the list",
        )
    }
}
