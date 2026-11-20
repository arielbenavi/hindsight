import UIKit

/// Opens Muse with our prompt.
///
/// Muse's iOS app is `com.facebook.hatch`. muse.ai's apple-app-site-association
/// routes `/chat`, `/chat/*`, `/share` and `/s/*` into the app (not the bare
/// domain), so we open `https://muse.ai/chat` as a universal link. Meta doesn't
/// document a prefill parameter, so the prompt always goes on the clipboard
/// first; if Muse honors `q`, it's typed in for the user as a bonus.
@MainActor
enum MuseLauncher {
    enum Outcome: Equatable {
        /// The Muse app opened (universal link).
        case opened
        /// The universal link didn't open an app, but muse.ai/chat opened in the
        /// browser, which hands off to Muse or works on the web. Inside LiveContainer
        /// (the owner's phone) universal links never open another app, so this is the
        /// normal path there.
        case openedInBrowser
        /// Nothing opened: offer the App Store.
        case notInstalled
    }

    static let appStoreURL = URL(string: "https://apps.apple.com/us/app/muse-from-meta/id6760173601")!

    static func chatURL(prompt: String) -> URL {
        var components = URLComponents(string: "https://muse.ai/chat")!
        components.queryItems = [URLQueryItem(name: "q", value: prompt)]
        return components.url!
    }

    /// Opens a URL; `universalLinksOnly` asks for an app or nothing.
    typealias Opener = @MainActor (_ url: URL, _ universalLinksOnly: Bool) async -> Bool

    static let systemOpener: Opener = { url, universalOnly in
        await UIApplication.shared.open(url, options: universalOnly ? [.universalLinksOnly: true] : [:])
    }

    /// What happened, from the two tries. Pure. `browser` is nil when it wasn't tried
    /// (the app opened first time).
    nonisolated static func outcome(universalLink: Bool, browser: Bool?) -> Outcome {
        if universalLink { return .opened }
        return browser == true ? .openedInBrowser : .notInstalled
    }

    /// The prompt goes on the clipboard first, whatever happens next. Then the Muse
    /// app by universal link; if that fails, the same URL without `universalLinksOnly`.
    static func launch(prompt: String, copy: @MainActor (String) -> Void = { UIPasteboard.general.string = $0 },
                       open: Opener = systemOpener) async -> Outcome {
        copy(prompt)
        let url = chatURL(prompt: prompt)
        if await open(url, true) { return outcome(universalLink: true, browser: nil) }
        return outcome(universalLink: false, browser: await open(url, false))
    }

    /// WhatsApp route. Muse's WhatsApp chat has no phone number and doesn't show
    /// up in WhatsApp's "send to…" picker, so a prefilled `wa.me/?text=` link
    /// can't reach it. Instead: copy the prompt and open WhatsApp; the user
    /// opens the Muse chat, pastes and sends.
    static let whatsAppURL = URL(string: "whatsapp://")!

    static func launchWhatsApp(prompt: String) async -> Outcome {
        UIPasteboard.general.string = prompt
        let opened = await UIApplication.shared.open(whatsAppURL)
        return opened ? .opened : .notInstalled
    }

    #if DEBUG
    /// Links to try by hand on a device, to find one that pre-fills a Muse chat.
    static let linkLabCandidates: [(label: String, url: String)] = [
        ("/chat?q=", "https://muse.ai/chat?q=hello%20from%20hindsight"),
        ("/chat?text=", "https://muse.ai/chat?text=hello%20from%20hindsight"),
        ("/chat?prompt=", "https://muse.ai/chat?prompt=hello%20from%20hindsight"),
        ("/chat?message=", "https://muse.ai/chat?message=hello%20from%20hindsight"),
        ("/share?text=", "https://muse.ai/share?text=hello%20from%20hindsight"),
        ("/share?url=", "https://muse.ai/share?url=https%3A%2F%2Fwww.instagram.com%2Fp%2FDdwJgsNABze%2F"),
        ("hatch://", "hatch://chat?q=hello"),
        ("fb-hatch://", "fb-hatch://chat?q=hello"),
        ("muse://", "muse://new?text=hello"),
    ]
    #endif
}
