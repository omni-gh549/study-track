import ActivityKit
import Foundation

/// Shared by the app and the Live Activity extension.
struct TimerActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Kind: String, Codable, Hashable {
            case stopwatch, focus, shortBreak, longBreak
        }

        enum Status: String, Codable, Hashable {
            /// Counting (a system-rendered timer, so it keeps ticking while the app is suspended).
            case running
            case paused
            /// A Pomodoro phase finished; waiting for you to start the next one.
            case waiting
        }

        var kind: Kind
        var status: Status
        /// Running Pomodoro: when the phase ends. Running stopwatch: the virtual start (now − elapsed).
        var referenceDate: Date
        /// Running Pomodoro: virtual start of the phase, so progress bars line up even after pauses.
        var phaseStart: Date
        /// Shown while paused / waiting: remaining seconds (Pomodoro) or elapsed seconds (stopwatch).
        var frozenSeconds: Double
        var phaseTotalSeconds: Double
        var blocksDone: Int
        var blocksPerCycle: Int
        var focusSeconds: Double

        var isBreak: Bool { kind == .shortBreak || kind == .longBreak }
        var isPomodoro: Bool { kind != .stopwatch }
    }

    var subjectName: String
    var subjectIcon: String
    var subjectColor: String
}
