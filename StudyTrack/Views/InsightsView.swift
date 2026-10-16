import Charts
import SwiftData
import SwiftUI

struct InsightsView: View {
    @Query private var sessions: [StudySession]

    private struct SubjectTotal: Identifiable {
        let id: String
        let name: String
        let minutes: Double
        let color: Color
    }

    private struct WeekdayTotal: Identifiable {
        let id: Int
        let name: String
        let minutes: Double
    }

    private var subjectTotals: [SubjectTotal] {
        Dictionary(grouping: sessions) { $0.subject?.name ?? "Other" }
            .map { name, items in
                SubjectTotal(id: name, name: name,
                             minutes: items.reduce(0) { $0 + $1.duration } / 60,
                             color: items.first?.subject?.color ?? .gray)
            }
            .sorted { $0.minutes > $1.minutes }
    }

    private var weekdayTotals: [WeekdayTotal] {
        let cal = Calendar.current
        let byWeekday = Dictionary(grouping: sessions) { cal.component(.weekday, from: $0.startDate) }
        let symbols = cal.shortWeekdaySymbols
        return (0..<7).map { offset in
            let weekday = (cal.firstWeekday - 1 + offset) % 7 + 1
            let minutes = (byWeekday[weekday] ?? []).reduce(0) { $0 + $1.duration } / 60
            return WeekdayTotal(id: weekday, name: symbols[weekday - 1], minutes: minutes)
        }
    }

    private var averageFocus: Double {
        sessions.isEmpty ? 0 : Double(sessions.reduce(0) { $0 + $1.focus }) / Double(sessions.count)
    }

    private var totalSeconds: TimeInterval { sessions.reduce(0) { $0 + $1.duration } }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if sessions.isEmpty {
                    ContentUnavailableView("No data yet", systemImage: "chart.pie",
                                           description: Text("Log some sessions to see insights."))
                } else {
                    HStack(spacing: 12) {
                        StatTile(title: "Total time", value: totalSeconds.studyDuration,
                                 systemImage: "clock.fill", tint: .blue)
                        StatTile(title: "Sessions", value: "\(sessions.count)",
                                 systemImage: "checkmark.circle.fill", tint: .green)
                    }
                    HStack(spacing: 12) {
                        StatTile(title: "Avg focus", value: String(format: "%.1f ★", averageFocus),
                                 systemImage: "star.fill", tint: .yellow)
                        StatTile(title: "Avg session",
                                 value: (totalSeconds / Double(sessions.count)).studyDuration,
                                 systemImage: "timer", tint: .purple)
                    }
                    subjectCard
                    weekdayCard
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var subjectCard: some View {
        let totals = subjectTotals
        return VStack(alignment: .leading, spacing: 12) {
            Text("Time by subject").font(.headline)
            Chart(totals) { item in
                SectorMark(angle: .value("Minutes", item.minutes),
                           innerRadius: .ratio(0.62),
                           angularInset: 2)
                    .cornerRadius(4)
                    .foregroundStyle(item.color)
            }
            .frame(height: 200)
            ForEach(totals) { item in
                HStack {
                    Circle().fill(item.color).frame(width: 10, height: 10)
                    Text(item.name)
                    Spacer()
                    Text((item.minutes * 60).studyDuration).foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
        }
        .card()
    }

    private var weekdayCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Best days").font(.headline)
            Chart(weekdayTotals) { item in
                BarMark(x: .value("Day", item.name),
                        y: .value("Minutes", item.minutes))
                    .foregroundStyle(Color.accentColor.gradient)
                    .cornerRadius(4)
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let minutes = value.as(Double.self) { Text("\(Int(minutes / 60))h") }
                    }
                }
            }
            .frame(height: 160)
        }
        .card()
    }
}

#Preview {
    NavigationStack { InsightsView() }.modelContainer(PreviewData.container)
}
