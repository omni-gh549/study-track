import SwiftData
import SwiftUI

struct GoalsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Goal.createdAt) private var goals: [Goal]
    @Query private var sessions: [StudySession]
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(GoalPeriod.allCases) { period in
                    let items = goals.filter { $0.period == period }
                    if !items.isEmpty {
                        Section(period.title) {
                            ForEach(items) { goal in
                                GoalRow(goal: goal, progress: goal.progress(in: sessions))
                            }
                            .onDelete { offsets in
                                for i in offsets { context.delete(items[i]) }
                            }
                        }
                    }
                }
            }
            .overlay {
                if goals.isEmpty {
                    ContentUnavailableView("No goals yet", systemImage: "target",
                                           description: Text("Set a daily or weekly target to stay on track."))
                }
            }
            .navigationTitle("Goals")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Goal", systemImage: "plus") { showingAdd = true }
                }
            }
            .sheet(isPresented: $showingAdd) { GoalFormView() }
        }
    }
}

private struct GoalRow: View {
    let goal: Goal
    let progress: TimeInterval

    private var fraction: Double { goal.target > 0 ? progress / goal.target : 0 }
    private var tint: Color { goal.subject?.color ?? .accentColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let subject = goal.subject {
                    SubjectBadge(subject: subject, size: 30)
                }
                Text(goal.title).font(.headline)
                Spacer()
                if fraction >= 1 {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Text("\(Int(fraction * 100))%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: min(fraction, 1))
                .tint(fraction >= 1 ? .green : tint)
            Text("\(progress.studyDuration) of \(goal.target.studyDuration)"
                 + (goal.subject.map { " · \($0.name)" } ?? " · All subjects"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct GoalFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Subject.name) private var subjects: [Subject]

    @State private var title = ""
    @State private var period: GoalPeriod = .weekly
    @State private var subject: Subject?
    @State private var targetMinutes = 120

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Goal name", text: $title)
                    Picker("Repeats", selection: $period) {
                        ForEach(GoalPeriod.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Target") {
                    Stepper(value: $targetMinutes, in: 15...3000, step: 15) {
                        Text(TimeInterval(targetMinutes * 60).studyDuration)
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                    }
                }
                Section("Applies to") {
                    Picker("Subject", selection: $subject) {
                        Text("All subjects").tag(Subject?.none)
                        ForEach(subjects) { s in
                            Label(s.name, systemImage: s.icon).tag(Optional(s))
                        }
                    }
                }
            }
            .navigationTitle("New Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let name = title.trimmingCharacters(in: .whitespaces)
                        context.insert(Goal(title: name, targetMinutes: targetMinutes,
                                            period: period, subject: subject))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    GoalsView().modelContainer(PreviewData.container)
}
