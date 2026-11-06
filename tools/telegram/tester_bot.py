#!/usr/bin/env python3
"""Tester bot (@flakheaven_bot): subscriber status and "new build" broadcasts.

Since 2026-11-06 the bot answers /start and /stop instantly through the Cloudflare Pages Function
`functions/api/tgbot.js` (webhook, subscribers in the KV namespace "flakheaven-bot-subs", binding SUBS).
This script only reads that KV and sends broadcasts. A person must press Start first (Telegram rule).

Run (bot token from TELEGRAM_BOT_TOKEN; Cloudflare API through the agent proxy, which injects the
real token, so any dummy Bearer value works; never print secrets):
  tester_bot.py status
  tester_bot.py broadcast --text-file notice.txt            # dry run: shows the count and text
  tester_bot.py broadcast --text-file notice.txt --send     # sends; only after Kanta's "yes"
Kept per subscriber: start date, Start payload, active flag (no names, see docs/legal/personal-data.md).
Decision: Kanta 2026-11-06. Options doc: docs/testers/automation-intake-and-delivery.md.
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
from pathlib import Path

CF = "https://api.cloudflare.com/client/v4/accounts/edb983a1b4c6a8a4122088072749af9a/storage/kv/namespaces/7fe906ac3d734e118cc95a139ff427c3"
TG = "https://api.telegram.org/bot{token}/sendMessage"


def cf_get(path: str) -> bytes:
    """GET a KV API path (list of keys or one value) and return the raw body."""
    req = urllib.request.Request(CF + path, headers={"Authorization": "Bearer x", "User-Agent": "curl/8"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read()


def subscribers() -> dict[str, dict]:
    """Return {chat_id: {"since", "payload", "active"}} for every key `sub:<chat id>` in KV."""
    subs: dict[str, dict] = {}
    cursor = ""
    while True:
        page = json.loads(cf_get("/keys?prefix=sub:&limit=1000" + (f"&cursor={cursor}" if cursor else "")))
        for item in page["result"]:
            subs[item["name"].removeprefix("sub:")] = json.loads(cf_get("/values/" + urllib.parse.quote(item["name"])))
        cursor = (page.get("result_info") or {}).get("cursor") or ""
        if not cursor:
            return subs


def send(chat_id: str, text: str) -> None:
    """Send a plain-text message; raises RuntimeError with the API description on failure."""
    token = os.environ.get("TELEGRAM_BOT_TOKEN") or sys.exit("TELEGRAM_BOT_TOKEN is not set")
    data = urllib.parse.urlencode({"chat_id": chat_id, "text": text, "disable_web_page_preview": "true"}).encode()
    try:
        urllib.request.urlopen(TG.format(token=token), data=data, timeout=60)
    except urllib.error.HTTPError as err:
        raise RuntimeError(f"{err.code} {json.load(err).get('description')}") from None


def cmd_status(_: argparse.Namespace) -> int:
    """Print subscriber counts and the Start sources (no ids)."""
    subs = subscribers()
    active = [s for s in subs.values() if s["active"]]
    sources: dict[str, int] = {}
    for s in active:
        sources[s.get("payload") or "-"] = sources.get(s.get("payload") or "-", 0) + 1
    print(f"subscribers: {len(subs)}, active: {len(active)}, sources: {sources}")
    return 0


def cmd_broadcast(args: argparse.Namespace) -> int:
    """Send a text file to all active subscribers (dry run unless --send)."""
    text = Path(args.text_file).read_text(encoding="utf-8").strip()
    targets = [cid for cid, s in subscribers().items() if s["active"]]
    print(f"recipients: {len(targets)}\n---\n{text}\n---")
    if not args.send:
        print("dry run: nothing sent (add --send after Kanta's yes)")
        return 0
    failed = 0
    for cid in targets:
        try:
            send(cid, text)
        except RuntimeError as err:
            failed += 1  # 403 = the person blocked the bot; they stay in KV, Telegram refuses delivery anyway
            print(f"failed: {str(err)[:80]}")
        time.sleep(0.1)  # far below Telegram's ~30 messages per second
    print(f"sent: {len(targets) - failed}, failed: {failed}")
    return 0


def main() -> int:
    """CLI entry point."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("status").set_defaults(func=cmd_status)
    b = sub.add_parser("broadcast")
    b.add_argument("--text-file", required=True)
    b.add_argument("--send", action="store_true")
    b.set_defaults(func=cmd_broadcast)
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
