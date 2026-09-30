# Flow spec: Layout proposal ("here's your app")

Status: draft for the MVP sprint ([mvp-sprint.md](../mvp-sprint.md)). Owner: Reut (the proposal and editing). Ariel owns the chat shell and topic clustering that come before it.

## The problem

Different people save different things and want to use them differently. Reut's saves are mostly NYC restaurants and cafés; Ariel's are AI, quant, music and back-pain stretches. One fixed layout serves neither of them well.

**The job:** turn "we grouped your saves into topics" into "here's an app built around them" in one short exchange that the user approves in a tap or tweaks in a few. It should feel like the app is getting to know you, not like a settings form.

## How it fits into onboarding

Ariel's onboarding becomes a **chat with a bot**. Its last part is the proposal:

```
connect apps → data pulled → topics clustered (Ariel)
   → chat: "here's what I found" → 0–2 quick questions → "here's your app" → approve / edit   ← this spec
   → place confirmation (confirm.md), if there's a Map tab
   → the app
```

This replaces the current `PreferencesStep` (group by / feed-grid-collections / topics). Grouping and layout are now decided by the lego screens. Resurface cadence moves to Fitness reminders.

## Principles

1. **Proposal first, questions second.** The bot does the work and shows a finished app. The user reacts to something concrete instead of answering abstract questions.
2. **At most 2 questions,** and only when the answer changes the layout. No "what are your goals?".
3. **Tap before type.** Every bot message has reply chips. Typing is allowed but never needed.
4. **Cheap by design.** The LLM only sees topic summaries (label, count, 3 sample captions), never every post. Most of the proposal is rules; the LLM phrases it, asks the ambiguity questions and understands typed edits. Budget: **under ~5k tokens per onboarding**.
5. **One tab per lego screen.** Topics are sections inside a tab, never tabs of their own (see *Topics → tabs*).

## Topics → tabs (the rules)

| Lego screen | Gets topics like | Proposed when |
|---|---|---|
| 🗺️ **Map** | restaurants, cafés, bars, travel spots, things to do | ≥ 5 places. With fewer, the bot offers it as a chip instead ("Also add a map? 4 spots") |
| 💪 **Fitness** | stretches, mobility, physical therapy, workouts | ≥ 5 exercise posts |
| 📚 **Learn** (Education) | tips, tutorials, how-tos: guitar, coding, design, cooking, AI | ≥ 5 posts; each topic becomes a section in the tab |
| (none) | memes, news, announcements, ads | Not shown in the MVP. The bot mentions them honestly (see B1) |

Tab order: largest first, but the Map always goes first if it's there (it's the "use it right now" tab).

**Worked examples from our seed data**
- **Reut:** 🗺️ Map (NYC food and cafés, Brooklyn, Argentina, travel) · 📚 Learn (guitar, design inspo). The "Aesthetic coffee" collection is the ambiguity question (B2).
- **Ariel:** 📚 Learn (AI tools, quant, music production) · 💪 Fitness (mobility, back pain) · 🗺️ Map (his handful of NYC rooftops and bars), offered as a chip if it's under 5.

## The conversation

The bot is short and a little playful (the same voice as DailySpend and the confirmation cards). Bot messages come in as bubbles; the user's replies are chips that turn into user bubbles when tapped.

### B1. "Here's what I found" (example numbers)

> **Bot:** Okay, I went through your 324 saves. Here's what's in there:
>
> *[Topic card: a wrap of chips with emoji + counts]* 🍽️ NYC food & cafés 187 · ✈️ Travel spots 22 · 🎨 Design inspo 66 · 🎸 Guitar 5 · 🤷 Random 44
>
> **Bot:** The random stuff (memes, news) I'll leave out for now.

No reply needed; it flows straight into B2 or B3.

### B2. Quick questions (0–2)

Only when a topic could go to two lego screens, or it's unclear whether it's worth a tab. The question comes with the evidence so it's quick to answer.

