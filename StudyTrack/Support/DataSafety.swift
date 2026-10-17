import Foundation
import SwiftData

extension ModelContext {
    /// Writes pending changes to disk immediately. Returns false (and rolls back) on failure so callers
    /// can tell the user instead of silently carrying on with data that was never stored.
    @discardableResult
    func commit() -> Bool {
        do {
            try save()
            return true
        } catch {
            rollback()
            return false
        }
    }
}

enum SubjectNaming {
    static let maxLength = 40

    static func clean(_ name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLength))
    }

    static func isDuplicate(_ name: String, among existing: [String]) -> Bool {
        let candidate = clean(name)
        return existing.contains {
            clean($0).compare(candidate, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }
}

enum CSVExport {
    static func make(sessions: [StudySession]) -> String {
        let iso = ISO8601DateFormatter()
        var lines = ["date,subject,minutes,focus,notes"]
        for s in sessions.sorted(by: { $0.startDate < $1.startDate }) {
            let minutes = s.duration.isFinite ? Int(s.duration / 60) : 0
            lines.append([iso.string(from: s.startDate), field(s.subject?.name ?? ""),
                          String(minutes), String(s.focus), field(s.notes)].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    /// Quotes the field, doubles embedded quotes, and neutralises spreadsheet formula injection.
    static func field(_ text: String) -> String {
        var t = text
        if let first = t.first, "=+-@\t\r".contains(first) { t = "'" + t }
        return "\"" + t.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// Reads a file the user picked, downloading it first if it lives in iCloud Drive.
enum FileReading {
    static func coordinatedData(at url: URL) throws -> Data {
        var coordinationError: NSError?
        var result: Result<Data, Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            result = Result { try Data(contentsOf: readURL) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }
}
