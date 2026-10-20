#!/usr/bin/env python3
"""Разовый вход в аккаунт проекта Telegram. Запускать на компьютере Kanta.

Печатает строку входа (StringSession). Её кладут в секрет среды TG_SESSION.
Строка даёт полный доступ к аккаунту: не коммитить, не присылать в чат.
Нужны: pip install telethon; ключи TG_API_ID и TG_API_HASH с my.telegram.org.
"""
import getpass
import os
import sys

from telethon.sessions import StringSession
from telethon.sync import TelegramClient


def main():
    api_id = int(os.environ.get("TG_API_ID") or input("api_id: ").strip())
    api_hash = os.environ.get("TG_API_HASH") or getpass.getpass("api_hash (ввод скрыт): ").strip()
    with TelegramClient(StringSession(), api_id, api_hash) as client:
        # Telethon сам спросит номер, код из Telegram/SMS и пароль двухэтапной защиты
        me = client.get_me()
        print(f"\nВошли как: {me.first_name} (@{me.username})", file=sys.stderr)
        print("\nСтрока входа (одной строкой, это значение TG_SESSION):\n", file=sys.stderr)
        print(client.session.save())


if __name__ == "__main__":
    main()
