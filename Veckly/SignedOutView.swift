import SwiftUI

struct SignedOutView: View {
    @Environment(AppModel.self) private var appModel

    private let weekDays = ["Mon", "Tue", "Wed", "Thu", "Fri"]
    private let accentDay = "Tue"

    var body: some View {
        ZStack {
            Color("canvas").ignoresSafeArea()

            VStack(spacing: 0) {

                // Brand cluster — anchored in the upper portion of the screen.
                // Chips sit inside this cluster as a subtle product hint, not a
                // standalone control row.
                VStack(spacing: 0) {
                    Image("VecklyMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 58, height: 58)
                        .accessibilityHidden(true)

                    Text("Veckly")
                        .font(VecklyDesign.Typography.displayHeading(size: 52))
                        .foregroundStyle(Color("textPrimary"))
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 20)

                    Text("Plan the week once. Know what's for dinner before the day starts.")
                        .font(.title3)
                        .foregroundStyle(Color("textMuted"))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 240)
                        .padding(.top, 12)

                    // Week chip strip — presentational only, no data binding.
                    // Auto-width so chips read as an ambient hint, not a picker.
                    HStack(spacing: 8) {
                        ForEach(weekDays, id: \.self) { day in
                            Text(day)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(day == accentDay ? Color.white : Color("textMuted"))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(
                                    day == accentDay
                                        ? VecklyDesign.Colors.hearthOrange
                                        : Color("chipSurface")
                                )
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.top, 20)
                }
                .padding(.top, 80)
                .frame(maxWidth: .infinity)

                // Deliberate breathing room — the space between brand and CTA
                // should feel calm and intentional, not like a layout accident.
                Spacer()

                // Auth block — pressed against the bottom of the safe area
                // so the button lands in the natural thumb zone.
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

                    if appModel.environment.enableDevLogin {
                        Button {
                            Task { await appModel.signInAsDev() }
                        } label: {
                            Text("Sign in as dev")
                                .font(.subheadline)
                                .foregroundStyle(VecklyDesign.Colors.inkMid)
                                .underline()
                        }
                        .buttonStyle(.plain)
                        .disabled(appModel.authSessionStore.isSigningIn)
                        .accessibilityIdentifier("signInAsDevButton")
                    }

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
                                .foregroundStyle(Color("textMuted"))
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

                    // Legal footer — plain text; no Terms/Privacy routes yet.
                    Text("By continuing you agree to our Terms & Privacy Policy.")
                        .font(.caption2)
                        .foregroundStyle(Color("textMuted"))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 24)
        }
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
