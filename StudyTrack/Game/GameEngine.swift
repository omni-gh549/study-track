import SwiftData
import SwiftUI

// Everything here is *derived* from sessions + goals, so XP, levels and badges
// can never drift out of sync with the data (delete a session, XP drops).

struct PlayerStats {
    var totalSeconds: TimeInterval = 0
    var sessionCount = 0
    var currentStreak = 0
    var bestStreak = 0
    var freezes = 0
    var freezesUsed = 0
    var longestSession: TimeInterval = 0
    var perfectFocusSessions = 0
    var subjectCount = 0
    var earlyBird = false
    var nightOwl = false
    var goalsCompleted = 0
    var xp = 0

    var level: Int { GameEngine.level(for: xp) }
}

struct LevelInfo {
    let level: Int
    let title: String
    let xpIntoLevel: Int
    let xpForNext: Int
    var progress: Double { xpForNext > 0 ? Double(xpIntoLevel) / Double(xpForNext) : 1 }
}

struct Quest: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let current: Double
    let target: Double
    let unit: String

    var done: Bool { current >= target }
    var fraction: Double { min(current / target, 1) }
    var caption: String { "\(Int(min(current, target))) / \(Int(target)) \(unit)" }
}

struct AchievementDef: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
    let measure: (PlayerStats) -> (current: Double, goal: Double)

    func isUnlocked(_ stats: PlayerStats) -> Bool {
        let m = measure(stats)
        return m.current >= m.goal
    }

    func progress(_ stats: PlayerStats) -> Double {
        let m = measure(stats)
        return min(m.current / m.goal, 1)
    }

    func progressText(_ stats: PlayerStats) -> String {
        let m = measure(stats)
        return "\(Int(min(m.current, m.goal))) / \(Int(m.goal))"
    }
}

struct GameSnapshot {
    let stats: PlayerStats
    let level: LevelInfo
    let unlocked: Set<String>
}

struct Celebration: Identifiable {
    let id = UUID()
    let xpGained: Int
    let newLevel: LevelInfo?
    let achievements: [AchievementDef]
    var isBig: Bool { newLevel != nil || !achievements.isEmpty }
}

enum GameEngine {
    static let questBonus = 25

    // MARK: XP & levels

    static func sessionXP(_ session: StudySession) -> Int {
        let minutes = Int(session.duration / 60)
        let focusBonus = session.focus >= 4 ? minutes / 5 : 0
        return minutes + focusBonus + 5
    }

    /// Live preview used by the timer while a session is running.
    static func previewXP(seconds: TimeInterval) -> Int {
        let minutes = Int(seconds / 60)
        return minutes > 0 ? minutes + 5 : 0
    }

    /// Total XP needed to *reach* a level: 0, 100, 300, 600, 1000, ...
    static func threshold(level: Int) -> Int { 50 * level * (level - 1) }

    static func level(for xp: Int) -> Int {
        var l = 1
        while xp >= threshold(level: l + 1) { l += 1 }
        return l
    }

    private static let titles = ["Newcomer", "Curious Mind", "Apprentice", "Scholar",
                                 "Strategist", "Sage", "Luminary", "Grandmaster"]

    static func levelInfo(for xp: Int) -> LevelInfo {
        let l = level(for: xp)
        let base = threshold(level: l)
        return LevelInfo(level: l,
                         title: titles[min((l - 1) / 2, titles.count - 1)],
                         xpIntoLevel: xp - base,
                         xpForNext: threshold(level: l + 1) - base)
    }

    // MARK: Quests

