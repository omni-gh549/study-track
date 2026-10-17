import SwiftData
import XCTest
@testable import StudyTrack

@MainActor
final class GameAndBackupTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        container = try ModelContainer(for: Subject.self, StudySession.self, Goal.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func noon(daysAgo: Int) -> Date {
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: -daysAgo, to: .now)!
        return cal.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
    }

    @discardableResult
    private func add(_ subject: Subject?, minutes: Int, daysAgo: Int = 0, focus: Int = 3, hour: Int = 12) -> StudySession {
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: -daysAgo, to: .now)!
        let start = cal.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
        let s = StudySession(subject: subject, startDate: start, duration: TimeInterval(minutes * 60), notes: "", focus: focus)
        context.insert(s)
        return s
    }

    private func sessions() throws -> [StudySession] { try context.fetch(FetchDescriptor<StudySession>()) }
    private func goals() throws -> [Goal] { try context.fetch(FetchDescriptor<Goal>()) }

    // MARK: Levels & XP

    func testLevelThresholds() {
        XCTAssertEqual(GameEngine.level(for: 0), 1)
        XCTAssertEqual(GameEngine.level(for: 99), 1)
        XCTAssertEqual(GameEngine.level(for: 100), 2)
        XCTAssertEqual(GameEngine.level(for: 299), 2)
        XCTAssertEqual(GameEngine.level(for: 300), 3)
        XCTAssertEqual(GameEngine.level(for: 600), 4)
        let info = GameEngine.levelInfo(for: 150)
        XCTAssertEqual(info.level, 2)
        XCTAssertEqual(info.xpIntoLevel, 50)
        XCTAssertEqual(info.xpForNext, 200)
    }

    func testSessionXPAndQuestBonus() throws {
        let maths = Subject(name: "Maths")
        context.insert(maths)
        let s = add(maths, minutes: 60, focus: 4)
        XCTAssertEqual(GameEngine.sessionXP(s), 60 + 12 + 5)
        // Quests done that day: 30 minutes + a sharp session => 2 x 25 bonus.
        let stats = GameEngine.stats(sessions: try sessions(), goals: [])
        XCTAssertEqual(stats.xp, 77 + 50)
    }

    func testStreaks() throws {
        add(nil, minutes: 20, daysAgo: 0)
        add(nil, minutes: 20, daysAgo: 1)
        add(nil, minutes: 20, daysAgo: 2)
        add(nil, minutes: 20, daysAgo: 5)
        add(nil, minutes: 20, daysAgo: 6)
        let all = try sessions()
        XCTAssertEqual(GameEngine.currentStreak(sessions: all), 3)
        XCTAssertEqual(GameEngine.bestStreak(sessions: all), 3)
    }

    func testStreakSurvivesUntilEndOfTodayWhenYesterdayStudied() throws {
        add(nil, minutes: 20, daysAgo: 1)
        add(nil, minutes: 20, daysAgo: 2)
        XCTAssertEqual(GameEngine.currentStreak(sessions: try sessions()), 2)
    }

    func testAchievementsAndCelebrationDiff() throws {
        let before = GameEngine.snapshot(sessions: [], goals: [])
        XCTAssertTrue(before.unlocked.isEmpty)
        add(nil, minutes: 90, focus: 5)
        let after = GameEngine.snapshot(sessions: try sessions(), goals: [])
        XCTAssertTrue(after.unlocked.contains("first"))
        XCTAssertTrue(after.unlocked.contains("hours1"))
        XCTAssertTrue(after.unlocked.contains("laser"))
        let celebration = GameEngine.celebration(from: before, to: after)
        XCTAssertGreaterThan(celebration.xpGained, 0)
        XCTAssertTrue(celebration.achievements.contains { $0.id == "first" })
    }

    func testEarlyBirdAndNightOwl() throws {
        add(nil, minutes: 20, hour: 6)
        add(nil, minutes: 20, hour: 23)
        let stats = GameEngine.stats(sessions: try sessions(), goals: [])
        XCTAssertTrue(stats.earlyBird)
        XCTAssertTrue(stats.nightOwl)
    }

    func testGoalProgressBySubject() throws {
        let maths = Subject(name: "Maths"), art = Subject(name: "Art")
        context.insert(maths); context.insert(art)
        add(maths, minutes: 30)
        add(art, minutes: 45)
        let all = try sessions()

        let anyGoal = Goal(title: "All", targetMinutes: 60, period: .daily, subject: nil)
        let mathsGoal = Goal(title: "Maths", targetMinutes: 60, period: .weekly, subject: maths)
        context.insert(anyGoal); context.insert(mathsGoal)

        XCTAssertEqual(anyGoal.progress(in: all), 75 * 60, accuracy: 0.1)
        XCTAssertEqual(mathsGoal.progress(in: all), 30 * 60, accuracy: 0.1)
    }

    // MARK: Backup

    private func populate() throws {
        let maths = Subject(name: "Maths", color: .blue, icon: "function")
        let art = Subject(name: "Art", color: .pink, icon: "paintpalette.fill")
        context.insert(maths); context.insert(art)
        add(maths, minutes: 60, daysAgo: 0, focus: 4)
        add(art, minutes: 30, daysAgo: 1, focus: 2)
        add(nil, minutes: 15, daysAgo: 2, focus: 5)
        context.insert(Goal(title: "Weekly", targetMinutes: 300, period: .weekly, subject: nil))
        context.insert(Goal(title: "Maths", targetMinutes: 120, period: .daily, subject: maths))
        try context.save()
    }

    func testBackupRoundTripIntoFreshStore() throws {
        try populate()
        let file = BackupFile.make(subjects: try context.fetch(FetchDescriptor<Subject>()),
                                   sessions: try sessions(), goals: try goals())
        let decoded = try BackupFile.decode(try file.encoded())

        let other = try ModelContainer(for: Subject.self, StudySession.self, Goal.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        decoded.restore(into: other.mainContext)

        let subjects = try other.mainContext.fetch(FetchDescriptor<Subject>())
        let restoredSessions = try other.mainContext.fetch(FetchDescriptor<StudySession>())
        let restoredGoals = try other.mainContext.fetch(FetchDescriptor<Goal>())
        XCTAssertEqual(subjects.count, 2)
        XCTAssertEqual(restoredSessions.count, 3)
        XCTAssertEqual(restoredGoals.count, 2)
        XCTAssertEqual(Set(restoredSessions.compactMap { $0.subject?.name }), ["Maths", "Art"])
        XCTAssertEqual(restoredSessions.filter { $0.subject == nil }.count, 1)
        XCTAssertEqual(restoredSessions.reduce(0) { $0 + $1.duration }, 105 * 60, accuracy: 0.1)
        XCTAssertEqual(restoredGoals.first { $0.title == "Maths" }?.subject?.name, "Maths")
        XCTAssertEqual(subjects.first { $0.name == "Art" }?.icon, "paintpalette.fill")
        XCTAssertEqual(subjects.first { $0.name == "Art" }?.colorRaw, SubjectColor.pink.rawValue)
    }

    func testRestoreReplacesExistingData() throws {
        try populate()
        let file = BackupFile.make(subjects: try context.fetch(FetchDescriptor<Subject>()),
                                   sessions: try sessions(), goals: try goals())
        add(nil, minutes: 500, daysAgo: 3)
        context.insert(Subject(name: "Extra"))
        try context.save()

        file.restore(into: context)
        XCTAssertEqual(try sessions().count, 3)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Subject>()).count, 2)
    }

    func testDecodesVersion1Format() throws {
        let json = """
        {"version":1,"exportedAt":"2026-10-16T12:00:00Z",
         "subjects":[{"name":"Maths","colorRaw":"blue","icon":"function","createdAt":"2026-10-01T09:00:00Z"}],
         "sessions":[{"subjectIndex":0,"startDate":"2026-10-15T09:00:00Z","duration":3600,"notes":"x","focus":4},
                     {"subjectIndex":null,"startDate":"2026-10-14T09:00:00Z","duration":600,"notes":"","focus":3}],
         "goals":[{"title":"G","targetMinutes":60,"periodRaw":"daily","subjectIndex":0,"createdAt":"2026-10-01T09:00:00Z"}]}
        """
        let file = try BackupFile.decode(Data(json.utf8))
        file.restore(into: context)
        XCTAssertEqual(try sessions().count, 2)
        XCTAssertEqual(try goals().first?.subject?.name, "Maths")
    }

    func testDeletingSubjectKeepsSessionsAndRemovesGoals() throws {
        try populate()
        let maths = try context.fetch(FetchDescriptor<Subject>()).first { $0.name == "Maths" }!
        context.delete(maths)
        try context.save()
        XCTAssertEqual(try sessions().count, 3)
        XCTAssertEqual(try goals().count, 1)
    }

    func testAutoBackupWritesRestorableFile() throws {
        try populate()
        let url = try XCTUnwrap(AutoBackup.write(prefix: "StudyTrack-test", context: context))
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try BackupFile.decode(try Data(contentsOf: url))
        XCTAssertEqual(file.sessions.count, 3)
    }
}
