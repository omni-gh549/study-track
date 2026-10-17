import CoreTransferable
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Portable, versioned snapshot of everything in the app. Subjects are referenced by
/// index so the file doesn't depend on SwiftData's internal identifiers.
struct BackupFile: Codable {
    struct SubjectDTO: Codable {
        var name: String
        var colorRaw: String
        var icon: String
        var createdAt: Date
    }

    struct SessionDTO: Codable {
        var subjectIndex: Int?
        var startDate: Date
        var duration: Double
        var notes: String
        var focus: Int
    }

    struct GoalDTO: Codable {
        var title: String
        var targetMinutes: Int
        var periodRaw: String
        var subjectIndex: Int?
        var createdAt: Date
    }

    struct BadgeDTO: Codable {
        var badgeID: String
        var unlockedAt: Date
    }

    enum BackupError: LocalizedError {
        case unsupportedVersion(Int)

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let v): return "This backup (format \(v)) was made by a newer version of StudyTrack."
            }
        }
    }

    static let currentVersion = 2

    var version: Int
    var exportedAt: Date
    var subjects: [SubjectDTO]
    var sessions: [SessionDTO]
    var goals: [GoalDTO]
    /// Absent in version 1 backups.
    var badges: [BadgeDTO]?

    static func make(subjects: [Subject], sessions: [StudySession], goals: [Goal],
                     badges: [UnlockedBadge] = []) -> BackupFile {
        var index: [PersistentIdentifier: Int] = [:]
        for (offset, subject) in subjects.enumerated() { index[subject.persistentModelID] = offset }

        return BackupFile(
            version: BackupFile.currentVersion,
            exportedAt: .now,
            subjects: subjects.map {
                SubjectDTO(name: $0.name, colorRaw: $0.colorRaw, icon: $0.icon, createdAt: $0.createdAt)
            },
            sessions: sessions.map {
                SessionDTO(subjectIndex: $0.subject.flatMap { index[$0.persistentModelID] },
                           startDate: $0.startDate, duration: $0.duration,
                           notes: $0.notes, focus: $0.focus)
            },
            goals: goals.map {
                GoalDTO(title: $0.title, targetMinutes: $0.targetMinutes, periodRaw: $0.periodRaw,
                        subjectIndex: $0.subject.flatMap { index[$0.persistentModelID] },
                        createdAt: $0.createdAt)
            },
            badges: badges.map { BadgeDTO(badgeID: $0.badgeID, unlockedAt: $0.unlockedAt) }
        )
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> BackupFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(BackupFile.self, from: data)
        guard (1...currentVersion).contains(file.version) else {
            throw BackupError.unsupportedVersion(file.version)
        }
        return file
    }

    /// Replaces everything currently in the store with this backup.
    @MainActor
    @discardableResult
    func restore(into context: ModelContext) -> Bool {
        context.deleteAllRecords()

        var restored: [Subject] = []
        for dto in subjects {
            let subject = Subject(name: dto.name)
            subject.colorRaw = dto.colorRaw
            subject.icon = dto.icon
            subject.createdAt = dto.createdAt
            context.insert(subject)
            restored.append(subject)
        }

        func subject(at index: Int?) -> Subject? {
            guard let index, restored.indices.contains(index) else { return nil }
            return restored[index]
        }

        for dto in sessions {
            // Never trust a file blindly: clamp values so a damaged backup can't crash the app later.
            let duration = dto.duration.isFinite ? min(max(dto.duration, 0), 7 * 86_400) : 0
            context.insert(StudySession(subject: subject(at: dto.subjectIndex), startDate: dto.startDate,
                                        duration: duration, notes: dto.notes,
                                        focus: min(max(dto.focus, 1), 5)))
        }
        for dto in goals {
            let goal = Goal(title: dto.title, targetMinutes: min(max(dto.targetMinutes, 1), 10_000),
                            period: GoalPeriod(rawValue: dto.periodRaw) ?? .weekly,
                            subject: subject(at: dto.subjectIndex))
            goal.createdAt = dto.createdAt
            context.insert(goal)
        }
        for dto in badges ?? [] {
            context.insert(UnlockedBadge(badgeID: dto.badgeID, unlockedAt: dto.unlockedAt))
        }
        // Deletion and re-insertion are committed together: either the whole restore applies or nothing does.
        guard context.commit() else { return false }
        GameEngine.syncBadges(context: context)
        return true
    }
}

/// Lets `ShareLink` hand the backup to Files / iCloud Drive / AirDrop as a real .json file.
struct BackupDocument: Transferable {
    let data: Data
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { doc in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(doc.filename)
            try doc.data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
