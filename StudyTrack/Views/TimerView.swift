import SwiftData
import SwiftUI

/// Timer state lives in `TimerModel` → `TimerState`, is written to disk (fsync'd) on every change, and all
/// time is derived from timestamps — so it survives backgrounding, the app being killed, and the phone
/// being switched off and on again. Works as a plain stopwatch or as a Pomodoro timer.
struct TimerView: View {
    @Environment(TimerModel.self) private var timer
    @Query(sort: \Subject.name) private var subjects: [Subject]

    @State private var subject: Subject?
    @State private var showingSave = false
    @State private var showingPomodoroSettings = false
    @State private var finishedDuration: TimeInterval = 0

    private var state: TimerState { timer.state }
    private var tint: Color {
        if state.isPomodoro && state.phase.isBreak { return .green }
        return subject?.color ?? .accentColor
    }

    private var modeBinding: Binding<TimerMode> {
        Binding(get: { timer.state.mode }, set: { new in timer.update { $0.mode = new } })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    if timer.persistenceFailing {
                        Label("This device won't let StudyTrack save the timer. It keeps running, but keep the app open until you finish.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("timer.persistenceWarning")
                    }

                    Picker("Mode", selection: modeBinding) {
                        ForEach(TimerMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(state.hasProgress)
                    .accessibilityIdentifier("timer.mode")

                    subjectPicker

                    if state.isPomodoro { pomodoroHeader }

                    clock

                    if state.isPomodoro && state.awaitingNext { phaseCompleteCard }

                    controls
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("Timer")
            .toolbar {
                if state.isPomodoro {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Pomodoro Settings", systemImage: "slider.horizontal.3") {
                            showingPomodoroSettings = true
                        }
                    }
                }
            }
            .sensoryFeedback(.impact, trigger: state.isRunning)
            .sensoryFeedback(.success, trigger: timer.phaseCompletions)
            .onAppear {
                timer.reload()
                subject = subjects.first { $0.name == timer.state.subjectName } ?? subjects.first
            }
            .onChange(of: subject) { _, new in
                let name = new?.name ?? ""
                if name != timer.state.subjectName {
                    timer.update {
                        $0.subjectName = name
                        $0.subjectIcon = new?.icon ?? "book.fill"
                        $0.subjectColor = new?.colorRaw ?? "blue"
                    }
                }
            }
            .sheet(isPresented: $showingSave) {
                SessionFormView(subject: subject,
                                date: timer.state.sessionStart ?? .now,
                                duration: finishedDuration,
                                onSaved: { timer.update { $0.reset() } })
            }
            .sheet(isPresented: $showingPomodoroSettings) { PomodoroSettingsView() }
        }
    }

    // MARK: Pieces

