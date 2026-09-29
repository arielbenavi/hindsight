import AuthenticationServices
import SwiftUI

/// "Connect X" row: sign in on X's own page, then pull bookmarks into the store.
struct XConnectRow: View {
    let store: SavedPostStore
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var status: Status = XTokenStore.load() == nil ? .idle : .connected(nil)

    enum Status: Equatable {
        case idle
        case working(String)
        case connected(Int?)
        case failed(String)
    }

    var body: some View {
        HStack(spacing: 14) {
            PlatformBadge(platform: .x)
            VStack(alignment: .leading, spacing: 2) {
                Text(Platform.x.displayName).font(OnboardingStyle.title)
                Text(detail)
                    .font(OnboardingStyle.caption)
                    .foregroundStyle(OnboardingStyle.muted)
            }
            Spacer()
            trailing
        }
        .onboardingCard(padding: 16)
    }

    private var detail: String {
        switch status {
        case .idle: XConfig.isConfigured ? "Sign in with X. No developer account needed." : "Needs hindsight's X client ID (dev)."
        case .working(let step): step
        case .connected(let count?): "\(count.formatted()) bookmarks synced."
        case .connected(nil): "Connected. Tap to sync again."
        case .failed(let message): message
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch status {
        case .working:
            ProgressView()
        case .connected:
            Button { Task { await connect() } } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(OnboardingStyle.accent)
            }
            .accessibilityLabel("Sync X again")
        case .idle, .failed:
            Button(status == .idle ? "Connect" : "Retry") { Task { await connect() } }
                .font(.system(.subheadline, design: .rounded, weight: .heavy))
                .foregroundStyle(OnboardingStyle.onAccent)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(OnboardingStyle.accent, in: .capsule)
                .disabled(!XConfig.isConfigured)
                .opacity(XConfig.isConfigured ? 1 : 0.4)
        }
    }

    private func connect() async {
        do {
            let tokens = try await validTokens()
            status = .working("Pulling your bookmarks…")
            let posts = try await XBookmarks.fetchAll(accessToken: tokens.accessToken)
            let added = store.merge(posts)
            DebugLog.write("x sync: \(posts.count) bookmarks, \(added) new")
            status = .connected(posts.count)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            status = .idle
        } catch XBookmarks.APIError.status(401, _) {
            XTokenStore.clear()
            status = .failed("X sign-in expired. Tap Retry.")
        } catch {
            DebugLog.write("x sync failed: \(error)")
            status = .failed(error.localizedDescription)
        }
    }

    /// Saved tokens (refreshed if stale), or a fresh sign-in on X's page.
    private func validTokens() async throws -> XAuth.Tokens {
        if var tokens = XTokenStore.load() {
            if tokens.isExpired {
                status = .working("Refreshing X sign-in…")
                tokens = try await XAuth.refresh(tokens)
                XTokenStore.save(tokens)
            }
            return tokens
        }
        guard XConfig.isConfigured else { throw XAuth.AuthError.notConfigured }
        status = .working("Signing in on X…")
        let pkce = XAuth.PKCE.make()
        let callback = try await webAuthenticationSession.authenticate(
            using: XAuth.authorizeURL(pkce: pkce),
            callback: .customScheme(XConfig.callbackScheme),
            preferredBrowserSession: .shared,
            additionalHeaderFields: [:]
        )
        let tokens = try await XAuth.exchange(code: XAuth.code(from: callback, pkce: pkce), pkce: pkce)
        XTokenStore.save(tokens)
        return tokens
    }
}
