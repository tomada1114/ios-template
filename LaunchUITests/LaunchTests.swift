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
        field.tap()
        field.typeText("Buy milk")
        app.buttons["addButton"].tap()

        XCTAssertTrue(
            app.staticTexts["Buy milk"].waitForExistence(timeout: Timeout.elementAppears),
            "the added item should appear in the list",
        )
    }
}
