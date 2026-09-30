# Lessons log

Things we learned the hard way: bugs, dead ends, setup gotchas. Read this before
starting a session; add to it when something surprises you. Newest first.
(Platform-by-platform fetching history lives in BACKFILL_STATUS.md and
DATA_FETCHING_RESEARCH.md.)

## Apple Intelligence / on-device AI

- ⚠️ **The iPhone's system language must be an Apple Intelligence language (e.g. English), or the app gets no AI at all.**
  Apple Intelligence only turns on when the iPhone language and Siri language are the same *supported* language.
  **Hebrew isn't one, even in iOS 27.** No Apple Intelligence means no on-device model *and* no Private Cloud Compute, even for English posts.
  Check the phone's language first when AI "doesn't work" on a tester's phone. (2026-09-30)
- **Hebrew captions are refused by the on-device model** (`unsupportedLanguageOrLocale`), even with English instructions. Hebrew is 7% of Reut's saves and 13% of Ariel's. Hebrew posts need the rules/collections/questions path. (2026-09-30)
- The on-device model (macOS 26.6 = 26.4 generation, 4K context) scored **62–70%** on bucket sorting vs the fixtures, and got **~41%** of place names. It also fills `places` on posts that have none and translates names. Don't trust it for extraction without checks. (2026-09-30)
- **Private Cloud Compute:** free only under the App Store Small Business Program with < 2M downloads. Needs the managed entitlement `com.apple.developer.private-cloud-compute` (granted to Reut's account 2026-09-30). The quota is per iCloud account and opaque (only below / approaching / reached + reset date). No paid tier. (2026-09-30)
- `.permissiveContentTransformations` guardrails only work for plain `String` output, not `@Generable`, so structured sorting always runs with default guardrails. 2–5% of benign English posts got `guardrailViolation` / `refusal`. (2026-09-30)

## Muse

- **`muse://new?text=` isn't real.** It only appears in a feature request for an
  unofficial desktop wrapper. Meta documents no prefill deep link. (2026-09-29)
- **Muse's iOS app is `com.facebook.hatch`.** muse.ai's
  `/.well-known/apple-app-site-association` routes `/chat`, `/chat/*`, `/share`,
  `/s/*` and friends into the app. **The bare `https://muse.ai` is not routed**, so
  opening it with `.universalLinksOnly` fails and looks like "not installed". Open
  `https://muse.ai/chat` instead. (2026-09-29)
- `https://muse.ai/chat?q=…` opens Muse but **doesn't prefill** the prompt, so we
  copy it to the clipboard first. Other params are in the DEBUG link lab, not yet
  all tried. (2026-09-29)
- The Muse paste flow works end to end on device. Asking only for saves after our
  newest date made the first real reply tiny (2 posts). That's expected, not a
  bug. (2026-09-29)
- **Muse accepts a custom MCP connector from a chat message.** It asks "Allow the
  agent to share information with <host>?" (Allow once / Always allow / Deny). So
  Meta does allow sending saves to a third-party connector. (2026-09-30)
- **Muse's WhatsApp chat has no number and isn't in WhatsApp's "send to…" picker**,
  so `wa.me/?text=` can't reach it. The WhatsApp route = copy + open WhatsApp +
  user pastes into the Muse chat. (2026-09-30)
- MCP server: answer `GET /mcp` with 405 unless you really serve an SSE stream.
  Holding it open made Muse's requests hang and get cancelled (cloudflared: "stream
  canceled by remote"). Muse then blamed "Cloudflare 403" and fell back to its
  browser tool. Log every HTTP request (method, path, UA, status) from the start.
  (2026-09-30)
- Users will tap our Paste button with our own prompt still on the clipboard. The
  sheet now detects that and explains. (2026-09-29)

## iOS / Xcode

- **Fresh Xcode installs have no iOS platform.** `xcodebuild -downloadPlatform iOS`
  (about 8.4 GB) is needed even to build for a physical device, not just the
  simulator. It's an Xcode component, not a macOS update. (2026-09-29)
- **The simulator can't render emoji** (shows `?` boxes, and the wide fallback
  glyph broke row layouts). Use SF Symbols for UI; emoji in real captions are fine
  on devices. (2026-09-29)
