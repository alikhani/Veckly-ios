import Foundation
@testable import Veckly

/// Minimal doubles for building an `AuthSessionStore` (and so an `AppModel`)
/// in tests without touching the Keychain or the network.
final class InMemoryAuthSessionStorage: AuthSessionPersisting {
    var session: AuthSession?
    init(session: AuthSession? = nil) { self.session = session }
    func load() -> AuthSession? { session }
    func save(_ session: AuthSession) { self.session = session }
    func clear() { session = nil }
}

final class StubAuthService: AuthServicing {
    var refreshResult: Result<AuthSession, SupabaseAuthError> = .failure(.unknown)
    /// Thrown instead of `refreshResult` when set — lets a test fail the refresh with a non-auth error such as `URLError`.
    var refreshFailure: Error?
    private(set) var refreshTokens: [String] = []

    func signInWithEmail(email: String, password: String) async throws -> AuthSession { throw SupabaseAuthError.unknown }
    func signUpWithEmail(email: String, password: String, redirectTo: URL) async throws -> AuthSession? { nil }
    func signInWithApple(identityToken: String, nonce: String?) async throws -> AuthSession { throw SupabaseAuthError.unknown }
    func resendSignupConfirmation(email: String, redirectTo: URL) async throws {}
    func requestPasswordReset(email: String, redirectTo: URL) async throws {}
    func updatePassword(_ password: String, accessToken: String) async throws {}
    func deleteUser(accessToken: String) async throws {}
    func refreshSession(refreshToken: String) async throws -> AuthSession {
        refreshTokens.append(refreshToken)
        if let refreshFailure { throw refreshFailure }
        return try refreshResult.get()
    }
}

enum AuthTestTokens {
    static func jwt(subject: String, expiresIn: TimeInterval = 3_600) -> String {
        let payload: [String: Any] = ["sub": subject, "exp": Date().timeIntervalSince1970 + expiresIn]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(encoded).signature"
    }
}
