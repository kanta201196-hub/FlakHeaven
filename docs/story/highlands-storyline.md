# Shahrisang Highlands — storyline proposal

31.10.2026 · thread «Проработать сюжет Нагорья и заставки» · asked by Kanta («проработай сюжетную линию для биома»).
Status: **proposal, waiting for Kanta's numbered answers** (questions at the end). Nothing here is in the game yet except
what is marked *(in game)*. Companion document: `cutscenes-and-presentation.md` (how the story is shown: intros, outros,
radio, visual and audio effects, Godot tech, cost).

Player-facing strings are quoted in Russian because that is the source language of the game; they go through `Loc.t()`
and the `.po` files like every other string. Names in English follow `docs/glossary-en.md`.

## 0. What already exists and stays

| Fact | Source |
| --- | --- |
| World: fictional near future, fictional factions, no real countries, aircraft or conflicts; kind humour | game-context «Игра и мир» (10.10) |
| «Чего не делаем: катсцены (радиореплики и брифинги — да)» | game-context (10.10, 17.10). **Any intro/outro scene changes this rule — see question 3** |
| Highlands campaign: 4 operations «Перевал» → «Сухое русло» → «Крепости» → «Небо над Шахрисангом», difficulty «Учебный» → «Ас», rival ace «Барон» | U-05, `campaign.gd` *(in game)* |
| Story thread **«Где Гром?»** (EX-09, Kanta «Б — делай» 22.10): leader «Гром» shot down by «Барон» before the campaign; Baron taunts at 8:00 of op 1; rescue activity «Сбитый пилот» in op 2; Baron shot down in op 3 → «Гром» alive; in op 4 Grom flies as a wingman from 3:00 and says the last line | `story.gd`, `rescue.gd`, `docs/playtest/external-2/ex09-story-texts.md` *(in game)* |
| Voices: dispatcher «Купол», «Гром», «Барон», wingmen «Стриж» / «Грачонок»; the Fortress script speaks as «Штаб» (inconsistency, see §6) | `story.gd`, `fortress.gd` |
| Final boss «Прорыв»: the flying HQ «Крепость» flies towards our base, the player intercepts; phases left wing → right wing → «Падение» | FB-01 (18.10, 26.10) |
| Our common air-force sign is called **«Вершина»** (now only on the fin) | insignia decision 17.10, 28.10 |
| Enemy ace callsigns are aristocratic: «Барон», «Граф» (+ «Шершень», «Сокол-7», «Профессор», «Тётя Шура») | `rival_ace.gd` |
| Demo (Next Fest): ops 1–2 only; the demo-end screen already teases op 3 («Барон ищет вас лично») | `docs/demo-next-fest.md`, M-07 |
| Biome 2 «Архипелаг Таласора»: ships, cruiser «Сторож», carrier «Левиафан», ekranoplan «Крачка» — paused, only a hook | E-10, E-11 |

The proposal **keeps the «Где Гром?» spine** (already approved and coded) and adds the frame around it: who we are, who
the enemy is, why the Highlands matter, and one clear beat per operation that a 10-second scene can show.

## 1. World frame (one paragraph the player never has to read)

The **Shahrisang Highlands** are a high mountain country of dry riverbeds, kishlaks, orchards and old fortress-forts
(«кала»). One road crosses them, over the **Shahrisang Pass**: everything the valley towns live on comes by this road.
We are the small highland air arm whose sign is the **«Вершина»** peak; our base sits below the pass at the valley mouth.

The enemy is a well-equipped **expeditionary company** (name — question 2) hired to take the pass and the mines behind it.
It fights like an engineering firm: it does not hold ground, it builds — AA positions in the riverbeds, old forts turned
into fire bases, and above all the **«Крепость»** programme: heavy flying headquarters that direct the whole offensive from
the air. Its pilots carry title-like callsigns («Барон», «Граф»): ranks in the company, not nobility. Nobody in this war
is a demon; the company's radio is dry and businesslike, which makes «Барон» stand out — he enjoys it.

Tone: the player is a line pilot, competent, not a chosen one. Humour stays kind and comes from «Купол» and the wingmen.
No politics, no real-world references, no named civilians in danger on screen (convoys, roads and lights of villages carry
the stakes).

## 2. Cast

