import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if appModel.authSessionStore.isRestoring {
                LoadingView(title: L10n.string("app.opening"))
            } else if appModel.authSessionStore.isSignedIn {
                MainTabView()
                    .fullScreenCover(isPresented: Binding(
                        get: { appModel.needsOnboarding },
                        set: { _ in }
                    )) {
                        OnboardingFlowView()
                            .environment(appModel)
                    }
            } else {
                SignedOutView()
            }
        }
        .task {
            await appModel.restoreSession()
            await appModel.refreshSundayReminderIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // The actual scene-active refresh logic — de-duping concurrent
            // callers, skipping the reload entirely when data is still
            // fresh, and never touching the network under seeded UI-test
            // data — now lives in `AppRefreshCoordinator` (Fas 7). This is
            // just the view-level trigger: is the phase transition one we
            // care about, and is anyone signed in to refresh for.
            guard newPhase == .active, appModel.authSessionStore.isSignedIn else { return }
            Task {
                await appModel.refreshCoordinator.refreshCoreReader(trigger: .sceneActive)
                await appModel.refreshSundayReminderIfNeeded()
            }
        }
    }
}

struct LoadingView: View {
    let title: String

    var body: some View {
        ZStack {
            VecklyDesign.Colors.canvas.ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .tint(VecklyDesign.Colors.hearthOrange)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(VecklyDesign.Colors.inkDeep)
            }
        }
    }
}
