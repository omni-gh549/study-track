import SwiftData
import SwiftUI

@main
struct StudyTrackApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Subject.self, StudySession.self, Goal.self])
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("didOnboard") private var didOnboard = false
    @State private var showOnboarding = false
    @State private var celebrations = CelebrationCenter()

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Today", systemImage: "chart.bar.fill") }
            TimerView()
                .tabItem { Label("Timer", systemImage: "timer") }
            GoalsView()
                .tabItem { Label("Goals", systemImage: "target") }
            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            ProfileView()
                .tabItem { Label("Profile", systemImage: "trophy.fill") }
        }
        .overlay { CelebrationOverlay(center: celebrations) }
        .environment(celebrations)
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                didOnboard = true
                showOnboarding = false
            }
        }
        .task {
            guard !didOnboard else { return }
            let existing = (try? context.fetchCount(FetchDescriptor<Subject>())) ?? 0
            if existing == 0 { showOnboarding = true } else { didOnboard = true }
        }
        // Flush to disk whenever the app leaves the foreground, so a kill never loses the last edit.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { try? context.save() }
        }
    }
}

#Preview {
    RootView().modelContainer(PreviewData.container)
}
