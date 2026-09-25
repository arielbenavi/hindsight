"""Dry-run health checks and setup page for savefeed."""
from __future__ import annotations

import html
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import httpx

import auth
import sweep


def _check_ig_cookies() -> dict[str, Any]:
    cf = sweep._ig_cookies_file()
    if not cf:
        return {
            "status": "fail",
            "message": "IG_COOKIES_FILE not set or file missing",
            "action": "Export cookies.txt from browser and set IG_COOKIES_FILE in .env",
        }
    cookies = sweep._parse_cookies_txt(cf)
    if "sessionid" not in cookies:
        return {
            "status": "fail",
            "message": "cookies.txt has no sessionid — invalid export",
            "action": "Re-export cookies from Instagram while logged in",
        }
    age_days = (time.time() - cf.stat().st_mtime) / 86400
    age_warning = None
    if age_days > 90:
        age_warning = f"cookies are {age_days:.0f} days old — almost certainly expired"
    elif age_days > 60:
        age_warning = f"cookies are {age_days:.0f} days old — will expire soon"

    # lightweight API probe
    try:
        headers = {
            "User-Agent": sweep._IG_UA,
            "X-CSRFToken": cookies.get("csrftoken", ""),
            "X-IG-App-ID": "936619743392459",
            "X-Requested-With": "XMLHttpRequest",
        }
        with httpx.Client(timeout=10) as cx:
            r = cx.get(
                sweep.IG_SAVED_API,
                headers=headers,
                cookies=cookies,
                params={"count": "1"},
            )
        if r.status_code in (401, 403):
            return {
                "status": "fail",
                "message": f"IG API returned {r.status_code} — cookies expired",
                "age_days": round(age_days, 1),
                "action": "Re-export cookies.txt from browser",
            }
        if r.status_code == 200:
            return {
                "status": "warn" if age_warning else "ok",
                "message": age_warning or "IG cookies valid, API responding",
                "age_days": round(age_days, 1),
            }
        return {
            "status": "warn",
            "message": f"IG API returned {r.status_code} — unexpected",
            "age_days": round(age_days, 1),
        }
    except Exception as e:
        return {
            "status": "warn",
            "message": f"Could not reach IG API: {e}",
            "age_days": round(age_days, 1),
        }


def _check_twitter() -> dict[str, Any]:
    if not os.environ.get("X_CLIENT_ID"):
        return {
            "status": "fail",
            "message": "X_CLIENT_ID not set in .env",
            "action": "Add X_CLIENT_ID and X_CLIENT_SECRET to .env",
        }
    tokens = auth.load_tokens()
    if not tokens or "access_token" not in tokens:
        return {
            "status": "fail",
            "message": "Not authenticated — no tokens found",
            "action": "Visit /auth/twitter to connect",
        }
    token = auth.get_valid_token()
    if not token:
        return {
            "status": "fail",
            "message": "Token expired and refresh failed",
            "action": "Re-authenticate at /auth/twitter",
        }
    # test API call
    try:
        with httpx.Client(timeout=10) as cx:
            r = cx.get(
                "https://api.x.com/2/users/me",
                headers={"Authorization": f"Bearer {token}"},
            )
        if r.status_code == 200:
            username = r.json().get("data", {}).get("username", "unknown")
            return {"status": "ok", "message": f"Authenticated as @{username}"}
        if r.status_code == 402:
            return {
                "status": "warn",
                "message": "Auth works but X API credits depleted",
                "action": "Purchase credits at developer.x.com",
            }
        return {
            "status": "warn",
            "message": f"API returned {r.status_code}: {r.text[:100]}",
        }
    except Exception as e:
        return {"status": "warn", "message": f"Could not reach X API: {e}"}


def _check_gemini() -> dict[str, Any]:
    key = os.environ.get("GEMINI_API_KEY")
    if not key:
        return {
            "status": "fail",
            "message": "GEMINI_API_KEY not set",
            "action": "Add GEMINI_API_KEY to .env",
        }
    try:
        from google import genai
        client = genai.Client(api_key=key)
        r = client.models.generate_content(
            model="gemini-2.5-flash",
            contents="Reply with exactly: ok",
            config={"max_output_tokens": 5},
        )
        return {"status": "ok", "message": "Gemini API responding"}
    except Exception as e:
        msg = str(e)
        if "429" in msg or "RESOURCE_EXHAUSTED" in msg:
            return {"status": "warn", "message": "Gemini rate limited — billing may be exhausted"}
        return {"status": "fail", "message": f"Gemini error: {msg[:200]}"}


def _check_ytdlp() -> dict[str, Any]:
    try:
        r = subprocess.run(
            [sys.executable, "-m", "yt_dlp", "--version"],
            capture_output=True, text=True, timeout=10,
        )
        if r.returncode != 0:
            return {"status": "fail", "message": "yt-dlp not installed in venv"}
        version = r.stdout.strip()
        try:
            vdate = datetime.strptime(version, "%Y.%m.%d").replace(tzinfo=timezone.utc)
            age_days = (datetime.now(timezone.utc) - vdate).days
            if age_days > 90:
                return {
                    "status": "warn",
                    "message": f"yt-dlp {version} is {age_days} days old — update recommended",
                    "action": f"{sys.executable} -m pip install -U yt-dlp",
                }
        except ValueError:
            pass
        return {"status": "ok", "message": f"yt-dlp {version}"}
    except Exception as e:
        return {"status": "fail", "message": f"yt-dlp check failed: {e}"}