| Callsign | Who | Voice on the radio | New? |
| --- | --- | --- | --- |
| **«Купол»** | base controller; the narrator of the campaign | calm, exact, dry humour; never panics | in game |
| **«Гром»** | leader of the player's flight, shot down a week before op 1 | warm, few words; heard in intercepts, free in op 4 | in game |
| **«Барон»** | the company's lead ace; shot Grom down; hunts the player personally | superior, short; red intercept frame | in game |
| **«Граф»** | second company ace, Baron's deputy; takes over after Baron falls (op 4 dogfights) | cold, formal, says one line per sortie | new, uses an existing callsign |
| **Wingmen** «Стриж», «Грачонок» | as now | react to orders | in game |
| **the rescued pilot** | op 2; callsign «Иволга» (no portrait, radio only) | tired, grateful | new name only |

No new voice acting: all radio is text (three languages). See the presentation document for the «radio texture».

## 3. The arc in four operations

One sentence per operation, then the beats. **Intro** / **outro** mark the 8–15 s in-engine scenes proposed in the
companion document (question 3 decides whether they exist). Everything else is radio and briefing text as today.

### Op 1 «Перевал» — «Дорога должна жить»
*The supply column goes over the pass; someone shot Grom down here a week ago.*

- **Briefing** *(in game)*: Grom missing, last word heard «Барон»; hold the sky over the road for 15 minutes.
- **Intro (8 s):** dawn over the pass road, the player's flight (hangar models, player livery) climbs over the first ridge, the column's lights below. Caption: «Перевал Шахрисанг. Неделя после пропажи „Грома“». Купол: «Звено, небо ваше».
- 8:00 *(in game)*: Baron's taunt (red frame): «Ваш ведущий падал красиво…»
- **New radio** at the 10:00 ground miniboss: Купол: «Это не ПВО кочевников. Кто-то строит здесь позиции по чертежу.» (first mention that the enemy *builds*).
- **Outro (6 s):** the column crosses the pass crest at dusk, the flight overhead. Купол: «Колонна прошла. О „Громе“ — ничего. Пока.»
- Result screen gets one **story line** under the operation title: «Перевал открыт. Барон знает ваш позывной.»

### Op 2 «Сухое русло» — «Они строят»
*The enemy fortifies the riverbeds; the first «Крепость» appears; a downed pilot saw Grom's parachute.*

- **Briefing** *(in game)*: AA in the riverbeds; «Крепость» at 15:00; Baron seen.
- **Intro (10 s):** camera slides along a dry riverbed where AA positions are being dug in (existing props: AA sites, trucks, crates); high above, a dark silhouette crosses the cloud layer — the first look at the Fortress. Купол: «Разведка видит движение у перевала. Держитесь выше хребта.» *(line in game)*
- Activity **«Сбитый пилот»** *(in game)*: rescued pilot «Иволга» saw Grom's parachute near the old forts. If the rescue fails, the line continues without the hint (as coded).
- 15:00 Fortress «Прорыв» *(in game)*. **New radio** on first sight: Купол: «Вот она. Летающий штаб. Так вот кто чертит их позиции.»
- **Outro (8 s):** the Fortress hull burns on a slope below; the flight banks over it. Купол: «Первая. Не последняя: перехват говорит о „программе“.»
- Result line: «Крепость № 1 сбита. „Гром“ — у старых крепостей?» (variant without the rescue: «Крепость № 1 сбита. О „Громе“ по-прежнему ничего.»)
- **Demo ends here** *(in game)*: the demo-end screen already teases op 3.

### Op 3 «Крепости» — «Один на один»
*Old mountain forts are now fire bases; Baron asks for a duel; after his fall the intercept says Grom is alive.*

- **Briefing** *(in game)*: forts as strongpoints; Baron wants you; Fortress again at 15:00.
- **Intro (10 s):** open channel, red frame fills the screen width: Baron over a fortress-kala, his plane doing a slow roll above the walls (the rival-ace model). Барон: «Один на один. Без ваших нянек.» *(line in game)* Купол, after a beat: «Не отвечайте. Пусть ищет.»
- Duel *(in game)*; Baron down → Купол: «Перехват из крепости: „Гром“ жив! Наземные идут за ним.» *(in game)*
- **New:** when Baron falls, **«Граф»** speaks once (red frame): «Барон был лучшим из нас. Был.» — introduces the op 4 aces.
- Fortress at 15:00 *(in game)*.
- **Outro (8 s):** night; a fortress-kala below with our flares over it (ground troops reaching Grom); a single green flare answers from the walls. Купол: «Зелёная. Он наш.»
- Result line: «„Барон“ сбит. „Гром“ свободен.» (if Baron escaped: the op is not cleared anyway — `need: baron`).

### Op 4 «Небо над Шахрисангом» — «Прорыв»
*Everything the company has left is in the air; the last Fortress goes for our base; Grom flies with you.*

