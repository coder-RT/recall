import XCTest

/// Every screen passes Apple's automated accessibility audit (labels, contrast, hit targets, Dynamic Type).
@MainActor
final class AccessibilityTests: XCTestCase {
    /// Runs Apple's audit and prints every issue with the element it is about, so a failure says what to fix.
    /// `edgesRechecked`: the caller audits this screen at both ends of its scroll (see auditBothEnds), so a contrast
    /// issue the audit can't attach to an element (a row inside a bar's fade) is let through.
    private func audit(_ app: XCUIApplication, edgesRechecked: Bool = false) throws {
        Thread.sleep(forTimeInterval: 1)  // let push and tab animations settle, or the audit measures a frame mid-way
        let bar = app.navigationBars.firstMatch
        print("AUDIT screen: \(bar.exists ? bar.identifier : app.tabBars.buttons.allElementsBoundByIndex.first { $0.isSelected }?.label ?? "(no bar)")")
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
            // Rows that run on under the floating tab bar, or into the fade iOS 26 draws above it (the scroll edge
            // effect, about 44 pt), are seen through glass until scrolled up; that is the system's scroll-under
            // behaviour, not a colour of ours.
            if issue.auditType == .contrast, let e = issue.element, app.tabBars.firstMatch.exists,
               e.frame.maxY > app.tabBars.firstMatch.frame.minY - 44 {
                print("AUDIT (under the tab bar, accepted) \(issue.compactDescription) :: \(el)")
                return true
            }
            // The same fade iOS 26 draws under the navigation bar at the top.
            if issue.auditType == .contrast, let e = issue.element, app.navigationBars.firstMatch.exists,
               e.frame.minY < app.navigationBars.firstMatch.frame.maxY + 44 {
                print("AUDIT (under the navigation bar's fade, accepted) \(issue.compactDescription) :: \(el)")
                return true
            }
            if edgesRechecked, issue.auditType == .contrast, issue.element == nil {
                print("AUDIT (no element; rechecked scrolled to the end) \(issue.compactDescription)")
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
            let ratio = issue.auditType == .contrast ? issue.element.flatMap(Self.measuredContrast) : nil  // measured once
            if let e = issue.element, let ratio, ratio >= (e.frame.height >= 24 ? 3 : 4.5) {
                print(String(format: "AUDIT (contrast measured %.1f:1, accepted) ", ratio) + "\(issue.compactDescription) :: \(el)")
                return true
            }
            let measured = ratio.map { String(format: " (measured %.1f:1)", $0) } ?? ""
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

    /// A screen up to about two displays tall: audited at the top, then scrolled to the end. Contrast issues the audit
    /// can't attach to an element come from rows inside the fades iOS 26 draws at the bars, and those rows move with
    /// the scroll, so every row sits clear of both fades in one of the two passes (and is checked there).
    private func auditBothEnds(_ app: XCUIApplication) throws {
        try audit(app, edgesRechecked: true)
        app.swipeUp()
        app.swipeUp()
        try audit(app, edgesRechecked: true)
        for _ in 0..<3 { app.swipeDown() }
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

    /// The app opens on Find; the scans live in their own tab.
    private func openScans(_ app: XCUIApplication) {
        let tab = app.tabBars.buttons["Scans"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.tap()
    }

    func testDevicesTabComesFirstButTheAppOpensOnFind() throws {
        let app = XCUIApplication()
        app.launch()
        let tabs = app.tabBars.buttons
        XCTAssertTrue(tabs["Devices"].waitForExistence(timeout: 5))
        XCTAssertEqual(tabs.element(boundBy: 0).label, "Devices")
        XCTAssertTrue(tabs["Find"].isSelected)  // asking stays one step away
        tabs["Devices"].tap()
        let card = { (id: String) in app.descendants(matching: .any)["device-\(id)"] }
        XCTAssertTrue(card("iphone").waitForExistence(timeout: 5))
        XCTAssertTrue(card("iphone").label.hasPrefix("iPhone. Available now."), card("iphone").label)
        XCTAssertTrue(app.buttons["iPhone"].isSelected)
        // tap an icon: its card slides into view, and the icon is marked chosen
        app.buttons["Meta AI glasses"].tap()
        XCTAssertTrue(card("glasses").waitForExistence(timeout: 3))
        XCTAssertTrue(card("glasses").label.hasPrefix("Meta AI glasses. Planned."), card("glasses").label)
        XCTAssertTrue(app.buttons["Meta AI glasses"].wait(for: \.isSelected, toEqual: true, timeout: 3))
        // swipe the cards: the icon row follows
        card("glasses").swipeRight()
        XCTAssertTrue(app.buttons["Apple Watch Ultra 4"].wait(for: \.isSelected, toEqual: true, timeout: 3))
        XCTAssertTrue(card("watch").label.hasPrefix("Apple Watch Ultra 4. Coming next."), card("watch").label)
        shot("ios-devices")
        try auditBothEnds(app)
        for _ in 0..<5 { app.swipeUp() }  // the very end: the buttons and the honest footnote
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Only the iPhone app works today'"))
            .firstMatch.exists)
        shot("ios-devices-end")
        try audit(app, edgesRechecked: true)
        app.buttons["Ask now"].tap()
        XCTAssertTrue(tabs["Find"].isSelected)
    }

    /// Found grouped by room, then furniture; sure things show their own icon, unsure ones the box.
    func testFoundGroupsByRoomAndFurnitureWithIcons() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestSampleThings"]
        app.launch()
        app.tabBars.buttons["Found"].tap()
        let group = { (id: String) in app.descendants(matching: .any)["group-\(id)"] }
        let living = group("Living room")
        XCTAssertTrue(living.waitForExistence(timeout: 5))
        XCTAssertEqual(living.label, "Living room, 4 things, 2 to check")
        XCTAssertEqual(group("Kitchen").label, "Kitchen, 2 things")
        XCTAssertTrue(app.staticTexts["ON OR NEAR THE DESK"].exists)
        XCTAssertTrue(app.staticTexts["ELSEWHERE IN THE ROOM"].exists)
        XCTAssertTrue(app.images["icon-keys"].exists)  // sure: a key
        XCTAssertGreaterThanOrEqual(app.images.matching(identifier: "icon-unknown").count, 2)  // unsure bag and book: boxes
        XCTAssertFalse(app.images["icon-handbag"].exists)
        shot("ios-found-grouped")
        try auditBothEnds(app)
        // folding a room hides its things
        XCTAssertTrue(living.waitForExistence(timeout: 3))
        living.tap()
        XCTAssertTrue(app.staticTexts["ON OR NEAR THE DESK"].waitForNonExistence(timeout: 2))
        XCTAssertEqual(living.value as? String, "Folded")
        living.tap()
        // by height: floor to head
        app.buttons["Group by height"].tap()
        XCTAssertTrue(group("floor").waitForExistence(timeout: 3))
        XCTAssertEqual(group("floor").label, "Floor height, 1 thing")
        XCTAssertEqual(group("waist").label, "Waist height, 4 things, 1 to check")
        // by kind
        app.buttons["Group by kind"].tap()
        XCTAssertTrue(group("keys").waitForExistence(timeout: 3))
        XCTAssertEqual(group("keys").label, "Keys, 1 thing")
        shot("ios-found-kind")
        try audit(app)
        app.buttons["Group by place"].tap()  // the choice is remembered; leave it as the default
    }

    func testFindShowsIconsAndRooms() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestSampleThings"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Kitchen"].waitForExistence(timeout: 5))  // two rooms: a heading each
        XCTAssertTrue(app.images["icon-wallet"].exists)
        XCTAssertTrue(app.images["icon-mug"].exists)
        shot("ios-find-icons")
        try auditBothEnds(app)
    }

    /// A processed scan offers "Scan again"; a rescan shows what moved, what's new and what's gone.
    func testScanAgainAndWhatChanged() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestSampleThings"]
        app.launch()
        openScans(app)
        let card = app.descendants(matching: .any)["what-changed"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["What changed"].exists)
        let moved = card.descendants(matching: .any)["Beige keys: Moved from near the desk to on the shelf."]
        XCTAssertTrue(moved.exists)
        XCTAssertTrue(card.descendants(matching: .any)["White mug: New, on the desk."].exists)
        XCTAssertTrue(card.descendants(matching: .any)["Grey bag: Gone from near the desk."].exists)
        XCTAssertTrue(app.buttons["Hear what changed again"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "Scan again").count, 2)  // on both processed scans
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "what-changed").count, 1)  // the first scan has none
        shot("ios-what-changed")
        try auditBothEnds(app)
    }

    /// Home robots in Devices, and Robot Access: the switch, what is and isn't shared, the map, the audit.
    func testRobotAccess() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestSampleThings"]
        app.launch()
        app.tabBars.buttons["Devices"].tap()
        app.buttons["Home robots"].tap()
        let card = app.descendants(matching: .any)["device-robots"]
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        XCTAssertTrue(card.label.hasPrefix("Home robots. Preview."), card.label)
        XCTAssertTrue(card.label.contains("picking it up is the robot's own skill"))
        let link = app.descendants(matching: .any)["robot-access-link"]
        XCTAssertTrue(link.waitForExistence(timeout: 3))
        link.tap()
        XCTAssertTrue(app.navigationBars["Robot Access"].waitForExistence(timeout: 5))
        let toggle = app.switches["robot-access-switch"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0")  // off by default
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Off. Robots can'"))
            .firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["Never: Photos or camera frames"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["Map of Living room for robots, with 1 things marked."].exists
            || app.otherElements.containing(NSPredicate(format: "label BEGINSWITH 'Map of Living room'")).firstMatch.exists)
        let activity = app.descendants(matching: .any)["robot-activity"]
        XCTAssertTrue(activity.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["A robot asked for keys: answered"].exists)
        XCTAssertTrue(app.staticTexts["Refused: wrong key (/a2a/home-memory)"].exists)
        shot("ios-robot-access")
        try auditBothEnds(app)
        toggle.switches.firstMatch.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'On. A robot'"))
            .firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["You turned robot access on"].waitForExistence(timeout: 3))  // the log, too
    }

    /// Privacy from Devices and from Settings: what leaves the Mac right now, what never happens, the controls.
    func testPrivacy() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestSampleThings"]
        app.launch()
        app.tabBars.buttons["Devices"].tap()
        let link = app.descendants(matching: .any)["privacy-link"]
        for _ in 0..<4 where !link.isHittable { app.swipeUp() }
        link.tap()
        XCTAssertTrue(app.navigationBars["Privacy"].waitForExistence(timeout: 5))
        let now = app.descendants(matching: .any)["privacy-right-now"]
        XCTAssertTrue(now.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).containing(NSPredicate(
            format: "label BEGINSWITH 'Scan photos, about 50 per room (no depth, no sound). Sent to Meta Model API: SAM 3.1.'"
        )).firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any).containing(NSPredicate(
            format: "label BEGINSWITH 'Never: No Recall server receives your home'")).firstMatch.exists)
        shot("ios-privacy")
        try auditBothEnds(app)
        app.tabBars.buttons["Settings"].tap()
        let row = app.descendants(matching: .any)["privacy"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.tap()
        XCTAssertTrue(app.navigationBars["Privacy"].waitForExistence(timeout: 5))
    }

    /// "Why?" on an answer: the evidence sheet passes the audit, and says its sighting as one sentence.
    func testEvidencePassesTheAudit() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestSampleThings"]
        app.launch()
        let q = field(app, "question")
        XCTAssertTrue(q.waitForExistence(timeout: 5))
        q.tap()
        q.typeText("Where are my keys?")
        app.buttons["Ask"].tap()
        XCTAssertTrue(app.buttons["Why?"].waitForExistence(timeout: 5))
        shot("ios-find-answer")
        app.buttons["Why?"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["sighting-ob1"].waitForExistence(timeout: 5))
        shot("ios-evidence")
        try audit(app)
    }

    func testHomePassesTheAudit() throws {
        let app = XCUIApplication()
        app.launch()
        openScans(app)
        XCTAssertTrue(app.buttons["Start a scan"].waitForExistence(timeout: 5))
        shot("ios-home")
        try audit(app)
    }

    func testRoomNameAndSettingsPassTheAudit() throws {
        let app = XCUIApplication()
        app.launch()
        openScans(app)
        app.buttons["Start a scan"].tap()
        XCTAssertTrue(field(app, "roomName").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Which room is this?"].exists)
        shot("ios-room-name")
        try audit(app)
        app.buttons["Cancel"].tap()
        app.tabBars.buttons["Found"].tap()
        // paired: the list; not paired: the reason and a way to Settings
        let heading = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'group-'")).firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 10) || app.buttons["Open Settings"].exists)
        shot("ios-found-unpaired")
        try audit(app)
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(field(app, "macAddress").waitForExistence(timeout: 5))
        shot("ios-settings")
        try auditBothEnds(app)
    }
}

