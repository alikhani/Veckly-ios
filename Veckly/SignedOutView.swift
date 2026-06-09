import SwiftUI

struct SignedOutView: View {
    @Environment(AppModel.self) private var appModel
    @State private var email = ""
    @State private var password = ""
    @State private var isCreatingAccount = false

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
                    VStack(spacing: 10) {
                        Picker("Auth mode", selection: $isCreatingAccount) {
                            Text("Sign in").tag(false)
                            Text("Create account").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("authModePicker")

                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 12)
                            .frame(height: 44)
                            .background(VecklyDesign.Colors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .accessibilityIdentifier("emailField")

                        SecureField("Password", text: $password)
                            .textContentType(isCreatingAccount ? .newPassword : .password)
                            .padding(.horizontal, 12)
                            .frame(height: 44)
                            .background(VecklyDesign.Colors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .accessibilityIdentifier("passwordField")

                        Button {
                            Task {
                                if isCreatingAccount {
                                    await appModel.signUpWithEmail(email: email, password: password)
                                } else {
                                    await appModel.signInWithEmail(email: email, password: password)
                                }
                            }
                        } label: {
                            Text(isCreatingAccount ? "Create account" : "Sign in")
                        }
                        .buttonStyle(VecklyPrimaryButtonStyle())
                        .disabled(appModel.authSessionStore.isSigningIn || !canSubmitEmailPassword)
                        .opacity(canSubmitEmailPassword ? 1 : 0.65)
                        .accessibilityIdentifier("emailPasswordSubmitButton")
                    }

                    HStack {
                        Rectangle()
                            .fill(VecklyDesign.Colors.edgeLight)
                            .frame(height: 1)
                        Text("or")
                            .font(.caption)
                            .foregroundStyle(VecklyDesign.Colors.inkFaint)
                        Rectangle()
                            .fill(VecklyDesign.Colors.edgeLight)
                            .frame(height: 1)
                    }

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

    private var canSubmitEmailPassword: Bool {
        email.contains("@") && password.count >= 6
    }
}
