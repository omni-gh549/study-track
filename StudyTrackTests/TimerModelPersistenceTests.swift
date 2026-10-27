import XCTest
@testable import StudyTrack

/// The live timer must never be replaced by an older or missing copy from disk, and a damaged state file must
/// fall back to the previous good one.
@MainActor
final class TimerModelPersistenceTests: XCTestCase {
    private var originalURL: URL!
    private var dir: URL!

    override func setUp() {
        originalURL = TimerStore.url
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("timer-tests-\(UUID().uuidString)")
        TimerStore.url = dir.appendingPathComponent("timer-state.json")
    }

    override func tearDown() {
        TimerStore.url = originalURL
        try? FileManager.default.removeItem(at: dir)
    }

    private func runningPomodoro(_ model: TimerModel) {
        model.update { $0.mode = .pomodoro }
        model.update { $0.start(at: .now) }
    }

    func testReloadNeverReplacesNewerMemoryWithAStaleDiskCopy() {
        let model = TimerModel()
        runningPomodoro(model)
        TimerStore.save(TimerState())                       // an old, empty copy lands on disk
        model.reload()
        XCTAssertTrue(model.state.isPomodoro)
        XCTAssertTrue(model.state.isRunning)
        XCTAssertEqual(TimerStore.load().revision, model.state.revision, "Disk should be healed from memory")
    }

    func testFailedWritesDoNotWipeTheLiveTimerWhenTheAppReturns() {
        TimerStore.url = URL(fileURLWithPath: "/nonexistent-root/timer/timer-state.json")   // can't be written
        let model = TimerModel()
        runningPomodoro(model)
        XCTAssertTrue(model.persistenceFailing)
        model.reload()                                      // what coming back to the app does
        XCTAssertTrue(model.state.isPomodoro)
        XCTAssertTrue(model.state.isRunning)
    }

    func testNewerDiskCopyIsAdopted() {
        let model = TimerModel()
        model.update { $0.subjectName = "Maths" }
        var newer = model.state
        newer.subjectName = "Physics"
        newer.revision += 5
        TimerStore.save(newer)
        model.reload()
        XCTAssertEqual(model.state.subjectName, "Physics")
    }

    func testUnreadableStateFileFallsBackToThePreviousCopy() throws {
        let model = TimerModel()
        model.update { $0.mode = .pomodoro }
        model.update { $0.subjectName = "Maths" }           // the file now holds this; .prev holds the one before
        try Data("not json".utf8).write(to: TimerStore.url)
        XCTAssertEqual(TimerStore.load().mode, .pomodoro)
    }

    func testRevisionSurvivesEncodingAndOldFilesDecodeAsZero() throws {
        var s = TimerState(); s.revision = 7
        let decoded = try JSONDecoder().decode(TimerState.self, from: try JSONEncoder().encode(s))
        XCTAssertEqual(decoded.revision, 7)
        let old = try JSONDecoder().decode(TimerState.self, from: Data(#"{"accumulated": 5}"#.utf8))
        XCTAssertEqual(old.revision, 0)
    }
}
