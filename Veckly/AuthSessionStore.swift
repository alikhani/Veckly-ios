import Foundation
import Security
import Observation

@MainActor
@Observable
final class AuthSessionStore {
    static let callbackURL = URL(string: "veckly://auth-callback")!

    private let authClient: any AuthServicing
    private let sessionStorage: any AuthSessionPersisting
    private var recoverySession: AuthSession?
    private var refreshTask: Task<Bool, Never>?

    private(set) var accessToken: String?
    private(set) var userID: String?
    private(set) var isRestoring = true
    private(set) var isSigningIn = false
    private(set) var errorMessage: String?
    private(set) var confirmationEmail: String?
    private(set) var resetEmail: String?
    private(set) var isPasswordRecoveryActive = false
    private(set) var passwordWasUpdated = false

    var isSignedIn: Bool { accessToken != nil }

    init(environment: AppEnvironment) {
        self.authClient = SupabaseAuthClient(environment: environment)
        self.sessionStorage = KeychainSessionStorage()
    }

    init(authClient: any AuthServicing, sessionStorage: any AuthSessionPersisting) {
        self.authClient = authClient
        self.sessionStorage = sessionStorage
    }

    func restoreSession() async {
        defer { isRestoring = false }
        if accessToken != nil { return }
        guard let session = sessionStorage.load() else { return }

        if JWTClaims.isExpired(session.accessToken) {
            guard let refreshToken = session.refreshToken,
                  await attemptRefresh(refreshToken: refreshToken) else {
                sessionStorage.clear()
                return
            }
        } else {
            accessToken = session.accessToken
            userID = session.userID
        }
    }

    func signInWithApple(identityToken: String, nonce: String?) async {
        await performAuth(errorKey: "error.auth.signInMoment") {
            try await authClient.signInWithApple(identityToken: identityToken, nonce: nonce)
        }
    }

    func signInWithEmail(email: String, password: String) async {
        confirmationEmail = nil
        await performAuth(errorKey: "error.auth.signInEmailPassword") {
            try await authClient.signInWithEmail(email: email.trimmed, password: password)
        }
    }

    func signUpWithEmail(email: String, password: String) async {
        isSigningIn = true
        errorMessage = nil
        confirmationEmail = nil
        defer { isSigningIn = false }

        do {
            if let session = try await authClient.signUpWithEmail(
                email: email.trimmed,
                password: password,
                redirectTo: Self.callbackURL
            ) {
                applySession(session)
            } else {
                confirmationEmail = email.trimmed
            }
        } catch {
            errorMessage = localizedMessage(for: error, fallbackKey: "error.auth.createAccount")
        }
    }

