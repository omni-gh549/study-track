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
    @Query private var badges: [UnlockedBadge]

    private let editing: StudySession?
    private let onSaved: (() -> Void)?
    private let wasTrimmed: Bool

    @State private var subject: Subject?
    @State private var date: Date
    @State private var hours: Int
    @State private var minutes: Int
    @State private var focus: Int
    @State private var notes: String
    @State private var saveFailed = false
    @State private var confirmDelete = false

    private static let maxHours = 24

    init(session: StudySession? = nil,
         subject: Subject? = nil,
         date: Date = .now,
         duration: TimeInterval = 3600,
         onSaved: (() -> Void)? = nil) {
        editing = session
        self.onSaved = onSaved
        let raw = session?.duration ?? duration
        let safe = raw.isFinite ? max(raw, 0) : 0
        let total = max(Int((safe / 60).rounded()), 1)
        wasTrimmed = total > Self.maxHours * 60
        let capped = min(total, Self.maxHours * 60)
        _subject = State(initialValue: session?.subject ?? subject)
        _date = State(initialValue: session?.startDate ?? date)
        _hours = State(initialValue: capped / 60)
        _minutes = State(initialValue: capped % 60)
        _focus = State(initialValue: session?.focus ?? 3)
        _notes = State(initialValue: session?.notes ?? "")
    }

    private var totalSeconds: TimeInterval { TimeInterval((hours * 60 + minutes) * 60) }
    private var xpPreview: Int {
        let m = Int(totalSeconds / 60)
        return m + (focus >= 4 ? m / 5 : 0) + 5
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Subject", selection: $subject) {
                        Text("None").tag(Subject?.none)
                        ForEach(subjects) { s in
                            Label(s.name, systemImage: s.icon).tag(Optional(s))
                        }
                    }
                } header: {
                    Text("Subject")
                } footer: {
                    if subjects.isEmpty { Text("No subjects yet. Add some under History › Subjects.") }
                }

                Section("When") {
                    DatePicker("Started", selection: $date, in: ...Date.now)
                }

                Section {
                    HStack(spacing: 0) {
                        Picker("Hours", selection: $hours) {
                            ForEach(0...Self.maxHours, id: \.self) { Text("\($0) h").tag($0) }
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
                } header: {
                    Text("Duration")
                } footer: {
                    if wasTrimmed {
                        Text("The timer ran for more than 24 hours, so it was trimmed. Adjust the duration if needed.")
                    }
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
                            .accessibilityLabel("\(i) \(i == 1 ? "star" : "stars")")
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

                if editing != nil {
                    Section {
                        Button("Delete session", role: .destructive) { confirmDelete = true }
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
            .alert("Couldn't save", isPresented: $saveFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your device may be out of storage. Nothing was changed — free up some space and try again.")
            }
            .confirmationDialog("Delete this session?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete session", role: .destructive, action: deleteSession)
            } message: {
                Text("This also removes the XP it earned.")
            }
        }
        .presentationDetents([.large])
    }

    private func deleteSession() {
        guard let editing else { return }
        context.delete(editing)
        if context.commit() { dismiss() } else { saveFailed = true }
    }

    private func save() {
        let cleaned = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        if let editing {
            editing.subject = subject
            editing.startDate = date
            editing.duration = totalSeconds
            editing.focus = focus
            editing.notes = cleaned
            if context.commit() { dismiss() } else { saveFailed = true }
            return
        }

        let storedBadges = Set(badges.map(\.badgeID))
        let existing = allSessions
        let before = GameEngine.snapshot(sessions: existing, goals: goals, stored: storedBadges)

        let session = StudySession(subject: subject, startDate: date, duration: totalSeconds,
                                   notes: cleaned, focus: focus)
        context.insert(session)
        // Only report success (and let the timer reset) once the session is really on disk.
        guard context.commit() else {
            saveFailed = true
            return
        }

        let afterSessions = existing.filter { $0.persistentModelID != session.persistentModelID } + [session]
        let after = GameEngine.snapshot(sessions: afterSessions, goals: goals, stored: storedBadges)
        GameEngine.syncBadges(context: context)

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
