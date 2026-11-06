#!/usr/bin/env python3
"""Tester bot (@flakheaven_bot): collects /start subscribers and broadcasts "new build" notices.

Why polling: the bot has no server; a person must press Start first (Telegram rule), and
this script answers those presses whenever it runs (`poll`). Broadcasts go only to people
who pressed Start and have not sent /stop.

Run (token only from the environment, never printed):
  TELEGRAM_BOT_TOKEN=... tester_bot.py poll
  tester_bot.py status
  tester_bot.py broadcast --text-file notice.txt            # dry run: shows the count and text
  tester_bot.py broadcast --text-file notice.txt --send     # sends; only after Kanta's "yes"

Storage: STORE (default /mnt/project-files/bot/subscribers.json, override with
TESTER_BOT_STORE). Only the numeric chat id, the Start date and the Start payload are
kept, no names or usernames (personal data, see docs/legal/personal-data.md).
Decision: Kanta 2026-11-06 ("Настраивай бота"). Options doc: docs/testers/automation-intake-and-delivery.md.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

API = "https://api.telegram.org/bot{token}/{method}"
DEFAULT_STORE = "/mnt/project-files/bot/subscribers.json"
DISK_LINK = "https://disk.yandex.ru/d/51-K79RPT2cO7Q"
SITE = "https://flakheaven.com/"

# Player-facing texts are Russian on purpose (audience language).
WELCOME = (
    "Привет! Это бот Flak Heaven.\n\n"
    "Здесь я буду писать, когда выходит новая тестовая сборка.\n\n"
    f"Текущая сборка: {DISK_LINK}\n"
    "Папки «Test for Win» (Windows) и «Test for Mac». Распакуй zip и запусти игру. "
    "Буду рад любым впечатлениям и багам прямо сюда.\n\n"
    f"{SITE}\n\n"
    "Отписаться: /stop"
)
STOPPED = "Хорошо, больше не пишу. Вернуться: /start"
RESUBSCRIBED = "С возвращением! Снова пишу о новых сборках."


def token() -> str:
    """Return the bot token from the environment or exit with a message (never prints it)."""
    value = os.environ.get("TELEGRAM_BOT_TOKEN", "")
    if not value:
        sys.exit("TELEGRAM_BOT_TOKEN is not set")
    return value


def call(method: str, params: dict | None = None) -> dict:
    """Call a Bot API method with a form-encoded POST and return `result`; raises on API errors."""
    data = urllib.parse.urlencode(params or {}).encode()
    req = urllib.request.Request(API.format(token=token(), method=method), data=data)
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            body = json.load(resp)
    except urllib.error.HTTPError as err:
        body = json.load(err)
    if not body.get("ok"):
        raise RuntimeError(f"{method}: {body.get('error_code')} {body.get('description')}")
    return body["result"]


def store_path() -> Path:
    """Path of the subscriber file."""
    return Path(os.environ.get("TESTER_BOT_STORE", DEFAULT_STORE))


def load() -> dict:
    """Load the store: {"offset": int, "subs": {chat_id: {"since", "payload", "active"}}}."""
    path = store_path()
    if path.exists():
        return json.loads(path.read_text(encoding="utf-8"))
    return {"offset": 0, "subs": {}}


def save(state: dict) -> None:
    """Write the store atomically (temp file, then replace)."""
    path = store_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".part")
    tmp.write_text(json.dumps(state, ensure_ascii=False, indent=1), encoding="utf-8")
    os.replace(tmp, path)


def send(chat_id: str, text: str) -> None:
    """Send a plain-text message without link previews."""
    call("sendMessage", {"chat_id": chat_id, "text": text, "disable_web_page_preview": "true"})


def cmd_poll(_: argparse.Namespace) -> int:
    """Process pending updates: /start subscribes and welcomes, /stop unsubscribes."""
    state = load()
    updates = call("getUpdates", {"offset": state["offset"], "timeout": 0, "limit": 100,
                                  "allowed_updates": json.dumps(["message"])})
    new = 0
    for upd in updates:
        state["offset"] = upd["update_id"] + 1
        msg = upd.get("message") or {}
        chat = msg.get("chat", {})
        text = (msg.get("text") or "").strip()
        if chat.get("type") != "private" or not text.startswith("/"):
            continue
        cid = str(chat["id"])
        command, _, payload = text.partition(" ")
        command = command.split("@")[0]
        sub = state["subs"].get(cid)
        if command == "/start":
            if sub and not sub["active"]:
                sub["active"] = True
                send(cid, RESUBSCRIBED)
            elif not sub:
                state["subs"][cid] = {
                    "since": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
                    "payload": payload.strip(), "active": True}
                send(cid, WELCOME)
                new += 1
            else:
                send(cid, WELCOME)
        elif command == "/stop" and sub and sub["active"]:
            sub["active"] = False
            send(cid, STOPPED)
        save(state)  # after each update so a crash never replays a welcome
    print(f"updates: {len(updates)}, new subscribers: {new}")
    return 0


def cmd_status(_: argparse.Namespace) -> int:
    """Print subscriber counts only (no ids)."""
    subs = load()["subs"]
    active = sum(1 for s in subs.values() if s["active"])
    print(f"subscribers: {len(subs)}, active: {active}")
    return 0


def cmd_broadcast(args: argparse.Namespace) -> int:
    """Send a text file to all active subscribers (dry run unless --send)."""
    text = Path(args.text_file).read_text(encoding="utf-8").strip()
    state = load()
    targets = [cid for cid, s in state["subs"].items() if s["active"]]
    print(f"recipients: {len(targets)}\n---\n{text}\n---")
    if not args.send:
        print("dry run: nothing sent (add --send after Kanta's yes)")
        return 0
    failed = 0
    for cid in targets:
        try:
            send(cid, text)
        except RuntimeError as err:
            failed += 1
            if "403" in str(err):  # the person blocked the bot: stop writing to them
                state["subs"][cid]["active"] = False
            print(f"failed: {str(err)[:80]}")
        time.sleep(0.1)  # stay far below Telegram's ~30 messages per second
    save(state)
    print(f"sent: {len(targets) - failed}, failed: {failed}")
    return 0


def main() -> int:
    """CLI entry point."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("poll").set_defaults(func=cmd_poll)
    sub.add_parser("status").set_defaults(func=cmd_status)
    b = sub.add_parser("broadcast")
    b.add_argument("--text-file", required=True)
    b.add_argument("--send", action="store_true")
    b.set_defaults(func=cmd_broadcast)
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
