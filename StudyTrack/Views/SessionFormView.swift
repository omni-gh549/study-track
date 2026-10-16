import SwiftData
import SwiftUI

/// Used for both manual entry and saving a finished timer run.
struct SessionFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Subject.name) private var subjects: [Subject]

    @State private var subject: Subject?
    @State private var date: Date
    @State private var hours: Int
    @State private var minutes: Int
    @State private var focus = 3
    @State private var notes = ""

    init(subject: Subject? = nil, date: Date = .now, duration: TimeInterval = 3600) {
        _subject = State(initialValue: subject)
        _date = State(initialValue: date)
        let total = max(Int((duration / 60).rounded()), 1)
        _hours = State(initialValue: min(total / 60, 12))
        _minutes = State(initialValue: total % 60)
    }

    private var totalSeconds: TimeInterval { TimeInterval((hours * 60 + minutes) * 60) }

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

                Section("How focused were you?") {
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
                }

                Section("Notes") {
                    TextField("What did you cover?", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("New Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(totalSeconds == 0)
                }
            }
            .onAppear { if subject == nil { subject = subjects.first } }
        }
        .presentationDetents([.large])
    }

    private func save() {
        context.insert(StudySession(subject: subject,
                                    startDate: date,
                                    duration: totalSeconds,
                                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                                    focus: focus))
        dismiss()
    }
}

#Preview {
    SessionFormView().modelContainer(PreviewData.container)
}
