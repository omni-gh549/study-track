import Foundation

enum TimerMode: String, Codable, CaseIterable, Identifiable {
    case stopwatch, pomodoro

    var id: String { rawValue }
    var title: String { self == .stopwatch ? "Stopwatch" : "Pomodoro" }
}

enum PomodoroPhase: String, Codable {
    case focus, shortBreak, longBreak

    var title: String {
        switch self {
        case .focus: return "Focus"
        case .shortBreak: return "Short break"
        case .longBreak: return "Long break"
        }
    }

    var isBreak: Bool { self != .focus }
}

struct PomodoroConfig: Codable, Equatable {
    var focusMinutes = 25
    var shortBreakMinutes = 5
    var longBreakMinutes = 15
    var blocksBeforeLongBreak = 4

    /// Seconds per "minute". Always 60 in the app; UI tests shrink it so whole phases pass in seconds.
    static let secondsPerMinute: TimeInterval = {
        if let raw = ProcessInfo.processInfo.environment["UITEST_POMODORO_SECONDS_PER_MINUTE"],
           let value = Double(raw), value > 0 { return value }
        return 60
    }()

    func duration(of phase: PomodoroPhase) -> TimeInterval {
        let minutes: Int
        switch phase {
        case .focus: minutes = focusMinutes
        case .shortBreak: minutes = shortBreakMinutes
        case .longBreak: minutes = longBreakMinutes
        }
        return TimeInterval(max(minutes, 1)) * Self.secondsPerMinute
    }

    /// Keeps values in a sane range, whatever was decoded from disk.
    func clamped() -> PomodoroConfig {
        PomodoroConfig(focusMinutes: min(max(focusMinutes, 1), 180),
                       shortBreakMinutes: min(max(shortBreakMinutes, 1), 60),
                       longBreakMinutes: min(max(longBreakMinutes, 1), 120),
                       blocksBeforeLongBreak: min(max(blocksBeforeLongBreak, 2), 8))
    }
}

/// Pure value type for the study timer (stopwatch or Pomodoro). All time maths is derived from timestamps,
/// so it is correct no matter how long the app was suspended or terminated.
///
/// Pomodoro rules:
/// - Only focus time counts towards your session; breaks never do.
/// - When a phase ends the timer **stops** and waits for you (it never silently rolls into the next phase
///   while the app is closed, which would credit study time you didn't do).
/// - Every `blocksBeforeLongBreak`-th focus block is followed by a long break.
struct TimerState: Codable, Equatable {
    /// Stopwatch: total elapsed. Pomodoro: focus seconds credited so far (excluding the running segment).
    var accumulated: TimeInterval = 0
    /// Non-nil while running.
    var runStart: Date?
    var sessionStart: Date?
    var subjectName: String = ""
    var subjectIcon: String = "book.fill"
    var subjectColor: String = "blue"

    var mode: TimerMode = .stopwatch
    var config = PomodoroConfig()
    var phase: PomodoroPhase = .focus
    /// Seconds already spent in the current phase, excluding the running segment.
    var phaseBase: TimeInterval = 0
    var completedBlocks = 0
    /// The previous phase finished; `phase` is the upcoming one, waiting to be started.
    var awaitingNext = false
    var phaseEndedAt: Date?
    /// Bumped on every change made through `TimerModel`. Lets the app tell a newer copy of the state from an
    /// older one, so a stale file on disk can never overwrite the live timer.
    var revision = 0

    init(subjectName: String = "") {
        self.subjectName = subjectName
    }

    private enum CodingKeys: String, CodingKey {
        case accumulated, runStart, sessionStart, subjectName, subjectIcon, subjectColor
        case mode, config, phase, phaseBase, completedBlocks, awaitingNext, phaseEndedAt, revision
    }

