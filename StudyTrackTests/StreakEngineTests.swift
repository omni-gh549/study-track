import XCTest
@testable import StudyTrack

final class StreakEngineTests: XCTestCase {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private lazy var now: Date = {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 10; parts.day = 20; parts.hour = 12
        parts.timeZone = TimeZone(identifier: "UTC")
        return cal.date(from: parts)!
    }()

    private func day(_ daysAgo: Int) -> Date { cal.date(byAdding: .day, value: -daysAgo, to: now)! }

    private func compute(_ daysAgo: [Int]) -> StreakResult {
        StreakEngine.compute(studyDays: Set(daysAgo.map(day)), now: now, calendar: cal)
    }

    private func start(_ d: Int) -> Date { cal.startOfDay(for: day(d)) }

    func testEmpty() {
        let r = compute([])
        XCTAssertEqual(r, StreakResult())
        XCTAssertFalse(r.atRisk)
    }

    func testTodayOnly() {
        let r = compute([0])
        XCTAssertEqual(r.current, 1)
        XCTAssertTrue(r.studiedToday)
        XCTAssertFalse(r.atRisk)
        XCTAssertEqual(r.daysToNextFreeze, 6)
    }

    func testYesterdayOnlyIsAtRiskButAlive() {
        let r = compute([1])
        XCTAssertEqual(r.current, 1)
        XCTAssertTrue(r.atRisk)
    }

    func testSevenDaysEarnsAFreeze() {
        let r = compute(Array(0...6))
        XCTAssertEqual(r.current, 7)
        XCTAssertEqual(r.best, 7)
        XCTAssertEqual(r.freezes, 1)
        XCTAssertEqual(r.daysToNextFreeze, 7)
    }

    func testFreezesCapAtTwo() {
        XCTAssertEqual(compute(Array(0...13)).freezes, 2)
        let r = compute(Array(0...27))
        XCTAssertEqual(r.freezes, StreakEngine.maxFreezes)
        XCTAssertEqual(r.daysToNextFreeze, 0)
    }

    func testFreezeCoversOneMissedDay() {
        let r = compute(Array(2...8) + [0]) // 7-day run, missed yesterday, studied today
        XCTAssertEqual(r.current, 8)
        XCTAssertEqual(r.freezes, 0)
        XCTAssertEqual(r.frozenDays, [start(1)])
        XCTAssertEqual(r.best, 8)
    }

    func testFreezeDoesNotAddToStreakCount() {
        // 7 days, one frozen miss, then studied on the day after: 8 studied days, not 9.
        let r = compute(Array(3...9) + [1, 0])
        XCTAssertEqual(r.current, 9)   // 7 + 2 studied days (frozen day is bridged, not counted)
        XCTAssertEqual(r.frozenDays, [start(2)])
    }

    func testTooBigAGapResetsAndWastesNoFreezes() {
        let r = compute(Array(6...12) + [0]) // earned 1 freeze, then missed 5 days
        XCTAssertEqual(r.current, 1)
        XCTAssertEqual(r.freezes, 1)
        XCTAssertTrue(r.frozenDays.isEmpty)
        XCTAssertEqual(r.best, 7)
    }

    func testTodayNotStudiedYetCostsNothing() {
        let r = compute(Array(1...7))
        XCTAssertEqual(r.current, 7)
        XCTAssertEqual(r.freezes, 1)
        XCTAssertTrue(r.frozenDays.isEmpty)
        XCTAssertTrue(r.atRisk)
        XCTAssertFalse(r.studiedToday)
    }

    func testTwoMissedDaysCoveredByTwoFreezes() {
        let r = compute(Array(7...20) + Array(0...4)) // 14-day run (2 freezes), miss 6 & 5, then 5 more days
        XCTAssertEqual(r.current, 19)
        XCTAssertEqual(r.freezes, 0)
        XCTAssertEqual(r.frozenDays, [start(6), start(5)])
    }

    func testStreakWithZeroRunNeverSpendsFreezes() {
        let r = compute([0, 10])
        XCTAssertEqual(r.current, 1)
        XCTAssertEqual(r.freezes, 0)
        XCTAssertTrue(r.frozenDays.isEmpty)
    }

    func testBestStreakKeptAfterReset() {
        let r = compute([0, 1, 2] + Array(10...20))
        XCTAssertEqual(r.current, 3)
        XCTAssertEqual(r.best, 11)
        XCTAssertEqual(r.daysToNextFreeze, 4)
    }

