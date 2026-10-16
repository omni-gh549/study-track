import Charts
import SwiftData
import SwiftUI

struct DashboardView: View {
    @Query(sort: \StudySession.startDate, order: .reverse) private var sessions: [StudySession]
    @Query private var goals: [Goal]
    @AppStorage("dailyGoalMinutes") private var fallbackDailyMinutes = 60
    @AppStorage("lastBackup") private var lastBackup: Double = 0
    @State private var showingAdd = false
    @State private var showingSettings = false

    private var calendar: Calendar { .current }

    // MARK: Derived data

    private var todayTotal: TimeInterval {
        sessions.filter { calendar.isDateInToday($0.startDate) }.reduce(0) { $0 + $1.duration }
    }

    private var weekStart: Date {
        calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: .now)) ?? .now
    }

    private var weekTotal: TimeInterval {
        sessions.filter { $0.startDate >= weekStart }.reduce(0) { $0 + $1.duration }
    }

    private var dailyTargetMinutes: Int {
        goals.first { $0.period == .daily && $0.subject == nil }?.targetMinutes ?? fallbackDailyMinutes
    }

    private var streak: Int {
        let days = Set(sessions.map { calendar.startOfDay(for: $0.startDate) })
        var day = calendar.startOfDay(for: .now)
        if !days.contains(day) {
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        var count = 0
        while days.contains(day) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? .distantPast
        }
        return count
    }

    private struct DayPoint: Identifiable {
        let id = UUID()
        let day: Date
        let subject: String
        let minutes: Double
    }

    private var weekPoints: [DayPoint] {
        let recent = sessions.filter { $0.startDate >= weekStart }
        let byDay = Dictionary(grouping: recent) { calendar.startOfDay(for: $0.startDate) }
        return byDay.flatMap { day, daySessions in
            Dictionary(grouping: daySessions) { $0.subject?.name ?? "Other" }
                .map { name, items in
                    DayPoint(day: day, subject: name, minutes: items.reduce(0) { $0 + $1.duration } / 60)
                }
        }
    }

    private var legend: [(name: String, color: Color)] {
        var seen: [String: Color] = [:]
        for s in sessions where s.startDate >= weekStart {
            seen[s.subject?.name ?? "Other"] = s.subject?.color ?? .gray
        }
        return seen.map { (name: $0.key, color: $0.value) }.sorted { $0.name < $1.name }
    }

    private var needsBackup: Bool {
        sessions.count >= 5 && Date.now.timeIntervalSince1970 - lastBackup > 14 * 86_400
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if needsBackup { backupNudge }
                    todayCard
                    LevelCard(info: GameEngine.snapshot(sessions: sessions, goals: goals).level, streak: streak)
                    QuestsCard(sessions: sessions)
                    HStack(spacing: 12) {
                        StatTile(title: "Streak", value: "\(streak) \(streak == 1 ? "day" : "days")",
                                 systemImage: "flame.fill", tint: .orange)
                        StatTile(title: "Last 7 days", value: weekTotal.studyDuration,
                                 systemImage: "calendar", tint: .indigo)
                    }
                    chartCard
                    recentCard
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Session", systemImage: "plus") { showingAdd = true }
                }
            }
            .sheet(isPresented: $showingAdd) { SessionFormView() }
            .sheet(isPresented: $showingSettings) { SettingsView() }
        }
    }

    private var backupNudge: some View {
        Button { showingSettings = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "externaldrive.fill.badge.icloud")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Back up your data").font(.subheadline.weight(.semibold))
                    Text(lastBackup == 0 ? "You haven't made a backup yet." : "It's been a while since your last backup.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary)
            .card()
        }
        .buttonStyle(.plain)
    }

    private var todayCard: some View {
        let target = TimeInterval(dailyTargetMinutes * 60)
        let progress = target > 0 ? todayTotal / target : 0
        return HStack(spacing: 20) {
            ProgressRing(progress: progress, tint: progress >= 1 ? .green : .accentColor)
                .frame(width: 104, height: 104)
                .overlay {
                    Image(systemName: progress >= 1 ? "checkmark" : "book.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(progress >= 1 ? Color.green : Color.accentColor)
                }
            VStack(alignment: .leading, spacing: 4) {
                Text("Studied today")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(todayTotal.studyDuration)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text("of \(target.studyDuration) daily goal")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This week").font(.headline)
            if weekPoints.isEmpty {
                ContentUnavailableView("No sessions yet", systemImage: "chart.bar",
                                       description: Text("Log a session to see your week."))
                    .frame(height: 180)
            } else {
                Chart(weekPoints) { point in
                    BarMark(
                        x: .value("Day", point.day, unit: .day),
                        y: .value("Minutes", point.minutes)
                    )
                    .foregroundStyle(by: .value("Subject", point.subject))
                    .cornerRadius(3)
                }
                .chartForegroundStyleScale(domain: legend.map(\.name), range: legend.map(\.color))
                .chartXScale(domain: weekStart...(calendar.date(byAdding: .day, value: 1,
                                                                 to: calendar.startOfDay(for: .now)) ?? .now))
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let minutes = value.as(Double.self) {
                                Text("\(Int(minutes / 60))h")
                            }
                        }
                    }
                }
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 200)
            }
        }
        .card()
    }

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent").font(.headline)
            ForEach(Array(sessions.prefix(3))) { session in
                SessionRow(session: session)
            }
            if sessions.isEmpty {
                Text("Nothing logged yet.").foregroundStyle(.secondary)
            }
        }
        .card()
    }
}

#Preview {
    DashboardView().modelContainer(PreviewData.container)
}