- **`YYYY-MM-DD` parsed as UTC midnight shows the previous day** in US timezones.
  Parse date-only strings as local midnight (`SavedPostParser.parseDate`).
  (2026-09-29)
- `Regex` isn't `Sendable`, so a regex literal can't be a `static let` under Swift 6.
  Use a computed `static var`. (2026-09-29)
- Long `Data` concatenations with `+` time out the type checker. Build them in
  steps. (2026-09-29)

## X

- Use a **separate "Native App"** (public client, PKCE, no secret) for iOS. The web
  prototype's app (savesFeed) is a confidential Web App; converting it would break
  the web prototype. Callback `hindsight://oauth/x`. (2026-09-29)
- Don't trust remembered test vectors. The "RFC 7636" PKCE challenge I recalled
  was wrong; the test now uses a value computed independently in Python. (2026-09-29)

## TikTok

- **The Data Portability API only returns data for EEA/UK users.** It's a DMA
  compliance API; US accounts get nothing back. Check a platform API's regional
  scope before recommending it. (2026-09-29)

- **Third-party "TikTok favorites" APIs (YepAPI `/v1/tiktok/user-favorites`) only see
  public Favorites.** Tested on two real accounts (tikvaqqfl75, pudabeats): both
  have `openFavorite: false`, and both returned `ok: true` with 0 videos. That's an
  empty "success", not an error. They scrape the public profile tab, so they'd need
  every user to make Favorites public. Not a product path. (2026-09-30)
- Even after @pudabeats made Favorites visible, logged-out tiktok.com showed only
  a **public Collection** ("For later 1"), not the flat Favorites list, and YepAPI
  still returned 0 (`openFavorite` stayed false; it has no collections endpoint).
  TikTok now exposes Collections, not Favorites. (2026-09-30)

## Process

- Screenshots of developer consoles leak secrets (X showed consumer secret,
  bearer token and OAuth 2.0 client secret on creation). Ask for only the specific
  public value (e.g. client ID) as pasted text, and regenerate anything exposed.
  Base64 IDs in screenshots are ambiguous (l/I/1), so always ask for text.
  (2026-09-29)

## Signing / devices

- **Being on a team as "App Manager" isn't enough to run on a device.** Xcode lists
  the team, but builds fail with `No Account for Team`. (2026-09-29)
- **Reut's Apple Developer account is an Individual membership, and only Organization
  accounts can give members certificate access.** So Ariel can never sign under
  Reut's team. Paths: Personal Team overrides for local builds, TestFlight builds
  uploaded by Reut, or Xcode Cloud (Apple signs server-side, triggered by a git
  push). Xcode Cloud needs a `ci_scripts/ci_post_clone.sh` that runs `xcodegen`,
  because the .xcodeproj isn't committed. (2026-09-30)
- Free Personal Teams probably can't use App Groups (unverified), which a share
  extension needs to share storage with the app. Plan share-extension testing
  around Reut's signing (TestFlight / Xcode Cloud). (2026-09-30)
- Workaround without touching `project.yml`: build with your free Personal Team and
  a different bundle ID via command-line overrides:
  `HINDSIGHT_TEAM=<id> HINDSIGHT_BUNDLE_ID=com.you.hindsight ios/scripts/device.sh install`.
  First launch needs Settings → General → VPN & Device Management → Trust.
  Personal Team builds expire after 7 days. (2026-09-29)
- The phone needs Developer Mode (Settings → Privacy & Security) before Xcode
  can use it. (2026-09-29)

## Testing loop

- DEBUG builds write `Library/Application Support/debug-log.txt`.
  `ios/scripts/device.sh log` pulls it off a connected phone, so a tester can just
  say "check the log". (2026-09-29)
