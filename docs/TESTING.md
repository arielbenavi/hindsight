# Testing

## Automated (run these before every PR)

| Part | Command | What it covers |
|---|---|---|
| iOS app (211 tests) | `cd ios && xcodegen && xcodebuild test -project Hindsight.xcodeproj -scheme Hindsight -destination 'platform=iOS Simulator,name=iPhone 17'` | parsers (seed, Muse JSON, IG/FB/TikTok exports, WhatsApp export), contract + old-data loading, store merge, sort engine (topics for every save, Unsorted, old caches, imports during a run), Today (picks by state/job/reminder, resume, one more, notification times, an empty set re-picked once saves arrive, sorting empty state, sent saves quiet for 30 days), save states, topic jobs (default mapping incl. Hebrew, overrides, moves), Keep close needs, Do lists, Ask filters, Topics, layout, Map matching, Learn/Fitness/practice, onboarding, Muse prompts/links + "Open Muse" browser fallback, server account URL rules + pull throttle, X PKCE + bookmarks, **destinations** (which apply per job/content, ingredient parser EN/HE + no-list fallback, dates in captions, Markdown, Reminders dedupe + denial with the in-memory writer, auto-route once only, older state files still decode), **in-app player** (`EmbedURL` for every Instagram/TikTok/X/YouTube/Facebook link shape, short links and notes → none, dead-end page text, player sizes, the Sources switch deciding what "Open it" does) |
| Connector (14 tests) | `cd connector && python3 -m venv /tmp/hs-venv && /tmp/hs-venv/bin/pip -q install -r requirements.txt pytest && /tmp/hs-venv/bin/python -m pytest -q tests` | Muse's real field names → contract, id rules = the app's, dedupe, notes, `get_sync_status`, MCP tools over HTTP, `/ingest`, `/saves`, secret-path auth, tenant isolation, bot number route, search/recent, **assistant-search consent** (`…/settings`, off by default, the owner's existing account kept on, notes never returned) |
| WhatsApp bot (11 tests) | `cd whatsapp-bot && npm test` | message → posts rules (links, owner-only notes, chat as collection, share-tracking params), chat-export parsing (iOS/Android formats, zip, note ids identical to the app's) |

No test calls a real API (X, Muse, Gemini, WhatsApp).

## Manual: the app (simulator is fine)

Fresh install each time: `xcrun simctl uninstall booted com.reutrabin.hindsight`, then install the build from
`xcodebuild -showBuildSettings` → `BUILT_PRODUCTS_DIR` (not a DerivedData glob: stale folders exist).

1. **Onboarding → Today:** Welcome → How it works → Plug in your apps → "Just looking? Try it with sample saves" →
   You're in → **Open hindsight**. Lands on the **Today** tab; tab bar shows Today · Library · Ask.
2. **Today card:** weekday + "Today", "1 of 3" with a 3-segment bar, one big card (picture or platform tile, reason
   like "SAVED 1 YEAR AGO TODAY", @author · kind, caption, topic chip), two cards peeking behind, buttons not under
   the tab bar. Not anymore / Did it / Open it each move on (swipe left/right does the same). Open it opens the post.
3. **Resume:** answer one, kill and relaunch → still "2 of 3", same cards. 🐞 → **New Today set** starts over.
4. **That's today.:** after 3 — the three outcomes, "New since yesterday" only if something was saved since
   yesterday, **One more** adds a 4th card, footnote "Three new ones tomorrow at 9:00". The notification
   permission prompt shows **now** (first finished set), never at launch.
5. **Eligibility:** Keep close / Look / Know topics never show in Today; done and let-go saves never come back.
6. **Library:** sections Go, Do, Learn, Keep close, Look, Know (empty ones hidden), each with symbol + one line;
   counts "62 saves · 41 places" (Go), "34 saves · 6 done" (Do); Keep close is a calm lavender card with no counts.
   At the end: "N saves still need a home", All saves, Let go (once something is let go). Search works. Nothing
   scrolls under the status bar.
7. **Job picker:** a topic → "…" → **What is this for?** → six jobs with descriptions, "Suggested" badge, current one
   checked; "Make it X" changes the page's shape right away and moves it to its new Library section.
8. **Do list:** progress "N of M done", To do / Done chips, 44pt round checks (done rows struck through, at the
   bottom), **Pick one for tonight** opens a not-done save's detail.
9. **Look board:** two uneven columns of tiles with author pills; tap → detail.
10. **Keep close:** darker background, lavender, "Private · never in Today or notifications", four needs; a need shows
    up to 3 saves (big quote card + rows), **Show me another** moves on, "All N" lists them; opening one twice shows
    "You've come back to this 2 times".
11. **Save detail:** meta line, topic chip + **Move**, Open in <Platform>, I did this, Remind me (Tonight / Weekend;
    hidden for Keep close saves), Add a note, Not interested anymore ↔ Bring it back; footer "Shown in Today N
    times. Opened …".
12. **Ask:** "What were you looking for?"; a query matches captions, authors, hashtags, topic names and your notes
    ("Your note" / "Topic:" tags); chips Never opened / Saved this month / Done / Let go / Notes.
13. **Views:** Map / All tips / Workouts buttons next to their sections; open each and come back (back button and
    edge swipe, also on the Map). Tips / Workouts first open: the normal screen with a "Make Tips yours" card;
    nothing opens on its own.
14. **Own saves:** onboarding 🐞 → **Load seed saves** → Start with 1,216 saves → Today shows at once (its set is
    remade once if sorting moves a pick into a Know/Look topic before you answer), Library's "Sorting your
    saves…" strip counts up, topics fill in; **Mental health** shows under Keep close.
15. **Sample → own saves:** start with the sample, then gear → Sources → import something → close Sources: the
    app switches to your saves on its own.
16. **Pull on launch / foreground** (connector running): launch with `-museConnectorBaseURL https://<host>/<token>`;
   `connector/data/calls.log` shows `tenant_created` once, then `app_pull` for that tenant. POST a post to
   `/<token>/t/<tenant>/ingest`, leave the app > 1 min, come back: it shows in Library (All saves), and gets sorted.
17. **One account per install:** relaunch with the same argument: no second `tenant_created`. DEBUG reset: Sources →
   Sync with Muse → **Fresh Muse test (new user)** (new account, local saves emptied).
18. **Destinations** (after 14): 🐞 → **Add destination test saves** (recipes, places, events with a date ahead, films;
   two of them saved on this day 1 and 2 years ago). Then:
   - Food & recipes → "Crispy miso pasta" → **Send to: Add ingredients to Groceries · 5 ingredients**. First tap asks
     for Reminders (copy: "hindsight adds the lists you choose…"); Allow → "Added to Groceries · 5 items" and the row
     becomes **In Groceries · <date>**. A recipe with no list says **Add to Groceries** ("adds the recipe").
   - Places → "Rooftop jazz night" → **Open in Maps** (+ Google) and **Add to Calendar · Sat, 5 Dec at 20:00** →
     Apple's New Event sheet prefilled (title, time, location, link); ✓ → **In Calendar**. Cancel changes nothing.
   - Ask "Perfect Days" → **Add to Watchlist** and **Export as Markdown** (share sheet with a .md file).
   - Keep close saves show no Send to at all; a caption saying "today" never offers Calendar.
   - 🐞 → **New Today set**: card 1 (L'Industrie) shows **Open in Maps** inside the card's bottom; tapping it opens
     Maps and moves on ("Sent" in That's today.). Card 2 (Shakshuka) **Add to Groceries** → toast "Added to Groceries ·
     4 items". The three round buttons stay above the tab bar.
   - Topic "…" → **Send all to…** → Reminders list / Markdown, each confirmed with a count first; a second run says
     "Already in …".
   - Topic "…" → What is this for? → **Send new saves here automatically** (off by default) + list → Save. New saves
     sorted into that topic later are added once, on foreground or after a sync.
   - Reminders app (simulator): the lists hold the items (Groceries 9 after the two recipes, no duplicates).
   - 🐞 → **Preview Today while sorting**: "Sorting your saves… Today's three will be ready in a moment."
19. **Use your saves in Claude** (Sources, bottom): off by default, only the switch. Turning it on asks first (captions,
   transcripts, links; never notes); with a server, `calls.log` shows `settings … assistant_search: true` and the card
   shows the connector address + Copy. With the server unreachable the switch goes back off with a message.
20. **Muse sheet**: Sources → **Connect with Muse** (primary; the Meta file import is the quiet link under it). The sheet
   says "One-time setup…"; **Open Muse** in the simulator (no Muse app) opens muse.ai in Safari, and back in the app
   the sheet says **Message copied. Open Muse and paste it.**
21. **In-app player** (after 14, simulator with network): Today → **Open it** (play icon) opens the player sheet:
   the Instagram embed on top (reels 9:16, posts wider), @author + our caption, **I did this** / **Not interested**
   (+ the save's one destination), ✕ and ↗ (Open in Instagram) in the top bar. Tap the video: it plays inline.
   **I did this** closes the sheet and the card moves on ("Did it"); just closing counts "Opened". "View more on
   Instagram" inside the embed leaves for Safari/Instagram instead of navigating the player. Library → a save →
   **Watch here** (or tapping the picture) turns the picture into the player in place; **Open in Instagram** is the
   text link under it; a web link says **Read here**. Gear → Sources → Viewing → turn **Play saves inside hindsight**
   off: "Open it" shows ↗ again and opens Instagram/Safari like before. A removed post shows **Can't play this one
   here** + Open in <Platform>.

## Manual: phone (needs a phone, Muse or WhatsApp)

Use the **logo** Hindsight app (Reut's app + our work, installed from the Mac) unless noted. The connector must be running on the Mac (with ngrok) for anything Muse/WhatsApp-bot related.

### A. Muse as a brand-new user (the important one)
**Why "fresh":** the existing Muse chat remembers earlier instructions (e.g. "only saves after Sep 28") and the old broken trycloudflare connector. Muse mixes those into new requests, which is why the first real sync sent only 2 posts. A new user has none of that.

1. **App:** 🐞 → **Start onboarding over** → Plug in your apps → **Sync with Muse** → scroll to the dev section → **Fresh Muse test (new user)**. This replaces the install's account with a new empty one on the server (so Muse gets a brand-new connector URL), empties the app's saves, and resets "connected".
2. Nothing to do in Muse by hand: the message tells Muse to **replace any old "hindsight" connector** and **ignore earlier hindsight messages** in the chat. (If Muse still mixes things up, start a new Muse chat. That's worth noting as a finding.)
3. Onboarding → Plug in your apps → **Sync with Muse** → **Open Muse** → paste → send → **"Always allow this site"**.
4. Expected: Muse calls `get_sync_status` (total 0), then `submit_saved_posts` in batches of ≤50 until done, then confirms a **daily 9am routine**. Back in hindsight, it shows "+N saves arrived from Muse".
5. Tell Claude "check the log": it reports number of batches, total received, platforms (Facebook?), caption lengths, collections.
6. **Next day ~9am:** did the routine fire on its own? `calls.log` shows it. Needs the Mac awake + ngrok up overnight (or real hosting).

### B. WhatsApp: past notes (export)
1. App → Plug in your apps → **WhatsApp notes → Import**.
2. Follow the animation: notes chat → tap its name → Export chat → **Without media** → Save to Files → back → **Choose the export file**.
3. Expected: "+N new saves · X links and Y notes". **Re-import the same file:** "Nothing new since last time".
4. Time it (the reason we're testing this path).

### C. WhatsApp: connect + new notes (bot is live on the Mac)
1. App → Plug in your apps → **WhatsApp notes → Connect** → **Open WhatsApp** → tap send.
   Expected: the bot replies "✅ Connected to hindsight…" (bot.log: `linked <number> → <tenant or main>`).
2. **Save hindsight to my contacts** → the New Contact card has the name, number and logo → save.
3. **Chat with myself:** send a note and a link in the hindsight chat. **A group:** add hindsight to a notes group (if offered, share the **Last 100** messages; tell Claude, since this is unverified).
4. Back in the app: **Check for new notes** → they appear within seconds.
5. Privacy: someone else in a group sends a note and a link → their link is saved, their note isn't.

### F. WhatsApp: old notes → send the export to hindsight
1. In WhatsApp: your old notes chat → its name → **Export chat** → **Without media** → in the share sheet pick **WhatsApp** → **hindsight** → send.
   (Unverified: whether WhatsApp offers itself in that share sheet. If not, Save to Files and attach the file in the hindsight chat with **+ → Document**, or use the app's "Or choose an export saved in Files".)
2. Expected: the bot replies "✅ Imported N links and M notes"; **Check for new notes** shows them. Sending the same file again adds nothing new.
3. Time it.

### D. X
App → Plug in your apps → **X → Connect** → authorize. Expected: "N bookmarks synced".

### G. Destinations on a real phone (Reminders, Calendar, Maps)
1. A recipe save → **Add ingredients to Groceries** → allow Reminders → open the Reminders app: a **Groceries** list
   (made if it wasn't there; in your default account, so it syncs to iCloud) with one item per ingredient and the post
   link. Tap again in hindsight → "Already in Groceries", nothing duplicated.
2. Deny Reminders once (Settings → Privacy → Reminders → hindsight off) → the tap shows "hindsight can't add to
   Reminders" with **Open Settings**, which lands on hindsight's settings page.
3. A save with a date ahead → **Add to Calendar** → Apple's sheet → Add → it's in the Calendar app. No Calendar
   permission prompt should ever appear (iOS 17+ write-only sheet).
4. **Open in Maps** opens Apple Maps on the place; **Google** opens Google Maps if installed, else the web.
5. Auto-route: turn it on for a topic, sync new saves that land there (Muse / seed), background + foreground the app →
   they appear in the chosen list once.
6. Inside LiveContainer: **Open Muse** should open Safari on muse.ai (which offers the Muse app); the sheet says the
   message was copied.

### E. Sources page + restart
Home's gear → **Sources**: every card shows its status, and syncing from there works. **Run setup again** goes back to onboarding without losing saves.

### Reporting
Just say "check the log". Claude pulls the phone's debug log and the connector's `calls.log`. Screenshots for anything visual.
