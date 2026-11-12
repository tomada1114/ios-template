import XCTest

/// The launch walk's sheet step, beside `LaunchTests.swift` so that file stays within
/// SwiftLint's length limits.
extension LaunchTests {
    /// The toolbar button presents the sheet through `NavigationModel.present(_:)`, and
    /// the sheet's close button dismisses it through `dismissSheet(_:)`, back to the list.
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
        // Settled when its close button can be tapped: the sheet has finished sliding
        // in. The list behind it is no signal, since on iPad a form sheet leaves it
        // partly uncovered.
        let close = app.buttons["aboutCloseButton"]
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"),
            object: close,
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [settled], timeout: Timeout.elementAppears),
            .completed,
            "the About sheet should settle with its close button hittable",
        )
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