    /// Tolerant decoding: state files written by older versions (which lack the Pomodoro fields) must
    /// keep working, or updating the app mid-session would lose a running timer.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accumulated = try c.decodeIfPresent(TimeInterval.self, forKey: .accumulated) ?? 0
        runStart = try c.decodeIfPresent(Date.self, forKey: .runStart)
        sessionStart = try c.decodeIfPresent(Date.self, forKey: .sessionStart)
        subjectName = try c.decodeIfPresent(String.self, forKey: .subjectName) ?? ""
        subjectIcon = try c.decodeIfPresent(String.self, forKey: .subjectIcon) ?? "book.fill"
        subjectColor = try c.decodeIfPresent(String.self, forKey: .subjectColor) ?? "blue"
        mode = try c.decodeIfPresent(TimerMode.self, forKey: .mode) ?? .stopwatch
        config = (try c.decodeIfPresent(PomodoroConfig.self, forKey: .config) ?? PomodoroConfig()).clamped()
        phase = try c.decodeIfPresent(PomodoroPhase.self, forKey: .phase) ?? .focus
        phaseBase = max(try c.decodeIfPresent(TimeInterval.self, forKey: .phaseBase) ?? 0, 0)
        completedBlocks = max(try c.decodeIfPresent(Int.self, forKey: .completedBlocks) ?? 0, 0)
        awaitingNext = try c.decodeIfPresent(Bool.self, forKey: .awaitingNext) ?? false
        phaseEndedAt = try c.decodeIfPresent(Date.self, forKey: .phaseEndedAt)
        revision = max(try c.decodeIfPresent(Int.self, forKey: .revision) ?? 0, 0)
    }

    // MARK: Derived

    var isRunning: Bool { runStart != nil }
    var isPomodoro: Bool { mode == .pomodoro }
    var phaseDuration: TimeInterval { config.duration(of: phase) }

    var hasProgress: Bool {
        if isRunning || accumulated > 0 { return true }
        return isPomodoro && (phaseBase > 0 || completedBlocks > 0 || awaitingNext || phase != .focus)
    }

    private func runningSegment(at now: Date) -> TimeInterval {
        runStart.map { max(now.timeIntervalSince($0), 0) } ?? 0
    }

    /// Time that counts towards the session: stopwatch time, or Pomodoro focus time.
    func elapsed(at now: Date) -> TimeInterval {
        if !isPomodoro { return accumulated + runningSegment(at: now) }
        guard isRunning, phase == .focus else { return accumulated }
        return accumulated + min(runningSegment(at: now), max(phaseDuration - phaseBase, 0))
    }

    func phaseElapsed(at now: Date) -> TimeInterval {
        min(phaseBase + runningSegment(at: now), phaseDuration)
    }

    func phaseRemaining(at now: Date) -> TimeInterval {
        max(phaseDuration - phaseElapsed(at: now), 0)
    }

    /// When the running Pomodoro phase will end.
    var phaseEndDate: Date? {
        guard isPomodoro, let start = runStart else { return nil }
        return start.addingTimeInterval(max(phaseDuration - phaseBase, 0))
    }

    /// The phase that follows the current one finishing.
    var phaseAfterCurrent: PomodoroPhase {
        if phase != .focus { return .focus }
        let blocks = completedBlocks + 1
        return blocks % max(config.blocksBeforeLongBreak, 1) == 0 ? .longBreak : .shortBreak
    }

    // MARK: Transitions

    func resolved(at now: Date) -> TimerState {
        var copy = self
        copy.resolve(at: now)
        return copy
    }

    /// Completes the running Pomodoro phase if its time is up. A no-op otherwise.
    mutating func resolve(at now: Date) {
        guard isPomodoro, let start = runStart else { return }
        let remaining = max(phaseDuration - phaseBase, 0)
        guard now.timeIntervalSince(start) >= remaining else { return }

        if phase == .focus {
            accumulated += remaining
            completedBlocks += 1
        }
        phase = phaseAfterPrevious()
        phaseBase = 0
        runStart = nil
        awaitingNext = true
        phaseEndedAt = start.addingTimeInterval(remaining)
    }

    /// Phase after the one that just ended, computed with `completedBlocks` already incremented.
    private func phaseAfterPrevious() -> PomodoroPhase {
        if phase != .focus { return .focus }
        return completedBlocks % max(config.blocksBeforeLongBreak, 1) == 0 ? .longBreak : .shortBreak
    }

    mutating func start(at now: Date) {
        resolve(at: now)
        guard !isRunning else { return }
        if sessionStart == nil { sessionStart = now }
        runStart = now
        awaitingNext = false
        phaseEndedAt = nil
    }

    mutating func pause(at now: Date) {
        resolve(at: now)
        guard isRunning else { return }
        let segment = runningSegment(at: now)
        if isPomodoro {
            phaseBase += segment
            if phase == .focus { accumulated += segment }
        } else {
            accumulated += segment
        }
        runStart = nil
    }

    /// Pomodoro only: abandon the current break and line up the next focus block.
    mutating func skipBreak(at now: Date) {
        resolve(at: now)
        guard isPomodoro, phase.isBreak else { return }
        runStart = nil
        phase = .focus
        phaseBase = 0
        awaitingNext = true
        phaseEndedAt = nil
    }

    /// Clears the run but keeps your subject, mode and Pomodoro settings.
    mutating func reset() {
        let keepSubject = subjectName, keepIcon = subjectIcon, keepColor = subjectColor
        let keepMode = mode, keepConfig = config
        self = TimerState(subjectName: keepSubject)
        subjectIcon = keepIcon
        subjectColor = keepColor
        mode = keepMode
        config = keepConfig
    }
}

/// Persists `TimerState` to disk and forces it through to storage (fsync) on every change,
/// so even an immediate power-off right after tapping Pause can't lose it.
///
/// The previous good copy is kept next to it (`.prev.json`) and used if the main file is ever unreadable.
enum TimerStore {
    static var url: URL = {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("timer-state.json")
    }()

    private static var previousURL: URL {
        url.deletingLastPathComponent().appendingPathComponent("timer-state.prev.json")
    }

    static func load() -> TimerState {
        for candidate in [url, previousURL] {
            if let data = try? Data(contentsOf: candidate),
               let state = try? JSONDecoder().decode(TimerState.self, from: data) { return state }
        }
        return TimerState()
    }

    /// Returns false when the state could not be written (the in-memory timer keeps working regardless).
    @discardableResult
    static func save(_ state: TimerState) -> Bool {
        guard let data = try? JSONEncoder().encode(state) else { return false }
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        do { try fm.createDirectory(at: dir, withIntermediateDirectories: true) } catch { return false }

        if fm.fileExists(atPath: url.path) {
            try? fm.removeItem(at: previousURL)
            try? fm.copyItem(at: url, to: previousURL)
        }
        if writeDurably(data) && (try? Data(contentsOf: url)) == data { return true }
        // Fallback for file systems that dislike the replace dance (e.g. some sideloading containers).
        do {
            try data.write(to: url, options: .atomic)
            return (try? Data(contentsOf: url)) == data
        } catch {
            return false
        }
    }

    private static func writeDurably(_ data: Data) -> Bool {
        let fm = FileManager.default
        let tmp = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".tmp")
        do {
            try? fm.removeItem(at: tmp)
            guard fm.createFile(atPath: tmp.path, contents: nil) else { return false }
            let handle = try FileHandle(forWritingTo: tmp)
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
            if fm.fileExists(atPath: url.path) {
                _ = try fm.replaceItemAt(url, withItemAt: tmp)
            } else {
                try fm.moveItem(at: tmp, to: url)
            }
            return true
        } catch {
            return false
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: previousURL)
    }
}
