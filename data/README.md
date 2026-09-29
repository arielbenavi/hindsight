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

Types: `reel`, `post`, `carousel`

## Usage

This data lets us:
- Build and test clustering/categorization without hitting IG API
- Design the feed UX with real content volume (1,216 items)
- Test onboarding flow preferences against actual data
- Prototype "how do you want to see your data" without waiting on platform auth
