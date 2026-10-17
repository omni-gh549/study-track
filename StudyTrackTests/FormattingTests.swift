import XCTest
@testable import StudyTrack

final class FormattingTests: XCTestCase {
    func testStudyDuration() {
        XCTAssertEqual(TimeInterval(0).studyDuration, "0m")
        XCTAssertEqual(TimeInterval(45 * 60).studyDuration, "45m")
        XCTAssertEqual(TimeInterval(3600).studyDuration, "1h")
        XCTAssertEqual(TimeInterval(5400).studyDuration, "1h 30m")
    }

    func testClock() {
        XCTAssertEqual(TimeInterval(0).clock, "00:00")
        XCTAssertEqual(TimeInterval(125).clock, "02:05")
        XCTAssertEqual(TimeInterval(3725).clock, "1:02:05")
    }
}