    func resendConfirmation() async {
        guard let confirmationEmail else { return }
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }
        do {
            try await authClient.resendSignupConfirmation(email: confirmationEmail, redirectTo: Self.callbackURL)
        } catch {
            errorMessage = localizedMessage(for: error, fallbackKey: "error.auth.resendConfirmation")
        }
    }

    func requestPasswordReset(email: String) async {
        isSigningIn = true
        errorMessage = nil
        resetEmail = nil
        defer { isSigningIn = false }
        do {
            try await authClient.requestPasswordReset(email: email.trimmed, redirectTo: Self.callbackURL)
            resetEmail = email.trimmed
        } catch {
            errorMessage = localizedMessage(for: error, fallbackKey: "error.auth.passwordReset")
        }
    }

    @discardableResult
    func handleAuthCallback(_ url: URL) -> Bool {
        guard let callback = AuthCallback(url: url) else { return false }
        errorMessage = nil

        if callback.error != nil {
            errorMessage = L10n.string("error.auth.linkExpired")
            return true
        }
        guard let session = callback.session else {
            errorMessage = L10n.string("error.auth.linkInvalid")
            return true
        }

        if callback.kind == .recovery {
            recoverySession = session
            isPasswordRecoveryActive = true
        } else {
            confirmationEmail = nil
            applySession(session)
        }
        return true
    }

    func updateRecoveredPassword(_ password: String) async -> Bool {
        guard let recoverySession else {
            errorMessage = L10n.string("error.auth.linkExpired")
            return false
        }
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }
        do {
            try await authClient.updatePassword(password, accessToken: recoverySession.accessToken)
            self.recoverySession = nil
            isPasswordRecoveryActive = false
            passwordWasUpdated = true
            applySession(recoverySession)
            return true
        } catch {
            errorMessage = localizedMessage(for: error, fallbackKey: "error.auth.updatePassword")
            return false
        }
    }

    func cancelPasswordRecovery() {
        recoverySession = nil
        isPasswordRecoveryActive = false
    }

    func clearNotices() {
        confirmationEmail = nil
        resetEmail = nil
        passwordWasUpdated = false
        errorMessage = nil
    }

    func signOut() {
        accessToken = nil
        userID = nil
        recoverySession = nil
        isPasswordRecoveryActive = false
        clearNotices()
        sessionStorage.clear()
    }

    func deleteAccount() async throws {
        guard let token = accessToken else { return }
        try await authClient.deleteUser(accessToken: token)
        signOut()
    }

    func refreshSession() async -> Bool {
        guard let stored = sessionStorage.load(), let refreshToken = stored.refreshToken else { return false }
        return await attemptRefresh(refreshToken: refreshToken)
    }

    func currentValidToken() async -> String? {
        guard let token = accessToken else { return nil }
        if !JWTClaims.isExpired(token) { return token }
        return await refreshSession() ? accessToken : nil
    }

    func setError(_ message: String) { errorMessage = message }

    func seedForUITests() {
        accessToken = "ui-test-token"
        userID = "11111111-1111-1111-1111-111111111111"
        isRestoring = false
    }

    private func performAuth(errorKey: String, operation: () async throws -> AuthSession) async {
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }
        do {
            applySession(try await operation())
        } catch {
            errorMessage = localizedMessage(for: error, fallbackKey: errorKey)
        }
    }

    private func applySession(_ session: AuthSession) {
        accessToken = session.accessToken
        userID = session.userID
        sessionStorage.save(session)
    }

    @discardableResult
    private func attemptRefresh(refreshToken: String) async -> Bool {
        if let refreshTask { return await refreshTask.value }
        let task = Task<Bool, Never> {
            do {
                applySession(try await authClient.refreshSession(refreshToken: refreshToken))
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

    private func localizedMessage(for error: Error, fallbackKey: String) -> String {
        if error is URLError { return L10n.string("error.auth.network") }
        guard let authError = error as? SupabaseAuthError else { return L10n.string(fallbackKey) }
        switch authError {
        case .invalidCredentials: return L10n.string("error.auth.invalidCredentials")
        case .alreadyRegistered: return L10n.string("error.auth.alreadyRegistered")
        case .weakPassword: return L10n.string("error.auth.weakPassword")
        case .rateLimited: return L10n.string("error.auth.rateLimited")
        case .emailNotConfirmed: return L10n.string("error.auth.emailNotConfirmed")
        case .linkExpired: return L10n.string("error.auth.linkExpired")
        case .unknown: return L10n.string(fallbackKey)
        }
    }
}

struct AuthSession: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let userID: String
}

protocol AuthSessionPersisting {
    func load() -> AuthSession?
    func save(_ session: AuthSession)
    func clear()
}

struct KeychainSessionStorage: AuthSessionPersisting {
    private let key = "veckly.auth-session"

    func load() -> AuthSession? {
        guard let data = keychainLoad() else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    func save(_ session: AuthSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrAccount: key]
        let attributes: [CFString: Any] = [kSecValueData: data, kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = data
            addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    func clear() {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrAccount: key]
        SecItemDelete(query as CFDictionary)
    }

    private func keychainLoad() -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess ? result as? Data : nil
    }
}

protocol AuthServicing {
    func signInWithEmail(email: String, password: String) async throws -> AuthSession
    func signUpWithEmail(email: String, password: String, redirectTo: URL) async throws -> AuthSession?
    func signInWithApple(identityToken: String, nonce: String?) async throws -> AuthSession
    func resendSignupConfirmation(email: String, redirectTo: URL) async throws
    func requestPasswordReset(email: String, redirectTo: URL) async throws
    func updatePassword(_ password: String, accessToken: String) async throws
    func deleteUser(accessToken: String) async throws
    func refreshSession(refreshToken: String) async throws -> AuthSession
}

struct SupabaseAuthClient: AuthServicing {
    let environment: AppEnvironment

    func signInWithEmail(email: String, password: String) async throws -> AuthSession {
        try await sessionRequest(path: "/auth/v1/token", query: ["grant_type": "password"], body: EmailPasswordRequest(email: email, password: password))
    }

    func signUpWithEmail(email: String, password: String, redirectTo: URL) async throws -> AuthSession? {
        let data = try await request(path: "/auth/v1/signup", query: ["redirect_to": redirectTo.absoluteString], body: EmailPasswordRequest(email: email, password: password))
        let payload = try JSONDecoder().decode(AuthResponse.self, from: data)
        guard let token = payload.accessToken else { return nil }
        return try payload.session(accessToken: token)
    }

    func signInWithApple(identityToken: String, nonce: String?) async throws -> AuthSession {
        try await sessionRequest(path: "/auth/v1/token", query: ["grant_type": "id_token"], body: SignInRequest(provider: "apple", idToken: identityToken, nonce: nonce))
    }

    func resendSignupConfirmation(email: String, redirectTo: URL) async throws {
        _ = try await request(path: "/auth/v1/resend", query: ["redirect_to": redirectTo.absoluteString], body: ResendRequest(email: email, type: "signup"))
    }

    func requestPasswordReset(email: String, redirectTo: URL) async throws {
        _ = try await request(path: "/auth/v1/recover", query: ["redirect_to": redirectTo.absoluteString], body: EmailRequest(email: email))
    }

    func updatePassword(_ password: String, accessToken: String) async throws {
        _ = try await request(path: "/auth/v1/user", method: "PUT", body: PasswordRequest(password: password), bearerToken: accessToken)
    }

    func deleteUser(accessToken: String) async throws {
        _ = try await request(path: "/auth/v1/user", method: "DELETE", bearerToken: accessToken)
    }

    func refreshSession(refreshToken: String) async throws -> AuthSession {
        try await sessionRequest(path: "/auth/v1/token", query: ["grant_type": "refresh_token"], body: RefreshTokenRequest(refreshToken: refreshToken))
    }

    private func sessionRequest<Body: Encodable>(path: String, query: [String: String], body: Body) async throws -> AuthSession {
        let data = try await request(path: path, query: query, body: body)
        let payload = try JSONDecoder().decode(AuthResponse.self, from: data)
        guard let token = payload.accessToken else { throw SupabaseAuthError.unknown }
        return try payload.session(accessToken: token)
    }

    private func request<Body: Encodable>(
        path: String,
        query: [String: String] = [:],
        method: String = "POST",
        body: Body? = Optional<String>.none,
        bearerToken: String? = nil
    ) async throws -> Data {
        var components = URLComponents(url: environment.supabaseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue(environment.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(bearerToken ?? environment.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try JSONEncoder().encode(body) }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SupabaseAuthError(data: data, statusCode: (response as? HTTPURLResponse)?.statusCode)
        }
        return data
    }
}

enum SupabaseAuthError: Error, Equatable {
    case invalidCredentials, alreadyRegistered, weakPassword, rateLimited, emailNotConfirmed, linkExpired, unknown

    init(data: Data, statusCode: Int?) {
        if statusCode == 429 { self = .rateLimited; return }
        let code = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.errorCode ?? ""
        switch code {
        case "invalid_credentials": self = .invalidCredentials
        case "user_already_exists", "user_already_registered": self = .alreadyRegistered
        case "weak_password": self = .weakPassword
        case "email_not_confirmed": self = .emailNotConfirmed
        case "otp_expired": self = .linkExpired
        default: self = .unknown
        }
    }
}

struct AuthCallback: Equatable {
    enum Kind: String { case signup, recovery, invite, magiclink, unknown }
    let kind: Kind
    let session: AuthSession?
    let error: String?

    init?(url: URL) {
        guard url.scheme?.lowercased() == "veckly", url.host == "auth-callback" else { return nil }
        let fragmentItems = URLComponents(string: "?\(url.fragment ?? "")")?.queryItems ?? []
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let values = Dictionary((fragmentItems + queryItems).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        self.kind = Kind(rawValue: values["type"] ?? "") ?? .unknown
        self.error = values["error"] ?? values["error_code"]
        if let token = values["access_token"], let userID = JWTClaims.userID(token) {
            self.session = AuthSession(accessToken: token, refreshToken: values["refresh_token"], userID: userID)
        } else {
            self.session = nil
        }
    }
}

enum JWTClaims {
    static func isExpired(_ token: String, now: Date = Date()) -> Bool {
        guard let exp = payload(token)?["exp"] as? TimeInterval else { return true }
        return now.timeIntervalSince1970 >= exp - 60
    }

    static func userID(_ token: String) -> String? { payload(token)?["sub"] as? String }

    private static func payload(_ token: String) -> [String: Any]? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else { return nil }
        var base64 = String(segments[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
}

private struct EmailPasswordRequest: Encodable { let email: String; let password: String }
private struct EmailRequest: Encodable { let email: String }
private struct PasswordRequest: Encodable { let password: String }
private struct ResendRequest: Encodable { let email: String; let type: String }
private struct RefreshTokenRequest: Encodable {
    let refreshToken: String
    enum CodingKeys: String, CodingKey { case refreshToken = "refresh_token" }
}
private struct SignInRequest: Encodable {
    let provider: String
    let idToken: String
    let nonce: String?
    enum CodingKeys: String, CodingKey { case provider; case idToken = "id_token"; case nonce }
}
private struct AuthResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let user: User?
    let id: String?
    enum CodingKeys: String, CodingKey { case accessToken = "access_token"; case refreshToken = "refresh_token"; case user; case id }
    struct User: Decodable { let id: String }

    func session(accessToken: String) throws -> AuthSession {
        guard let userID = user?.id ?? id ?? JWTClaims.userID(accessToken) else { throw SupabaseAuthError.unknown }
        return AuthSession(accessToken: accessToken, refreshToken: refreshToken, userID: userID)
    }
}
private struct ErrorResponse: Decodable {
    let errorCode: String?
    enum CodingKeys: String, CodingKey { case errorCode = "error_code" }
}
