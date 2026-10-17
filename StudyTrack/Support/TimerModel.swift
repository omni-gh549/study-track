import SwiftUI
import UserNotifications

/// Shared, observable wrapper around `TimerState` so the Timer tab and the Today tab always agree.
/// Every change is written to disk immediately.
@MainActor
@Observable
final class TimerModel {
    private(set) var state: TimerState

    init() {
        state = TimerStore.load()
    }

    func reload() {
        state = TimerStore.load()
    }

    func update(_ change: (inout TimerState) -> Void) {
        change(&state)
        TimerStore.save(state)
        TimerReminder.sync(running: state.isRunning)
    }
}

/// If the timer is left running, nudge after 3 hours. Only schedules when notification permission
/// has already been granted — it never prompts by itself.
enum TimerReminder {
    private static let identifier = "timer-still-running"

    static func sync(running: Bool) {
        Task {
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            guard running else { return }
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

            let content = UNMutableNotificationContent()
            content.title = "Your study timer is still running"
            content.body = "Open StudyTrack to pause or finish your session."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3 * 3600, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
    }
}
