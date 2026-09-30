# Research prompt: automatic sync of a WhatsApp notes chat

Paste everything below the line into ChatGPT (deep research). Save the answer next to this file as `WHATSAPP_RESEARCH_ANSWER.md`.

---

I'm building **hindsight**, an iOS app (SwiftUI, iOS 26, US-first, App Store distribution) that collects things people save for later. Many people keep a **WhatsApp chat with themselves** for notes, links and reminders: either the built-in "Message yourself" chat, a **group they created with only themselves**, or both. I want hindsight to sync that chat **automatically, or with the fewest possible taps**, both **once for the full history** and **ongoing** (new messages).

It's September 2026. I need current (2026) facts with links, and a clear label on each claim: **verified** (docs or a first-hand report) or **speculative**.

**What we already know (don't re-explain, but correct anything wrong):**
- WhatsApp chats are end-to-end encrypted. There's no official API to read a consumer's personal or group chats.
- **Cloud API Groups API** (2026): a business can create groups and send invite links, and it receives new messages by webhook. But it needs an Official Business Account (blue tick), groups are limited to 8 participants, it can't join existing groups, and there's no history.
- A **hindsight business number** (Cloud API) can receive messages users send or forward to it. That's official, but it changes the user's habit.
- **"Export chat"** (chat → name → Export chat → Without media) gives a `.txt`/`.zip` that we already parse. It's 3 taps inside WhatsApp, and no app can trigger it.
- `wa.me/<phone>` opens a 1:1 chat. `wa.me/?text=` opens WhatsApp's "send to" picker with the text pre-typed; we plan to use it as a chat chooser and to post a `📌 hindsight sync` bookmark message.
- QR-linked-account services (Unipile, Whapi, Evolution API, whatsapp-web.js, Baileys) can read existing chats and history. But they act as an extra device logged in as the user, violate WhatsApp's terms, risk bans, and conflict with App Store guideline 5.1.1 (no off-device storage of social-network tokens). We won't ship them.
- Meta AI / Muse can only read messages that mention it or that are shared with it.

**Questions:**
1. **The local WhatsApp database on the user's own devices.**
   a. WhatsApp for **Mac** (native Catalyst app): where is the chat database stored (e.g. `~/Library/Group Containers/group.net.whatsapp.WhatsApp.shared/ChatStorage.sqlite`)? Is it readable by another app the user installs (full-disk access, sandbox, encryption at rest)? What's the schema for messages, chats and groups? Could a small **Mac companion app** (outside the App Store, or in it) read one chosen chat and sync new messages automatically? What are the ToS and security implications of reading the user's *own* local data on their *own* machine?
   b. **iPhone backups**: a local Finder/iTunes backup (encrypted or not) contains `ChatStorage.sqlite`. Can a Mac app read it with the user's permission? Can iCloud WhatsApp backups be read at all (they're end-to-end encrypted by default now?)?
   c. WhatsApp **Windows** / **WhatsApp Web** local storage (IndexedDB): same questions, briefly.
2. **iOS automation**: can **Shortcuts** (personal automations, Share Sheet actions, App Intents) do any part of "open this chat → export → send to hindsight"? Does WhatsApp expose any App Intents or Shortcuts actions in 2026? Can a hindsight App Intent receive a WhatsApp export automatically from a user-built Shortcut?
3. **Official or partner routes**: any 2026 WhatsApp feature for exporting or syncing a chat to another app (Digital Markets Act interoperability in the EU, the Data Transfer Initiative, "Chat transfer", third-party chat interop, account data export "Request account info")? What does "Request account info" / DYI include for WhatsApp in 2026: message content or only metadata?
4. **Notes-to-self specifically**: does WhatsApp have a dedicated notes, "saved messages" or "starred messages" feature with any export or integration? Are starred messages exportable?
5. **Business-number approaches that feel invisible**: e.g. the user adds hindsight's number to their notes group once (is that possible for a *consumer* group with a Cloud API number in 2026?), or a hindsight-created group that *replaces* their notes group. What's the real friction, and what are the limits?
6. **How other apps do it**: any app (notes, read-later, CRM, AI assistants, "second brain" apps like Mem, Tana, Reflect, Readwise, Heyday) that syncs WhatsApp chats in 2025–2026. Exactly how, officially or not?
7. **Risk**: for each approach, App Store review risk, WhatsApp/Meta ToS risk (account bans), and privacy law (other people's messages in groups).

**Deliverable:** a table of every approach (initial history, ongoing, taps per sync, reliability, ToS/App Store risk, iOS/Mac/Android, build effort), a recommended design for launch, the best "power user" option (e.g. a Mac companion), and experiments to run on a real iPhone/Mac to confirm the unknowns.
