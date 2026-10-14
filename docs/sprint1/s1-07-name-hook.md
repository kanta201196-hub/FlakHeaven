# S1-07: рабочее название и хук

*Аналитик рынка и аудитории, 10.10.2026. Как проверял: поиск Steam через API `storesearch` (точное название), веб-поиск (в том числе по itch.io, Google Play и App Store) и веб-поиск по брендам. Поиск на самом itch.io закрыт для бота (robots), поэтому itch.io проверен только через веб-поиск. Базы товарных знаков (USPTO, EUIPO, WIPO, Роспатент) я не смотрел. Это задача Kirill, пункт 4.*

## 1–2. Десять названий и проверка занятости

| # | Название | Что значит | RU звучание / локализация | Результат проверки |
|---|---|---|---|---|
| 1 | **Bingo Fuel** | Авиационный термин: минимум топлива, чтобы вернуться на базу. Прямо описывает нашу петлю «эвакуироваться или остаться». | «На остатках» (это наш внутриигровой термин) или оставить латиницей | **Есть похожее.** В Steam 0 совпадений. Есть джем-игра [Bingo Fuel на itch.io](https://gettingrekt.itch.io/bingo-fuel) (2021, стратегия), [приложение Bingo Fuel в App Store](https://apps.apple.com/us/app/bingo-fuel/id634222670) и [страница Bingo Fuel в вики Arma](https://armedassault.fandom.com/wiki/Bingo_Fuel). Минус для поиска: слово «bingo» в Steam выдаёт рогалики про бинго, например [Bango Bingo](https://store.steampowered.com/app/4893020/) и [Bingo Betty](https://store.steampowered.com/app/4217620). |
| 2 | **Flak Heaven** | Каламбур на «bullet heaven»: сразу видно жанр и авиацию. | «Зенитный рай» или латиницей | **Свободно (как сочетание).** Steam: 0. Точная фраза в вебе не нашлась. Отдельное слово «Flak» занято: [Flak (1984)](https://en.wikipedia.org/wiki/Flak_(video_game)), в Steam есть Flak, Flak Simulator, Flak Duty. |
| 3 | **Overburn** | Форсаж «сверх предела»: рост силы и риск. | «Перегрев». Не «Форсаж»: так в России называется кинофраншиза | **Есть похожее.** Steam: 0. На itch.io есть [OVERBURNED](https://itch.io/post/9506654) (cheesebaron2) и [Outburn](https://quadralion.itch.io/outburn), на RAWG — [LD44 – Overburnt](https://rawg.io/games/ld44-overburnt). |
| 4 | **Skyhaul** | «Небесная добыча»: вылет ради трофеев. | «Небесный улов» | **Игры не найдены, но слово занято компаниями.** Steam: 0, итч и Google Play — пусто. Компании: [SkyHaul (EU)](https://skyhaul.eu/), [Skyhaul Inc](https://www.carriersource.io/carriers/skyhaul-inc), [SkyHaul Aerial Data](https://skyhaulada.com/). |
| 5 | **Bandit Swarm** | «Bandit» на радиожаргоне значит враждебный самолёт, «swarm» — орды. | «Рой бандитов» | **Есть похожее.** Steam: 0. Фраза встречается как термин фанатов Star Wars X-Wing ([BGG](https://boardgamegeek.com/thread/1197601/crackens-bandit-swarm)). Само слово Swarm — частое название игр ([Swarm, 1998](https://en.wikipedia.org/wiki/Swarm_(1998_video_game))). |
| 6 | **Last Sortie** | «Последний вылет»: забег-вылет. | «Последний вылет» | **Свободно (как сочетание).** Steam: 0. Но в Steam уже есть «Sortie» и «Soldier Sortie», а в веб-поиске название тонет в выдаче. Звучит мрачновато для доброго юмора. |
| 7 | **Jetwake** | Спутный след реактивного самолёта. | «Реактивный след» | **Бренд занят.** Steam: 0, игр нет. Но JETWAKE — производитель электросёрфов: [Crunchbase](https://www.crunchbase.com/organization/jetwake), [jetwake.co.kr](https://jetwake.co.kr/ENG), [jetwake.jp](https://www.jetwake.jp/). |
| 8 | **Wingload** | Нагрузка на крыло, отсылка к нашей механике веса. | «Нагрузка» | **Есть похожее.** Steam: 0. Есть приложение для парашютистов [Wingload for Skydiving](https://apps.apple.com/app/id1452094262). Термин узкий, игроку мало что говорит. |
| 9 | **Pylon Panic** | Pylon — это подвес. | «Паника на подвесах» | **Есть похожее.** Фраза свободна, но в Steam есть рогалик [Pylon: Rogue](https://store.steampowered.com/app/386100) и Pylon Racer. Слово «pylon» у игрока связывается с электричеством. |
| 10 | **Hot Exfil** | «Горячая эвакуация». | «Горячая эвакуация» | **Занято по смыслу.** В Steam есть EXFIL, ExfilZone и Exfil Void, на мобильных — [Exfil: Loot & Extract](https://apps.apple.com/app/id6448720577). Название будут путать с экстракшен-шутерами. |

Ещё один отсев: **Hardpoint** (идеально подходит по смыслу) **занят**. В Steam вышла [HARDPOINT](https://store.steampowered.com/app/3733820/HARDPOINT/) от Gumshoe Interactive (08.2026). Также не берём названия, которые ассоциируются с Ace Combat, Jet Lancer и After Burner (последнее — марка SEGA).

## 3. Пять хуков

Оценки по 5-балльной шкале.

| # | Хук (EN — для Steam и трейлера) | Ясность | Отличие от Sublight |
|---|---|---|---|
| A | *A 15-minute sortie: build your jet from hardpoints and wingmen, extract with the loot — or stay for the multiplier.* (текущий рабочий) | 3 — много понятий в одной фразе | 4 — эвакуация и ведомые |
| B | *Vampire Survivors — but you're a fighter jet that can't stop.* | 5 | 4 — инерция и разворот, это наше главное отличие |
| C | *Bullet heaven where fuel is your timer: bank the loot or burn on for a bigger multiplier.* | 4 | 5 — у Sublight нет решения «улететь или рискнуть» |
| D | *Nova Drift meets LUFTRAUSERS: build a fighter, gunship or bomber and lead your wingmen through drone swarms.* | 4 — но только для тех, кто знает обе игры | 3 — звучит как «ещё один космошутер с апгрейдами» |
| E | *Hang missiles on every pylon, drag a swarm on your tail, and make it home before bingo fuel.* | 3 — нужно знать термин | 4 — хорош для трейлера и в паре с названием Bingo Fuel |

## 4. Шорт-лист

**Топ-3 названия:**
1. **Flak Heaven.** Единственный вариант без найденных совпадений и брендов. Жанр и авиация понятны из двух слов, тон лёгкий и подходит к доброму юмору. Риск: слово «Flak» в поиске Steam выдаёт старые игры про зенитки. Нужен логотип, где читаются оба слова.
2. **Bingo Fuel.** Лучше всех описывает нашу механику (топливо, эвакуация, «на остатках»), и в Steam его нет. Риски: уже есть джем-игра и приложение с этим названием, а «bingo» в поиске Steam даёт рогалики про бинго. Казуальный игрок может не знать термин.
3. **Overburn.** Короткое, энергичное, в Steam свободно. Риск: рядом OVERBURNED на itch.io. По смыслу название не так точно привязано к авиации.

**Лучший хук: B + C в связке.** В капсуле Steam и в первые 3 секунды трейлера — B (*«Vampire Survivors — but you're a fighter jet that can't stop.»*). В описании и в конце трейлера — C, он раскрывает петлю риска. Вместе они закрывают оба сегмента: билдкрафтеров (VS) и фанатов авиации (инерция). Это прямо отделяет нас от Sublight. Если выберем Bingo Fuel, финальную фразу трейлера берём из E.

**Что проверить дальше:**
- **Товарные знаки (решение и действие Kirill).** Поиск в [USPTO](https://tmsearch.uspto.gov/), [EUIPO eSearch](https://euipo.europa.eu/eSearch/), [WIPO Global Brand DB](https://branddb.wipo.int/) и Роспатенте по классам 9 и 41 (видеоигры) для трёх финалистов. Для Skyhaul и Jetwake сначала проверить, в каких классах зарегистрированы найденные компании.
- **Домены.** Свободны ли `flakheaven.com`, `bingofuelgame.com`, `overburngame.com`. Эту проверку я не делал.
- **Соцсети.** Свободны ли имена в Steam-группе, X/Twitter, YouTube, TikTok, Discord, VK, Telegram. Не проверял.
- **Поиск в Steam после анонса.** Убедиться, что по запросу мы выходим в первую тройку. Для Flak Heaven и Bingo Fuel это критично.
- **Тест на аудитории.** A/B на 30–50 игроках из ядра (Discord и Reddit по bullet heaven), в EN и RU: что запоминается, что понятно без пояснений и что хочется добавить в список желаемого. Сделать до создания страницы Steam.

**Источники:** все ссылки указаны в таблицах выше. Поиск по Steam: `store.steampowered.com/api/storesearch/?term=<название>`, 10.10.2026.
