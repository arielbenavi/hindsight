import UIKit

/// Opens Muse with our prompt, trying the smoothest route first.
///
/// Meta doesn't document a deep link that pre-fills a Muse chat
/// (`muse://new?text=` is only an unofficial feature request), so:
/// 1. try `muse://new?text=…` in case the app handles it,
/// 2. else copy the prompt and open https://muse.ai, a universal link that
///    lands in the Muse app when it's installed,
/// 3. else report that Muse isn't installed.
@MainActor
enum MuseLauncher {
    enum Outcome: Equatable {
        /// Muse opened with the prompt already typed.
        case openedWithPrompt
        /// Muse opened; the prompt is on the clipboard for the user to paste.
        case openedWithCopiedPrompt
        case notInstalled
    }

    static let appStoreURL = URL(string: "https://apps.apple.com/us/app/muse-from-meta/id6760173601")!
    static let universalLink = URL(string: "https://muse.ai")!

    static func deepLink(prompt: String) -> URL? {
        var components = URLComponents()
        components.scheme = "muse"
        components.host = "new"
        components.queryItems = [URLQueryItem(name: "text", value: prompt)]
        return components.url
    }

    static func launch(prompt: String) async -> Outcome {
        let app = UIApplication.shared
        if let url = deepLink(prompt: prompt), await app.open(url) {
            return .openedWithPrompt
        }
        UIPasteboard.general.string = prompt
        if await app.open(universalLink, options: [.universalLinksOnly: true]) {
            return .openedWithCopiedPrompt
        }
        return .notInstalled
    }
}
