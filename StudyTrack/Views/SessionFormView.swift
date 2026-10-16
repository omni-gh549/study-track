import SwiftData
import SwiftUI

/// Used for manual entry, saving a finished timer run, and editing an existing session.
struct SessionFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(CelebrationCenter.self) private var celebrations
    @Query(sort: \Subject.name) private var subjects: [Subject]
    @Query private var allSessions: [StudySession]
    @Query private var goals: [Goal]

    private let editing: StudySession?
    private let onSaved: (() -> Void)?

    @State private var subject: Subject?
    @State private var date: Date
    @State private var hours: Int
    @State private var minutes: Int
    @State private var focus: Int
    @State private var notes: String

    init(session: StudySession? = nil,
         subject: Subject? = nil,
         date: Date = .now,
         duration: TimeInterval = 3600,
         onSaved: (() -> Void)? = nil) {
        editing = session
        self.onSaved = onSaved
        let total = max(Int(((session?.duration ?? duration) / 60).rounded()), 1)
        _subject = State(initialValue: session?.subject ?? subject)
        _date = State(initialValue: session?.startDate ?? date)
        _hours = State(initialValue: min(total / 60, 12))
        _minutes = State(initialValue: total % 60)
        _focus = State(initialValue: session?.focus ?? 3)
        _notes = State(initialValue: session?.notes ?? "")
    }

    private var totalSeconds: TimeInterval { TimeInterval((hours * 60 + minutes) * 60) }
    private var xpPreview: Int { editing == nil ? Int(totalSeconds / 60) + (focus >= 4 ? Int(totalSeconds / 60) / 5 : 0) + 5 : 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section("Subject") {
                    Picker("Subject", selection: $subject) {
                        Text("None").tag(Subject?.none)
                        ForEach(subjects) { s in
                            Label(s.name, systemImage: s.icon).tag(Optional(s))
                        }
                    }
                }

                Section("When") {
                    DatePicker("Started", selection: $date, in: ...Date.now)
                }

                Section("Duration") {
                    HStack(spacing: 0) {
                        Picker("Hours", selection: $hours) {
                            ForEach(0...12, id: \.self) { Text("\($0) h").tag($0) }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                        .clipped()

                        Picker("Minutes", selection: $minutes) {
                            ForEach(0..<60, id: \.self) { Text("\($0) min").tag($0) }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                        .clipped()
                    }
                    .frame(height: 120)
                }

                Section {
                    HStack {
                        ForEach(1...5, id: \.self) { i in
                            Button {
                                focus = i
                            } label: {
                                Image(systemName: i <= focus ? "star.fill" : "star")
                                    .font(.title2)
                                    .foregroundStyle(.yellow)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .sensoryFeedback(.selection, trigger: focus)
                } header: {
                    Text("How focused were you?")
                } footer: {
                    Text("4★ and 5★ sessions earn bonus XP.")
                }

                Section("Notes") {
                    TextField("What did you cover?", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let editing {
                    Section {
                        Button("Delete session", role: .destructive) {
                            context.delete(editing)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(editing == nil ? "New Session" : "Edit Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Save · +\(xpPreview) XP" : "Save", action: save)
                        .disabled(totalSeconds == 0)
                }
            }
            .onAppear { if subject == nil && editing == nil { subject = subjects.first } }
        }
        .presentationDetents([.large])
    }

    private func save() {
        let cleaned = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        if let editing {
            editing.subject = subject
            editing.startDate = date
            editing.duration = totalSeconds
            editing.focus = focus
            editing.notes = cleaned
            dismiss()
            return
        }

        let existing = allSessions
        let before = GameEngine.snapshot(sessions: existing, goals: goals)
        let session = StudySession(subject: subject, startDate: date, duration: totalSeconds,
                                   notes: cleaned, focus: focus)
        context.insert(session)
        let afterSessions = existing.filter { $0.persistentModelID != session.persistentModelID } + [session]
        let after = GameEngine.snapshot(sessions: afterSessions, goals: goals)

        onSaved?()
        dismiss()
        celebrations.present(GameEngine.celebration(from: before, to: after))
    }
}

#Preview {
    SessionFormView()
        .modelContainer(PreviewData.container)
        .environment(CelebrationCenter())
}
