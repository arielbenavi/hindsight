# Flow spec: Place confirmation ("is this right?")

Status: draft for the MVP sprint ([mvp-sprint.md](../mvp-sprint.md)). Owner: Reut. Companion to the [Map spec](map.md).

## The problem

The Map is only useful if the pins are right. A wrong pin is worse than a missing one: you walk to a place and it's the wrong café. Our guesses will be wrong sometimes, because:

- 42% of Reut's place posts have no written clue to the place (it's only in the video).
- Names are ambiguous ("Little Mint" could be several places; "Semma" needs "NYC" to find the right one).
- Collections mislead ("Aesthetic coffee" is mostly home coffee setups).

**The job:** get the user to trust their map, while asking as few questions as possible. Confirming is a chore, so the flow has to feel quick and a little fun, and it must never block getting into the app.

## Where it appears

| Entry point | When | What it shows |
|---|---|---|
| **After onboarding** | Once the user approves a layout that includes a Map tab | The first batch of uncertain places (see *Triage*) |
| **Needs review** (Map M4) | Any time, from the "5 spots need a look →" pill | Everything left over |
| **Wrong place?** (Map M2) | From a place card | One card for that place, starting on the alternatives |

It's the same card component everywhere.

## Triage: who gets asked what

Every extracted place lands in one of three groups before we show anything:

| Group | Rule (MVP) | What happens |
|---|---|---|
| **Placed** | Strong evidence (📍, @mention or an address) **and** the top MapKit result's name matches the extracted name, inside the area hint | Straight onto the map, no question. `match_status = auto` |
| **Ask** | We have a name and at least one MapKit result, but not both conditions above | A confirmation card |
| **Can't tell** | No place name found (the place is only in the video), or MapKit found nothing | Not asked in onboarding. Goes to Needs review with a "Search it yourself" card |

**Target: a handful of cards (≤ 5–10), hard cap 20.** A first rough estimate for Reut's data is about 100 placed automatically, 40–60 to ask about, about 75 "can't tell". 40–60 is far too many, so the Ask group has to shrink before the cap ever matters:

- Use the @mention's **display name** as the search term ("Cappone's", not "capponesnyc").
- Use the **collection city** as the area hint when the caption has none ("NYC Restaurants" → New York).
- If there's **only one plausible MapKit result** in the area hint, place it automatically.
- Agree on the same place across posts: if two posts point to the same place, that's strong evidence.

If more than 20 are still in Ask, show the 20 with the strongest evidence; the rest go to Needs review.

## Screens

### C1. Intro

One screen, before the first card.

- Big heavy headline (example numbers): **"We found 187 spots in your saves."**
- Subline: "142 are on your map already. Help us check 6 more? Takes 30 seconds."
- Buttons: **Let's go** (primary) · **Later** (secondary; everything goes to Needs review and the user lands in the app).

### C2. Confirmation card

A full-screen card, one place at a time. Two halves stacked vertically (a phone is too narrow for real side-by-side).

**Top half: your saved post**
- Thumbnail (or the fallback from the Map spec), author, platform icon.
- The caption excerpt where we found the name, with the name **highlighted in lime**: "Trying one of NYC's most underrated sandwich shops. **@capponesnyc** in the West Village 🙌🏾"
- Tap the thumbnail → opens the post in Instagram, to check the video.

**Bottom half: our best guess**
- A small Apple map snapshot with the pin (Look Around image if available).
- Name, type emoji, address, neighborhood.
- A **"Check in Google Maps ↗"** link, so the user can verify against the app they trust.

**The question**, between the halves: **"Is this the place?"**

**Actions**
- **Yes** (primary, lime) or swipe right → placed, next card.
- **No** or swipe left → opens C3 (alternatives).
- **Skip** (text button) → goes to Needs review, next card.
- **Undo** appears for 3 seconds after each action.

**Progress:** a thin bar at the top plus "3 of 6". **Hard stop at 20 cards**: after the 20th, the flow goes to C5 and anything left goes to Needs review.

**Tone:** short playful lines between cards, in DailySpend's voice (see *Tone* below).

### C3. Alternatives

Opens when the user says No.

- "Which one is it?" and up to 5 other MapKit results for the same name near the area hint, each with name, address and distance from the area.
- A search field: "Search for the place" (MapKit search, area hint already applied).
- **"It's not a place"** → removes it from the Map. The post goes to whichever lego screen fits, or none.
- **"I don't know"** → Needs review.

### C4. Posts with many places

A "Top 12 cookies" post shouldn't make 12 separate cards.

