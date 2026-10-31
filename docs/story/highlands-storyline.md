# Shahrisang Highlands — storyline proposal

31.10.2026 · thread «Проработать сюжет Нагорья и заставки» · asked by Kanta («проработай сюжетную линию для биома»).
Status: **decided by Kanta 31.10.2026** (answers in §8): depth 3 (full narrative for the Highlands), enemy «Монолит»
with a worked-out history, rule «катсцены — нет» amended, everything in the demo, second ace «Граф». Implementation plan:
`docs/superpowers/plans/2026-10-31-highlands-story.md` (waits for Kanta's «yes» on the plan and §8 open points).
Nothing here is in the game yet except what is marked *(in game)*. Companion document: `cutscenes-and-presentation.md` (how the story is shown: intros, outros,
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
The outro and the hangar debrief tell the operation's ending («Он наш»), so they play only when the sortie cleared the
operation (`need` met); after a failed sortie they wait for the clear (step 7). The intro and the briefing play before any
attempt. «Граф» is counted as met from his op 3 line (`met_graf`), so his op 4 lines are «again» lines.

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

## 7. Decisions (Kanta 31.10.2026)

| # | Question | Answer |
| --- | --- | --- |
| 1 | Story depth | **3 — full narrative for the Highlands now**: hangar dialogue scenes with portraits and choices, plus everything of option 2 |
| 2 | Enemy name | **«Монолит»**, but with a history: the player must understand why we fight (§9) |
| 3 | Rule «катсцены — нет» | **amend** — see game-context «Чего не делаем» |
| 4 | Demo scope | **everything the Highlands story has for ops 1–2** |
| 5 | Second ace «Граф» | **yes** |

Kanta also asked how the mini-bosses («Сквозняк», «Почтальон») fit in → §10. «Компания» (a firm) vs «кампания»
(a campaign): both words are used on purpose — Monolith is a company, the four operations are the campaign.

## 9. «Монолит»: why we fight

**What Monolith is.** A military-engineering company. It does not conquer; it *builds under contract*. It arrives in a
resource region with a client's order, builds the road, the mine, the air defence around them, and runs them. Whoever pays
Monolith owns the region; whoever refuses gets Monolith anyway, because the client already paid. Its doctrine is written
on every briefing slide of theirs: «Дорога, потом подпись» — take the road, and the valley will sign.

**Why Shahrisang.** The mines behind the pass («Шахрисанг» — «stone city» in the valley's old speech) hold the metal
Monolith's client needs. The valley communities refused the contract a year ago. Monolith came in spring with its
engineers, took the high passes nobody defended, and started building: AA in the dry riverbeds, old kala forts as fire bases,
and the flying headquarters «Крепость» that lets it direct a whole offensive without putting a soldier in the valley.

**Who we are.** The valley has no army, only a small highland air arm with the «Вершина» peak on its fins: a few dozen
pilots, one base at the valley mouth, planes bought second-hand and rebuilt by hand (this is why the hangar upgrades and
«Поколения техники» look the way they do). We are the only thing that reaches the fortresses. The pass road is the valley's
lifeline: food, fuel, medicine, people. Hold the road and Monolith's contract does not close.

**Why it is not a war of hatred.** Monolith's people are professionals doing a job; their radio is dry and polite. The
company does not want to destroy the valley — a ruined valley cannot sign. It wants to make resistance unprofitable, which
is why the campaign's climax is «Прорыв»: the last Fortress flies to our base. No base, no air arm, contract signed.
The one person in Monolith who enjoys the war is «Барон»; the others («Граф», «Почтальон», «Сквозняк») are colleagues,
and the humour comes from treating a war like a building site: «У компании хорошие спасатели», «Они опять привезли бетон».

**How the player learns it.** Never as a lecture: one sentence per hangar scene, one radio line per sortie, the «opens»
lines of the campaign screen. By op 2 the player knows Monolith builds; by op 3 who pays its pilots; by op 4 what «Прорыв» means.

**Enemy visual identity (needs Kanta's «ok» as art):** a plain grey vertical slab as the Monolith mark on the Fortress,
AA sites and trucks; no colours, no eagles, no letters. Cheap (one decal), makes «they are one company» readable from
the air. Not in this plan's cost until approved.

## 10. Mini-bosses and bosses in the story

The sortie already has three fixed enemy «characters»: ace «Почтальон» (missile carrier) at 5:00, ace «Сквозняк»
(interceptor) at 10:00, and the Fortress at 15:00 (`spawner.gd`, `boss.gd`). They respawn every sortie; in the fiction
Monolith pilots eject and the company's rescue service brings them back — this is said out loud once (op 1, Купол) and
becomes a running joke. Each gets a role, a memory of the player and two or three lines per operation; the generic
boss lines stay for other biomes.

| Who | Role in Monolith | Arc over ops 1–4 |
| --- | --- | --- |
| **«Почтальон»** | «delivers» the Fortress's orders: the spotter who marks targets for the riverbed AA and brings the missile salvos | op 1: pure business («Доставка по адресу»). op 2: lets slip that the headquarters is in the air («Штаб видит вас с высоты. Доставлю.») — the first mention of the Fortress. op 3: after Baron falls he is the one who sounds tired. op 4: flies escort for the last Fortress: «Последняя доставка». |
| **«Сквозняк»** | Baron's wingman, the company's hothead | op 1–2: echoes Baron, mocks («Сквозит у вас в строю»). op 3: after Baron is shot down, bitter («Это был мой ведущий»), a mirror of the player's own loss of Grom. op 4: challenges the player personally at 10:00 — the only enemy who takes it personally like Baron did. |
| **«Барон»** | lead ace | as in §3; falls in op 3 |
| **«Граф»** | deputy, takes over | §3: one line in op 3, leads the aces of op 4 |
| **«Крепость»** | the method itself; its controller speaks as «Штаб „Монолита“» (red frame), two lines per appearance | op 2: first appearance, surprised to be attacked at all. op 3: businesslike. op 4: «Прорыв» — the only time the headquarters addresses our base directly: «„Вершина“, предложение остаётся в силе до нашего прибытия». |

Memory: campaign flags `met_postman`, `met_draft` (count) choose the «again» line, like Baron's today.

## 11. Depth 3: hangar scenes and choices

**Where.** In the hangar (the 3D hangar scene with the max-quality plane exists). A scene = 3–6 exchanges with portraits
left (our side) and right (Купол / guests), typed-out text, Enter / click / gamepad advances, Esc skips the scene; every
scene can be replayed from the campaign screen («Журнал» — the story log). Scenes are drawn with `HudKit` (ADR-05).

**Who appears.** The player's crew member of the selected class (existing portrait and trait: «Шмель · Торопыга» etc. — the
trait title colours one line per scene), «Купол» (new portrait), «Гром» (new portrait, op 3 debrief and op 4), «Иволга»
(radio only), the base mechanic «Ключ» (new portrait, optional: hangar humour, explains plane 2 and experimental weapons —
ties the story to «Поколения техники»). Enemies never get portraits: red radio plates only.

**Scenes (10):**

| # | When | Content | Choice |
| --- | --- | --- | --- |
| H0 | first entry into the campaign | Prologue: a week after Grom; Купол explains the road and Monolith in three lines; the crew member's first line shows the trait | none (sets the tone) |
| H1 | before op 1 | briefing as dialogue (the briefing text stays on the campaign screen) | ask Купол about Monolith *or* about Grom (changes which fact you learn first) |
| H1′ | after op 1 | debrief: Baron's taunt discussed; Купол: «У компании хорошие спасатели» | none |
| H2 | before op 2 | riverbed AA; Почтальон's «headquarters in the air» line is explained | ask about the Fortress *or* about the rescue beacon procedure |
| H2′ | after op 2 | Иволга's testimony (if rescued) or recon has nothing; **demo: the demo-end screen follows** | pass the parachute lead to recon (op 3 intro shows the fort with a marker) *or* keep it quiet (Baron does not know; his op 3 «again» line changes) — text and intro only, no balance effect |
| H3 | before op 3 | Baron's challenge; Купол: «Не отвечайте. Пусть ищет» | accept the duel openly *or* let him come — flavour, the duel happens anyway |
| H3′ | after op 3 | Grom in the hangar, on crutches, with his portrait; first conversation | **Grom's role in op 4**: flies as the special wingman (default, in code) *or* stays at the base as a second controller (one extra radio warning before each boss; no stats change). Needs Kanta's «ok» — see §8 |
| H4 | before op 4 | «Прорыв»: Купол reads the headquarters' «offer» aloud; the crew answers in character | the crew member's reply (two flavours) |
| H4′ | after op 4 | epilogue: the road, the valley, Grom; Купол's hook about the south | none |
| HX | «Битва асов» first start | one card «Учебный полигон „Вершины“» | none |

**Rules for choices.** A choice changes words, a camera target in the intro or one radio warning — never damage,
HP, rewards or unlocks (rule 2: no balance change without Kanta). All choices are stored in the campaign save and listed
in the story log.

**Text volume.** ~70 dialogue lines + ~25 radio lines + 8 result lines + 10 hangar-scene captions ≈ 115 strings in
Russian; EN/ZH drafts through the translation thread.

## 8. Open points for Kanta (answers by number)

1. **Portraits** for Купол, Гром, Ключ (3 pictures, same style as the 15 crew portraits that were made «ChatGPT по брифу,
   стиль D»). 1 — **generate in the same way, brief and input picture to you for approval first (recommended)**;
   2 — radio plates without faces for all three; 3 — only Grom gets a face.
2. **Grom in op 4** (scene H3′): 1 — **the player chooses: wingman or second controller (recommended)**;
   2 — always a wingman (as coded today), no choice.
3. **Mechanic «Ключ»** as a fourth voice (hangar humour, explains plane 2 and experimental weapons): 1 — **yes (recommended)**; 2 — no.
4. **Monolith mark** (grey slab decal on the Fortress, AA and trucks): 1 — **yes, show a frame first (recommended)**; 2 — no marks.
5. **The plan** `docs/superpowers/plans/2026-10-31-highlands-story.md` — «да» to start. Order: texts and small fixes →
   cutscene runtime → hangar dialogue runtime → scenes for ops 1–2 (demo) → ops 3–4 → epilogue.
