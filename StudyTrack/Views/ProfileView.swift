import SwiftData
import SwiftUI

struct ProfileView: View {
    @Query(sort: \StudySession.startDate, order: .reverse) private var sessions: [StudySession]
    @Query private var goals: [Goal]
    @Query private var badges: [UnlockedBadge]
    @State private var showingSettings = false
    @State private var selected: AchievementDef?

    private var snapshot: GameSnapshot {
        GameEngine.snapshot(sessions: sessions, goals: goals, stored: Set(badges.map(\.badgeID)))
    }

    var body: some View {
        let snap = snapshot
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    LevelCard(info: snap.level, streak: snap.stats.currentStreak, large: true)

                    HStack(spacing: 12) {
                        StatTile(title: "Total XP", value: "\(snap.stats.xp)",
                                 systemImage: "bolt.fill", tint: .yellow)
                        StatTile(title: "Best streak", value: "\(snap.stats.bestStreak) days",
                                 systemImage: "flame.fill", tint: .orange)
                    }

                    QuestsCard(sessions: sessions)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Last 12 weeks").font(.headline)
                        ActivityHeatmap(sessions: sessions)
                    }
                    .card()

                    NavigationLink {
                        InsightsView()
                    } label: {
                        HStack {
                            Label("Insights", systemImage: "chart.pie.fill").font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .foregroundStyle(.primary)
                        .card()
                    }
                    .buttonStyle(.plain)

                    achievementsCard(snap)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Settings", systemImage: "gearshape") { showingSettings = true }
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(item: $selected) { def in
                AchievementDetail(def: def, stats: snap.stats)
            }
        }
    }

    private func achievementsCard(_ snap: GameSnapshot) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Badges").font(.headline)
                Spacer()
                Text("\(snap.unlocked.count)/\(GameEngine.achievements.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(GameEngine.achievements) { def in
                    let unlocked = snap.unlocked.contains(def.id)
                    Button { selected = def } label: {
                        VStack(spacing: 6) {
                            Image(systemName: unlocked ? def.symbol : "lock.fill")
                                .font(.title2)
                                .foregroundStyle(unlocked ? Color.white : Color.secondary)
                                .frame(width: 56, height: 56)
                                .background(unlocked ? AnyShapeStyle(def.tint.gradient)
                                                     : AnyShapeStyle(Color(.tertiarySystemFill)),
                                            in: Circle())
                            Text(def.title)
                                .font(.caption.weight(.medium))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .foregroundStyle(unlocked ? Color.primary : Color.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .card()
    }
}

struct AchievementDetail: View {
    let def: AchievementDef
    let stats: PlayerStats
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let unlocked = def.isUnlocked(stats)
        VStack(spacing: 14) {
            Image(systemName: unlocked ? def.symbol : "lock.fill")
                .font(.system(size: 44))
                .foregroundStyle(unlocked ? Color.white : Color.secondary)
                .frame(width: 100, height: 100)
                .background(unlocked ? AnyShapeStyle(def.tint.gradient) : AnyShapeStyle(Color(.tertiarySystemFill)),
                            in: Circle())
                .padding(.top, 24)
            Text(def.title).font(.title2.bold())
            Text(def.detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if unlocked {
                Label("Unlocked", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            } else {
                VStack(spacing: 6) {
                    ProgressView(value: def.progress(stats)).tint(def.tint)
                    Text(def.progressText(stats)).font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 40)
            }
            Spacer()
        }
        .padding()
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

struct ActivityHeatmap: View {
    let sessions: [StudySession]
    private let weeks = 12

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let start = cal.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek) ?? today
        let minutesByDay = Dictionary(grouping: sessions) { cal.startOfDay(for: $0.startDate) }
            .mapValues { $0.reduce(0) { $0 + $1.duration } / 60 }

        HStack(spacing: 4) {
            ForEach(0..<weeks, id: \.self) { col in
                VStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { row in
                        let day = cal.date(byAdding: .day, value: col * 7 + row, to: start) ?? start
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(color(for: day > today ? nil : minutesByDay[day] ?? 0))
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
    }

    private func color(for minutes: Double?) -> Color {
        guard let minutes else { return .clear }
        switch minutes {
        case 0: return Color(.tertiarySystemFill)
        case ..<30: return Color.accentColor.opacity(0.3)
        case ..<60: return Color.accentColor.opacity(0.55)
        case ..<120: return Color.accentColor.opacity(0.8)
        default: return Color.accentColor
        }
    }
}

#Preview {
    ProfileView().modelContainer(PreviewData.container)
}
