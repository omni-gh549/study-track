import SwiftData
import SwiftUI
import UserNotifications

enum Reminders {
    private static let identifier = "daily-study-reminder"

    /// Returns false when the user has denied notification permission.
    static func schedule(minutesAfterMidnight: Int) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return false }

        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        let content = UNMutableNotificationContent()
        content.title = "Time to study 📚"
        content.body = "Keep your streak alive — even 15 minutes counts."
        content.sound = .default

        var components = DateComponents()
        components.hour = minutesAfterMidnight / 60
        components.minute = minutesAfterMidnight % 60
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        return true
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \StudySession.startDate) private var sessions: [StudySession]
    @Query private var subjects: [Subject]

    @AppStorage("dailyGoalMinutes") private var dailyGoalMinutes = 60
    @AppStorage("remindersOn") private var remindersOn = false
    @AppStorage("reminderMinutes") private var reminderMinutes = 19 * 60

    @State private var permissionDenied = false
    @State private var confirmReset = false

    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: reminderMinutes / 60, minute: reminderMinutes % 60,
                                      second: 0, of: .now) ?? .now
            },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                reminderMinutes = (c.hour ?? 19) * 60 + (c.minute ?? 0)
            }
        )
    }

    private var csv: String {
        let iso = ISO8601DateFormatter()
        var lines = ["date,subject,minutes,focus,notes"]
        for s in sessions {
            let subject = s.subject?.name ?? ""
            let notes = s.notes.replacingOccurrences(of: "\"", with: "\"\"")
            lines.append("\(iso.string(from: s.startDate)),\"\(subject)\",\(Int(s.duration / 60)),\(s.focus),\"\(notes)\"")
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $dailyGoalMinutes, in: 15...600, step: 15) {
                        LabeledContent("Default daily goal", value: TimeInterval(dailyGoalMinutes * 60).studyDuration)
                    }
                } footer: {
                    Text("Used for the Today ring when you haven't created a daily goal.")
                }

                Section("Reminders") {
                    Toggle("Daily reminder", isOn: $remindersOn)
                    if remindersOn {
                        DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
                    }
                }

                Section("Data") {
                    ShareLink(item: csv, subject: Text("StudyTrack export")) {
                        Label("Export sessions as CSV", systemImage: "square.and.arrow.up")
                    }
                    .disabled(sessions.isEmpty)

                    if subjects.isEmpty {
                        Button("Load sample data", systemImage: "wand.and.stars") {
                            SampleData.seed(context)
                        }
                    }
                    Button("Erase all data", systemImage: "trash", role: .destructive) {
                        confirmReset = true
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: "0.2.0")
                    Text("XP, levels and badges are calculated from your sessions, so editing or deleting a session updates them too.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: remindersOn) { _, on in
                if on {
                    Task {
                        let ok = await Reminders.schedule(minutesAfterMidnight: reminderMinutes)
                        if !ok {
                            remindersOn = false
                            permissionDenied = true
                        }
                    }
                } else {
                    Reminders.cancel()
                }
            }
            .onChange(of: reminderMinutes) { _, minutes in
                guard remindersOn else { return }
                Task { _ = await Reminders.schedule(minutesAfterMidnight: minutes) }
            }
            .alert("Notifications are off", isPresented: $permissionDenied) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Enable notifications for StudyTrack in the Settings app to get reminders.")
            }
            .confirmationDialog("Erase all subjects, sessions and goals?",
                                isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Erase everything", role: .destructive) {
                    try? context.delete(model: StudySession.self)
                    try? context.delete(model: Goal.self)
                    try? context.delete(model: Subject.self)
                }
            }
        }
    }
}

#Preview {
    SettingsView().modelContainer(PreviewData.container)
}
