# Instagram Cookie Refresh Workflow

Documented from live walkthrough on 2026-09-25.
Goal: collect step-by-step UX observations for building a guided setup assistant.

## Prerequisites
- Chrome browser
- "Get cookies.txt LOCALLY" extension installed
  - Chrome Web Store: https://chromewebstore.google.com/detail/get-cookiestxt-locally/cclelndahbckbenkjhflpdbgdldlbecc
- User logged into Instagram in Chrome

## Workflow Steps

### Step 0: Verify IG login
- Navigate to instagram.com
- **Surprise:** If user is logged out, the page shows a login form — NOT the feed
- The extension will export cookies regardless, but without `sessionid` they're useless
- **Detection:** Check for login form vs feed. Feed has `[role="main"]` with posts
- **Fallback:** User must log in manually (credentials can't be automated)

### Step 1: Open the extension
- Click the Chrome extensions puzzle icon (top-right toolbar)
- Find "Get cookies.txt LOCALLY" in the dropdown
- **Surprise:** TBD — need to document popup behavior
- **Alternative:** If pinned, click the cookie icon directly in toolbar

### Step 2: Export cookies
- In the extension popup:
  - Select "Current Site" (should show instagram.com)
  - Click "Export" or "Get cookies.txt"
- **Output format:** Netscape cookies.txt (tab-separated)
- **Surprise:** TBD — does it download a file or copy to clipboard?

### Step 3: Save to correct path
- Target: `~/.savefeed/cookies.txt`
- **Surprise:** Browser downloads go to ~/Downloads by default
- Need to either:
  a. Move the downloaded file, OR
  b. Copy text from extension popup and write to file
- **Automation opportunity:** Claude can handle the file move/write

### Step 4: Verify
- Hit `/sweep/dry-run` to confirm cookies are valid
- Check for `sessionid` presence
- Test API probe (lightweight IG API call)

## Surprises & Edge Cases (append as discovered)

1. **User not logged in** — extension exports empty/useless cookies
2. **Multiple IG accounts** — extension exports whichever account is active
3. **Cookie expiry** — ~90 days from export date
4. **Private/incognito** — extension may not work in private windows
5. **Chrome IG login blocked** — Instagram shows captcha/anti-bot when logging in via Chrome that Claude controls. User had to export from a separate browser session (Safari or manual Chrome) instead.
6. **Extension exports ALL cookies** — 7372 lines, not just instagram.com. File includes cookies from all sites. The parser filters for `instagram.com` domain so this is fine, but the file is large (~200KB vs ~1KB if filtered).
7. **Download path** — extension saves to `~/Downloads/cookies.txt` by default. Claude must copy to `~/.savefeed/cookies.txt`.
8. **Multiple sessionid entries** — file had 4 sessionid matches (likely different subdomains/paths). Parser picks them all but only one is used.

## Automation Limits
- Cannot click Chrome extensions via browser MCP (extension popups are outside page DOM)
- Cannot enter credentials (security constraint)
- Cannot bypass IG captcha/anti-bot on login
- CAN: navigate to IG, detect login state, move/write cookie files, verify via dry-run
- CAN: detect ~/Downloads/cookies.txt and auto-copy to correct path

## Recommended Setup Flow for End Users
1. Assistant checks cookie freshness via dry-run
2. If expired/missing: show overlay with instructions
3. User logs into IG in their own browser (NOT the assistant-controlled one)
4. User clicks extension to export (assistant can't click extensions)
5. Assistant detects the downloaded file and copies it to the right place
6. Assistant verifies via API probe and confirms green status
7. Total manual steps: 3 (login, click extension, click export)
8. Total automated steps: 3 (detect, copy, verify)
