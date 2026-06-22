"""Telegram front door — forward a message, POST it to /capture."""
from __future__ import annotations

import logging
import os

import httpx
from dotenv import load_dotenv
from telegram import Update
from telegram.ext import Application, ContextTypes, MessageHandler, filters

load_dotenv()

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
log = logging.getLogger("savefeed.bot")

API_URL = os.environ.get("SAVEFEED_API_URL", "http://localhost:8000")


async def on_message(update: Update, _ctx: ContextTypes.DEFAULT_TYPE) -> None:
    msg = update.effective_message
    if not msg:
        return
    text = (msg.text or msg.caption or "").strip()
    if not text:
        await msg.reply_text("savefeed: empty message, ignored")
        return
    try:
        async with httpx.AsyncClient(timeout=10) as cx:
            r = await cx.post(f"{API_URL}/capture", json={"payload": text})
            r.raise_for_status()
            data = r.json()
    except Exception as e:
        log.exception("capture call failed")
        await msg.reply_text(f"savefeed: capture failed ({type(e).__name__}: {e})")
        return
    await msg.reply_text(f"saved #{data['id']} as {data['source']} (processing…)")


def main() -> None:
    token = os.environ.get("BOT_TOKEN")
    if not token:
        raise SystemExit("BOT_TOKEN not set in env (.env or shell)")
    app = Application.builder().token(token).build()
    app.add_handler(MessageHandler(filters.ALL & ~filters.COMMAND, on_message))
    log.info("savefeed bot polling, API=%s", API_URL)
    app.run_polling()


if __name__ == "__main__":
    main()
