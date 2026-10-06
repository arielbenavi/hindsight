# Data contract: from the data pull to the app

Status: v1 draft for the MVP sprint ([mvp-sprint.md](mvp-sprint.md)). Owners: Ariel (produces the data), Reut (the screens that use it).

## What this is

A recap of **all the data the app's screens need**, and **the exact format it arrives in**. The specs in [`specs/`](specs) each list their own "Data needs"; this document merges them into one list and one uniform JSON format.

- **Ariel:** configure the data pull, topic sorting and extraction to produce exactly this format, whatever the source (Muse, an Instagram/Facebook/TikTok export, X, the seed files).
- **Reut / the coding agent:** build the screens and Swift types against this format. This week a Claude agent generates a file in this format from both seed files, so the screens can be built before Ariel's pipeline is ready. When the pipeline is ready, its output replaces that file and nothing in the screens changes.

If a field is missing or shaped differently from this doc, the doc wins; fix the producer or update the doc (and bump the version).

## The pipeline and who fills what

```
1. Pull       (Ariel)   posts[]      every saved post, same shape for every source
2. Sort       (Ariel)   topics[]     groups of posts + which lego screen they belong to
3. Extract    (Ariel)   items[]      per post: the details its lego screen needs
────────────── the file this contract describes ends here ──────────────
4. Match      (app)     Map only: Apple Maps search → coordinates, address
5. Use        (app)     user state: been there, tried it, reminders…
```

Steps 4 and 5 happen inside the app and are **not** part of this file (listed at the end for completeness).

## Format rules (apply everywhere)

- **One JSON file per user**, UTF-8. For the MVP: `data/fixtures/<name>.hindsight.json`.
- **Keys are `snake_case`.** Enum values are lowercase `snake_case` strings.
- **Missing values:** `null` for a missing single value, `[]` for an empty list. **Never `""`** as a stand-in for "unknown".
- **Dates:** ISO 8601 with a timezone, e.g. `"2026-09-24T18:03:11Z"`. If only the day is known: `"2026-09-24"`.
- **Text is clean, decoded Unicode.** Fix Instagram's export encoding first (it escapes UTF-8 as Latin-1; see `data/README.md`). Keep the original language; never translate captions.
- **IDs:** a post's `id` is `"<platform>:<shortcode>"` (e.g. `"instagram:DdwJgsNABze"`), the same as `SavedPost.id` in the app today.
- **Never invent content.** Extracted fields (exercises, key points, addresses) come only from the post's text. If it isn't there, it's `null` / `[]`.
- **Unknown extra keys are ignored** by the app, so producers can add fields without breaking anything. Removing or renaming a field is a breaking change: bump `contract_version`.

## Top level

```json
{
  "contract_version": 1,
  "generated_at": "2026-10-01T09:00:00Z",
  "user": { "handle": "reut_rabin", "platforms": ["instagram"] },
  "posts": [ ... ],
  "topics": [ ... ],
  "items": [ ... ]
}
```

## 1. `posts[]`: the data pull

One object per saved post, identical in shape for every source.