> **Bot:** Your "Aesthetic coffee" saves: cafés you want to visit, or coffee setups for home?
>
> *[3 sample thumbnails from the collection]*
>
> Chips: **Cafés to visit** · **Home setups** · **A mix**

The answer moves the topic (Map / Learn / left out). Ariel's clustering suggests these questions (`ambiguity_question` in the contract); the bot only asks the top 2.

### B3. "Here's your app"

The key moment. A rich message showing the proposed app:

> **Bot:** Here's your app:
>
> *[App preview card]*
>
> **Bot:** Want to change anything?
>
> Chips: **Looks good** · **Change something**

**App preview card**
- A mini phone tab bar with the proposed tabs: emoji + name ("🗺️ Map", "📚 Learn").
- Under it, one row per tab: name, what's inside ("164 spots in NYC, Brooklyn and Buenos Aires"; "Guitar · Design inspo, 71 posts"), and a tiny preview (3 thumbnails, or a map snapshot full of emoji pins for Map).
- A card, not a screenshot, so it can be edited in place (B4).

### B4. Editing

Tapping **Change something** puts the preview card in edit mode, and the bot says "Tap a tab to change it, or just tell me."

**Direct edits on the card**
- Drag tabs to reorder.
- Tap a tab → a small menu: **Rename** · **Remove** · **Change emoji**.
- In Learn: tap a topic section → **Remove** or **Move to its own…** (disabled in the MVP; see open questions).
- A **+ Add** row with any lego screen that isn't there yet (e.g. "💪 Fitness — 2 posts").

**Typed edits:** "drop design", "call it Eats", "put Learn first". The LLM turns the message into one of a few edit operations (add / remove / rename / reorder / move topic / leave out topic), applies it, and the card updates. If it can't tell, it asks with chips.

After each edit the bot confirms in one line ("Done. Learn is just guitar now.") and shows **Looks good** again.

### B5. Approve

> **User:** Looks good
>
> **Bot:** Building it… 🔨

Then: place confirmation if there's a Map (confirm.md), otherwise straight into the app, on the first tab.

## States

| State | What the user sees |
|---|---|
| **Clustering still running** | The bot types ("…") with a line that updates: "Reading your saves… 180 of 324". |
| **Only one lego screen fits** | Still a proposal: "Your saves are basically one big food map. Here's your app:" with one tab. |
| **Nothing fits** | "Your saves are mostly memes and news, which I can't organize yet." Offer **Learn** anyway with whatever's closest, or finish with the list of what's coming. |
| **Very few saves** (< 20) | Skip B2. Propose whatever fits; say that more saves make it smarter. |
| **LLM unavailable / offline** | The rules alone build the proposal (B1 and B3 with fixed wording), no B2, no typed edits; the chips still work. |
| **User quits mid-chat** | Resume at the last bot message next launch. |

## Data needs

### From clustering (Ariel → this screen)

| Field | Why |
|---|---|
| `topics[].id`, `label` | Chips in B1, sections in Learn. |
| `topics[].emoji` | Chip and section icon. Can default by lego screen. |
| `topics[].post_count` | Counts in B1 and B3; the ≥ 5 thresholds. |
| `topics[].sample_post_ids` (3–5) | Thumbnails in B2 and B3; also the only posts the LLM sees for that topic. |
| `topics[].suggested_lego_screen` | map / fitness / learn / none. The rules above apply this. |
| `topics[].confidence` | Low confidence → candidate for a B2 question. |
| `topics[].ambiguity_question` + `options[]` (optional) | The B2 question and chips, and which lego screen each answer maps to. |
| `topics[].source_collections` | Lets B2 name the user's own collection ("Your 'Aesthetic coffee' saves…"). Much clearer than a made-up topic name. |
| `post_ids` per topic | Which posts each tab shows. |

### Output: `LayoutConfig` (this screen → the app)

