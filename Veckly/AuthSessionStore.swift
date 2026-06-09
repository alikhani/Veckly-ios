import Foundation
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
        accessToken = session.accessToken
        userID = session.userID
    }

    func signInWithApple(identityToken: String, nonce: String?) async {
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }

        do {
            let session = try await SupabaseAuthClient(environment: environment)
                .signInWithApple(identityToken: identityToken, nonce: nonce)
            accessToken = session.accessToken
            userID = session.userID
            sessionStorage.save(session)
        } catch {
            errorMessage = "We could not sign you in. Try again in a moment."
        }
    }

    func signInWithEmail(email: String, password: String) async {
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }

        do {
            let session = try await SupabaseAuthClient(environment: environment)
                .signInWithEmail(email: email, password: password)
            accessToken = session.accessToken
            userID = session.userID
            sessionStorage.save(session)
        } catch {
            errorMessage = "We could not sign you in. Check your email and password."
        }
    }

    func signUpWithEmail(email: String, password: String) async {
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }

        do {
            let session = try await SupabaseAuthClient(environment: environment)
                .signUpWithEmail(email: email, password: password)
            accessToken = session.accessToken
            userID = session.userID
            sessionStorage.save(session)
        } catch SupabaseAuthError.emailConfirmationRequired {
            errorMessage = "Check your email to confirm your account, then sign in."
        } catch {
            errorMessage = "We could not create that account. Try a different email or password."
        }
    }

    func signOut() {
        accessToken = nil
        userID = nil
        errorMessage = nil
        sessionStorage.clear()
    }

    func seedForUITests() {
        accessToken = "ui-test-token"
        userID = "11111111-1111-1111-1111-111111111111"
        isRestoring = false
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
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    func save(_ session: AuthSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
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
