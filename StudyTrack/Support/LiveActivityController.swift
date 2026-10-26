import ActivityKit
import Foundation

/// Maps `TimerState` to the Live Activity (lock screen + Dynamic Island) and keeps it in sync.
///
/// Everything here is best-effort: if Live Activities are off, unsupported, or the extension isn't part of this
/// install (the "lite" edition used for LiveContainer), the timer works exactly the same without them.
@MainActor
enum LiveActivityController {
    static let enabledKey = "liveActivityEnabled"

    static var isEnabledByUser: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static var isAvailable: Bool {
        AppFlavor.hasLiveActivityExtension && ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Pure mapping, unit tested.
    static func contentState(for state: TimerState, now: Date = .now) -> TimerActivityAttributes.ContentState {
        if !state.isPomodoro {
            let elapsed = state.elapsed(at: now)
            return .init(kind: .stopwatch,
                         status: state.isRunning ? .running : .paused,
                         referenceDate: now.addingTimeInterval(-elapsed),
                         phaseStart: now,
                         frozenSeconds: elapsed,
                         phaseTotalSeconds: 0,
                         blocksDone: 0,
                         blocksPerCycle: state.config.blocksBeforeLongBreak,
                         focusSeconds: elapsed)
        }

        let kind: TimerActivityAttributes.ContentState.Kind
        switch state.phase {
        case .focus: kind = .focus
        case .shortBreak: kind = .shortBreak
        case .longBreak: kind = .longBreak
        }
        let total = state.phaseDuration
        let status: TimerActivityAttributes.ContentState.Status =
            state.isRunning ? .running : (state.awaitingNext ? .waiting : .paused)

        let end = state.phaseEndDate ?? now
        return .init(kind: kind,
                     status: status,
                     referenceDate: end,
                     phaseStart: end.addingTimeInterval(-total),
                     frozenSeconds: max(total - state.phaseBase, 0),
                     phaseTotalSeconds: total,
                     blocksDone: blocksDoneInCycle(state),
                     blocksPerCycle: state.config.blocksBeforeLongBreak,
                     focusSeconds: state.elapsed(at: now))
    }

    /// Blocks completed in the current set: a finished set stays full during its long break, then the next
    /// focus block starts a fresh, empty set.
    static func blocksDoneInCycle(_ state: TimerState) -> Int {
        let per = max(state.config.blocksBeforeLongBreak, 1)
        let done = state.completedBlocks
        if done == 0 { return 0 }
        if state.phase == .focus { return done % per }
        return done % per == 0 ? per : done % per
    }

    static func sync(_ state: TimerState) {
        guard isEnabledByUser, isAvailable, state.hasProgress else {
            end()
            return
        }
        let content = ActivityContent(state: contentState(for: state),
                                      staleDate: state.isRunning ? state.phaseEndDate : nil)
        if let existing = Activity<TimerActivityAttributes>.activities.first {
            Task { await existing.update(content) }
        } else {
            let attributes = TimerActivityAttributes(subjectName: state.subjectName.isEmpty ? "Study" : state.subjectName,
                                                     subjectIcon: state.subjectIcon,
                                                     subjectColor: state.subjectColor)
            _ = try? Activity.request(attributes: attributes, content: content, pushType: nil)
        }
    }

    static func end() {
        let activities = Activity<TimerActivityAttributes>.activities
        guard !activities.isEmpty else { return }
        Task {
            for activity in activities { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}

/// Which build of the app is installed: the full one embeds the Live Activity extension, the "lite" one
/// (made for LiveContainer, which can't run extensions) does not.
enum AppFlavor {
    static var hasLiveActivityExtension: Bool {
        guard let path = Bundle.main.builtInPlugInsPath,
              let items = try? FileManager.default.contentsOfDirectory(atPath: path) else { return false }
        return items.contains { $0.hasSuffix(".appex") }
    }

    static var isLite: Bool { !hasLiveActivityExtension }
}
