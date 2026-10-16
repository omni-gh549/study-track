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

    var version: Int
    var exportedAt: Date
    var subjects: [SubjectDTO]
    var sessions: [SessionDTO]
    var goals: [GoalDTO]

    static func make(subjects: [Subject], sessions: [StudySession], goals: [Goal]) -> BackupFile {
        var index: [PersistentIdentifier: Int] = [:]
        for (offset, subject) in subjects.enumerated() { index[subject.persistentModelID] = offset }

        return BackupFile(
            version: 1,
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
            }
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
        return try decoder.decode(BackupFile.self, from: data)
    }

    /// Replaces everything currently in the store with this backup.
    @MainActor
    func restore(into context: ModelContext) {
        try? context.delete(model: StudySession.self)
        try? context.delete(model: Goal.self)
        try? context.delete(model: Subject.self)

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
            context.insert(StudySession(subject: subject(at: dto.subjectIndex), startDate: dto.startDate,
                                        duration: dto.duration, notes: dto.notes, focus: dto.focus))
        }
        for dto in goals {
            let goal = Goal(title: dto.title, targetMinutes: dto.targetMinutes,
                            period: GoalPeriod(rawValue: dto.periodRaw) ?? .weekly,
                            subject: subject(at: dto.subjectIndex))
            goal.createdAt = dto.createdAt
            context.insert(goal)
        }
        try? context.save()
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
