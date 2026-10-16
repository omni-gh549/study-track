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
    @AppStorage("didSeedSampleData") private var didSeed = false
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
        .task {
            if !didSeed {
                SampleData.seed(context)
                didSeed = true
            }
        }
    }
}

#Preview {
    RootView().modelContainer(PreviewData.container)
}
