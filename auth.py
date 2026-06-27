"""Twitter/X OAuth 2.0 PKCE flow for user-context API access.

Endpoints:
    GET  /auth/twitter          — redirect to X's authorize URL
    GET  /auth/twitter/callback — exchange code for tokens, store to disk
"""
from __future__ import annotations

import hashlib
import json
import logging
import os
import secrets
import time
from base64 import urlsafe_b64encode
from pathlib import Path
from typing import Any, Optional

import httpx
from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse

log = logging.getLogger("savefeed.auth")

router = APIRouter(prefix="/auth")

TOKENS_PATH = Path.home() / ".savefeed" / "twitter_tokens.json"
AUTHORIZE_URL = "https://x.com/i/oauth2/authorize"
TOKEN_URL = "https://api.x.com/2/oauth2/token"
SCOPES = "bookmark.read tweet.read users.read offline.access"

_pending_pkce: dict[str, str] = {}


def _client_id() -> str:
    val = os.environ.get("X_CLIENT_ID", "")
    if not val:
        raise HTTPException(500, "X_CLIENT_ID not set in .env")
    return val


def _client_secret() -> str:
    val = os.environ.get("X_CLIENT_SECRET", "")
    if not val:
        raise HTTPException(500, "X_CLIENT_SECRET not set in .env")
    return val


def _callback_url(request: Request) -> str:
    return str(request.url_for("twitter_callback"))


def load_tokens() -> Optional[dict[str, Any]]:
    if not TOKENS_PATH.is_file():
        return None
    try:
        return json.loads(TOKENS_PATH.read_text())
    except (json.JSONDecodeError, OSError):
        return None


def save_tokens(data: dict[str, Any]) -> None:
    TOKENS_PATH.parent.mkdir(parents=True, exist_ok=True)
    TOKENS_PATH.write_text(json.dumps(data, indent=2))


def get_valid_token() -> Optional[str]:
    """Return a valid access token, refreshing if expired. None if not authed."""
    tokens = load_tokens()
    if not tokens or "access_token" not in tokens:
        return None
    if tokens.get("expires_at", 0) < time.time() - 60:
        tokens = _refresh(tokens)
        if not tokens:
            return None
    return tokens["access_token"]


def _refresh(tokens: dict[str, Any]) -> Optional[dict[str, Any]]:
    refresh_token = tokens.get("refresh_token")
    if not refresh_token:
        log.warning("no refresh token available")
        return None
    try:
        client_id = os.environ.get("X_CLIENT_ID", "")
        client_secret = os.environ.get("X_CLIENT_SECRET", "")
        if not client_id:
            return None
        with httpx.Client(timeout=15) as cx:
            r = cx.post(
                TOKEN_URL,
                data={
                    "grant_type": "refresh_token",
                    "refresh_token": refresh_token,
                    "client_id": client_id,
                },
                auth=(client_id, client_secret),
            )
        if r.status_code != 200:
            log.warning("token refresh failed: %s %s", r.status_code, r.text[:200])
            return None
        body = r.json()
        updated = {
            **tokens,
            "access_token": body["access_token"],
            "refresh_token": body.get("refresh_token", refresh_token),
            "expires_at": time.time() + body.get("expires_in", 7200),
        }
        save_tokens(updated)
        log.info("Twitter token refreshed")
        return updated
    except Exception as e:
        log.exception("token refresh error: %s", e)
        return None


@router.get("/twitter")
def twitter_auth(request: Request):
    code_verifier = secrets.token_urlsafe(64)
    code_challenge = urlsafe_b64encode(
        hashlib.sha256(code_verifier.encode()).digest()
    ).decode().rstrip("=")
    state = secrets.token_urlsafe(32)
    _pending_pkce[state] = code_verifier

    params = {
        "response_type": "code",
        "client_id": _client_id(),
        "redirect_uri": _callback_url(request),
        "scope": SCOPES,
        "state": state,
        "code_challenge": code_challenge,
        "code_challenge_method": "S256",
    }
    qs = "&".join(f"{k}={httpx.URL('', params={k: v}).params[k]}" for k, v in params.items())
    return RedirectResponse(f"{AUTHORIZE_URL}?{qs}")


@router.get("/twitter/callback", name="twitter_callback")
def twitter_callback(request: Request, code: str = "", state: str = "", error: str = ""):
    if error:
        return HTMLResponse(
            f"<h2>Auth failed</h2><p>{error}</p><p><a href='/auth/twitter'>Try again</a></p>",
            status_code=400,
        )
    code_verifier = _pending_pkce.pop(state, None)
    if not code_verifier:
        raise HTTPException(400, "Invalid or expired state parameter")

    client_id = _client_id()
    client_secret = _client_secret()

    with httpx.Client(timeout=15) as cx:
        r = cx.post(
            TOKEN_URL,
            data={
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": _callback_url(request),
                "code_verifier": code_verifier,
                "client_id": client_id,
            },
            auth=(client_id, client_secret),
        )

    if r.status_code != 200:
        return HTMLResponse(
            f"<h2>Token exchange failed</h2><pre>{r.status_code}: {r.text[:500]}</pre>"
            f"<p><a href='/auth/twitter'>Try again</a></p>",
            status_code=400,
        )

    body = r.json()
    tokens = {
        "access_token": body["access_token"],
        "refresh_token": body.get("refresh_token"),
        "expires_at": time.time() + body.get("expires_in", 7200),
    }
    save_tokens(tokens)
    log.info("Twitter OAuth tokens saved to %s", TOKENS_PATH)

    return HTMLResponse(
        "<h2>Connected!</h2>"
        "<p>Twitter bookmarks sweep is now active. You can close this tab.</p>"
        "<p>Tokens saved. The sweep will run automatically every 30 minutes.</p>"
    )
