# Data fetching research (iOS app)

Last updated: 2026-09-29. This covers how the iOS app gets saved posts from each platform, what's been verified on a real iPhone, and what's still open. For what worked and failed in the web prototype, see [BACKFILL_STATUS.md](BACKFILL_STATUS.md). For gotchas, see [LESSONS.md](LESSONS.md).

| Platform | Path | User effort | Status |
|----------|------|-------------|--------|
| Instagram | Muse (its built-in IG connector reads saved posts) | open Muse, paste, send, copy, paste back | **Works on device** (paste flow) |
| Facebook | Muse (same prompt as IG) | same as IG | Same flow; FB not yet seen in a real reply |
| X | OAuth 2.0 PKCE with hindsight's own "Native App" | 1 tap + X's Authorize screen | **Works on device** (97 bookmarks) |
| TikTok | Share extension (new saves) + data-download import (backfill) | 1 tap per save / one-time file | Export parser built, no UI; share extension not started |
| All | Data-download import (`DataExportParser`) | request export, wait, pick file | Parser built + tested, no UI (fallback only) |

---

## Instagram + Facebook via Muse

### Facts (verified 2026-09-29)
- **Muse's iOS app is `com.facebook.hatch`** (seen on device via `devicectl`). The Android package is `com.facebook.aura`.
- muse.ai's `/.well-known/apple-app-site-association` routes these paths into the app: `/chat`, `/chat/*`, `/thread/*`, `/share`, `/s/*`, `/connectors/connect/*`, `/search` and others. **The bare `https://muse.ai` is not routed**, so opening it as a universal link fails.
- **`muse://new?text=…` is NOT an official scheme.** The only mention is a feature request on an unofficial desktop wrapper (benjaminkitt/muse-desktop#8).
- `https://muse.ai/chat?q=…` **opens Muse, but the prompt is not typed in.** So the prompt goes on the clipboard and the user pastes it. The DEBUG "link lab" in the Muse sheet has other candidates (`?text=`, `?prompt=`, `/share?text=`, `hatch://`…) that haven't been fully tested yet.
- Muse's built-in Instagram/Facebook connectors connect automatically for anyone in the same Meta Accounts Center, and Instagram's can read saved posts.
- Custom and directory connectors speak MCP. muse.ai/platform opened on Sep 18, 2026 for directory submissions, which Meta reviews. Custom connectors (one user adds any MCP URL) aren't reviewed.

### The flow that works today (no backend)

```
hindsight                               Muse app
─────────                               ────────
[Open Muse] copies prompt ──open───────▶ muse.ai/chat (new chat, empty)
                                         user pastes prompt, sends
                                         Muse reads IG/FB saves, replies
                                         with one ```json block
                                         user long-presses → Copy
◀──────────── user switches back ───────┘
[Paste] (SwiftUI PasteButton: no iOS paste-permission alert)
  → SavedPostParser (JSON, or legacy markdown)
  → SavedPostStore.merge (dedup by platform + shortcode)
  → "+N new saves"
```

- The prompt asks only for saves **after the newest date we already have**, so a daily sync is small. In the first real test, Muse returned 2 posts, which were exactly the new ones. A new user with no saves gets "up to 100".
- If the user pastes our own prompt back by mistake, the sheet says so instead of "0 posts".

### Why JSON instead of the seed's markdown
The seed file (`data/ig-saved-posts-seed.md`, 1,216 posts) is whatever format Muse chose when asked for saved reels in bulk. Muse's formatting drifts, so the prompt pins a JSON schema:

```json
[{"platform":"instagram","author":"evolving.ai","kind":"post",
  "date":"2026-09-26","caption":"…","url":"https://www.instagram.com/p/DdwJgsNABze/"}]
```

The parser still accepts the markdown format. The canonical format is the Swift model `SavedPost`, not any file format.

### Known limits and next steps
- **About 100 posts per reply** (Muse's output length). Full backfill needs paging: a "Get older saves" button that asks for the 100 before our oldest date. Not built yet.
- **The zero-paste version is a hindsight MCP connector.** The server exposes `submit_saved_posts(posts)`, Muse calls it, and the app fetches from our backend. That needs a **hosted backend plus per-user auth** (see "Ingestion backend" below). It starts as a custom connector (each user adds our URL), and the production path is a directory listing (Meta review).
- Open: does Muse's `date` mean *saved* or *posted*? The seed is ordered newest-saved-first, but its dates look like post dates.
- Open: do Muse's replies include Facebook items when asked? Not yet seen.

---

## X (Twitter)

- **Working on device.** One tap on "Connect" → iOS asks to use x.com → X's own login/Authorize page → back in the app → bookmarks pulled (97 in the first test).
- **Users never need a developer account.** hindsight has **one** X app, `hindsight-ios` in the pudabeats developer console, of type **Native App** (a public client, with no secret used). OAuth 2.0 Authorization Code + PKCE via SwiftUI's `webAuthenticationSession`, with scopes `tweet.read users.read bookmark.read offline.access` and callback `hindsight://oauth/x`. No Info.plist URL type is needed.
- **Tokens only read the signed-in user's own bookmarks.** Bookmarks are private, so there's no way to read anyone else's.
- The client ID lives in `ios/Hindsight/Sync/X/XConfig.swift`. It's public by design for native apps. Tokens (with refresh) are stored in the Keychain.
- Cost: pay-per-use (about $0.001 per bookmark read), billed to the pudabeats X developer account. The API returns at most 800 bookmarks (8 pages).
- `date` is the tweet's creation time, because X doesn't expose when it was bookmarked.
- The web prototype's app (`savesFeed`) is a confidential Web App and stays as-is.
- **Security to-do:** the hindsight-ios consumer secret, bearer token and OAuth 2.0 client secret were shown in screenshots during setup. None of them are used, so regenerate them in the X console.

---

## TikTok

### No official "connect TikTok" for US users
| Official API | Gives us | Why it doesn't work |
|---|---|---|
| Login Kit + Display API | profile, **your own posted videos** | no likes/favorites |
| Data Portability API | likes, favorites (activity scopes) | **EEA/UK accounts only** (DMA compliance); also 3–4 week review, privacy policy URL, business email, 4 UX mockups, data-deletion description |
| Research API | public likes | academics only |

**Third-party scraper APIs (tested 2026-09-30):** YepAPI's `user-favorites` needs only a numeric user ID, but it returns nothing unless the user's Favorites tab is public (`openFavorite: true`). Both test accounts were private, so both returned 0 videos. Asking users to publish their Favorites is a privacy cost and it's still scraping, so it's ruled out.

Unofficial scraping of the user's logged-in session (like the old IG cookie approach) is possible, but it breaks TikTok's terms, risks the user's account and would likely fail App Store review. Not recommended.

### What we can do
1. **Share extension ("Share → hindsight").** In TikTok (or Instagram, X, Safari…), tap Share → hindsight. The extension receives the post URL, and the app saves it and later enriches it. One tap per save, for every platform, going forward. It needs a new app-extension target in `project.yml` plus an App Group so the extension and the app share storage. Tell Reut before changing `project.yml`.
2. **Data-download import for backfill.** TikTok → Settings → Account → Download your data → JSON. It arrives in about 1–3 days and includes `Favorite Videos` and `Like List`. `DataExportParser` already reads it (and the IG/FB equivalents), straight from the zip. No UI yet.

Still looking for something smoother; see [research/SYNC_RESEARCH_PROMPT.md](research/SYNC_RESEARCH_PROMPT.md).

---

## Ingestion backend (planned, not started)

The iOS app only has link, author, date and caption. To be useful it needs what's *inside* each save.

- **Keep:** transcript, on-screen text, summary, key takeaways, category/tags, thumbnail, embedding (for search and "more like this"), and the link back.
- **Don't keep video files** (proposed; decision pending). Download them only while processing, then delete. Reasons: size (about 6–18 GB for 1,216 reels for one user) and copyright/ToS for re-serving other people's videos. Playback opens the original app.
- **Runs on a hosted service, not the phone.** yt-dlp against Instagram and video processing can't run on-device. The phone sends new saves up (`POST /items`) and reads enriched items back.
- **Mostly already written** in the web prototype: `web/backend/adapters.py` (yt-dlp, gallery-dl, trafilatura), `gemini.py` (video → gist, transcript, on-screen text), `db.py`/`embeddings.py` (categories, 768-dim embeddings). Port it into a standalone service.
- The same server later hosts the **Muse MCP connector**.
- Cost: Gemini Flash is about 1¢ or less per video, so backfilling 1,216 is a few dollars.
- **Hosting: undecided (Ariel + Reut to discuss).**
  - Fly.io: an always-on small VM with a persistent disk, so the prototype's SQLite + background loop runs almost unchanged, for about $2–5/mo.
  - Google Cloud Run: scales to zero and is Google-native (Gemini), but has no persistent disk, so the database has to move (Cloud SQL about $10/mo, or Firestore with a rewrite) and the worker needs Cloud Tasks/Jobs.
  - Datacenter IPs may get blocked by Instagram when downloading, whichever host we pick.

---

## Sources
- Muse app-site-association: https://muse.ai/.well-known/apple-app-site-association
- Muse connectors overview: https://cellcog.ai/blog/muse-connector-platform/
- Muse connector list (IG reads saved posts): https://www.sprites.ai/muse/connectors
- Muse custom integrations (MCP): https://parallel.ai/articles/meta-muse-custom-integrations
- Unofficial `muse://` request: https://github.com/benjaminkitt/muse-desktop/issues/8
- Muse iOS app: https://apps.apple.com/us/app/muse-from-meta/id6760173601
- TikTok Data Portability: https://developers.tiktok.com/doc/data-portability-api-get-started
- TikTok Data Portability guidelines: https://developers.tiktok.com/doc/data-portability-api-application-guidelines/
- TikTok Data Portability overview (EEA/UK only): https://developers.tiktok.com/products/data-portability-api/
- tikfav: https://github.com/davidkeipert/tikfav
