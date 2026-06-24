import SwiftUI

struct SignedOutView: View {
    @Environment(AppModel.self) private var appModel

    private let weekDays = Weekday.allCases.prefix(5)
    private let accentDay = Weekday.tuesday

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

                    Text("auth.title")
                        .font(VecklyDesign.Typography.displayHeading(size: 52))
                        .foregroundStyle(Color("textPrimary"))
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 20)

                    Text("auth.subtitle")
                        .font(.title3)
                        .foregroundStyle(Color("textMuted"))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 240)
                        .padding(.top, 12)

                    // Week chip strip — presentational only, no data binding.
                    // Auto-width so chips read as an ambient hint, not a picker.
                    HStack(spacing: 8) {
                        ForEach(Array(weekDays), id: \.self) { day in
                            Text(day.shortDisplayName)
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
                        onComplete: { token, nonce, givenName, familyName in
                            Task {
                                await appModel.completeSignInWithApple(
                                    identityToken: token,
                                    nonce: nonce,
                                    givenName: givenName,
                                    familyName: familyName
                                )
                            }
                        },
                        onFailure: {
                            appModel.authSessionStore.setError(L10n.string("auth.appleFailed"))
                        }
                    )

                    if appModel.authSessionStore.isSigningIn {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(VecklyDesign.Colors.hearthOrange)
                            Text("auth.signingIn")
                                .font(.footnote)
                                .foregroundStyle(Color("textMuted"))
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(L10n.string("accessibility.signingInWait"))
                    }

                    #if DEBUG
                    Button {
                        Task {
                            await appModel.authSessionStore.signInWithEmail(
                                email: DebugTestAccount.current.email,
                                password: DebugTestAccount.current.password
                            )
                        }
                    } label: {
                        Text("Sign in as test user")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Color("textMuted"))
                    }
                    .disabled(appModel.authSessionStore.isSigningIn)
                    .padding(.top, 4)
                    #endif

                    if let message = appModel.authSessionStore.errorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Color(red: 0.80, green: 0.15, blue: 0.10))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel(L10n.format("accessibility.error.message", message))
                    }

                    // Legal footer — plain text; no Terms/Privacy routes yet.
                    Text("auth.legal")
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
}
