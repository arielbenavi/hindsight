# Lego screen spec: Fitness

Status: draft for the MVP sprint ([mvp-sprint.md](../mvp-sprint.md)). Owner: Reut. Built on the practice loop from the [Learn spec](learn.md); read that first. This spec only covers what's different.

## The problem

People save stretches and exercises for a specific reason: a stiff upper back, lower back pain from sitting, tight hips. The save is aspirational ("I'll do this every morning"), and then it never happens. When the back hurts again, the reel is buried and forgotten.

**Fitness's job:**
1. **Nudge me to actually do my saved stretches, regularly.** Not a workout tracker: no timers, no sets logging, no live sessions. Occasional reminders and a gentle weekly rhythm.
2. **"My lower back hurts: what did I save for that?"** Find saves by body area or problem, in plain words.

Unlike a tip in Learn, which you try once and then review, a stretch is meant to be **repeated**. That's the main difference from Learn's loop.

## What the seed data tells us

Keyword matches are noisy ("hip" matches hip-hop, "core" matches everything), so these are hand-checked counts.

| Finding | Example | What it means for us |
|---|---|---|
| **Small but real:** about 10 true fitness saves in Ariel's 1,216, 2 in Reut's | Ariel: back pain, posture, thoracic spine, low back, abs. Reut: "Your upper back will thank you for this" | Fitness is a small tab for most people. It has to be useful with 5–15 saves. Reut's 2 are under the 5-save threshold, so they go to Learn (see *Decided*). |
| **Almost everything is about a body area or a pain** | "Upper back pain / knot between shoulder blades? Try this movement…", "BEGINNER LOW BACK EXERCISES" | Body area + problem is the right way to organize and search, not muscle groups or workout types. |
| **One post, several exercises** | "Try these 5 exercises to improve shoulder mobility" | The practice unit is the **routine** (the post); its exercises are listed inside for reference and search. |
| **Many are promos for a course** | "NEW MOBILITY PROGRAM OUT NOW (link in bio)" | The caption often names the problem but not the moves. The moves are in the video. |
| **Fitness-adjacent isn't Fitness** | Gym memes ("Tag bro #GymMeme"); protein pancake recipes | Memes → Everything else. Food/nutrition → Learn (cooking), not Fitness, in the MVP. |

## How Fitness uses the practice loop

Same shared loop (`ios/Hindsight/Practice/`), with these differences:

| | Learn | Fitness |
|---|---|---|
| Unit | a tip | a **routine** (one post, 1+ exercises) |
| Main action | **Tried it** | **Did it** |
| After the action | spaced review at 3 / 10 / 30 days ("Still got it?") | **comes back into rotation**, weighted up; repeating is the point |
| Thin posts (moves only in the video) | library only, never in Today's 1 | **allowed in Today's 1** as "Follow along with this reel (~1 min)". Following the video *is* the practice. |
| Reminders | "When?" one-offs | "When?" one-offs **plus Regulars**: recurring reminders the user sets per routine |
| Weekly ring | tries per week (default 3) | sessions per week (default 3), **its own ring** |
| Extra browse | topic sections | **body areas** + problem search |

## Screens

### F0. First-time setup (first open of the Fitness tab)

Same shape as Learn's setup (L0), three quick steps, skippable:

1. **"What needs some love?"** Body-area chips, multi-select, showing only areas the user has saves for, with counts: Lower back · 4, Upper back · 3, Shoulders · 2, Hips · 1… The picked areas weight Today's 1.
2. **"How many sessions a week?"** 1 · **3** (default) · 5 · 7. "A session is one routine. Two minutes counts."
3. **"When should we nudge you?"** Morning (default for Fitness) · Lunch · Evening · Off.

The ring starts with the setup segment filled, as in Learn.

### F1. Fitness home (tab root)

1. **Header:** "Fitness" and the Everything else button top right.
2. **Weekly ring:** "1 of 3 sessions this week".
3. **Monday / fresh-start card**, as in Learn.
4. **Today's 1:** one routine card (F2). After it's handled: "Done for today." + one-liner ("Your spine sends its regards.") + "One more?".
5. **Regulars:** routines the user pinned, each with its schedule ("Upper back release · Mon Wed Fri 8:00"). Tap → F4. Empty state: "Pin a routine you want to do regularly."
6. **Search field:** plain-language problem search (F6).
7. **Body areas:** a grid of area tiles, each with an SF Symbol and a count ("Lower back · 4"). **Only areas that have at least one saved routine**; never show empty tiles for areas with nothing saved. Tap → F3.

### F2. Routine card (Today's 1)

The practice card from Learn, with Fitness content:

- Thumbnail (fallback: body-area symbol on a dark tile), title ("Upper back release"), area chips, "~3 min".
- **Exercise list** when the caption has one: "90/90 hip switch · 10 each side", "Thoracic rotation · 30s hold". Max 5 lines.
- **Do prompt** with the "Suggested" label: "Do the 2 moves, 30 seconds each side."
  - Thin variant: "Follow along with this reel (~1 min)", and **Open reel ↗** becomes the big secondary button.
