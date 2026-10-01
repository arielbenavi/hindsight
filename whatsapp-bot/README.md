# WhatsApp bot (experiment)

A dedicated **hindsight WhatsApp account** that users add to their notes chat: a group with themselves, or just a 1:1 chat with the bot. After that, every new message there lands in hindsight with no export and no forwarding. The other WhatsApp path, "Export chat" import, stays for history and as the fallback.

```
user adds "hindsight" to their notes group (once)
        ↓
bot.js (Baileys, linked device of OUR bot account)
        ↓  new message
convert.js → contract posts (links → saves, owner's text → notes, chat name → collection)
        ↓
connector /ingest  (same store Muse writes to; deduped)
        ↓
app pulls /saves
```

## How a user connects (the app's WhatsApp screen)
1. **Open the hindsight chat:** the app opens `wa.me/<bot>` with "Hi hindsight 👋 connect code: <tenant>" typed in; the user taps send. The bot links that phone number to the app's store (`state/links.json`) and replies with what to do next.
2. **Save hindsight to contacts** (iOS New Contact card, prefilled), so it shows up in "Add members".
3. Where they write notes:
   - **Chat with myself:** WhatsApp's self-chat can't take a third member, so the hindsight chat *becomes* their notes chat (pin it).
   - **A group:** add hindsight to it.
4. **Old notes:** Export chat → Without media → share to WhatsApp → hindsight. The bot reads the zip (`exportParser.js`, same rules and note ids as the app's parser) and replies "✅ Imported N links and M notes".

Messages from people who never sent a connect code go to the default store.

## Rules
- Links anyone shares become saves. Plain text becomes a **note only from the chat's owner**: the person who added the bot, or the only other person in the group. Other people's text isn't stored, since it's their personal data.
- First time in a chat, the bot posts one hello message. In groups with other people, the message explains what's saved. `SILENT=1` turns this off.
- History: when adding the bot to a group, WhatsApp (2026) offers to **share the last 25–100 messages from the past 14 days**. Pick "Last 100", and the bot imports those too (via `messaging-history.set`; not yet verified with Baileys). Anything older needs the one-time "Export chat" import.

## Run it

Needs: the connector running (`connector/server.py`), and **a phone number with WhatsApp for the bot** (a cheap eSIM/second SIM works; WhatsApp Business app is fine).

```bash
cd whatsapp-bot
npm install
HINDSIGHT_INGEST_URL="http://127.0.0.1:8765/$(cat ../connector/data/token)/ingest" BOT_PHONE=15551234567 npm start
```

With `BOT_PHONE`, it prints a pairing code: on the bot phone, go to WhatsApp → Linked devices → **Link with phone number** and enter it. Without it, it shows a QR to scan from Linked devices. The login is stored in `auth/` (gitignored); delete it to re-link.

`state/groups.json` remembers each chat's name and owner, `state/links.json` maps phone numbers to hindsight stores, and `state/outbox.jsonl` queues posts if the connector is down.

### On the Mac (current setup)
`./install-launchd.sh` installs two launch agents: the bot (`run.sh`, restarted if it crashes, started at login) and `healthcheck.sh` every 2 days. The check appends a line to `state/health.log` (running? linked? last connect/message, days since the bot phone was opened) and shows a Mac notification when something needs a person.

**After opening WhatsApp on the bot phone, run `./healthcheck.sh opened`.** That's how the log tests the "linked devices are logged out after ~14 days without the phone" assumption: if a logout ever happens, the log shows how long the phone had been away.

## Getting the bot a number (done 2026-10-01: Tello eSIM + WhatsApp Business on a spare phone, named "hindsight" with the app icon as photo)
- **Use a new number only for the bot,** not an existing WhatsApp/WhatsApp Business account. If WhatsApp bans the bot, only that number is lost.
- **Cheapest:** a **Tello** eSIM ("build your own" plan, about $5/mo; activates online in ~5 min). It only has to receive one SMS to register WhatsApp, and the bot itself runs on our server, so the line needs no data. Adding a line to Mint (Mint Family) works too, but costs ~$15/mo. Avoid Google Voice and other virtual numbers (WhatsApp often rejects them).
- **The bot account needs a "primary" WhatsApp somewhere:** Baileys runs as a *linked device*, and WhatsApp wants the primary to come online about every 14 days. Ariel's iPhone already uses WhatsApp (Israeli number) and WhatsApp Business (US number), so put the bot account on a **spare phone** (any old iPhone/Android on Wi-Fi), or as a second account if WhatsApp offers "Add account" on that phone.


## Risks (why it's an experiment)
- **Unofficial client.** Baileys speaks the WhatsApp Web protocol, which breaks WhatsApp's terms. The *bot number* can be banned; user accounts aren't at risk, since they never log in here. Keep the bot quiet (no bulk messaging) and keep export as the fallback.
- **Consent in shared groups:** the hello message, owner-only notes, and removal is one tap.
- The official alternative (Cloud API Groups) needs a blue-tick Official Business Account and can't join existing groups. See docs/research and issue #3.

## Tests
`npm test` covers the message → posts rules (`convert.test.js`) and chat-export parsing (`exportParser.test.js`), with no WhatsApp connection needed.
