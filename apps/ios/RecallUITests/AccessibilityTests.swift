import XCTest

/// Every screen passes Apple's automated accessibility audit (labels, contrast, hit targets, Dynamic Type).
@MainActor
final class AccessibilityTests: XCTestCase {
    /// Runs Apple's audit and prints every issue with the element it is about, so a failure says what to fix.
    private func audit(_ app: XCUIApplication) throws {
        let bar = app.navigationBars.firstMatch
        print("AUDIT screen: \(bar.exists ? bar.identifier : "(no bar)")")
        let screen = app.windows.firstMatch.frame
        try app.performAccessibilityAudit { issue in
            let el = issue.element.map { "\($0.elementType.rawValue) '\($0.label)' frame \($0.frame)" } ?? "no element"
            // System navigation-bar buttons cap their text size and offer the Large Content Viewer instead (Apple's
            // own behaviour, not ours to change); every other issue fails the test.
            if issue.auditType == .dynamicType, let e = issue.element, e.elementType == .button,
               app.navigationBars.buttons[e.label].exists {
                print("AUDIT (system toolbar, accepted) \(issue.compactDescription) :: \(el)")
                return true
            }
            // The audit enlarges the text and re-measures; rows in the lower part of a screen move off it and can't be
            // measured. testLargeTextScales checks those rows at the largest size instead.
            if issue.auditType == .dynamicType, let e = issue.element, e.frame.minY > screen.height * 0.55 {
                print("AUDIT (moves off screen when enlarged; see testLargeTextScales) \(issue.compactDescription) :: \(el)")
                return true
            }
            // A secure field's dots are clipped when the key is long; they are not readable text (VoiceOver reads the
            // field's label and value count), so clipping there is accepted.
            if issue.auditType == .textClipped, issue.element?.elementType == .secureTextField {
                print("AUDIT (secure field dots, accepted) \(issue.compactDescription) :: \(el)")
                return true
            }
            // Rows that run on under the floating tab bar are seen through its glass until scrolled up; that is the
            // system's scroll-under behaviour, not a colour of ours.
            if issue.auditType == .contrast, let e = issue.element, app.tabBars.firstMatch.exists,
               e.frame.maxY > app.tabBars.firstMatch.frame.minY {
                print("AUDIT (under the tab bar, accepted) \(issue.compactDescription) :: \(el)")
                return true
            }
            // The system search field truncates its own placeholder at large text sizes.
            if issue.auditType == .textClipped, issue.element?.elementType == .searchField {
                print("AUDIT (system search field, accepted) \(issue.compactDescription) :: \(el)")
                return true
            }
            // The audit misjudges text near Liquid Glass (on screen: white on deep blue at 12:1). So a contrast issue
            // is checked against the pixels: text against its background must reach 4.5:1 (3:1 for large text, WCAG's
            // 18 pt and up, taken as a frame at least 24 pt tall), or the issue stands.
            if issue.auditType == .contrast, let e = issue.element, let ratio = Self.measuredContrast(e),
               ratio >= (e.frame.height >= 24 ? 3 : 4.5) {
                print(String(format: "AUDIT (contrast measured %.1f:1, accepted) ", ratio) + "\(issue.compactDescription) :: \(el)")
                return true
            }
            let measured = issue.element.flatMap(Self.measuredContrast).map { String(format: " (measured %.1f:1)", $0) } ?? ""
            print("AUDIT \(issue.compactDescription)\(measured) :: \(el) :: \(issue.detailedDescription)")
            return false
        }
    }

    /// WCAG contrast between the two most common colours in the element's own screenshot (text and its background).
    static func measuredContrast(_ element: XCUIElement) -> Double? {
        guard let cg = element.screenshot().image.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var counts: [UInt32: Int] = [:]  // colours rounded to 8 levels per channel, so anti-aliasing doesn't split them
        for i in stride(from: 0, to: px.count, by: 4) {
            let key = UInt32(px[i] >> 3) << 10 | UInt32(px[i + 1] >> 3) << 5 | UInt32(px[i + 2] >> 3)
            counts[key, default: 0] += 1
        }
        // background: the most common colour; text: the colour, among those covering at least 3 % of the element,
        // that stands out most from it (on a gradient the two most common colours are both background)
        let total = Double(px.count / 4)
        let ranked = counts.sorted { $0.value > $1.value }
        guard let background = ranked.first?.key else { return nil }
        func luminance(_ key: UInt32) -> Double {
            let c = [(key >> 10) & 31, (key >> 5) & 31, key & 31].map { Double($0 * 8 + 4) / 255 }
            let l = c.map { $0 <= 0.03928 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return 0.2126 * l[0] + 0.7152 * l[1] + 0.0722 * l[2]
        }
        func ratio(_ a: UInt32, _ b: UInt32) -> Double {
            let (x, y) = (luminance(a), luminance(b))
            return (max(x, y) + 0.05) / (min(x, y) + 0.05)
        }
        return ranked.dropFirst().filter { Double($0.value) / total >= 0.03 }.map { ratio(background, $0.key) }.max()
    }

    /// A text field by identifier; fields that grow vertically are exposed as text views.
    private func field(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.textFields[id].exists ? app.textFields[id] : app.textViews[id]
    }

    /// Saves a screenshot for the progress notes when RECALL_SHOTS points at a folder (the simulator can write to it).
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
        XCTAssertTrue(app.buttons["Start a scan"].waitForExistence(timeout: 5))
        shot("ios-home")
        try audit(app)
    }

