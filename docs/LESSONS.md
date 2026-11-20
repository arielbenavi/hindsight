# Lessons log

Things we learned the hard way: bugs, dead ends, setup gotchas. Read this before
starting a session; add to it when something surprises you. Newest first.
(Platform-by-platform fetching history lives in BACKFILL_STATUS.md and
DATA_FETCHING_RESEARCH.md.)

## Apple Intelligence / on-device AI

- **On a real iPhone (17 Pro, iOS 27.0), both Apple models beat the Mac test by a lot** (115 fixture posts, 2026-09-30):
  on-device 82% buckets, 45/70 place names, 1.2 s/post; **Private Cloud Compute 86%, 57/70, 1.0 s/post**, quota still "below the limit" after ~150 requests.
  **Hebrew captions worked on both** (PCC 15/15 answered, 14 correct), **even though `supportsLocale(he_IL)` says no.** Trust a real run over the language list.
  The Mac numbers below are from the older macOS 26.6 model; don't plan from them. (2026-09-30)
- ⚠️ **The iPhone's system language must be an Apple Intelligence language (e.g. English), or the app gets no AI at all.**
  Apple Intelligence only turns on when the iPhone language and Siri language are the same *supported* language.
  **Hebrew isn't one, even in iOS 27.** No Apple Intelligence means no on-device model *and* no Private Cloud Compute, even for English posts.
  Check the phone's language first when AI "doesn't work" on a tester's phone. (2026-09-30)
