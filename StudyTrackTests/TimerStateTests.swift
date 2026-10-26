import XCTest
@testable import StudyTrack

final class TimerStateTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testPauseKeepsElapsedForever() {
        var s = TimerState()
        s.start(at: t0)
        XCTAssertTrue(s.isRunning)
        s.pause(at: t0.addingTimeInterval(900))
        XCTAssertFalse(s.isRunning)
        XCTAssertEqual(s.elapsed(at: t0.addingTimeInterval(900)), 900, accuracy: 0.001)
        // Hours later (phone off, long break) the paused time must be unchanged.
        XCTAssertEqual(s.elapsed(at: t0.addingTimeInterval(99_999)), 900, accuracy: 0.001)
    }

    func testResumeAddsToAccumulated() {
        var s = TimerState()
        s.start(at: t0)
        s.pause(at: t0.addingTimeInterval(600))
        s.start(at: t0.addingTimeInterval(1_200))
        XCTAssertEqual(s.elapsed(at: t0.addingTimeInterval(1_500)), 900, accuracy: 0.001)
        XCTAssertEqual(s.sessionStart, t0)
    }

    func testRunningKeepsCountingWhileAppIsDead() {
        var s = TimerState()
        s.start(at: t0)
        XCTAssertEqual(s.elapsed(at: t0.addingTimeInterval(3_600)), 3_600, accuracy: 0.001)
    }

    func testClockMovedBackwardsNeverNegative() {
        var s = TimerState()
        s.start(at: t0)
        XCTAssertGreaterThanOrEqual(s.elapsed(at: t0.addingTimeInterval(-500)), 0)
        s.pause(at: t0.addingTimeInterval(-500))
        XCTAssertGreaterThanOrEqual(s.accumulated, 0)
    }

    func testDoubleStartAndDoublePauseAreIgnored() {
        var s = TimerState()
        s.start(at: t0)
        s.start(at: t0.addingTimeInterval(100))
        XCTAssertEqual(s.runStart, t0)
        s.pause(at: t0.addingTimeInterval(200))
        s.pause(at: t0.addingTimeInterval(900))
        XCTAssertEqual(s.accumulated, 200, accuracy: 0.001)
    }

    func testResetKeepsSubjectOnly() {
        var s = TimerState(subjectName: "Physics")
        s.start(at: t0)
        s.pause(at: t0.addingTimeInterval(60))
        s.reset()
        XCTAssertFalse(s.hasProgress)
        XCTAssertNil(s.sessionStart)
        XCTAssertEqual(s.subjectName, "Physics")
    }

    func testPersistenceRoundTripAndOverwrite() {
        let original = TimerStore.url
        defer { TimerStore.url = original }
        TimerStore.url = FileManager.default.temporaryDirectory
            .appendingPathComponent("timer-test-\(UUID().uuidString)/state.json")

        XCTAssertEqual(TimerStore.load(), TimerState())

        var s = TimerState(subjectName: "Maths")
        s.start(at: t0)
        s.pause(at: t0.addingTimeInterval(900))
        TimerStore.save(s)
        XCTAssertEqual(TimerStore.load(), s)

        s.start(at: t0.addingTimeInterval(2_000))
        TimerStore.save(s)
        let loaded = TimerStore.load()
        XCTAssertEqual(loaded, s)
        XCTAssertTrue(loaded.isRunning)

        TimerStore.clear()
        XCTAssertEqual(TimerStore.load(), TimerState())
    }

    func testCorruptFileFallsBackToEmpty() throws {
        let original = TimerStore.url
        defer { TimerStore.url = original }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("timer-bad-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        TimerStore.url = dir.appendingPathComponent("state.json")
        try Data("not json".utf8).write(to: TimerStore.url)
        XCTAssertEqual(TimerStore.load(), TimerState())
    }
}

// MARK: - Pomodoro

