# ADR-001: One app. Merging the onboarding + data work with the lego screens

**Status:** Proposed. D1–D3 decided 2026-09-30 (zero AI compute cost; see [AI requirements](#ai-requirements-read-this))
**Date:** 2026-09-30
**Deciders:** Reut + Ariel (the decisions are listed in [Decisions to make together](#decisions-to-make-together))

## TL;DR

- **The git merge is easy.** A trial merge of all three branches (`reut/mvp-build` + `master` + `ariel/muse-sync`) had **zero textual conflicts**, built, and passed **92/92 tests** (checked 2026-09-30). The merged app lives on branch **`all/merge`** (`origin/reut/mvp-build` + `master` + `ariel/muse-sync`, merged 9/30 with no conflicts). **Heads-up:** the separate design revamp (branch `reut/design-revamp`, `123c42f`) restyles `ConnectStep.swift`, which **conflicts** with Ariel's copy change on `master` (`c264da5`: TikTok copy + the WhatsApp notes "soon" row). Resolve it when the design revamp meets `all/merge` or `master`: keep the new layout and Ariel's rows and copy.
- **The hard part is the seam between the two halves.** Ariel's half gets a user's saves *into* the phone (`SavedPost`). Reut's half makes a contract file *usable* (`ContractFile`). Nothing connects them yet: after onboarding, `RootView` ignores everything the user just imported and loads a bundled fixture instead.
- **The missing piece is steps 2–3 of the data contract (Sort + Extract).** For the fixtures these ran once, offline, via Claude subagents and a hand-written topics file. No runtime code does them yet, so no new user can get their own tabs today.
- **The product seam has five rough edges:** two endings ("You're in" → then a chat starts), a Preferences step that the app ignores, a "Whose saves are these?" picker right after the user connected their own, two design systems, and seed data mixed into every user's saves.
- **Proposal:** one router, one live dataset per user, a single onboarding arc (*Connect → Reading your saves → Here's your app → Is this right? → your tabs*), and an **on-phone sort engine with zero AI compute cost**: rules and group labels first, then Apple's models (Private Cloud Compute, on-device) only for what's left, then the user for anything still unsure.

---

## AI requirements (read this)

> [!IMPORTANT]
> **The iPhone's system language must be one Apple Intelligence supports (e.g. English). Hebrew is not supported, even in iOS 27.**
> Apple Intelligence only turns on when **Settings → General → Language & Region → iPhone Language** and the **Siri language** are the same supported language. Without Apple Intelligence the app gets **no model at all**: no on-device model and no Private Cloud Compute, even for English posts. Such phones still work, on the rules + groups + questions path only.

| Requirement | Why | Our testers (9/30) |
|---|---|---|
| iPhone 15 Pro, iPhone 16 or newer | Apple Intelligence hardware | All on iPhone 16+ ✅ |
| iOS 27 | `PrivateCloudComputeLanguageModel` is iOS 27+ (on-device model is iOS 26+) | — |
| System + Siri language = a supported language (English, Spanish, French, German, …; **not Hebrew**) | Apple Intelligence won't turn on otherwise | All English ✅ |
| Apple Intelligence on, model downloaded | `SystemLanguageModel.availability` | check in-app |
| Signed in to iCloud | The Private Cloud Compute quota is per iCloud account | — |

**Hebrew captions** (7% of Reut's saves, 13% of Ariel's) are refused by the on-device model even on an English phone (`unsupportedLanguageOrLocale`). Whether Private Cloud Compute accepts them is the first thing the on-phone test checks (see E3). Until then they go through rules, collections and questions.

**Private Cloud Compute terms:** free while enrolled in the App Store Small Business Program with < 2M first-time downloads (TestFlight doesn't count). Managed entitlement `com.apple.developer.private-cloud-compute`: **granted to Reut's account 2026-09-30**. The quota is per iCloud account and opaque (only below / approaching / reached + reset date). No paid tier: past 2M we have 6 months to migrate, which is why every model sits behind one `LanguageModel`-based interface.

---

## Context

### Who built what, and why

| | **Ariel** (data pull + onboarding) | **Reut** (frontend / UX) |
|---|---|---|
| **Job** | Get a user's saves off Instagram, Facebook, X and TikTok, with as little friction as possible. First-run onboarding. | Turn saves into an app people use: lego screens, the layout proposal, place confirmation, the practice loop. |
| **Before iOS** | `web/`: FastAPI + SQLite + Gemini ingestion, cookie sweeps, React dashboard (June–Sept, now deprecated). The research behind [SYNC_PLAN.md](SYNC_PLAN.md) and [DATA_FETCHING_RESEARCH.md](DATA_FETCHING_RESEARCH.md). | Repo restructure, XcodeGen, the MVP sprint and every spec in [`specs/`](specs), the [data contract](data-contract.md). |
| **iOS code** | `Models/SavedPost` (now contract v1 fields), `Import/` (Muse JSON, seed markdown, IG/FB/TikTok export + zip parsers, `SavedPostStore`), `Onboarding/` (5 steps + `OnboardingStyle`), `Sync/` (Muse clipboard / WhatsApp / MCP connector, X OAuth + bookmarks), `DebugLog`, `scripts/device.sh` | `Contract/`, `App/` (`AppModel`, `RootView`, `JSONFile`), `Design/Theme`, `Layout/` (rules + proposal chat), `LegoScreens/` (Map + Confirmation, Learn, Fitness), `Practice/` |
| **Data** | `data/ig-saved-posts-seed.md` (1,216 posts, captions cut at 160) | `data/ig-reut-export/`, `data/fixtures/` (contract files + extraction tooling + warm MapKit caches) |
| **Server** | `connector/server.py`: single-user Muse MCP experiment behind a tunnel (branch `ariel/muse-sync`, unmerged) | none |
| **Where it lives** | `master` (PR #1, #5) + `ariel/muse-sync` (5 commits ahead) | `reut/mvp-build` (PR #4, 23 commits, open) |

The line between them is the **data contract**. Ariel's side produces `posts[]`; Reut's side consumes `posts[] + topics[] + items[]`.

```
Contract step       Owner (per data-contract.md)   What exists today
─────────────────   ────────────────────────────   ─────────────────────────────────────────────
1. Pull  posts[]    Ariel                          ✅ SavedPost + parsers + SavedPostStore (live, on device)
2. Sort  topics[]   Ariel                          ❌ only TopicSuggester keyword counts (placeholder)
3. Extract items[]  Ariel                          ❌ done offline for the fixtures (Claude subagents + EXTRACTION.md)
4. Match (Map)      app                            ✅ PlaceMatcher (MapKit, throttled, cached)
5. Use              app                            ✅ Layout proposal, Confirmation, Map, Learn, Fitness, Practice
```

Steps 2–3 are items 4–6 of *Changes needed on Ariel's side* in the contract. Items 1–3 are done (the prompt change sits on `ariel/muse-sync`).

### What happens on a fresh install today (merged tree)

1. `HindsightApp` shows `OnboardingFlow(store:)` with a `SavedPostStore` that **already holds the 1,216 seed posts** (`SavedPostStore.init` merges `SeedData.posts()` when there's no file yet).
2. Welcome → How it works → Connect (Muse / X) → **Preferences** (grouping, feed/grid/collections, topic chips, resurface cadence) → **Done** ("You're in. N saves") → *Open hindsight*.
3. `RootView` creates its own `AppModel`, which loads a **bundled fixture** (`reut` / `ariel`). It first asks "Whose saves are these?", then runs the proposal chat → confirmation → tabs.
4. The `SavedPostStore` and `OnboardingPreferences` are never read again.

### Forces

- **Deadline:** TestFlight on Mon 10/5 ([mvp-sprint.md](mvp-sprint.md)). Today is Wed 9/30.
- **Goal of this merge:** anyone can install the app and onboard with **their own** saves, and it feels like one product.
- **Data arrives slowly and in pieces:** Muse paste gives ≤ 50 posts per reply. X caps at 800. Exports take days. The Muse connector is an unverified experiment. The first layout has to work from a partial pull, and later saves have to land without breaking it.
- **LLM work can't ship an API key in the app.** Anything beyond rules needs a server, or Apple's on-device models (post-MVP per the sprint doc; Apple Intelligence devices only).
- **Signing:** Reut's Individual account. Ariel can't sign, and TestFlight uploads go through Reut.
- **Deferred on purpose:** extraction *quality* tuning waits for live data ([build plan → Deferred](mvp-frontend-build-plan.md#deferred)). This plan makes live data possible; it doesn't tune it.

---

## Where the two halves conflict

Ordered by how much each blocks the goal. 🔴 blocks "anyone can onboard". 🟠 breaks cohesion. 🟡 hygiene.

| # | Conflict | Ariel's side | Reut's side | Why it matters |
|---|---|---|---|---|
| C1 🔴 | **No runtime Sort + Extract** | `TopicSuggester` keyword counts | Screens need `topics[]` + `items[]` | Without it, a real user's saves can't become tabs. Only bundled fixtures work. |
| C2 🔴 | **Two sources of truth for "the user's saves"** | `SavedPostStore`: one global `saved-posts.json` | `AppModel`: one bundled `Dataset` per tester, state under `Hindsight/<dataset>/` | Imports go into a store the app never reads. |
| C3 🔴 | **Seed data mixed into every user's saves** | `SavedPostStore` seeds from Ariel's 1,216 posts on first launch | Fixtures are bundled and selectable | A new tester's app would contain Ariel's saves. |
| C4 🟠 | **Two answers to "how do you want to see it?"** | `PreferencesStep` + `OnboardingPreferences` (grouping, layout, topics, resurface) | Layout proposal chat → `LayoutConfig` | The user answers questions nothing reads, then gets asked again differently. |
| C5 🟠 | **Two endings** | `DoneStep`: "You're in." → *Open hindsight* | Proposal chat starts: "Okay, I went through your saves…" | Feels like two apps stitched together. |
| C6 🟠 | **Dataset picker after the user connected their own data** | Connect step imports *your* saves | `DatasetPicker`: "Whose saves are these?" | Contradicts what just happened. |
| C7 🟠 | **Two design systems** | `OnboardingStyle` (+ `OnboardingPage`, `OnboardingChip`, button styles) | `Theme` (copied the same values) | Near-identical today, but they will drift. Two places to restyle. |
| C8 🟠 | **Syncing only exists inside onboarding** | Muse / X live in `ConnectStep` | No sync entry point in the tabs | Users can't add new saves after day one. The whole practice loop assumes a growing library. |
| C9 🟡 | **Two post models** | `SavedPost` (Swift camelCase, `Date`, `author: String`) | `ContractPost` (snake_case JSON, string dates, `author {username, display_name}`) | Same fields since PR #5, different shapes. Needs one adapter; unifying later is optional. |
| C10 🟡 | **Two routers / global flags** | `HindsightApp` + `@AppStorage hasCompletedOnboarding` | `RootView` phase logic + per-dataset `layout.json` / `flags.json` | Reset, resume and "what screen am I on" live in two places. |
| C11 🟡 | **`project.yml`** | Next: share extension target + App Group | Fixture bundling, location key, Info.plist | Same file, parallel edits. Also: what ships in Release? |
| C12 🟡 | **Muse connector is single-user** | `connector/server.py`, local tunnel, one token | n/a | Fine as an experiment, but it can't serve "anyone" as is. |

---

## Decision

### 1. One arc for the user

```
 Ariel's shell (restyled on Theme)                        Reut's screens
┌───────────┬──────────────┬────────────┬─────────────────┐┌───────────────────┬───────────────────┬────────────┐
│ Welcome   │ How it works │ Connect    │ Reading your    ││ Here's your app   │ Is this right?    │ Your tabs  │
│           │              │ Muse · X · │ saves (NEW)     ││ proposal chat     │ place cards       │            │
│           │              │ file · demo│ counts + taste  ││ B1 → B5           │ (if there's a Map)│            │
└───────────┴──────────────┴────────────┴─────────────────┘└───────────────────┴───────────────────┴────────────┘
   progress capsules continue through the whole arc; "You're in." moves to the very end
```

- **Remove `PreferencesStep` and `DoneStep`** (C4, C5). Grouping and layout are decided by the proposal. Topic chips become B1. Resurface cadence already lives in Learn/Fitness setup (reminders).
- **Add a "Reading your saves" step** in their place. It keeps the best of `DoneStep`: the celebratory count ("**324** saves · Instagram 227 · X 97") and the "taste of what's in there" cards. Those become what you look at while sorting runs, with the progress line from the proposal spec ("Reading your saves… 180 of 324").
- **The chat picks up the same numbers and voice** ("Okay, I went through your 324 saves"), so the reading step and B1 read as one conversation.
- **The last line of the arc is the "You're in" moment:** C5's "Map's ready. Go eat something.", or B5's "Building it… 🔨" when there's no Map.
- **One progress indicator for the whole arc**, not five capsules that end before setup starts.
- **Connect gets two more rows:** *Import a file* (the export parser already exists; SYNC_PLAN 0.3) and *Just looking? Try it with sample saves* (demo mode, see D6). This also covers people without Muse, and App Review.
- **After onboarding:** a **Sync** sheet reachable from every tab header (next to Everything else), reusing `ConnectStep`'s rows (C8).

### 2. One data path

```
Sources (Ariel)                 Device (everything runs on the phone)
───────────────                 ────────────────────────────────────────────────────────────────────────────
Muse paste / connector ─┐
X bookmarks ────────────┼─► SavedPostStore (per user, NO seed)
Export file ────────────┤        │  SavedPost → contract posts[] (adapter)
(Share ext., later) ────┘        ▼
                          SortEngine   ── layer 1  Rules: 📍, location tags, addresses, venue mentions, fitness /
                                       │           tip / meme signals, "comment X" CTAs → confident posts decided
                                       ├─ layer 2  Groups: each collection and each repeat author labeled ONCE
                                       │           (model or majority of rule-decided members), members inherit
                                       ├─ layer 3  Model, only for what's left: Private Cloud Compute → on-device
                                       │           → skipped (Hebrew, no Apple Intelligence, quota reached)
                                       ├─ layer 4  Still unsure → questions in the proposal chat, or Everything else
                                       └─ details  places: rules first, model picks venue names, MapKit + confirmation cards
                                                   tips / routines: rule fields now, model wording lazily when a card is shown
                                 ▼
                     Hindsight/me/hindsight.json  ──► HindsightData ──► AppModel ──► proposal / confirmation / tabs
                     (+ layout.json, places, practice, match-cache: unchanged)
```

- **`Dataset` gets a live kind** (C2): `.live("me")` reads `Application Support/Hindsight/me/hindsight.json`, written by the sort engine. `.bundled(url)` stays for demo and dev. All the per-dataset user state (`JSONFile`, `PlaceStore`, `PracticeStore`) works unchanged.
- **`SavedPostStore` starts empty** (C3). It moves under the live dataset's folder. The seed is only merged for the demo / `DEBUG` path. Existing tests pass the seed explicitly.
- **Adapter, not unification (C9):** one `ContractPost.init(_ savedPost:)`. The two types are field-for-field compatible since PR #5, so the adapter is ~40 lines with a round-trip test. Merging the two types is later cleanup.
- **Zero AI compute cost, by design.** No server and no API key. Models are used last and least, and every model call is one small, well-scoped question. Measured on the fixtures (2026-09-30):
  - **Rules alone** confidently decide 47% of Reut's posts (82% agree with the fixtures), but only 3% of Ariel's (short captions, no collections).
  - **Groups are the big lever:** Reut's 15 collections cover 252 of her 324 posts, so 15 questions replace 252. Ariel's repeat authors cover 740 of 1,216 posts, and 88% of each author's posts land in the same bucket.
  - **Lazy details:** tip and routine wording is only generated when a card is about to be shown (Today's 1 shows one a day), not for 400 posts up front.
- **The fixture tooling stays the reference.** `EXTRACTION.md`'s rules become the engine's instructions and the rules layer. `validate.py`'s checks run as Swift tests on the engine's output. The committed fixtures are the golden set the engine is scored against (the in-app eval, E3).
- **Incremental from day one (the Muse 50-per-reply reality):** results are cached by `post_id` + caption hash. Later syncs sort only new posts, into existing topics. Posts that fit none land in Everything else. **The approved `LayoutConfig` never changes on its own.** "Rebuild my app" stays a later feature (layout-proposal spec, decided item 3).
- **Quota-aware:** the engine checks `quotaUsage` before each batch. It slows down when the quota is approaching; when it's reached, it finishes with rules + groups + questions and resumes after `resetDate`. The user never waits on it. Onboarding proceeds with whatever's decided.

### 3. One router

`RootView` becomes the single router for the whole arc, derived from persisted state. `HindsightApp` just hosts it (C10):

```swift
enum Phase { case onboarding, reading, proposal, confirmation, tabs }
// onboarding   : no saves and no demo chosen
// reading      : saves exist, no hindsight.json yet (or a sort job in flight)
// proposal     : hindsight.json exists, no layout.json
// confirmation : layout has a Map and flags.confirmationDone == false
// tabs         : otherwise
```

- Killing the app anywhere resumes at the right place. The job id is persisted, so a sort in progress is re-polled.
- `hasCompletedOnboarding` goes away. The phase is computed from what exists on disk.
- `DatasetPicker` only shows in `DEBUG` or from the ladybug menu (C6).
- `OnboardingFlow` keeps its own internal steps (Welcome, How it works, Connect). Its `onFinish` now means "saves are in, start reading".

### 4. One theme

`Theme` is the source of truth (C7). `OnboardingStyle`'s members become one-line aliases to `Theme` in a single commit, so none of Ariel's call sites change. The onboarding components (`OnboardingPage`, `OnboardingChip`, button styles) move into `Design/` later, when nobody has them open.

---

## Options considered (for the biggest call: where Sort + Extract runs)

**Decided 2026-09-30: Option D.** Reut's goal is zero AI compute cost. Options A–C are kept for the record.

### Option D: on-phone sort engine, rules first, Apple's models for the rest (chosen)

| Dimension | Assessment |
|---|---|
| Complexity | Medium. Swift only, in our own folder. The model layers share one `LanguageModel`-based interface. |
| Cost | **Zero AI compute cost** while under the Private Cloud Compute free tier (< 2M downloads). No server. |
| Scalability | Per user and per iCloud quota. Group labeling and lazy details keep model calls well below one per post. |
| Team familiarity | Medium. The Foundation Models API is new, but `@Generable` code is already written and tested (`scratchpad fm/eval2.swift`, to be moved in). |

**Pros:** free; captions never touch our servers (Apple's servers keep nothing); works offline for everything but the Private Cloud Compute layer; no hosting decision. **Cons:** Apple Intelligence phones only (see [AI requirements](#ai-requirements-read-this)); Hebrew unproven; opaque quota; no paid tier to grow into. **Mitigations:** the rules + groups + questions path works on every phone, and Option A stays the documented fallback behind the same interface.

### Option A: hosted sort job reusing the Python fixture tooling (fallback)

| Dimension | Assessment |
|---|---|
| Complexity | Medium. One small service with 2 endpoints. The prompt, merge rules and validator already exist and produced both fixtures. |
| Cost | LLM tokens per onboarding (~33k caption tokens for a whole import), plus a small host. |
| Scalability | Fine for a friends beta. It's the seed of SYNC_PLAN phase 2. |
| Team familiarity | High. Ariel built the FastAPI + Gemini backend in `web/`. Reut's tooling is Python. |

**Pros:** handles Hebrew; same code for fixtures and live data; the prompt can change without an app update. **Cons:** ongoing AI cost (rejected on 9/30); captions leave the device; needs a host.

### Option B: on-device model only

Tested 2026-09-30 on 115 fixture posts (macOS 26.6 model): **62–70%** bucket accuracy, **~41%** of place names, Hebrew refused, 2–5% of benign English posts blocked by guardrails. Not enough on its own. It becomes layer 3's fallback inside Option D.

### Option C: keep generating fixtures offline and bundle one per tester

Zero new infrastructure, but not "anyone can onboard". It's the Monday safety net only.

### Trade-off

D is the only option with zero AI cost and no server. It trades device coverage (Apple Intelligence phones) and unproven Hebrew for that. Designing it rules-first means the model is an accelerator, not a dependency: every phone gets a working app, and Apple Intelligence phones get a smarter one. A remains the escape hatch if D fails the on-phone test.

---

## Decisions to make together

Each has a recommendation. **D1 and D10 decide the sprint's shape; settle them first.**

| # | Decision | Recommendation | Who |
|---|---|---|---|
| **D1** | Where Sort + Extract run | ✅ **Decided 9/30: Option D.** On-phone sort engine, rules → groups → Private Cloud Compute → on-device → user. Zero AI compute cost. | Reut |
| D2 | Which models | ✅ **Decided 9/30:** Apple's Private Cloud Compute first, on-device model second. Both via the Foundation Models framework. Entitlement granted 9/30. | Reut |
| D3 | Hosting | ✅ **Not needed for sorting.** It stays open only for the Muse connector and X server-side sync (SYNC_PLAN phase 2). Fly.io / Cloud Run came from the old video-ingestion plan; re-evaluate from scratch (Firebase, Vercel, Cloudflare…) when it's needed. | Reut + Ariel |
| D4 | Onboarding arc | Remove `PreferencesStep` + `DoneStep`, add *Reading your saves*, one progress indicator, "You're in" at the end | Reut (product), Ariel (his files) |
| D5 | Owners of the shared files for this sprint | Ariel owns `Onboarding/`, `Sync/`, `Import/`, `Models/`, the server. Reut owns `App/` (router), `Design/`, `Layout/`, `LegoScreens/`, `Practice/`. `project.yml` changes go through one small PR each, announced in Slack. | both |
| D6 | Demo data in TestFlight | Ship one demo dataset behind *Try it with sample saves*. Use Reut's (she consents), not Ariel's seed, unless Ariel wants his in too. Ask the girlfriend before any of her data is ever bundled. | both |
| D7 | Post models | Adapter now (`SavedPost` → `ContractPost`), unify later | Reut |
| D8 | Muse path for Monday | Paste (+ WhatsApp route) is the supported path. The connector stays a `DEBUG` experiment until a host exists (D3), then it moves there with per-user tokens. | Ariel |
| D9 | New saves after the layout is approved | Incremental: join existing topics, else Everything else; never change tabs automatically | Reut |
| **D10** | Monday's bar | **Monday = merged app where a fresh install onboards with its own data (Option D)**, plus the demo. If the engine isn't good enough by Sat night, ship C for the 3 testers and keep D behind the ladybug menu. | Reut + Ariel |

---

## The sprint (Thu 10/1 → Mon 10/5)

### Day 0: merge (✅ done 9/30 on `all/merge`)

The three lines are merged on **`all/merge`**, kept separate from the design revamp. The steps below are how that branch gets into `master`.


1. **Ariel:** PR `ariel/muse-sync` → `master` (it only touches `Sync/`, `connector/`, `LESSONS.md` and `MuseSyncTests`).
2. **Reut:** merge `master` into `reut/mvp-build` → `xcodegen` → full test run → merge PR #4. (Verified today: no conflicts, 92/92 green on the combined tree.)
3. Both branch from the new `master` for everything below. **Freeze rule:** the hotspot files below only change in their owner's PR.

### Workstreams

| # | Work | Owner | Files (new unless noted) | Done when |
|---|---|---|---|---|
| **E1** | `Pipeline/`: `SortEngine` + layer 1 `RuleScorer` (pure, tested) + contract assembly (topics, items, samples, the ≥5 fitness rule) | Reut + Claude | `ios/Hindsight/Pipeline/` (new) | Produces a contract file that passes the `validate.py` rules as Swift tests |
| E2 | Layer 2 groups (collections, repeat authors) + layer 3 model classifiers (Private Cloud Compute, on-device) behind one interface; quota handling; Hebrew routing | Reut + Claude | `Pipeline/` | Kill mid-sort → resumes; quota reached → finishes on rules |
| **E3** | **On-phone eval screen** (ladybug menu): runs the engine per layer on a bundled fixture, scores it against the fixture labels, and prints Private Cloud Compute availability, `supportedLanguages` (Hebrew?), quota status and timing | Reut + Claude | `Pipeline/SortEvalView.swift` | Run on Reut's iPhone 16 → numbers in this doc |
| E4 | Place details: rule extraction (📍, location tag, mentions, addresses) + model picks venue names; lazy tip/routine wording when a card is shown | Reut + Claude | `Pipeline/`, `LegoScreens/*` | Place recall ≥ fixtures' on Reut's data |
| A1 | `SavedPost` → contract adapter + round-trip test | Reut | `Contract/ContractPost+SavedPost.swift` | Muse sample reply + X page → valid `posts[]` |
| A2 | Seed fix: `SavedPostStore` starts empty, lives under `Hindsight/me/`; seed only for demo/`DEBUG` | Ariel | `Import/SavedPostStore.swift`, `SeedData.swift` (**his files**) | Fresh install has 0 saves |
| A3 | `Dataset.live`, `PipelineClient` (submit, poll, resume, extraction cache, incremental submit) | Reut | `App/`, new `Pipeline/` | Kill mid-job → relaunch resumes; second sync only sends new posts |
| A4 | Router: `RootView` phases, `HindsightApp` hosts it; `DatasetPicker` → `DEBUG` / ladybug only | Reut | `App/RootView.swift`, `HindsightApp.swift` (**shared**) | Every phase resumes after a kill |
| O1 | Onboarding arc: remove Preferences + Done, add Reading step, one progress indicator, Connect → *Import a file* + *Try with sample saves* | Ariel (steps) + Reut (Reading screen) | `Onboarding/*` (**his**), `Onboarding/Steps/ReadingStep.swift` | Walkthrough reads as one conversation (D4) |
| O2 | Theme unification: `OnboardingStyle` → aliases to `Theme` | Reut, reviewed by Ariel | `Onboarding/OnboardingStyle.swift` (**his**, one commit) | No visual diff in onboarding screenshots |
| O3 | Sync sheet in the tabs: reuse Connect rows; new saves → incremental sort | Reut | `App/SyncSheet.swift` | New Muse paste after onboarding shows up in the right tab |
| Q1 | Privacy line ("sorted on your iPhone and Apple's Private Cloud Compute; nothing is stored") + App Store privacy answers + a note for phones without Apple Intelligence | Reut | Connect / Reading step | Wording approved |
| Q2 | End-to-end on device: fresh install, real Muse paste + X, own data → tabs | both | — | Under ~10 min from install to first tab |
| Q3 | Third tester onboards **herself**, with no fixture made for her | Reut | — | The real acceptance test |

### Calendar

| Day | Ariel | Reut |
|---|---|---|
| **Thu 10/1** | Day-0 merge (step 1) · A2 · O1 planning | **E3 on her phone** · E1 · A1 (on `all/merge`) |
| **Fri 10/2** | O1 (his steps) · Muse prompt/paste polish | E2 · A3 · A4 · Reading step UI |
| **Sat 10/3** | O1 wrap-up · X / export import polish | E4 · Reading step wired to the engine · O3 · Q1 · **cut-line check (below)** |
| **Sun 10/4** | Q2 on his phone · server fixes | Q2 on her phone · Q3 with the girlfriend · blocking fixes only |
| **Mon 10/5** | — | Bump build, archive, TestFlight upload, invite (existing Mon checklist) |

### Cut line (Sat night)

- **The engine is badly off on E3's numbers, or Private Cloud Compute misbehaves:** ship Option C for Monday (fixtures + demo, live onboarding behind the ladybug menu). Keep A1–A4, O1, O2 (all valuable regardless). Generate the girlfriend's fixture the old way.
- **Then cut, in order:** O3 Sync sheet (keep re-onboarding via the ladybug menu) → *Import a file* row → incremental submit (re-sort everything on each sync; user state survives because it's keyed by post id) → the previous sprint's cut order.

### Acceptance (the merge is done when)

- [ ] Fresh install, no bundled data used: a real person's Muse paste and/or X connect ends in *their* tabs.
- [ ] No other person's saves appear anywhere unless they picked the demo.
- [ ] Killing the app at any phase resumes there.
- [ ] A second sync adds new posts to the existing tabs; layout, been-there, practice and reminders survive.
- [ ] Onboarding → proposal → confirmation reads as one conversation: one look, one progress indicator, one "you're in".
- [ ] All tests green, including the new adapter, sort-engine and router tests.
- [ ] A phone without Apple Intelligence (or set to Hebrew) still onboards, on rules + groups + questions.

---

## ⚠️ Merge-conflict hotspots with Ariel (this plan)

| File / symbol | Change | Owner | Risk / how to avoid |
|---|---|---|---|
| `ios/Hindsight/HindsightApp.swift` | Hosts `RootView` only; `@AppStorage hasCompletedOnboarding` and `SavedPostStore` creation move into the router | Reut (A4) | **High.** Ariel's file. One commit, announced first. |
| `ios/Hindsight/Onboarding/OnboardingModel.swift` (`Step`), `OnboardingFlow.swift` (`switch model.step`, `onFinish`) | Remove `.preferences` / `.done`; `onFinish` means "start reading" | Ariel (O1) | **High.** Reut doesn't touch them; she only adds `ReadingStep.swift` in a new file. |
| `Onboarding/Steps/PreferencesStep.swift`, `DoneStep.swift`, `OnboardingPreferences.swift` (`TopicSuggester`) | Deleted. `FlowLayout` (in `PreferencesStep.swift`) and `SavedPostPreviewCard` (in `DoneStep.swift`) move to `Design/` first, because the Reading step reuses them. | Ariel (O1) | **High.** Move before deleting. `OnboardingTests` needs updating in the same PR. |
| `ios/Hindsight/Onboarding/OnboardingStyle.swift` | Members become aliases to `Theme` | Reut (O2), Ariel reviews | Medium. One commit, no call-site changes. |
| `ios/Hindsight/Import/SavedPostStore.swift`, `SeedData.swift` | No seed by default; file under the live dataset's folder | Ariel (A2) | Medium. `SavedPostStoreTests` and `SeedDataTests` pass the seed explicitly. |
| `ios/Hindsight/Onboarding/Steps/ConnectStep.swift` | *Import a file*, *Try with sample saves*; rows reused by the Sync sheet (extract a `ConnectRows` view) | Ariel (O1) | Medium. Reut's Sync sheet waits for the extracted view. |
| `ios/Hindsight/Models/SavedPost.swift` | **Nothing.** The adapter lives in `Contract/`. | — | None. |
| `ios/project.yml` | Release stops bundling `ig-saved-posts-seed.md` and non-demo fixtures (D6); later, the share-extension target + App Group | Reut (bundling), Ariel (extension) | Medium. Separate small PRs; rerun `xcodegen`. |
| `ios/Hindsight/App/AppModel.swift` | `Dataset.live`, sort-engine hook | Reut | None for Ariel. |
| `ios/project.yml` → `entitlements` | `com.apple.developer.private-cloud-compute` (new `Hindsight.entitlements`) | Reut (E2) | Low. Ariel's Personal Team builds must drop it (the Personal Team can't have it); add a `device.sh` override. |
| `ios/Hindsight/Onboarding/Steps/ConnectStep.swift` (again) | **Known conflict:** the design revamp (`123c42f`, on `reut/design-revamp`) vs Ariel's `c264da5` | Whoever merges `reut/design-revamp`; Ariel reviews | **High** when the design revamp lands. Keep the new layout + Ariel's TikTok / WhatsApp rows and copy. |

---

## Consequences

**Easier**
- Any tester onboards themselves; no per-tester builds.
- No AI bills and no server to run for sorting. Captions never touch our servers.
- The eval screen makes model quality a number we re-check whenever Apple ships a new model.

**Harder**
- Only Apple Intelligence phones get the model layers. The others rely on rules, groups and questions, so those have to be good on their own.
- Hebrew is unproven (see [AI requirements](#ai-requirements-read-this)).
- The quota is opaque, so a big first import may finish over two days for the model layers. Rules and groups finish immediately.
- No paid tier: crossing 2M downloads forces a migration within 6 months (Option A is the plan for that).

**Revisit later**
- Hebrew support in Apple Intelligence (the AFM 3 report lists Hebrew as an evaluation locale, a hint it's coming).
- Moving more work on-device as models improve (the eval screen tells us when).
- Unifying `SavedPost` and `ContractPost`.
- "Rebuild my app" / "Try to place these" when new topics pile up in Everything else.

## Action items

1. [x] Reut: D1–D3 decided (Option D, zero AI compute cost). Private Cloud Compute entitlement granted.
1. [ ] Reut + Ariel: decide **D10** and D4–D9, and update this ADR's status to *Accepted*
2. [ ] Ariel: open the `ariel/muse-sync` → `master` PR
3. [ ] Reut: merge `master` into `reut/mvp-build`, retest, merge PR #4
4. [ ] Reut: run the E3 eval on her iPhone 16 (iOS 27) and paste the numbers into this doc
5. [ ] Update [mvp-sprint.md](mvp-sprint.md) and [mvp-frontend-build-plan.md](mvp-frontend-build-plan.md) to point here, and add the "anyone can onboard" goal to Monday's bar (or not, per D10)
6. [ ] Update the contract's *Changes needed on Ariel's side*: mark item 1 done when `muse-sync` merges; items 4–6 are now covered on-device by the sort engine (E1–E4), not by Ariel's pipeline
