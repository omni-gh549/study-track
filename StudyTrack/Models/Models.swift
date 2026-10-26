import SwiftData
import SwiftUI

enum GoalPeriod: String, CaseIterable, Identifiable {
    case daily, weekly

    var id: String { rawValue }
    var title: String { self == .daily ? "Daily" : "Weekly" }
    var component: Calendar.Component { self == .daily ? .day : .weekOfYear }
}

// MARK: - Models

@Model
final class Subject {
    var name: String = ""
    var colorRaw: String = SubjectColor.blue.rawValue
    var icon: String = "book.fill"
    var createdAt: Date = Date()

    // Deleting a subject must never wipe study history: sessions are kept and become "No subject".
    @Relationship(deleteRule: .nullify, inverse: \StudySession.subject)
    var sessions: [StudySession] = []

    @Relationship(deleteRule: .cascade, inverse: \Goal.subject)
    var goals: [Goal] = []

    init(name: String, color: SubjectColor = .blue, icon: String = "book.fill") {
        self.name = name
        self.colorRaw = color.rawValue
        self.icon = icon
    }

    var subjectColor: SubjectColor {
        get { SubjectColor(rawValue: colorRaw) ?? .blue }
        set { colorRaw = newValue.rawValue }
    }

    var color: Color { subjectColor.color }
}

@Model
final class StudySession {
    var subject: Subject?
    var startDate: Date = Date()
    var duration: TimeInterval = 0
    var notes: String = ""
    /// 1...5 self-rated focus.
    var focus: Int = 3

    init(subject: Subject?, startDate: Date, duration: TimeInterval, notes: String = "", focus: Int = 3) {
        self.subject = subject
        self.startDate = startDate
        self.duration = duration
        self.notes = notes
        self.focus = focus
    }
}

@Model
final class Goal {
    var title: String = ""
    var targetMinutes: Int = 60
    var periodRaw: String = GoalPeriod.weekly.rawValue
    var subject: Subject?
    var createdAt: Date = Date()

    init(title: String, targetMinutes: Int, period: GoalPeriod, subject: Subject?) {
        self.title = title
        self.targetMinutes = targetMinutes
        self.periodRaw = period.rawValue
        self.subject = subject
    }

    var period: GoalPeriod {
        get { GoalPeriod(rawValue: periodRaw) ?? .weekly }
        set { periodRaw = newValue.rawValue }
    }

    var target: TimeInterval { TimeInterval(targetMinutes * 60) }

    /// Time studied towards this goal within the current day / week.
    func progress(in sessions: [StudySession], now: Date = .now) -> TimeInterval {
        guard let interval = Calendar.current.dateInterval(of: period.component, for: now) else { return 0 }
        let goalSubject = subject?.persistentModelID
        return sessions
            .filter { interval.contains($0.startDate) && (goalSubject == nil || $0.subject?.persistentModelID == goalSubject) }
            .reduce(0) { $0 + $1.duration }
    }
}

/// Badges are permanent: once earned they are stored here and never taken away, even if the
/// numbers they were derived from later change (a weekly goal resets, a session is deleted…).
@Model
final class UnlockedBadge {
    var badgeID: String = ""
    var unlockedAt: Date = Date()

    init(badgeID: String, unlockedAt: Date = .now) {
        self.badgeID = badgeID
        self.unlockedAt = unlockedAt
    }
}

/// A freeze given to you (rather than earned by studying), e.g. a gift. Stored so it lands on a specific day
/// of your history and is included in backups.
@Model
final class FreezeGrant {
    var key: String = ""
    var grantedAt: Date = Date()
    var count: Int = 1
    var note: String = ""

    init(key: String, grantedAt: Date = .now, count: Int, note: String = "") {
        self.key = key
        self.grantedAt = grantedAt
        self.count = count
        self.note = note
    }
}