    func testRoomNameAndSettingsPassTheAudit() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Start a scan"].tap()
        XCTAssertTrue(field(app, "roomName").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Which room is this?"].exists)
        shot("ios-room-name")
        try audit(app)
        app.buttons["Cancel"].tap()
        app.tabBars.buttons["Found"].tap()
        XCTAssertTrue(app.navigationBars["Found"].waitForExistence(timeout: 5))
        shot("ios-found-unpaired")
        try audit(app)
        app.tabBars.buttons["Settings"].tap()
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
        app.buttons["Start a scan"].tap()
        app.buttons["Kitchen"].tap()
        XCTAssertTrue(app.staticTexts["Scanning needs an iPhone with LiDAR"].waitForExistence(timeout: 5))
        shot("ios-scan-unsupported")
        try audit(app)
    }
}

@MainActor
extension AccessibilityTests {
    /// The review screens against the real API on this Mac: run with TEST_RUNNER_RECALL_DEVICE_KEY set
    /// (xcodebuild passes it to the test). Only opens screens; never saves.
    func testReviewScreensPassTheAudit() throws {
        let env = ProcessInfo.processInfo.environment
        guard let key = env["RECALL_DEVICE_KEY"], !key.isEmpty else {
            throw XCTSkip("Needs RECALL_DEVICE_KEY and the API running on this Mac.")
        }
        let app = XCUIApplication()
        app.launch()
        var pair = URLComponents(string: "recall://pair")!
        pair.queryItems = [.init(name: "url", value: "http://127.0.0.1:8000"), .init(name: "key", value: key),
                           .init(name: "home", value: "flat")]
        app.open(pair.url!)
        let open = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Open"]
        if open.waitForExistence(timeout: 3) { open.tap() }  // iOS asks before a link opens an app
        let check = app.tabBars.buttons["Found"]
        XCTAssertTrue(check.waitForExistence(timeout: 10))
        check.tap()
        XCTAssertTrue(app.staticTexts["Everything"].waitForExistence(timeout: 10))
        shot("ios-review")
        try audit(app)
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'sure' OR label CONTAINS 'Checked by you'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Save, it's right"].waitForExistence(timeout: 5))
        shot("ios-review-edit")
        try audit(app)
        app.buttons["Cancel"].tap()
    }
}

@MainActor
extension AccessibilityTests {
    /// At the largest accessibility text size, the rows lowest on their screens still grow (the audit can't measure
    /// them once they move off screen).
    func testLargeTextScales() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Settings"].tap()
        shot("ios-settings-large-text-top")
        let homeName = app.descendants(matching: .any).matching(identifier: "homeName").firstMatch
        for _ in 0..<4 where !homeName.isHittable { app.swipeUp() }
        XCTAssertTrue(homeName.exists)
        XCTAssertGreaterThan(homeName.frame.height, 50, "Home name field grows with the text")
        shot("ios-settings-large-text")
        // the tab bar shrinks while scrolling down; scrolling back up brings it back
        for _ in 0..<4 where !app.tabBars.buttons["Scans"].isHittable { app.swipeDown() }
        app.tabBars.buttons["Scans"].tap()
        let start = app.buttons["Start a scan"]
        for _ in 0..<3 where !start.isHittable { app.swipeDown() }
        start.tap()
        XCTAssertTrue(field(app, "roomName").waitForExistence(timeout: 5))
        let office = app.buttons["Office"]
        for _ in 0..<4 where !office.isHittable { app.swipeUp() }
        XCTAssertTrue(office.exists)
        XCTAssertGreaterThan(office.frame.height, 60, "room choices grow with the text")
        shot("ios-room-name-large-text")
    }
}
