import Foundation
import Testing
@testable import Veckly

@MainActor
struct AuthSessionStoreTests {
    @Test func signUpWithoutSessionShowsConfirmationAndCanResend() async {
        let client = FakeAuthClient()
        client.signUpSession = nil
        let store = AuthSessionStore(authClient: client, sessionStorage: MemorySessionStorage())

        await store.signUpWithEmail(email: "  FAMILY@example.com ", password: "long-enough")
        #expect(store.confirmationEmail == "family@example.com")
        #expect(store.isSignedIn == false)

        await store.resendConfirmation()
        #expect(client.resentEmail == "family@example.com")
        #expect(client.lastRedirect == AuthSessionStore.callbackURL)
    }

    @Test func confirmationCallbackPersistsSession() {
        let storage = MemorySessionStorage()
        let store = AuthSessionStore(authClient: FakeAuthClient(), sessionStorage: storage)
        let token = testJWT(subject: "confirmed-user")
        let url = URL(string: "veckly://auth-callback#access_token=\(token)&refresh_token=refresh&type=signup")!

        #expect(store.handleAuthCallback(url))
        #expect(store.userID == "confirmed-user")
        #expect(storage.session?.refreshToken == "refresh")
    }

    @Test func recoveryCallbackWaitsForNewPasswordBeforeSigningIn() async {
        let client = FakeAuthClient()
        let storage = MemorySessionStorage()
        let store = AuthSessionStore(authClient: client, sessionStorage: storage)
        let token = testJWT(subject: "recovering-user")
        let url = URL(string: "veckly://auth-callback#access_token=\(token)&refresh_token=recovered&type=recovery")!

        #expect(store.handleAuthCallback(url))
        #expect(store.isPasswordRecoveryActive)
        #expect(store.isSignedIn == false)

        #expect(await store.updateRecoveredPassword("new-password"))
        #expect(client.updatedPassword == "new-password")
        #expect(store.userID == "recovering-user")
        #expect(storage.session?.refreshToken == "recovered")
    }

    @Test func coldLaunchRestoresSavedValidSession() async {
        let session = AuthSession(accessToken: testJWT(subject: "saved-user"), refreshToken: "refresh", userID: "saved-user")
        let storage = MemorySessionStorage(session: session)
        let store = AuthSessionStore(authClient: FakeAuthClient(), sessionStorage: storage)

        await store.restoreSession()
        #expect(store.userID == "saved-user")
        #expect(store.isRestoring == false)
    }

    @Test func expiredTokenRefreshesOnceAndRotatesSavedSession() async {
        let old = AuthSession(accessToken: testJWT(subject: "user", expiresIn: -120), refreshToken: "old-refresh", userID: "user")
        let fresh = AuthSession(accessToken: testJWT(subject: "user"), refreshToken: "new-refresh", userID: "user")
        let client = FakeAuthClient()
        client.refreshSessionValue = fresh
        let storage = MemorySessionStorage(session: old)
        let store = AuthSessionStore(authClient: client, sessionStorage: storage)

        await store.restoreSession()
        #expect(client.refreshTokens == ["old-refresh"])
        #expect(storage.session == fresh)
        #expect(store.isSignedIn)
    }

    @Test func revokedRefreshTokenClearsSavedSession() async {
        let old = AuthSession(accessToken: testJWT(subject: "user", expiresIn: -120), refreshToken: "revoked", userID: "user")
        let client = FakeAuthClient()
        client.refreshError = .invalidCredentials
        let storage = MemorySessionStorage(session: old)
        let store = AuthSessionStore(authClient: client, sessionStorage: storage)

        await store.restoreSession()
        #expect(store.isSignedIn == false)
        #expect(storage.session == nil)
    }

    private func testJWT(subject: String, expiresIn: TimeInterval = 3_600) -> String {
        let payload: [String: Any] = ["sub": subject, "exp": Date().timeIntervalSince1970 + expiresIn]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(encoded).signature"
    }
}

private final class FakeAuthClient: AuthServicing {
    var signUpSession: AuthSession?
    var refreshSessionValue: AuthSession?
    var refreshError: SupabaseAuthError?
    var refreshTokens: [String] = []
    var resentEmail: String?
    var updatedPassword: String?
    var lastRedirect: URL?

    func signInWithEmail(email: String, password: String) async throws -> AuthSession { try requiredSession() }
    func signInWithApple(identityToken: String, nonce: String?) async throws -> AuthSession { try requiredSession() }
    func signUpWithEmail(email: String, password: String, redirectTo: URL) async throws -> AuthSession? {
        lastRedirect = redirectTo
        return signUpSession
    }
    func resendSignupConfirmation(email: String, redirectTo: URL) async throws {
        resentEmail = email
        lastRedirect = redirectTo
    }
    func requestPasswordReset(email: String, redirectTo: URL) async throws { lastRedirect = redirectTo }
    func updatePassword(_ password: String, accessToken: String) async throws { updatedPassword = password }
    func deleteUser(accessToken: String) async throws {}
    func refreshSession(refreshToken: String) async throws -> AuthSession {
        refreshTokens.append(refreshToken)
        if let refreshError { throw refreshError }
        return try requiredSession(refreshSessionValue)
    }

    private func requiredSession(_ value: AuthSession? = nil) throws -> AuthSession {
        guard let session = value ?? signUpSession else { throw SupabaseAuthError.unknown }
        return session
    }
}

private final class MemorySessionStorage: AuthSessionPersisting {
    var session: AuthSession?
    init(session: AuthSession? = nil) { self.session = session }
    func load() -> AuthSession? { session }
    func save(_ session: AuthSession) { self.session = session }
    func clear() { session = nil }
}
