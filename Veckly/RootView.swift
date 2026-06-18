import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if appModel.authSessionStore.isRestoring {
                LoadingView(title: "Opening Veckly")
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
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, appModel.authSessionStore.isSignedIn else { return }
            Task { await appModel.loadCoreReader() }
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