- Buttons: **Did it** (primary) · **Not today** ("When?" chips) · **Not for me**.
- A one-line safety note on pain-related routines: "Gentle does it. Stop if it hurts."

### F3. Body area page

- "Lower back", with "Done 6 times this month".
- Filter chips by goal: **All** · **Pain relief** · **Mobility** · **Posture** · **Strength**. Only goals present.
- Routine cards, most done first, then newest saved.

### F4. Routine detail (sheet)

- Big thumbnail → opens the reel in Instagram (⚠️ in-app playback is the known gap; for Fitness it matters most, since the moves are in the video).
- Title, author, areas, goal, equipment ("No equipment", "Mat", "Foam roller"), ~minutes.
- Exercises (name, reps / hold / sides), only from the caption.
- History: "Done 4 times · last on Tuesday".
- Actions: **Did it** · **Make it a regular** (→ F5) · **Remind me…** · **Move to…** · **Not for me**.
- The original caption, collapsed. The safety note, where relevant.

### F5. Regular schedule (sheet)

- "Do *Upper back release* on": weekday chips (M T W T F S S) + a time picker.
- Presets: **Every morning** · **Weekdays** · **3× a week** (Mon Wed Fri).
- Saving pins it to Regulars and schedules repeating local notifications: "Upper back release, 3 min. Your back will thank you."
- **Remove from regulars** at the bottom.

### F6. Problem search

Typed in plain words, matched to body areas and goals through a fixed synonym table, plus normal text search:

- "lower back pain", "back hurts", "sciatica" → Lower back + Pain relief
- "stiff neck", "tech neck" → Neck
- "desk posture", "hunched" → Upper back + Posture
- "tight hips", "hip flexors" → Hips + Mobility
- …

Results: routine cards, best match first. Empty: "Nothing saved for that yet." + **Search Everything else**.

### Progress

Learn's progress sheet (L5), with sessions instead of tries and per-area counts: "Lower back · 6 sessions". Identity line: "6 sessions this month. You're someone who looks after their back."

## Notifications across Learn and Fitness

The shared `ReminderPolicy` now covers both tabs:

- **App-chosen nudges** (the daily practice notification): **at most one per day across the whole app**, alternating between Learn and Fitness when both exist. Back-off and stop rules as in Learn, per tab.
- **User-set reminders** ("When?" one-offs and Regular schedules) always fire; the user asked for them. On a day a Regular fires, the app-chosen Fitness nudge is skipped.
- Tapping any Fitness notification opens that routine's card.

## Picking Today's 1 (Fitness)

Same pure picker as Learn, with Fitness rules:

1. **Due first:** a "When?" reminder for today, then a Regular scheduled for today that isn't done yet.
2. **Otherwise weighted random** over routines that aren't archived (thin ones included):
   - base weight 1;
   - × 2 if its area was picked in setup;
   - × 1.5 if it has been done before (repetition is the goal), capped so one routine doesn't take over;
   - × 0.3 if it was shown in the last 3 days (shorter than Learn's 14: stretches repeat).
3. Rotate areas: not the same area two days in a row when another is available.

## States

| State | What the user sees |
|---|---|
| **Very few routines (5–9)** | Everything works; no body-area grid if there's only one area (show the routines as a list instead). |
| **Setup skipped** | Today's 1 from all routines; goal 3; reminders off, with a "Get a nudge?" row. |
| **Notifications denied** | Regulars still show on the home screen on their days ("Today: Upper back release"), without a push. |
| **All routines archived** | "Nothing left to do here. Save a stretch you like and it'll show up." |
| **Away 7+ days** | "Fresh start" card, no missed-days count. |

## Data needs

### From the data pull (per saved post)

Same as Learn: `url`, `platform`, `author`, **full `caption`** (exercise lists and reps are often past 160 characters), `hashtags` (#backpain, #mobility are strong area signals when the caption is a promo), `saved_at`, `thumbnail_url` ⭐, and later `on_screen_text` + `transcript` (most moves are only in the video; this is what makes Fitness really good).

### From extraction (LLM, per post)

| Field | Why |
|---|---|
| `lego_screen` = fitness | Whether it's in Fitness at all. Memes → none, food → learn. |
| `title` (≤ 40 characters, e.g. "Upper back release") | Cards, notifications, Regulars. |
| `body_areas[]`: neck, shoulders, upper_back, lower_back, hips, knees, ankles, core, full_body | The area grid, F3, search, setup chips. |
| `goal`: pain_relief, mobility, posture, strength, recovery | F3 filters, search. |
| `exercises[]`: `name`, `reps?`, `sets?`, `hold_seconds?`, `each_side` | The exercise list. **Only from the caption, never invented.** |
| `est_minutes` | "~3 min" on cards. |
| `equipment[]`: none, mat, band, foam_roller, dumbbell, other | Detail sheet. |
| `do_prompt` (≤ 100 characters) | The card's prompt. Empty when `is_thin` (the app uses the follow-along prompt). |
| `is_thin` | The moves are only in the video. |
| `is_pain_related` | Shows the safety note. |

### User state (on device)

The shared `PracticeState` (status, `doneAt[]`, `lastShownAt`, `remindAt`), plus `RegularSchedule` (routine, weekdays, time) and the Fitness settings (weekly goal, reminder slot, picked areas).

## Model sketch

```swift
struct Routine: Identifiable, Codable {      // extracted, read-only in the app
    let id: SavedPost.ID
    var title: String
    var bodyAreas: [BodyArea]
    var goal: FitnessGoal
    var exercises: [Exercise]
    var estMinutes: Int?
    var equipment: [Equipment]
    var doPrompt: String?
    var isThin: Bool
    var isPainRelated: Bool
}

struct Exercise: Codable {
    var name: String
    var reps: Int?
    var sets: Int?
    var holdSeconds: Int?
    var eachSide: Bool
}

struct RegularSchedule: Codable {            // user state
    let routineID: Routine.ID
    var weekdays: Set<Int>                   // 1 = Sunday … 7 = Saturday, like Calendar
    var time: DateComponents                 // hour + minute
}
```

## Build notes for the coding agent

- **Build on `ios/Hindsight/Practice/` from Learn.** Add only what's generic and missing:
  - repeat-friendly scheduling in the picker (a per-screen config: repeat penalty window, "done before" weight, thin allowed);
  - `RegularSchedule` + repeating notifications in `ReminderScheduler`;
  - the cross-app nudge cap in `ReminderPolicy` (one app-chosen nudge per day, alternating tabs).
  Learn's tests must still pass unchanged.
- **Fitness-specific**, in `ios/Hindsight/LegoScreens/Fitness/`: `Routine.swift` (with `BodyArea`, `FitnessGoal`, `Equipment`, `Exercise`), `FitnessView.swift` (F1), `FitnessSetupView.swift` (F0), `RoutineCard.swift` (F2), `BodyAreaView.swift` (F3), `RoutineDetailSheet.swift` (F4), `RegularScheduleSheet.swift` (F5), `ProblemSearch.swift` (the synonym table + matching; pure).
- **Body-area icons:** SF Symbols only (the simulator can't render emoji; see `docs/LESSONS.md`).
- **Tests** (`ios/HindsightTests/FitnessTests.swift`):
  - problem search: "back hurts" → Lower back; "tech neck" → Neck; unknown words fall back to text search.
  - picker: thin routines allowed; done routines weighted up but capped; 3-day repeat window; area rotation; a Regular due today comes first.
  - reminders: a Mon/Wed/Fri 8:00 Regular creates the right repeating notifications; at most one app-chosen nudge per day across Learn + Fitness; no Fitness nudge on a day a Regular fires.
- **Previews** with Ariel's real fitness saves (at least one thin promo reel, one multi-exercise post, one pain-related).

## ⚠️ Merge-conflict hotspots with Ariel

| File | What we'd change | Risk |
|---|---|---|
| `ios/Hindsight/Models/SavedPost.swift` | Same new fields as Map and Learn (`hashtags`, `thumbnailURL`, `savedAt`). | **High.** Already covered: one shared commit. |
| `ios/Hindsight/Onboarding/OnboardingPreferences.swift` | Ariel's `resurface` setting is replaced by Learn's and Fitness's reminders. | Medium. Same conversation as Learn. |
| `ios/Hindsight/Onboarding/OnboardingPreferences.swift` → `TopicSuggester` | Its `"fitness"` keywords (`gym`, `workout`, …) disagree with what counts as Fitness here (mobility, pain, posture; memes out). | Low. Clustering is Ariel's; send him the `body_areas` / `goal` definitions instead of editing his keywords. |

## Done when

- [ ] With Ariel's seed: a Fitness tab with his ~10 real fitness saves; gym memes are in Everything else and the protein pancakes are in Learn.
- [ ] Back-pain posts are under Lower back; "back hurts" and "desk posture" searches find the right routines.
- [ ] A multi-exercise post shows its exercise list; nothing is listed that isn't in the caption.
- [ ] Thin promo reels appear in Today's 1 with the follow-along prompt.
- [ ] Did it fills the Fitness ring (separate from Learn's) and the routine comes back into rotation within days.
- [ ] Making a routine a Regular (Mon/Wed/Fri 8:00) schedules repeating notifications that open its card.
- [ ] Across Learn + Fitness, the app never sends more than one app-chosen nudge a day.
- [ ] Pain-related routines show the safety note.

## Decided (was open)

1. **Body areas are a grid in the MVP**, populated only with areas that have saves. A tappable body map is for later.
2. **Separate rings** for Learn and Fitness. Later, home-screen / lock-screen **widgets** can show a ring, and the user picks which tab it tracks.
3. **Under 5 fitness saves:** no Fitness tab; those saves go to Learn. Offering Fitness as an optional extra tab is for later.
4. **Food and nutrition saves** go to Learn for now. A **Recipes** lego screen is planned for later.
