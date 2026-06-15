import SwiftUI

struct SignedOutView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        ZStack {
            VecklyDesign.Colors.canvas.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Veckly")
                        .font(.custom("Georgia-Bold", size: 52))
                        .foregroundStyle(VecklyDesign.Colors.inkDeep)
                        .accessibilityAddTraits(.isHeader)

                    Text("Plan the week once. Know what dinner is before the day starts.")
                        .font(.title3)
                        .foregroundStyle(VecklyDesign.Colors.inkMid)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                VStack(spacing: 12) {
                    AppleSignInButton(
                        isLoading: appModel.authSessionStore.isSigningIn,
                        onComplete: { token, nonce in
                            Task { await appModel.completeSignInWithApple(identityToken: token, nonce: nonce) }
                        },
                        onFailure: {
                            appModel.authSessionStore.setError("Sign in with Apple failed. Please try again.")
                        }
                    )

//                    Button {
//                        withAnimation(.spring(duration: 0.28)) { showEmailForm.toggle() }
//                    } label: {
//                        HStack(spacing: 4) {
//                            Text(showEmailForm ? "Hide email options" : "Use email instead")
//                                .font(.subheadline)
//                                .foregroundStyle(VecklyDesign.Colors.inkMid)
//                            Image(systemName: showEmailForm ? "chevron.up" : "chevron.down")
//                                .font(.caption.weight(.semibold))
//                                .foregroundStyle(VecklyDesign.Colors.inkFaint)
//                        }
//                    }
//                    .buttonStyle(.plain)
//                    .frame(maxWidth: .infinity, alignment: .center)
//
//                    if showEmailForm {
//                        VStack(spacing: 10) {
//                            Picker("Account action", selection: $isCreatingAccount) {
//                                Text("Sign in").tag(false)
//                                Text("Create account").tag(true)
//                            }
//                            .pickerStyle(.segmented)
//
//                            TextField("Email", text: $email)
//                                .textContentType(.emailAddress)
//                                .keyboardType(.emailAddress)
//                                .textInputAutocapitalization(.never)
//                                .autocorrectionDisabled()
//                                .foregroundStyle(VecklyDesign.Colors.inkDeep)
//                                .tint(VecklyDesign.Colors.hearthOrange)
//                                .padding(.horizontal, 14)
//                                .frame(height: 48)
//                                .background(VecklyDesign.Colors.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
//                                .overlay {
//                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
//                                        .stroke(VecklyDesign.Colors.edgeLight, lineWidth: 1)
//                                }
//
//                            SecureField("Password", text: $password)
//                                .textContentType(isCreatingAccount ? .newPassword : .password)
//                                .foregroundStyle(VecklyDesign.Colors.inkDeep)
//                                .tint(VecklyDesign.Colors.hearthOrange)
//                                .padding(.horizontal, 14)
//                                .frame(height: 48)
//                                .background(VecklyDesign.Colors.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
//                                .overlay {
//                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
//                                        .stroke(VecklyDesign.Colors.edgeLight, lineWidth: 1)
//                                }
//
//                            Button {
//                                Task {
//                                    if isCreatingAccount {
//                                        await appModel.signUpWithEmail(email: email, password: password)
//                                    } else {
//                                        await appModel.signInWithEmail(email: email, password: password)
//                                    }
//                                }
//                            } label: {
//                                Text(isCreatingAccount ? "Create account" : "Sign in")
//                            }
//                            .buttonStyle(VecklyPrimaryButtonStyle())
//                            .disabled(appModel.authSessionStore.isSigningIn || !canSubmitEmailPassword)
//                            .opacity(canSubmitEmailPassword ? 1 : 0.45)
//                        }
//                        .transition(.opacity.combined(with: .move(edge: .top)))
//                    }

                    if appModel.authSessionStore.isSigningIn {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(VecklyDesign.Colors.hearthOrange)
                            Text("Signing in…")
                                .font(.footnote)
                                .foregroundStyle(VecklyDesign.Colors.inkMid)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Signing in, please wait")
                    }

                    if let message = appModel.authSessionStore.errorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Color(red: 0.80, green: 0.15, blue: 0.10))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel("Error: \(message)")
                    }
                }

                Spacer(minLength: 56)
            }
            .padding(.horizontal, 24)
        }
        .preferredColorScheme(.light)
    }

//    @State private var email = ""
//    @State private var password = ""
//    @State private var isCreatingAccount = false
//    @State private var showEmailForm = false
//
//    private var canSubmitEmailPassword: Bool {
//        email.contains("@") && password.count >= 6
//    }
}
