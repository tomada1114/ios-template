import XCTest

/// The failure launch's link steps — a deep link that arrives while a failure alert is
/// coming up (#140) — beside `LaunchTests.swift` so that file stays within SwiftLint's
/// length limits.
extension LaunchTests {
    /// Opens a link to an item that does not exist and comes back to the list, answering
    /// the system's "Open in …?" if this is the simulator's first link of the scheme, so
    /// every later link in the launch opens directly.
    @MainActor
    func openAFirstLinkAndGoBack(in app: XCUIApplication) {
        XCTAssertTrue(
            openFromTheSystem(
                link(toItemWithID: UUID()),
                expecting: app.staticTexts["Item Not Found"],
            ),
            "a link to an unknown item should show the detail screen's not-found state",
        )
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(
            app.textFields["newItemField"].waitForExistence(timeout: Timeout.elementAppears),
            "the back button should return from a linked screen to the list",
        )
    }

    /// A link that arrives while a failure alert is still coming up over the list moves
    /// nothing under it — UIKit drops a push that lands while an alert presents, which
    /// left the link dead (#140) — and pushes its screen once the person answers the
    /// alert. The link is opened the moment the alert exists, so it lands while the alert
    /// is still presenting.
    @MainActor
    func aLinkUnderAnAlertOverTheListWaitsForItsAnswer(in app: XCUIApplication) throws {
        let (toggle, id) = try theRowToggleAndItsItem(in: app)
        toggle.tap()
        let alert = app.alerts["Something Went Wrong"]
        XCTAssertTrue(
            waitForExistenceWithoutDelay(of: alert, timeout: Timeout.delayedFailure),
            "a toggle that fails on the list should present the failure there",
        )
        XCUIDevice.shared.system.open(link(toItemWithID: id))
        XCTAssertTrue(alert.exists, "a link should leave the alert it arrived under up")

        alert.buttons["OK"].tap()
        XCTAssertTrue(
            app.collectionViews["todoDetail"].waitForExistence(timeout: Timeout.elementAppears),
            "the link should push its detail screen once the alert is answered",
        )
        XCTAssertFalse(alert.exists, "the failure answered over the list should not present again")
        XCTAssertEqual(
            app.buttons["detailToggle"].label,
            "Mark as Done",
            "the item should stay open after its save failed",
        )
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(
            app.textFields["newItemField"].waitForExistence(timeout: Timeout.elementAppears),
            "the back button should return to the list",
        )
    }

    /// The same link under an alert over the About sheet: nothing moves until the alert
    /// is answered, the sheet included; then the sheet closes and, once it has left, the
    /// link's screen is pushed, showing the item unchanged.
    @MainActor
    func aLinkUnderAnAlertOverTheAboutSheetWaitsForItsAnswer(in app: XCUIApplication) throws {
        let (toggle, id) = try theRowToggleAndItsItem(in: app)
        toggle.tap()
        app.buttons["aboutButton"].tap()
        let sheet = waitForTheAboutSheetToSettle(in: app)
        let alert = app.alerts["Something Went Wrong"]
        XCTAssertTrue(
            waitForExistenceWithoutDelay(of: alert, timeout: Timeout.delayedFailure),
            "a failure that arrives while the About sheet is up should present over it",
        )
        XCUIDevice.shared.system.open(link(toItemWithID: id))
        XCTAssertTrue(alert.exists, "a link should leave the alert it arrived under up")
        XCTAssertTrue(sheet.exists, "a link should leave the sheet up while its alert is")

        alert.buttons["OK"].tap()
        XCTAssertTrue(
            waitForDisappearance(of: sheet),
            "the link should close the sheet once the alert is answered",
        )
        let detail = app.collectionViews["todoDetail"]
        XCTAssertTrue(
            detail.waitForExistence(timeout: Timeout.elementAppears),
            "the link should push its detail screen once the sheet has left",
        )
        XCTAssertFalse(alert.exists, "the failure answered over the sheet should not present again")
        XCTAssertEqual(
            app.buttons["detailToggle"].label,
            "Mark as Done",
            "the item should stay open after its save failed",
        )
    }

    /// The list's row toggle, and the item it toggles, read from the toggle's identifier.
    @MainActor
    private func theRowToggleAndItsItem(in app: XCUIApplication) throws -> (XCUIElement, UUID) {
        let toggle = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", Self.rowTogglePrefix))
            .firstMatch
        XCTAssertTrue(
            toggle.waitForExistence(timeout: Timeout.elementAppears),
            "the list should show the item's row toggle",
        )
        let id = try XCTUnwrap(
            UUID(uuidString: String(toggle.identifier.dropFirst(Self.rowTogglePrefix.count))),
            "the row toggle's identifier should end in the item's UUID",
        )
        return (toggle, id)
    }
}
