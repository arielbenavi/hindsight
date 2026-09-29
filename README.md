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

## How user data gets in

The main path: each user signs up for **Meta Muse** and gets a `.md` file listing all of their saved posts. The app reads that file.

[`data/ig-saved-posts-seed.md`](data/ig-saved-posts-seed.md) shows what that file looks like (1,216 real saved posts). Each entry has the account, post type, date, caption, and URL:

```
1. **@username** · reel · 2026-09-27
   Caption text…
   https://www.instagram.com/reel/CODE/
```

See [data/README.md](data/README.md) for the full format.

## Docs

- [docs/HANDOFF.md](docs/HANDOFF.md): the state of the project when the web prototype was handed off
- [docs/BACKFILL_STATUS.md](docs/BACKFILL_STATUS.md): what worked and what failed when pulling saved posts from each platform
- [docs/cookie-refresh-workflow.md](docs/cookie-refresh-workflow.md): notes on the Instagram cookie flow and its UX pain points
- [web/README.md](web/README.md): how to run the deprecated prototype

## Who's working on what

- **iOS app**: [@reyr13](https://github.com/reyr13) (Reut)
- **Data pull + onboarding**: [@arielbenavi](https://github.com/arielbenavi) (Ariel)

Workflow: each person runs Claude Code locally against the repo, uses Slack + Claude Tag for brainstorming, and lands code changes through branches + PRs.
