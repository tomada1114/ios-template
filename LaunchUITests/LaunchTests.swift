import XCTest

/// The template's launch guarantee: the app starts on a simulator, shows its list, and
/// the core interaction — adding an item — reaches the screen. Hiding completed items
/// proves the preferences wiring in `App/` reaches the view model, and opening an item
/// proves the navigation model reaches the stack; opening it by a deep link proves the
/// registered scheme and `App/`'s URL handling reach that model, and opening and closing
/// the About sheet proves the model's sheet reaches `RootView`'s `.sheet(item:)`. Deleting
/// in Edit mode proves a swipe is not the only way to delete. Xcode's accessibility audit
/// runs on the empty list, the list with an item, the About sheet, the detail screen, its
/// not-found state, and the All Done state
/// (`Support/XCTestCase+AccessibilityAudit.swift`).
///
/// XCTest by necessity — Apple has not ported UI automation to Swift Testing.
/// All other tests use Swift Testing in Packages/MyAppKit.
final class LaunchTests: XCTestCase {
    /// One launch walks every scenario in turn, because each relaunch costs tens of
    /// seconds on CI (#57). The steps are ordered so none undoes what a later one needs:
    /// audit the empty list, add, audit the list, open the About sheet, audit it and close
    /// it, open the detail, audit it and come back,
    /// open it and an unknown item by deep link, audit the not-found state and come back,
    /// complete and hide the item and audit the All Done state, show it again, then delete
    /// it in Edit mode.
    /// Each step runs as a named activity with its own assertion message, so a failure
    /// still names the broken behavior — but a failure stops the walk, so the steps after
    /// it go unreported until it is fixed.
    @MainActor
    func testLaunchedAppAddsOpensHidesAndDeletesAnItem() throws {
        // A failed assertion should end the test immediately instead of cascading
        // through the remaining waits against a dead app or a wrong screen.
        continueAfterFailure = false
        let app = XCUIApplication()
        // An in-memory store and scratch preferences (App/MyAppApp.swift), so the list
        // starts empty, and Hide Completed off, on every run. English, whatever the
        // simulator's language, because the tests find system controls ("Delete") by label.
        // Light appearance and the default text size, whatever the simulator is set to,
        // so the accessibility audits judge the same rendering on every run.
        XCUIDevice.shared.appearance = .light
        app.launchArguments = [
            "-uiTesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL",
        ]
        app.launch()

        try XCTContext.runActivity(named: "Audit the empty list's accessibility") { _ in
            try auditTheEmptyList(in: app)
        }
        XCTContext.runActivity(named: "Add an item") { _ in addAnItem(in: app) }
        try XCTContext.runActivity(named: "Audit the list's accessibility with an item") { _ in
            try auditTheListWithAnItem(in: app)
        }
        try XCTContext
            .runActivity(named: "Open the About sheet, audit it, then close it") { _ in
                try openTheAboutSheetAuditItAndCloseIt(in: app)
            }
        try XCTContext
            .runActivity(named: "Open the item's detail, audit it, then go back") { _ in
                try openTheDetailAuditItAndGoBack(in: app)
            }
        try XCTContext
            .runActivity(named: "Open the item, then an unknown item, by deep link, and audit") { _ in
                try openTheItemThenAnUnknownItemByDeepLink(in: app)
            }
        try XCTContext
            .runActivity(named: "Complete the item, hide completed items, and audit") { _ in
                try completeHideAndAuditTheItem(in: app)
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

    /// A failure presents over whichever screen is on top (#78), and over a sheet that is
    /// up (#124): a toggle that fails on the pushed detail screen shows its alert there,
    /// and dismissing it leaves the detail screen showing the item unchanged; a toggle on
    /// the list whose failure arrives once the About sheet is up shows its alert over the
    /// sheet, and dismissing it leaves the sheet up; and a deep link that arrives while
    /// the alert is coming up, over the list or over the sheet, pushes its screen once
    /// the alert is answered (#140).
    ///
    /// A link is opened first, before any save is in flight: the first link of the scheme
    /// on a simulator asks "Open in …?", and the links under an alert must reach the app
    /// at once.
    ///
    /// A launch of its own, because `-failUpdates` (Debug-only, `App/MyAppApp.swift`)
    /// fails every toggle for the whole launch, and the walk above needs one to succeed.
    /// `-delayFailedUpdates` makes each failure arrive `Timeout.failedUpdateDelay` after
    /// the tap, the time the sheet steps need to open the sheet over a save in flight.
    @MainActor
    func testAFailedTogglePresentsTheFailureOverTheDetailScreenAndOverASheet() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-failUpdates",
            "-delayFailedUpdates", String(Int(Timeout.failedUpdateDelay)),
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()

        XCTContext.runActivity(named: "Add an item") { _ in addAnItem(in: app) }
        XCTContext.runActivity(named: "Open a first link, which the system may ask about") { _ in
            openAFirstLinkAndGoBack(in: app)
        }
        XCTContext.runActivity(named: "Fail a toggle on the item's detail") { _ in
            failATogglePresentsTheFailureOnTheDetail(in: app)
        }
        XCTContext.runActivity(named: "Fail a toggle that lands while the About sheet is up") { _ in
            failATogglePresentsTheFailureOverTheAboutSheet(in: app)
        }
        try XCTContext
            .runActivity(named: "Open a link as an alert comes up over the list") { _ in
                try aLinkUnderAnAlertOverTheListWaitsForItsAnswer(in: app)
            }
        try XCTContext
            .runActivity(named: "Open a link as an alert comes up over the About sheet") { _ in
                try aLinkUnderAnAlertOverTheAboutSheetWaitsForItsAnswer(in: app)
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
            alert.waitForExistence(timeout: Timeout.delayedFailure),
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
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(
            app.textFields["newItemField"].waitForExistence(timeout: Timeout.elementAppears),
            "the back button should return to the list",
        )
    }

    @MainActor
    private func openTheDetailAuditItAndGoBack(in app: XCUIApplication) throws {
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
        waitForThePushToSettle(in: app)
        try auditAccessibility(of: app)
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(
            app.textFields["newItemField"].waitForExistence(timeout: Timeout.elementAppears),
            "the back button should return to the list",
        )
    }

    /// A link reaches the app through `App/`'s `.onOpenURL`, and Core's `DeepLink` and
    /// `NavigationModel` push the detail screen for the item it names, or the not-found
    /// state for an identifier no item has.
    @MainActor
    private func openTheItemThenAnUnknownItemByDeepLink(in app: XCUIApplication) throws {
        // The item's identifier, read from its row toggle rather than hard-coded: the
        // walk created the item, so only the running app knows it.
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

        // The found state's identifier lands on its Form, a collection view to XCUITest.
        let detail = app.collectionViews["todoDetail"]
        XCTAssertTrue(
            openFromTheSystem(link(toItemWithID: id), expecting: detail),
            "a link to an item should push that item's detail screen",
        )
        XCTAssertTrue(
            detail.staticTexts["Buy milk"].exists,
            "the detail screen a link opened should show the item it names",
        )

        XCTAssertTrue(
            openFromTheSystem(
                link(toItemWithID: UUID()),
                expecting: app.staticTexts["Item Not Found"],
            ),
            "a link to an unknown item should show the detail screen's not-found state",
        )
        // The found screen it replaced may still be animating out.
        XCTAssertTrue(
            waitForDisappearance(of: app.buttons["detailToggle"]),
            "the not-found state should show no item",
        )
        waitForThePushToSettle(in: app)
        try auditAccessibility(of: app)

        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(
            app.textFields["newItemField"].waitForExistence(timeout: Timeout.elementAppears),
            "the back button should return from a linked screen to the list",
        )
    }

    @MainActor
    private func completeHideAndAuditTheItem(in app: XCUIApplication) throws {
        let item = app.staticTexts["Buy milk"]
        let hideCompleted = app.buttons["hideCompletedToggle"]
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", Self.rowTogglePrefix))
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
        try auditAccessibility(of: app)
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

/// The audit steps the walk interleaves with its behavior steps.
extension LaunchTests {
    @MainActor
    private func auditTheEmptyList(in app: XCUIApplication) throws {
        XCTAssertTrue(
            app.staticTexts["No Items"].waitForExistence(timeout: Timeout.launch),
            "the list should start empty",
        )
        try auditAccessibility(of: app)
    }

    /// The keyboard the add left up is the system's, and it covers the list's lower half;
    /// the audit judges the list without it. Return on the empty field adds nothing
    /// (`canAdd` is false) and ends editing.
    @MainActor
    private func auditTheListWithAnItem(in app: XCUIApplication) throws {
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists {
            app.textFields["newItemField"].typeText("\n")
        }
        XCTAssertTrue(
            waitForDisappearance(of: keyboard),
            "Return on the empty field should dismiss the keyboard",
        )
        try auditAccessibility(of: app)
    }
}

/// What both launches and the sheet steps (`LaunchTests+AboutSheet.swift`) share, outside
/// the class body so they can be internal.
extension LaunchTests {
    /// The app's URL scheme, `DeepLink.scheme` in Core, which this target cannot import.
    /// One unsplit literal, so `scripts/bootstrap.sh` renames it with that constant and
    /// with the scheme `project.yml` registers.
    static let scheme = "my-app"

    /// The prefix of a row toggle's identifier; the rest is the item's `UUID`.
    static let rowTogglePrefix = "toggle-"

    @MainActor
    func addAnItem(in app: XCUIApplication) {
        let item = app.staticTexts["Buy milk"]
        let field = app.textFields["newItemField"]
        XCTAssertTrue(
            field.waitForExistence(timeout: Timeout.launch),
            "the list should show its new-item field",
        )
        let addButton = app.buttons["addButton"]
        focus(field)
        waitForTheKeyboardToPresent(below: addButton, in: app)
        field.typeText("Buy milk")
        addButton.tap()
        XCTAssertTrue(
            item.waitForExistence(timeout: Timeout.elementAppears),
            "the added item should appear in the list",
        )
    }

    /// Opens `url` as a tap on a link elsewhere would: the system resolves the scheme to
    /// the app the build registered it for and hands the link to the running app.
    /// `XCUIApplication.open(_:)` would relaunch the app instead, emptying its in-memory
    /// store. The first link of the scheme on a simulator asks "Open in …?" over the app;
    /// later ones open directly. So it waits for whichever comes first, `target` or the
    /// prompt, and answers the prompt only when it shows — with its last button, the
    /// confirming one after Cancel, because its labels follow the simulator's language.
    ///
    /// - Returns: whether `target` appeared within `Timeout.elementAppears` of the link
    ///   opening (or of the prompt being answered).
    @MainActor
    func openFromTheSystem(_ url: URL, expecting target: XCUIElement) -> Bool {
        XCUIDevice.shared.system.open(url)
        let prompt = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        var deadline = Date.now.addingTimeInterval(Timeout.elementAppears)
        while Date.now < deadline {
            if target.waitForExistence(timeout: Timeout.poll) {
                return true
            }
            if prompt.exists {
                let buttons = prompt.buttons
                buttons.element(boundBy: buttons.count - 1).tap()
                deadline = Date.now.addingTimeInterval(Timeout.elementAppears)
            }
        }
        return target.exists
    }

    /// The link that opens the item with `id`: the one shape `DeepLink` accepts.
    func link(toItemWithID id: UUID) -> URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "todo"
        components.path = "/\(id.uuidString)"
        guard let url = components.url else {
            preconditionFailure("could not form a link to item \(id)")
        }
        return url
    }
}