final class PomodoroStateTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 2_000_000)

    private func pomodoro() -> TimerState {
        var s = TimerState(subjectName: "Maths")
        s.mode = .pomodoro            // 25 / 5 / 15, long break after 4
        return s
    }

    func testFocusPhaseEndsAndWaitsForYou() {
        var s = pomodoro()
        s.start(at: t0)
        XCTAssertTrue(s.isRunning)
        XCTAssertEqual(s.phaseEndDate, t0.addingTimeInterval(1500))

        s.resolve(at: t0.addingTimeInterval(1499))
        XCTAssertEqual(s.phase, .focus)
        XCTAssertTrue(s.isRunning)

        s.resolve(at: t0.addingTimeInterval(1500))
        XCTAssertEqual(s.phase, .shortBreak)
        XCTAssertFalse(s.isRunning)
        XCTAssertTrue(s.awaitingNext)
        XCTAssertEqual(s.completedBlocks, 1)
        XCTAssertEqual(s.accumulated, 1500, accuracy: 0.001)
        XCTAssertEqual(s.phaseEndedAt, t0.addingTimeInterval(1500))
    }

    func testBeingAwayForHoursNeverInflatesFocusTime() {
        var s = pomodoro()
        s.start(at: t0)
        s.resolve(at: t0.addingTimeInterval(10 * 3600))   // phone off all day
        XCTAssertEqual(s.accumulated, 1500, accuracy: 0.001)
        XCTAssertEqual(s.elapsed(at: t0.addingTimeInterval(10 * 3600)), 1500, accuracy: 0.001)
        XCTAssertTrue(s.awaitingNext)
        XCTAssertFalse(s.isRunning)
    }

    func testElapsedIsCappedAtPhaseEndEvenBeforeResolving() {
        var s = pomodoro()
        s.start(at: t0)
        XCTAssertEqual(s.elapsed(at: t0.addingTimeInterval(99_999)), 1500, accuracy: 0.001)
        XCTAssertEqual(s.phaseRemaining(at: t0.addingTimeInterval(99_999)), 0, accuracy: 0.001)
    }

    func testPauseMidFocusKeepsProgress() {
        var s = pomodoro()
        s.start(at: t0)
        s.pause(at: t0.addingTimeInterval(600))
        XCTAssertEqual(s.accumulated, 600, accuracy: 0.001)
        XCTAssertEqual(s.phaseBase, 600, accuracy: 0.001)
        XCTAssertEqual(s.phaseRemaining(at: t0.addingTimeInterval(5_000)), 900, accuracy: 0.001)
        XCTAssertTrue(s.hasProgress)

        s.start(at: t0.addingTimeInterval(1_000))
        XCTAssertEqual(s.phaseEndDate, t0.addingTimeInterval(1_900))
        s.resolve(at: t0.addingTimeInterval(1_900))
        XCTAssertEqual(s.phase, .shortBreak)
        XCTAssertEqual(s.accumulated, 1500, accuracy: 0.001)
    }

    func testBreaksNeverCountAsStudyTime() {
        var s = pomodoro()
        s.start(at: t0)
        s.resolve(at: t0.addingTimeInterval(1500))
        s.start(at: t0.addingTimeInterval(1600))                    // start the break
        XCTAssertEqual(s.elapsed(at: t0.addingTimeInterval(1700)), 1500, accuracy: 0.001)
        s.pause(at: t0.addingTimeInterval(1700))
        XCTAssertEqual(s.accumulated, 1500, accuracy: 0.001)
        s.start(at: t0.addingTimeInterval(1800))
        s.resolve(at: t0.addingTimeInterval(1800 + 200))            // 100 s done + 200 s => break (300 s) over
        XCTAssertEqual(s.phase, .focus)
        XCTAssertTrue(s.awaitingNext)
        XCTAssertEqual(s.accumulated, 1500, accuracy: 0.001)
    }

    func testLongBreakAfterEveryFourthBlock() {
        var s = pomodoro()
        var now = t0
        var phasesSeen: [PomodoroPhase] = []
        for _ in 0..<4 {
            s.start(at: now)                                          // focus
            now = now.addingTimeInterval(s.phaseDuration)
            s.resolve(at: now)
            phasesSeen.append(s.phase)                                // break that follows
            s.start(at: now)                                          // the break
            now = now.addingTimeInterval(s.phaseDuration)
            s.resolve(at: now)
        }
        XCTAssertEqual(phasesSeen, [.shortBreak, .shortBreak, .shortBreak, .longBreak])
        XCTAssertEqual(s.completedBlocks, 4)
        XCTAssertEqual(s.phase, .focus)
        XCTAssertEqual(s.accumulated, 4 * 1500, accuracy: 0.001)
    }

    func testCustomBlocksBeforeLongBreak() {
        var s = pomodoro()
        s.config.blocksBeforeLongBreak = 2
        s.start(at: t0)
        s.resolve(at: t0.addingTimeInterval(1500))
        XCTAssertEqual(s.phase, .shortBreak)
        s.start(at: t0.addingTimeInterval(1500)); s.resolve(at: t0.addingTimeInterval(1800))
        s.start(at: t0.addingTimeInterval(1800)); s.resolve(at: t0.addingTimeInterval(3300))
        XCTAssertEqual(s.phase, .longBreak)
    }

    func testSkipBreak() {
        var s = pomodoro()
        s.start(at: t0)
        s.resolve(at: t0.addingTimeInterval(1500))
        s.skipBreak(at: t0.addingTimeInterval(1500))
        XCTAssertEqual(s.phase, .focus)
        XCTAssertTrue(s.awaitingNext)
        XCTAssertFalse(s.isRunning)
        XCTAssertEqual(s.accumulated, 1500, accuracy: 0.001)

        // Skipping while a break is running also works, and skipping a focus block does nothing.
        s.start(at: t0.addingTimeInterval(1600))
        s.resolve(at: t0.addingTimeInterval(1600 + 1500))
        s.start(at: t0.addingTimeInterval(3200))
        s.skipBreak(at: t0.addingTimeInterval(3250))
        XCTAssertEqual(s.phase, .focus)
        XCTAssertFalse(s.isRunning)
        var focusing = pomodoro()
        focusing.start(at: t0)
        focusing.skipBreak(at: t0.addingTimeInterval(10))
        XCTAssertTrue(focusing.isRunning)
        XCTAssertEqual(focusing.phase, .focus)
    }

    func testStartAfterPhaseEndedWhileAppWasClosed() {
        var s = pomodoro()
        s.start(at: t0)
        // The user comes back an hour later and taps Start: the finished focus block is settled first,
        // so this starts the *break*, not another 25 minutes of focus.
        s.start(at: t0.addingTimeInterval(3600))
        XCTAssertEqual(s.phase, .shortBreak)
        XCTAssertTrue(s.isRunning)
        XCTAssertEqual(s.accumulated, 1500, accuracy: 0.001)
    }

    func testResetKeepsModeConfigAndSubject() {
        var s = pomodoro()
        s.config.focusMinutes = 50
        s.subjectIcon = "atom"; s.subjectColor = "purple"
        s.start(at: t0)
        s.resolve(at: t0.addingTimeInterval(4000))
        s.reset()
        XCTAssertFalse(s.hasProgress)
        XCTAssertEqual(s.mode, .pomodoro)
        XCTAssertEqual(s.config.focusMinutes, 50)
        XCTAssertEqual(s.subjectName, "Maths")
        XCTAssertEqual(s.subjectIcon, "atom")
        XCTAssertEqual(s.completedBlocks, 0)
    }

    func testHasProgressForEveryPomodoroSituation() {
        var s = pomodoro()
        XCTAssertFalse(s.hasProgress)
        s.start(at: t0); XCTAssertTrue(s.hasProgress)
        s.pause(at: t0.addingTimeInterval(1)); XCTAssertTrue(s.hasProgress)
        s.reset(); XCTAssertFalse(s.hasProgress)
        s.start(at: t0); s.resolve(at: t0.addingTimeInterval(1500)); XCTAssertTrue(s.hasProgress)
    }

    func testStopwatchBehaviourUnchangedByPomodoroFields() {
        var s = TimerState()
        s.start(at: t0)
        s.pause(at: t0.addingTimeInterval(900))
        XCTAssertEqual(s.elapsed(at: t0.addingTimeInterval(9_999)), 900, accuracy: 0.001)
        s.resolve(at: t0.addingTimeInterval(99_999))
        XCTAssertEqual(s.accumulated, 900, accuracy: 0.001)
        XCTAssertEqual(s.mode, .stopwatch)
    }

    // MARK: Persistence compatibility

    func testStateFileFromOlderVersionStillDecodes() throws {
        // Exactly the keys 0.6.x wrote: nothing about Pomodoro or the subject icon/colour.
        let old = #"{"accumulated": 900, "subjectName": "Maths", "runStart": 780000000.5, "sessionStart": 779999000}"#
        let s = try JSONDecoder().decode(TimerState.self, from: Data(old.utf8))
        XCTAssertEqual(s.accumulated, 900)
        XCTAssertEqual(s.subjectName, "Maths")
        XCTAssertTrue(s.isRunning)
        XCTAssertEqual(s.mode, .stopwatch)
        XCTAssertEqual(s.config, PomodoroConfig())
        XCTAssertEqual(s.subjectIcon, "book.fill")
    }

    func testRoundTripKeepsPomodoroState() throws {
        var s = pomodoro()
        s.subjectIcon = "atom"
        s.start(at: t0)
        s.pause(at: t0.addingTimeInterval(300))
        let decoded = try JSONDecoder().decode(TimerState.self, from: try JSONEncoder().encode(s))
        XCTAssertEqual(decoded, s)
    }

    func testAbsurdConfigFromDiskIsClamped() throws {
        let json = #"{"config": {"focusMinutes": 99999, "shortBreakMinutes": -4, "longBreakMinutes": 0, "blocksBeforeLongBreak": 1}, "phaseBase": -50, "completedBlocks": -3}"#
        let s = try JSONDecoder().decode(TimerState.self, from: Data(json.utf8))
        XCTAssertEqual(s.config.focusMinutes, 180)
        XCTAssertEqual(s.config.shortBreakMinutes, 1)
        XCTAssertEqual(s.config.longBreakMinutes, 1)
        XCTAssertEqual(s.config.blocksBeforeLongBreak, 2)
        XCTAssertEqual(s.phaseBase, 0)
        XCTAssertEqual(s.completedBlocks, 0)
    }

    func testPersistedPomodoroSurvivesStoreRoundTrip() {
        let original = TimerStore.url
        defer { TimerStore.url = original }
        TimerStore.url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pomo-\(UUID().uuidString)/state.json")
        var s = pomodoro()
        s.start(at: t0)
        TimerStore.save(s)
        XCTAssertEqual(TimerStore.load(), s)
        TimerStore.clear()
    }
}

