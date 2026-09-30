# MVP frontend build plan (Reut's side)

> **Scope: frontend only.** This is Reut's (+ Claude's) working checklist for the iOS screens: lego screens, layout proposal, confirmation flow, shared theme. **Ariel / Ariel's agents:** this is not your task list. Nothing here asks you to change your files; the *Merge-conflict hotspots* table below lists the only places we touch shared code. What we need from your side is in [data-contract.md](data-contract.md) → *Changes needed on Ariel's side*.

How the [MVP sprint](mvp-sprint.md) gets built, step by step. The specs in [`specs/`](specs) say *what*; this says *in what order and where the code goes*. Tick boxes as work lands.

- **Owner:** Reut + Claude. **Branch:** `reut/mvp-build`, one PR into `master` at the end.
- **Target:** all steps in one push, then review, then TestFlight.

## Architecture in one screen

```
data/fixtures/{reut,ariel,<girlfriend>}.hindsight.json  ← contract v1 (generated this week; Ariel's pipeline replaces it)
        │  bundled via project.yml
        ▼
Contract/   HindsightFile (Codable, snake_case) → HindsightData (lookup by post/topic, Everything else)
        │
Layout/     LayoutRules (pure: topics → proposal) · LayoutConfig · LayoutEdit (+ typed-edit parser) · proposal chat UI
        │  approved LayoutConfig
        ▼
App/        RootView: onboarding done? → proposal → confirmation (if Map) → MainTabView (tabs from LayoutConfig)
        │
LegoScreens/Map/            PlaceMatcher (MapKit, throttled, cached) · Triage · Map UI · Confirmation/
LegoScreens/Learn/          Tip · Learn UI
LegoScreens/Fitness/        Routine · ProblemSearch · Fitness UI
Practice/                   shared loop: PracticeStore · TodayPicker · WeeklyProgress · ReminderPolicy/Scheduler · card/ring views
EverythingElse/             the sheet + header button
Design/Theme.swift          DailySpend Theme + OnboardingStyle merged (OnboardingStyle itself untouched)
```

**Principles**
- The screens read the **contract models directly**, not `SavedPost`. That keeps us out of `SavedPost.swift` (the top hotspot) for the whole MVP. `SavedPost` → contract conversion is Ariel's pipeline.
- **Pure logic, tested:** layout rules, edits, triage, pickers, reminder policy, search, ring math. Dates and randomness are injected.
- **User state is persisted separately** from the fixture (JSON in Application Support), so regenerating a fixture never wipes it.
- `@Observable` stores, Swift 6 strict concurrency, iOS 26, SF Symbols in UI (emoji only as content; see LESSONS).
- **One Ariel-file touch:** `HindsightApp.swift` swaps `ContentView()` for our `RootView()`. The proposal runs after his current onboarding until his chat lands; then his chat calls `LayoutProposalView(data:onApprove:)`, one line he owns.

## ⚠️ Merge-conflict hotspots with Ariel (this plan)

| File | What we change | When | Risk / mitigation |
|---|---|---|---|
| `ios/Hindsight/HindsightApp.swift` | `ContentView()` → `RootView()` (one line). All routing lives in our `App/RootView.swift`. | Step 2 | **High** file, tiny change. Tell Ariel first; own commit. |
| `ios/project.yml` | Bundle `data/fixtures/*.json`; `NSLocationWhenInUseUsageDescription`; later a `ci_scripts` note for Xcode Cloud. | Steps 2–3 | Medium. Separate small commits; rerun `xcodegen`. |
| `ios/Hindsight/Onboarding/*` (`OnboardingModel`, `OnboardingFlow`, `PreferencesStep`, `OnboardingPreferences`) | **Nothing.** PreferencesStep stays until Ariel's chat replaces it. | — | None. |
| `ios/Hindsight/Models/SavedPost.swift` | **Nothing** in the MVP (see principles). | — | None. |
| `ios/Hindsight/Onboarding/OnboardingStyle.swift` | Read only; Theme copies its values. | — | None. |

## Steps

### 0. Setup
- [x] Branch `reut/mvp-build` off `master`; `xcodegen`; build + run the 26 existing tests green on iPhone 17 sim
- [ ] Tell Ariel about the one-line `HindsightApp.swift` change and the `project.yml` additions

### 1. Data: fixtures — everything else depends on this
- [x] `data/fixtures/tools/build_posts.py`: deterministic `posts[]` for both seeds (Reut's export: fix Latin-1 mojibake, collections from `saved_collections.json`, hashtags, @mentions, `saved_at`; Ariel's markdown: parse entries). Note: Ariel's seed captions are cut at 160 chars, so his extraction is weaker.
- [x] Extraction by Claude subagents in batches (~100 posts each): per post `lego_screen`, topic label, and `places` / `tip` / `routine` per the contract; never invent content
- [x] Consolidation pass: stable `topics[]` (each post in exactly one), samples, `source_collections`, ≤ 2 `ambiguity` questions ("Aesthetic coffee" for Reut); apply the < 5 fitness → learn rule
- [x] `data/fixtures/tools/validate.py`: contract rules (snake_case, no `""`, ids exist, every non-`none` post has exactly one item, lengths) → commit `data/fixtures/reut.hindsight.json`, `ariel.hindsight.json`
- [ ] Third tester: generate her fixture the same way once Reut has her Instagram export
- [x] Sanity check against the specs' "Done when" data points (Salt Hank's, Top-12 cookies, gym memes → none, protein pancakes → learn, ~10 Ariel fitness saves)

