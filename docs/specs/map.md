# Lego screen spec: Map

Status: draft for the MVP sprint ([mvp-sprint.md](../mvp-sprint.md)). Owner: Reut.

## The problem

We save restaurants, cafés and spots from Instagram, usually into one collection per city ("NYC Restaurants", "Brooklyn", "Argentina"). When we're actually out and hungry, the saves are useless: finding one means scrolling a collection, opening each reel, working out the place's name, then searching for it in Maps.

**The Map's job:** *"I'm out. What have I saved near here?"* Answered in under 10 seconds and 3 taps, ending in directions.

Planning a trip ("show me everything in Lisbon") is a second use, and the same screen handles it with a city filter. It isn't the design target.

## What Reut's real data tells us

From `data/ig-reut-export/` (179 posts in place-type collections):

| Finding | Example | What it means for us |
|---|---|---|
| **42% have no written clue to the place** | "Brooklyn restaurants by neighborhood !!!" (the names are only in the video) | Caption-only extraction misses almost half. We need on-screen text / transcripts, or the user confirms. The confirmation flow isn't optional. |
| **40% name the place with an @mention** | "@capponesnyc in the West Village" | The mentioned account is the strongest signal. Its display name usually is the place's name. |
| **28% use 📍** | "📍 Salt Hank's (Greenwich Village, NYC)" | Easy extraction; often the name + neighborhood, rarely a full address. |
| **Only 5% have a street address** | "📍Los Burritos Juarez - 354 Myrtle Ave" | Matching has to work from name + area, not addresses. |
| **One post, many places** | "Top 12 NYC chocolate chip cookies! 12. @orwashers 11. @gramercytavern…" | A post has 0…n places. A pin is a place, not a post. |
| **Collection ≠ place** | "Aesthetic coffee" (60 posts) is home coffee stations and interior design, not cafés | The collection name is a hint (city, vibe), never proof. Each post is judged on its own. |
| **Multilingual** | Hebrew, Korean and Spanish captions | Extraction must handle any language; place names usually stay in Latin script. |

## Scope

**In:** one Map tab; pins for every confirmed place; a nearby list; filters; a place card; been-there / want-to-go; open in Apple Maps or Google Maps; tap-through to the original post; city jump; a review list for places we couldn't match.

