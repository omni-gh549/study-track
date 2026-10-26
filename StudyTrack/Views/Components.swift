import SwiftUI

extension View {
    /// Grouped-list style card, matches Settings / Health look.
    func card() -> some View {
        self
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct ProgressRing: View {
    var progress: Double
    var tint: Color = .accentColor
    var lineWidth: CGFloat = 14

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(tint.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: progress)
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(value)
                .font(.title2.bold())
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }
}

struct SubjectBadge: View {
    let subject: Subject?
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: subject?.icon ?? "questionmark")
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background((subject?.color ?? .gray).gradient,
                        in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

struct SessionRow: View {
    let session: StudySession

    var body: some View {
        HStack(spacing: 12) {
            SubjectBadge(subject: session.subject)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.subject?.name ?? "No subject")
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(session.notes.isEmpty
                     ? session.startDate.formatted(date: .omitted, time: .shortened)
                     : session.notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(session.duration.studyDuration)
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                HStack(spacing: 1) {
                    ForEach(1...5, id: \.self) { i in
                        Image(systemName: i <= session.focus ? "star.fill" : "star")
                            .font(.system(size: 8))
                            .foregroundStyle(i <= session.focus ? Color.yellow : Color.secondary.opacity(0.4))
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
