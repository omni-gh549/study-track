import SwiftUI

struct PomodoroSettingsView: View {
    @Environment(TimerModel.self) private var timer
    @Environment(\.dismiss) private var dismiss

    private var locked: Bool { timer.state.hasProgress }

    private func binding(_ keyPath: WritableKeyPath<PomodoroConfig, Int>) -> Binding<Int> {
        Binding(get: { timer.state.config[keyPath: keyPath] },
                set: { value in
                    timer.update {
                        var config = $0.config
                        config[keyPath: keyPath] = value
                        $0.config = config.clamped()
                    }
                })
    }

    private func apply(_ focus: Int, _ short: Int, _ long: Int) {
        timer.update {
            $0.config.focusMinutes = focus
            $0.config.shortBreakMinutes = short
            $0.config.longBreakMinutes = long
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if locked {
                    Section {
                        Label("Finish or reset the current run to change these.", systemImage: "lock.fill")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Presets") {
                    Button("Classic · 25 / 5 / 15") { apply(25, 5, 15) }
                    Button("Deep work · 50 / 10 / 30") { apply(50, 10, 30) }
                    Button("Quick · 15 / 3 / 10") { apply(15, 3, 10) }
                }
                .disabled(locked)

                Section {
                    Stepper(value: binding(\.focusMinutes), in: 1...180) {
                        LabeledContent("Focus", value: "\(timer.state.config.focusMinutes) min")
                    }
                    Stepper(value: binding(\.shortBreakMinutes), in: 1...60) {
                        LabeledContent("Short break", value: "\(timer.state.config.shortBreakMinutes) min")
                    }
                    Stepper(value: binding(\.longBreakMinutes), in: 1...120) {
                        LabeledContent("Long break", value: "\(timer.state.config.longBreakMinutes) min")
                    }
                    Stepper(value: binding(\.blocksBeforeLongBreak), in: 2...8) {
                        LabeledContent("Long break after", value: "\(timer.state.config.blocksBeforeLongBreak) blocks")
                    }
                } header: {
                    Text("Durations")
                } footer: {
                    Text("Only focus time is added to your study session — breaks never count. When a phase ends the timer stops and waits for you, and you get a notification if the app is in the background.")
                }
                .disabled(locked)
            }
            .navigationTitle("Pomodoro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    PomodoroSettingsView().environment(TimerModel())
}
