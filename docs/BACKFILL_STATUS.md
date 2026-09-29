# Savefeed Backfill — Status & Lessons Learned

Last updated: 2026-09-29

---

## Platform Status Summary

| Platform | Method | Status | Items in DB | Notes |
|----------|--------|--------|-------------|-------|
| **Twitter/X** | OAuth API | **Done** | 97 bookmarks (all) | Fully backfilled, zero new items left |
| **Instagram** | Cookie API | **In progress** | ~193 IG posts | 233 seen, 129 ingested across 3 sessions, `more_available: true` |
| **Facebook** | Cookie scraping | **Blocked** | 0 | mbasic.facebook.com broken; www.facebook.com is JS-only SPA |
| **TikTok** | Manual only | **Deferred** | 0 | Adapter exists (yt-dlp), no automated sweep yet |

**Total DB items: ~301** (97 tweets + ~193 IG + misc web/notes)

---

## Twitter/X — Complete

### What works
- OAuth 2.0 with PKCE, `bookmark.read` scope
- `GET /2/users/{id}/bookmarks` with `pagination_token`
- Watermark-based sweep every 30 min catches new bookmarks
- Full backfill ran in one pass: 97 items, all already in DB (were captured by sweeps)

### Key details
- Token auto-refreshes via `auth.py`
- Rate limit: 180 req/15min (Basic tier)
- Inter-item delay: 5s (Gemini processing is the bottleneck)
- State file: `~/.savefeed/twitter_backfill_state.json`

### Lessons
- Twitter API is the most reliable platform — straightforward pagination, no cookie games
- All 97 bookmarks were already captured by recurring sweeps before backfill ran
- X API credits cost $0.001/bookmark read — negligible

---

## Instagram — In Progress

### What works
- Cookie-based private API: `GET /api/v1/feed/saved/posts/` with `max_id` pagination
- Cookies exported via "Get cookies.txt LOCALLY" Chrome extension
- 100 items/session cap to avoid soft-bans
- Resumable: cursor saved to `~/.savefeed/ig_backfill_state.json`
- Skip optimization: deduped items don't sleep (saves ~60% time on pages with known items)

### Key details
- Cookies file: `~/.savefeed/cookies.txt` (set via `IG_COOKIES_FILE` in `.env`)
- Required cookie: `sessionid`
- UA: standard Instagram app user-agent
- Inter-item delay: 10s (stricter than Twitter)
- Inter-page delay: 3s
- Sweep runs every 30 min for new saves

### Backfill progress
- Session 1: ~76 items
- Session 2: ~100 items (cap hit)
- Session 3: 233 seen, 129 ingested, 1 failed, `more_available: true`
- Resume with: `curl -X POST http://127.0.0.1:8000/sweep/ig/backfill`

### Lessons
- IG private API is reliable but needs conservative pacing (10s delays)
- Cookies last ~90 days — re-export when they expire
- The API only returns posts still in your Saved; un-saved posts are gone (use data export for complete history)
- `max_id` pagination is cursor-based, not offset-based — stable across saves/unsaves
- Session cap of 100 is important — IG will shadow-ban at ~200-300 requests

---

## Facebook — Blocked (needs different approach)

### What was tried

#### 1. mbasic.facebook.com cookie scraping (FAILED)
- **Goal**: Scrape `https://mbasic.facebook.com/saved/` using exported cookies, parse HTML for links
- **Result**: Page returns "Facebook is not available in this browser" error page (title "שגיאה")
- **Root cause**: mbasic.facebook.com has tightened browser detection. Returns error for ALL user-agent strings tested:
  - Desktop Chrome → "unsupported browser" interstitial
  - Mobile Chrome (Android) → same error  
  - iPhone Safari → redirects to `m.facebook.com/login` (cookies not accepted)
  - Nokia feature phone → same error
  - Raw `Cookie:` header → same error
- **Conclusion**: mbasic.facebook.com is effectively dead for cookie-based scraping

#### 2. www.facebook.com static HTML scraping (FAILED)
- **Goal**: Fetch `https://www.facebook.com/saved/` and extract items from server-rendered HTML
- **Result**: Page is 1.7MB React app shell with zero saved item data in HTML
- Extracted auth tokens successfully: `fb_dtsg`, `lsd`, `hsi`, `c_user`
- But all saved items data is loaded client-side via GraphQL after JS execution
- **Conclusion**: Cannot scrape without a full JS runtime