// MARK: - Live Activity mapping & bundle integrity

@MainActor
final class LiveActivityMappingTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 2_000_000)

    func testStopwatchRunningUsesAVirtualStartDate() {
        var s = TimerState()
        s.start(at: t0)
        let now = t0.addingTimeInterval(125)
        let c = LiveActivityController.contentState(for: s, now: now)
        XCTAssertEqual(c.kind, .stopwatch)
        XCTAssertEqual(c.status, .running)
        XCTAssertEqual(c.referenceDate.timeIntervalSince(t0), 0, accuracy: 0.001)   // counts up from the real start
        XCTAssertEqual(c.frozenSeconds, 125, accuracy: 0.001)
    }

    func testStopwatchPausedIsFrozen() {
        var s = TimerState()
        s.start(at: t0); s.pause(at: t0.addingTimeInterval(300))
        let c = LiveActivityController.contentState(for: s, now: t0.addingTimeInterval(9_999))
        XCTAssertEqual(c.status, .paused)
        XCTAssertEqual(c.frozenSeconds, 300, accuracy: 0.001)
    }

    func testPomodoroRunningCountsDownToTheEndDate() {
        var s = TimerState(); s.mode = .pomodoro
        s.start(at: t0)
        let c = LiveActivityController.contentState(for: s, now: t0.addingTimeInterval(60))
        XCTAssertEqual(c.kind, .focus)
        XCTAssertEqual(c.status, .running)
        XCTAssertEqual(c.referenceDate, t0.addingTimeInterval(1500))
        XCTAssertEqual(c.phaseStart, t0)                           // progress bar spans the whole phase
        XCTAssertEqual(c.phaseTotalSeconds, 1500, accuracy: 0.001)
    }

    func testPomodoroPausedKeepsRemainingAndProgressAfterPause() {
        var s = TimerState(); s.mode = .pomodoro
        s.start(at: t0); s.pause(at: t0.addingTimeInterval(600))
        let c = LiveActivityController.contentState(for: s, now: t0.addingTimeInterval(700))
        XCTAssertEqual(c.status, .paused)
        XCTAssertEqual(c.frozenSeconds, 900, accuracy: 0.001)
    }

    func testPomodoroWaitingAndBreakKinds() {
        var s = TimerState(); s.mode = .pomodoro
        s.start(at: t0); s.resolve(at: t0.addingTimeInterval(1500))
        let c = LiveActivityController.contentState(for: s, now: t0.addingTimeInterval(1600))
        XCTAssertEqual(c.kind, .shortBreak)
        XCTAssertEqual(c.status, .waiting)
        XCTAssertEqual(c.frozenSeconds, 300, accuracy: 0.001)
        XCTAssertEqual(c.blocksDone, 1)
    }

    func testBlocksShownResetsForANewSet() {
        var s = TimerState(); s.mode = .pomodoro
        s.completedBlocks = 4; s.phase = .longBreak
        XCTAssertEqual(LiveActivityController.blocksDoneInCycle(s), 4)   // full set during the long break
        s.phase = .focus
        XCTAssertEqual(LiveActivityController.blocksDoneInCycle(s), 0)   // new set starts empty
        s.completedBlocks = 6; s.phase = .shortBreak
        XCTAssertEqual(LiveActivityController.blocksDoneInCycle(s), 2)
    }

    func testContentStateIsCodable() throws {
        var s = TimerState(); s.mode = .pomodoro; s.start(at: t0)
        let c = LiveActivityController.contentState(for: s, now: t0)
        let decoded = try JSONDecoder().decode(TimerActivityAttributes.ContentState.self, from: try JSONEncoder().encode(c))
        XCTAssertEqual(decoded, c)
    }

    // The things that make a Live Activity work at all. They live in Info.plists and project settings, which
    // nothing else would notice if they broke.

    func testAppDeclaresLiveActivitySupportAndRealVersionNumbers() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "NSSupportsLiveActivities") as? Bool, true)
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        XCTAssertNotNil(Int(build), "CFBundleVersion must be a number, got '\(build)' (the updater compares it)")
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        XCTAssertFalse(version.contains("$("), "unexpanded variable: \(version)")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "UIFileSharingEnabled") as? Bool, true)
        XCTAssertNotNil(Bundle.main.object(forInfoDictionaryKey: "UILaunchScreen"))
    }

    func testWidgetExtensionIsEmbeddedAndConfiguredAsAWidget() throws {
        let plugIns = try XCTUnwrap(Bundle.main.builtInPlugInsPath, "no PlugIns folder in the app")
        let appex = try XCTUnwrap(try FileManager.default.contentsOfDirectory(atPath: plugIns).first { $0.hasSuffix(".appex") })
        let info = try XCTUnwrap(NSDictionary(contentsOfFile: plugIns + "/" + appex + "/Info.plist"))
        let ext = try XCTUnwrap(info["NSExtension"] as? [String: Any])
        XCTAssertEqual(ext["NSExtensionPointIdentifier"] as? String, "com.apple.widgetkit-extension")
        XCTAssertEqual(info["CFBundleIdentifier"] as? String, "com.studytrack.app.widgets")
        XCTAssertTrue(AppFlavor.hasLiveActivityExtension)
        XCTAssertFalse(AppFlavor.isLite)
    }
}
