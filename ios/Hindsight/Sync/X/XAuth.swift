import CryptoKit
import Foundation

/// OAuth 2.0 Authorization Code + PKCE against X, as a public client.
/// The user signs in on X's own page; we only ever see a token scoped to
/// reading *their* bookmarks.
enum XAuth {
    struct Tokens: Codable, Sendable {
        var accessToken: String
        var refreshToken: String?
        var expiresAt: Date

        var isExpired: Bool { expiresAt < .now.addingTimeInterval(60) }
    }

    struct PKCE: Sendable {
        let verifier: String
        let challenge: String
        let state: String

        static func make() -> PKCE {
            let verifier = randomURLSafe(bytes: 48)
            return PKCE(verifier: verifier, challenge: challenge(for: verifier), state: randomURLSafe(bytes: 16))
        }

        /// S256: base64url(SHA256(verifier)).
        static func challenge(for verifier: String) -> String {
            base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        }
    }

    enum AuthError: LocalizedError {
        case notConfigured, stateMismatch, missingCode, tokenRequest(String)
        var errorDescription: String? {
            switch self {
            case .notConfigured: "X isn't set up yet (missing client ID)."
            case .stateMismatch, .missingCode: "X sign-in didn't finish. Try again."
            case .tokenRequest(let detail): "X refused the sign-in: \(detail)"
            }
        }
    }

    static func authorizeURL(pkce: PKCE) -> URL {
        var components = URLComponents(string: "https://x.com/i/oauth2/authorize")!
        components.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: XConfig.clientID),
            .init(name: "redirect_uri", value: XConfig.redirectURI),
            .init(name: "scope", value: XConfig.scopes),
            .init(name: "state", value: pkce.state),
            .init(name: "code_challenge", value: pkce.challenge),
            .init(name: "code_challenge_method", value: "S256"),
        ]
        return components.url!
    }

    /// Pulls the authorization code out of `hindsight://oauth/x?state=…&code=…`.
    static func code(from callback: URL, pkce: PKCE) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == pkce.state else { throw AuthError.stateMismatch }
        guard let code = items.first(where: { $0.name == "code" })?.value else { throw AuthError.missingCode }
        return code
    }

    static func exchange(code: String, pkce: PKCE) async throws -> Tokens {
        try await tokenRequest([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": XConfig.redirectURI,
            "code_verifier": pkce.verifier,
            "client_id": XConfig.clientID,
        ])
    }

    static func refresh(_ tokens: Tokens) async throws -> Tokens {
        guard let refreshToken = tokens.refreshToken else { throw AuthError.tokenRequest("no refresh token") }
        return try await tokenRequest([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": XConfig.clientID,
        ])
    }

    private static func tokenRequest(_ form: [String: String]) async throws -> Tokens {
        var request = URLRequest(url: URL(string: "https://api.x.com/2/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((body.percentEncodedQuery ?? "").utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AuthError.tokenRequest(String(decoding: data.prefix(300), as: UTF8.self))
        }
        struct Response: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Double
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return Tokens(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token,
            expiresAt: .now.addingTimeInterval(decoded.expires_in)
        )
    }

    private static func randomURLSafe(bytes count: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        return base64URL(Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) }))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// X tokens in the Keychain (this device only).
enum XTokenStore {
    private static var query: [String: Any] { [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "hindsight.x",
        kSecAttrAccount as String: "oauth",
    ] }

    static func load() -> XAuth.Tokens? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        var result: AnyObject?
        guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(XAuth.Tokens.self, from: data)
    }

    static func save(_ tokens: XAuth.Tokens) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    static func clear() {
        SecItemDelete(query as CFDictionary)
    }
}
