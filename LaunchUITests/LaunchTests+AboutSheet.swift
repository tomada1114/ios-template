import XCTest

/// The launch walk's sheet step, beside `LaunchTests.swift` so that file stays within
/// SwiftLint's length limits.
extension LaunchTests {
    /// The toolbar button presents the sheet through `NavigationModel.present(_:)`, and
    /// the sheet's close button dismisses it through `dismissSheet()`, back to the list.
    @MainActor
    func openTheAboutSheetAuditItAndCloseIt(in app: XCUIApplication) throws {
        let about = app.buttons["aboutButton"]
        XCTAssertTrue(
            about.waitForExistence(timeout: Timeout.elementAppears),
            "the list should offer the About button",
        )
        about.tap()
        // The identifier lands on the sheet's Form, a collection view to XCUITest.
        let sheet = app.collectionViews["aboutSheet"]
        XCTAssertTrue(
            sheet.waitForExistence(timeout: Timeout.elementAppears),
            "the About button should present the About sheet",
        )
        let close = app.buttons["aboutCloseButton"]
        XCTAssertTrue(close.exists, "the About sheet should offer a close button")
        waitForTheListToBeCovered(in: app)
        try auditAccessibility(of: app)

        close.tap()
        XCTAssertTrue(waitForDisappearance(of: sheet), "the close button should dismiss the sheet")
        XCTAssertTrue(
            app.textFields["newItemField"].waitForExistence(timeout: Timeout.elementAppears),
            "closing the About sheet should return to the list",
        )
        XCTAssertTrue(
            app.staticTexts["Buy milk"].exists,
            "the list under the sheet should still show its item",
        )
    }
}
