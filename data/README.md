# Seed Data

Pre-exported saved posts used for development and testing so we're not blocked on live API access.

| file | platform | items | date range | source |
|------|----------|-------|------------|--------|
| `ig-saved-posts-seed.md` | Instagram | 1,216 | 2019-07 → 2026-09 | @pudabeats saved posts export |
| `ig-reut-export/` | Instagram | 324 unique | 2024-08 → 2026-09 | @reut_rabin "Download your information" export |

The two sets cover different interests on purpose: Ariel's is mostly AI, quant, music and fitness/mobility tips; Reut's is mostly NYC restaurants and cafes, organized into saved collections per city or theme.

## Format: `ig-saved-posts-seed.md` (Ariel, via Muse)

Each entry:
```
N. **@username** · type · YYYY-MM-DD
   Caption text...
   https://www.instagram.com/p|reel/CODE/
```

Types: `reel`, `post` (1,216 entries: 792 reels, 424 posts; 58 have no caption)

This is the format Muse happened to produce when asked for saved reels, so it isn't a contract. The app's canonical format is the Swift `SavedPost` model, and new Muse syncs ask for a fixed JSON schema instead (see `ios/Hindsight/Sync/MusePrompt.swift`). `SavedPostParser` reads both.

## Format: `ig-reut-export/` (Reut, Instagram data download)

The raw files from Instagram's export (`your_instagram_activity/saved/`), unmodified:

- `saved_collections.json`: 15 saved collections (e.g. "NYC Restaurants", "NYC cafe", "Brooklyn", "Argentina"), each with its posts. 253 posts.
- `saved_posts.json`: 113 saved posts from 2025-11 onward, whether or not they're in a collection. 72 of them are in no collection.

Each post has the URL, the **full caption** (median 204 characters, up to 3,200), hashtags, and the owner (username, display name, profile link). There's no location tag, no media or thumbnail, and no post type beyond what the URL says (`/reel/` or `/p/`). The `timestamp` is when it was saved (Unix seconds).

Gotcha: text is UTF-8 that Instagram escaped as if each byte were a Latin-1 character, so `we’re` reads as `weâ\u0080\u0099re`. Decode each string with `latin-1 → bytes → utf-8` before using it.

## Usage

This data lets us:
- Build and test clustering/categorization without hitting IG API
- Design the feed UX with real content volume (1,216 items)
- Test onboarding flow preferences against actual data
- Prototype "how do you want to see your data" without waiting on platform auth
