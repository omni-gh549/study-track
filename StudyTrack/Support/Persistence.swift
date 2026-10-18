import SwiftData
import SwiftUI

enum Persistence {
    static let schema = Schema([Subject.self, StudySession.self, Goal.self, UnlockedBadge.self, FreezeGrant.self])

    /// Opens the on-disk store. If it can't be opened (corruption, failed migration) the old files are
    /// moved aside — never deleted — and a fresh store is created, so the app always launches and the
    /// original data can still be recovered.
    static func makeContainer() -> ModelContainer {
        let env = ProcessInfo.processInfo.environment

        if env["UITEST_RESET"] == "1" {
            TimerStore.clear()
            if let id = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: id)
            }
        }
        if env["UITEST_INMEMORY"] == "1" {
            return try! ModelContainer(for: schema,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }

        let config = ModelConfiguration(schema: schema)
        if env["UITEST_RESET"] == "1" {
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: config.url.path + suffix))
            }
        }
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            quarantineStore(at: config.url)
            UserDefaults.standard.set(true, forKey: "storeWasRecovered")
            do {
                return try ModelContainer(for: schema, configurations: config)
            } catch {
                return try! ModelContainer(for: schema,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            }
        }
    }

    private static func quarantineStore(at url: URL) {
        let fm = FileManager.default
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        let dir = url.deletingLastPathComponent().appendingPathComponent("Recovered-\(stamp)")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for suffix in ["", "-shm", "-wal"] {
            let source = URL(fileURLWithPath: url.path + suffix)
            guard fm.fileExists(atPath: source.path) else { continue }
            try? fm.moveItem(at: source, to: dir.appendingPathComponent(source.lastPathComponent))
        }
    }
}

/// Rolling local snapshots, visible in the Files app (On My iPhone › StudyTrack › Backups).
/// They protect against a corrupted store or a bad restore; they don't survive deleting the app,
/// which is what exporting a backup to iCloud Drive is for.
enum AutoBackup {
    static var directory: URL {
        let docs = (try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return docs.appendingPathComponent("Backups", isDirectory: true)
    }

    @MainActor
    static func snapshotIfNeeded(context: ModelContext) {
        let defaults = UserDefaults.standard
        let last = defaults.double(forKey: "lastAutoBackup")
        guard Date.now.timeIntervalSince1970 - last > 20 * 3600 else { return }
        if write(prefix: "StudyTrack-auto", context: context) != nil {
            defaults.set(Date.now.timeIntervalSince1970, forKey: "lastAutoBackup")
            prune(prefix: "StudyTrack-auto", keep: 14)
        }
    }

    @MainActor
    @discardableResult
    static func write(prefix: String, context: ModelContext) -> URL? {
        let subjects = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
        let sessions = (try? context.fetch(FetchDescriptor<StudySession>())) ?? []
        let goals = (try? context.fetch(FetchDescriptor<Goal>())) ?? []
        let badges = (try? context.fetch(FetchDescriptor<UnlockedBadge>())) ?? []
        let freezeGrants = (try? context.fetch(FetchDescriptor<FreezeGrant>())) ?? []
        guard !(subjects.isEmpty && sessions.isEmpty && goals.isEmpty) else { return nil }

        let file = BackupFile.make(subjects: subjects, sessions: sessions, goals: goals, badges: badges, freezeGrants: freezeGrants)
        guard let data = try? file.encoded() else { return nil }
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        let url = directory.appendingPathComponent("\(prefix)-\(stamp).json")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private static func prune(prefix: String, keep: Int) {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix(prefix) }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in files.dropFirst(keep) { try? fm.removeItem(at: old) }
    }
}
