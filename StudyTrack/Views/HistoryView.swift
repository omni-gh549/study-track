import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \StudySession.startDate, order: .reverse) private var sessions: [StudySession]
    @State private var search = ""
    @State private var showingAdd = false
    @State private var showingSubjects = false
    @State private var editing: StudySession?
    @State private var pendingDelete: StudySession?
    @State private var deleteFailed = false

    private struct DayGroup: Identifiable {
        let day: Date
        let sessions: [StudySession]
        var id: Date { day }
        var total: TimeInterval { sessions.reduce(0) { $0 + $1.duration } }
    }

    private var filtered: [StudySession] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return sessions }
        return sessions.filter {
            $0.notes.localizedCaseInsensitiveContains(term)
                || ($0.subject?.name.localizedCaseInsensitiveContains(term) ?? false)
        }
    }

    private var groups: [DayGroup] {
        Dictionary(grouping: filtered) { Calendar.current.startOfDay(for: $0.startDate) }
            .map { DayGroup(day: $0.key, sessions: $0.value) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.sessions) { session in
                            Button { editing = session } label: {
                                SessionRow(session: session).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) { pendingDelete = session } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text(group.day, format: .dateTime.weekday(.wide).month().day())
                            Spacer()
                            Text(group.total.studyDuration)
                        }
                    }
                }
            }
            .overlay {
                if sessions.isEmpty {
                    ContentUnavailableView("No sessions yet", systemImage: "book.closed",
                                           description: Text("Tap + or use the timer to log your first session."))
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .searchable(text: $search, prompt: "Search subjects and notes")
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Subjects", systemImage: "square.grid.2x2") { showingSubjects = true }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Session", systemImage: "plus") { showingAdd = true }
                }
            }
            .sheet(isPresented: $showingAdd) { SessionFormView() }
            .sheet(isPresented: $showingSubjects) { SubjectsView() }
            .sheet(item: $editing) { SessionFormView(session: $0) }
            .confirmationDialog("Delete this session?", isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ), titleVisibility: .visible, presenting: pendingDelete) { session in
                Button("Delete session", role: .destructive) {
                    context.delete(session)
                    if !context.commit() { deleteFailed = true }
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: { session in
                Text("\(session.duration.studyDuration) of \(session.subject?.name ?? "study") will be removed, along with the XP it earned.")
            }
            .alert("Couldn't delete", isPresented: $deleteFailed) {
                Button("OK", role: .cancel) {}
            }
        }
    }
}

#Preview {
    HistoryView().modelContainer(PreviewData.container)
}
