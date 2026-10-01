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

## Rules
- Links anyone shares become saves. Plain text becomes a **note only from the chat's owner**: the person who added the bot, or the only other person in the group. Other people's text isn't stored, since it's their personal data.
- First time in a chat, the bot posts one hello message. In groups with other people, the message explains what's saved. `SILENT=1` turns this off.
- No history: the bot only sees messages sent after it joins. Use "Export chat" for the past.

## Run it

Needs: the connector running (`connector/server.py`), and **a phone number with WhatsApp for the bot** (a cheap eSIM/second SIM works; WhatsApp Business app is fine).

```bash
cd whatsapp-bot
npm install
HINDSIGHT_INGEST_URL="http://127.0.0.1:8765/$(cat ../connector/data/token)/ingest" BOT_PHONE=15551234567 npm start
```

With `BOT_PHONE`, it prints a pairing code: on the bot phone, go to WhatsApp → Linked devices → **Link with phone number** and enter it. Without it, it shows a QR to scan from Linked devices. The login is stored in `auth/` (gitignored); delete it to re-link.

`state/groups.json` remembers each chat's name and owner. `state/outbox.jsonl` queues posts if the connector is down.

## Risks (why it's an experiment)
- **Unofficial client.** Baileys speaks the WhatsApp Web protocol, which breaks WhatsApp's terms. The *bot number* can be banned; user accounts aren't at risk, since they never log in here. Keep the bot quiet (no bulk messaging) and keep export as the fallback.
- **Consent in shared groups:** the hello message, owner-only notes, and removal is one tap.
- The official alternative (Cloud API Groups) needs a blue-tick Official Business Account and can't join existing groups. See docs/research and issue #3.

## Tests
`npm test` covers the message → posts rules (`convert.test.js`), with no WhatsApp connection needed.
