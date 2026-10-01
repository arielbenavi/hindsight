# Lessons log

Things we learned the hard way: bugs, dead ends, setup gotchas. Read this before
starting a session; add to it when something surprises you. Newest first.
(Platform-by-platform fetching history lives in BACKFILL_STATUS.md and
DATA_FETCHING_RESEARCH.md.)

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

- Pairing codes fail ("Couldn't link device") with a made-up browser name like
  `Browsers.macOS('hindsight')`. Use a real one (`Browsers.macOS('Chrome')`). (2026-10-01)
- Right after pairing, WhatsApp closes the stream with code 515 ("restart required").
  That's normal; the bot reconnects and is linked. (2026-10-01)
- Adding the bot while *creating* a group fires `groups.upsert`, not
  `group-participants.update`, so "who added the bot" is unknown. Fall back to the
  group creator (`meta.owner` / `meta.ownerPn`). Owners show up as `@lid` ids, so
  compare against both the LID and the phone number. (2026-10-01)
- Instagram share links carry `?stkn=` / `?igsh=`; strip the query for IG/X/TikTok. (2026-10-01)

## Testing loop

- DEBUG builds write `Library/Application Support/debug-log.txt`.
  `ios/scripts/device.sh log` pulls it off a connected phone, so a tester can just
  say "check the log". (2026-09-29)