- **With no model, every unsorted save used to land in one "Other" topic** (simulator: 1,213 of 1,216 seed saves). `SortEngine.sortOne` fell back to `SortRules.fallback` = `none/other`. Now `TopicFallback` picks a topic from the post's own signals; with a lexicon + hashtags + author majority, 72% of captioned seed saves get a real topic. The unmatched rest are mostly meme captions with nothing to go on ("Gm", "omg", "🙏"). (2026-11-20)
- Topic lexicon tuning: single generic words ("love", "photo", "show", "car", "website") caused most wrong topics in a 30-post spot check; marking them `~weak` (half weight, need a second word) took errors from ~6/30 to ~3/30. Hashtag stems need prefix/suffix (4+ letters) or contains (5+), else "style" hits #freestyle and "art" hits #start. Hebrew prefix-stripping two letters only after ו/ש ("למספר" is not "ספר"). (2026-11-20)
- **`AppModel.init` runs inside `HindsightApp.body`, so every observed property it reads becomes a dependency of the app's body.** It starts the sort, which read `SortEngine`'s observed `cache`/`progress`; each sorted post then re-ran the body, built a new `RootView` → `AppModel` → `SortEngine`, which started sorting again (dozens of engines, debug log full of "sort: 1216 of 1216 posts to sort"). Cheap before; once starting a sort cost ~3 s (scoring every save on the main actor) the sort never finished. Fixes: `SortEngine`'s state is `@ObservationIgnored` (views follow `progressStream()`), lexicon entries are parsed once, and scoring runs in `Task.detached`. `AppModel` is still built ~3 times at launch; the real fix is building it outside the body. (2026-11-20)
- SF Symbol names in data tables aren't checked by the compiler: "figure.2.and.child.holdinghand" doesn't exist and drew nothing. `TopicFallbackTests` checks each with `UIImage(systemName:)`. (2026-11-20)
- **Hebrew captions are refused by the on-device model** (`unsupportedLanguageOrLocale`), even with English instructions. Hebrew is 7% of Reut's saves and 13% of Ariel's. Hebrew posts need the rules/collections/questions path. (2026-09-30)
- The on-device model (macOS 26.6 = 26.4 generation, 4K context) scored **62–70%** on bucket sorting vs the fixtures, and got **~41%** of place names. It also fills `places` on posts that have none and translates names. Don't trust it for extraction without checks. (2026-09-30)
- **Private Cloud Compute:** free only under the App Store Small Business Program with < 2M downloads. Needs the managed entitlement `com.apple.developer.private-cloud-compute` (granted to Reut's account 2026-09-30). The quota is per iCloud account and opaque (only below / approaching / reached + reset date). No paid tier. (2026-09-30)
- `.permissiveContentTransformations` guardrails only work for plain `String` output, not `@Generable`, so structured sorting always runs with default guardrails. 2–5% of benign English posts got `guardrailViolation` / `refusal`. (2026-09-30)

## Meta data download (Instagram/Facebook export)

- **It's the dependable Instagram/Facebook path while Muse fails** (2026-09-30). The app's guided sheet:
  Connect → Instagram + Facebook → *Get your saves from Meta*. Meta's page is
  `https://accountscenter.instagram.com/info_and_permissions/dyi/` (asks you to sign in first).
- **Saves are split across two files:** in Reut's export, `saved_posts.json` has 113 posts (with saved dates) and
  `saved_collections.json` has 252 (with collection names); together 324. **Import the whole .zip**, not one file.
  `DataExportParser` reads a zip as-is (0.2 s) and only opens the saved files. (2026-09-30)
- **A full download is mostly sensitive data we must never read**: synced contacts, login activity and
  locations, ads history (33 of 35 files in Reut's). Tell users to request only **Saved** (JSON, All time).
- `data/ig-reut-export/` is byte-identical to the saved files in the raw zip; it just leaves the rest out.

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
- ✅ **First real send (2026-09-30 21:04): Muse called `submit_saved_posts`** through
  the ngrok connector. Handshake: initialize (200), initialized (202), tools/list,
  then tools/call, all from `Python-urllib/3.12` on Meta's side. **Muse ignores our
  field names**: `author` = display name + `author_username`, `post_creation_time`,
  `tagged_users`, `media_type`, and the default "Saved"/"All posts" folders as
  collections. The server normalizes to the contract (`normalized()` in
  connector/server.py). Never trust an LLM to follow a schema; normalize at the edge.
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
- **Cloudflare quick tunnels (trycloudflare.com) block AI agents with 403**: a
  GPTBot user agent gets 403 at the edge, and Muse's server-side calls never reached
  our server. Muse's *browser* got through, which is why it kept falling back to the
  browser. localhost.run's free domains rotate every few minutes. For an MCP
  connector Muse can call, use a fixed-address tunnel without AI-bot blocking
  (ngrok static domain) or real hosting. (2026-09-30)
- Users will tap our Paste button with our own prompt still on the clipboard. The
  sheet now detects that and explains. (2026-09-29)

- **Muse carries chat context into new requests** (an old "after Sep 28" limit; an
  old broken connector). Our first-time message now says to replace any existing
  "hindsight" connector and ignore earlier hindsight messages. Fresh-user tests use
  a new connector tenant, so the URL is new too. (2026-10-01)

## iOS / Xcode

- **Today's set was picked before the first sort finished**, when no save had a topic (so every save counted as
  eligible), and a Career (Know) save showed in Today on a fresh "Load seed saves". `TodayPlan.record` now remakes
  a set nobody has answered yet when a pick stops being eligible; once the user answers one, the set stays. (2026-11-20)
- A tab root that hides its nav bar lets scrolled content run under the clock; the old Home painted the strip with
  a zero-height `Theme.background.ignoresSafeArea(edges: .top)` overlay. That's now `.statusBarStrip()` on all
  three tab roots. (2026-11-20)
- Hebrew final letters break prefix matching: "מתכון*" never matches "מתכונים" (final ן vs medial נ). The lexicon
  already lists both stems ("מתכון*", "מתכונ*"); keyword tables need the same. (2026-11-20)
- Today's fixed-height card (so the two cards behind always peek by the same amount) pushed the action buttons
  under the iOS 26 floating tab bar on an iPhone 17 Pro at 470pt; 420pt fits. Check the bottom of a tab's first
  screen against the tab bar in a screenshot, not just the layout code. (2026-11-20)
- Simulator: a tap right after `simctl launch` can land before the first frame; the iOS Simulator tool's
  screenshot-then-tap is more reliable than chaining taps blind (scroll offsets differ run to run). (2026-11-20)

- **A `@State` initial value is built on every init of the view, even though SwiftUI keeps the first one.**
  `RootView(...)` makes `AppModel(...)` in its init, and `AppModel.init` starts sorting; so anything that
  re-runs `HindsightApp.body` (an `@AppStorage` it observes changing) built a second, throwaway AppModel with
  a second sort engine on the same cache file. `HindsightApp` now reads `setupSource` instead of observing it,
  and AppModel switches sample → own saves in place. Keep side effects out of view inits. (2026-11-15)
- **MapKit's pan beats the edge swipe back**, even with the interactive pop gesture re-enabled for screens
  that hide the nav bar. A thin clear strip on the left edge with its own drag gesture works (`MapScreen.backEdge`).
  Other pushed screens got the system swipe back via `UINavigationController` as the pop gesture's delegate. (2026-11-15)
- In a `LazyVGrid`, `.lineLimit(2, reservesSpace: true)` keeps cards the same height but leaves a gap under
  one-line titles; a `minHeight` on the card's content looks right. (2026-11-15)
- `xcrun simctl spawn booted defaults read <bundle id> <key>` didn't see keys the app had just written.
  Check server-side effects (connector `calls.log`) instead of the simulator's defaults. (2026-11-15)
- Swift 6: a `nonisolated static func` can't use a `@MainActor` static as a default argument
  ("main actor-isolated default value in a nonisolated context"); mark the constant `nonisolated`. (2026-11-15)

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
- **`Dictionary.max` on ties is random** (hash order varies per run). A test passed
  by luck and then failed. Always break ties explicitly (WhatsApp owner = most
  messages, then earliest). Run new tests a few times. (2026-10-01)
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

## WhatsApp

- **No official way to read a user's existing chats.** The Cloud API Groups API needs
  a blue-tick Official Business Account, caps groups at 8, and can't join existing
  groups. "Link your own account by QR" services (Unipile, whatsapp-web.js) break
  App Store 5.1.1 (no social tokens off-device) and risk the *user's* account.
  (2026-10-01)
- **A bot on *our own* number (Baileys) is different:** users only add a contact, and
  their account is never involved. The risk is the bot number getting banned
  (unofficial client), so keep the export import as the fallback. (2026-10-01)
- **History:** since 2026, adding someone to a group can share the last 25–100
  messages (max 14 days). That's the most the bot can backfill; older notes need
  "Export chat". (2026-10-01)
- "Export chat" **with media** can be 1.5 GB; **Without media** is a few MB. Say
  "Without media" loudly in the UI. (2026-10-01)
- Muse's WhatsApp chat has no number and isn't in WhatsApp's send-to picker. A
  `wa.me/<number>` link only works for real numbers (e.g. our bot's). (2026-09-30)

## Process

- Before building anything that touches another person's files (Reut's open PR),
  test the merge locally in a worktree (`git worktree add … origin/<branch>`, then
  merge ours in and build). This caught the Xcode 26.3 MapKit errors and confirmed
  the PRs merge cleanly. (2026-10-01)
- Screenshots of developer consoles leak secrets (X showed consumer secret,
  bearer token and OAuth 2.0 client secret on creation). Ask for only the specific
  public value (e.g. client ID) as pasted text, and regenerate anything exposed.
  Base64 IDs in screenshots are ambiguous (l/I/1), so always ask for text.
  (2026-09-29)

## Signing / devices

- **An App ID (developer account) is not an app record (App Store Connect).** Registering
  `com.reutrabin.hindsight` with Private Cloud Compute made signing work, but TestFlight uploads also need
  an app in App Store Connect using that bundle ID. Without it, `xcodebuild -exportArchive` (upload) fails
  with "Error Downloading App Information" (`missingApp` in the distribution log). Created 2026-09-30;
  first TestFlight build 0.1.0 (2) uploaded the same day. (2026-09-30)
- TestFlight upload from the command line: archive (Release, `generic/platform=iOS`), then
  `xcodebuild -exportArchive` with `method app-store-connect`, `destination upload`, `-allowProvisioningUpdates`.

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

## WhatsApp bot (Baileys)

- **Confirmed: the bot is logged out when its phone is offline ~14 days.** The spare phone stayed off 15 days
  and the bot has been logged out since 2026-10-17. The bot needs a phone that stays online, or a relink
  every ~2 weeks. (2026-11-15)
- Pairing codes fail ("Couldn't link device") with a made-up browser name like
  `Browsers.macOS('hindsight')`. Use a real one (`Browsers.macOS('Chrome')`). (2026-10-01)
- Right after pairing, WhatsApp closes the stream with code 515 ("restart required").
  That's normal; the bot reconnects and is linked. (2026-10-01)
- Adding the bot while *creating* a group fires `groups.upsert`, not
  `group-participants.update`, so "who added the bot" is unknown. Fall back to the
  group creator (`meta.owner` / `meta.ownerPn`). Owners show up as `@lid` ids, so
  compare against both the LID and the phone number. (2026-10-01)
- WhatsApp's "message yourself" chat can't take a third member, so the bot can't
  join it. Those users switch to a 1:1 chat with the bot as their notes chat, and
  bring the old self-chat in via Export chat. (2026-10-01)
- The repo is **public**: keep the bot's phone number out of it. The app fetches
  it from the server (`/<token>/whatsapp`, from `data/whatsapp_bot` or env). (2026-10-01)
- `CNContactViewController(forNewContact:)` needs no Contacts permission, and
  `ImageRenderer` can draw the contact photo (the app icon isn't loadable at runtime). (2026-10-01)
- Under launchd with `KeepAlive`, exit cleanly (0) on WhatsApp logout, or launchd
  restarts the bot in a loop. (2026-10-01)
- Instagram share links carry `?stkn=` / `?igsh=`; strip the query for IG/X/TikTok. (2026-10-01)

- A reinstall on the phone can drop the app's saved server URL; with no server the
  WhatsApp screen fell back to export-only, which looked like missing features.
  `device.sh install` now always launches with `-museConnectorBaseURL` (from
  `connector/data/token`), and the screen says when it can't reach the server. (2026-10-01)

- Private Cloud Compute (`PrivateCloudComputeLanguageModel`, `session.usage`, `contextSize`)
  exists only in the iOS 27 SDK. Every use is wrapped in `#if compiler(>=6.3)` so the app
  still builds on Xcode 26 (where the cloud path is simply absent; iOS 26 phones never run it
  anyway). Keep new iOS 27-only API behind the same guard. (2026-11-15)

- ngrok 3.39 with `--log=stdout` outside a terminal printed nothing and the tunnel never
  came up (public URL 404). `--log=<file>` works. (2026-11-15)

- The repo's `.env` has `X_CLIENT_SECRET` twice (consumer secret, then the OAuth client secret).
  dotenv keeps the last one; a hand-rolled loader that keeps the first makes X token refresh
  fail with `unauthorized_client`. (2026-11-19)
- Instagram cookies exported 2026-09-29 still worked on 2026-11-19 (the ~90-day estimate holds so far);
  the saved-posts endpoint returns thumbnails and captions but not which collection a save is in. (2026-11-19)

- A free Apple ID allows 3 installed apps; Ariel's slots are full, so `device.sh install` fails with
  `MIFreeProfileValidatedAppTracker` (looks like a signing error, isn't). hindsight runs inside
  LiveContainer instead: `ios/scripts/ipa.sh` builds an unsigned IPA into iCloud Drive, then
  LiveContainer → + → replace. Launch arguments don't reach an app in LiveContainer, so the server
  URL is baked in at build time (`HINDSIGHT_SERVER_URL` → Info.plist `HindsightServerURL`). (2026-11-19)

## Testing loop

- DEBUG builds write `Library/Application Support/debug-log.txt`.
  `ios/scripts/device.sh log` pulls it off a connected phone, so a tester can just
  say "check the log". (2026-09-29)
