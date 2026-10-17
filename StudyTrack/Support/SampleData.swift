import SwiftData
import SwiftUI

/// Demo content so the concept looks alive on first launch.
/// Delete the `seedIfNeeded` call in `RootView` to start with an empty app.
enum SampleData {
    @MainActor
    static func seed(_ context: ModelContext) {
        guard (try? context.fetchCount(FetchDescriptor<Subject>())) == 0 else { return }

        let maths = Subject(name: "Mathematics", color: .blue, icon: "function")
        let physics = Subject(name: "Physics", color: .purple, icon: "atom")
        let lit = Subject(name: "Literature", color: .orange, icon: "character.book.closed.fill")
        let code = Subject(name: "Programming", color: .green, icon: "laptopcomputer")
        let subjects = [maths, physics, lit, code]
        for subject in subjects { context.insert(subject) }

        // (subject, minutes, hour of day, days ago, focus, note)
        let plan: [(Int, Int, Int, Int, Int, String)] = [
            (0, 60, 9, 0, 4, "Integration by parts"),
            (1, 45, 14, 0, 3, "Chapter 7 problem set"),
            (3, 50, 19, 1, 5, "SwiftUI layout deep dive"),
            (0, 90, 10, 1, 4, "Past paper, section B"),
            (2, 40, 16, 2, 3, "Reading: Middlemarch ch. 12"),
            (1, 75, 11, 3, 5, "Electromagnetism revision"),
            (3, 60, 20, 3, 4, "Data structures"),
            (0, 45, 9, 4, 3, "Linear algebra flashcards"),
            (2, 55, 15, 5, 4, "Essay outline"),
            (1, 80, 10, 6, 5, "Lab report"),
            (3, 35, 18, 6, 2, "Debugging practice"),
            (0, 70, 9, 8, 4, "Differential equations"),
            (2, 45, 17, 9, 3, "Poetry analysis"),
        ]

        let cal = Calendar.current
        for (subjectIndex, minutes, hour, daysAgo, focus, note) in plan {
            let day = cal.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
            let start = min(cal.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day, .now)
            context.insert(StudySession(subject: subjects[subjectIndex],
                                        startDate: start,
                                        duration: TimeInterval(minutes * 60),
                                        notes: note,
                                        focus: focus))
        }

        context.insert(Goal(title: "Study every day", targetMinutes: 90, period: .daily, subject: nil))
        context.insert(Goal(title: "Weekly study time", targetMinutes: 600, period: .weekly, subject: nil))
        context.insert(Goal(title: "Master calculus", targetMinutes: 240, period: .weekly, subject: maths))
        context.insert(Goal(title: "Ship a side project", targetMinutes: 180, period: .weekly, subject: code))
        context.commit()
        GameEngine.syncBadges(context: context)
    }
}

@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        let container = try! ModelContainer(
            for: Persistence.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        SampleData.seed(container.mainContext)
        return container
    }()
}
