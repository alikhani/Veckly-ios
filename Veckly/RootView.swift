import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Group {
            if appModel.authSessionStore.isRestoring {
                LoadingView(title: "Opening Veckly")
            } else if appModel.authSessionStore.isSignedIn {
                MainTabView()
            } else {
                SignedOutView()
            }
        }
        .task {
            await appModel.restoreSession()
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