### 2. Foundations in the app
- [x] `Design/Theme.swift`: DailySpend theme + OnboardingStyle merged (colors, heavy rounded type, pill buttons, cards, lime accent)
- [x] `Contract/`: Codable types for the whole file + `HindsightData` index; decoding tests on both fixtures
- [x] Fixture selection: bundled fixtures, chosen by a DEBUG/settings switch (Reut / Ariel / third tester), remembered
- [x] `Layout/LayoutConfig.swift`, persisted per dataset by `App/AppModel`
- [x] `App/RootView.swift` + `MainTabView` built only from `LayoutConfig`; placeholder tabs; Everything else header button + sheet
- [x] The one-line `HindsightApp.swift` commit; `project.yml` fixture bundling

### 3. Map
- [x] `Place` model + `PlaceStore` (matching results + user state: visit status, hidden, filters), persisted
- [x] `PlaceMatcher`: MapKit `MKLocalSearch` (name + area hint), throttled queue, on-disk cache, Apple/Google Maps URLs, candidates (≤ 5), de-dupe by `map_item_id` across posts
- [x] `Triage` (pure): placed / ask / can't tell, per confirm.md incl. the shrink rules and the 20 cap; tests
- [x] M1 map: emoji pins by type, ✓ badge, clustering, locate-me, opens on you / nearest city
- [x] M1a bottom sheet (peek / half / full) with distance-sorted list following the visible region
- [x] M2 place card: reason, post thumbnail/fallback (Look Around → snapshot), Directions / Google Maps / Been there, Wrong place?, Hide, Apple's place sheet
- [x] Filters (type, status, collection) remembered; M3 city picker
- [x] States: location ask / denied, nothing nearby, no places, matching in progress, offline

### 4. Confirmation + proposal
- [x] Confirmation: C1 intro, C2 swipe card (evidence highlighted in lime), C3 alternatives + search, C4 multi-place checklist, C5 done, C6 search it yourself; undo; tone one-liners; answers persisted; M4 Needs review uses the same card
- [x] `LayoutRules` (pure): thresholds, tab order, questions, states (one tab / nothing fits / < 20 saves); tests for Reut's and Ariel's expected proposals
- [x] Proposal chat UI: B1 topic card, B2 questions with thumbnails, B3 app preview card, B4 edit mode (drag reorder, rename, remove, change emoji, + Add), B5 approve; resume mid-chat
- [x] Typed edits without an LLM: small rule-based parser (remove / rename / reorder / leave out); falls back to chips when unsure
- [x] Routing end to end: onboarding → proposal → confirmation → Map tab

### 5. Practice loop + Learn
- [x] `Practice/`: `PracticeState`, `PracticeStore`, `TodayPicker` (config per screen), `WeeklyProgress`, spaced review 3/10/30, `ReminderPolicy` (incl. cross-tab cap), `ReminderScheduler` (owns the notification delegate); `PracticeTests`
- [x] Views: `PracticeCard`, `WeeklyRing`, `WhenChips`, swipe deck (shared with confirmation)
- [x] Learn: L0 setup, L1 home, L2 card (Still got it? variant, CTA-keyword variant), L3 topic, L4 detail, L5 progress, L6 search (`TipSearch`, Hebrew/accents); `LearnTests`

### 6. Fitness
- [x] `Routine` + enums, `ProblemSearch` synonym table; `FitnessTests`
- [x] F0 setup, F1 home (ring, Today's 1, Regulars, search, area grid), F2 routine card (thin follow-along, safety note), F3 area page, F4 detail, F5 Regular schedule + repeating notifications, progress
- [x] Picker config for Fitness (thin allowed, done ×1.5 capped, 3-day window, area rotation)

### 7. Polish + ship
- [ ] Look-and-feel pass; every view has previews with seed data
- [ ] Full test run; walk every spec's "Done when" list and tick what passes
- [ ] Real-device pass on Reut's phone (emoji pins, location, notifications), Reut's and Ariel's data
- [ ] Bump build number, archive; **Reut uploads to TestFlight** (her Individual account signs); invite Ariel + girlfriend
- [ ] PR into `master`; send Ariel the contract + needed pipeline changes

## Cut order if we slip (from the sprint doc)
1. Fitness practice loop (keep browse + search) · 2. L5 progress + back-off rules · 3. Thumbnails · 4. Proposal editing (approve only) · 5. Map list view
