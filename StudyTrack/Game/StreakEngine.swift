import Foundation

struct StreakResult: Equatable {
    var current = 0
    var best = 0
    /// Freezes currently held (0...maxFreezes).
    var freezes = 0
    /// Missed days that a freeze protected, oldest first.
    var frozenDays: [Date] = []
    var studiedToday = false
    /// Study days still needed in the current run to earn the next freeze (0 when at the cap).
    var daysToNextFreeze = StreakEngine.daysPerFreeze

    /// There's a streak to lose and nothing studied yet today.
    var atRisk: Bool { current > 0 && !studiedToday }
}

/// Streaks with freezes, computed purely from the set of days you studied — so it always agrees with your
/// history (edit or delete a session and everything recalculates) and is included in backups for free.
///
/// Rules:
/// - Every 7th consecutive study day earns a freeze. You can hold at most `maxFreezes`.
/// - When you miss days, freezes are spent automatically — one per missed day — and the streak carries on.
///   A frozen day doesn't add to the streak count.
/// - If you miss more days than you have freezes, the streak resets and **no** freezes are wasted.
/// - Today only counts once it's over: not having studied *yet* never costs a freeze.
enum StreakEngine {
    static let maxFreezes = 2
    static let daysPerFreeze = 7
    private static let maxLookbackDays = 3650

    static func compute(studyDays: Set<Date>, now: Date = .now, calendar: Calendar = .current) -> StreakResult {
        let cal = calendar
        let today = cal.startOfDay(for: now)
        let days = Set(studyDays.map { cal.startOfDay(for: $0) })

        func next(_ d: Date) -> Date {
            cal.date(byAdding: .day, value: 1, to: d) ?? d.addingTimeInterval(86_400)
        }

        var result = StreakResult()
        result.studiedToday = days.contains(today)

        let earliestAllowed = cal.date(byAdding: .day, value: -maxLookbackDays, to: today) ?? today
        guard let first = days.filter({ $0 <= today }).min() else { return result }

        var day = max(first, earliestAllowed)
        var run = 0
        var best = 0
        var freezes = 0
        var frozen: [Date] = []

        while day <= today {
            if days.contains(day) {
                run += 1
                best = max(best, run)
                if run % daysPerFreeze == 0 { freezes = min(freezes + 1, maxFreezes) }
                day = next(day)
            } else if day == today {
                break // today isn't over: not studying yet doesn't break anything
            } else {
                var gap: [Date] = []
                var d = day
                while d < today && !days.contains(d) {
                    gap.append(d)
                    d = next(d)
                }
                if run > 0 && freezes >= gap.count {
                    freezes -= gap.count
                    frozen.append(contentsOf: gap)
                } else {
                    run = 0
                }
                day = d
            }
        }

        result.current = run
        result.best = best
        result.freezes = freezes
        result.frozenDays = frozen
        result.daysToNextFreeze = freezes >= maxFreezes ? 0 : daysPerFreeze - (run % daysPerFreeze)
        return result
    }
}
