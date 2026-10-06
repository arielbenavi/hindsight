# Flow spec: Onboarding as one conversation

Status: **accepted** (2026-09-30). Decisions 1–4 below were made by Reut, all as recommended. Owners: Reut (the chat), Ariel (the Connect screen and the data behind it). Part of [ADR-001](../merge-plan.md), where it replaces workstream O1.

> **Revised 2026-10-06 (Reut + Ariel, after merging PR 16).** The flow is now: Ariel's **Welcome → How it works → Plug in your apps**, then **the chat**, then Ariel's **"You're in"** screen (`DoneStep`), then the tabs. What changed from the text below:
> - Welcome and How it works are separate screens again; Connect keeps Ariel's "Plug in your apps." heading, with three step dots. The Preferences step stays removed.
> - Connect keeps the Meta data-file import, "Start with N saves" (disabled at zero) and the sample-saves link (a testing aid for the beta; remove before the App Store release).
> - The chat no longer shows the receipt (R1) or the taste cards (R2), and no longer ends with its own "You're in": it starts at reading (R3) and hands over to `DoneStep`, which shows the counts and the taste. No dots or back button there.
> - Restarting onboarding (bug menu, Sources → "Run setup again") starts from Welcome.
> - New installs still start with no seed; the bundled datasets are reachable from the bug menu's Data section.

## The problem

