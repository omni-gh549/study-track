import SwiftData
import SwiftUI

/// The running state lives in `@AppStorage`, so the timer survives the app being
/// backgrounded or killed — elapsed time is always derived from timestamps.
struct TimerView: View {
    @Query(sort: \Subject.name) private var subjects: [Subject]

    @AppStorage("timer.runStart") private var runStartTS: Double = 0
    @AppStorage("timer.accumulated") private var accumulated: Double = 0
    @AppStorage("timer.sessionStart") private var sessionStartTS: Double = 0
    @AppStorage("timer.subject") private var subjectName: String = ""

    @State private var subject: Subject?
    @State private var showingSave = false
    @State private var finishedDuration: TimeInterval = 0

    private var isRunning: Bool { runStartTS > 0 }
    private var hasProgress: Bool { isRunning || accumulated > 0 }
    private var tint: Color { subject?.color ?? .accentColor }

    private func elapsed(at date: Date) -> TimeInterval {
        accumulated + (isRunning ? max(date.timeIntervalSince1970 - runStartTS, 0) : 0)
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
                .disabled(hasProgress)

                Spacer()

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let value = elapsed(at: context.date)
                    ZStack {
                        ProgressRing(progress: value.truncatingRemainder(dividingBy: 3600) / 3600,
                                     tint: tint, lineWidth: 12)
                            .frame(width: 280, height: 280)
                        VStack(spacing: 8) {
                            Text(value.clock)
                                .font(.system(size: 56, weight: .light, design: .rounded))
                                .monospacedDigit()
                            Text(isRunning ? "Focusing…" : (hasProgress ? "Paused" : "Ready"))
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
                    Button(role: .destructive) { reset() } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!hasProgress)

                    Button { toggle() } label: {
                        Label(isRunning ? "Pause" : (accumulated > 0 ? "Resume" : "Start"),
                              systemImage: isRunning ? "pause.fill" : "play.fill")
                            .frame(minWidth: 110)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)

                    Button { finish() } label: {
                        Label("Finish", systemImage: "checkmark")
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                    .disabled(!hasProgress)
                }
                .controlSize(.large)
                .padding(.bottom, 24)
            }
            .padding()
            .navigationTitle("Timer")
            .sensoryFeedback(.impact, trigger: isRunning)
            .onAppear {
                subject = subjects.first { $0.name == subjectName } ?? subjects.first
            }
            .onChange(of: subject) { _, new in subjectName = new?.name ?? "" }
            .sheet(isPresented: $showingSave) {
                SessionFormView(subject: subject,
                                date: sessionStartTS > 0 ? Date(timeIntervalSince1970: sessionStartTS) : .now,
                                duration: finishedDuration,
                                onSaved: reset)
            }
        }
    }

    private func toggle() {
        if isRunning {
            accumulated = elapsed(at: .now)
            runStartTS = 0
        } else {
            if sessionStartTS == 0 { sessionStartTS = Date.now.timeIntervalSince1970 }
            runStartTS = Date.now.timeIntervalSince1970
        }
    }

    private func finish() {
        accumulated = elapsed(at: .now)
        runStartTS = 0
        finishedDuration = accumulated
        showingSave = true
    }

    private func reset() {
        runStartTS = 0
        sessionStartTS = 0
        accumulated = 0
    }
}

#Preview {
    TimerView().modelContainer(PreviewData.container)
}
