import SwiftData
import SwiftUI

@main
struct StudyTrackApp: App {
    private let container = Persistence.makeContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}

enum AppTab: Hashable {
    case today, timer, goals, history, profile
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("didOnboard") private var didOnboard = false
    @AppStorage("storeWasRecovered") private var storeWasRecovered = false
    @State private var showOnboarding = false
    @State private var tab: AppTab = .today
    @State private var celebrations = CelebrationCenter()
    @State private var timer = TimerModel.shared
    @State private var updates = UpdateService()

    var body: some View {
        TabView(selection: $tab) {
            DashboardView(openTimer: { tab = .timer })
                .tabItem { Label("Today", systemImage: "chart.bar.fill") }
                .tag(AppTab.today)
            TimerView()
                .tabItem { Label("Timer", systemImage: "timer") }
                .tag(AppTab.timer)
            GoalsView()
                .tabItem { Label("Goals", systemImage: "target") }
                .tag(AppTab.goals)
            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(AppTab.history)
            ProfileView()
                .tabItem { Label("Profile", systemImage: "trophy.fill") }
                .tag(AppTab.profile)
        }
        .overlay { CelebrationOverlay(center: celebrations) }
        .environment(celebrations)
        .environment(timer)
        .environment(updates)
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                didOnboard = true
                showOnboarding = false
            }
        }
        .alert("Your data file couldn't be opened", isPresented: $storeWasRecovered) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The damaged file was set aside safely and the app started fresh. Restore your latest backup in Profile › Settings (automatic backups are in Files › On My iPhone › StudyTrack › Backups).")
        }
        .task {
            if ProcessInfo.processInfo.environment["UITEST_SEED"] == "1" {
                SampleData.seed(context)
                didOnboard = true
            }
            FreezeGifts.applyPending(context: context)
            GameEngine.syncBadges(context: context)
            await updates.autoCheckIfDue()
            guard !didOnboard else { return }
            let existing = (try? context.fetchCount(FetchDescriptor<Subject>())) ?? 0
            if existing == 0 { showOnboarding = true } else { didOnboard = true }
        }
        // Flush to disk whenever the app leaves the foreground, so a kill never loses the last edit.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                timer.reload()
                GameEngine.syncBadges(context: context)
                Task { await updates.autoCheckIfDue() }
            } else {
                context.commit()
                if phase == .background { AutoBackup.snapshotIfNeeded(context: context) }
            }
        }
    }
}

#Preview {
    RootView().modelContainer(PreviewData.container)
}
