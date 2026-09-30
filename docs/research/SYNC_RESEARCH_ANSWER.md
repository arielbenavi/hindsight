# Sync research answer (ChatGPT deep research, 2026-09-29)

Answer to [SYNC_RESEARCH_PROMPT.md](SYNC_RESEARCH_PROMPT.md). Condensed from the original report, with inline citation markers removed. Claims marked "verified" were backed by platform docs; everything else is plausible but untested. Our decisions based on it are in [../SYNC_PLAN.md](../SYNC_PLAN.md).

## Executive conclusion

No single "sync my saves" mechanism exists across platforms for US users in Sept 2026. Ship a hybrid:

**X gets real automatic sync. Instagram/Facebook/TikTok get frictionless capture from now on via an iOS Share Extension, plus a one-time backfill. Muse is an optional Instagram backfill/sync accelerator, not a launch dependency.**

| Platform | Best launch backfill | Best launch ongoing path | Zero-effort ongoing today? |
|---|---|---|---|
| X | Official Bookmarks API | Server-side scheduled Bookmarks API sync | Yes (800-bookmark cap) |
| Instagram | Meta export if Saved data is present; otherwise Muse | Share Extension | Not via documented API. A Muse MCP connector could change this if cross-connector transfer is allowed |
| Facebook | Meta export if Saved Items/Collections are present | Share Extension | No documented saved-items API |
| TikTok US | Download Your Data JSON | Share Extension | No (Data Portability API is EEA/UK-only) |
| TikTok EEA/UK | Data Portability API `activity.single` | `activity.ongoing` (approval + field coverage to verify) | Potentially yes |

**Launch around one ingestion layer, not per-platform integrations.** X API, Share Extension, Muse, Meta exports and TikTok exports all feed one normalized ingest endpoint. Suggested sequence: **X API → Share Extension → TikTok export → Meta export → Muse MCP.** Don't wait on Muse review, and never ship cookie scraping.

## Per platform

**X.** OAuth PKCE + Bookmarks API is the primary sync (already built). After authorization the phone doesn't need to be involved: keep tokens server-side, poll incrementally, dedupe, and show sync health. Promise "sync recent X bookmarks", not full history (800 cap). Never fall back to scraping; the fallback is the Share Extension.

**Instagram.** Meta itself describes Muse working with a Reel the user **saved on Instagram**, so saved-content access is an intentional Muse integration (verified). There's no public, self-serve Instagram API permission for a consumer's Saved posts or collections. Options, ranked:
- Muse + hindsight MCP `submit_saved_posts`: highest-value experiment, unverified.
- Meta "Download Your Information" JSON importer: best official backfill candidate.
- Share Extension: primary ongoing path at launch.
- Cookie/private API: don't ship.

**Facebook.** Meta's export offers JSON explicitly for transfer to other services (verified). Before advertising "import all Facebook saves", capture a real Sept 2026 archive from a test account: are Saved Items and Collections included, is collection membership represented, and how do Marketplace/Reels/group posts and deleted targets look? Muse solving Facebook saves is **not documented**; treat it as an experiment.

