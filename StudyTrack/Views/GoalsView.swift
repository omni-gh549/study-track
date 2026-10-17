import SwiftData
import SwiftUI

struct GoalsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Goal.createdAt) private var goals: [Goal]
    @Query private var sessions: [StudySession]
    @State private var showingAdd = false
    @State private var editing: Goal?
    @State private var pendingDelete: Goal?

    var body: some View {
        NavigationStack {
            List {
                ForEach(GoalPeriod.allCases) { period in
                    let items = goals.filter { $0.period == period }
                    if !items.isEmpty {
                        Section(period.title) {
                            ForEach(items) { goal in
                                Button { editing = goal } label: {
                                    GoalRow(goal: goal, progress: goal.progress(in: sessions))
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) { pendingDelete = goal } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
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
            .sheet(item: $editing) { GoalFormView(goal: $0) }
            .alert("Delete this goal?", isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ), presenting: pendingDelete) { goal in
                Button("Delete “\(goal.title)”", role: .destructive) {
                    context.delete(goal)
                    context.commit()
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: { goal in
                Text("“\(goal.title)” will be removed. Your study sessions are not affected.")
            }
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

    private let goal: Goal?
    @State private var title: String
    @State private var period: GoalPeriod
    @State private var subject: Subject?
    @State private var targetMinutes: Int
    @State private var saveFailed = false

    init(goal: Goal? = nil) {
        self.goal = goal
        _title = State(initialValue: goal?.title ?? "")
        _period = State(initialValue: goal?.period ?? .weekly)
        _subject = State(initialValue: goal?.subject)
        _targetMinutes = State(initialValue: goal?.targetMinutes ?? 120)
    }

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
            .navigationTitle(goal == nil ? "New Goal" : "Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let name = title.trimmingCharacters(in: .whitespaces)
                        if let goal {
                            goal.title = name
                            goal.targetMinutes = targetMinutes
                            goal.period = period
                            goal.subject = subject
                        } else {
                            context.insert(Goal(title: name, targetMinutes: targetMinutes,
                                                period: period, subject: subject))
                        }
                        if context.commit() {
                            GameEngine.syncBadges(context: context)
                            dismiss()
                        } else {
                            saveFailed = true
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .alert("Couldn't save", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    GoalsView().modelContainer(PreviewData.container)
}
