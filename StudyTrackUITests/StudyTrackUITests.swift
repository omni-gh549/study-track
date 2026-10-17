import XCTest

final class StudyTrackUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(reset: Bool = true, seed: Bool = false) {
        var env = ["UITEST_INMEMORY": "1"]
        if reset { env["UITEST_RESET"] = "1" }
        if seed { env["UITEST_SEED"] = "1" }
        app.launchEnvironment = env
        app.launch()
    }

    private func openTimer() {
        app.tabBars.buttons["Timer"].tap()
        XCTAssertTrue(app.staticTexts["timer.display"].waitForExistence(timeout: 5))
    }

    private var display: String { app.staticTexts["timer.display"].label }

    private func seconds(_ clock: String) -> Int {
        clock.split(separator: ":").compactMap { Int($0) }.reduce(0) { $0 * 60 + $1 }
    }

    private func snap(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    // The bug that was reported: pause, switch off, come back, timer reset.
    func testPausedTimerSurvivesTerminationAndRelaunch() throws {
        launch(seed: true)
        openTimer()
        app.buttons["Start"].tap()
        sleep(3)
        app.buttons["Pause"].tap()
        let paused = display
        XCTAssertGreaterThanOrEqual(seconds(paused), 3)

        app.terminate()
        sleep(2)
        launch(reset: false, seed: true)
        openTimer()
        XCTAssertEqual(display, paused, "Paused time must be identical after relaunch")
        XCTAssertTrue(app.buttons["Resume"].exists)
    }

    func testRunningTimerKeepsCountingWhileAppIsClosed() throws {
        launch(seed: true)
        openTimer()
        app.buttons["Start"].tap()
        sleep(2)
        app.terminate()
        sleep(4)
        launch(reset: false, seed: true)
        openTimer()
        XCTAssertGreaterThanOrEqual(seconds(display), 6)
        XCTAssertTrue(app.buttons["Pause"].exists)
    }

    func testResumeAfterRelaunchAddsToPausedTime() throws {
        launch(seed: true)
        openTimer()
        app.buttons["Start"].tap()
        sleep(2)
        app.buttons["Pause"].tap()
        let before = seconds(display)
        app.terminate()
        launch(reset: false, seed: true)
        openTimer()
        app.buttons["Resume"].tap()
        sleep(3)
        app.buttons["Pause"].tap()
        XCTAssertGreaterThanOrEqual(seconds(display), before + 3)
    }

    func testResetClearsTimer() throws {
        launch(seed: true)
        openTimer()
        app.buttons["Start"].tap()
        sleep(2)
        app.buttons["Reset"].tap()
        XCTAssertEqual(display, "00:00")
        XCTAssertTrue(app.buttons["Start"].exists)
    }

    func testOnboardingThenTimerSessionSavesAndAppearsInHistory() throws {
        launch()
        let chip = app.buttons["Mathematics"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        chip.tap()
        app.buttons["Get started"].tap()

        openTimer()
        app.buttons["Start"].tap()
        sleep(2)
        app.buttons["Finish"].tap()

        let save = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Save'")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(app.staticTexts["Session saved"].waitForExistence(timeout: 5))

        // Timer is cleared after a successful save.
        XCTAssertEqual(display, "00:00")

        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["Mathematics"].waitForExistence(timeout: 5))
    }

    func testCancelingSaveKeepsTimerPausedWithoutLosingTime() throws {
        launch(seed: true)
        openTimer()
        app.buttons["Start"].tap()
        sleep(2)
        app.buttons["Finish"].tap()
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(seconds(display), 2)
    }

    func testCaptureScreenshots() throws {
        launch(seed: true)
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 5))
        sleep(1)
        snap("1-today")
        app.tabBars.buttons["Timer"].tap()
        snap("2-timer")
        app.tabBars.buttons["Goals"].tap()
        snap("3-goals")
        app.tabBars.buttons["History"].tap()
        snap("4-history")
        app.tabBars.buttons["Profile"].tap()
        sleep(1)
        snap("5-profile")
        app.swipeUp()
        snap("6-profile-badges")
        app.tabBars.buttons["Today"].tap()
        app.buttons["Add Session"].tap()
        sleep(1)
        snap("7-new-session")
    }
}
