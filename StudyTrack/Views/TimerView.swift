import SwiftData
import SwiftUI

/// Timer state lives in `TimerState`, is written to disk (fsync'd) on every change, and all time is
/// derived from timestamps — so it survives backgrounding, the app being killed, and the phone
/// being switched off and on again.
struct TimerView: View {
    @Query(sort: \Subject.name) private var subjects: [Subject]

    @State private var state = TimerStore.load()
    @State private var subject: Subject?
    @State private var showingSave = false
    @State private var finishedDuration: TimeInterval = 0

    private var tint: Color { subject?.color ?? .accentColor }

    private func update(_ change: (inout TimerState) -> Void) {
        change(&state)
        TimerStore.save(state)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Picker("Subject", selection: $subject) {
                    Text("No subject").tag(Subject?.none)
                    ForEach(subjects) { s in
                        Label(s.name, systemImage: s.icon).tag(Optional(s))
                    }
                }
                .pickerStyle(.menu)
                .buttonStyle(.bordered)
                .disabled(state.hasProgress)

                Spacer()

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let value = state.elapsed(at: context.date)
                    ZStack {
                        ProgressRing(progress: value.truncatingRemainder(dividingBy: 3600) / 3600,
                                     tint: tint, lineWidth: 12)
                            .frame(width: 280, height: 280)
                        VStack(spacing: 8) {
                            Text(value.clock)
                                .font(.system(size: 56, weight: .light, design: .rounded))
                                .monospacedDigit()
                                .accessibilityIdentifier("timer.display")
                            Text(state.isRunning ? "Focusing…" : (state.hasProgress ? "Paused" : "Ready"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Label("+\(GameEngine.previewXP(seconds: value)) XP", systemImage: "bolt.fill")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Color.yellow.opacity(0.2), in: Capsule())
                                .opacity(value >= 60 ? 1 : 0)
                        }
                    }
                }

                Spacer()

                HStack(spacing: 16) {
                    Button(role: .destructive) { update { $0.reset() } } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!state.hasProgress)

                    Button { toggle() } label: {
                        Label(state.isRunning ? "Pause" : (state.accumulated > 0 ? "Resume" : "Start"),
                              systemImage: state.isRunning ? "pause.fill" : "play.fill")
                            .frame(minWidth: 110)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)

                    Button { finish() } label: {
                        Label("Finish", systemImage: "checkmark")
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                    .disabled(!state.hasProgress)
                }
                .controlSize(.large)
                .padding(.bottom, 24)
            }
            .padding()
            .navigationTitle("Timer")
            .sensoryFeedback(.impact, trigger: state.isRunning)
            .onAppear {
                // Re-read from disk in case the view was recreated; restore the chosen subject.
                state = TimerStore.load()
                subject = subjects.first { $0.name == state.subjectName } ?? subjects.first
            }
            .onChange(of: subject) { _, new in
                let name = new?.name ?? ""
                if name != state.subjectName { update { $0.subjectName = name } }
            }
            .sheet(isPresented: $showingSave) {
                SessionFormView(subject: subject,
                                date: state.sessionStart ?? .now,
                                duration: finishedDuration,
                                onSaved: { update { $0.reset() } })
            }
        }
    }

    private func toggle() {
        if state.isRunning {
            update { $0.pause(at: .now) }
        } else {
            update { $0.start(at: .now) }
        }
    }

    private func finish() {
        update { $0.pause(at: .now) }
        finishedDuration = state.accumulated
        showingSave = true
    }
}

#Preview {
    TimerView().modelContainer(PreviewData.container)
}
