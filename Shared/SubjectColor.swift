import SwiftUI

enum SubjectColor: String, CaseIterable, Identifiable {
    case blue, indigo, purple, pink, red, orange, yellow, green, teal, mint

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue: return Color.blue
        case .indigo: return Color.indigo
        case .purple: return Color.purple
        case .pink: return Color.pink
        case .red: return Color.red
        case .orange: return Color.orange
        case .yellow: return Color.yellow
        case .green: return Color.green
        case .teal: return Color.teal
        case .mint: return Color.mint
        }
    }
}
