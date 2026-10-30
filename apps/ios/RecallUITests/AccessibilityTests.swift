import XCTest

/// Every screen passes Apple's automated accessibility audit (labels, contrast, hit targets, Dynamic Type).
@MainActor
final class AccessibilityTests: XCTestCase {
    /// Runs Apple's audit and prints every issue with the element it is about, so a failure says what to fix.
    private func audit(_ app: XCUIApplication) throws {
        try app.performAccessibilityAudit { issue in
            let el = issue.element.map { "\($0.elementType.rawValue) '\($0.label)' frame \($0.frame)" } ?? "no element"
            // System navigation-bar buttons cap their text size and offer the Large Content Viewer instead (Apple's
            // own behaviour, not ours to change); every other issue fails the test.
            if issue.auditType == .dynamicType, let e = issue.element, e.elementType == .button,
               app.navigationBars.buttons[e.label].exists {
                print("AUDIT (system toolbar, accepted) \(issue.compactDescription) :: \(el)")
                return true
            }
            print("AUDIT \(issue.compactDescription) :: \(el)")
            return false
        }
    }

    /// A text field by identifier; fields that grow vertically are exposed as text views.
    private func field(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.textFields[id].exists ? app.textFields[id] : app.textViews[id]
    }

    /// Saves a screenshot for docs/progress/ when RECALL_SHOTS points at a folder (the simulator can write to it).
    private func shot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["RECALL_SHOTS"] {
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    func testHomePassesTheAudit() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Scan a room"].waitForExistence(timeout: 5))
        shot("ios-home")
        try audit(app)
    }

    func testRoomNameAndSettingsPassTheAudit() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Scan a room"].tap()
        XCTAssertTrue(field(app, "roomName").waitForExistence(timeout: 5))
        shot("ios-room-name")
        try audit(app)
        app.buttons["Cancel"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(field(app, "macAddress").waitForExistence(timeout: 5))
        shot("ios-settings")
        try audit(app)
    }
}

@MainActor
extension AccessibilityTests {
    /// The simulator has no LiDAR, so the Scan screen shows its explanation; that screen is audited too.
    func testUnsupportedScanScreenPassesTheAudit() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Scan a room"].tap()
        app.buttons["Kitchen"].tap()
        XCTAssertTrue(app.staticTexts["Scanning needs an iPhone with LiDAR"].waitForExistence(timeout: 5))
        shot("ios-scan-unsupported")
        try audit(app)
    }
}
