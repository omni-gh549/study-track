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
