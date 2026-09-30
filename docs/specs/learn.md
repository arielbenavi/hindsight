# Lego screen spec: Learn

Status: draft for the MVP sprint ([mvp-sprint.md](../mvp-sprint.md)), v2 (rebuilt around a practice loop). Owner: Reut. "Learn" is the working name for the Education lego screen.

## The problem

Saving a tip is **aspirational**. "I'll learn this guitar trick." "I'll try this Claude Code plugin." "I'll use this mixing technique." Then two things go wrong:

1. **We forget it exists, and where.** Instagram's saved tab is a wall of thumbnails with no search, and the caption rarely says what the tip was.
2. **Even when we find it, nothing makes us practice it.** The save was a promise to our future self, and nothing holds us to it.

Finding things again is the easy half. **Learn's real job is to turn saved intentions into small, repeated practice**: nudge the user to actually try one thing, make that feel good, and build a routine the app keeps reinforcing.

Reference ("what was that tip about X?") still matters, and search stays one tap away, but it's secondary.

The same holds for Fitness (saved stretches are just as aspirational). The practice loop below is built so Fitness can reuse it.

## What the research says

We looked at how Duolingo, Brilliant, Readwise, Finch and habit research handle this (full report summarized in *Sources*). The mechanisms that fit saved reels best, and how Learn uses them:

| Mechanism | The psychology | How Learn uses it |
|---|---|---|
| **Minimum viable action** | Starting has to be nearly free. Doing beats rereading (retrieval practice: 61% vs 40% recall after a week). | Every tip gets a one-line **"Try this (2 min)"** prompt. The daily action is one small try, not "learn guitar". |
| **Curated resurfacing** (Readwise Daily Review) | A small daily batch with a finish line turns a guilty backlog into something doable. | **Today's 1**: one save a day, never the whole backlog. Then "Done for today". |
| **Implementation intentions** ("when X, I'll do Y") | Among the best-evidenced ways to close the intention-behavior gap (d = 0.65 across 94 tests). | **Not today** asks "When?" (Tonight · Tomorrow · Weekend) and schedules a reminder about that exact save. |
| **Forgiving progress** (Duolingo streak freezes, Weekend Amulet) | Seeing a broken streak makes people quit more than the miss warrants; missing a day doesn't break habit formation. | A **weekly ring** ("2 of 3 tries this week") that resets each Monday. No daily streak, never a "broken" state. |
| **Endowed progress + first-week commitment** | A card with 2 of 10 stamps pre-filled gets completed far more than a blank 8-stamp card (34% vs 19%). | The first week's ring has a pre-filled segment for setting up ("Picked your saves ✓"). |
| **Specific, varied, polite notifications** (Duolingo's notification research) | The same message repeated gets ignored; backing off beats nagging. | Max 1 a day, always about a specific save, rotating wording, backs off when ignored, stops politely after a quiet week. |
| **Spaced review** (Readwise Mastery, Anki) | Coming back to something at growing intervals makes it stick. | A tried tip comes back at 3, 10 and 30 days as **"Still got it?"** |
| **Fresh starts** | Aspirational behavior spikes after landmarks (a new week, month). | A Monday card: "New week. Here's today's pick." After a lapse: "Fresh start", never "You missed 12 days". |

### Design rules (the pitfalls)

- **No XP, points, leagues or badges.** Expected rewards undermine intrinsic motivation, and leagues need social features we don't have. Informative feedback ("You've tried 5 guitar tips") is fine.
- **Never show a broken streak or a guilt message.** Tone is warm and playful (DailySpend's voice), never Duolingo's guilt trip.
- **Opening the reel isn't progress.** Only "Tried it" counts.
- **Never present the backlog as a to-do list.** Today's 1, then done.
- **AI-written prompts are labeled as suggestions** and are easy to dismiss.
- **At most one notification a day**, and fewer if they're ignored.

## What the seed data tells us

From Ariel's 1,216 saves (`data/ig-saved-posts-seed.md`) and Reut's export (`data/ig-reut-export/`):

| Finding | Example | What it means for us |
|---|---|---|
| **The caption often isn't the tip** | "It's cool that he shared this! #claude #chatgpt #ai" | We need our own title, gist and try prompt, written from whatever text we have. |
| **27% of Ariel's captions are almost empty** (under 40 characters without hashtags), and 58 have none | "Tag bro #GymMeme…" | No decent try prompt is possible from text alone. These stay in the library but are never picked for Today's 1 (until we can read the video). |
| **Comment-for-the-link posts** (about 50 in Ariel's saves) | "Comment "DESIGN" and I'll send you the 5 Claude Code tools" | The try is literally "comment DESIGN and get the link". Show the keyword and a button to open the post. |
| **Much of what people save isn't a tip** | Memes, SpongeBob theories, Spotify ads, news | Those go to Everything else, not Learn. |
| **Topics are narrow and personal** | Ariel: AI tools, quant, music production, guitar. Reut: guitar ("Instruments again soon"), design inspo | Sections are whatever the user has. |
| **Multilingual** | Hebrew and Korean captions | Titles, gists and prompts in the caption's language; search handles Hebrew. |

## Scope

**In (MVP):** Today's 1 with try prompts; Tried it / Not today / Not for me; "When?" reminders; the weekly ring; spaced "Still got it?" reviews; the daily practice notification with back-off; a short first-time setup; the library (search, topic sections, tip detail); per-topic progress counts.

**Out (MVP):** AI-generated check questions after a try (later, behind a setting that is off by default); XP, streaks, badges, leagues; summaries from the video itself (needs transcripts); an AI chat over the saves; user-made folders; notes; more than one Learn tab.

## The core loop

```
open Learn → weekly ring + Today's 1
   each card:  Tried it ──→ ring fills, small celebration, review in 3 days
               Not today → "When?" → reminder about this save
               Not for me → archived, never picked again
   handled → "Done for today" (+ a one-liner, "One more?" link)
daily notification (chosen time) → one specific save → opens its card
Monday → fresh week, ring resets, new picks
```

## Screens

### L0. First-time setup (first open of the Learn tab)

Three quick steps, skippable:

1. **"Pick what you actually want to learn."** 5 saves from the user's biggest Learn topics, one at a time, swiped (the confirmation card's swipe component): right = *I want to try this*, left = *Not for me*. These seed Today's picks.
2. **"How many tries a week?"** Chips: 1 · **3** (default) · 5 · 7. Copy: "Small is fine. You can change it."
3. **"When should we nudge you?"** Time chips (Morning · Lunch · **Evening** · Off) → the system notification prompt.

Then the weekly ring appears with its first segment already filled: "Picked your saves ✓".

### L1. Learn home (tab root)

Top to bottom:

1. **Header:** "Learn" and the Everything else button top right (see *Everything else* in [layout-proposal.md](layout-proposal.md)).
2. **Weekly ring:** "2 of 3 tries this week" in the DailySpend ring style, lime fill. Tap → L5 (progress).
3. **Monday card** (Mondays only, or the first open after 7+ days away): "New week. Here's today's pick." / "Fresh start. Here's today's pick."
4. **Today's 1:** one practice card (L2), big. Once it's handled it collapses into a small done row ("✓ Box-shift trick") and **"Done for today."** appears with a one-liner ("Your future self says thanks.") and a quiet **"One more?"** link.
5. **Search field** (the library starts here).
6. **Topic sections**, largest first: "🎸 Guitar · 4 tried of 12", a horizontal row of tip cards, **See all →** to L3.

### L2. Practice card (Today's 1)

- Thumbnail (fallback: the topic emoji on a dark tile), title, author, topic.
- The **try prompt**, big and prominent, with a small "Suggested" label: *"Try this (2 min): play the A minor pentatonic box, then shift it up one fret."*
- For comment-for-the-link posts, the prompt is: *"Comment DESIGN on the post to get the 5 tools."* with **Open post to comment**.
- A **Still got it?** variant for spaced reviews: same card, prompt reads "You tried this 10 days ago. Still got it?", buttons **Yep** / **Try again**.
- Buttons:
  - **Tried it** (primary, lime) → ring fills with a small spring animation + haptic, a quip ("Look at you."), the card collapses. Schedules a review in 3 days.
  - **Not today** → "When?" chips: **Tonight** · **Tomorrow** · **Weekend** → a local notification about this save at that time ("Tonight" = the user's evening slot). The card shows as handled ("Tonight ⏰"), with a small **Pick another** link.
  - **Not for me** → archived: stays in the library, never picked again. Undo for 3 seconds. Since today's pick was a miss, a new one replaces it (once a day; after that, "Done for today").
- **Open the reel ↗** as a small secondary link (doesn't count as a try).

### L3. Topic page

- "🎸 Guitar", with "4 tried of 12".
- Filter chips: **All** · **Not tried** · **Tried** · **Not for me**.
- Vertical list of tip cards, newest saved first. Tap → L4.

### L4. Tip detail (sheet)

- Big thumbnail → opens the post in Instagram (⚠️ in-app playback is the known gap; see the sprint doc).
- Title, author, when saved, status ("Tried twice · next review in 8 days").
- The try prompt, with **Tried it** right there (a try from the library counts too).
- **Gist** (1–2 sentences) and **key points** (0–5, only when the caption lists them).
- The comment-for-the-link notice, when relevant.
- The original caption, collapsed.
- Actions: **Remind me…** (the "When?" chips) · **Move to…** (another topic or lego screen) · **Not for me** / **Bring back**.

### L5. Progress (sheet)

Deliberately simple, about identity, not points:

- This week's ring, and the last 8 weeks as small rings (all tries count, no "failed" styling for low weeks).
- Per topic: "🎸 Guitar · 5 tried · 2 still got it".
- One identity line built from the counts: "You've tried 5 guitar tips. You're someone who practices."
- Settings: weekly goal, reminder time, reminders on/off.

### L6. Search results

- Tip cards, best match first, across all topics.
- Matches the title, gist, key points, try prompt, caption, hashtags, author and topic. Case- and accent-insensitive; works for Hebrew.
- Empty: "Nothing in Learn for 'x'." + **Search Everything else**.

## Picking Today's 1

A pure, testable function. Each day (stable for the whole day):

1. **Due first:** a reminder the user scheduled for today ("Not today → Tomorrow"), then a spaced review that's due. If several are due, the others become the next "One more?" picks, then roll to following days.
2. **Fill the rest** by weighted random over tips that are not tried, not archived, not thin:
   - base weight 1;
   - × 2 if the user swiped "want to try" in setup;
   - × (1 + tries in that topic ÷ 5), so topics the user acts on come up more;
   - × 0.2 if it was shown in the last 14 days (so everything gets seen before repeats).
3. Rotate topics: don't pick the same topic two days in a row when another topic is available.

"One more?" draws one extra tip from the same pool.

## Notifications

Local only (`UNUserNotificationCenter`), all rules in one pure `ReminderPolicy` type:

- **At most 1 practice notification a day**, at the chosen time. With Fitness in the app too, it's one app-chosen nudge a day **across both tabs** (see *Notifications across Learn and Fitness* in [fitness.md](fitness.md)). "When?" reminders are extra but never more than one at the same time.
- **Always about a specific save.** Rotating templates, never the same one twice in a row, e.g.:
  - "2 min tonight? The box-shift trick you saved in March."
  - "You saved this for a reason: 'Diminished scale tricks'."
  - "One try. That's the whole ask. 🎸"
- **First week:** only the daily one, nothing extra.
- **Back-off:** after 3 ignored in a row → every other day. After 7 days with no opens → one last message ("We'll stop nudging for now. Your saves will be here.") and then no more practice notifications until the user opens Learn again.
- Tapping a notification opens Learn on that save's card.

## States

| State | What the user sees |
|---|---|
| **Setup skipped** | Today's 1 from the biggest topic; goal 3; reminders off, with a small "Get a nudge?" row in L1. |
| **Notifications denied** | Everything works; the "When?" chips set in-app reminders that show at the top of Today's 1 instead. |
| **All tips tried or archived** | Today's 1 shows only due reviews; if none: "You've tried everything you saved. Go save more." |
| **Only thin tips** | Today's 1 is empty with an explanation; the library still works. |
| **Away 7+ days** | "Fresh start" card; no mention of what was missed. |
| **No search results** | See L6. |

## Data needs

### From the data pull (per saved post)

| Field | Required? | Why Learn needs it |
|---|---|---|
| `url`, `platform`, `author` | ✅ | Open the post; card byline. |
| **full `caption`** | ✅ | The only source for the title, gist, key points, try prompt and comment keyword. The 160-character cut loses lists like "5 tools: …". |
| `hashtags` | ✅ | Topic signal when the caption is thin; search. |
| `saved_at` | ✅ | "The trick you saved in March" in notifications; newest-first lists. |
| `collections` | ⭐ | A strong topic signal ("Instruments again soon" → guitar). |
| `thumbnail_url` | ⭐ | Cards and notifications are far more recognizable with the image. |
| `on_screen_text` + `transcript` | Later | Most tips live in the video: better try prompts, and thin posts become usable. |

### From extraction (LLM, per post)

| Field | Why |
|---|---|
| `lego_screen` = learn | Whether it's in Learn at all. |
| `topic_id` | Which section. |
| `title` (≤ 60 characters, caption's language) | Cards, notifications. |
| `gist` (≤ 140 characters) | Detail sheet; search. |
| `try_prompt` (≤ 100 characters, imperative, doable in ~2 minutes) | **The heart of the loop.** Must be concrete and based only on the caption; never invented steps. Empty when `is_thin`. |
| `tip_type`: tool / technique / tutorial / list / idea | Card badge; tunes the prompt (a tool's try is "open it and do X"). |
| `key_points[]` (0–5) | Only when the caption lists them. Never invented. |
| `cta_keyword` | "DESIGN" for comment-for-the-link posts. |
| `is_thin` | Too little text to say what the tip is → library only, never in Today's 1. |

### User state (on device)

Per tip: `status` (new · wantToTry · tried · archived), `triedAt[]`, `reviewStep` (0–3), `nextReviewAt`, `remindAt`, `lastShownAt`, `topicOverride`.
Global: `weeklyGoal`, `reminderSlot`, `setupDone`, `ignoredNotificationCount`, `lastOpenedAt`.

## Model sketch

```swift
struct Tip: Identifiable, Codable {          // extracted, read-only in the app
    let id: SavedPost.ID
    var topicID: String
    var title: String
    var gist: String?
    var tryPrompt: String?
    var type: TipType                        // tool, technique, tutorial, list, idea
    var keyPoints: [String]
    var ctaKeyword: String?
    var isThin: Bool
}

struct PracticeState: Codable {              // user's, persisted separately so
    var status: PracticeStatus = .new        // re-running extraction never wipes it
    var triedAt: [Date] = []
    var reviewStep = 0                       // 3, 10, 30 days
    var nextReviewAt: Date?
    var remindAt: Date?
    var lastShownAt: Date?
    var topicOverride: String?
}
```

## Build notes for the coding agent

- **The practice loop is shared with Fitness later.** Build it in `ios/Hindsight/Practice/`, generic over a small protocol (id, title, prompt, topic), and use it from Learn. Don't build Fitness now.
  - `PracticeState.swift`, `PracticeStore.swift` (persists user state; loads/saves JSON in Application Support).
  - `TodayPicker.swift`: the *Picking Today's 1* rules as a pure function; date and random source injected.
  - `WeeklyProgress.swift`: ring math (week starts Monday, the first-week setup segment).
  - `ReminderPolicy.swift`: the notification rules as pure logic (what to send, when, which template, back-off). `ReminderScheduler.swift`: the thin `UNUserNotificationCenter` wrapper.
  - `PracticeCard.swift`, `WeeklyRing.swift`, `WhenChips.swift`: reusable views.
- **Learn-specific**, in `ios/Hindsight/LegoScreens/Learn/`: `Tip.swift`, `LearnView.swift` (L1), `LearnSetupView.swift` (L0), `LearnTopicView.swift` (L3), `TipDetailSheet.swift` (L4), `LearnProgressSheet.swift` (L5), `TipCard.swift`, `TipSearch.swift` (pure).
- **Depends on** (built Thursday): `Design/Theme.swift`, `Layout/LayoutConfig.swift`, the extraction fixture JSON (must include `try_prompt`), the confirmation card's swipe component, the shared Everything else button.
- **Notification taps:** set `UNUserNotificationCenter.current().delegate` from our own `ReminderScheduler`, not from `HindsightApp.swift`, to stay out of Ariel's file (see hotspots).
- **Tests** (`ios/HindsightTests/PracticeTests.swift`, `LearnTests.swift`):
  - picker: due items first; never tried/archived/thin; same pick all day; the 14-day repeat penalty; topic rotation across days.
  - weekly progress: resets Monday; the first-week setup segment; no "broken" state exists.
  - reminder policy: max 1/day; never the same template twice in a row; back-off after 3 ignored; stops after 7 quiet days; restarts on open.
  - spaced review: 3 → 10 → 30 days; "Try again" resets the step.
  - search: title above caption matches; case/accent-insensitive; Hebrew.
  - user state survives reloading the fixture.
- **Previews:** every view with seed tips (at least one thin, one comment-for-the-link, one Hebrew, one due review).

## ⚠️ Merge-conflict hotspots with Ariel

| File | What we'd change | Risk |
|---|---|---|
| `ios/Hindsight/Models/SavedPost.swift` | `hashtags`, `thumbnailURL`, `collections`, `savedAt`, shared with the Map spec. | **High.** One commit for all new `SavedPost` fields (see the [Map spec](map.md)). |
| `ios/Hindsight/Onboarding/OnboardingPreferences.swift` | Ariel's `resurface` (daily / weekly / never) overlaps with Learn's reminders. Learn doesn't read it; it's retired with the preferences step. | Medium. Agree with Ariel before removing it. |
| `ios/Hindsight/HindsightApp.swift` | **Avoided:** notification handling lives in `ReminderScheduler`, not the app entry point. | None if the rule above is followed. |

## Done when

- [ ] First open of Learn runs setup (5 swipes, goal, reminder time) in under a minute, and the ring starts with the setup segment filled.
- [ ] Today's 1 never includes thin, archived or tried tips; due reminders and reviews come first; the pick doesn't change during the day.
- [ ] Tried it fills the ring with animation + haptic; the tip comes back as "Still got it?" after 3 days (testable with an injected clock).
- [ ] Not today → Tonight schedules a local notification that opens that save's card.
- [ ] After today's card is handled: "Done for today", and nothing nags until tomorrow.
- [ ] No screen ever shows a broken streak, a missed-days count, points or badges.
- [ ] Notifications: max 1 a day, rotating wording, back-off and stop rules pass their unit tests.
- [ ] With Ariel's seed: Learn sections for his main topics; comment-for-the-link posts show the keyword prompt.
- [ ] With Reut's seed: a Guitar section with try prompts.
- [ ] Search finds "diminished"; a Hebrew query finds Hebrew tips.

## Decided (was open in v1)

1. **Home layout:** the practice loop (ring + Today's 1) on top, the library (search + topic sections) below.
2. **"Tried it"** is the core action of the loop, not a side toggle.
3. **Resurfacing** is Today's 1 plus the daily notification (in the MVP).
4. **Thin posts** stay in the library with a fallback title but are never picked for Today's 1.

## Decided (was open in v2)

1. **Weekly goal:** 3 tries a week by default, customizable (setup and the progress sheet).
2. **Today's 1**, not Today's 3. One card a day, then "Done for today", with "One more?" for the motivated.
3. **The "Suggested" label** on AI-written prompts stays visible.
4. **Check questions after a try:** built later, behind a setting that's **off by default**. Not in the MVP.

## Sources

From the research report (2026-09-30). Figures marked *unverified* couldn't be checked against the primary source.

- Retrieval practice: Roediger & Karpicke 2006. https://journals.sagepub.com/doi/10.1111/j.1467-9280.2006.01693.x
- Readwise Daily Review and Mastery: https://docs.readwise.io/readwise/docs/faqs/reviewing-highlights
- Implementation intentions meta-analysis: Gollwitzer & Sheeran 2006. https://kops.uni-konstanz.de/handle/123456789/10973
- Duolingo on streaks and freezes: https://blog.duolingo.com/how-duolingo-streak-builds-habit and https://blog.duolingo.com/how-streaks-keep-duolingo-learners-committed-to-their-language-goals/
- Broken streaks demotivate: Silverman & Barasch, JCR 2023. https://academic.oup.com/jcr/article-abstract/49/6/1095/6623414
- Missing a day doesn't break habit formation: Lally et al. 2010. https://onlinelibrary.wiley.com/doi/abs/10.1002/ejsp.674
- Endowed progress: Nunes & Drèze 2006; goal gradient: Kivetz et al. 2006. https://journals.sagepub.com/doi/abs/10.1509/jmkr.43.1.39
- Duolingo notification bandits: Yancey & Settles, KDD 2020. https://research.duolingo.com/papers/yancey.kdd20.pdf (*effect sizes unverified*)
- Fresh-start effect: Dai, Milkman & Riis 2014. https://pubsonline.informs.org/doi/10.1287/mnsc.2014.1901
- Rewards vs intrinsic motivation: Deci, Koestner & Ryan 1999. https://pubmed.ncbi.nlm.nih.gov/10589297
- Brilliant's bite-size format: https://brilliant.org/faq/
