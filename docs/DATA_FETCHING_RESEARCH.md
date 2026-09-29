# Data fetching research (iOS app)

Last updated: 2026-09-29. This covers how the iOS app gets saved posts from each platform. For what worked and failed in the web prototype, see [BACKFILL_STATUS.md](BACKFILL_STATUS.md).

| Platform | Recommended path | User effort | Status in iOS app |
|----------|------------------|-------------|-------------------|
| Instagram | Muse (built-in IG connector reads saved posts) | 2 pastes | **Working on device** (paste flow) |
| Facebook | Muse (same flow, same prompt) | shared with IG | Prototype (`Sync/`) |
| X | OAuth 2.0 PKCE, using hindsight's own X app | 1 sign-in | **Working on device** (97 bookmarks) |
| TikTok | Share extension + data-download import (API is EEA/UK-only) | 1 tap per save | Export parser built; no UI |

---

## Instagram + Facebook via Muse

### What we know
- Muse's built-in Instagram and Facebook connectors connect automatically for anyone in the same Accounts Center. Instagram's connector can read saved posts. Meta's own example is turning a saved recipe reel into a grocery list.
- Custom and directory connectors use MCP. On Sep 18, 2026 Meta opened muse.ai/platform for directory submissions, with Meta reviewing each one. Custom connectors (a single user adds any MCP URL) aren't reviewed.
- **`muse://new?text=…` is NOT an official scheme.** The only place it appears is a feature request on an unofficial desktop wrapper (benjaminkitt/muse-desktop#8). Meta documents no deep link that opens Muse with a prompt already filled in. We need to test this on a real iPhone that has Muse installed.

### The flow we're prototyping (no backend needed)

```
hindsight                          Muse app
─────────                          ────────
[Sync with Muse] ──open──────────▶ new chat, prompt pre-filled
  (fallback: prompt copied,          (or: user pastes prompt)
   open https://muse.ai)             │
                                     ▼
                                   Muse reads IG/FB saved posts,
                                   replies with a ```json block
                                     │ user taps "copy"
◀──────────── user switches back ────┘
[Paste from Muse] (PasteButton, no permission alert)
  → SavedPostParser (JSON, or legacy markdown)
  → SavedPostStore.merge (dedup by platform+shortcode)
  → "+N new saves"
```

`MuseLauncher` tries each way of opening Muse in order:
1. `muse://new?text=<prompt>`, if Muse turns out to support it
2. copy the prompt, then open `https://muse.ai` (a universal link that opens the app when it's installed)
3. the App Store page

`ShareLink` is a secondary option, in case Muse has a share extension.

### Why we ask Muse for JSON
The seed file (`data/ig-saved-posts-seed.md`) is whatever format Muse chose when asked for saved reels. Muse's formatting will drift, so the prompt asks for a fixed JSON schema:

```json
[{"platform":"instagram","author":"evolving.ai","kind":"post",
  "date":"2026-09-26","caption":"…","url":"https://www.instagram.com/p/DdwJgsNABze/"}]
```

The parser still accepts the markdown format, so the seed and loose replies both work. The canonical format is the Swift model `SavedPost`, not any file format.

### Next step: a hindsight MCP connector (removes the paste step)
- The MCP server exposes one tool, `submit_saved_posts(posts: [SavedPost])`. Muse calls it, and the server stores the posts under the user's hindsight account.
- This needs a **hosted** HTTPS endpoint plus user auth (OAuth or an API key per user). The iOS app has no backend yet. The web prototype's FastAPI `/capture` runs locally only.
- After that, the prompt becomes "send my saved posts to hindsight". The app fetches from our backend, or a push notification wakes it.
- Options: a custom connector (each user adds our URL; fine for testing) or a directory listing (Meta review; the production path).

### Open questions (test on a real device)
- Does the iOS Muse app register any URL scheme? Try `muse://`, `fb-muse://` and `aura://`; the Android package is `com.facebook.aura`.
- Does Muse have a share extension (for `ShareLink`)?
- How many saved posts will Muse list in one reply? We'll probably need paging ("next 100 since <date>").
- Does Muse's `date` mean the date it was *saved* or the date it was *posted*? The seed is newest-saved-first, but its dates look like post dates.

---

## X (Twitter)

- The web prototype uses a **confidential** client, so each person needs `X_CLIENT_ID` and a secret in `.env`. That's why "Developer Studio setup" felt necessary.
- **For iOS, no per-user developer app is needed.** hindsight registers **one** X app of type "Native App" (a public client, with no secret). The app runs OAuth 2.0 Authorization Code + PKCE through `ASWebAuthenticationSession`, with scopes `bookmark.read tweet.read users.read offline.access`. The callback is `hindsight://oauth/x`, and `ASWebAuthenticationSession` catches it, so no Info.plist URL-type change is needed.
- Cost: pay-per-use reads (about $0.001 per bookmark), billed to hindsight's developer account. Rate limit: 180 req / 15 min.
- The refresh token goes in the Keychain.
- TODO: register the native X app and add the callback URL.

## TikTok

- **Data Portability API** (official). **It only returns data for TikTok users in the EEA/UK** (it exists for DMA compliance), so it's useless for US users. The `portability.activity.single` / `.ongoing` scopes cover activity, including likes and favorites. Also needs Login Kit approval, a public privacy-policy URL, a business-domain email, 4 UX mockups and a data-deletion description. It needs an application form and review (about 3–4 weeks), and the data comes back as an asynchronous export the app downloads.
- **Fallback that works today:** the user requests their data download in TikTok (Settings → Account → Download your data, JSON), then shares the file to hindsight. tikfav does the same thing. We'd write a parser for `Activity › Favorite Videos` / `Like List`.
- Third-party scrapers (Apify, about $6 per 1k) and Chrome extensions (myfaveTT) aren't usable for an iOS consumer app.
- Recommendation: a share extension ("Share → hindsight" on a TikTok) for capturing new saves everywhere; data-download import (`DataExportParser`, built) for backfill. Apply for Data Portability only if we target EU/UK users.

---

## Sources
- Muse connectors overview: https://cellcog.ai/blog/muse-connector-platform/
- Muse connector list (IG reads saved posts): https://www.sprites.ai/muse/connectors
- Muse custom integrations (MCP): https://parallel.ai/articles/meta-muse-custom-integrations
- Unofficial `muse://` request: https://github.com/benjaminkitt/muse-desktop/issues/8
- Muse iOS app: https://apps.apple.com/us/app/muse-from-meta/id6760173601
- TikTok Data Portability: https://developers.tiktok.com/doc/data-portability-api-get-started
- TikTok portability data types: https://developers.tiktok.com/docs/en/data-portability-data-types
- tikfav: https://github.com/davidkeipert/tikfav