Onboarding today is two flows glued together. Ariel's steps (welcome → how it works → connect) end, and then a second experience starts: "Whose saves are these?", then the proposal chat. Nothing carries over between them. The chat doesn't know what you just connected, and the moment your saves arrive (the payoff of all of Ariel's data work) goes by with no acknowledgement.

**The job:** two screens, one story. **Screen 1:** bring your saves in. **Screen 2:** a single chat that takes it from there. It confirms what arrived, shows it reading and grouping your saves, then proposes your app, checks your places, and hands you the keys. All in one transcript.

## The shape

```
┌──────────────────────────┐        ┌───────────────────────────────────────────────────────────────┐
│ 1. CONNECT (first screen)│        │ 2. THE CHAT (one transcript, resumable)                        │
│                          │        │                                                               │
│ Your saves, in hindsight.│  Start │  R1 Receipt ─ R2 A taste ─ R3 Reading & grouping (live) ──┐    │
│ Instagram + Facebook ... │ ─────► │                                                          │    │
│ X .......................│        │  B1 Here's what I found ─ B2 ≤2 questions ─ B3 Your app ──┤    │
│ TikTok · WhatsApp (soon) │        │  B4 edits ─ B5 approve                                   │    │
│ Import a file · Try demo │        │                                                          │    │
│ [Start with 412 saves]   │        │  C1 "12 spots to double-check?" ─► card deck ─► C2 back ─┘    │
└──────────────────────────┘        │  ─► "You're in." [Open my app] ─► tabs                        │
       Ariel's screen               └───────────────────────────────────────────────────────────────┘
                                       R = new (reading) · B = built (layout-proposal.md) · C = confirm.md
```

## Principles

1. **One voice, one transcript.** Everything after Connect is the same chat and the same bot. Nothing interrupts it with a new "screen". The confirmation card deck opens *from* a chat message and returns *to* it.
2. **Show the work.** The user watches their saves get read and grouped (counts, then topic chips popping in), so the proposal feels earned, not random.
3. **Never make them wait on the slow part.** Rules and group labels sort most posts in seconds. The proposal starts once enough is decided. Model calls (Private Cloud Compute) keep going behind the chat, and late posts slot into the topics already shown.
4. **Tap first, typing optional**, as in the proposal spec. Every bot message has chips.
5. **The chat is a UI, not a free-form LLM conversation (v1).** Bot lines are fixed templates filled with real numbers: testable, instant, and they use no quota. Apple's models do the *sorting* and later the *typed edits*, not the small talk. A free-form bot is a later upgrade (see Later).

## Screen 1: Connect (Ariel's, now the first screen)

Ariel's page with the Instagram/Facebook (Muse), X and TikTok options becomes **the first thing you see**. Changes:

- **A welcome header on top**, folded in from `WelcomeStep`: "Your saves, in hindsight." plus one line on what happens next ("Connect where you save things. We'll read them and build your app around them."). `WelcomeStep` and `HowItWorksStep` go away as separate screens (decision 1).
- **Sources, as today:** Instagram + Facebook via Muse, X, and TikTok and WhatsApp notes as "soon". Plus two new rows: **Import a file** (Instagram/Facebook/TikTok export; the parser exists) and **Just looking? Try it with sample saves** (the demo, which runs the same chat on a bundled dataset).
- **The button is the confirmation the user asked for:** "**Start with 412 saves**". Disabled at 0, with "Connect at least one source to start". Under it: "You can add more later."
- If a Muse connector sync is still delivering, the button still works. The chat picks up late arrivals (R3).

## Screen 2: The chat

### R1. Receipt (new; Ariel's "You're in" numbers move here)

> **Bot:** Got them. **412 saves**: 324 from Instagram, 88 from X.
>
> *[Receipt card: one tile per platform with its count, as on the old Done screen]*

### R2. A taste (new; Ariel's preview cards move here)

> **Bot:** Here's a taste of what's in there:
>
> *[3 post cards: newest, one per platform when possible; tap opens the post]*

No reply needed. It flows into R3.

### R3. Reading & grouping (new; live)

A single bot message that **updates in place** while the sort engine works:

> **Bot:** Reading your saves… **180 of 412**
>
> *[Topic chips pop in as groups form: 🍽️ NYC food & cafés 64 · 🎸 Guitar 5 · 🧘 Back & mobility 9 …]*

- The count and chips come from the sort engine's progress stream (rules → groups → model).
- If Muse is still sending: a line under it, "Still getting saves from Muse… +38".
- **When to move on:** when ≥ 90% of posts are decided, or after ~20 s, whichever comes first (decision 3). The rest keep sorting behind the chat and join existing topics.
- Ends with: "Done. That's all 412." (or "Done with most of them. I'll finish the rest in the background.")

### B1–B5. The proposal (built; unchanged in substance)

It picks up in the same transcript. B1 no longer needs its own intro ("Okay, I went through your 324 saves"), because R3 just did that. B1 becomes the settled topic card plus "The random stuff (memes, news) I'll leave out for now." Then B2 questions (≤ 2), B3 the app preview card, B4 edits, and B5 "Looks good" → "Building it… 🔨". See [layout-proposal.md](layout-proposal.md).

### C1–C2. Place check (built; now opened from the chat)

If the app has a Map:

> **Bot:** One last thing. I put **148 spots** on your map. **12** I'm not sure about. Want to check them? About a minute.
>
> Chips: **Check them** · **Later**

- **Check them** opens the confirmation card deck ([confirm.md](confirm.md)) full screen, from this message. When it's done, it closes back into the chat:

> **Bot:** Map's ready. Go eat something.

- **Later** puts the 12 in Needs review. Nothing is lost.
- No Map, or nothing to ask ("Nailed all of them"): skip straight to the end.

### End

> **Bot:** You're in. 🎉
>
> Chips: **Open my app**

That's the single "you're in" moment, at the very end. The tab bar appears on the first tab.

## States

| State | What the chat does |
|---|---|
| **Fewer than 20 saves** | R1–R2 as usual; R3 is quick; skip B2; "More saves make it smarter. Add more anytime." (proposal spec) |
| **Nothing fits** | The proposal spec's "nothing fits" wording, offering Learn anyway |
| **No Apple Intelligence** (older iPhone, or phone language not supported; see [AI requirements](../merge-plan.md#ai-requirements-read-this)) | The same chat. The engine runs rules + groups only, so R3 decides fewer posts, B2 may ask the maximum 2 questions, and the rest go to Everything else. No error message. |
| **Private Cloud Compute quota reached** | The same as above for the rest of today. "I'll keep sorting the last few in the background" |
| **Quit mid-chat** | Resume at the last bot message; if R3 was running, the engine resumes from its cache |
| **Muse delivers more after the proposal** | New posts join existing topics quietly; a count badge on Everything else if they fit nowhere |
| **Demo** | The same chat on the bundled dataset; R3 replays fast; a "Sample saves" pill stays in the header |

## Architecture

```
RootView phases:  connect ──► chat ──► tabs          (computed from what's on disk; see ADR §3)

ConnectScreen (Ariel)            SetupChat (Reut)                              Engines
───────────────────              ──────────────────────────────────────        ─────────────────────────
SavedPostStore ──"Start"────►    SetupChatModel (was ProposalChatModel)        SortEngine (ADR E1–E2)
                                   stages: receipt, reading, found,              AsyncStream<SortProgress>
                                   questions, proposal, editing, approved,       {decided, total, topics[]}
                                   placeCheck, done                            PlaceStore.startMatching()
                                   messages: + receipt, samples, progress        (starts as soon as map
                                   persisted per dataset (proposal-chat.json)     posts are decided)
                                        │
                                        └─ "Check them" ─► ConfirmationFlow(mode: .onboarding) ─► back to chat
```

- **One model, extended, not a second chat.** `ProposalChatModel` becomes `SetupChatModel`, with three new stages (`receipt`, `reading`, `placeCheck`) and three new message kinds (`receipt`, `samples`, `progress`). The B-stages, the app preview card, edits and resume all stay as they are.
- **`progress` is the one message that updates in place.** It's re-rendered from the engine's stream, and only its final text is persisted.
- **RootView loses two phases:** `DatasetPicker` (the demo replaces it) and the standalone `ConfirmationFlow` phase (it's launched from the chat now).
- **Built before the engine exists:** R1–R3 can run against a bundled fixture with a simulated progress stream (replaying its topics over ~5 s). So the chat UX can land before E1–E2 and switch to the real stream with no UI change.

## ⚠️ Merge-conflict hotspots with Ariel

| File | Change | Owner | Risk |
|---|---|---|---|
| `Onboarding/OnboardingFlow.swift`, `OnboardingModel.swift` | Down to one screen (Connect). The step machine and progress capsules go away. | Ariel | **High.** Ariel's files; he makes this change. |
| `Onboarding/Steps/WelcomeStep.swift`, `HowItWorksStep.swift` | Deleted; the welcome header moves into Connect | Ariel | Medium. Also restyled on `reut/design-revamp`. |
| `Onboarding/Steps/ConnectStep.swift` | Welcome header, *Import a file*, *Try sample saves*, "Start with N saves" (the last is already on `all/merge`) | Ariel | **High.** Also restyled on `reut/design-revamp`, which conflicts with `master` already. |
| `HindsightApp.swift` / `App/RootView.swift` | connect → chat → tabs; `DatasetPicker` and the confirmation phase removed | Reut | **High** (`HindsightApp` is Ariel's). One commit, announced. |
| `Layout/LayoutProposalView.swift` | Grows into the setup chat (or moves to `Setup/`) | Reut | **High** vs `reut/design-revamp`, which restyled it. Land the design revamp first, or rebase this on it. |
| Old Done-step code (`DoneStep.swift`, deleted in `3303da7`) | Its platform tiles and `SavedPostPreviewCard` come back as R1/R2 bubbles | Reut | Low. Restore from git history into `Design/`. |

## Done when

- [ ] A fresh install shows Connect first, with nothing before it.
- [ ] After "Start with N saves", every step through "You're in" happens in one scrolling transcript.
- [ ] The receipt counts match what was imported, per platform.
- [ ] R3 shows live progress and topic chips; the proposal starts within ~20 s even on 1,200 saves.
- [ ] The place check opens from the chat and returns to it.
- [ ] Quitting anywhere resumes in the same place in the transcript.
- [ ] It works end to end with no Apple Intelligence (rules only) and on the demo.

## Decided (2026-09-30)

1. **Welcome and How it works** fold into a one-line header on Connect; both screens are deleted. Connect is the first screen.
2. **Place check** opens from a chat message as the existing full-screen swipe deck, and returns to the chat.
3. **Reading ends** at ≥ 90% of posts decided or ~20 s, whichever is first. The rest finish in the background.
4. **Bot voice (v1):** fixed lines with real numbers. Apple's models do the sorting, not the talking.

## Later

- **A free-form bot:** Private Cloud Compute understands typed edits first (the natural next step for `TypedEditParser`), then open questions ("what did I save about Lisbon?").
- **Connect inside the chat:** "Want to add your TikTok too?" as a chip later on, once the Share extension exists.
- **Re-running the chat** as "Rebuild my app" (layout-proposal spec, decided item 3).