| Field | Type | MVP | Used by | Notes |
|---|---|---|---|---|
| `id` | string | ✅ | everything | `"instagram:DdwJgsNABze"` |
| `platform` | `instagram` · `facebook` · `x` · `tiktok` | ✅ | all cards | Which app to open. |
| `url` | string | ✅ | all cards | The post's permalink. |
| `kind` | `reel` · `post` · `carousel` · `video` · `tweet` · `unknown` | ✅ | cards | |
| `author.username` | string | ✅ | all cards | Without the `@`. |
| `author.display_name` | string / null | ⭐ | cards | |
| **`caption`** | string / null | ✅ | Map, Learn, Fitness, confirmation | **The full caption. No 160-character cut.** Addresses, 📍, @mentions, "5 tools: …" lists and exercise lists are often past 160 characters. |
| `hashtags` | [string] | ✅ | Learn, Fitness, search | Without `#`, lowercase. |
| **`mentions`** | [{`username`, `display_name`}] | ✅ | Map | Accounts tagged or @mentioned. The strongest place signal (40% of Reut's place posts); the display name is usually the place's name ("capponesnyc" → "Cappone's"). `display_name` may be `null`. |
| **`collections`** | [string] | ✅ | Map, Learn, layout proposal | The user's saved-collection names ("NYC Restaurants"). City hint for the Map; topic hint for Learn; lets the onboarding bot say "your 'Aesthetic coffee' saves". `[]` if none. |
| `saved_at` | date / null | ✅ | Learn, Fitness, sorting | **When the user saved it.** Not the same as when it was posted. |
| `posted_at` | date / null | nice | detail sheets | When the creator posted it, if known. |
| `thumbnail_url` | string / null | ⭐ | all cards, notifications | Cards are far easier to recognize with an image. The app falls back to Apple Maps imagery / an icon when `null`. |
| `location_tag` | {`name`, `address`, `lat`, `lng`} / null | ⭐ | Map | Instagram's own location sticker, if the post has one. Near-certain place match. Any sub-field may be `null`. |
| `language` | string / null | nice | extraction | BCP 47 code of the caption, e.g. `"he"`, `"en"`. |
| `on_screen_text` | string / null | later | all | Text shown in the video. Unlocks posts whose content is only in the video (42% of Reut's place posts, 27% of Ariel's tips). |
| `transcript` | string / null | later | all | Speech in the video. Same reason. |
| `source` | `muse` · `ig_export` · `fb_export` · `tiktok_export` · `x_api` · `seed_md` | ✅ | debugging | Where this record came from. |

## 2. `topics[]`: sorting

Groups of posts, used by the onboarding chat's layout proposal ([specs/layout-proposal.md](specs/layout-proposal.md)).

| Field | Type | MVP | Notes |
|---|---|---|---|
| `id` | string | ✅ | Stable slug, e.g. `"nyc-food"`, `"guitar"`. |
| `label` | string | ✅ | Short, human: "NYC food & cafés". |
| `emoji` | string / null | nice | The app falls back to the lego screen's icon. |
| `lego_screen` | `map` · `learn` · `fitness` · `none` | ✅ | Where this topic goes. `none` = Everything else (memes, news, ads). |
| `confidence` | `high` · `low` | ✅ | `low` makes it a candidate for a question in the chat. |
| `post_ids` | [string] | ✅ | Every post in the topic. **Each post is in exactly one topic.** |
| `sample_post_ids` | [string] (3–5) | ✅ | Thumbnails in the chat; the only posts the chat's LLM sees for this topic. |
| `source_collections` | [string] | ⭐ | The user's collections this topic mostly came from. |
| `ambiguity` | object / null | ⭐ | A question the chat can ask: `{ "question": "...", "options": [{ "label": "...", "lego_screen": "map" }] }`. |

**Lego screen rules** (from the layout proposal):
- `map`: places to go (restaurants, cafés, bars, sights, shops). Any place.
- `fitness`: stretches, mobility, physical therapy, workouts. If the user has **fewer than 5** such posts, put them in `learn` instead.
- `learn`: tips, tutorials, tools, how-tos, including food/recipes (until a Recipes screen exists).
- `none`: memes, news, ads, announcements, anything not actionable.

## 3. `items[]`: extraction

One object per post whose topic isn't `none`. It carries the details for **exactly one** lego screen, matching the post's topic: `places` for `map`, `tip` for `learn`, `routine` for `fitness`. The other two keys are absent.

Shared fields:

| Field | Type | MVP | Notes |
|---|---|---|---|
| `post_id` | string | ✅ | |
| `lego_screen` | `map` · `learn` · `fitness` | ✅ | Must match the topic's. |
| `topic_id` | string | ✅ | |

### `places` (lego screen `map`): a list, a post can name several places

| Field | Type | MVP | Notes |
|---|---|---|---|
| `name` | string | ✅ | What the app searches for in Apple Maps. Prefer the mention's display name over the handle. |
| `handle` | string / null | ✅ | If the place came from an @mention. |
| `area_hint` | string / null | ✅ | Neighborhood / city from the caption, 📍, location tag or collection: "West Village, New York". Narrows the search. |
| `address` | string / null | ✅ | Only when the text has one (~5% of posts). |
| `type` | `food` · `cafe` · `bakery` · `bar` · `other` | ✅ | Pin emoji and filters. |
| `reason` | string / null | ✅ | One line on why it was saved: "the meatball hero". ≤ 60 characters, caption's language. |
| `evidence` | string | ✅ | The exact bit of text the name came from: "@capponesnyc in the West Village". Highlighted on confirmation cards. |
| `evidence_kind` | `location_tag` · `pin_emoji` · `mention` · `address` · `plain_text` · `collection_only` | ✅ | Decides whether the app places it automatically or asks. |
| `confidence` | `high` · `low` | ✅ | |

A `map` post where no place name can be found (the place is only in the video) gets `"places": []`. The app sends it to Needs review.

### `tip` (lego screen `learn`)

| Field | Type | MVP | Notes |
|---|---|---|---|
| `title` | string | ✅ | ≤ 60 characters, caption's language. Not the raw caption. |
| `gist` | string / null | ✅ | ≤ 140 characters: what the tip is. |
| **`try_prompt`** | string / null | ✅ | ≤ 100 characters, imperative, doable in ~2 minutes, based only on the caption. **The heart of the practice loop.** `null` when `is_thin`. |
| `tip_type` | `tool` · `technique` · `tutorial` · `list` · `idea` | ✅ | |
| `key_points` | [string] (0–5) | ✅ | Only when the caption lists them. |
| `cta_keyword` | string / null | ✅ | "DESIGN" for "comment DESIGN and I'll send you the link" posts. The app treats a tip with a `cta_keyword` and no `key_points` as **gated** (library only, never practiced), so don't put the "comment X" instruction in `try_prompt`. |
| `is_thin` | bool | ✅ | Too little text to tell what the tip is. |

### `routine` (lego screen `fitness`)

| Field | Type | MVP | Notes |
|---|---|---|---|
| `title` | string | ✅ | ≤ 40 characters: "Upper back release". |
| `body_areas` | [`neck` · `shoulders` · `upper_back` · `lower_back` · `hips` · `knees` · `ankles` · `core` · `full_body`] | ✅ | At least one. |
| `goal` | `pain_relief` · `mobility` · `posture` · `strength` · `recovery` | ✅ | |
| `exercises` | [{`name`, `reps`, `sets`, `hold_seconds`, `each_side`}] | ✅ | Only from the caption. Numbers `null` when not stated; `each_side` is a bool. |
| `est_minutes` | int / null | ✅ | |
| `equipment` | [`none` · `mat` · `band` · `foam_roller` · `dumbbell` · `other`] | ✅ | |
| `do_prompt` | string / null | ✅ | Like `try_prompt`. `null` when `is_thin`. |
| `is_thin` | bool | ✅ | The moves are only in the video. |
| `is_pain_related` | bool | ✅ | Shows the safety note. |

## Full example

Four posts, one of each kind, from the real seed data (captions shortened here).

```json
{
  "contract_version": 1,
  "generated_at": "2026-10-01T09:00:00Z",
  "user": { "handle": "reut_rabin", "platforms": ["instagram"] },
  "posts": [
    {
      "id": "instagram:C1aaaaaaaaa",
      "platform": "instagram",
      "url": "https://www.instagram.com/reel/C1aaaaaaaaa/",
      "kind": "reel",
      "author": { "username": "elizabethfowlerx", "display_name": null },
      "caption": "Top 3 sandwich in New York City 🥪\n\n📍 Salt Hank's (Greenwich Village, NYC)\n\n#nycfood #nyceats",
      "hashtags": ["nycfood", "nyceats"],
      "mentions": [],
      "collections": ["NYC Restaurants"],
      "saved_at": "2025-08-17T20:12:00Z",
      "posted_at": null,
      "thumbnail_url": null,
      "location_tag": null,
      "language": "en",
      "on_screen_text": null,
      "transcript": null,
      "source": "ig_export"
    },
    {
      "id": "instagram:C2bbbbbbbbb",
      "platform": "instagram",
      "url": "https://www.instagram.com/reel/C2bbbbbbbbb/",
      "kind": "reel",
      "author": { "username": "ryan.liatsis", "display_name": null },
      "caption": "Diminished scale tricks to get outside the box as we say 🎸 #guitartips #guitarlessons #diminishedscale",
      "hashtags": ["guitartips", "guitarlessons", "diminishedscale"],
      "mentions": [],
      "collections": [],
      "saved_at": "2025-03-02",
      "posted_at": null,
      "thumbnail_url": null,
      "location_tag": null,
      "language": "en",
      "on_screen_text": null,
      "transcript": null,
      "source": "seed_md"
    },
    {
      "id": "instagram:C3ccccccccc",
      "platform": "instagram",
      "url": "https://www.instagram.com/reel/C3ccccccccc/",
      "kind": "reel",
      "author": { "username": "coachgreen.pt", "display_name": null },
      "caption": "Upper back pain / knot between shoulder blades? Try this movement to improve thoracic spine mobility…",
      "hashtags": [],
      "mentions": [],
      "collections": [],
      "saved_at": "2023-11-07",
      "posted_at": null,
      "thumbnail_url": null,
      "location_tag": null,
      "language": "en",
      "on_screen_text": null,
      "transcript": null,
      "source": "seed_md"
    },
    {
      "id": "instagram:C4ddddddddd",
      "platform": "instagram",
      "url": "https://www.instagram.com/reel/C4ddddddddd/",
      "kind": "reel",
      "author": { "username": "liftlifeadam", "display_name": null },
      "caption": "Tag bro #GymMeme #FitnessHumor",
      "hashtags": ["gymmeme", "fitnesshumor"],
      "mentions": [],
      "collections": [],
      "saved_at": "2025-06-21",
      "posted_at": null,
      "thumbnail_url": null,
      "location_tag": null,
      "language": "en",
      "on_screen_text": null,
      "transcript": null,
      "source": "seed_md"
    }
  ],
  "topics": [
    {
      "id": "nyc-food", "label": "NYC food & cafés", "emoji": "🍽️",
      "lego_screen": "map", "confidence": "high",
      "post_ids": ["instagram:C1aaaaaaaaa"], "sample_post_ids": ["instagram:C1aaaaaaaaa"],
      "source_collections": ["NYC Restaurants"], "ambiguity": null
    },
    {
      "id": "guitar", "label": "Guitar", "emoji": "🎸",
      "lego_screen": "learn", "confidence": "high",
      "post_ids": ["instagram:C2bbbbbbbbb"], "sample_post_ids": ["instagram:C2bbbbbbbbb"],
      "source_collections": [], "ambiguity": null
    },
    {
      "id": "back-mobility", "label": "Back & mobility", "emoji": "🧘",
      "lego_screen": "fitness", "confidence": "high",
      "post_ids": ["instagram:C3ccccccccc"], "sample_post_ids": ["instagram:C3ccccccccc"],
      "source_collections": [], "ambiguity": null
    },
    {
      "id": "memes", "label": "Memes", "emoji": "😂",
      "lego_screen": "none", "confidence": "high",
      "post_ids": ["instagram:C4ddddddddd"], "sample_post_ids": ["instagram:C4ddddddddd"],
      "source_collections": [], "ambiguity": null
    }
  ],
  "items": [
    {
      "post_id": "instagram:C1aaaaaaaaa", "lego_screen": "map", "topic_id": "nyc-food",
      "places": [
        {
          "name": "Salt Hank's", "handle": null,
          "area_hint": "Greenwich Village, New York", "address": null,
          "type": "food", "reason": "a top-3 NYC sandwich",
          "evidence": "📍 Salt Hank's (Greenwich Village, NYC)", "evidence_kind": "pin_emoji",
          "confidence": "high"
        }
      ]
    },
    {
      "post_id": "instagram:C2bbbbbbbbb", "lego_screen": "learn", "topic_id": "guitar",
      "tip": {
        "title": "Diminished scale tricks for solos",
        "gist": "Using the diminished scale to play outside the usual box.",
        "try_prompt": "Play the diminished scale over one chord, then resolve back to the box.",
        "tip_type": "technique", "key_points": [], "cta_keyword": null, "is_thin": false
      }
    },
    {
      "post_id": "instagram:C3ccccccccc", "lego_screen": "fitness", "topic_id": "back-mobility",
      "routine": {
        "title": "Upper back knot release",
        "body_areas": ["upper_back"], "goal": "pain_relief",
        "exercises": [], "est_minutes": 2, "equipment": ["none"],
        "do_prompt": null, "is_thin": true, "is_pain_related": true
      }
    }
  ]
}
```

The meme post has a topic (`none`) but no item; the app lists it under Everything else.

*The example posts use placeholder IDs and illustrative dates; the captions come from the seed files.*

## Filled in by the app (not in this file)

For completeness; these never come from the pipeline:

- **Map matching** (Apple Maps, on the device): `map_item_id`, `coordinate`, `formatted_address`, `locality`, `neighborhood`, `apple_maps_url`, `google_maps_url`, `candidates[]`, `match_status`. See [specs/map.md](specs/map.md) and [specs/confirm.md](specs/confirm.md).
- **User state:** been there / want to go, hidden, confirmation answers, tried / did it, reminders, Regulars, weekly goals, the approved layout. See each spec.

## Changes needed on Ariel's side

What's different from the code on `master` today:

1. **Muse prompt** (`ios/Hindsight/Sync/MusePrompt.swift`): ask for the **full caption** (drop "the first 160 characters"), plus `collections`, `hashtags`, `mentions` (with display names), `saved_at` separately from `posted_at`, `thumbnail_url`, `location_tag`, and `author.display_name`. Each only if Muse can provide it; otherwise `null` / `[]`.
2. ✅ *(done 2026-09-30: Reut's export parses to 324 posts, 252 with collections)* **Instagram export parser** (`ios/Hindsight/Import/DataExportParser.swift`): Instagram's current export is a top-level array with `label_values`, plus `saved_collections.json` for collection names. Today's parser expects the older `saved_saved_media` format, so Reut's export parses to nothing. Also fix the text encoding. Reut's export in `data/ig-reut-export/` is the test file.
3. ✅ *(done 2026-09-30 by Ariel; Swift names are the contract keys in camelCase, `date` kept as computed `savedAt ?? postedAt`)* **`SavedPost`** (`ios/Hindsight/Models/SavedPost.swift`): add the new post fields as optional values with defaults, in **one** commit, so existing parsers and tests keep working. Its single `date` becomes `saved_at` + `posted_at`. Agree who makes this commit (it's a merge-conflict hotspot for both of us).
4. **Sorting** (replaces `TopicSuggester`'s keyword counts): output `topics[]` with a `lego_screen` for each, following the rules above, plus up to 2 `ambiguity` questions.
5. **Extraction:** output `items[]` in the shapes above: places, tips, routines. Never invent content; write in the caption's language.
6. **Delivery:** for the MVP, a file in this format (the one we generate this week is the reference). Later, the backend returns the same JSON.

## Proposed additions (Ariel, 2026-09-30; not yet agreed)

Additive only, so v1 readers keep working (Reut's decoder falls back to `instagram` / `unknown`):
- `platform`: `web` (any other site: articles, YouTube…) and `whatsapp` (notes with no post behind them).
- `kind`: `link` (a web page) and `note` (text the user wrote to themselves).
- `source`: `whatsapp_export` (a WhatsApp "Export chat" import).
- A `note` has no permalink, so its `url` is a stable made-up `hindsight-note:whatsapp/<time>-<hash>`. Don't open it; show the caption.

If agreed, bump `contract_version` to 2 and decide where notes and links appear in the screens.

## Changelog

- **v1** (2026-09-30): first version, merged from the Map, confirmation, layout proposal, Learn and Fitness specs.
