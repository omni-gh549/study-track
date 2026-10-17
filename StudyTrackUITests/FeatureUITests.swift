import XCTest

/// End-to-end tests for every user-facing feature, driven through the real UI on the simulator.
final class FeatureUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(reset: Bool = true, seed: Bool = true, disk: Bool = false,
                        arguments: [String] = []) {
        var env: [String: String] = [:]
        if !disk { env["UITEST_INMEMORY"] = "1" }
        if reset { env["UITEST_RESET"] = "1" }
        if seed { env["UITEST_SEED"] = "1" }
        app.launchEnvironment = env
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 10), app.debugDescription)
    }

    private func tab(_ name: String) {
        app.tabBars.buttons[name].tap()
    }

    private func row(containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func tapSave() {
        let save = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Save'")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
    }

    private func type(into placeholder: String, _ text: String) {
        let ids = placeholder == "What did you cover?" ? ["session.notes", placeholder] : [placeholder]
        var field = app.textFields[ids[0]]
        for id in ids {
            for candidate in [app.textFields[id], app.textViews[id]] where candidate.waitForExistence(timeout: 2) {
                field = candidate
                break
            }
        }
        XCTAssertTrue(field.waitForExistence(timeout: 5), "No field '\(placeholder)'")
        field.tap()
        field.typeText(text)
    }

    // MARK: Sessions

    func testAddSessionManually() throws {
        launch(seed: false)
        app.buttons["Science"].tap()
        app.buttons["Get started"].tap()
        XCTAssertTrue(app.buttons["Add Session"].waitForExistence(timeout: 5))
        app.buttons["Add Session"].tap()
        XCTAssertTrue(app.navigationBars["New Session"].waitForExistence(timeout: 5))
        tapSave()
        XCTAssertTrue(app.staticTexts["Session saved"].waitForExistence(timeout: 5))
        tab("History")
        XCTAssertTrue(app.staticTexts["Science"].waitForExistence(timeout: 5))
    }

    func testEditSessionPersists() throws {
        launch()
        tab("History")
        let target = row(containing: "Integration by parts")
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        target.tap()
        XCTAssertTrue(app.navigationBars["Edit Session"].waitForExistence(timeout: 5))
        type(into: "What did you cover?", " EDITED")
        tapSave()
        XCTAssertTrue(row(containing: "EDITED").waitForExistence(timeout: 5))
    }

    func testDeleteSessionNeedsConfirmationAndCancelKeepsIt() throws {
        launch()
        tab("History")
        let target = row(containing: "Integration by parts")
        XCTAssertTrue(target.waitForExistence(timeout: 5))

        target.swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["Delete session"].waitForExistence(timeout: 5), "Deleting must ask first")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(target.exists, "Cancel must keep the session")

        target.swipeLeft()
        app.buttons["Delete"].tap()
        app.buttons["Delete session"].tap()
        XCTAssertTrue(waitForDisappearance(row(containing: "Integration by parts")))
    }

    func testSearchFiltersHistory() throws {
        launch()
        tab("History")
        XCTAssertTrue(row(containing: "Integration by parts").waitForExistence(timeout: 5))
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Middlemarch")
        XCTAssertTrue(row(containing: "Middlemarch").waitForExistence(timeout: 5))
        XCTAssertFalse(row(containing: "Integration by parts").exists)
        search.typeText("zzzz")
        XCTAssertTrue(app.staticTexts["No Results for “Middlemarchzzzz”"].waitForExistence(timeout: 5)
                      || app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'No Results'")).firstMatch.exists)
    }

    // MARK: Goals

    func testGoalAddEditDelete() throws {
        launch()
        tab("Goals")
        app.buttons["Add Goal"].tap()
        type(into: "Goal name", "Read five chapters")
        tapSave()
        let created = row(containing: "Read five chapters")
        XCTAssertTrue(created.waitForExistence(timeout: 5))

        created.tap()
        XCTAssertTrue(app.navigationBars["Edit Goal"].waitForExistence(timeout: 5))
        type(into: "Goal name", " v2")
        tapSave()
        XCTAssertTrue(row(containing: "Read five chapters v2").waitForExistence(timeout: 5))

        row(containing: "Read five chapters v2").swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Delete “'")).firstMatch.waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Delete “'")).firstMatch.tap()
        XCTAssertTrue(waitForDisappearance(row(containing: "Read five chapters v2")))
    }

    // MARK: Subjects

    func testSubjectsAddDuplicateBlockedAndSessionsKeptOnDelete() throws {
        launch()
        tab("History")
        app.buttons["Subjects"].tap()
        XCTAssertTrue(app.navigationBars["Subjects"].waitForExistence(timeout: 5))

        app.buttons["Add Subject"].tap()
        type(into: "Subject name", "Chemistry")
        tapSave()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Chemistry'")).firstMatch.waitForExistence(timeout: 5))

        // Duplicate (case-insensitive) is refused.
        app.buttons["Add Subject"].tap()
        type(into: "Subject name", "chemistry")
        XCTAssertTrue(app.staticTexts["You already have a subject with this name."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Save'")).firstMatch.isEnabled)
        app.buttons["Cancel"].tap()

        // Delete a subject that has sessions: asks first and says the sessions are kept.
        let maths = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Mathematics'")).firstMatch
        XCTAssertTrue(maths.waitForExistence(timeout: 5))
        maths.swipeLeft()
        app.buttons["Delete"].tap()
        let confirm = app.buttons["Delete Mathematics"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(waitForDisappearance(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Mathematics'")).firstMatch))

        app.buttons["Done"].tap()
        // The sessions are still in History, just without a subject.
        XCTAssertTrue(row(containing: "Integration by parts").waitForExistence(timeout: 5))
    }

    // MARK: Timer ↔ Today

    func testTimerBannerOnTodayOpensTimer() throws {
        launch()
        tab("Timer")
        app.buttons["Start"].tap()
        tab("Today")
        let banner = app.buttons["dashboard.timerBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        banner.tap()
        XCTAssertTrue(app.staticTexts["timer.display"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Pause"].exists)
    }

    // MARK: Profile / settings

    func testProfileBadgesInsightsAndSettings() throws {
        launch()
        tab("Profile")

        // Settings (nav bar button, always reachable)
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Restore from backup…"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()

        // Insights is further down the page.
        let insights = app.buttons["Insights"]
        reveal(insights)
        insights.tap()
        XCTAssertTrue(app.staticTexts["Time by subject"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()

        // Badges are below that.
        let badge = app.buttons["First Steps"]
        reveal(badge)
        badge.tap()
        XCTAssertTrue(app.staticTexts["Unlocked"].waitForExistence(timeout: 5))
    }

    func testEraseAllThenLoadSampleData() throws {
        launch()
        tab("Profile")
        app.buttons["Settings"].tap()
        let erase = app.buttons["Erase all data"]
        XCTAssertTrue(erase.waitForExistence(timeout: 5))
        erase.tap()
        XCTAssertTrue(app.buttons["Erase everything"].waitForExistence(timeout: 5), "Erase must ask first")
        app.buttons["Erase everything"].tap()

        let load = app.buttons["Load sample data"]
        XCTAssertTrue(load.waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        tab("History")
        XCTAssertTrue(app.staticTexts["No sessions yet"].waitForExistence(timeout: 5))

        tab("Profile")
        app.buttons["Settings"].tap()
        app.buttons["Load sample data"].tap()
        app.buttons["Done"].tap()
        tab("History")
        XCTAssertTrue(row(containing: "Integration by parts").waitForExistence(timeout: 5))
    }

    // MARK: Real on-disk persistence across a kill

    func testSessionsAndSubjectsSurviveForceQuit() throws {
        launch(seed: false, disk: true)
        app.buttons["Mathematics"].tap()
        app.buttons["Get started"].tap()
        app.buttons["Add Session"].tap()
        tapSave()
        XCTAssertTrue(app.staticTexts["Session saved"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchEnvironment = ["UITEST_SEED": ""]   // same on-disk store, no reset, no seed
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["History"].waitForExistence(timeout: 10))
        tab("History")
        XCTAssertTrue(app.staticTexts["Mathematics"].waitForExistence(timeout: 5), "Session lost after force-quit")
        tab("Profile")
        reveal(app.buttons["First Steps"])
    }

    // MARK: Dark mode

    func testDarkModeScreens() throws {
        launch(arguments: ["-AppleInterfaceStyle", "Dark"])
        for name in ["Today", "Timer", "Goals", "History", "Profile"] {
            tab(name)
            let shot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = "dark-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
            if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
                try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("dark-\(name).png"))
            }
        }
    }

    // MARK: helpers

    private func reveal(_ element: XCUIElement, maxSwipes: Int = 8) {
        _ = element.waitForExistence(timeout: 5)
        var swipes = 0
        while !element.isHittable && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(element.isHittable, "Could not scroll to \(element)")
    }

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }
}
