import ActivityKit
import SwiftUI
import WidgetKit

@main
struct StudyTrackWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TimerLiveActivity()
    }
}

// MARK: - Helpers

private extension TimerActivityAttributes.ContentState.Kind {
    var title: String {
        switch self {
        case .stopwatch: return "Studying"
        case .focus: return "Focus"
        case .shortBreak: return "Short break"
        case .longBreak: return "Long break"
        }
    }

    var symbol: String {
        switch self {
        case .stopwatch: return "timer"
        case .focus: return "brain.head.profile"
        case .shortBreak: return "cup.and.saucer.fill"
        case .longBreak: return "figure.walk"
        }
    }
}

private func activityColor(_ attributes: TimerActivityAttributes, _ state: TimerActivityAttributes.ContentState) -> Color {
    if state.isBreak { return .green }
    return SubjectColor(rawValue: attributes.subjectColor)?.color ?? .blue
}

private func statusText(_ state: TimerActivityAttributes.ContentState, isStale: Bool) -> String {
    switch state.status {
    case .paused: return "Paused"
    case .waiting: return state.isBreak ? "Ready for a break" : "Ready to focus"
    case .running:
        if isStale && state.isPomodoro { return state.isBreak ? "Break over" : "Focus block done" }
        return state.kind.title
    }
}

/// The clock. A running timer is rendered by the system, so it keeps moving while the app is suspended.
private struct TimerReadout: View {
    let state: TimerActivityAttributes.ContentState
    var isStale = false

    var body: some View {
        Group {
            if state.status == .running && !isStale {
                if state.kind == .stopwatch {
                    Text(state.referenceDate, style: .timer)
                } else {
                    Text(timerInterval: min(Date.now, state.referenceDate)...state.referenceDate,
                         countsDown: true, showsHours: false)
                }
            } else if state.status == .running {
                Text("0:00")
            } else {
                Text(clock(state.frozenSeconds))
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
    }

    private func clock(_ seconds: Double) -> String {
        let s = max(Int(seconds.rounded()), 0)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

private struct PhaseProgress: View {
    let state: TimerActivityAttributes.ContentState
    let color: Color
    var isStale = false

    var body: some View {
        if state.kind == .stopwatch {
            EmptyView()
        } else if state.status == .running && !isStale {
            ProgressView(timerInterval: min(state.phaseStart, state.referenceDate)...state.referenceDate,
                         countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                .tint(color)
        } else {
            let total = max(state.phaseTotalSeconds, 1)
            ProgressView(value: state.status == .waiting ? 0 : min(max(1 - state.frozenSeconds / total, 0), 1))
                .tint(color)
        }
    }
}

private struct BlockDots: View {
    let state: TimerActivityAttributes.ContentState
    let color: Color

    var body: some View {
        if state.isPomodoro {
            HStack(spacing: 5) {
                ForEach(0..<max(state.blocksPerCycle, 1), id: \.self) { i in
                    Circle()
                        .fill(i < state.blocksDone ? color : color.opacity(0.25))
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityLabel("\(state.blocksDone) of \(state.blocksPerCycle) focus blocks done")
        }
    }
}

private struct SubjectIcon: View {
    let attributes: TimerActivityAttributes
    let color: Color
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: attributes.subjectIcon)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

// MARK: - Lock screen / banner

private struct LockScreenView: View {
    let attributes: TimerActivityAttributes
    let state: TimerActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        let color = activityColor(attributes, state)
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                SubjectIcon(attributes: attributes, color: color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusText(state, isStale: isStale))
                        .font(.subheadline.weight(.semibold))
                    Text(attributes.subjectName)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                TimerReadout(state: state, isStale: isStale)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            if state.isPomodoro {
                PhaseProgress(state: state, color: color, isStale: isStale)
                HStack {
                    BlockDots(state: state, color: color)
                    Spacer()
                    Text("\(Int((state.focusSeconds / 60).rounded())) min focused")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
    }
}

// MARK: - Widget

struct TimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state, isStale: context.isStale)
                .activityBackgroundTint(activityColor(context.attributes, context.state).opacity(0.18))
                .activitySystemActionForegroundColor(activityColor(context.attributes, context.state))
        } dynamicIsland: { context in
            let color = activityColor(context.attributes, context.state)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        SubjectIcon(attributes: context.attributes, color: color, size: 30)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(statusText(context.state, isStale: context.isStale))
                                .font(.caption.weight(.semibold))
                            Text(context.attributes.subjectName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimerReadout(state: context.state, isStale: context.isStale)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.isPomodoro {
                        VStack(spacing: 6) {
                            PhaseProgress(state: context.state, color: color, isStale: context.isStale)
                            BlockDots(state: context.state, color: color)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.kind.symbol).foregroundStyle(color)
            } compactTrailing: {
                TimerReadout(state: context.state, isStale: context.isStale)
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: context.state.kind.symbol).foregroundStyle(color)
            }
            .keylineTint(color)
        }
    }
}