#### 3. GraphQL API with doc_id (FAILED)
- **Goal**: Call `POST /api/graphql/` directly using auth tokens extracted from page
- **Attempt 1**: Used known doc_id `5889917927699928` → "document not found" (doc_ids rotate with FB deployments)
- **Attempt 2**: Used `fb_api_req_friendly_name` without doc_id → "Must provide either query_id or q" 
- **Attempt 3**: Tried `CometSavedItemsAllPaginationQuery` as friendly_name with full params → "Incorrect Query"
- **Root cause**: FB requires either a valid `doc_id` (rotates frequently) or raw query text `q`
- No doc_ids are embedded in the HTML (they're loaded from external JS bundles)
- **Conclusion**: GraphQL approach requires capturing fresh doc_ids from live browser traffic

#### 4. Chrome browser DOM scraping (PARTIAL)
- **Goal**: Use Claude in Chrome extension to read saved items from rendered page
- **Result**: Successfully extracted 10 unique saved items (all FB reels/videos)
- Items found: `/reel/{id}/` links (deduplicated from `/watch/?v={id}` duplicates)
- **Problem**: Infinite scroll doesn't trigger further loading — page stuck at ~10 items
- Tried: window.scrollTo, scroll events, waiting — skeleton loader visible but never loads
- **Conclusion**: Works for visible items but can't paginate

#### 5. Network interception for doc_id capture (IN PROGRESS, abandoned)
- **Goal**: Intercept fetch/XHR in Chrome to capture the GraphQL doc_id from live requests
- Patched `fetch()` and `XMLHttpRequest` — captured 0 requests
- FB likely uses a web worker or custom network layer that bypasses standard APIs
- Chrome extension's `read_network_requests` sees 7 graphql POSTs but doesn't expose bodies
- **Conclusion**: Need Chrome DevTools Protocol or HAR export to capture request bodies

### What could still work

1. **Data export** (most reliable, highest friction):
   - Facebook → Settings → Download Your Information → Saved Items → JSON
   - Takes 24-48 hours for FB to prepare
   - Endpoint ready: `POST /backfill/fb-export?file_path=~/Downloads/facebook-export.zip`
   
2. **Playwright/headless browser** (medium reliability, medium effort):
   - Use Playwright with real browser profile to render the saved page
   - Scroll and collect URLs from rendered DOM
   - Risk: FB's bot detection (device fingerprinting, behavioral analysis)
   
3. **Chrome DevTools Protocol** (for doc_id capture):
   - Connect to Chrome via CDP, intercept network at protocol level
   - Capture the exact `doc_id` and request format from live traffic
   - Then replay via httpx (until doc_id rotates again with next FB deploy)
   
4. **Manual URL collection** (lowest effort, one-time):
   - User scrolls through facebook.com/saved/ manually
   - Copy-paste URLs or use a bookmarklet to collect them
   - Feed to `/capture` endpoint

### FB cookies location
- File: `~/.savefeed/fb_cookies.txt`
- Exported from facebook.com via "Get cookies.txt LOCALLY" extension
- Contains valid `c_user`, `xs`, `fr` cookies
- Cookies ARE valid for www.facebook.com (page loads with auth) — just can't scrape content without JS

### FB sweep infrastructure (ready, waiting on working scraper)
- `sweep.py`: `sweep_fb_saved()` + all helpers (parse cookies, fetch page, extract URLs, watermark)
- `app.py`: `POST /sweep/fb` manual trigger, `POST /sweep/fb/backfill`, 30-min auto-sweep loop
- `backfill.py`: `fb_backfill()` with resumable state
- All wired up and registered in server lifespan — just needs a working data source

---

## Architecture & Infrastructure

### Backfill system (`backfill.py`)
- `BackfillState` class: JSON state files at `~/.savefeed/{platform}_backfill_state.json`
- States: `idle → running → paused/done`
- Saves after every item — survives crashes
- Cursor-based resume: picks up exactly where it left off
- Three-layer dedup: URL dedup in DB, cursor-based resume, watermark handoff

### Ingestion pipeline
- URL → platform adapter (yt-dlp for video, trafilatura for web) → Gemini summarization → DB
- Per-item data: summary, raw_text, transcript, on_screen_text, category, key_takeaways, tags, 768-dim embedding
- Gemini free tier: 15 RPM generate, 1500 RPM embeddings — running at ~3 RPM (well under)

### Recurring sweeps
| Platform | Interval | Endpoint | Auto-start |
|----------|----------|----------|------------|
| Twitter | 30 min | `POST /sweep/twitter` | Yes (lifespan) |
| Instagram | 30 min | `POST /sweep/ig` | Yes (lifespan) |
| Facebook | 30 min | `POST /sweep/fb` | Yes (if cookies present) |

### Key endpoints
| Endpoint | Purpose |
|----------|---------|
| `GET /setup` | Health checks + setup instructions |
| `GET /sweep/status` | All sweep statuses (auth, last run) |
| `GET /backfill/status` | All backfill progress |
| `POST /sweep/{platform}/backfill` | Trigger historical backfill |
| `POST /sweep/{platform}` | Trigger one-off sweep |

### Files modified this session
- `backfill.py` — FB UA fix (desktop→mobile), FB backfill functions
- `sweep.py` — FB UA fix, FB sweep infrastructure
- `app.py` — FB sweep loop in lifespan, `POST /sweep/fb` endpoint

---

## Recommendations for next session

1. **Resume IG backfill**: `curl -X POST http://127.0.0.1:8000/sweep/ig/backfill` (still has more items)
2. **FB decision needed**: Choose between:
   - Request FB data export (most reliable, 24-48h wait)
   - Try Playwright approach (needs testing, bot detection risk)
   - Try Chrome DevTools Protocol for doc_id capture (technical but could work)
3. **Commit changes**: FB sweep wiring + UA fixes not yet committed
