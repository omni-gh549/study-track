import SwiftUI

// MARK: - Confetti

struct ConfettiView: View {
    private struct Piece: Identifiable {
        let id: Int
        let x: CGFloat
        let delay: Double
        let color: Color
        let size: CGFloat
        let spin: Double
        let drift: CGFloat
    }

    private static let palette: [Color] = [.blue, .purple, .pink, .orange, .yellow, .green, .mint]

    private let pieces: [Piece] = (0..<70).map { i in
        Piece(id: i,
              x: .random(in: 0...1),
              delay: .random(in: 0...0.5),
              color: ConfettiView.palette.randomElement() ?? .blue,
              size: .random(in: 6...11),
              spin: .random(in: 180...720),
              drift: .random(in: -60...60))
    }

    @State private var fall = false

    var body: some View {
        GeometryReader { geo in
            ForEach(pieces) { p in
                RoundedRectangle(cornerRadius: 2)
                    .fill(p.color)
                    .frame(width: p.size, height: p.size * 1.6)
                    .rotationEffect(.degrees(fall ? p.spin : 0))
                    .position(x: p.x * geo.size.width + (fall ? p.drift : 0),
                              y: fall ? geo.size.height + 40 : -20)
                    .animation(.easeIn(duration: 2.4).delay(p.delay), value: fall)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .onAppear { fall = true }
    }
}

// MARK: - Celebration banner

struct CelebrationOverlay: View {
    let center: CelebrationCenter

    var body: some View {
        ZStack(alignment: .top) {
            if let c = center.current {
                if c.isBig {
                    ConfettiView().id(c.id)
                }
                CelebrationBanner(celebration: c)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { center.dismiss() }
                    .task(id: c.id) {
                        try? await Task.sleep(for: .seconds(c.isBig ? 5 : 3))
                        center.dismiss(id: c.id)
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(duration: 0.5), value: center.current?.id)
        .sensoryFeedback(.success, trigger: center.current?.id)
    }
}

private struct CelebrationBanner: View {
    let celebration: Celebration

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill").foregroundStyle(.yellow)
                Text("+\(celebration.xpGained) XP")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Spacer()
                Text("Session saved").font(.footnote).foregroundStyle(.secondary)
            }
            if let level = celebration.newLevel {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.circle.fill").foregroundStyle(.purple)
                    Text("Level \(level.level) · \(level.title)").font(.headline)
                }
            }
            ForEach(celebration.achievements) { a in
                HStack(spacing: 10) {
                    Image(systemName: a.symbol)
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(a.tint.gradient, in: Circle())
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Badge unlocked").font(.caption2).foregroundStyle(.secondary)
                        Text(a.title).font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
    }
}

// MARK: - Level card

struct LevelCard: View {
    let info: LevelInfo
    var streak: Int
    var large = false

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                ProgressRing(progress: info.progress, tint: .purple, lineWidth: large ? 12 : 8)
                VStack(spacing: 0) {
                    Text("LV").font(.system(size: large ? 12 : 9, weight: .bold)).foregroundStyle(.secondary)
                    Text("\(info.level)")
                        .font(.system(size: large ? 38 : 24, weight: .bold, design: .rounded))
                }
            }
            .frame(width: large ? 104 : 64, height: large ? 104 : 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(info.title).font(large ? .title2.bold() : .headline)
                Text("\(info.xpIntoLevel) / \(info.xpForNext) XP to level \(info.level + 1)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if streak > 0 {
                    Label("\(streak)-day streak", systemImage: "flame.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
        }
        .card()
    }
}

// MARK: - Quests

struct QuestsCard: View {
    let sessions: [StudySession]

    var body: some View {
        let quests = GameEngine.quests(for: .now, sessions: sessions)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Daily quests").font(.headline)
                Spacer()
                Text("\(quests.filter(\.done).count)/\(quests.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ForEach(quests) { q in
                HStack(spacing: 12) {
                    Image(systemName: q.done ? "checkmark.circle.fill" : q.symbol)
                        .font(.title3)
                        .foregroundStyle(q.done ? Color.green : Color.accentColor)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(q.title)
                            .font(.subheadline.weight(.medium))
                            .strikethrough(q.done, color: .secondary)
                        ProgressView(value: q.fraction).tint(q.done ? .green : .accentColor)
                        Text(q.caption).font(.caption).foregroundStyle(.secondary)
                    }
                    Text("+\(GameEngine.questBonus)")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.yellow.opacity(q.done ? 0.35 : 0.15), in: Capsule())
                }
            }
        }
        .card()
    }
}

// MARK: - Streak & freezes

struct StreakCard: View {
    let streak: StreakResult

    private var explanation: String {
        if streak.freezes >= StreakEngine.maxFreezes {
            return "You're holding the maximum of \(StreakEngine.maxFreezes) freezes. One is used automatically if you miss a day."
        }
        let n = streak.daysToNextFreeze
        return "Next freeze after \(n) more day\(n == 1 ? "" : "s") of studying in a row. One is used automatically if you miss a day."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Streak", systemImage: "flame.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Spacer()
                Text("\(streak.current) \(streak.current == 1 ? "day" : "days")")
                    .font(.headline.monospacedDigit())
            }
            if streak.atRisk {
                Label(streak.freezes > 0
                      ? "Study today to extend it — a freeze will protect you if you miss."
                      : "Study today to keep it alive — you have no freezes left.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            Divider()
            HStack {
                Text("Streak freezes").font(.subheadline.weight(.semibold))
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0..<StreakEngine.maxFreezes, id: \.self) { i in
                        Image(systemName: "snowflake")
                            .font(.title3)
                            .foregroundStyle(i < streak.freezes ? Color.cyan : Color.secondary.opacity(0.3))
                    }
                }
            }
            Text(explanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if !streak.frozenDays.isEmpty {
                let recent = streak.frozenDays.suffix(3).map { $0.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) }
                Text("Frozen days: " + recent.joined(separator: ", "))
                    .font(.footnote)
                    .foregroundStyle(.cyan)
            }
        }
        .card()
    }
}
