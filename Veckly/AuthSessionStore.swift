import Foundation
import Security
import Observation

@MainActor
@Observable
final class AuthSessionStore {
    private let environment: AppEnvironment
    private let sessionStorage = SessionStorage()

    private(set) var accessToken: String?
    private(set) var userID: String?
    private(set) var isRestoring = true
    private(set) var isSigningIn = false
    private(set) var errorMessage: String?

    var isSignedIn: Bool {
        accessToken != nil
    }

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func restoreSession() async {
        defer { isRestoring = false }
        if accessToken != nil { return }
        guard let session = sessionStorage.load() else { return }

        if isTokenExpired(session.accessToken) {
            guard let refreshToken = session.refreshToken else {
                sessionStorage.clear()
                return
            }
            guard await attemptRefresh(refreshToken: refreshToken) else {
                sessionStorage.clear()
                return
            }
        } else {
            accessToken = session.accessToken
            userID = session.userID
        }
    }

    func signInWithApple(identityToken: String, nonce: String?) async {
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }

        do {
            let session = try await SupabaseAuthClient(environment: environment)
                .signInWithApple(identityToken: identityToken, nonce: nonce)
            applySession(session)
        } catch {
            errorMessage = L10n.string("error.auth.signInMoment")
        }
    }

    func signInWithEmail(email: String, password: String) async {
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }

        do {
            let session = try await SupabaseAuthClient(environment: environment)
                .signInWithEmail(email: email, password: password)
            applySession(session)
        } catch {
            errorMessage = L10n.string("error.auth.signInEmailPassword")
        }
    }

    func signUpWithEmail(email: String, password: String) async {
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }

        do {
            let session = try await SupabaseAuthClient(environment: environment)
                .signUpWithEmail(email: email, password: password)
            applySession(session)
        } catch SupabaseAuthError.emailConfirmationRequired {
            errorMessage = L10n.string("auth.confirmEmail")
        } catch {
            errorMessage = L10n.string("error.auth.createAccount")
        }
    }

    func signOut() {
        accessToken = nil
        userID = nil
        errorMessage = nil
        sessionStorage.clear()
    }

    func deleteAccount() async throws {
        guard let token = accessToken else { return }
        try await SupabaseAuthClient(environment: environment).deleteUser(accessToken: token)
        signOut()
    }

    // Returns true if the token was refreshed successfully and session is now valid.
    func refreshSession() async -> Bool {
        guard let stored = sessionStorage.load(), let refreshToken = stored.refreshToken else {
            return false
        }
        return await attemptRefresh(refreshToken: refreshToken)
    }

    // Returns a valid access token, refreshing it first if it is expired or about to expire.
    func currentValidToken() async -> String? {
        guard let token = accessToken else { return nil }
        if !isTokenExpired(token) { return token }
        let refreshed = await refreshSession()
        return refreshed ? accessToken : nil
    }

    func setError(_ message: String) {
        errorMessage = message
    }

    func seedForUITests() {
        accessToken = "ui-test-token"
        userID = "11111111-1111-1111-1111-111111111111"
        isRestoring = false
    }

    // MARK: - Private

    private func applySession(_ session: AuthSession) {
        accessToken = session.accessToken
        userID = session.userID
        sessionStorage.save(session)
    }

    // Coalesces concurrent refresh attempts into one network call — without this,
    // several requests hitting an expired token at once would each independently
    // refresh, and if Supabase rotates the refresh token, the losing attempt fails
    // and spuriously signs the user out.
    private var refreshTask: Task<Bool, Never>?

    @discardableResult
    private func attemptRefresh(refreshToken: String) async -> Bool {
        if let refreshTask { return await refreshTask.value }

        let task = Task<Bool, Never> {
            do {
                let session = try await SupabaseAuthClient(environment: environment)
                    .refreshSession(refreshToken: refreshToken)
                applySession(session)
                return true
            } catch {
                return false
            }
        }
        refreshTask = task
        let result = await task.value
        refreshTask = nil
        return result
    }

    // Decodes the JWT payload (middle segment) and checks the `exp` claim.
    // No signature verification — that's the server's job. We just need to know
    // if the token is worth sending before making a network call.
    private func isTokenExpired(_ token: String) -> Bool {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else { return true }

        var base64 = String(segments[1])
        let remainder = base64.count % 4
        if remainder != 0 { base64 += String(repeating: "=", count: 4 - remainder) }

        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = payload["exp"] as? TimeInterval else {
            return true
        }

        return Date().timeIntervalSince1970 >= exp - 60
    }
}

struct AuthSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let userID: String
}

private struct SessionStorage {
    private let key = "veckly.auth-session"

    func load() -> AuthSession? {
        guard let data = keychainLoad() else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    func save(_ session: AuthSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        keychainSave(data)
    }

    func clear() {
        keychainDelete()
    }

    // MARK: - Keychain

    private func keychainLoad() -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func keychainSave(_ data: Data) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
        ]
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = data
            addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private func keychainDelete() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private struct SupabaseAuthClient {
    let environment: AppEnvironment

    func signInWithEmail(email: String, password: String) async throws -> AuthSession {
        var components = URLComponents(url: environment.supabaseURL.appending(path: "/auth/v1/token"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "grant_type", value: "password")]

        var request = authenticatedRequest(url: components.url!)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(EmailPasswordRequest(email: email, password: password))

        return try await sendSessionRequest(request)
    }

    func signUpWithEmail(email: String, password: String) async throws -> AuthSession {
        let url = environment.supabaseURL.appending(path: "/auth/v1/signup")
        var request = authenticatedRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(EmailPasswordRequest(email: email, password: password))

        return try await sendSessionRequest(request)
    }

    func signInWithApple(identityToken: String, nonce: String?) async throws -> AuthSession {
        var components = URLComponents(url: environment.supabaseURL.appending(path: "/auth/v1/token"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "grant_type", value: "id_token")]

        var request = authenticatedRequest(url: components.url!)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(SignInRequest(provider: "apple", idToken: identityToken, nonce: nonce))

        return try await sendSessionRequest(request)
    }

    func deleteUser(accessToken: String) async throws {
        let url = environment.supabaseURL.appending(path: "/auth/v1/user")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(environment.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    func refreshSession(refreshToken: String) async throws -> AuthSession {
        var components = URLComponents(url: environment.supabaseURL.appending(path: "/auth/v1/token"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]

        var request = authenticatedRequest(url: components.url!)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(RefreshTokenRequest(refreshToken: refreshToken))

        return try await sendSessionRequest(request)
    }

    private func authenticatedRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(environment.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(environment.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func sendSessionRequest(_ request: URLRequest) async throws -> AuthSession {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.userAuthenticationRequired)
        }

        let payload = try JSONDecoder().decode(SignInResponse.self, from: data)
        guard let accessToken = payload.accessToken else {
            throw SupabaseAuthError.emailConfirmationRequired
        }

        return AuthSession(accessToken: accessToken, refreshToken: payload.refreshToken, userID: payload.user.id)
    }
}

private enum SupabaseAuthError: Error {
    case emailConfirmationRequired
}

private struct EmailPasswordRequest: Encodable {
    let email: String
    let password: String
}

private struct RefreshTokenRequest: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

private struct SignInRequest: Encodable {
    let provider: String
    let idToken: String
    let nonce: String?

    enum CodingKeys: String, CodingKey {
        case provider
        case idToken = "id_token"
        case nonce
    }
}

private struct SignInResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let user: User

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case user
    }

    struct User: Decodable {
        let id: String
    }
}