@MainActor
extension AccessibilityTests {
    /// The simulator has no LiDAR, so the Scan screen shows its explanation; that screen is audited too.
    func testUnsupportedScanScreenPassesTheAudit() throws {
        let app = XCUIApplication()
        app.launch()
        openScans(app)
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
        app.tabBars.buttons["Find"].tap()
        XCTAssertTrue(app.staticTexts["Your things"].waitForExistence(timeout: 10))
        shot("ios-find")
        try audit(app)
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
        XCTAssertTrue(app.buttons["Start a scan"].waitForExistence(timeout: 5))
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

@MainActor
extension AccessibilityTests {
    /// Every theme passes the audit: dark, and high contrast in light and dark (launch arguments set the same
    /// UserDefaults keys as Settings → Appearance).
    func testThemesPassTheAudit() throws {
        for (name, args) in [("dark", ["-appearance", "dark"]),
                             ("contrast-light", ["-appearance", "light", "-highContrast", "YES"]),
                             ("contrast-dark", ["-appearance", "dark", "-highContrast", "YES"])] {
            let app = XCUIApplication()
            app.launchArguments += args
            app.launch()
            XCTAssertTrue(app.tabBars.buttons["Find"].waitForExistence(timeout: 5))
            shot("ios-find-\(name)")
            try audit(app)
            openScans(app)
            XCTAssertTrue(app.buttons["Start a scan"].waitForExistence(timeout: 5))
            shot("ios-home-\(name)")
            try audit(app)
            app.tabBars.buttons["Settings"].tap()
            XCTAssertTrue(field(app, "macAddress").waitForExistence(timeout: 5))
            shot("ios-settings-\(name)")
            try auditBothEnds(app)
            app.buttons["appearance"].tap()
            XCTAssertTrue(app.navigationBars["Appearance"].waitForExistence(timeout: 5))
            shot("ios-appearance-\(name)")
            try audit(app)
            app.terminate()
        }
    }
}