    static func quests(for day: Date, sessions: [StudySession]) -> [Quest] {
        let cal = Calendar.current
        let today = sessions.filter { cal.isDate($0.startDate, inSameDayAs: day) }
        let minutes = today.reduce(0) { $0 + $1.duration } / 60
        let subjects = Set(today.compactMap { $0.subject?.persistentModelID }).count
        let sharp = today.filter { $0.focus >= 4 && $0.duration >= 15 * 60 }.count
        return [
            Quest(id: "minutes", title: "Study for 30 minutes", symbol: "clock.fill",
                  current: minutes, target: 30, unit: "min"),
            Quest(id: "subjects", title: "Cover 2 different subjects", symbol: "square.stack.3d.up.fill",
                  current: Double(subjects), target: 2, unit: "subjects"),
            Quest(id: "sharp", title: "Log a sharp 15+ min session (4★+)", symbol: "bolt.fill",
                  current: Double(sharp), target: 1, unit: "session"),
        ]
    }

    // MARK: Streaks

    static func streak(sessions: [StudySession], now: Date = .now) -> StreakResult {
        StreakEngine.compute(studyDays: Set(sessions.map(\.startDate)), now: now)
    }

    static func currentStreak(sessions: [StudySession]) -> Int { streak(sessions: sessions).current }

    static func bestStreak(sessions: [StudySession]) -> Int { streak(sessions: sessions).best }

    // MARK: Stats

    static func stats(sessions: [StudySession], goals: [Goal]) -> PlayerStats {
        let cal = Calendar.current
        var s = PlayerStats()
        s.sessionCount = sessions.count
        s.totalSeconds = sessions.reduce(0) { $0 + $1.duration }
        s.longestSession = sessions.map(\.duration).max() ?? 0
        s.perfectFocusSessions = sessions.filter { $0.focus == 5 && $0.duration >= 30 * 60 }.count
        s.subjectCount = Set(sessions.compactMap { $0.subject?.persistentModelID }).count
        s.earlyBird = sessions.contains { cal.component(.hour, from: $0.startDate) < 8 }
        s.nightOwl = sessions.contains { cal.component(.hour, from: $0.startDate) >= 22 }
        let streakInfo = streak(sessions: sessions)
        s.currentStreak = streakInfo.current
        s.bestStreak = streakInfo.best
        s.freezes = streakInfo.freezes
        s.freezesUsed = streakInfo.frozenDays.count
        s.goalsCompleted = goals.filter { $0.target > 0 && $0.progress(in: sessions) >= $0.target }.count

        let byDay = Dictionary(grouping: sessions) { cal.startOfDay(for: $0.startDate) }
        let questXP = byDay.reduce(0) { total, entry in
            total + quests(for: entry.key, sessions: entry.value).filter(\.done).count * questBonus
        }
        s.xp = sessions.reduce(0) { $0 + sessionXP($1) } + questXP
        return s
    }

    /// `stored` are badges already earned and persisted; they stay unlocked no matter what the data says now.
    static func snapshot(sessions: [StudySession], goals: [Goal], stored: Set<String> = []) -> GameSnapshot {
        let s = stats(sessions: sessions, goals: goals)
        let derived = Set(achievements.filter { $0.isUnlocked(s) }.map(\.id))
        return GameSnapshot(stats: s, level: levelInfo(for: s.xp), unlocked: derived.union(stored))
    }

    /// Persists any newly earned badges. Safe to call as often as you like.
    @MainActor
    static func syncBadges(context: ModelContext) {
        let sessions = (try? context.fetch(FetchDescriptor<StudySession>())) ?? []
        let goals = (try? context.fetch(FetchDescriptor<Goal>())) ?? []
        let existing = (try? context.fetch(FetchDescriptor<UnlockedBadge>())) ?? []
        let stored = Set(existing.map(\.badgeID))
        let missing = snapshot(sessions: sessions, goals: goals, stored: stored).unlocked.subtracting(stored)
        guard !missing.isEmpty else { return }
        for id in missing { context.insert(UnlockedBadge(badgeID: id)) }
        context.commit()
    }

    static func celebration(from before: GameSnapshot, to after: GameSnapshot) -> Celebration {
        let newly = achievements.filter { after.unlocked.contains($0.id) && !before.unlocked.contains($0.id) }
        return Celebration(xpGained: after.stats.xp - before.stats.xp,
                           newLevel: after.level.level > before.level.level ? after.level : nil,
                           achievements: newly)
    }

