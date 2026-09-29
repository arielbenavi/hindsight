# hindsight

Your saved posts, finally usable. People save hundreds of Instagram and Facebook posts (restaurants and coffee shops to try in a city, recipes, tips) and never go back to them. Hindsight turns a user's saved posts into an interface they'll actually use.

The product is an **iOS app**. The original web prototype is kept in [`web/`](web) for reference but is deprecated.

## Repo layout

```
ios/     the iOS app (new work goes here)
data/    seed data: example saved-post exports used for development
docs/    research, platform notes, and handoff docs
web/     deprecated web prototype (Python backend + React frontend)
```

## Running the iOS app

**Requires [XcodeGen](https://github.com/yonaskolb/XcodeGen).** The Xcode project isn't committed; it's generated from `ios/project.yml`.

```bash
brew install xcodegen
cd ios && xcodegen && open Hindsight.xcodeproj
```

Change project settings in `ios/project.yml`, not in Xcode's settings UI. See [ios/README.md](ios/README.md) for why, and for the full rules.

## How user data gets in

Every platform is different; see [docs/DATA_FETCHING_RESEARCH.md](docs/DATA_FETCHING_RESEARCH.md) for the full picture.

- **Instagram + Facebook:** through **Meta Muse**. The app opens Muse with our question on the clipboard, Muse replies with a JSON list of saves, and the user pastes it back. This works on a real iPhone today. A Muse MCP connector (needs our backend) would remove the paste.
- **X:** "Connect X" (OAuth 2.0 PKCE, X's own sign-in page). Pulls the user's bookmarks. Works on device.
- **TikTok:** no official API for US users. The plan is a share extension ("Share → hindsight") for new saves plus the "Download your data" export for backfill.
- Everything becomes a Swift `SavedPost` (`ios/Hindsight/Models/SavedPost.swift`). [`data/ig-saved-posts-seed.md`](data/ig-saved-posts-seed.md) (1,216 real IG saves in Muse's markdown format) is bundled so the app has real content during development.

Next (planned): a hosted **ingestion backend**, ported from `web/backend/`, that turns each save into transcript, on-screen text, summary, tags and embeddings.

## Docs

- [docs/HANDOFF.md](docs/HANDOFF.md): current status, open decisions, and the web prototype's handoff notes
- [docs/DATA_FETCHING_RESEARCH.md](docs/DATA_FETCHING_RESEARCH.md): how the iOS app gets saves from each platform, what's verified, what's open
- [docs/LESSONS.md](docs/LESSONS.md): gotchas and dead ends. **Read before starting a session; add to it when something surprises you.**
- [docs/research/SYNC_RESEARCH_PROMPT.md](docs/research/SYNC_RESEARCH_PROMPT.md): open research brief on the smoothest sync per platform
- [docs/BACKFILL_STATUS.md](docs/BACKFILL_STATUS.md): what worked and what failed when pulling saved posts from each platform
- [docs/cookie-refresh-workflow.md](docs/cookie-refresh-workflow.md): notes on the Instagram cookie flow and its UX pain points
- [web/README.md](web/README.md): how to run the deprecated prototype

## Who's working on what

- **iOS app**: [@reyr13](https://github.com/reyr13) (Reut)
- **Data pull + onboarding**: [@arielbenavi](https://github.com/arielbenavi) (Ariel)

Workflow: each person runs Claude Code locally against the repo, uses Slack + Claude Tag for brainstorming, and lands code changes through branches + PRs.
