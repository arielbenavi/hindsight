import SwiftUI
import WebKit

/// A save's own embed player (Instagram, TikTok, X, YouTube, Facebook) or an article,
/// in a web view. Shows a spinner while loading, and "Can't play this one here" when
/// the embed fails or is a dead end. Links that leave the embed open outside.
struct EmbedPlayer: View {
    let post: ContractPost
    let source: EmbedSource
    @State private var phase: EmbedPhase = .loading
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Color.black
            if phase != .failed {
                EmbedWebView(source: source, phase: $phase) { url in
                    PostOpener.open(url, openURL: openURL)
                }
                .opacity(phase == .loading ? 0.01 : 1)  // drawn (so it loads), hidden until ready
            }
            switch phase {
            case .loading:
                ProgressView().controlSize(.large).tint(Theme.lime)
            case .failed:
                fallback
            case .ready:
                EmptyView()
            }
        }
        .animation(.easeOut(duration: 0.2), value: phase)
    }

    private var fallback: some View {
        VStack(spacing: 14) {
            Image(systemName: "play.slash.fill").font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.muted)
            Text("Can't play this one here").font(Theme.body(18, weight: .heavy)).foregroundStyle(Theme.text)
            Button { PostOpener.open(post, openURL: openURL) } label: {
                Label("Open in \(post.platform.displayName)", systemImage: "arrow.up.right")
            }
            .buttonStyle(.pillCompactPrimary)
        }
        .padding(24)
    }
}

enum EmbedPhase: Equatable { case loading, ready, failed }

/// The web view itself. Default (persistent) website data store, so signing in to
/// Instagram here once sticks.
struct EmbedWebView: UIViewRepresentable {
    let source: EmbedSource
    @Binding var phase: EmbedPhase
    let openOutside: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = true
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.backgroundColor = .black
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.customUserAgent = Coordinator.safariUserAgent
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        #if DEBUG
        web.isInspectable = true
        #endif
        context.coordinator.load(source, in: web)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.loaded != source { context.coordinator.load(source, in: web) }
    }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.stopLoading()
        // Stops audio when the sheet closes.
        web.pauseAllMediaPlayback()
        web.loadHTMLString("", baseURL: nil)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        /// Safari on iOS 26. Some embeds serve a cut-down page to an unknown web view.
        static let safariUserAgent =
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"

        var parent: EmbedWebView
        var loaded: EmbedSource?
        private var firstLoadDone = false
        private var checkTask: Task<Void, Never>?

        init(_ parent: EmbedWebView) { self.parent = parent }

        func load(_ source: EmbedSource, in web: WKWebView) {
            loaded = source
            firstLoadDone = false
            parent.phase = .loading
            switch source {
            case .url(let url): web.load(URLRequest(url: url))
            case .html(let html, let base): web.loadHTMLString(html, baseURL: base)
            }
        }

        private var embedHost: String? {
            switch loaded {
            case .url(let url): url.host()?.lowercased()
            case .html(_, let base): base.host()?.lowercased()
            case nil: nil
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = action.request.url else { return .cancel }
            let scheme = url.scheme?.lowercased() ?? ""
            if ["about", "blob", "data", "javascript"].contains(scheme) { return .allow }
            // Iframes inside the embed (X's tweet, players) do what they like.
            if action.targetFrame?.isMainFrame == false { return .allow }
            guard scheme == "http" || scheme == "https" else {
                parent.openOutside(url)  // instagram://, tiktok:// …
                return .cancel
            }
            if !firstLoadDone && action.navigationType != .linkActivated { return .allow }  // the embed and its redirects
            // Anything the user taps that leaves the embed ("View on Instagram") opens outside.
            if action.navigationType == .linkActivated || url.host()?.lowercased() != embedHost {
                parent.openOutside(url)
                return .cancel
            }
            return .allow
        }

        /// target=_blank links (X's widget, "Watch on YouTube").
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url { parent.openOutside(url) }
            return nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !firstLoadDone else { return }
            firstLoadDone = true
            parent.phase = .ready
            checkTask?.cancel()
            checkTask = Task { [weak self, weak webView] in
                // Let scripted embeds (X, Instagram) draw before reading the page.
                try? await Task.sleep(for: .milliseconds(1200))
                guard let self, let webView, !Task.isCancelled else { return }
                let text = (try? await webView.evaluateJavaScript(
                    "document.body ? document.body.innerText.slice(0, 2000) : ''") as? String) ?? ""
                #if DEBUG
                DebugLog.write("player: loaded \(webView.url?.absoluteString ?? "?") text=\(text.count) chars: \(text.prefix(80).replacingOccurrences(of: "\n", with: " | "))")
                #endif
                if EmbedURL.looksUnavailable(pageText: text) { self.parent.phase = .failed }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            fail(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            fail(error)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            parent.phase = .failed
        }

        private func fail(_ error: Error) {
            let ns = error as NSError
            // A link we sent outside, or a newer load replacing this one.
            if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
            if ns.domain == "WebKitErrorDomain" && ns.code == 102 { return }  // frame load interrupted
            #if DEBUG
            DebugLog.write("player: failed \(ns.domain) \(ns.code)")
            #endif
            if !firstLoadDone { parent.phase = .failed }
        }
    }
}
