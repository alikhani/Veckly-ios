import SwiftUI

struct SignedOutView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        ZStack {
            VecklyDesign.Colors.canvas.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 28) {
                Spacer()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Veckly")
                        .font(.system(size: 48, weight: .bold, design: .serif))
                        .foregroundStyle(VecklyDesign.Colors.inkDeep)
                        .accessibilityIdentifier("signedOutTitle")

                    Text("Plan the week once. Know what dinner is before the day starts.")
                        .font(.title3)
                        .foregroundStyle(VecklyDesign.Colors.inkMid)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 12) {
                    AppleSignInButton(isLoading: appModel.authSessionStore.isSigningIn) { token, nonce in
                        Task {
                            await appModel.completeSignInWithApple(identityToken: token, nonce: nonce)
                        }
                    }

                    if appModel.authSessionStore.isSigningIn {
                        ProgressView("Signing in")
                            .tint(VecklyDesign.Colors.hearthOrange)
                            .font(.footnote)
                    }

                    if let errorMessage = appModel.authSessionStore.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()
            }
            .padding(24)
        }
    }
}
