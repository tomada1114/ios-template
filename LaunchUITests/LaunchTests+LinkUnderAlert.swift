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
        HeldFailure.release()
        let alert = app.alerts["Something Went Wrong"]
        XCTAssertTrue(
            waitForExistenceWithoutDelay(of: alert, timeout: Timeout.releasedFailureAppears),
            "a toggle that fails on the list should present the failure there",
        )
        XCUIDevice.shared.system.open(link(toItemWithID: id))
        waitForTheLinkToWait(under: alert, in: app)

        alert.buttons["OK"].tap()
        waitForTheLinkedDetail(in: app, uncoveredBy: alert)
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
        HeldFailure.release()
        let alert = app.alerts["Something Went Wrong"]
        XCTAssertTrue(
            waitForExistenceWithoutDelay(of: alert, timeout: Timeout.releasedFailureAppears),
            "a failure that arrives while the About sheet is up should present over it",
        )
        XCUIDevice.shared.system.open(link(toItemWithID: id))
        waitForTheLinkToWait(under: alert, in: app)
        XCTAssertTrue(sheet.exists, "a link should leave the sheet up while its alert is")

        alert.buttons["OK"].tap()
        XCTAssertTrue(
            waitForDisappearance(of: sheet),
            "the link should close the sheet once the alert is answered",
        )
        waitForTheLinkedDetail(in: app, uncoveredBy: alert)
    }

    /// Waits until the app holds the link back, and asserts it moved nothing: the app
    /// says so through an invisible element it adds only under `-uiTesting`
    /// (`MyAppUI`'s `WaitingLinkMarker`), because by design nothing a person can see
    /// changes under the alert. Without it, a link still on its way and a link that is
    /// waiting look the same, and OK tapped before the link arrived would show the same
    /// detail screen through the path that never waits.
    @MainActor
    private func waitForTheLinkToWait(under alert: XCUIElement, in app: XCUIApplication) {
        let marker = app.descendants(matching: .any)
            .matching(identifier: "waitingLinkMarker")
            .firstMatch
        XCTAssertTrue(
            marker.waitForExistence(timeout: Timeout.elementAppears),
            "a link that arrives under an alert should wait for the alert's answer",
        )
        XCTAssertTrue(alert.exists, "a link should leave the alert it arrived under up")
        XCTAssertFalse(
            app.collectionViews["todoDetail"].exists,
            "a link should push nothing while the alert it arrived under is up",
        )
    }

    /// Waits for the link's detail screen, then for its toggle to be hittable: nothing
    /// covers the screen, so the failure `alert` showed did not present again over it —
    /// an alert coming back would be up by the time the push has finished, and nothing
    /// under an alert is hittable.
    @MainActor
    private func waitForTheLinkedDetail(in app: XCUIApplication, uncoveredBy alert: XCUIElement) {
        XCTAssertTrue(
            app.collectionViews["todoDetail"].waitForExistence(timeout: Timeout.elementAppears),
            "the link should push its detail screen once the alert is answered",
        )
        let toggle = app.buttons["detailToggle"]
        let uncovered = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"),
            object: toggle,
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [uncovered], timeout: Timeout.elementAppears),
            .completed,
            "nothing should cover the linked screen once its push has finished",
        )
        XCTAssertFalse(alert.exists, "a failure that was answered should not present again")
        XCTAssertEqual(
            toggle.label,
            "Mark as Done",
            "the item should stay open after its save failed",
        )
    }

    /// The list's row toggle, and the item it toggles, read from the toggle's identifier
    /// rather than hard-coded: the test created the item, so only the running app knows
    /// it.
    @MainActor
    func theRowToggleAndItsItem(in app: XCUIApplication) throws -> (XCUIElement, UUID) {
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