**TikTok.** Data Portability API: available to apply for globally but **returns data only for EEA/UK users** (verified). Scopes include `portability.activity.single/.ongoing`. Requests are asynchronous (webhook when ready, downloads kept 4 days), review takes about 3–4 weeks, the limit is 1,000 requests/min, and it needs Login Kit plus a separate portability review with high-fidelity mockups (connect screen, data explanation, TikTok's unmodified auth screen, result). Verify that `activity` actually contains Favorite Videos vs. Like List before applying. Login Kit / user-info returns profile and stats only, never favorites. For the US: Download Your Data (backfill) + Share Extension (ongoing). Don't hunt for a secret favorites scope.

## Muse deep dive

- **Prefill:** no documented URL scheme, universal-link param, App Intent, Shortcut or share target accepts prompt text. This matches our finding that `?q=` doesn't prefill. **Worth testing: Muse inside WhatsApp.** If Muse's WhatsApp chat can be targeted by a standard prefilled-message link, the flow becomes "tap Sync → WhatsApp opens with prompt → Send".
- **MCP push (most promising):** a narrow tool
  `submit_saved_posts(sync_id, source, items, cursor?, final_batch)`, where items are `{platform_id, url, creator, caption?, saved_at?, collection?}`. The instruction: "read my saved posts in batches, call `submit_saved_posts` after each batch, continue until done, don't print the data in chat". The benefits: no reply-size limit, no clipboard, per-batch acknowledgement and dedup. The tool must be **idempotent** (sync_id, dedup by platform+id and canonical URL) and return tiny results like `{"accepted":47,"duplicates":3,"continue":true}`, never echoing records back.
- **The crucial unknown is permission, not mechanics:** will Meta allow data to flow from Muse's Instagram connector into a third-party connector? This will be settled in Meta's security/legal review. Keep the first connector boring: user-directed transfer of saved-item URLs into the same user's account, and nothing else.
- **Limits:** there are no public Muse payload, rate, tool-call, execution-time or token-lifetime limits. Our "about 100 per reply" is a *chat-output* limit and may not apply to tool calls. Test with 10/50/100/250/1,000 items and prefer many small calls.
- **Scheduling:** Muse can run long tasks after the app closes (verified), but there's no documented recurring connector job. "Ask Muse to sync to hindsight" is plausible; "Muse syncs every night forever" is speculative.
- **Review:** no public review-time SLA. The ecosystem is weeks old, so don't tie a launch date to connector approval.

## Share Extension = hindsight's universal write API

- Enumerate every `NSItemProvider` in every input item. Try `UTType.url`, then `UTType.plainText`, and extract http(s) URLs from text. Keep all plausible URLs and canonicalize on the backend (resolve `vm.tiktok.com` short links, strip `?s=` from X links). Never assume `attachments[0]` is the useful one.
- The social apps' share payloads aren't documented contracts, so **measure on a real iPhone**: log host app, `registeredTypeIdentifiers`, decoded URL and text, and item order (debug builds only, since shared text is user data).
- Expected: Safari sends a URL (high confidence). X, Instagram and TikTok send a URL and/or text with a permalink (medium). Facebook varies most (low–medium).
- **UX: Share → hindsight → "Saved ✓".** No collection picking, no waiting for AI, no opening the app. An optional tag field is fine, but the save happens first.
- **Persist before network:** write to a durable queue in an **App Group** container (for example a small SQLite table: capture_id, raw_payload, raw_url, normalized_url, platform, created_at, upload_state, attempt_count, last_error), try a tiny upload, show Saved, and finish. The app or a background session drains the queue later.
- App Review: the extension must be disclosed and follow the extension guide. **No marketing, ads or in-app purchases inside the extension.**

## Backfill vs ongoing

Make them visibly different features. Users tolerate about 10 taps and a wait **once** to recover years of history, but not per save. Tomorrow's saves go through the Share Extension. Every item keeps provenance: `source_platform, source_item_id, ingest_method (e.g. instagram_meta_export_v2 / instagram_share_extension / instagram_muse), original_url, canonical_url, platform_saved_at?, hindsight_captured_at, import_batch_id?, parser_version?`, so parser changes can be traced and repaired later.

```
X bookmarks API ─┐
Muse MCP ────────┤
Share Extension ─┼──► /v1/saves/ingest → normalize → dedupe → enrich → resurface
Meta export ─────┤
TikTok export ───┤
TikTok portab. ──┘
```

**Comparable products** (mymind, Raindrop, Readwise Reader, Matter, Glasp, Recall): value comes from ubiquitous capture (share sheet/browser), not from mirroring private bookmark databases. No evidence any of them has an API for IG Saved + FB Saved + TikTok Favorites for US users. Dewey is X-bookmarks-focused, and "Sortd" is a shopping wishlist app. UX to copy: first launch "Add hindsight to Share", normal day "Share → hindsight", optional "Bring your old saves with you".

## Risk ranking

| Technique | App Store risk | ToS risk | Ops risk |
|---|---|---|---|
| Official X API | Low | Low | Low–med |
| Share Extension (user-shared URL) | Low | Low | Low |
| User-provided Meta/TikTok export | Low | Low | Med (schema upkeep) |
| TikTok Data Portability | Low | Low after approval | Low–med |
| Approved Muse directory connector | Low/med (novel) | Low after approval | Med |
| User-triggered Muse copy/paste | Low | Low/med | Med |
| Private API scraping | High | High | Very high |
| Storing social login cookies | Very high | High | Very high |

## Experiments to run on a real iPhone (in value order)

1. Share payload matrix: IG, TikTok, X, FB, Safari (public + private posts) into a diagnostic extension.
2. Meta archive fixture: test accounts with known Saved posts/Collections/Reels/Marketplace/group/private items → all-time JSON export.
3. TikTok export fixture: Like vs Favorite distinct known videos → Download Your Data JSON.
4. Muse discovery: Share Sheet, Shortcuts → Apps, Siri/App Intents, more universal-link variants.
5. Muse via WhatsApp: prefilled-message link.
6. **Minimal Muse MCP** (`ping` + `submit_saved_posts`), asking Muse to transfer 10 known IG saves. **The single most important test.**
7. Muse scale (50/100/250/1,000+), pagination (older-than-first-batch saves), recurrence ("every day", with the app killed and phone locked), and auth expiry.
8. Extension offline, stress (20 rapid shares, duplicates) and private-content tests.
9. App Review rehearsal: review video, privacy flow, extension explanation, delete-data flow, test credentials.
