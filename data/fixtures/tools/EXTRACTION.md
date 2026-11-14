# Extraction instructions (per-post pass)

You classify saved Instagram posts for the Hindsight app and extract the details its screens need. The authoritative format is `docs/data-contract.md` (sections 2 and 3). This file is the per-post pass; topics are consolidated afterwards from your `topic_hint`s.

## Input

A JSON list of posts: `id`, `author`, `author_name`, `caption`, `hashtags`, `mentions` (username + display_name), `collections` (the user's own saved-collection names; a strong hint, never proof).

## Output

Write **one JSON array** (valid JSON, UTF-8, no comments, no trailing commas) to the output path you were given, one object per input post, same order:

```json
{"post_id": "instagram:XYZ", "lego_screen": "map|learn|fitness|none", "topic_hint": "nyc-food", "topic_label": "NYC food & cafés", "places": [...]}
```

- `topic_hint`: a short kebab-case slug for the group this post belongs to, as a person would name a section of their saves. Reuse the same slug for similar posts. Keep them **broad** (aim for 5–15 slugs per batch, not one per post). Suggested slugs (use when they fit, invent when not): `nyc-food`, `nyc-cafes`, `brooklyn-spots`, `travel-argentina`, `travel-spots`, `guitar`, `music-production`, `ai-tools`, `coding`, `quant-finance`, `design-inspo`, `home-coffee-setups`, `cooking-recipes`, `productivity`, `career`, `back-mobility`, `workouts`, `memes`, `news`, `ads-promos`.
- `topic_label`: human label for the slug (≤ 30 chars).
- Exactly **one** of `places` / `tip` / `routine`, matching `lego_screen`. For `none`, none of them.
- **Fitness posts also get a `tip`** (in addition to `routine`), because users with fewer than 5 fitness posts get them in Learn instead.

### Which lego screen

- `map`: the post is about **a specific place (or places) to go**: restaurant, café, bakery, bar, shop, sight, venue, hotel, neighborhood spot. Any city. A food/cafe collection alone doesn't make it map: judge the post itself. Home coffee stations, interiors and product shots are **not** map.
- `fitness`: stretches, mobility, physical therapy, posture, workouts, exercise routines. Gym **memes/jokes are `none`**. Food/nutrition/recipes are `learn`.
- `learn`: tips, tutorials, tools, how-tos, techniques, recipes, song tutorials, design/interior inspiration the user could apply, useful knowledge.
- `none`: memes, jokes, news, announcements, ads, personal/lifestyle posts, motivation quotes, anything not actionable. When unsure between `learn` and `none` for low-substance posts, pick `none`.

### `places` (map): a list; a "Top 12" post has 12 entries

| field | rules |
|---|---|
| `name` | The place's real name as you'd search it in Apple Maps. From an @mention, prefer a readable name ("capponesnyc" → "Cappone's"). |
| `handle` | The @username (no `@`) if the place came from a mention, else `null`. |
| `area_hint` | Neighborhood / city from caption, 📍 or collection, e.g. "West Village, New York". Collection city ("NYC Restaurants" → "New York", "Brooklyn" → "Brooklyn, New York", "Argentina" → "Argentina") when the caption has none. `null` if nothing. |
| `address` | Only if the text has a street address. Else `null`. |
| `type` | `food` · `cafe` · `bakery` (bakery & dessert) · `bar` · `other` |
| `reason` | ≤ 60 chars, caption's language: why it was saved ("the meatball hero"). `null` if nothing. |
| `evidence` | The **exact substring** of the caption the name came from (copy it verbatim, ≤ 120 chars). If only from the collection: the collection name. |
| `evidence_kind` | `pin_emoji` (📍) · `mention` (@) · `address` · `plain_text` · `collection_only` |
| `confidence` | `high` if the name is explicit and unambiguous, else `low`. |

If it's clearly a place post but **no place name is in the text** (it's only in the video), use `"places": []`.

### `tip` (learn; also on fitness posts)

| field | rules |
|---|---|
| `title` | ≤ 60 chars, caption's language. **Not** the raw caption: what the tip is ("Diminished scale tricks for solos"). |
| `gist` | ≤ 140 chars, what the tip is. `null` if thin. |
| `try_prompt` | ≤ 100 chars, imperative, doable in ~2 minutes, **only from what the caption says**. Never invent steps or facts. `null` if `is_thin`. For comment-for-the-link posts: "Comment DESIGN on the post to get the 5 tools." For song tutorials: "Learn the first riff of Sparks." |
| `tip_type` | `tool` · `technique` · `tutorial` · `list` · `idea` |
| `key_points` | 0–5 strings, **only** if the caption itself lists them. Else `[]`. |
| `cta_keyword` | The keyword for "comment X and I'll send you…" posts, else `null`. |
| `is_thin` | `true` if there's too little text to tell what the tip is. |

### `routine` (fitness)

| field | rules |
|---|---|
| `title` | ≤ 40 chars ("Upper back release"). |
| `body_areas` | ≥ 1 of `neck` `shoulders` `upper_back` `lower_back` `hips` `knees` `ankles` `core` `full_body` |
| `goal` | `pain_relief` · `mobility` · `posture` · `strength` · `recovery` |
| `exercises` | `[{"name","reps","sets","hold_seconds","each_side"}]` **only** as listed in the caption; numbers `null` when not stated; `each_side` bool. `[]` if none listed. |
| `est_minutes` | int or `null` |
| `equipment` | list of `none` `mat` `band` `foam_roller` `dumbbell` `other` |
| `do_prompt` | like `try_prompt`; `null` if thin. |
| `is_thin` | the moves are only in the video. |
| `is_pain_related` | bool |

## Hard rules

- **Never invent content.** Names, exercises, key points, addresses come only from the given text.
- Missing values are `null` (single) or `[]` (list). **Never `""`.**
- Enum values exactly as listed, lowercase.
- Keep the caption's language (Hebrew stays Hebrew, etc.). Don't translate.
- Every input post appears exactly once in the output.
- Validate your file parses as JSON before finishing (e.g. `python3 -c "import json;json.load(open(PATH))"`), and check the count matches the input.
