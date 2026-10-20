# Страница Steam: черновик текстов

Черновик 18.10.2026 для проверки Kanta. Основа: `docs/game-context.md` (механики и решения). Пишу только то, что уже есть в игре или решено; всё, что ещё не сделано, помечено **[проверить]**. Размеры картинок и лимиты текста — по моей памяти, **перед загрузкой сверить в Steamworks**.

## 1. Название и хук
- Название: **Flak Heaven** (решено 18.10.2026).
- Хук для заголовка трейлера и первой строки: *«Vampire Survivors, but you're a fighter jet that can't stop.»* (EN). RU: «Вы истребитель, который не может остановиться».

## 2. Короткое описание (в Steam не больше 300 знаков, **проверить**)
**EN:** Fighter-jet bullet heaven roguelite. You can never stop flying: build your plane from weapons and wingmen, bomb ground targets, dodge missiles, and decide when to extract with your loot. 15-minute sorties.

**RU:** Roguelike про боевую авиацию в стиле bullet heaven. Остановиться нельзя: собирайте самолёт из оружия и ведомых, бомбите наземные цели, уворачивайтесь от ракет и решайте, когда улетать с добычей. Вылет 15 минут.

## 3. Полное описание (EN, RU переводим по тому же плану)
**About this game**
Flak Heaven is a top-down fighter-jet roguelite. Every sortie lasts 15 minutes. Your plane keeps moving, you steer it, and the sky fills with enemy jets, drones and missiles while the ground fights back with flak.

**Build your plane**
- Three classes: fighter, attacker and bomber, each with its own feel and weapon slots.
- Hang weapons on your hardpoints and set what each group targets: ground, air, missiles or bosses.
- Heavier loads slow you down, so every upgrade is a trade-off.
- Pick up wingmen and turrets that fly and fight for you.

**Fly, bomb, survive**
- You cannot stop; inertia and turning radius are part of the game. Barrel roll, afterburner and sharp turns keep you alive.
- Bomb ground targets and defence positions for rewards, not just chores.
- Bosses at minutes 5, 10 and 15, plus events: strike an air-defence site, hunt an enemy ace, intercept a transport, escort a convoy.

**Risk and reward**
- Extract with your loot after the final boss, or stay for a growing bonus while fuel runs down.
- Die without extracting and you keep half the loot.

**Biomes**
- The mountain Highlands of Shahrisang and the Archipelago of Talasor, with more planned **[проверить, сколько биомов в раннем доступе]**.

**A fictional world**
All vehicles and places are invented, inspired by aviation but without real countries, flags or insignia.

## 4. Теги и категории (для страницы)
Bullet Heaven, Action Roguelike, Roguelite, Shoot 'Em Up, Top-Down, Flight, Aircraft (или Military), Singleplayer. Не ставим теги, которых в игре нет (например Co-op, Steam Deck Verified, пока не проверено).

## 5. Ранний доступ: что обещаем
Это текст для раздела «Почему ранний доступ» (по правилам Steam нужно честно написать, что готово, а что нет). Черновик:
- Что сейчас: три класса, [N] биома, [N] боссов, прокачка самолёта и вылеты по 15 минут **[проверить к запуску]**.
- Что добавим: ещё биомы, ещё оружие и враги, русский и английский языки (китайский позже), правки по отзывам.
- Цена: $9.99 в раннем доступе, в России 250 ₽ (решение Kanta 19.10), скидка запуска 10 %, к версии 1.0 вырастет до $12.99–14.99 — написать об этом в блоке вопросов о раннем доступе. Расчёт — `docs/marketing/pricing.md`.
- Срок раннего доступа: [6–12 месяцев — решение, по аналогам Sublight минимум 6 месяцев].

## 6. Картинки (размеры сверить в Steamworks)
Основная капсула 616×353 и малая 462×174 (на них самолёт крупно, название, без мелкого текста), вертикальная 748×896, библиотечные 600×900 и hero 3840×1240, логотип 1280×720 с прозрачным фоном, трейлер 30–45 с, 5–8 скриншотов 1920×1080 без интерфейса. Кадры снимаем после чистки кадров и запуска Архипелага. Иллюстрации капсул может сделать Kirill через ChatGPT по промптам (решение 10.10.2026); я подготовлю промпты.

## 8. Отметка об ИИ-генерации (itch.io и Steam, 20.10.2026)
Ответ на обеих площадках одинаковый: «Да, есть контент, созданный генеративным ИИ». Проверено по `docs/game-context.md`, `game/models/CREDITS.md`, `game/audio/CREDITS.md`, `game/README.md`:
- 3D-модели части техники созданы в генераторе Meshy (платная подписка, решение 14.10.2026) и дорабатываются вручную.
- Портреты экипажа (15 позывных) нарисованы владельцем в ChatGPT.
- Код игры пишется с помощью Claude (Claude Code).
- Музыка и звуки НЕ сгенерированы ИИ: стоковые CC0 и CC-BY (Kenney, nene, bobjt, Alexandr Zhelanov, Eldritch Grim и др., таблица в `game/audio/CREDITS.md`). Если позже появится ИИ-музыка (решение Kanta), обновить этот раздел.
- Модели Sketchfab (CC BY, `game/models/CREDITS.md`) сделаны людьми, переработаны для игры.
Перед отправкой страницы Steam сверить формулировку с формой Steamworks («AI Generated Content Disclosure»).

## 7. Что нужно от Kanta
1. Проверить тон и факты в тексте (особенно «Что обещаем»).
2. Решить, сколько биомов и боссов считаем готовыми к раннему доступу.
3. Сказать, нужен ли ещё русский перевод полного описания сейчас (по умолчанию делаю после утверждения английского).
