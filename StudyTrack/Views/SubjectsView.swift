import SwiftData
import SwiftUI

struct SubjectsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Subject.name) private var subjects: [Subject]
    @State private var editing: Subject?
    @State private var showingNew = false
    @State private var pendingDelete: Subject?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(subjects) { subject in
                        Button { editing = subject } label: {
                            HStack(spacing: 12) {
                                SubjectBadge(subject: subject)
                                VStack(alignment: .leading) {
                                    Text(subject.name).foregroundStyle(.primary)
                                    Text("\(subject.sessions.count) sessions")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        if let i = offsets.first { pendingDelete = subjects[i] }
                    }
                } footer: {
                    Text("Deleting a subject keeps its sessions (they show as “No subject”) but removes its goals.")
                }
            }
            .overlay {
                if subjects.isEmpty {
                    ContentUnavailableView("No subjects", systemImage: "square.grid.2x2",
                                           description: Text("Add a subject to start logging."))
                }
            }
            .navigationTitle("Subjects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Subject", systemImage: "plus") { showingNew = true }
                }
            }
            .sheet(isPresented: $showingNew) { SubjectFormView(subject: nil) }
            .sheet(item: $editing) { SubjectFormView(subject: $0) }
            .confirmationDialog("Delete this subject?", isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ), titleVisibility: .visible, presenting: pendingDelete) { subject in
                Button("Delete \(subject.name)", role: .destructive) {
                    context.delete(subject)
                    pendingDelete = nil
                }
            } message: { subject in
                Text("\(subject.sessions.count) sessions will be kept without a subject. Its goals will be removed.")
            }
        }
    }
}

struct SubjectFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let subject: Subject?
    @State private var name: String
    @State private var color: SubjectColor
    @State private var icon: String

    private static let icons = [
        "book.fill", "function", "atom", "globe.europe.africa.fill",
        "laptopcomputer", "paintpalette.fill", "music.note", "brain.head.profile",
        "pencil.and.ruler.fill", "character.book.closed.fill", "leaf.fill", "chart.bar.fill",
    ]

    init(subject: Subject?) {
        self.subject = subject
        _name = State(initialValue: subject?.name ?? "")
        _color = State(initialValue: subject?.subjectColor ?? .blue)
        _icon = State(initialValue: subject?.icon ?? "book.fill")
    }

    private let columns = Array(repeating: GridItem(.flexible()), count: 5)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: icon)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(color.color.gradient,
                                        in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        TextField("Subject name", text: $name)
                    }
                }
                Section("Colour") {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(SubjectColor.allCases) { c in
                            Button { color = c } label: {
                                Circle().fill(c.color)
                                    .frame(width: 36, height: 36)
                                    .overlay {
                                        if c == color {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(c.rawValue.capitalized)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Icon") {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(Self.icons, id: \.self) { symbol in
                            Button { icon = symbol } label: {
                                Image(systemName: symbol)
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                                    .foregroundStyle(symbol == icon ? Color.white : Color.primary)
                                    .background(symbol == icon ? color.color : Color(.tertiarySystemFill),
                                                in: Circle())
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(subject == nil ? "New Subject" : "Edit Subject")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let subject {
            subject.name = trimmed
            subject.subjectColor = color
            subject.icon = icon
        } else {
            context.insert(Subject(name: trimmed, color: color, icon: icon))
        }
        dismiss()
    }
}

#Preview {
    SubjectsView().modelContainer(PreviewData.container)
}