- **One card for the post** with a checklist: "We found 12 places in this post". Each row has the name, the matched address, and a ✓ that's on by default for good matches.
- Untick a row → it's excluded. Tap a row → C3 alternatives for just that place.
- **Looks good** → confirms all the ticked rows at once.

### C5. Done

- "Your map is ready. 164 spots." with a zoomed-out snapshot of the map full of emoji pins.
- If anything was skipped: "23 are in Needs review whenever you want."
- **Open map** → lands on the Map tab (F1 in the Map spec).

### C6. Search it yourself (Needs review only)

For "can't tell" posts. The top half is the same as C2. The bottom half is just a search field and **"Not a place"**. The caption and a "Watch on Instagram" button help the user remember what the place was.

## Flows

**CF1. Onboarding pass.** Layout approved → C1 → Let's go → cards (C2 / C4) → C5 → Map tab. Target: **under a minute** for Reut's data.

**CF2. Wrong guess.** C2 → No → C3 → tap the right result → placed, next card.

**CF3. Nothing matches.** C2 → No → C3 → type in search → pick a result → placed. Or "It's not a place".

**CF4. Later.** C1 → Later → Map tab, with the "spots need a look" pill. Nothing is lost.

**CF5. From a pin.** Map → place card → Wrong place? → C3 for that place → pick → the pin moves.

## States

| State | What the user sees |
|---|---|
| **Still matching** (MapKit searches still running) | C1 shows a count going up: "Finding your spots… 94". Cards start as soon as the first uncertain ones are ready. |
| **Offline** (MapKit search needs a network) | "We'll finish finding your spots when you're back online." → the app, with the pill. |
| **Nothing to ask** | Skip C1–C4 and go straight to C5. |
| **User quits halfway** | Answers so far are saved. The rest go to Needs review. |

## Data needs

Adds to the Map spec's data needs. Everything else (thumbnail, caption, matched fields) is already there.

| Field | From | Why |
|---|---|---|
| `places[].evidence` | Extraction | The exact bit of caption the name came from ("@capponesnyc in the West Village"), so the card can highlight it. Seeing the evidence is what makes a confirmation quick. |
| `places[].evidence_kind` | Extraction | pin_emoji / mention / address / plain_text / collection_only. Triage uses it. |
| `candidates[]` (up to 5) | Matching | Alternatives for C3 without searching again. |
| `rejected_ids[]` | User | Places the user said No to, so re-matching never suggests them again. |
| `match_status` | User / triage | Adds `skipped` and `not_a_place` to the Map spec's values. |
| `confirmed_at` | User | So Needs review only shows what's still open. |

## Done when

- [ ] With Reut's export, the onboarding pass shows a handful of cards (target ≤ 10) and never more than 20.
- [ ] Strong-evidence exact matches never produce a card.
- [ ] "Can't tell" posts never appear in the onboarding pass; they're in Needs review.
- [ ] A Top-N post shows one checklist card, not N cards.
- [ ] Yes / No / Skip / Undo and swipes all work; answers survive quitting the app.
- [ ] "Check in Google Maps" opens the guessed place in Google Maps.
- [ ] "It's not a place" removes the pin and the post from the Map.
- [ ] Later / quitting never loses data and never blocks entering the app.

## Tone

Playful one-liners in DailySpend's voice, shown briefly between cards or on C5. Never more than one line, never blocking. Examples:

- After 3 Yeses in a row: "You have taste."
- After a No: "Good catch."
- After "It's not a place": "Fair. That's a coffee machine."
- On C5: "Map's ready. Go eat something."
- When nothing needs asking: "Nailed all of them. Didn't even need you."

## ⚠️ Merge-conflict hotspots with Ariel

| File | What we'd change | Risk |
|---|---|---|
| `ios/Hindsight/HindsightApp.swift` | Show the confirmation flow after the layout is approved, before the tab shell. | **High.** Same file as the layout proposal's routing change; do both in one commit. |

The flow itself lives in new files we own: `ios/Hindsight/LegoScreens/Map/Confirmation/`.

## Later

- **LLM confidence scoring.** A lightweight LLM goes through every matched place and scores how confident we are that the pin is right (caption evidence vs. the MapKit result's name, address, type and area). The score replaces the rule-based triage above and decides what's placed, asked or parked. Not in the MVP.
- **Browse automatic matches:** a view listing what we placed without asking, for spot-checking.

## Decided (was open)

1. **Swipes plus buttons.**
2. **Trust automatic matches.** "Wrong place?" catches mistakes. A "browse what we placed automatically" view can come later; not needed for the MVP.
3. **Hard stop at 20 cards**, with a target of a handful. The triage improvements above are what keep it small.
4. **Playful tone** between cards (see *Tone*).