def run_all_checks() -> dict[str, Any]:
    return {
        "ig_cookies": _check_ig_cookies(),
        "twitter": _check_twitter(),
        "gemini": _check_gemini(),
        "ytdlp": _check_ytdlp(),
        "all_ok": all(
            v.get("status") == "ok"
            for v in [_check_ig_cookies(), _check_twitter(), _check_gemini(), _check_ytdlp()]
        ),
    }


def setup_html() -> str:
    checks = run_all_checks()

    def _icon(status: str) -> str:
        if status == "ok":
            return "<span style='color:#16a34a'>&#x2714;</span>"
        if status == "warn":
            return "<span style='color:#d97706'>&#x26A0;</span>"
        return "<span style='color:#dc2626'>&#x2716;</span>"

    def _row(label: str, check: dict) -> str:
        icon = _icon(check["status"])
        msg = html.escape(check.get("message", ""))
        action = check.get("action", "")
        action_html = f"<div style='color:#666;font-size:13px;margin-top:2px'>{html.escape(action)}</div>" if action else ""
        return f"<div class='check'>{icon} <strong>{html.escape(label)}</strong><div style='margin-left:24px'>{msg}{action_html}</div></div>"

    ig_cookies_path = os.environ.get("IG_COOKIES_FILE", "~/.savefeed/cookies.txt")

    return f"""<!doctype html><html><head><meta charset="utf-8"><title>savefeed setup</title>
<style>
body {{ font: 15px/1.6 -apple-system, system-ui, sans-serif; max-width: 640px; margin: 2rem auto; padding: 0 1rem; color: #222; }}
h1 {{ font-size: 1.3rem; margin-bottom: 0.25rem; }}
.subtitle {{ color: #666; margin-bottom: 1.5rem; }}
.check {{ padding: 12px 0; border-bottom: 1px solid #eee; }}
.check strong {{ font-size: 14px; }}
.section {{ margin: 1.5rem 0; }}
.section h2 {{ font-size: 1rem; color: #444; margin-bottom: 0.5rem; }}
ol {{ padding-left: 1.25rem; }}
li {{ margin-bottom: 0.5rem; }}
code {{ background: #f3f4f6; padding: 2px 6px; border-radius: 3px; font-size: 13px; }}
a {{ color: #2563eb; }}
.btn {{ display: inline-block; padding: 8px 16px; background: #2563eb; color: #fff; text-decoration: none; border-radius: 6px; font-size: 14px; margin-top: 4px; }}
.btn:hover {{ background: #1d4ed8; }}
.refresh {{ text-align: center; margin: 1.5rem 0; }}
.all-good {{ background: #f0fdf4; border: 1px solid #bbf7d0; padding: 12px 16px; border-radius: 8px; margin: 1rem 0; }}
</style></head><body>
<h1>savefeed setup</h1>
<p class="subtitle">Health checks and setup guide</p>

{"<div class='all-good'>All systems operational</div>" if checks["all_ok"] else ""}

{_row("Instagram cookies", checks["ig_cookies"])}
{_row("Twitter / X API", checks["twitter"])}
{_row("Gemini (summarization)", checks["gemini"])}
{_row("yt-dlp (media download)", checks["ytdlp"])}

<div class="refresh"><a href="/setup" style="color:#888;font-size:13px">refresh status</a></div>

<div class="section">
<h2>Instagram cookie setup</h2>
<ol>
<li>Install the <a href="https://chromewebstore.google.com/detail/get-cookiestxt-locally/cclelndahbckbenkjhflpdbgdldlbecc" target="_blank">Get cookies.txt LOCALLY</a> Chrome extension</li>
<li>Go to <a href="https://www.instagram.com/" target="_blank">instagram.com</a> and make sure you're logged in</li>
<li>Click the extension icon &rarr; "Export" (for instagram.com only)</li>
<li>Save or copy the file to: <code>{html.escape(ig_cookies_path)}</code></li>
<li>Come back here and <a href="/setup">refresh</a> — the check should turn green</li>
</ol>
<p style="color:#888;font-size:13px">Cookies expire every ~90 days. Re-export when the check turns red.</p>
</div>

<div class="section">
<h2>Twitter / X setup</h2>
<ol>
<li>Make sure <code>X_CLIENT_ID</code> and <code>X_CLIENT_SECRET</code> are in your <code>.env</code></li>
<li><a href="/auth/twitter" class="btn">Connect Twitter</a></li>
<li>After authorizing, come back and <a href="/setup">refresh</a></li>
</ol>
<p style="color:#888;font-size:13px">Tokens auto-refresh. Re-auth only needed if revoked or after months idle.</p>
<p style="color:#888;font-size:13px">X API credits: <a href="https://developer.x.com/en/portal/dashboard" target="_blank">developer.x.com</a> &rarr; Billing &rarr; Credits &rarr; Purchase credits ($0.001/bookmark read)</p>
</div>

<div class="section">
<h2>Auto-start on login (launchd)</h2>
<p>To have savefeed start automatically when you log in:</p>
<pre style="background:#f9fafb;padding:12px;border-radius:6px;font-size:12px;overflow-x:auto">launchctl load ~/Library/LaunchAgents/com.savefeed.server.plist</pre>
<p style="color:#888;font-size:13px">The plist is generated by the setup script. To stop: <code>launchctl unload ~/Library/LaunchAgents/com.savefeed.server.plist</code></p>
</div>

</body></html>"""
