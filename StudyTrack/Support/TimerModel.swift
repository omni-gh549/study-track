import SwiftUI
import UserNotifications

/// Shared, observable wrapper around `TimerState` so the Timer tab, the Today tab, the lock-screen alerts and
/// the Live Activity always agree. Every change is written to disk immediately.
@MainActor
@Observable
final class TimerModel {
    private(set) var state: TimerState
    /// Bumped whenever a Pomodoro phase finishes while the app is in the foreground (drives haptics).
    private(set) var phaseCompletions = 0
    /// True when the last attempt to write the timer to disk failed. The timer itself keeps working, but would
    /// not survive the app being closed.
    private(set) var persistenceFailing = false

    /// One timer for the whole app. (`RootView` is re-created by SwiftUI now and then; a second model would
    /// load, settle and write the file behind the live one's back.)
    static let shared = TimerModel()

    @ObservationIgnored private var wakeTask: Task<Void, Never>?

    init() {
        state = TimerStore.load()
        if let seeded = Self.uiTestSeed() { state = seeded }
        _ = settle()
        scheduleSideEffects()
    }

    /// UI tests only: a timer that is already 4 Pomodoro blocks (25 min each) in, plus 1 minute into the 5th.
    private static func uiTestSeed() -> TimerState? {
        guard ProcessInfo.processInfo.environment["UITEST_TIMER_SEED"] == "fifth-block-running" else { return nil }
        var s = TimerState()
        s.mode = .pomodoro
        s.accumulated = 4 * 1500
        s.completedBlocks = 4
        s.sessionStart = Date.now.addingTimeInterval(-3 * 3600)
        s.runStart = Date.now.addingTimeInterval(-60)
        return s
    }

    /// Re-applies alerts and the Live Activity (e.g. after a setting changed).
    func refreshSideEffects() { scheduleSideEffects() }

    /// Called when the app returns to the foreground: settles any phase that finished while away.
    /// Memory is the source of truth while the app is alive — a copy from disk is only adopted when it is
    /// strictly newer, so a stale or failed write can never wipe the running timer.
    func reload() {
        let disk = TimerStore.load()
        if disk.revision > state.revision { state = disk }
        if settle() { phaseCompletions += 1 }
        persist(state)            // self-heal if an earlier write failed
        scheduleSideEffects()
    }

    func update(_ change: (inout TimerState) -> Void) {
        var next = state
        next.resolve(at: .now)          // a phase that already ran out counts before the user's tap
        change(&next)
        next.revision = state.revision &+ 1
        state = next
        persist(next)
        scheduleSideEffects()
    }

    /// Applies a finished phase, if any. Returns true when something changed.
    @discardableResult
    private func settle() -> Bool {
        let settled = state.resolved(at: .now)
        guard settled != state else { return false }
        var next = settled
        next.revision = state.revision &+ 1
        state = next
        persist(next)
        return true
    }

    private func persist(_ value: TimerState) {
        persistenceFailing = !TimerStore.save(value)
    }

    private func scheduleSideEffects() {
        PhaseAlerts.sync(state)
        TimerReminder.sync(running: state.isRunning && !state.isPomodoro)
        LiveActivityController.sync(state)

        wakeTask?.cancel()
        wakeTask = nil
        guard let end = state.phaseEndDate else { return }
        wakeTask = Task { [weak self] in
            let delay = max(end.timeIntervalSinceNow, 0) + 0.05
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            if self.settle() {
                self.phaseCompletions += 1
                self.scheduleSideEffects()
            }
        }
    }
}

/// If a stopwatch is left running, nudge after 3 hours. Only schedules when notification permission
/// has already been granted — it never prompts by itself.
enum TimerReminder {
    private static let identifier = "timer-still-running"

    static func sync(running: Bool) {
        Task {
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            guard running else { return }
            guard await PhaseAlerts.isAuthorized() else { return }

            let content = UNMutableNotificationContent()
            content.title = "Your study timer is still running"
            content.body = "Open StudyTrack to pause or finish your session."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3 * 3600, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
    }
}

/// Lock-screen alert for the end of a Pomodoro phase — the app is usually suspended by then.
enum PhaseAlerts {
    private static let identifier = "pomodoro-phase-end"

    static func isAuthorized() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }

    /// Asks once, the first time a Pomodoro is started.
    static func requestAuthorizationIfNeeded() async {
        if ProcessInfo.processInfo.environment["UITEST_SKIP_NOTIFICATION_PROMPT"] == "1" { return }
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    static func message(for state: TimerState) -> (title: String, body: String) {
        let next = state.phaseAfterCurrent
        switch (state.phase, next) {
        case (.focus, .longBreak):
            return ("Focus block done 🎉", "Great work — take a long break (\(state.config.longBreakMinutes) min).")
        case (.focus, _):
            return ("Focus block done 🎉", "Take a short break (\(state.config.shortBreakMinutes) min).")
        default:
            return ("Break's over", "Ready for the next focus block?")
        }
    }

    static func sync(_ state: TimerState) {
        Task {
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            guard state.isPomodoro, let end = state.phaseEndDate else { return }
            let interval = end.timeIntervalSinceNow
            guard interval > 0.5, await isAuthorized() else { return }

            let text = message(for: state)
            let content = UNMutableNotificationContent()
            content.title = text.title
            content.body = text.body
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
    }
}
