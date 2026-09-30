# Lego screen spec: Learn

Status: draft for the MVP sprint ([mvp-sprint.md](../mvp-sprint.md)). Owner: Reut. "Learn" is the working name for the Education lego screen.

## The problem

People save tips, tutorials and tools because they mean to use them later: a guitar scale trick, a Claude Code plugin, a mixing technique. Later, they can't find them. Instagram's saved tab is a wall of thumbnails with no search, and the caption rarely says what the tip actually was.

**Learn's job:** *"What was that tip about X?"*, answered with a search or two taps. Second, occasionally put a forgotten good save back in front of you.

It's a reference shelf, not a feed to scroll.

## What the seed data tells us

From Ariel's 1,216 saves (`data/ig-saved-posts-seed.md`) and Reut's export (`data/ig-reut-export/`):

| Finding | Example | What it means for us |
|---|---|---|
| **The caption often isn't the tip** | "It's cool that he shared this! #claude #chatgpt #ai" | We need our own title and one-line gist, written from whatever text we have. The raw caption is a poor title. |
| **27% of Ariel's captions are almost empty** (under 40 characters without hashtags), and 58 have none | "Tag bro #GymMeme…" | For these, the tip lives only in the video. MVP: a fallback title from topic + author; video transcripts later. |
| **Comment-for-the-link posts** (about 50 in Ariel's saves) | "Comment "DESIGN" and I'll send you the 5 Claude Code tools" | The actual resource is sent in DMs. Show it clearly: "Comment DESIGN to get the link", with a button to open the post. |
| **Much of what people save isn't a tip** | Memes, SpongeBob theories, Spotify ads, news | Sorting decides what's Learn; the rest goes to Everything else, not here. |
| **Topics are narrow and personal** | Ariel: AI tools, quant, music production, guitar. Reut: guitar ("Instruments again soon"), design inspo | Topics come from clustering; sections are whatever the user has, not a fixed list. |
| **Multilingual** | Hebrew and Korean captions | Titles and gists are written in the caption's language; search must handle Hebrew. |

## Scope

**In:** one Learn tab; topic sections; search; tip cards; a tip detail sheet; "Tried it" toggle; a resurfaced tip at the top; opening the original post; moving a tip to another topic; hiding a tip (→ Everything else).

**Out (MVP):** summaries or key points from the video itself (needs transcripts from the backend), notifications (Fitness has reminders; Learn doesn't in the MVP), user-made folders, notes, an AI chat over the saves (the web prototype had one; later), more than one Learn tab.

## Screens

### L1. Learn home (tab root)

Top to bottom:

1. **Header:** "Learn" (big heavy type) and the Everything else button top right (see *Everything else* in [layout-proposal.md](layout-proposal.md)).
2. **Search field.** Typing replaces everything below it with results (L4).
3. **Resurfaced tip** ("From your saves"): one large card with a tip you haven't tried and haven't seen here in the last 7 days. Changes once a day. A small **Not now** swaps it for another. Tap → L3.
4. **Topic sections**, largest first. Each is a header ("🎸 Guitar · 12", with **See all →** to L2) and a horizontal row of up to 10 tip cards, newest saved first.

With only 1 topic, skip the sections: show that topic's tips as a vertical list right under the resurfaced tip.

### Tip card

Used in the rows, lists and search results.

- Thumbnail (fallback: the topic's emoji on a dark tile in the theme's surface color).
- **Title** (ours, not the caption), max 2 lines: "Diminished scale tricks for solos".
- Author · type badge: **Tool**, **Technique**, **Tutorial**, **List** or **Idea**.
- A small ✓ if tried; a 💬 if it's a comment-for-the-link post.

### L2. Topic page

- Title: "🎸 Guitar", with the count.
- Filter chips: **All** · **Not tried** · **Tried**.
- Vertical list of tip cards, newest saved first.

### L3. Tip detail (sheet)

- Big thumbnail → tap opens the post in Instagram (⚠️ in-app playback is the known gap; see the sprint doc).
- Title, author, when saved.
- **Gist:** one or two sentences on what the tip is.
- **Key points** (0–5 bullets), only when the caption actually lists them (e.g. a "5 tools" caption that names them).
- **Comment-for-the-link notice**, when relevant: "The creator sends this link if you comment **DESIGN**." Button: **Open post to comment**.
- The original caption, collapsed ("Show caption").
- Actions: **Tried it ✓** toggle · **Move to…** (another topic in Learn, or another lego screen) · **Hide** (moves it to Everything else).

### L4. Search results

- Results as a vertical list of tip cards, best match first, across all topics. The topic shows on each card.
- Matches the title, gist, key points, caption, hashtags, author and topic name. Case- and accent-insensitive; works for Hebrew.
- Empty: "Nothing in Learn for 'x'." plus **Search Everything else**, which runs the same search there.

## Flows

**LF1. "What was that tip?"** Learn → type "diminished" → tap the result → L3 → Open post. **Search + 2 taps.**

**LF2. Browse a topic.** Learn → "See all →" on Guitar → L2 → Not tried → pick one.

**LF3. Resurfaced.** Learn → the "From your saves" card → L3 → Tried it ✓ (it won't be resurfaced again).

**LF4. Comment for the link.** L3 → notice → Open post to comment → Instagram opens on the post.

**LF5. Wrong place.** L3 → Move to… → Fitness (it was actually a stretch). The tip leaves Learn and shows up in Fitness.

## States

| State | What the user sees |
|---|---|
| **No tips at all** | Shouldn't happen (no Learn tab would have been proposed). If it does: "Nothing here yet" + a link to Everything else. |
| **Everything tried** | The resurfaced card is hidden. |
| **Thin caption, no thumbnail** | Card with the fallback title ("Guitar reel from @ryan.liatsis") and the topic emoji tile. |
| **No search results** | See L4. |

## Data needs

### From the data pull (per saved post)

| Field | Required? | Why Learn needs it |
|---|---|---|
| `url`, `platform`, `author` | ✅ | Open the post; card byline. |
| **full `caption`** | ✅ | The only source for the title, gist, key points and the comment keyword. The 160-character cut loses lists like "5 tools: …". |
| `hashtags` | ✅ | Topic signal when the caption is thin; search. The export has them; the Muse prompt should ask for them. |
| `saved_at` | ✅ | "Newest saved first"; "saved 3 weeks ago". |
| `collections` | ⭐ | A strong topic signal ("Instruments again soon" → guitar). |
| `thumbnail_url` | ⭐ | Cards are far easier to recognize with an image. |
| `on_screen_text` + `transcript` | Later | Most tips live in the video. This is what makes Learn really good; needs the backend. |

### From extraction (LLM, per post)

| Field | Why |
|---|---|
| `lego_screen` = learn | Whether it's in Learn at all. |
| `topic_id` | Which section. |
| `title` (≤ 60 characters, in the caption's language) | Card and detail title. |
| `gist` (≤ 140 characters) | Detail sheet; search. |
| `tip_type`: tool / technique / tutorial / list / idea | Card badge. |
| `key_points[]` (0–5) | Only when the caption lists them. Never invented. |
| `cta_keyword` | "DESIGN" for comment-for-the-link posts, else empty. |
| `is_thin` | True when there's too little text to say what the tip is; the app uses the fallback title. |

### User state (on device)

`tried`, `hidden`, `topic_override` / `lego_screen_override` (from Move to…), `last_resurfaced_at`, `resurface_skipped_at`.

## Model sketch

```swift
struct Tip: Identifiable, Codable {
    let id: SavedPost.ID             // one tip per post
    var topicID: String
    var title: String
    var gist: String?
    var type: TipType                // tool, technique, tutorial, list, idea
    var keyPoints: [String]
    var ctaKeyword: String?
    var isThin: Bool
}

struct TipUserState: Codable {       // persisted separately from extracted data,
    var tried = false                // so re-running extraction never wipes it
    var hidden = false
    var topicOverride: String?
    var lastResurfacedAt: Date?
}
```

## Build notes for the coding agent

- **New files only**, in `ios/Hindsight/LegoScreens/Learn/`:
  - `Tip.swift`: `Tip`, `TipType`, `TipUserState`.
  - `LearnView.swift` (L1), `LearnTopicView.swift` (L2), `TipDetailSheet.swift` (L3), `TipCard.swift`.
  - `TipSearch.swift`: a pure function `search(_ query: String, in tips: [Tip], posts: [SavedPost.ID: SavedPost]) -> [Tip]`. No UI, fully unit-tested.
  - `TipResurfacer.swift`: a pure type that picks the daily tip, with the date and random source injected for tests.
  - `LearnStore.swift`: loads tips from the fixture, keeps `TipUserState`, persists it.
- **Depends on** (built Thursday): `Design/Theme.swift`, `Layout/LayoutConfig.swift` (`TabConfig.topicIDs` = Learn's sections), the extraction fixture JSON, and the shared Everything else button in `Layout/`.
- **Tests** (`ios/HindsightTests/LearnTests.swift`):
  - search: title matches rank above caption matches; case- and accent-insensitive; a Hebrew query matches a Hebrew title.
  - resurfacer: never picks a tried or hidden tip; never repeats within 7 days; same pick for the whole day.
  - hiding a tip removes it from sections and search.
  - user state survives reloading the fixture.
- **Previews:** every view gets a SwiftUI preview using a few tips from each seed (at least one thin, one comment-for-the-link, one Hebrew).

## ⚠️ Merge-conflict hotspots with Ariel

None beyond the ones already in the [Map spec](map.md) (its merge-conflict table): Learn also needs `hashtags`, `thumbnailURL` and `collections` on `SavedPost.swift`. Add all the new `SavedPost` fields in one commit, shared by both specs.

## Done when

- [ ] With Ariel's seed: sections for his main topics (e.g. AI tools, quant, music production); memes and ads are not in Learn.
- [ ] With Reut's seed: a Guitar section (plus design inspo, depending on the "Aesthetic coffee" answer in onboarding).
- [ ] Searching "diminished" finds the diminished-scale guitar tip; a Hebrew query finds Hebrew tips.
- [ ] Comment-for-the-link posts show the 💬 badge and the notice with the keyword.
- [ ] Thin-caption posts show a fallback title, never an empty or hashtag-only one.
- [ ] Tried it, Hide and Move to… work and survive restarting the app.
- [ ] The resurfaced tip changes daily and skips tried tips.

## Open questions

1. **Home layout:** topic sections with horizontal rows (draft, like the App Store), or one vertical list with topic chips as a filter? Rows look richer; a list is faster to scan.
2. **"Tried it":** useful for tips, or noise? It feeds the resurfacing ("don't show me what I've done").
3. **Resurfaced tip on the home screen:** keep it (draft), or save resurfacing for notifications after the MVP?
4. **Thin posts** (27% of Ariel's): show them with a fallback title (draft), or park them in Everything else until we can read the video?
