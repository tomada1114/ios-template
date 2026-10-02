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

    /// Waits until `element` no longer exists, and reports whether it went.
    @MainActor
    private func waitForDisappearance(of element: XCUIElement) -> Bool {
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: element,
        )
        return XCTWaiter().wait(for: [gone], timeout: Timeout.elementAppears) == .completed
    }

    /// One launch walks every scenario in turn, because each relaunch costs tens of
    /// seconds on CI (#57). The steps are ordered so none undoes what a later one needs:
    /// add, open the detail and come back, complete and hide the item, show it again,
    /// then delete it in Edit mode. Each step runs as a named activity with its own
    /// assertion message, so a failure still names the broken behavior — but a failure
    /// stops the walk, so the steps after it go unreported until it is fixed.
    @MainActor
    func testLaunchedAppAddsOpensHidesAndDeletesAnItem() {
        // A failed assertion should end the test immediately instead of cascading
        // through the remaining waits against a dead app or a wrong screen.
        continueAfterFailure = false
        let app = XCUIApplication()
        // An in-memory store and scratch preferences (App/MyAppApp.swift), so the list
        // starts empty, and Hide Completed off, on every run. English, whatever the
        // simulator's language, because the tests find system controls ("Delete") by label.
        app.launchArguments = ["-uiTesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        XCTContext.runActivity(named: "Add an item") { _ in addAnItem(in: app) }
        XCTContext
            .runActivity(named: "Open the item's detail, then go back") { _ in
                openTheDetailAndGoBack(in: app)
            }
        XCTContext
            .runActivity(named: "Complete the item and hide completed items") { _ in
                completeAndHideTheItem(in: app)
            }
        XCTContext
            .runActivity(named: "Show completed items again") { _ in
                showCompletedItemsAgain(in: app)
            }
        XCTContext
            .runActivity(named: "Delete the item in Edit mode") { _ in
                deleteTheItemInEditMode(in: app)
            }
    }

    /// A failure presents over whichever screen is on top (#78): a toggle that fails on
    /// the pushed detail screen shows its alert there, and dismissing it leaves the
    /// detail screen showing the item unchanged.
    ///
    /// A launch of its own, because `-failUpdates` (Debug-only, `App/MyAppApp.swift`)
    /// fails every toggle for the whole launch, and the walk above needs one to succeed.
    @MainActor
    func testAFailedToggleOnTheDetailScreenPresentsTheFailureThere() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-failUpdates",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()

        XCTContext.runActivity(named: "Add an item") { _ in addAnItem(in: app) }
        XCTContext.runActivity(named: "Fail a toggle on the item's detail") { _ in
            failATogglePresentsTheFailureOnTheDetail(in: app)
        }
    }

    @MainActor
    private func failATogglePresentsTheFailureOnTheDetail(in app: XCUIApplication) {
        app.staticTexts["Buy milk"].tap()
        let detail = app.collectionViews["todoDetail"]
        XCTAssertTrue(
            detail.waitForExistence(timeout: Timeout.elementAppears),
            "tapping a row's title should push that item's detail screen",
        )
        let toggle = app.buttons["detailToggle"]
        XCTAssertEqual(toggle.label, "Mark as Done", "the item should start open")
        toggle.tap()

        let alert = app.alerts["Something Went Wrong"]
        XCTAssertTrue(
            alert.waitForExistence(timeout: Timeout.elementAppears),
            "a toggle that fails on the detail screen should present the failure there",
        )
        XCTAssertTrue(
            alert.staticTexts["Your change could not be saved."].exists,
            "the alert should say the change was not saved",
        )
        alert.buttons["OK"].tap()
        XCTAssertTrue(waitForDisappearance(of: alert), "OK should dismiss the alert")
        XCTAssertTrue(detail.exists, "dismissing the alert should leave the detail on top")
        XCTAssertEqual(
            toggle.label,
            "Mark as Done",
            "the item should stay open after its save failed",
        )
    }

    @MainActor
    private func addAnItem(in app: XCUIApplication) {
        let item = app.staticTexts["Buy milk"]
        let field = app.textFields["newItemField"]
        XCTAssertTrue(
            field.waitForExistence(timeout: Timeout.launch),
            "the list should show its new-item field",
        )
        focus(field)
        field.typeText("Buy milk")
        app.buttons["addButton"].tap()
        XCTAssertTrue(
            item.waitForExistence(timeout: Timeout.elementAppears),
            "the added item should appear in the list",
        )
    }

    @MainActor
    private func openTheDetailAndGoBack(in app: XCUIApplication) {
        let item = app.staticTexts["Buy milk"]
        item.tap()
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
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(
            app.textFields["newItemField"].waitForExistence(timeout: Timeout.elementAppears),
            "the back button should return to the list",
        )
    }

    @MainActor
    private func completeAndHideTheItem(in app: XCUIApplication) {
        let item = app.staticTexts["Buy milk"]
        let hideCompleted = app.buttons["hideCompletedToggle"]
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'toggle-'"))
            .firstMatch.tap()
        XCTAssertTrue(
            hideCompleted.waitForExistence(timeout: Timeout.elementAppears),
            "the list should offer the Hide Completed toggle",
        )
        hideCompleted.tap()
        XCTAssertTrue(waitForDisappearance(of: item), "the done item should be hidden")
        XCTAssertTrue(
            app.staticTexts["All Done"].waitForExistence(timeout: Timeout.elementAppears),
            "the all-done state should replace the hidden list",
        )
    }

    @MainActor
    private func showCompletedItemsAgain(in app: XCUIApplication) {
        let item = app.staticTexts["Buy milk"]
        let hideCompleted = app.buttons["hideCompletedToggle"]
        hideCompleted.tap()
        XCTAssertTrue(
            item.waitForExistence(timeout: Timeout.elementAppears),
            "turning Hide Completed off should show the done item again",
        )
    }

    @MainActor
    private func deleteTheItemInEditMode(in app: XCUIApplication) {
        let item = app.staticTexts["Buy milk"]
        let edit = app.buttons["editButton"]
        XCTAssertTrue(
            edit.waitForExistence(timeout: Timeout.elementAppears),
            "the list should offer an Edit button",
        )
        edit.tap()
        // Edit mode's leading delete control carries no accessibility element of its
        // own, so the test taps the cell's leading edge, where the control sits, and
        // then the trailing Delete button it reveals.
        let cell = app.cells.containing(.staticText, identifier: "Buy milk").firstMatch
        XCTAssertTrue(
            cell.waitForExistence(timeout: Timeout.elementAppears),
            "the item's row should exist",
        )
        cell.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: 20, dy: 0))
            .tap()
        let confirm = app.buttons["Delete"]
        XCTAssertTrue(
            confirm.waitForExistence(timeout: Timeout.elementAppears),
            "Edit mode's delete control should reveal the Delete button",
        )
        confirm.tap()
        XCTAssertTrue(
            waitForDisappearance(of: item),
            "deleting in Edit mode should remove the item",
        )
    }
}
