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
    @Query private var goals: [Goal]
    @Query private var badges: [UnlockedBadge]
    @Query private var freezeGrants: [FreezeGrant]

    @AppStorage("dailyGoalMinutes") private var dailyGoalMinutes = 60
    @AppStorage("remindersOn") private var remindersOn = false
    @AppStorage("reminderMinutes") private var reminderMinutes = 19 * 60
    @AppStorage("lastBackup") private var lastBackup: Double = 0
    @AppStorage("liveActivityEnabled") private var liveActivityEnabled = true
    @Environment(TimerModel.self) private var timerModel

    @State private var showingImporter = false
    @State private var pendingRestore: BackupFile?
    @State private var restoreFailed = false

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

    private var backupName: String {
        "StudyTrack-Backup-\(Date.now.formatted(.iso8601.year().month().day())).json"
    }

    private var backupDocument: BackupDocument {
        let file = BackupFile.make(subjects: subjects, sessions: sessions, goals: goals, badges: badges, freezeGrants: freezeGrants)
        return BackupDocument(data: (try? file.encoded()) ?? Data(), filename: backupName)
    }

    private var lastBackupText: String {
        lastBackup == 0
            ? "You haven't backed up yet."
            : "Last backup: " + Date(timeIntervalSince1970: lastBackup).formatted(.relative(presentation: .named))
    }

    private var csv: String { CSVExport.make(sessions: sessions) }

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

                Section {
                    Toggle("Live Activity", isOn: $liveActivityEnabled)
                        .onChange(of: liveActivityEnabled) { _, _ in timerModel.refreshSideEffects() }
                } header: {
                    Text("Timer")
                } footer: {
                    Text(AppFlavor.hasLiveActivityExtension
                         ? (LiveActivityController.isAvailable
                            ? "Shows your running timer on the lock screen and in the Dynamic Island."
                            : "Live Activities are turned off for StudyTrack in the iOS Settings app.")
                         : "This is the lite edition (no app extensions), so there's no Live Activity. Install the full edition to get one.")
                }

                UpdatesSection()

                Section("Reminders") {
                    Toggle("Daily reminder", isOn: $remindersOn)
                    if remindersOn {
                        DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
                    }
                }

                Section {
                    ShareLink(item: backupDocument, preview: SharePreview(backupName)) {
                        Label("Back up all data", systemImage: "externaldrive.badge.icloud")
                    }
                    .simultaneousGesture(TapGesture().onEnded { lastBackup = Date.now.timeIntervalSince1970 })

                    Button("Restore from backup…", systemImage: "arrow.counterclockwise") {
                        showingImporter = true
                    }
                    .alert("Couldn't read that file", isPresented: $restoreFailed) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text("Choose a StudyTrack backup (.json) created with “Back up all data”.")
                    }
                } header: {
                    Text("Backup & restore")
                } footer: {
                    Text("\(lastBackupText) Save the file to iCloud Drive — deleting the app erases everything on this phone. Automatic snapshots are also kept in Files › On My iPhone › StudyTrack › Backups.")
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
                    .alert("Erase everything?", isPresented: $confirmReset) {
                        Button("Erase everything", role: .destructive) {
                            AutoBackup.write(prefix: "pre-erase", context: context)
                            context.deleteAllData()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("All subjects, sessions, goals and badges will be deleted. A safety copy is saved to Files first.")
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: "0.7.1")
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
            .task {
                // The user may have revoked notification permission in iOS Settings since last time.
                guard remindersOn else { return }
                let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
                if status == .authorized || status == .provisional {
                    _ = await Reminders.schedule(minutesAfterMidnight: reminderMinutes)
                } else {
                    remindersOn = false
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
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
                guard case .success(let url) = result else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    pendingRestore = try BackupFile.decode(try FileReading.coordinatedData(at: url))
                } catch {
                    restoreFailed = true
                }
            }
        }
        .alert("Replace all current data?", isPresented: Binding(
            get: { pendingRestore != nil },
            set: { if !$0 { pendingRestore = nil } }
        ), presenting: pendingRestore) { backup in
            Button("Replace with backup", role: .destructive) {
                AutoBackup.write(prefix: "pre-restore", context: context)
                if !backup.restore(into: context) { restoreFailed = true }
                pendingRestore = nil
            }
            Button("Cancel", role: .cancel) { pendingRestore = nil }
        } message: { backup in
            Text("Backup from \(backup.exportedAt.formatted(date: .abbreviated, time: .shortened)): \(backup.sessions.count) sessions, \(backup.subjects.count) subjects, \(backup.goals.count) goals. Everything currently in the app will be replaced.")
        }
    }
}

#Preview {
    SettingsView().modelContainer(PreviewData.container).environment(UpdateService()).environment(TimerModel())
}
