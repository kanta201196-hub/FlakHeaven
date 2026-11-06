/**
 * Telegram webhook of the tester bot (@flakheaven_bot): instant reply to /start and /stop.
 *
 * Why here: Cloudflare Pages Functions deploy with the site from `main`, so the bot answers
 * at once without a separate server. Replaces the hourly polling of tools/telegram/tester_bot.py
 * (a webhook and getUpdates cannot be used together).
 * Bindings (Pages project settings): KV namespace `SUBS`; secrets `BOT_TOKEN`, `WEBHOOK_SECRET`.
 * Telegram sends `X-Telegram-Bot-Api-Secret-Token`; any request without the right value is rejected,
 * so nobody else can make the bot send messages through this URL.
 * Stored per subscriber (KV key `sub:<chat id>`): start date, Start payload, active flag.
 * No names or usernames (personal data, docs/legal/personal-data.md). Decision: Kanta 2026-11-06.
 */

const DISK_LINK = "https://disk.yandex.ru/d/51-K79RPT2cO7Q";
const WELCOME =
  "Привет! Это бот Flak Heaven.\n\n" +
  "Здесь я буду писать, когда выходит новая тестовая сборка.\n\n" +
  `Текущая сборка: ${DISK_LINK}\n` +
  "Папки «Test for Win» (Windows) и «Test for Mac». Распакуй zip и запусти игру. " +
  "Буду рад любым впечатлениям и багам прямо сюда.\n\n" +
  "https://flakheaven.com/\n\n" +
  "Отписаться: /stop";
const STOPPED = "Хорошо, больше не пишу. Вернуться: /start";
const RESUBSCRIBED = "С возвращением! Снова пишу о новых сборках.";

/** Send a plain-text message to a chat. */
async function send(env, chatId, text) {
  await fetch(`https://api.telegram.org/bot${env.BOT_TOKEN}/sendMessage`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ chat_id: chatId, text, disable_web_page_preview: true }),
  });
}

/** Handle one Telegram update. */
export async function onRequestPost({ request, env }) {
  if (!env.WEBHOOK_SECRET || request.headers.get("x-telegram-bot-api-secret-token") !== env.WEBHOOK_SECRET) {
    return new Response("forbidden", { status: 403 });
  }
  const update = await request.json().catch(() => null);
  const msg = update && update.message;
  const text = ((msg && msg.text) || "").trim();
  if (!msg || msg.chat.type !== "private" || !text.startsWith("/")) return new Response("ok");

  const chatId = msg.chat.id;
  const [rawCommand, ...rest] = text.split(/\s+/);
  const command = rawCommand.split("@")[0];
  const key = `sub:${chatId}`;
  const sub = await env.SUBS.get(key, "json");

  if (command === "/start") {
    if (!sub) {
      await env.SUBS.put(key, JSON.stringify({
        since: new Date().toISOString().slice(0, 10),
        payload: rest.join(" ").slice(0, 64),
        active: true,
      }));
      await send(env, chatId, WELCOME);
    } else if (!sub.active) {
      await env.SUBS.put(key, JSON.stringify({ ...sub, active: true }));
      await send(env, chatId, RESUBSCRIBED);
    } else {
      await send(env, chatId, WELCOME);
    }
  } else if (command === "/stop" && sub && sub.active) {
    await env.SUBS.put(key, JSON.stringify({ ...sub, active: false }));
    await send(env, chatId, STOPPED);
  }
  return new Response("ok");
}