**Out (MVP):** sharing lists, "open now" (as far as I know, MapKit doesn't expose opening hours for filtering; verify), adding places by hand, notes, ratings, route planning, events with dates (e.g. a pop-up on Oct 3), in-app video playback (⚠️ tracked: needs platform API access).

## Screens

### M1. Map (tab root)

A full-screen map with a bottom sheet over it, like Apple Maps / Find My.

- **Opens centered on you**, zoomed to include your nearest saved places (e.g. the closest 10, max ~3 km). If nothing is within ~25 km, it opens on the city picker (M3) instead.
- **Pins:** one per place. The icon shows the type (fork and knife, cup, wine glass, bag, star). Want-to-go pins are lime, been-there pins are dimmed. Nearby pins merge into a count bubble when zoomed out.
- **Floating buttons:** locate me; city picker (shows the current city name, e.g. "NYC ▾").
- **Bottom sheet, 3 heights:**
  - *Peek:* "12 saved spots near you" + the filter chips.
  - *Half:* the nearby list (M1a).
  - *Full:* the same list, full screen.
- **Review badge:** if places are waiting for review, a small pill at the top: "5 spots need a look →" (opens M4).

### M1a. Nearby list (inside the sheet)

This is the "list view"; it isn't a separate screen.

- Rows sorted by distance: thumbnail, name, type · neighborhood, distance ("6 min walk" / "1.2 km"), a dot for been-there.
- Tap a row → the map centers on it and the place card opens (M2).
- If the map was panned, the list follows what's visible: "12 spots in this area".

### M2. Place card (sheet)

- **Top:** name (big, heavy type), type · neighborhood, distance.
- **Why I saved it:** the post thumbnail + author + a one-line reason from the caption ("the meatball hero", "thinnest crispiest pizza"). Tap → opens the post in Instagram. If several of your posts mention this place, show them all.
- **Actions (pills):** **Directions** (Apple Maps, primary), **Google Maps**, **Been there ✓** toggle.
- **More:** "Wrong place?" → re-match (M4 flow for this one place); "Hide" (removes it from the map without deleting the save).
- Apple's own place details (hours, photos, phone, website) show up when the user taps the place name, using MapKit's built-in place sheet. This gets us hours without building them.

### M3. City picker

- A list of your cities with counts ("NYC · 142", "Brooklyn · 20", "Buenos Aires · 7"), plus "Near me" at the top.
- A city comes from the matched address, not the collection name (Brooklyn is part of NYC in addresses). Group by locality.
- Picking one moves the map there and updates the sheet ("142 saved spots in NYC").

### M4. Needs review

A short list of posts where we think there's a place but couldn't match it confidently. Each row opens a single confirmation card (the same component as the post-onboarding confirmation flow; see its own spec): post on one side, best guess on the other, **Yes / No / Search** buttons.

### Filters (chips in the sheet)

- **Type:** All · Food · Café · Bakery & dessert · Bar · Other. Only types you actually have are shown.
- **Status:** Want to go (default) · Been there · All.
- **Collection:** a chip menu with your Instagram collections ("NYC Restaurants", "We love Yavan"…). This keeps the way you already organize things.

Filters apply to both the map and the list at the same time, and are remembered between launches.

## Flows

**F1. "What's near me?" (the main one).** Open the app → Map tab (or it's already there) → the sheet shows the closest spots → tap one → place card → Directions. **3 taps.**

**F2. "Coffee nearby."** Map → the Café chip → the list re-sorts → tap → Directions.

**F3. Traveling.** You land in Buenos Aires → open Map → it's already centered on you with your Argentina saves. If you open it before the trip: city picker → Buenos Aires.

**F4. After a visit.** Place card → Been there ✓ → the pin dims and it leaves the default Want to go filter.

**F5. "Why did I save this?"** Place card → thumbnail → Instagram opens on the reel.

**F6. Wrong pin.** Place card → Wrong place? → confirmation card with other search results → pick one, or "not a place" (removes the pin and moves the post to the right lego screen, or none).

## States

| State | What the user sees |
|---|---|
| **Location not asked yet** | The first time on the Map tab, a short explanation card ("See what you've saved near you") → the system prompt (When In Use). |
| **Location denied** | Map opens on your biggest city. The locate button shows a "Turn on location" hint that opens Settings. Everything else works. |
| **No saved places nearby** | Sheet: "Nothing saved around here. Your spots are in NYC (142), Buenos Aires (7)" → buttons to jump. |
| **No places at all** | An empty state explaining what gets pinned, plus a link to review posts that might contain places. (In practice, if you have no places, onboarding shouldn't have suggested a Map tab.) |
| **Matching in progress** | Pins appear as they're matched. Sheet shows "Finding 23 more spots…". |
| **Offline** | Pins and cards still show from the cache; the map tiles may be missing. Directions hand off to Maps, which handles offline itself. |

## Data needs

This is the part we send back to Ariel. Each field says who produces it and why the Map needs it.

### From the data pull (per saved post)

| Field | Required? | Why the Map needs it |
|---|---|---|
| `url` | ✅ | Tap-through to the post; the post's identity. |
| `platform` | ✅ | Which app to open; which icon to show. |
| `author` (username) | ✅ | Shown on the card ("@allie.eats"). |
| **full `caption`** | ✅ | Where most place names, 📍 and @mentions are. **The Muse prompt's 160-character cut loses them.** Top 12 lists go past 160 characters. |
| **`collections`** (names) | ✅ | City hint for matching ("Brooklyn" → search Brooklyn) and the Collection filter. The Instagram export has it; Muse doesn't ask for it yet. |
| `saved_at` | ✅ | Sorting ties; "recently saved" later. |
| **`mentions`** (tagged / @ accounts, with display names) | ✅ | The strongest place signal in 40% of posts. The display name of @capponesnyc is "Cappone's". |
| **`location_tag`** (Instagram's place tag, if any) | ⭐ strongly wanted | Instagram's own location sticker is a near-certain match. Not in the export; ask Muse for it. |
| `thumbnail_url` | ⭐ strongly wanted | The card and list rows are much easier to recognize with the image. Not in the export or the Muse prompt. |
| `on_screen_text` + `transcript` | Later | Unlocks the 42% where the place is only in the video. Needs the backend pipeline. For the MVP these go to the review list. |
| `hashtags` | Nice | Weak city/type hints (#westvillage, #nycfood). The export has them. |

### From extraction (LLM, per post)

| Field | Why |
|---|---|
| `lego_screen` = map / fitness / education / none | Whether this post goes on the Map at all ("Aesthetic coffee" posts → none). |
| `places[]` | A post can have many places. |
| `places[].name` | What we search for. |
| `places[].handle` | If the place came from an @mention; helps matching and de-duplication. |
| `places[].area_hint` | Neighborhood/city from the caption, 📍 or collection ("West Village, NYC"). Narrows the search. |
| `places[].address` | When the caption has one (5%). |
| `places[].type` | food / café / bakery & dessert / bar / other → the pin icon and filter. |
| `places[].reason` | A one-liner for "why I saved it" ("meatball hero"). |
| `places[].confidence` | high / low → low goes to the review list instead of the map. |

### From matching (MapKit, on device)

| Field | Why |
|---|---|
| `map_item_id` | MapKit's stable place identifier: reopen Apple's place sheet, and de-duplicate the same place across posts. |
| `coordinate` | The pin. |
| `formatted_address`, `locality`, `neighborhood` | Card subtitle, city picker grouping. |
| `apple_maps_url` | Directions. |
| `google_maps_url` | Built from name + address (`https://www.google.com/maps/search/?api=1&query=…`). No API needed. |
| `match_status` | auto / confirmed / rejected / manual. Decides whether it's on the map or in review. |

### User state (on device)

`visit_status` (want to go / been there), `hidden`, the filters last used.

## Sketch of the model

```swift
struct Place: Identifiable, Codable {
    let id: String                 // map_item_id once matched, else a local UUID
    var name: String
    var type: PlaceType            // food, cafe, bakery, bar, other
    var coordinate: Coordinate?
    var address: String?
    var locality: String?          // city for the picker
    var neighborhood: String?
    var appleMapsURL: URL?
    var googleMapsURL: URL?
    var matchStatus: MatchStatus   // auto, confirmed, rejected, manual, unmatched
    var sources: [PlaceSource]     // one per post that mentions it
    var visitStatus: VisitStatus   // wantToGo, beenThere
    var isHidden: Bool
}

struct PlaceSource: Codable {      // the link back to a saved post
    let postID: SavedPost.ID
    var reason: String?
    var confidence: Confidence
}
```

## Done when

- [ ] With Reut's export loaded, standing anywhere in Manhattan, the Map opens showing the nearest saved spots, and Directions is reachable in 3 taps.
- [ ] A Top-N list post produces N pins, all linking back to the same reel.
- [ ] "Aesthetic coffee" home-barista posts are not on the map.
- [ ] Low-confidence and unmatched places go to Needs review, not the map.
- [ ] Filters (type, status, collection) change the map and list together and are remembered.
- [ ] Been there dims the pin and removes it from the default filter.
- [ ] Location denied still gives a usable map.
- [ ] Apple Maps and Google Maps buttons open the right place.

## Open questions

1. **Default status filter:** hide been-there places by default, or show them dimmed? The draft hides them (Want to go is the default).
2. **Pin color:** lime for all want-to-go pins, or one color per type? Lime is louder and more on-brand; type colors are easier to scan.
3. **Thumbnails:** if we can't get `thumbnail_url` in time, do rows show the author's initial on a colored tile, or a type icon?
4. **Places from Ariel's seed:** his data has a few NYC spots (rooftops, date-night bars). Should they show on his map in the MVP? The draft says yes, same rules.
