import XCTest

/// The template's launch guarantee: the app starts on a simulator, shows its list, and
/// the core interaction — adding an item — reaches the screen. Hiding completed items
/// proves the preferences wiring in `App/` reaches the view model, and opening an item
/// proves the navigation model reaches the stack. Deleting in Edit mode proves a swipe
/// is not the only way to delete.
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

    /// Launches the app under test and adds "Buy milk", asserting it appears.
    @MainActor
    private func launchAndAddAnItem() -> XCUIApplication {
        let app = XCUIApplication()
        // An in-memory store and scratch preferences (App/MyAppApp.swift), so the list
        // starts empty, and Hide Completed off, on every run.
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
        return app
    }

    @MainActor
    func testAddingAnItemShowsItInTheList() {
        // A failed launch assertion should end the test immediately instead of
        // cascading through the remaining waits against a dead app.
        continueAfterFailure = false
        _ = launchAndAddAnItem()
    }

    @MainActor
    func testOpeningAnItemShowsItsDetail() {
        continueAfterFailure = false
        let app = launchAndAddAnItem()

        app.staticTexts["Buy milk"].tap()

        // The identifier lands on the detail screen's Form, which XCUITest sees as a
        // collection view; the not-found state would carry it on another element type.
        XCTAssertTrue(
            app.collectionViews["todoDetail"].waitForExistence(timeout: Timeout.elementAppears),
            "tapping a row's title should push that item's detail screen",
        )
        XCTAssertTrue(
            app.buttons["detailToggle"].exists,
            "the detail screen should show the item it was opened for",
        )
    }

    @MainActor
    func testEditModeDeletesAnItemWithoutASwipe() {
        continueAfterFailure = false
        let app = launchAndAddAnItem()

        let edit = app.buttons["editButton"]
        XCTAssertTrue(edit.waitForExistence(timeout: Timeout.elementAppears))
        edit.tap()

        // Edit mode's leading delete control carries no accessibility element of its own,
        // so the test taps the cell's leading edge, where the control sits, and then the
        // trailing Delete button it reveals.
        let cell = app.cells.containing(.staticText, identifier: "Buy milk").firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: Timeout.elementAppears))
        cell.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: 20, dy: 0))
            .tap()
        let confirm = app.buttons["Delete"]
        XCTAssertTrue(
            confirm.waitForExistence(timeout: Timeout.elementAppears),
            "Edit mode's delete control should reveal the Delete button",
        )
        confirm.tap()

        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: app.staticTexts["Buy milk"],
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [gone], timeout: Timeout.elementAppears),
            .completed,
            "deleting in Edit mode should remove the item",
        )
    }

    @MainActor
    func testHidingCompletedItemsHidesThem() {
        continueAfterFailure = false
        let app = launchAndAddAnItem()

        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'toggle-'"))
            .firstMatch.tap()
        let hideCompleted = app.buttons["hideCompletedToggle"]
        XCTAssertTrue(hideCompleted.waitForExistence(timeout: Timeout.elementAppears))
        hideCompleted.tap()

        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: app.staticTexts["Buy milk"],
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [gone], timeout: Timeout.elementAppears),
            .completed,
            "the done item should be hidden",
        )
        XCTAssertTrue(
            app.staticTexts["All Done"].waitForExistence(timeout: Timeout.elementAppears),
            "the all-done state should replace the hidden list",
        )
    }
}
