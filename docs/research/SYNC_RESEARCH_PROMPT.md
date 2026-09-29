# Research prompt: the smoothest way to sync saved posts

Paste everything below the line into ChatGPT (deep research mode) or another
research agent. Save the answer next to this file as `SYNC_RESEARCH_ANSWER.md`.

---

I'm building **hindsight**, an iOS app (SwiftUI, iOS 26) that pulls a user's **saved/bookmarked posts** from Instagram, Facebook, X and TikTok into one place, then organizes and resurfaces them. It's September 2026. I need the **smoothest possible way to sync each user's saves**: ideally one tap, then automatic, and it must be App Store-safe and not break platform terms.

**What we already have and have verified:**
- **X:** OAuth 2.0 PKCE (public "Native App" client) plus `GET /2/users/:id/bookmarks`. It works: one tap, pay-per-use. The API caps at 800 bookmarks.
- **Instagram + Facebook:** no official API for saved posts. Cookie scraping of IG's private API works but is fragile, and FB scraping is fully blocked. Our current path is **Meta Muse** (Meta's AI agent, launched Sep 2026). Its built-in Instagram connector can read saved posts. We open `https://muse.ai/chat` (a universal link into the Muse app, `com.facebook.hatch`), the user pastes our prompt, Muse replies with a JSON list, and the user copies it back into our app. That's roughly 5 manual steps and about 100 posts per reply. `?q=` does not prefill the chat. Muse supports MCP connectors (custom per-user, or directory-listed after Meta review via muse.ai/platform).
- **TikTok:** Data Portability API is EEA/UK-only. Login Kit/Display API gives only the user's own posts. Research API is academics-only. We can parse the "Download your data" export (JSON, 1–3 day wait).

**Questions. For each, give concrete, current (2026) evidence with links, and say what's verified vs. speculative:**

1. **Muse:** What's the best way to make this near-zero-effort?
   a. Is there any documented or observed way to open the Muse app with a prompt pre-filled (URL params, share sheet/share extension, App Intents/Shortcuts, Siri)?
   b. If we build an MCP connector (for example a tool `submit_saved_posts`), can Muse be told to call it and push the user's saved posts to our server? What are the auth, rate and size limits?
   c. Can a directory connector be triggered on a schedule or by the user from Muse ("sync my saves to hindsight every day")?
   d. How do other apps built on Muse connectors handle onboarding, and how long does Meta's review take?
2. **Instagram/Facebook without Muse:** any official or partner API in 2026 that exposes a user's saved posts or collections? Any data-portability APIs from Meta (DMA/DTI "Data Transfer Initiative") that a third party can receive exports through, and in which regions?
3. **TikTok for US users:** any legitimate way to read a user's favorites/likes (partner programs, new APIs, DTI transfers, Login Kit scopes added in 2025–2026)? How do existing apps (bookmark managers, "read later", "TikTok recipe" apps) do it?
4. **iOS share extension as the universal capture path:** best practices for a share extension that accepts links from Instagram, TikTok, X, Facebook and Safari. What does each app actually put in the share sheet (URL vs. text vs. both)? App Group storage, background upload, and UX patterns from apps like Pocket/Matter/Raindrop/Readwise.
5. **Backfill vs. ongoing sync:** for each platform, what's the most realistic "import everything once" path, and the most realistic "keep up automatically" path?
6. **Comparable products:** who else aggregates saved posts across platforms in 2025–2026 (e.g. Mymind, Recall, Glasp, Raindrop, Dewey, Saved, "Sortd"…)? Exactly how does each get the data? Screenshot-level detail on their onboarding if available.
7. **Risks:** App Store review guidelines, and Meta/TikTok/X terms that constrain each approach. What gets apps rejected or banned?

**Deliverable:** a table per platform (path, user effort in taps, reliability, legality/ToS risk, US availability, effort to build), then a recommended sync architecture for launch, and a list of experiments we should run on a real iPhone to confirm the unknowns.