```swift
struct LayoutConfig: Codable {
    var tabs: [TabConfig]              // in tab-bar order
    var excludedTopicIDs: [String]     // "left out for now"
    var createdAt: Date
    var version: Int                   // for migrations when lego screens change
}

struct TabConfig: Codable, Identifiable {
    let id: String
    var legoScreen: LegoScreen         // .map, .fitness, .learn
    var title: String                  // "Map", or the user's rename ("Eats")
    var emoji: String
    var topicIDs: [String]             // sections inside the tab
}
```

The app's tab bar is built only from `LayoutConfig`. It replaces `OnboardingPreferences.grouping`, `.layout` and `.topics`.

## Done when

- [ ] With Reut's seed: the proposal is 🗺️ Map + 📚 Learn, and "Aesthetic coffee" is asked about in B2.
- [ ] With Ariel's seed: the proposal is 📚 Learn + 💪 Fitness, with Map included or offered as a chip.
- [ ] **Looks good** on the first proposal finishes in one tap after B3.
- [ ] Reorder, rename, remove and add all work by tapping; at least rename and remove also work typed.
- [ ] Never more than 2 questions.
- [ ] Works without the LLM (rules + fixed wording).
- [ ] The tab bar after onboarding matches the approved card exactly.

## Decided (was open)

1. **One Learn tab in the MVP.** Letting the user split a topic into its own tab is an idea for later.
2. **"Learn"** is the working name. Loose; we'll workshop it.
3. **No "Rebuild my app" in the MVP.** Definitely later.
4. **Keep an "Everything else" list** (see below). Later, it gets a "try to place these" action that sorts them into existing tabs, which ties into rebuilding the app and creating new pages.

## Everything else

Saves that didn't fit any tab (and topics the user left out) stay reachable, so nothing feels lost.

- **Where:** a button in the top-right of every tab's header opens a sheet: "Everything else · 44".
- **What:** a plain list, newest first: thumbnail, author, first line of caption. Tap → opens the post.
- **Later:** "Try to place these" re-runs sorting on the list and suggests moving posts into existing tabs; with "Rebuild my app", it can also propose new tabs.

## ⚠️ Merge-conflict hotspots with Ariel

This spec replaces part of Ariel's onboarding, so it touches his files more than any other spec. Talk to him **before** changing any of these, and land each change as its own small commit.

| File | What we'd change | Risk |
|---|---|---|
| `ios/Hindsight/Onboarding/OnboardingModel.swift` | The `Step` enum (`welcome, howItWorks, connect, preferences, done`): `.preferences` is replaced by the chat + proposal. `topicSuggestions` is replaced by Ariel's clustering output. | **High.** Ariel is turning onboarding into a chat, so he's rewriting this file too. |
| `ios/Hindsight/Onboarding/OnboardingFlow.swift` | The `switch model.step` that picks each screen. | **High**, same reason. |
| `ios/Hindsight/Onboarding/Steps/PreferencesStep.swift` | Deleted, replaced by the proposal. | **High** if he edits it meanwhile. |
| `ios/Hindsight/Onboarding/OnboardingPreferences.swift` | `grouping`, `layout` and `topics` are replaced by `LayoutConfig`; `resurface` moves to Fitness. The saved UserDefaults key must still load or be migrated. | Medium. |
| `ios/Hindsight/HindsightApp.swift` | After onboarding: proposal → confirmation → tab shell, instead of `ContentView`. | **High.** Ariel changed it in PR #1. |
| `ios/HindsightTests/OnboardingTests.swift` | Tests for the preferences step and topic suggestions will need updating. | Medium. |

**How we avoid them:** put our code in new files we own (`ios/Hindsight/Layout/`: `LayoutConfig`, the proposal card, the edit operations). Agree with Ariel on one integration point: his chat calls our proposal view with the clustering output and gets a `LayoutConfig` back. Then only one line of `OnboardingFlow` changes, and he makes it.