- **Briefing** *(in game)*: last push. **Add one sentence:** «„Гром“ догонит звено на третьей минуте — ему дали первый исправный самолёт.»
- **Intro (12 s):** the base at the valley mouth at first light; on the strip, the player's plane and one «Стриж» with Grom's name stencil; the flight takes off over the valley towns (the lights the player has defended for three operations). Купол: «Все их звенья в воздухе. Курс „Крепости“ — на нас. Поднимаемся всем, что есть.»
- 3:00 *(in game)*: Grom joins: «Звено, я снова в строю. Должок за мной.»
- **New:** aces in this op prefer the callsign «Граф» (rival_ace: Baron is dead; Count takes the first slot). Граф on arrival: «Компания не отступает. Только пересчитывает.»
- Fortress «Прорыв» *(in game)*; on its fall Гром: «Небо над Шахрисангом наше. Спасибо, что не бросили.» *(in game)*
- **Outro (12 s):** sunset, the flight (player + Grom + wingmen) passes over the pass road with the column moving below and the burnt Fortress on the ridge; slow pull-back to the valley. Then one **hook line** over black: Купол: «Радиоперехват с юга: компания грузится на корабли. Таласора…» → Archipelago (only when biome 2 is live; until then the line is «…Мы ещё услышим о них.»).
- Result line: «Кампания Нагорья завершена» + district credits (already planned in EX-09).

### Replays and difficulty
Scenes and story lines play **on the first clear of an operation** (campaign save flags). Replays for loot start straight
in the sortie; a setting «Заставки: при первом прохождении / всегда / никогда» (default: first time). The campaign
flags that already exist (`rescued`, `grom_free`) stay; new flags: `seen_intro_<op>`, `seen_outro_<op>`, `graf_met`.

### «Битва асов» (test mode)
No story. Optional 3-second title card «Учебный полигон „Вершины“» so the mode has a place in the world. Not before EA.

## 4. Why this shape

- It needs **no new systems**: all beats are radio lines, briefing sentences, result-screen lines and (if approved) 8–12 s camera flights over things the engine already renders.
- It gives each operation a **visible promise and payoff** (road → first Fortress → duel → breakthrough), which is what the external tester asked for («сюжет, цель, устремление»).
- The enemy gets a face without a villain monologue: the Fortress *is* the enemy's method; Baron is its one personality; «Граф» shows the company survives him (useful for biome 2).
- Everything is **fictional** and checkable against rule 1 (no real countries, insignia, aircraft).
- Localisation cost is small: about 20 new strings.

## 5. Alternatives considered (for the record)

- **«Пропавший караван»** — the column itself is the story (a named convoy commander talks each op). Rejected: convoys are random activities, the commander would speak at random moments.
- **«Барон — бывший наш»** (Baron is Grom's former student). Rejected: melodrama, and it contradicts «юмор добрый, без злодейских монологов»; keep Baron a professional.
- **Branching endings** (Grom lost if the rescue fails). Rejected: a story branch that depends on an optional activity punishes the «кайфовать» principle; the rescue only changes one hint line.

## 6. Small fixes to do regardless of the decision

1. `fortress.gd` speaks as «Штаб»; everyone else hears «Купол». Unify to «Купол» (3 lines, `.po` entries).
2. Story strings in `story.gd` bypass `Loc.t()` on some lines — check all radio lines go through translation (EN/ZH).
3. The briefing of op 4 lacks the Grom sentence (S9-17 made him join at 3:00; the text does not say so).

## 7. Questions for Kanta (numbered; answers by number)

1. **Story depth.** 1 — only text (§3 radio and result lines, no scenes). **2 — text + short in-engine intros/outros as in §3 (recommended).** 3 — full narrative (crew scenes in the hangar, portraits, choices) — not before EA.
2. **Enemy name** (the company). 1 — **«Компания „Монолит“»** (recommended: neutral, corporate, nothing real). 2 — «Кондотта» (mercenary flavour, matches the title callsigns). 3 — keep it nameless («противник», «компания» in lower case).
3. **Rule change.** Intros/outros mean amending «Чего не делаем: катсцены» to «короткие заставки в движке (≤ 15 с, пропускаемые любой клавишей), без видео». 1 — **yes (recommended)**. 2 — no, text only (then question 1 = 1).
4. **Scope for the demo** (Next Fest, ops 1–2). 1 — **intro + outro of ops 1–2 and the Fortress first-sight line (recommended)**; 2 — only op 1 intro; 3 — nothing new in the demo.
5. **«Граф»** as the second ace with two lines. 1 — **yes (recommended)**. 2 — no, Baron is the only named enemy.