    private var subjectPicker: some View {
        VStack(spacing: 6) {
            Picker("Subject", selection: $subject) {
                Text("No subject").tag(Subject?.none)
                ForEach(subjects) { s in
                    Label(s.name, systemImage: s.icon).tag(Optional(s))
                }
            }
            .pickerStyle(.menu)
            .buttonStyle(.bordered)
            .disabled(state.hasProgress)

            if subjects.isEmpty {
                Text("Add subjects under History › Subjects to organise your sessions.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var pomodoroHeader: some View {
        let per = max(state.config.blocksBeforeLongBreak, 1)
        let done = LiveActivityController.blocksDoneInCycle(state)
        let capsule = Text(state.phase.title)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
            .accessibilityIdentifier("timer.phase")
        // Running total, so the 5th block reads "Block 5" instead of wrapping back to "Block 1 of 4".
        // The dots below show where you are within the current set.
        let blockNumber = state.phase == .focus ? state.completedBlocks + 1 : state.completedBlocks
        let setNumber = (max(blockNumber, 1) - 1) / per + 1
        let blockLabel = state.phase == .focus ? "Block \(blockNumber)" : "Block \(blockNumber) done"
        let blockText = Text(setNumber > 1 ? "\(blockLabel) · Set \(setNumber)" : blockLabel)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        return VStack(spacing: 8) {
            // At very large text sizes the label drops below the capsule instead of squeezing it.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { capsule; blockText }
                VStack(spacing: 6) { capsule; blockText }
            }
            HStack(spacing: 6) {
                ForEach(0..<per, id: \.self) { i in
                    Circle()
                        .fill(i < done ? tint : tint.opacity(0.22))
                        .frame(width: 9, height: 9)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(done) of \(per) focus blocks done in this set")
        }
    }

    private var clock: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let s = state.resolved(at: context.date)
            let value: TimeInterval = s.isPomodoro ? s.phaseRemaining(at: context.date).rounded(.up)
                                                   : s.elapsed(at: context.date)
            let progress: Double = s.isPomodoro
                ? s.phaseElapsed(at: context.date) / max(s.phaseDuration, 1)
                : value.truncatingRemainder(dividingBy: 3600) / 3600
            let focusTime = s.elapsed(at: context.date)

            ZStack {
                ProgressRing(progress: progress, tint: tint, lineWidth: 12)
                VStack(spacing: 8) {
                    Text(value.clock)
                        .font(.system(size: 56, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .accessibilityIdentifier("timer.display")
                    Text(statusText(s))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    Label("+\(GameEngine.previewXP(seconds: focusTime)) XP", systemImage: "bolt.fill")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.yellow.opacity(0.2), in: Capsule())
                        .opacity(focusTime >= 60 ? 1 : 0)
                }
                .padding(.horizontal, 28)
            }
            .frame(maxWidth: 280)
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
        }
    }

    private func statusText(_ s: TimerState) -> String {
        if s.isPomodoro {
            if s.awaitingNext { return s.phase == .focus ? "Ready to focus" : "Time for a break" }
            if s.isRunning { return s.phase == .focus ? "Focusing…" : "Resting…" }
            return s.phaseBase > 0 ? "Paused" : "Ready"
        }
        return s.isRunning ? "Focusing…" : (s.hasProgress ? "Paused" : "Ready")
    }

    private var phaseCompleteCard: some View {
        let minutes = Int((state.phaseDuration / PomodoroConfig.secondsPerMinute).rounded())
        let ended = state.phase == .focus ? "Break over" : "Focus block complete 🎉"
        let next = state.phase == .focus ? "Start your next focus block when you're ready."
                                         : "Take \(minutes) minute\(minutes == 1 ? "" : "s") to rest."
        return VStack(spacing: 4) {
            Text(ended).font(.headline)
            Text(next).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("timer.phaseComplete")
    }

    private var primaryTitle: String {
        if state.isRunning { return "Pause" }
        if state.isPomodoro {
            if state.awaitingNext { return state.phase == .focus ? "Start focus" : "Start break" }
            return state.phaseBase > 0 ? "Resume" : "Start"
        }
        return state.accumulated > 0 ? "Resume" : "Start"
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Button { primaryAction() } label: {
                Label(primaryTitle, systemImage: state.isRunning ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .buttonStyle(.borderedProminent)
            .tint(tint)

            HStack(spacing: 10) {
                Button(role: .destructive) { timer.update { $0.reset() } } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .buttonStyle(.bordered)
                .disabled(!state.hasProgress)

                if state.isPomodoro && state.phase.isBreak {
                    Button { timer.update { $0.skipBreak(at: .now) } } label: {
                        Label("Skip break", systemImage: "forward.fill")
                            .frame(maxWidth: .infinity)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .buttonStyle(.bordered)
                }

                Button { finish() } label: {
                    Label("Finish", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .buttonStyle(.bordered)
                .tint(.green)
                .disabled(!state.hasProgress)
            }
        }
        .controlSize(.large)
    }

    // MARK: Actions

    private func primaryAction() {
        if state.isRunning {
            timer.update { $0.pause(at: .now) }
        } else {
            if state.isPomodoro { Task { await PhaseAlerts.requestAuthorizationIfNeeded() } }
            timer.update { $0.start(at: .now) }
        }
    }

    private func finish() {
        timer.update { $0.pause(at: .now) }
        finishedDuration = timer.state.accumulated
        if finishedDuration < 1 {
            timer.update { $0.reset() }   // nothing studied, nothing to save
        } else {
            showingSave = true
        }
    }
}

#Preview {
    TimerView()
        .modelContainer(PreviewData.container)
        .environment(TimerModel())
}
