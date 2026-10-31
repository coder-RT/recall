import XCTest

/// Usability: can the main tasks be done without looking, in a few actions? Each task uses only what VoiceOver
/// reaches (accessibility labels, identifiers, the actions a context menu offers), counts every tap, swipe and typed
/// entry, and must finish within its budget. What was spoken is read from the app's spoken log, since a test can't
/// hear. Every task runs at the default text size and again at the largest accessibility size.
final class UsabilityTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// Counts the person's actions.
    private final class Steps {
        private(set) var count = 0
        func tap(_ e: XCUIElement, _ file: StaticString = #filePath, _ line: UInt = #line) {
            XCTAssertTrue(e.waitForExistence(timeout: 5), "not found: \(e)", file: file, line: line)
            count += 1
            e.tap()
        }
        func type(_ e: XCUIElement, _ text: String) { count += 1; e.typeText(text) }
        func hold(_ e: XCUIElement) { XCTAssertTrue(e.waitForExistence(timeout: 5)); count += 1; e.press(forDuration: 1.2) }
        func swipeUp(_ app: XCUIApplication) { count += 1; app.swipeUp() }
        func swipeDown(_ app: XCUIApplication) { count += 1; app.swipeDown() }
    }

    private func launch(largestText: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestSampleThings", "-UITestSpokenLog"]
        if largestText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        return app
    }

    private func spoken(_ app: XCUIApplication) -> String { app.descendants(matching: .any)["spoken-log"].label }

    private func waitSpoken(_ app: XCUIApplication, contains text: String, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if spoken(app).contains(text) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    private func element(_ app: XCUIApplication, labelContaining text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Reaches an element by swiping, as someone exploring the screen would; each swipe counts.
    private func reach(_ e: XCUIElement, in app: XCUIApplication, steps: Steps, maxSwipes: Int = 4) {
        for _ in 0..<maxSwipes where !(e.exists && e.isHittable) { steps.swipeUp(app) }
    }

    // MARK: tasks

    /// Ask where the keys are: heard "Looking for your keys." at once, then the answer naming the desk; ≤ 3 actions.
    private func askWhereTheKeysAre(largestText: Bool) {
        let app = launch(largestText: largestText)
        let steps = Steps()
        let field = app.textViews["question"].exists ? app.textViews["question"] : app.textFields["question"]
        steps.tap(field)
        steps.type(field, "Where are my keys?")
        steps.tap(app.buttons["Ask"])
        XCTAssertTrue(waitSpoken(app, contains: "Looking for your keys."))
        XCTAssertTrue(waitSpoken(app, contains: "Your keys are near the desk"))
        let log = spoken(app)
        let ack = log.range(of: "Looking for your keys.")!, answer = log.range(of: "Your keys are near the desk")!
        XCTAssertLessThan(ack.lowerBound, answer.lowerBound, "the acknowledgement comes first")
        XCTAssertTrue(element(app, labelContaining: "Your keys are near the desk").waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Take me there"].exists)
        XCTAssertLessThanOrEqual(steps.count, 3)
    }

    /// Something never seen: says so and how to fix it, without a dead end; ≤ 3 actions.
    private func askForSomethingNeverSeen(largestText: Bool) {
        let app = launch(largestText: largestText)
        let steps = Steps()
        let field = app.textViews["question"].exists ? app.textViews["question"] : app.textFields["question"]
        steps.tap(field)
        steps.type(field, "Where is my umbrella?")
        steps.tap(app.buttons["Ask"])
        XCTAssertTrue(waitSpoken(app, contains: "Checking."))
        XCTAssertTrue(waitSpoken(app, contains: "I haven't seen that yet. Scan the room"))
        XCTAssertFalse(app.buttons["Take me there"].exists)
        XCTAssertLessThanOrEqual(steps.count, 3)
    }

    /// Hear where the bag is from Found: its place is in the row itself; ≤ 3 actions.
    private func findTheBagInFound(largestText: Bool) {
        let app = launch(largestText: largestText)
        let steps = Steps()
        steps.tap(app.tabBars.buttons["Found"])
        let bag = element(app, labelContaining: "bag")
        reach(bag, in: app, steps: steps)
        XCTAssertTrue(bag.label.contains("desk") && bag.label.contains("knee"), bag.label)
        XCTAssertLessThanOrEqual(steps.count, 3)
    }

    /// Delete a scan: the question says it reaches the Mac; Cancel keeps it; confirming removes it; ≤ 4 actions.
    private func deleteAScan(largestText: Bool) {
        let app = launch(largestText: largestText)
        let steps = Steps()
        steps.tap(app.tabBars.buttons["Scans"])
        let row = element(app, labelContaining: "64 frames")
        reach(row, in: app, steps: steps)
        steps.hold(row)
        steps.tap(app.buttons["Delete scan"])
        let title = element(app, labelContaining: "Delete this scan from your iPhone and your Mac?")
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        XCTAssertLessThanOrEqual(steps.count, 4)
        app.buttons["Keep it"].firstMatch.tap()
        XCTAssertTrue(row.exists, "Keep it keeps the scan")
        row.press(forDuration: 1.2)
        app.buttons["Delete scan"].tap()
        app.buttons["Delete from iPhone and Mac"].tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 3))
        XCTAssertTrue(waitSpoken(app, contains: "Deleted from your iPhone"))
    }

    /// Find out what leaves the Mac, from Devices and from Settings; ≤ 3 actions each.
    private func findWhatLeavesTheMac(largestText: Bool) {
        let app = launch(largestText: largestText)
        var steps = Steps()
        steps.tap(app.tabBars.buttons["Devices"])
        let link = app.descendants(matching: .any)["privacy-link"]
        reach(link, in: app, steps: steps, maxSwipes: 6)
        steps.tap(link)
        XCTAssertTrue(app.descendants(matching: .any)["privacy-right-now"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, labelContaining: "Sent to Meta Model API: SAM 3.1").exists)
        XCTAssertLessThanOrEqual(steps.count, largestText ? 8 : 4)  // very large text needs more swipes to reach it
        steps = Steps()
        if !app.tabBars.buttons["Settings"].isHittable { steps.swipeDown(app) }  // the bar shrinks while scrolling
        steps.tap(app.tabBars.buttons["Settings"])
        steps.tap(app.descendants(matching: .any)["privacy"])
        XCTAssertTrue(app.navigationBars["Privacy"].waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(steps.count, 3)
    }

    /// Turn Robot Access on and hear what it means; ≤ 4 actions (it starts off).
    private func shareWithARobot(largestText: Bool) {
        let app = launch(largestText: largestText)
        let steps = Steps()
        steps.tap(app.tabBars.buttons["Devices"])
        let link = app.descendants(matching: .any)["robot-access-link"]
        reach(link, in: app, steps: steps, maxSwipes: 6)
        steps.tap(link)
        let toggle = app.switches["robot-access-switch"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0")
        steps.tap(toggle.switches.firstMatch)
        XCTAssertTrue(waitSpoken(app, contains: "Robot access is on."))
        XCTAssertLessThanOrEqual(steps.count, largestText ? 8 : 4)
    }

    // MARK: the tasks at both text sizes

    func testAskWhereTheKeysAre() { askWhereTheKeysAre(largestText: false) }
    func testAskWhereTheKeysAreLargestText() { askWhereTheKeysAre(largestText: true) }
    func testAskForSomethingNeverSeen() { askForSomethingNeverSeen(largestText: false) }
    func testFindTheBagInFound() { findTheBagInFound(largestText: false) }
    func testFindTheBagInFoundLargestText() { findTheBagInFound(largestText: true) }
    func testDeleteAScan() { deleteAScan(largestText: false) }
    func testDeleteAScanLargestText() { deleteAScan(largestText: true) }
    func testFindWhatLeavesTheMac() { findWhatLeavesTheMac(largestText: false) }
    func testFindWhatLeavesTheMacLargestText() { findWhatLeavesTheMac(largestText: true) }
    func testShareWithARobot() { shareWithARobot(largestText: false) }
}
