import SwiftData
import SwiftUI

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    let onFinish: () -> Void

    private struct Preset: Identifiable {
        let name: String
        let color: SubjectColor
        let icon: String
        var id: String { name }
    }

    private let presets: [Preset] = [
        Preset(name: "Mathematics", color: .blue, icon: "function"),
        Preset(name: "Science", color: .purple, icon: "atom"),
        Preset(name: "Languages", color: .orange, icon: "character.book.closed.fill"),
        Preset(name: "History", color: .red, icon: "globe.europe.africa.fill"),
        Preset(name: "Programming", color: .green, icon: "laptopcomputer"),
        Preset(name: "Art", color: .pink, icon: "paintpalette.fill"),
        Preset(name: "Music", color: .teal, icon: "music.note"),
        Preset(name: "Literature", color: .indigo, icon: "book.fill"),
        Preset(name: "Business", color: .mint, icon: "chart.bar.fill"),
    ]

    @State private var selected: Set<String> = []
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.white)
                    .frame(width: 104, height: 104)
                    .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .padding(.top, 32)

                VStack(spacing: 6) {
                    Text("Welcome to StudyTrack").font(.largeTitle.bold()).multilineTextAlignment(.center)
                    Text("Track study sessions, hit goals and level up.")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 14) {
                    feature("timer", "Time your sessions", "Run the timer or log them by hand.")
                    feature("target", "Set daily & weekly goals", "See your progress at a glance.")
                    feature("trophy.fill", "Earn XP and badges", "Build streaks and complete daily quests.")
                    feature("lock.shield.fill", "Your data stays on this phone", "Back it up any time from Profile › Settings.")
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("What are you studying?").font(.headline)
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(presets) { p in
                            let on = selected.contains(p.name)
                            Button {
                                if on { selected.remove(p.name) } else { selected.insert(p.name) }
                            } label: {
                                Label(p.name, systemImage: p.icon)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .foregroundStyle(on ? Color.white : Color.primary)
                                    .background(on ? AnyShapeStyle(p.color.color.gradient)
                                                   : AnyShapeStyle(Color(.tertiarySystemFill)),
                                                in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text("You can add, rename or remove subjects later.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                VStack(spacing: 10) {
                    Button { start() } label: {
                        Text(selected.isEmpty ? "Start empty" : "Get started").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Explore with sample data") {
                        SampleData.seed(context)
                        onFinish()
                    }
                    .font(.subheadline)
                }
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
        }
        .interactiveDismissDisabled()
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func start() {
        for p in presets where selected.contains(p.name) {
            context.insert(Subject(name: p.name, color: p.color, icon: p.icon))
        }
        context.commit()
        onFinish()
    }
}

#Preview {
    OnboardingView {}.modelContainer(PreviewData.container)
}
