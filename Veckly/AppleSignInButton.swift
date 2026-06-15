import AuthenticationServices
import CryptoKit
import Security
import SwiftUI

struct AppleSignInButton: View {
    let isLoading: Bool
    let onComplete: (String, String?) -> Void
    let onFailure: () -> Void

    @State private var currentNonce: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        SignInWithAppleButton(.continue) { request in
            let nonce = Self.randomNonceString()
            currentNonce = nonce
            request.requestedScopes = [.email, .fullName]
            request.nonce = Self.sha256(nonce)
        } onCompletion: { result in
            switch result {
            case .success(let authorization):
                guard
                    let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                    let tokenData = credential.identityToken,
                    let token = String(data: tokenData, encoding: .utf8)
                else {
                    onFailure()
                    return
                }
                onComplete(token, currentNonce)
            case .failure(let error):
                let code = (error as? ASAuthorizationError)?.code
                guard code != .canceled && code != .unknown else { return }
                onFailure()
            }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 48)
        .clipShape(Capsule())
        .disabled(isLoading)
        .opacity(isLoading ? 0.7 : 1)
        .accessibilityIdentifier("continueWithAppleButton")
        .accessibilityLabel("Continue with Apple")
    }

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var random: UInt8 = 0
            let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            guard errorCode == errSecSuccess else { continue }
            if random < charset.count {
                result.append(charset[Int(random)])
                remainingLength -= 1
            }
        }

        return result
    }

    private static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
}
