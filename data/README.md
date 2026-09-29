# Seed Data

Pre-exported saved posts used for development and testing so we're not blocked on live API access.

| file | platform | items | date range | source |
|------|----------|-------|------------|--------|
| `ig-saved-posts-seed.md` | Instagram | 1,216 | 2019-07 → 2026-09 | @pudabeats saved posts export |

## Format

Each entry:
```
N. **@username** · type · YYYY-MM-DD
   Caption text...
   https://www.instagram.com/p|reel/CODE/
```

Types: `reel`, `post` (1,216 entries: 792 reels, 424 posts; 58 have no caption)

This is the format Muse happened to produce when asked for saved reels, so it isn't a contract. The app's canonical format is the Swift `SavedPost` model, and new Muse syncs ask for a fixed JSON schema instead (see `ios/Hindsight/Sync/MusePrompt.swift`). `SavedPostParser` reads both.

## Usage

This data lets us:
- Build and test clustering/categorization without hitting IG API
- Design the feed UX with real content volume (1,216 items)
- Test onboarding flow preferences against actual data
- Prototype "how do you want to see your data" without waiting on platform auth
