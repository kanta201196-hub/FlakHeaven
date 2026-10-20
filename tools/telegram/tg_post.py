#!/usr/bin/env python3
"""Публикация от аккаунта проекта в Telegram (Telethon).

Ключи только из переменных среды: TG_API_ID, TG_API_HASH, TG_SESSION.
Без --send ничего не отправляется (проверка доступа и показ того, что уйдёт).

Примеры:
  tg_post.py whoami
  tg_post.py rules @make_game
  tg_post.py post @make_game --reply-to 2155 --text-file t.txt --image now_3_5.png
  tg_post.py post @make_game --reply-to 2155 --text-file t.txt --image now_3_5.png --send

--reply-to: номер поста канала, сообщение уйдёт комментарием в обсуждение.
Предохранители: не больше MAX_PER_DAY отправок в сутки (журнал sent.log),
пауза перед отправкой, при FloodWait скрипт останавливается, а не повторяет.
"""
import argparse
import asyncio
import os
import random
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

from telethon import TelegramClient, errors
from telethon.sessions import StringSession
from telethon.tl.functions.channels import GetFullChannelRequest
from telethon.tl.types import InputMessagesFilterPinned

MAX_PER_DAY = 3
LOG = Path(os.environ.get("TG_LOG", Path(__file__).with_name("sent.log")))


def make_client():
    try:
        return TelegramClient(StringSession(os.environ["TG_SESSION"]),
                              int(os.environ["TG_API_ID"]), os.environ["TG_API_HASH"])
    except KeyError as e:
        sys.exit(f"Нет переменной среды {e.args[0]}")


def sent_last_day():
    if not LOG.exists():
        return 0
    cut = datetime.now(timezone.utc) - timedelta(days=1)
    return sum(1 for l in LOG.read_text().splitlines()
               if l and datetime.fromisoformat(l.split()[0]) > cut)


async def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("whoami")
    r = sub.add_parser("rules")
    r.add_argument("chat")
    p = sub.add_parser("post")
    p.add_argument("chat")
    p.add_argument("--reply-to", type=int)
    p.add_argument("--text-file", required=True)
    p.add_argument("--image")
    p.add_argument("--send", action="store_true")
    a = ap.parse_args()

    async with make_client() as c:
        if not await c.is_user_authorized():
            sys.exit("Сессия недействительна: войти заново (tg_login.py)")
        if a.cmd == "whoami":
            me = await c.get_me()
            print(f"{me.first_name} (@{me.username}) id={me.id}")
        elif a.cmd == "rules":
            ent = await c.get_entity(a.chat)
            full = await c(GetFullChannelRequest(ent))
            print("Описание:", full.full_chat.about)
            async for m in c.iter_messages(ent, filter=InputMessagesFilterPinned, limit=3):
                print("Закреплено:", m.id, (m.text or "")[:1500])
        elif a.cmd == "post":
            text = Path(a.text_file).read_text(encoding="utf-8").strip()
            ent = await c.get_entity(a.chat)
            print(f"Куда: {a.chat}, к посту: {a.reply_to}\nКартинка: {a.image}\n---\n{text}\n---")
            if not a.send:
                print("Это проверка: ничего не отправлено (нужен --send).")
                return
            if sent_last_day() >= MAX_PER_DAY:
                sys.exit("Лимит отправок за сутки исчерпан")
            await asyncio.sleep(random.uniform(20, 60))
            try:
                if a.reply_to and getattr(ent, "broadcast", False):
                    msg = await c.send_message(ent, text, file=a.image, comment_to=a.reply_to)
                else:
                    msg = await c.send_message(ent, text, file=a.image, reply_to=a.reply_to)
            except errors.FloodWaitError as e:
                sys.exit(f"FloodWait {e.seconds} с: остановились, повторять не будем")
            except (errors.ChatWriteForbiddenError, errors.UserBannedInChannelError) as e:
                sys.exit(f"Писать сюда нельзя: {type(e).__name__}")
            with LOG.open("a") as f:
                f.write(f"{datetime.now(timezone.utc).isoformat()} {a.chat} {msg.id}\n")
            print(f"Отправлено: id={msg.id}")


asyncio.run(main())
