import SwiftData
import SwiftUI

struct TimerView: View {
    @Query(sort: \Subject.name) private var subjects: [Subject]

    @State private var subject: Subject?
    @State private var sessionStart: Date?
    @State private var runStart: Date?
    @State private var accumulated: TimeInterval = 0
    @State private var isRunning = false

    @State private var showingSave = false
    @State private var finishedDuration: TimeInterval = 0

    private func elapsed(at date: Date) -> TimeInterval {
        accumulated + (isRunning ? date.timeIntervalSince(runStart ?? date) : 0)
    }

    private var hasProgress: Bool { isRunning || accumulated > 0 }

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
                        ProgressRing(progress: (value.truncatingRemainder(dividingBy: 3600)) / 3600,
                                     tint: subject?.color ?? .accentColor, lineWidth: 12)
                            .frame(width: 280, height: 280)
                        VStack(spacing: 4) {
                            Text(value.clock)
                                .font(.system(size: 56, weight: .light, design: .rounded))
                                .monospacedDigit()
                            Text(isRunning ? "Focusing…" : (hasProgress ? "Paused" : "Ready"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
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
                    .tint(subject?.color ?? .accentColor)

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
            .onAppear { if subject == nil { subject = subjects.first } }
            .sheet(isPresented: $showingSave, onDismiss: reset) {
                SessionFormView(subject: subject,
                                date: sessionStart ?? .now,
                                duration: finishedDuration)
            }
        }
    }

    private func toggle() {
        if isRunning {
            accumulated = elapsed(at: .now)
            runStart = nil
            isRunning = false
        } else {
            if sessionStart == nil { sessionStart = .now }
            runStart = .now
            isRunning = true
        }
    }

    private func finish() {
        finishedDuration = elapsed(at: .now)
        runStart = nil
        isRunning = false
        showingSave = true
    }

    private func reset() {
        isRunning = false
        runStart = nil
        sessionStart = nil
        accumulated = 0
    }
}

#Preview {
    TimerView().modelContainer(PreviewData.container)
}
