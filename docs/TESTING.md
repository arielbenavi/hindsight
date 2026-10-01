# Testing

## Automated (run these before every PR)

| Part | Command | What it covers |
|---|---|---|
| iOS app (42 tests) | `cd ios && xcodegen && xcodebuild test -project Hindsight.xcodeproj -scheme Hindsight -destination 'platform=iOS Simulator,name=iPhone 17'` | parsers (seed, Muse JSON, IG/FB/TikTok exports, WhatsApp export), SavedPost contract fields + old-data loading, store merge, onboarding model, Muse prompts/links, X PKCE + bookmarks mapping, server records |
| Connector (7 tests) | `cd connector && .venv/bin/python -m pytest -q tests` | Muse's real field names → contract, id rules = the app's, dedupe, notes, `get_sync_status`, MCP tools over HTTP, `/ingest`, `/saves`, secret-path auth, tenant isolation |
| WhatsApp bot (4 tests) | `cd whatsapp-bot && npm test` | message → posts rules (links, owner-only notes, chat as collection) |

No test calls a real API (X, Muse, Gemini, WhatsApp).

## Manual (needs a phone, Muse or WhatsApp)

Use the **logo** Hindsight app (Reut's app + our work, installed from the Mac) unless noted. The connector must be running on the Mac (with ngrok) for anything Muse/WhatsApp-bot related.

### A. Muse as a brand-new user (the important one)
**Why "fresh":** the existing Muse chat remembers earlier instructions (e.g. "only saves after Sep 28") and the old broken trycloudflare connector. Muse mixes those into new requests, which is why the first real sync sent only 2 posts. A new user has none of that.

1. **App:** 🐞 → **Restart onboarding** → Plug in your apps → **Sync with Muse** → scroll to the dev section → **Fresh Muse test (new user)**. This creates a new empty store on the server (so Muse gets a brand-new connector URL), empties the app's saves, and resets "connected".
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

### C. WhatsApp bot (once there's a bot number, see whatsapp-bot/README.md)
1. Claude starts the bot; you link it with the pairing code on the bot phone.
2. In WhatsApp: add **hindsight** to your notes group, and when asked, **share the last 100 messages**.
3. Expected: a "✅ Connected to hindsight" message in the group. Write a note and paste a link; in the app (WhatsApp notes → **Check for new notes**) they appear within seconds. The last-100 history appears too, if Baileys receives it (unverified).

### D. X
App → Plug in your apps → **X → Connect** → authorize. Expected: "N bookmarks synced".

### E. Sources page + restart
🐞 → **Sources (sync your apps)**: every card shows its status, and syncing from there works. **Run setup again** goes back to onboarding without losing saves.

### Reporting
Just say "check the log". Claude pulls the phone's debug log and the connector's `calls.log`. Screenshots for anything visual.