    // MARK: Achievements

    static let achievements: [AchievementDef] = [
        AchievementDef(id: "first", title: "First Steps", detail: "Log your first study session.",
                       symbol: "figure.walk", tint: .blue) { (Double($0.sessionCount), 1) },
        AchievementDef(id: "sessions10", title: "Getting Into It", detail: "Log 10 study sessions.",
                       symbol: "books.vertical.fill", tint: .teal) { (Double($0.sessionCount), 10) },
        AchievementDef(id: "sessions50", title: "Regular", detail: "Log 50 study sessions.",
                       symbol: "medal.fill", tint: .indigo) { (Double($0.sessionCount), 50) },
        AchievementDef(id: "hours1", title: "First Hour", detail: "Study for 1 hour in total.",
                       symbol: "hourglass", tint: .mint) { ($0.totalSeconds / 3600, 1) },
        AchievementDef(id: "hours10", title: "Ten Hour Club", detail: "Study for 10 hours in total.",
                       symbol: "clock.fill", tint: .green) { ($0.totalSeconds / 3600, 10) },
        AchievementDef(id: "hours100", title: "Centurion", detail: "Study for 100 hours in total.",
                       symbol: "trophy.fill", tint: .yellow) { ($0.totalSeconds / 3600, 100) },
        AchievementDef(id: "streak3", title: "On a Roll", detail: "Study 3 days in a row.",
                       symbol: "flame.fill", tint: .orange) { (Double($0.bestStreak), 3) },
        AchievementDef(id: "streak7", title: "Week Warrior", detail: "Study 7 days in a row.",
                       symbol: "flame.fill", tint: .red) { (Double($0.bestStreak), 7) },
        AchievementDef(id: "streak30", title: "Unstoppable", detail: "Study 30 days in a row.",
                       symbol: "flame.fill", tint: .pink) { (Double($0.bestStreak), 30) },
        AchievementDef(id: "freeze", title: "Saved by the Ice", detail: "A streak freeze protected your streak.",
                       symbol: "snowflake", tint: .cyan) { (Double($0.freezesUsed), 1) },
        AchievementDef(id: "marathon", title: "Marathon", detail: "Complete a single 2 hour session.",
                       symbol: "figure.run", tint: .purple) { ($0.longestSession / 3600, 2) },
        AchievementDef(id: "laser", title: "Laser Focus", detail: "Log a 30+ minute session with 5★ focus.",
                       symbol: "bolt.fill", tint: .yellow) { (Double($0.perfectFocusSessions), 1) },
        AchievementDef(id: "early", title: "Early Bird", detail: "Start a session before 8am.",
                       symbol: "sunrise.fill", tint: .orange) { ($0.earlyBird ? 1 : 0, 1) },
        AchievementDef(id: "night", title: "Night Owl", detail: "Start a session after 10pm.",
                       symbol: "moon.stars.fill", tint: .indigo) { ($0.nightOwl ? 1 : 0, 1) },
        AchievementDef(id: "polymath", title: "Polymath", detail: "Study 3 different subjects.",
                       symbol: "square.stack.3d.up.fill", tint: .teal) { (Double($0.subjectCount), 3) },
        AchievementDef(id: "goal", title: "Goal Getter", detail: "Complete a goal for the current period.",
                       symbol: "target", tint: .green) { (Double($0.goalsCompleted), 1) },
        AchievementDef(id: "level5", title: "Rising Star", detail: "Reach level 5.",
                       symbol: "star.circle.fill", tint: .purple) { (Double($0.level), 5) },
    ]
}

// MARK: - Celebration plumbing

@MainActor
@Observable
final class CelebrationCenter {
    var current: Celebration?

    func present(_ celebration: Celebration) { current = celebration }

    func dismiss(id: UUID? = nil) {
        guard id == nil || current?.id == id else { return }
        current = nil
    }
}
