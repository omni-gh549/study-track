import Foundation

/// Pure value type for the study timer. All time maths is derived from timestamps,
/// so it is correct no matter how long the app was suspended or terminated.
struct TimerState: Codable, Equatable {
    var accumulated: TimeInterval = 0
    /// Non-nil while the timer is running.
    var runStart: Date?
    var sessionStart: Date?
    var subjectName: String = ""

    var isRunning: Bool { runStart != nil }
    var hasProgress: Bool { isRunning || accumulated > 0 }

    func elapsed(at now: Date) -> TimeInterval {
        // A clock that moved backwards must never produce negative time.
        let running = runStart.map { max(now.timeIntervalSince($0), 0) } ?? 0
        return accumulated + running
    }

    mutating func start(at now: Date) {
        guard !isRunning else { return }
        if sessionStart == nil { sessionStart = now }
        runStart = now
    }

    mutating func pause(at now: Date) {
        guard isRunning else { return }
        accumulated = elapsed(at: now)
        runStart = nil
    }

    mutating func reset() {
        self = TimerState(subjectName: subjectName)
    }
}

/// Persists `TimerState` to disk and forces it through to storage (fsync) on every change,
/// so even an immediate power-off right after tapping Pause can't lose it.
enum TimerStore {
    static var url: URL = {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("timer-state.json")
    }()

    static func load() -> TimerState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(TimerState.self, from: data) else { return TimerState() }
        return state
    }

    static func save(_ state: TimerState) {
        do {
            let data = try JSONEncoder().encode(state)
            let fm = FileManager.default
            let dir = url.deletingLastPathComponent()
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)

            let tmp = dir.appendingPathComponent(url.lastPathComponent + ".tmp")
            try? fm.removeItem(at: tmp)
            guard fm.createFile(atPath: tmp.path, contents: nil) else { return }
            let handle = try FileHandle(forWritingTo: tmp)
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()

            if fm.fileExists(atPath: url.path) {
                _ = try fm.replaceItemAt(url, withItemAt: tmp)
            } else {
                try fm.moveItem(at: tmp, to: url)
            }
        } catch {
            // Persistence is best-effort; the in-memory timer keeps working.
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
