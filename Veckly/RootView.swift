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
            // Seeded UI-test data must stay network-free — a real
            // `loadCoreReader()` here (scenePhase turns `.active` moments
            // after launch) would otherwise silently overwrite the seed
            // with a load error. Full app-wide network-free UI-test mode is
            // Fas 7 scope; this is the one call site that needs it today.
            guard !appModel.usesSeededCoreReader else { return }
            guard newPhase == .active, appModel.authSessionStore.isSignedIn else { return }
            Task {
                await appModel.loadCoreReader()
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
