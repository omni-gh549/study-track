import Foundation

extension TimeInterval {
    /// "2h 5m", "45m", "3h"
    var studyDuration: String {
        let totalMinutes = Int((self / 60).rounded())
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }

    /// Stopwatch style: "05:03" or "1:05:03"
    var clock: String {
        let s = Int(self)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%02d:%02d", m, sec)
    }
}