    func testRemovingADayRecalculates() {
        let full = compute(Array(0...6))
        let missing = compute(Array(0...6).filter { $0 != 3 })
        XCTAssertEqual(full.current, 7)
        XCTAssertEqual(missing.current, 3)
    }

    func testFutureSessionsAreIgnored() {
        let r = compute([-3, -2, 0])
        XCTAssertEqual(r.current, 1)
    }

    func testAncientHistoryDoesNotHang() {
        let ancient = Date(timeIntervalSince1970: -2_000_000_000)
        let r = StreakEngine.compute(studyDays: [ancient, now], now: now, calendar: cal)
        XCTAssertEqual(r.current, 1)
    }

    func testSurvivesDaylightSavingChange() {
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = TimeZone(identifier: "America/New_York")!
        var parts = DateComponents()
        parts.year = 2026; parts.month = 11; parts.day = 5; parts.hour = 12
        parts.timeZone = ny.timeZone
        let nowNY = ny.date(from: parts)!   // DST ended on Nov 1
        let days = (0..<10).map { ny.date(byAdding: .day, value: -$0, to: nowNY)! }
        let r = StreakEngine.compute(studyDays: Set(days), now: nowNY, calendar: ny)
        XCTAssertEqual(r.current, 10)
        XCTAssertTrue(r.frozenDays.isEmpty)
    }

    // MARK: Granted freezes

    private func computeWithGrants(_ daysAgo: [Int], grants: [(Int, Int)]) -> StreakResult {
        StreakEngine.compute(studyDays: Set(daysAgo.map(day)),
                             grants: grants.map { FreezeGrantEvent(date: day($0.0), count: $0.1) },
                             now: now, calendar: cal)
    }

    func testGiftWithNoHistoryIsHeld() {
        let r = computeWithGrants([], grants: [(0, 2)])
        XCTAssertEqual(r.freezes, 2)
        XCTAssertEqual(r.current, 0)
        XCTAssertEqual(r.daysToNextFreeze, 0)
    }

    func testGiftIsCappedAtTwo() {
        XCTAssertEqual(computeWithGrants([], grants: [(0, 2), (1, 2), (2, 5)]).freezes, 2)
    }

    func testGiftProtectsAMissedDay() {
        // 3 days studied, miss yesterday, studied today; two freezes gifted on the first study day.
        let r = computeWithGrants([5, 4, 3, 0], grants: [(5, 2)])
        // days: 5,4,3 studied; 2,1 missed (2 days) -> both covered by the 2 gifted freezes; today studied.
        XCTAssertEqual(r.current, 4)
        XCTAssertEqual(r.frozenDays, [start(2), start(1)])
        XCTAssertEqual(r.freezes, 0)
    }

    func testGiftBeforeHistoryStartsIsAvailableLater() {
        let r = computeWithGrants([3, 2, 0], grants: [(10, 2)])   // gift long before first study day; missed 1 day
        XCTAssertEqual(r.current, 3)
        XCTAssertEqual(r.frozenDays, [start(1)])
        XCTAssertEqual(r.freezes, 1)
    }

    func testGiftArrivingMidGapCanSaveTheStreak() {
        // Studied 6,5,4 ago, missed 3 and 2 ago, studied yesterday and today.
        let studied = [6, 5, 4, 1, 0]

        // A single freeze can't cover two missed days: the streak resets, but the gift is not wasted.
        let short = computeWithGrants(studied, grants: [(3, 1)])
        XCTAssertEqual(short.current, 2)
        XCTAssertTrue(short.frozenDays.isEmpty)
        XCTAssertEqual(short.freezes, 1)

        // Two freezes arriving on the first missed day bridge the gap.
        let saved = computeWithGrants(studied, grants: [(3, 2)])
        XCTAssertEqual(saved.current, 5)
        XCTAssertEqual(saved.frozenDays, [start(3), start(2)])
        XCTAssertEqual(saved.freezes, 0)
    }

    func testFutureGiftIsIgnored() {
        XCTAssertEqual(computeWithGrants([0], grants: [(-3, 2)]).freezes, 0)
    }

    func testGiftTodayCoversNothingYetButIsHeld() {
        let r = computeWithGrants([2, 1], grants: [(0, 2)])
        XCTAssertEqual(r.current, 2)
        XCTAssertEqual(r.freezes, 2)
        XCTAssertTrue(r.atRisk)
    }
}
