import XCTest

/// The sheet steps — the launch walk's, and the failure launch's — beside
/// `LaunchTests.swift` so that file stays within SwiftLint's length limits.
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
        let sheet = waitForTheAboutSheetToSettle(in: app)
        try auditAccessibility(of: app)
        app.buttons["aboutCloseButton"].tap()
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

    /// A failure that arrives while a sheet is up presents over the sheet, from the
    /// sheet's own `failureAlert` (`RootView`), and dismissing it leaves the sheet up. The
    /// toggle's save is still in flight when the sheet opens: `-delayFailedUpdates` holds
    /// its failure back for seconds, and the step proves the alert is not up yet once the
    /// sheet has settled, so the alert that follows arrived under the sheet.
    @MainActor
    func failATogglePresentsTheFailureOverTheAboutSheet(in app: XCUIApplication) {
        let toggle = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", Self.rowTogglePrefix))
            .firstMatch
        XCTAssertTrue(
            toggle.waitForExistence(timeout: Timeout.elementAppears),
            "the list should show the item's row toggle",
        )
        toggle.tap()
        app.buttons["aboutButton"].tap()
        let sheet = waitForTheAboutSheetToSettle(in: app)
        let alert = app.alerts["Something Went Wrong"]
        XCTAssertFalse(
            alert.exists,
            "the toggle's failure should still be in flight once the sheet has settled",
        )

        XCTAssertTrue(
            alert.waitForExistence(timeout: Timeout.delayedFailure),
            "a failure that arrives while the About sheet is up should present over it",
        )
        XCTAssertTrue(
            alert.staticTexts["Your change could not be saved."].exists,
            "the alert should say the change was not saved",
        )
        alert.buttons["OK"].tap()
        XCTAssertTrue(waitForDisappearance(of: alert), "OK should dismiss the alert")
        XCTAssertTrue(sheet.exists, "dismissing the alert should leave the sheet up")

        app.buttons["aboutCloseButton"].tap()
        XCTAssertTrue(waitForDisappearance(of: sheet), "the close button should dismiss the sheet")
        XCTAssertTrue(
            app.textFields["newItemField"].waitForExistence(timeout: Timeout.elementAppears),
            "closing the About sheet should return to the list",
        )
        XCTAssertFalse(
            alert.exists,
            "the failure dismissed over the sheet should not present again over the list",
        )
    }

    /// Waits for the About sheet to present and settle, and returns it. Settled when its
    /// close button can be tapped: the sheet has finished sliding in. The list behind it is
    /// no signal, since on iPad a form sheet leaves it partly uncovered.
    @MainActor
    private func waitForTheAboutSheetToSettle(in app: XCUIApplication) -> XCUIElement {
        // The identifier lands on the sheet's Form, a collection view to XCUITest.
        let sheet = app.collectionViews["aboutSheet"]
        XCTAssertTrue(
            sheet.waitForExistence(timeout: Timeout.elementAppears),
            "the About button should present the About sheet",
        )
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"),
            object: app.buttons["aboutCloseButton"],
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [settled], timeout: Timeout.elementAppears),
            .completed,
            "the About sheet should settle with its close button hittable",
        )
        return sheet
    }
}
