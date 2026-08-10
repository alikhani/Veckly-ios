import SwiftUI

struct EmailAuthView: View {
    enum Mode { case signIn, signUp, forgotPassword }

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var passwordConfirmation = ""

    private var store: AuthSessionStore { appModel.authSessionStore }
    private var validEmail: Bool { email.contains("@") && email.contains(".") }
    private var validPassword: Bool { password.count >= 8 }
    private var canSubmit: Bool {
        switch mode {
        case .signIn: validEmail && !password.isEmpty
        case .signUp: validEmail && validPassword && password == passwordConfirmation
        case .forgotPassword: validEmail
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let confirmationEmail = store.confirmationEmail {
                        inboxPanel(
                            title: "auth.checkInbox.title",
                            message: L10n.format("auth.checkInbox.confirmation", confirmationEmail),
                            actionTitle: "auth.resendConfirmation"
                        ) { await store.resendConfirmation() }
                    } else if let resetEmail = store.resetEmail {
                        inboxPanel(
                            title: "auth.checkInbox.title",
                            message: L10n.format("auth.checkInbox.reset", resetEmail)
                        )
                    } else {
                        authForm
                    }

                    if let message = store.errorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityLabel(L10n.format("accessibility.error.message", message))
                    }
                }
                .padding(24)
            }
            .background(Color("canvas"))
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.dismiss") { dismiss() }
                }
            }
            .interactiveDismissDisabled(store.isSigningIn)
        }
    }

    @ViewBuilder private var authForm: some View {
        if mode != .forgotPassword {
            Picker("auth.mode", selection: $mode) {
                Text("auth.signIn").tag(Mode.signIn)
                Text("auth.createAccount").tag(Mode.signUp)
            }
            .pickerStyle(.segmented)
        }

        Text(mode == .forgotPassword ? "auth.forgotPassword.help" : "auth.email.help")
            .font(.subheadline)
            .foregroundStyle(Color("textMuted"))

        VStack(spacing: 14) {
            TextField("auth.email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(mode == .forgotPassword ? .send : .next)
                .textFieldStyle(.roundedBorder)

            if mode != .forgotPassword {
                SecureField("auth.password", text: $password)
                    .textContentType(mode == .signUp ? .newPassword : .password)
                    .textFieldStyle(.roundedBorder)
                if mode == .signUp {
                    SecureField("auth.passwordConfirmation", text: $passwordConfirmation)
                        .textContentType(.newPassword)
                        .textFieldStyle(.roundedBorder)
                    Text("auth.passwordRequirement")
                        .font(.caption)
                        .foregroundStyle(Color("textMuted"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }

        Button {
            Task { await submit() }
        } label: {
            Group {
                if store.isSigningIn { ProgressView().tint(.white) }
                else { Text(submitTitle) }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(VecklyPrimaryButtonStyle())
        .disabled(!canSubmit || store.isSigningIn)

        Button(mode == .forgotPassword ? "auth.backToSignIn" : "auth.forgotPassword") {
            store.clearNotices()
            mode = mode == .forgotPassword ? .signIn : .forgotPassword
            password = ""
            passwordConfirmation = ""
        }
        .font(.subheadline.weight(.medium))
        .frame(maxWidth: .infinity)
    }

    private func inboxPanel(
        title: LocalizedStringKey,
        message: String,
        actionTitle: LocalizedStringKey? = nil,
        action: (@MainActor () async -> Void)? = nil
    ) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 42))
                .foregroundStyle(VecklyDesign.Colors.hearthOrangeFill)
                .accessibilityHidden(true)
            Text(title).font(.title2.bold()).multilineTextAlignment(.center)
            Text(message).foregroundStyle(Color("textMuted")).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle) { Task { await action() } }
                    .buttonStyle(.bordered)
                    .disabled(store.isSigningIn)
            }
            Button("auth.backToSignIn") {
                store.clearNotices()
                mode = .signIn
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var navigationTitle: LocalizedStringKey {
        switch mode {
        case .signIn: "auth.signIn"
        case .signUp: "auth.createAccount"
        case .forgotPassword: "auth.forgotPassword"
        }
    }

    private var submitTitle: LocalizedStringKey {
        switch mode {
        case .signIn: "auth.signIn"
        case .signUp: "auth.createAccount"
        case .forgotPassword: "auth.sendResetLink"
        }
    }

    private func submit() async {
        switch mode {
        case .signIn: await appModel.signInWithEmail(email: email, password: password)
        case .signUp: await appModel.signUpWithEmail(email: email, password: password)
        case .forgotPassword: await store.requestPasswordReset(email: email)
        }
    }
}

struct PasswordRecoveryView: View {
    @Environment(AppModel.self) private var appModel
    @State private var password = ""
    @State private var confirmation = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("auth.newPassword.help")
                    .foregroundStyle(Color("textMuted"))
                SecureField("auth.newPassword", text: $password)
                    .textContentType(.newPassword)
                    .textFieldStyle(.roundedBorder)
                SecureField("auth.passwordConfirmation", text: $confirmation)
                    .textContentType(.newPassword)
                    .textFieldStyle(.roundedBorder)
                Text("auth.passwordRequirement")
                    .font(.caption)
                    .foregroundStyle(Color("textMuted"))

                if let message = appModel.authSessionStore.errorMessage {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }

                Button {
                    Task { await appModel.updateRecoveredPassword(password) }
                } label: {
                    Group {
                        if appModel.authSessionStore.isSigningIn { ProgressView().tint(.white) }
                        else { Text("auth.saveNewPassword") }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(VecklyPrimaryButtonStyle())
                .disabled(password.count < 8 || password != confirmation || appModel.authSessionStore.isSigningIn)
                Spacer()
            }
            .padding(24)
            .background(Color("canvas"))
            .navigationTitle("auth.newPassword")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { appModel.authSessionStore.cancelPasswordRecovery() }
                }
            }
        }
        .interactiveDismissDisabled()
    }
}
