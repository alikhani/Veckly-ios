import SwiftUI

struct SignedOutView: View {
    @Environment(AppModel.self) private var appModel
    @State private var email = ""
    @State private var password = ""
    @State private var isCreatingAccount = false
    @State private var showEmailForm = false

    var body: some View {
        ZStack {
            VecklyDesign.Colors.canvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.top, 52)

                    Color.clear.frame(height: 52)

                    authSection

                    Color.clear.frame(height: 48)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.light)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "fork.knife")
                .font(.title2.weight(.medium))
                .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                .accessibilityHidden(true)
                .padding(.bottom, 6)

            Text("Veckly")
                .font(.custom("Georgia-Bold", size: 52))
                .foregroundStyle(VecklyDesign.Colors.inkDeep)
                .accessibilityAddTraits(.isHeader)

            Text("Plan the week once.\nKnow what dinner is before the day starts.")
                .font(.title3)
                .foregroundStyle(VecklyDesign.Colors.inkMid)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Auth section

    private var authSection: some View {
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

            emailToggleButton

            if showEmailForm {
                emailForm
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if appModel.authSessionStore.isSigningIn {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(VecklyDesign.Colors.hearthOrange)
                    Text("Signing in…")
                        .font(.footnote)
                        .foregroundStyle(VecklyDesign.Colors.inkMid)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Signing in, please wait")
            }

            if let message = appModel.authSessionStore.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Color(red: 0.80, green: 0.15, blue: 0.10))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
                    .accessibilityLabel("Error: \(message)")
            }
        }
    }

    private var emailToggleButton: some View {
        Button {
            withAnimation(.spring(duration: 0.28)) {
                showEmailForm.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Text(showEmailForm ? "Hide email options" : "Use email instead")
                    .font(.subheadline)
                    .foregroundStyle(VecklyDesign.Colors.inkMid)
                Image(systemName: showEmailForm ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VecklyDesign.Colors.inkFaint)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 2)
        .accessibilityLabel(showEmailForm ? "Hide email sign-in" : "Sign in with email")
        .accessibilityHint(showEmailForm ? "Collapses the email form" : "Shows email and password fields")
    }

    private var emailForm: some View {
        VStack(spacing: 10) {
            Picker("Account action", selection: $isCreatingAccount) {
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
                .foregroundStyle(VecklyDesign.Colors.inkDeep)
                .tint(VecklyDesign.Colors.hearthOrange)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(VecklyDesign.Colors.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(VecklyDesign.Colors.edgeLight, lineWidth: 1)
                }
                .accessibilityIdentifier("emailField")
                .accessibilityLabel("Email address")

            SecureField("Password", text: $password)
                .textContentType(isCreatingAccount ? .newPassword : .password)
                .foregroundStyle(VecklyDesign.Colors.inkDeep)
                .tint(VecklyDesign.Colors.hearthOrange)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(VecklyDesign.Colors.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(VecklyDesign.Colors.edgeLight, lineWidth: 1)
                }
                .accessibilityIdentifier("passwordField")
                .accessibilityLabel("Password")
                .accessibilityHint(isCreatingAccount ? "Must be at least 6 characters" : "")

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
            .opacity(canSubmitEmailPassword ? 1 : 0.45)
            .accessibilityIdentifier("emailPasswordSubmitButton")
            .accessibilityHint(
                !canSubmitEmailPassword
                    ? "Enter a valid email and a password with at least 6 characters"
                    : ""
            )
        }
        .padding(.top, 4)
    }

    private var canSubmitEmailPassword: Bool {
        email.contains("@") && password.count >= 6
    }
}
