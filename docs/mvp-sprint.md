# MVP sprint: Wed 9/30 → Mon 10/5

Reut (frontend/UX) + Claude. Ariel's data-pull and onboarding work runs in parallel and isn't tracked here.

**Monday goal:** a TestFlight build that Reut, Ariel and Reut's girlfriend can install. It goes: seed or imported saves → proposed layout → approve → a working **Map** tab (with "is this right?" confirmation cards), a **Fitness** tab and an **Education** tab.

**How we avoid waiting on Ariel:** each lego screen spec defines the data it needs (the data contract). A Claude agent then reads both seed files once and writes that data into a committed fixture file, so the app runs on real saves. When Ariel's pipeline outputs the same shape, it replaces the fixture.

## Decisions

- **Lego screens in the MVP:** Map, Fitness, Education. The tab bar is one tab per lego screen, never per category.
- **Map:** any place, built for deciding in the moment (what's near me now). One Map tab; cities and collections are filters.
- **Confirmation flow:** after onboarding, cards show the saved post next to the best-guess match: "is this right?"
- **Fitness:** reminders to do saved stretches, plus search by problem area or muscle group. Not live workout tracking.
- **Place matching:** Apple Maps (MapKit search) for now. Every place also gets an "Open in Google Maps" link. A full Google Maps option comes later.
- **Video:** thumbnail + tap-through to the original app. ⚠️ **Known gap:** we want in-app playback (Instagram/TikTok/X embeds), which needs API access. Tracked for after the MVP.
- **Users:** Reut, Ariel, Reut's girlfriend → then a friends beta on TestFlight. Everyone has their own data; no sharing.
- **LLM:** for this sprint, sorting and extraction on the seed data is done once by a Claude agent, with the output committed as a fixture. The app's real LLM (Apple's on-device models, cheap local models on a VPS, a hosted provider) gets evaluated after the MVP.
- **Design:** DailySpend's look ([reyr13/daily-spend](https://github.com/reyr13/daily-spend), `Shared/Design/Theme.swift`), brrr.now, and Ariel's onboarding (`ios/Hindsight/Onboarding/OnboardingStyle.swift`). Both already share the same language: near-black background, heavy rounded type, a lime accent, pill buttons, rounded dark cards. We merge them into one theme file instead of keeping two.

## Wed 9/30: Specs

- [x] Map lego screen spec: screens, flows, states, data needs ([specs/map.md](specs/map.md))
- [x] Confirmation flow spec ("is this right?" cards) ([specs/confirm.md](specs/confirm.md))
- [ ] Fitness lego screen spec: search by problem area or muscle group, reminders
- [ ] Education lego screen spec
- [ ] Layout proposal screen spec (onboarding handoff: "here's your app", approve or edit)
- [ ] Data contract: the fields each lego screen needs and why → becomes the list for Ariel
- [x] Design references reviewed (DailySpend theme + Ariel's onboarding style)

## Thu 10/1: Foundations

- [ ] Parser for Reut's Instagram export (collections, full captions, encoding fix) → `SavedPost` with a new `collection` field
- [ ] Data models for extracted items: `Place`, `Exercise`, `Tip`, plus `LayoutConfig` (which lego screens, in what order)
- [ ] Extraction agent: goes over both seed files → assigns each post to a lego screen and pulls out the contract fields → commits the fixture JSON
- [ ] Place matching: place name + city → MapKit search → coordinates, address, Apple Maps and Google Maps links; cached
- [ ] App shell: tab bar built from `LayoutConfig`, not hardcoded
- [ ] Shared theme: merge `OnboardingStyle` and the DailySpend theme into one design system

## Fri 10/2: Map lego screen

- [ ] Map opens centered on you, pins for nearby saved places, locate-me button
- [ ] Filters: type (food / café / bar / other), collection or city, want-to-go / been there
- [ ] Place card: name, type, neighborhood, thumbnail → Instagram, Open in Apple Maps / Google Maps, been-there toggle
- [ ] List view of the same places, sorted by distance
- [ ] Posts with several places: one pin per place, all linking to the same post
- [ ] Empty, loading and location-permission-denied states

## Sat 10/3: Confirmation flow + onboarding handoff + Education

- [ ] Confirmation cards: saved post on one side, best-guess match on the other. Yes, no, or pick another result. "Couldn't place" goes to a review list
- [ ] Layout proposal screen: read topics → suggest lego screens → approve, rename, reorder, remove
- [ ] Hook into Ariel's onboarding: onboarding done → layout proposal → confirmation cards → app
- [ ] Education lego screen: grouped by topic, search, tip cards linking to the post

## Sun 10/4: Fitness + polish

- [ ] Fitness: browse by body area or problem, exercise cards (name, target area, form tips, link to the reel)
- [ ] Reminders: pick exercises → local notification schedule → tapping the notification opens those exercises
- [ ] Thumbnails, if we find a way to fetch them (otherwise a styled placeholder)
- [ ] Look-and-feel pass across all tabs
- [ ] Unit tests: export parser, contract decoding, layout config

## Mon 10/5: Ship

- [ ] Walk through it on Reut's phone with Reut's data and Ariel's data
- [ ] Fix blocking bugs only
- [ ] Archive, upload to TestFlight, invite Ariel and Reut's girlfriend
- [ ] Send Ariel the data contract and the changes his Muse pull needs

## Cut order if we slip

1. Fitness reminders (keep browse and search)
2. Thumbnails (styled placeholders)
3. Editing on the layout proposal screen (approve only)
4. Map list view

## After the MVP

- In-app video playback via platform embeds / API access
- Evaluating the app's LLM: Apple's on-device SDKs, cheap local models on a VPS, hosted providers
- Google Maps as a full place-matching option
- Sharing lists (e.g. with a partner)
- More lego screens (e.g. guitar or other instructional content)
