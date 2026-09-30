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
        case opened
        case notInstalled
    }

    static let appStoreURL = URL(string: "https://apps.apple.com/us/app/muse-from-meta/id6760173601")!

    static func chatURL(prompt: String) -> URL {
        var components = URLComponents(string: "https://muse.ai/chat")!
        components.queryItems = [URLQueryItem(name: "q", value: prompt)]
        return components.url!
    }

    static func launch(prompt: String) async -> Outcome {
        UIPasteboard.general.string = prompt
        let opened = await UIApplication.shared.open(chatURL(prompt: prompt), options: [.universalLinksOnly: true])
        return opened ? .opened : .notInstalled
    }

    /// WhatsApp route. Muse's WhatsApp chat has no phone number (it's linked
    /// through the Muse app), so we open WhatsApp's "send to…" picker with the
    /// prompt already typed; the user picks the Muse chat and taps Send.
    static func whatsAppURL(prompt: String) -> URL {
        var components = URLComponents(string: "https://wa.me/")!
        components.queryItems = [URLQueryItem(name: "text", value: prompt)]
        return components.url!
    }

    static func launchWhatsApp(prompt: String) async -> Outcome {
        UIPasteboard.general.string = prompt
        let opened = await UIApplication.shared.open(whatsAppURL(prompt: prompt), options: [.universalLinksOnly: true])
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
