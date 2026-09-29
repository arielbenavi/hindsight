import Foundation

/// hindsight's X app (developer.x.com → Project → hindsight-ios).
/// Must be a "Native App" (public client, PKCE, no secret) with callback
/// `hindsight://oauth/x`. A native client ID is public, so it lives in code.
enum XConfig {
    static let clientID = ""
    static let callbackScheme = "hindsight"
    static let redirectURI = "hindsight://oauth/x"
    static let scopes = "tweet.read users.read bookmark.read offline.access"

    static var isConfigured: Bool { !clientID.isEmpty }
}
