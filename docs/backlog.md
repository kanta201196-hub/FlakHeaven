# Бэклог проекта

Переписан по системам игры 22.10.2026 (решение Kanta, задача R-03). Всё закрытое и прошлые спринты — в `docs/backlog-archive.md` (там же старые таблицы P5 / S4…S8 / M / U / L / E с полными описаниями; в строках ниже на них даны номера).

**Статусы — пять:**
- **идея** — принято или предложено, но никто ещё не начал (очередь);
- **ждёт Kanta** — нужны его решение, материал или действие;
- **в работе (тред)** — тред пишется в скобках;
- **на проверке в сборке N** — слито и вошло в сборку, ждёт проверки в игре;
- **готово** — закрыто; такая строка живёт здесь до конца раздела недели и дальше уходит в архив.

**Правила ведения.** В каждом разделе не больше 10–15 живых задач. Новая задача — в раздел своей системы, с номером. Номера не меняются. Закрыл — строка в конец `backlog-archive.md` («Дописано после…»), здесь удалил. Шапку «Где мы сейчас» обновляем при каждой сборке и каждую пятницу на ревью.

## Where we are (12.11.2026)

- **Game:** last code PR merged is #622 (PG-12 card telemetry, PG-14 first synergy), on 11.11. Also merged on 11.11: #619 (PG-17 lighter first sortie), #620 (PG-13 «момент силы»), #621 (PG-16 album in combat). Open: PR #600 (two editions, ED-03/04/08); not re-checked on 12.11 (догадка: still open, waits for Kanta's merge decision).
- **Last build:** 3.5-s18, rebuilt 09.11 with #615. Nothing new since, so no build line in `docs/status-log.md` on 12.11. Kanta has not reported the s18 check (догадка: not done yet). Next build only on Kanta's command, not before the s18 items are checked in the game. The next build will carry the 11.11 merges (#619–#622).
- **Waiting on Kanta (details in `docs/owner-checklist/kanta-now.md`):** pick a bomb package for «Кит» (GD-18, Claude recommends option 1); look at the in-combat album frames (PG-16); «ок» on the marketing texts (Diary №4 and №5, and more); decide on the Steam roadmap (early access option B, `Составить дорожную карту релиза в Steam`); «да» on the two comic redraws (Купол, Гром; two Figma generations, it spends credits); «ок» on the 7 capsules and 8 screenshots (R-29).
- **Main path:** Valve's review of the Steamworks documents ~16.11 (4 days left); Steam Next Fest registration by 10.01.2027 (59 days left); demo and page to Valve by 18.01.2027 (67 days left). The 18.01 date comes from Steamworks; `docs/process/early-access.md` still says 25.01 (to reconcile).
- **Strong-model threads:** no more than six at once (since 25.10.2026); the coordinator runs the queue.

## Правки по сборке 3.5-s16

One numbered list for the build under test (3.5-s16). Kanta sends items as he plays; work is handed out only after his «готово» (or an explicit «раздать сразу»). Code locations below are read from the code, causes are hypotheses until reproduced (`systematic-debugging`).

| ID | Task | Thread / owner | Status |
| --- | --- | --- | --- |
| S16-01 | In story scenes the mouse does not pick an option in the talk with «Купол» (choice steps, e.g. `ask_pass`, `ask_riverbed`, `lead`, `duel`, `grom_role`, `reply`). Path: `hud_dialog.gd:40-49` registers `dlg:opt:<k>` rects (44 px rows) over a full-screen `dlg:next` → `Hud._input` `button_at` (`hud.gd:166-184`) → `Main.ui_click` (`main_input.gd:259`) → `Dialog.ui` → `Dialog.pick` (`story/dialog.gd:130`, ignored while `total < ARM` 0.3 s). Keyboard path (`1-3`, Enter, arrows) is separate and works. Hypotheses: the click lands on the full `dlg:next` rect (rect order/offset vs drawn rows), or `Hud._input` bails out (`tuning_panel`/`report` visible), or the click is eaten before `Hud`. Needs a repro with `--dialog` and a synthetic click | Интерфейс | done 06.11, PR #567 — check in the next build |
| S16-02 | Music changes abruptly and constantly. `Main` calls `sfx.music(track)` every frame (`main.gd:379-409`); a different track starts a 1.5 s crossfade with a random file from the list (`sfx.gd:431-453`). Hypothesis: in flight `battle` ↔ `boss` flips whenever `boss_alive()` or a `RivalAce` activity appears/disappears (`main.gd:407-409`), each flip also restarts a random track from 0:00; plus `menu` ↔ `result` in cutscenes (`main.gd:379`). Check the log for track switches per sortie; fix idea: hysteresis/min hold time and no restart when returning to the same family | Звук и музыка | PR #565 merged 06.11: boss music holds 8 s after the last boss/ace, battle track resumes where it stopped, battle↔boss fade 3 s; F1 toggle `music_steady` (R-22, 0 = s16). Waits for Kanta to check by ear in s17 |
| S16-03 | The combat turn (E, `combat_turn`) jerks the plane instead of turning smoothly. Cause read from the code: `player_flight.gd:64-68` rotates `heading` toward the target at a constant `tr*4 + PI/0.35` rad/s (~9 rad/s, a 180° turn in ~0.35 s, `time` in `plane_classes.gd:83`) with no ease-in/out, then control returns at once. Fix idea: ease the angular speed (smoothstep/acceleration), longer `time` ~0.5–0.6 s, keep the shape of the arc; touches combat feel, so behind an F1 switch until Kanta's «ок» (R-22) and `smoke.sh` + `full.sh` | Полёт и манёвры | collected, not started |
| S16-04 | The convoy notice is too big (Kanta's screenshot: a full-width plate at the top, «КОЛОННА: до укрытия 58 с · грузовиков: 3 из 3» plus the reward line). It is the shared activity task plate: `HudFlight._task` (`hud_flight.gd:1041`) draws a fixed 980×62 px plate at 0.78 alpha with a 22 px title and a 17 px sub line (`_task_sub`); the convoy text is at `hud_flight.gd:1117-1121`. The one-line `_task_compact` form (width of the text, 34 px) exists but is used only under boss bars. Fix idea: size the plate to the text (as the compact form does) and drop or shorten the reward line after the first ~8 s for all activities, not only the convoy; UI-only, no numbers | Интерфейс | done 06.11, PR #567 — check in the next build |
| S16-05 | Make the ground fortress sturdier. Confirmed by Kanta 05.11: «Укрепрайон» (ground base activity, `fort_area.gd`, launcher HP via `setup_fort(f, hp_mult, dps)`) not the boss «Крепость». Rule 2: a balance change needs Kanta's «yes» and is at most one per build cycle; target from memory: fight 60–100 s, fortress downed in 90 % of sorties — measure on the s16 log first, then propose a number (HP ×1.15–1.3 as a starting range, not a decision). Also counts as the single balance change of the next cycle together with GD-14/15/16 [Data (`/mnt/project-files/s16_review.md`): bunker lives 2–4 s, base 7–12 s, goal 60–100 s; cause `ground_target.gd` lower bound 3 s / 1 s of player damage plus timers AASite.LIMIT 60 s and FortBalance.LIMIT 90 s] | Геймдизайн | in PR #564: site floor 3/6/20 s (was 0.6/1/3), site timers 150 s, unit test `site_hp_test.gd`; check in the game (Kanta «Да» 06.11) |
| S16-06 | Make the air-defence bunker («бункер ПВО», the «удар по позиции ПВО» activity, `aa_site.gd`) sturdier too — a continuation of S16-05, same rules: balance change needs Kanta's «yes», one per build cycle, measure on the s16 log first [Same data: bunker 2–4 s; see S16-05] | Геймдизайн | in PR #564 together with S16-05; check in the game |
| S16-07 | Enemy missiles are still too few to use the potential of the flares (Kanta: «Ракет как будто бы все еще слишком мало»). Related history: S10-13 (enemy missiles ineffective), GD-11 (aces flare her missiles). Balance change: needs Kanta's «yes», one per build cycle, so it competes with S16-05/06. Measure first: enemy launches per sortie and flares that caught a missile, from the s16 log; then propose numbers (e.g. launch cooldown of SAM/fighters, share of missile-armed enemies) [Data: only 59 missiles flared in 3 sorties (Kit 12 on 22 salvos); launches are not logged — add a counter in `Projectiles.spawn_missile` first; ×1.5 is probably too little, try ×3 (guess)] | Геймдизайн | enemy missile counter in PR #564; numbers after the s17 log; needs «yes» |
| S16-08 | Hangar, buying a level-2 plane: show the stat difference (old → new). Add concrete stats to every plane: speed, damage per second, hull, plus suggestions: turn rate, gun fire rate, bomb/missile load, module slots, cooldown of the class skills, wingman | Интерфейс + Геймдизайн (набор цифр) | done 06.11, PR #567 — check in the next build |
| S16-09 | Level 2 is bought too easily: one sortie gave 12k iron, crew level 6 and the second plane (it costs 1.5k). Either the price is several times higher or income is lower; ties to S16-15 «economy» (item 14). Balance: needs Kanta's «yes», choose with the s16 log [Data: income `parts_kept` 12.6–14.1k per sortie vs plane 1500 (≈9 planes per sortie)] | Геймдизайн | plane 2 = 50000 in PR #564; upgrade prices unchanged, check in the s17 log |
| S16-10 | Hangar weapon-display textures: many «cheap» textures with squares; overall fine, raise quality | 3D | merged #570 06.11: the «squares» were the hangar floor's square grains (now round) and 236 store/turret texture imports without mipmaps (now on); battle/biome textures still without mipmaps (~200 files, not in scope) |
| S16-11 | Hangar: «Модерниз НАР» (rockets mod) hangs in the air, no stand (screenshot `rockets_mod.png`). Stands: `hangar3d.gd:445-470` `_place_on_stand` | 3D | merged #570 06.11: wide munitions trailer, pods on timber blocks |
| S16-12 | Hangar: «Модерниз бомбы» also hangs in the air (`bombs_mod.png`) | 3D | merged #570 06.11: long trailer, rack along it on two blocks, no overhang |
| S16-13 | Hangar: flares lvl 1–5 hang in the air; they are flat — find another flat stand (`flares.png`) | 3D | merged #570 06.11: flat platform trolley for flares lvl 1–5 and the modernised launcher |
| S16-14 | Hangar: the high-explosive bomb sits on a stand that does not fit it (`he_bomb.png`) | 3D | merged #570 06.11: mid trailer, bomb on two timber blocks between nose and fins |
| S16-15 | «Сборщик трофеев» (`cards.gd:65`, cat «Модуль», max 3) probably should not take a module slot (`trophy_collector.png`). Rule/UI change: a passive pickup perk instead of a module? Kanta asked «нет?» — needs his «yes» | Геймдизайн | done 06.11: takes no module slot (`Cards.SLOT_FREE`), card says «БЕЗ МЕСТА МОДУЛЯ» |
| S16-16 | Wingman must not appear from nowhere when the skill is picked: fly in from the edge/behind or a short spawn effect | Полёт и манёвры | done 06.11: PR #566, behind F1 `wing_arrive` (off until Kanta's «ок», R-22). A permanent wingman added mid-sortie flies in from beyond the screen edge behind (1329 px), like a replacement; temp «Грачата» unchanged |
| S16-17 | «Ремонт в воздухе» (`cards.gd:69`, cat «Ремонт», max 99) — why is it a module? Kanta questions it (`air_repair.png`); the card category says «Ремонт», check what screen/slot shows it as a module and fix label or slot | Интерфейс + Геймдизайн | done 06.11: already took no slot; the pause screen no longer shows it as a module tile |
| S16-18 | Enemy missiles hitting the player should also explode with a light blast (visual/sfx) | Эффекты боя | done 06.11, PR #569, behind F1 `fx_s16` (off until Kanta ok, R-22) |
| S16-19 | Bomber flight (wingmen/formation): sturdier at the sides and front, vulnerable zone when attacked from behind. Rules/balance — needs «yes» | Геймдизайн | done 06.11 behind F1 `bomber_rear` = 1: armour nose and sides (115°) ×0.5, tail ×1.25 |
| S16-20 | Course gun options: text of the selected option is too bold (`gun_options.png`, «Спарка ✓ выбрана», «Зажигательные ✓ выбраны») | Интерфейс | done 06.11, PR #567 — check in the next build |
| S16-21 | Check «Economy»: resources look excessive (see S16-09; compare income per sortie with prices from the s16 logs) | Геймдизайн | price 50 000 in PR #564; income left as is (recommended), check how fast hangar upgrades are bought in s17 |
| S16-22 | Rerolls/bans/pins: add perks and achievements that give them; also reward them for activities. Starting values: 3 rerolls, 1 ban, 2 pins. Now `main.gd:49-52,328-329` uses `TEST_PICKS = 10` for rerolls and bans (test value) plus class and medal bonuses (`medals.gd:69-71`). Recommendation in the thread reply | Геймдизайн → Прокачка | done 06.11: crew ranks 4/8/12/16, medals «Разведка боем» and «Штабист», +1 reroll per task (`balance/picks.gd`); starting values in PR #564 |
| S16-23 | Transport plane («Транспортник», `transport.gd`) should try to escape from us, not circle | Геймдизайн (активности) | done 06.11 behind F1 `transport_flee` = 1: spotted at 900 px or hit, turns away 22°/s, speed ×1.3 |
| S16-24 | Wingman «nose-pokes» into the player again (the ramming/«утыкание» bug seen before) | Полёт и манёвры | done 06.11: PR #566, behind F1 `wing_avoid` (off until Kanta's «ок», R-22). Unit test `wing_avoid_test`: poke frames 70–90 → 0 on hard turns; real sortie `--wingtest`: fighter 83 → 12, bomber 180 → 6, no overlap |
| S16-25 | At 16:15 («Оса») three text lines overlap: «Разведка: база противника…», «ЭВАКУАЦИЯ…», «База противника…» (frame `evac_overlap_fighter.jpg`) | Интерфейс | done 06.11, PR #567 — check in the next build |
| S16-26 | A new «база противника» task is issued during the evacuation after the «Крепость» is killed — looks superfluous; Kanta decides | Геймдизайн | done 06.11: no new task while the evacuation gates are open |
| S16-27 | Evacuation window burns out 2–3 times per sortie while the player fights (gate 1 of 3 moves away); is the «Окно эвакуации закрыто» hint understood? | Интерфейс + Геймдизайн | done 06.11 behind F1 `evac_hold` = 1: the window after the final boss with the goal done does not close |
| S16-28 | System mouse arrow is still visible on cutscenes and in dialogues (`main.gd:204` hides it only in playing/cutscene; probably related to S16-01) | Интерфейс | done 06.11, PR #567 — check in the next build |
| S16-29 | Turn bank: the plane levels out of the bank too fast (Kanta 06.11). Visible bank now rolls in ×0.75 and levels out ×0.5 slower, flight bank untouched; F1 `bank_soft` (+ `bank_soft_in/out`), off until Kanta's «ок» (R-22). PR #573 | Замедлить выход самолёта из крена | on by default since PR #591 (R-22 change 06.11); на проверке в следующей сборке |
| S16-30 | Kanta 06.11: markers say «100 м» while we fly a plane — show real-feeling distances. Display only: `DistText` (`dist_text.gd`), 0.6 m per world px picked from cruise speed (fighter ≈ 840 km/h), «300 м» / «5,3 км» on edge markers, task plates, fortress and warship captions | Сделать реальные расстояния на указателях | merged #575 06.11 — check in the next build |
| S16-31 | Kanta 06.11: hangar plane stats as real numbers, not bars (damage per second with air / ground factors, km/h); the table over the model looked bad, hover over a node upgrade shows its gain in green; rank and «Э+» cards in real «now → after» numbers. Rarity on «Э+» and mastery rank cards: Kanta chose (1) make it count → +15 % × (k − 1) group damage like weapon upgrades | Показать реальные цифры характеристик самолётов | merged #578, #581, #587 06.11 — check in the next build |
| FR06-01 | Flights review 06.11, items 1.1–1.3, 3, 5.1 (Kanta «Да»): synergy texts and recipe line under `build_pairs`, «Наработка» off under it, telemetry `player_missiles_launched`, plane node prices ×2. Item 1.4 (last-mount warning, `SynPairs.closes`, tag «ЗАКРОЕТ СВЯЗКУ») done after Kanta «да» | Геймдизайн | done 06.11

## Правки по сборке 3.5-s15

Items from the s15 recordings and log review (04.11.2026, `/mnt/project-files/s15_review-20261104T204803-22d9.md`); Kanta 04.11: «Отдавай». ID number = review item number; balance items 21–24 are GD-14…GD-17, aces items 16–20 go to the aces thread. Does not start a new build.

| ID | Task | Thread / owner | Status |
| --- | --- | --- | --- |
| S15-01 | False «ИЛИ-ИЛИ» screen from level 36: an ordinary row of 4 cards looked like the mastery fork (`hud_cards.gd:56` checked only the first card) | Починить интерфейс по замечаниям s15 | merged #548 04.11, check in the next build: `Cards.is_fork` + unit test |
| S15-02 | Fortress title cut («ПАДАЕТ И ИДЁТ НА ТА») | Починить интерфейс по замечаниям s15 | merged #548 04.11, check in the next build: boss name shrinks to the bar width (40 → down to 24 px) |
| S15-03 | Half-screen skill tooltip pops up in flight when the cursor crosses the skill bar | Починить интерфейс по замечаниям s15 | merged #548 04.11, check in the next build: no skill tooltip in flight (descriptions stay on cards and in the hangar) |
| S15-04 | System mouse arrow next to the gunsight and over cutscenes | Починить интерфейс по замечаниям s15 | merged #548 04.11, check in the next build: cursor hidden in flight and cutscenes, shown on screens with buttons |
| S15-05 | Centre texts on top of each other (evacuation, tanker, task, banner) | Починить интерфейс по замечаниям s15 | merged #548 04.11, check in the next build: one stack under the boss bars, evacuation and tanker lines on a plate; the «На волоске!» float over the plane not changed |
| S15-06 | Cut captions: «НАВОДЯЩИЕСЯ РАК…», «бомбы и ракет…», «разворот к враг…» | Починить интерфейс по замечаниям s15 | merged #548 04.11, check in the next build: left column 250 → 272 px, the skill bar grows upwards for a long hint (up to 3 lines) |
| S15-15 | «МЫШЬ куда лететь» hint on every sortie | Починить интерфейс по замечаниям s15 | merged #548 04.11, check in the next build: first 3 sorties only, key of the chosen control scheme |
| S15-07 | «Playback can only happen when a node is inside the scene tree» in the log | Ускорить большие бои | merged #549 04.11: the Fortress drone started before the Fortress entered the world, now autoplay; check the next build's log |
| S15-08 | VRAM in «Битва асов» 3460 MB vs 2600 MB in the campaign | Ускорить большие бои | merged #549 04.11: skin and hq weapon caches kept the hangar plane's full-size textures after takeoff; cleared on takeoff (cloud, Kanta's profile: combat textures 392 → 224 MB). Also restored 363 turret `.import` files emptied by c5c98e82. Check `vram_mb` aces vs campaign in the next build's log |
| S15-09 | Pale patches with a stair-step «pixel» edge all over the Highlands (ridge snow and the takyr border followed relief triangles) | 3D-модели по плану Kirill | merged #557 05.11 behind F1 `sand_edge` (Kanta «ок» 05.11: on by default, #561): wider band broken by noise; a few rock-outcrop patches keep straighter edges |
| S15-10 | Scorch marks too black and large; a dark strip along cliffs | 3D-модели по плану Kirill | merged #558 05.11 behind F1 `scorch_soft` (on by default since #561, Kanta «ок» 05.11): burnt-brown soft mark, 0.7 size, not on slopes over ~40°. The long band along cliffs is the canyon sun shadow, not scorch (not changed) |
| S15-11 | White clouds hide enemies; the left weapon column is unreadable over a cloud | 3D-модели по плану Kirill | merged #559 05.11 behind F1 `cloud_soft` and `hud_backing` (on by default since #561): clouds without Forward+ over-exposure, shaded underside, thinner over the fight; column backing 0.38 → 0.78 |
| S15-12 | Own plane lost under effects in the last minutes | 3D-модели по плану Kirill | merged #560 05.11 behind F1 `own_plane_read` (on by default since #561): effects fully clear over the plane, zone 2.2 → 2.8 lengths, thin hull outline above effects; bright sparks still not faded |

## Правки по сборке 3.5-s14

Замечания Kanta 31.10.2026 по тестовой сборке 3.5-s14 (13 пунктов, номер = номер замечания; S14-14…17 — мелочи самопроверки сборки) и страница «что проверить» (R-18, https://claude.ai/artifact/Q2AKgd9VCCB5KFd8HpWSS3). Правки с ощущением и эффектами идут за переключателем до «ок» (R-22). Баланс — не чаще раза в сборку.

| ID | Задача | Тред / владелец | Статус |
| --- | --- | --- | --- |
| S14-01 | В карточке выбора торчит уголок (скос рамки карточки выступает за рамку) | Меню и ангар | сделано 31.10, PR #508 (метка идёт по скосу рамки) и #512 (подсветка выбранной карточки больше не выступает углом на скосе) |
| S14-02 | На «Ките-2» какие-то бугры на корпусе | 3D-модели | сделано 31.10 (#527): гребень, корень крыла и передняя кромка выровнены, серые плиты над гондолами убраны; остались мелкие зубцы на внешнем предкрылке |
| S14-03 | Редактор знаков: модель неудобно держать при нанесении, нужен отъезд камеры (zoom out) | Меню и ангар | сделано 31.10, PR #508: Ctrl + колесо и кнопки «Вид − / +» отдаляют камеру всегда |
| S14-04 | Активности (ПВО) всё ещё появляются рядом с игроком: не в видимости и не ближе чем за 2 экрана | Разобрать генерацию карты Нагорья | слито #507 31.10, проверить в следующей сборке |
| S14-05 | На земле остались ровные круглые пятна (выровненные площадки), так быть не должно; запросить глубокий разбор генерации карты | Разобрать генерацию карты Нагорья | слито #507 31.10, проверить в следующей сборке |
| S14-06 | Плазменная бомба висит в воздухе | 3D-модели | по кадру Kanta 31.10 «висело» пятно «снега» над землёй (S14-18): новый вид плазмы включён по умолчанию #523 (Kanta: «оставим, посмотрим в игре»), проверить в следующей сборке |
| S14-07 | Индикатор тяги «Газ [W/S]: 100%»: название. Решение: переименовать в «Тяга» (ключ перевода, `.po`); вопрос Kanta закрыт ответом | Интерфейс боя | сделано 31.10: «Скорость [W/S]» (Kanta: вместо «Тяга»), en «Speed», zh «速度» |
| S14-08 | Ведомый ведёт себя неестественно: резко останавливается и разворачивается (под R-22: за переключателем) | Геймдизайн (ИИ ведомых) | сделано 31.10: PR #502 (за переключателем F1 `wing_smooth`), «ок» Kanta 31.10 — включено по умолчанию (PR #506). Догадки автотеста s14 покрыты: нос задаёт курс, скорость идёт за носом; «прыжка» в слот нет (только мягкая подтяжка ближе 60 пикс.); разворот 160 °/с теперь с плавным входом и выходом. Самостоятельные заходы раз в 3–6 с оставлены: это задача ведомого, не поломка строя; заход тоже летит плавно |
| S14-09 | Одинаковые карточки «Калибр» (на одном экране выпали две с одним названием: ближний бой и ракета В-3) | Прокачка | сделано 31.10, PR #500: одноимённые ветки разных оружий подписаны оружием («Калибр: Турели») |
| S14-10 | Завис «кусок» текстуры взрыва в горе | Разобрать генерацию карты Нагорья | сделано 31.10, PR #517: воронка карты стала меткой на земле |
| S14-11 | Стартовый экран: самолёты летят в одну сторону к верху экрана, не по кругу | Меню и ангар | сделано 31.10, PR #508: звено летит прямо к верху экрана, маршрут по реке убран |
| S14-12 | Просмотр оружия в ангаре: красивый фон (ангар самолётов) | 3D-модели | сделано #533 01.11 |
| S14-13 | Естественная окраска ракет, оружия и подставок (пилонов) | 3D-модели | сделано #533 01.11 |
| S14-14 | Самопроверка: плитка на дорожках кишлака полосами с резкими краями | 3D-модели | сделано #533 01.11 |
| S14-15 | Самопроверка: земля с высоты боя местами в светлых пятнах (проверить вместе с S14-05) | Разобрать генерацию карты Нагорья | проверить на следующей сборке: вероятно та же причина, что S14-05 (догадка) 31.10 |
| S14-16 | Самопроверка: фугасная бомба ур. 3 и 5 и ракеты «srm» ур. 1 и 3 выглядят одинаково | 3D-модели | сделано #533 01.11 |
| S14-17 | Самопроверка: у медали «Небо над Шахрисангом» обрезана подпись | Меню и ангар | сделано 31.10, PR #508: длинное имя медали уменьшается до 13–11 px |
| S14-18 | Autotest finding: after ~3 s the plasma bomb fire patch looks like a pixelated white-blue "snow" patch (related to S14-06, which was not reproduced; frame from Kanta needed). Autotest page https://claude.ai/artifact/XSfCTy7c92Aip1Doathf3B | Эффекты боя | сделано 31.10, PR #514, #520; включено по умолчанию #523 (Kanta: «Ну давай пока так оставим бомбу, посмотрим в игре»). Взрыв — готовый взрыв бомбы в цветах плазмы, затем зона 4 с горит голубым пламенем с холодным светом, на земле гарь с голубыми трещинами. Кадры https://claude.ai/artifact/G4mEqzEHfzYKkEKtXFiumu; проверить в следующей сборке |
| S14-19 | Autotest guess for S14-10: flat crater quads on slopes in `render3d.gd` `_sync_craters` | Эффекты боя | сделано 31.10, PR #514, за `fx_s14`: следы воронок и копоти не тянутся по обрывам (normal fade у декалей). Сам S14-10 по кадрам Kanta — скорее висящая плита-скала, её ведёт тред карты |
| S14-20 | Autotest: first sortie of a new build loads in 76 s, the second in 0.7 s (guess: shader compile); VRAM 2.2-2.9 GB, 1.75 GB of it hangar textures | Ускорить большие бои | merged #515 (load_ms counted the aces card draft; hangar view freed on takeoff) and #543 (590 combat model textures BC7, hangar lossless; cloud: textures 1097 -> 592 MB at «Высокое»). Check VRAM in the next build's PC log |
| S14-21 | Autotest: tilted brown slab in the sea on Leviathan (Archipelago) | 3D-модели | передано 31.10 |
| S14-22 | Autotest signal: bot gets ~400 kills per sortie on Kit vs ~600 on Osa and Grach (no change without Kanta's yes) | Геймдизайн | разобрано 31.10: только сигнал, разговор с Kanta не нужен. Бот на «Ките» плохо держит бой (s13: по асу 2–12 тыс. урона за 3 мин), а у «Кита» роль — прочность и бомбы по земле, не число убийств. Сверить по живым вылетам Kanta на «Ките» в следующей сборке; правок без его «да» нет |

## Правки по сборке 3.5-s10

Замечания Kanta 23.10.2026 по тестовой сборке 3.5-s10 (12 пунктов + разбор лога боя «Осы», номер = номер замечания). Работа по тредам начнётся после слова «готово» Kanta (замечания ещё могут дополняться); разбор лога — `docs/playtest/3.5-s10/analysis-fighter-biome2.md`. Баланс — по методике, не чаще раза в сборку.

| ID | Задача | Тред / владелец | Статус |
| --- | --- | --- | --- |
| S10-01 | Выбор мастерства перерисовать так же, как экран повышения опыта (карточки) | Понятность игры для новичков | на проверке в следующей сборке (бой: экран «или-или» — карточки веток разных цветов, красная плашка «вторая закроется»; ангар не менялся) |
| S10-02 | Второй биом: ПВО и наземная техника заезжает на воду — убрать с воды на равнины, на воде свои активности | Второй биом | слито PR #338, проверить в следующей сборке |
| S10-03 | При выпуске тепловых ловушек ракеты уходят в них и взрываются | Бой: правки по 3.5-s10 | на проверке в следующей сборке (PR #337) |
| S10-04 | Ракеты врагов всё ещё вылетают вбок или назад: S9-23 исправил только ракеты босса и аса, остальные пуски (ракетоносец, экраноплан, «Крепость», конвой, вертолёт, корабли) идут прямо из текущей позиции — причина в разборе лога | Бой: правки по 3.5-s10 | на проверке в следующей сборке (PR #337) |
| S10-05 | Ракеты и у игрока, и у врагов: вылет вперёд, затем манёвр на цель | Бой: правки по 3.5-s10 | на проверке в следующей сборке (PR #337) |
| S10-06 | Второй биом: вода плохого качества даже на максимуме — сильно поднять детализацию | Второй биом | слито PR #338, проверить в следующей сборке |
| S10-07 | Уничтоженная техника врага лежит тёмным куском — выглядит неестественно (обломки, воронка, выгоревшая рама) | Архипелаг: правки по 3.5-s10 | слито PR #338, проверить в следующей сборке |
| S10-08 | Плазменная бомба: взрыв как будто в воздухе (должен быть на земле) и эффект — «фиолетовое желе»; переделать | Бой: правки по 3.5-s10 | на проверке в следующей сборке (PR #337) |
| S10-09 | У тепловых ловушек мастерство как у ракет В-В (Калибр, Скорострел): урон ловушкам не нужен — заменить на подходящие (шанс увода, радиус, перезарядка) | Бой: правки по 3.5-s10 | на проверке в следующей сборке (PR #337) |
| S10-10 | След на воде за водной техникой при движении | Второй биом | слито PR #338, проверить в следующей сборке |
| S10-11 | Уменьшить размер взрывов и дыма от них — закрывают весь экран | Бой: правки по 3.5-s10 | на проверке в следующей сборке (PR #337) |
| S10-12 | Автоматическое оружие (плазменная бомба) часто промахивается: улучшить упреждение / выбор цели | Бой: правки по 3.5-s10 | на проверке в следующей сборке (PR #337) |
| S10-13 | Бой «Осы» во втором биоме слишком лёгкий, после 10-й минуты всё прокачано; ракеты врагов малоэффективны — варианты баланса в разборе лога (опыт от убийств, цепочки «Карусели»/«Волчьей стаи», ловушки) | Бой: правки по 3.5-s10 | на проверке в следующей сборке (PR #337) |
| S10-14 | Главное меню: строка «Запчасти: … · экипажи: Оса · Грач · Кит» налезает на кнопки «Ангар» и «Настройки» (скриншот Kanta 24.10) | Понятность игры для новичков | на проверке в следующей сборке: строка «Запчасти · экипажи» убрана редизайном главного меню (PR #369, UI-01), наложения нет |
| S10-15 | На Нагорье после Архипелага «слышен звук воды» (Kanta 24.10). Причина: в фоне гор был слой ветра в листве (шелест 300–3000 Гц), тот же, что в фоне моря, — на слух как прибой; переключение фона по биому работает (проверено скриптом). Фон гор пересобран из одного низкого порывистого ветра | Звук и музыка | ✅ 24.10, ждёт проверки Kanta на слух |
| S10-16 | «Грачата» накладываются на уже имеющегося ведомого (Kanta 24.10): ряды строя за первым отступали всего на 30 пикс., меньше размера ведомого; теперь шаг — размер ведомого + зазор, новые ведомые прилетают к своему месту | Бой: правки по 3.5-s10 | на проверке в следующей сборке (PR #354) |

## Правки по сборке 3.5-s9

Замечания Kanta 23.10.2026 по тестовой сборке 3.5-s9 (24 пункта, номер = номер замечания). Исполнитель назначен 23.10, работа идёт по тредам; баланс — по методике, не чаще раза в сборку.

| ID | Задача | Тред / владелец | Статус |
| --- | --- | --- | --- |
| S9-01 | Экран вылета: навык класса («Ёлочка», «Боевой разворот») выглядит доступным, но не переключается; нет описаний навыков | Отзывы внешних тестеров | на проверке в следующей сборке (PR #331) |
| S9-02 | Самолёт ур. 1 и ур. 2 — разные машины, прокачка у каждого своя; в s9 улучшались сразу обе (ангар улучшал выбранный в вылет, а не тот, что на виде) | Отзывы внешних тестеров | на проверке в следующей сборке (PR #333) |
| S9-03 | Модели оружия в ангаре (3D-вращение) засвечены и выглядят неестественно: матовый материал и свет | 3D-модели по плану Kirill | принято Kanta 23.10 по кадрам (#332), на проверке в следующей сборке |
| S9-04 | Турель «Грача» в ангаре почти не меняется при улучшении; в ангаре не вращается (вращается только на самолёте) | 3D-модели по плану Kirill | принято Kanta 23.10 по кадрам (#332), на проверке в следующей сборке |
| S9-05 | Подсказка при наведении на выбранные элементы и карты модернизаций на экране повышения уровня (что это за оружие) | Отзывы внешних тестеров | на проверке в следующей сборке (PR #331) |
| S9-06 | Ведомый на резком вираже застывает и втыкается носом в игрока: брать вираж шире и облетать | Отзывы внешних тестеров | на проверке в следующей сборке (PR #331) |
| S9-07 | Нагорье: квадратные заборчики с деревьями у городка накладываются поверх протоки реки | 3D-модели по плану Kirill | принято Kanta 23.10 по кадрам (#329), на проверке в следующей сборке |
| S9-08 | Нагорье: протока возле города накладывается на окопы и оборонительные позиции | 3D-модели по плану Kirill | принято Kanta 23.10 по кадрам (#329), на проверке в следующей сборке |
| S9-09 | Нет ощущения веса и инерции самолёта (отзывы тестеров): Ж1 «показать вес» перенести из EX-11 в текущие, плюс B-05 | Отзывы внешних тестеров | на проверке в следующей сборке (PR #331; Kanta 23.10: модули без веса, «Оса» как сейчас) |
| S9-10 | Переработать панель паузы: текст налезает друг на друга, нечитаем (скриншот Kanta) | Отзывы внешних тестеров | на проверке в следующей сборке (PR #331) |
| S9-11 | Ас в догфайте на 7-й минуте убился о игрока, пока тот летел прочь: переработать поведение и эффективность | Отзывы внешних тестеров | на проверке в следующей сборке (PR #331) |
| S9-12 | Потеря ведомого — сообщение по радио | Отзывы внешних тестеров | на проверке в следующей сборке (PR #331) |
| S9-13 | Дымные следы ракет идут над самолётом, хотя пуск из-под него | Отзывы внешних тестеров | на проверке в следующей сборке (PR #331) |
| S9-14 | Панель радио почти незаметна: сделать крупнее | Отзывы внешних тестеров | на проверке в следующей сборке (PR #331) |
| S9-15 | После 35-го уровня прокачка неинтересна: мало вариативности, нет ощущения отказа от чего-то. Варианты — Kanta | в работе (Отзывы внешних тестеров): вариант 1+2 — ветки мастерства после 35-го уровня и редкие «или-или» карточки (Kanta 23.10) | на проверке в следующей сборке (PR #333) 
| S9-16 | Навык «Звуковой удар»: звук двигателя и след при ускорении; ударная волна рябью по воздуху вместо круга | Отзывы внешних тестеров | на проверке в следующей сборке (PR #331) |
| S9-17 | Убрать стартового ведомого у «Осы» (только получить в вылете) | Отзывы внешних тестеров | на проверке в следующей сборке (PR #331) |
| S9-18 | Убрать стартовых ведомых у «Кита» (только получить в вылете) | Отзывы внешних тестеров | на проверке в следующей сборке (PR #331) |
| S9-19 | «Кит»: бомбы и НАР по ПКМ неудобны — варианты управления — Kanta | отложено: Kanta вернётся после доп. тестов (23.10) |
| S9-20 | Босс «Крепость»: после повреждения двигателей чёрный дым и попытка уйти, а не кружить | Отзывы внешних тестеров | на проверке в следующей сборке (PR #331) |
| S9-21 | Белая раскраска «Кита» на Нагорье слишком яркая, засвечена | 3D-модели по плану Kirill | принято Kanta 23.10 по кадрам (#330), на проверке в следующей сборке |
| S9-22 | Вращающийся винт вертолёта выглядит чёрным пятном | 3D-модели по плану Kirill | принято Kanta 23.10 по кадрам (#330), на проверке в следующей сборке |
| S9-23 | Ракеты босса не должны лететь сразу назад, когда игрок за ним: вылет вперёд, манёвр, наведение на игрока или ведомых | Отзывы внешних тестеров | на проверке в следующей сборке (PR #331) |
| S9-24 | Первого босса не пройти: у «Осы» не хватает живучести, у «Кита» урона по воздуху; разобрать по логам, баланс по методике | Отзывы внешних тестеров | на проверке в следующей сборке (PR #331, #333) |
| S9-25 | Вражеский вертолёт «Сарыч»: залп — настоящие НАР с дымным следом (Kanta 23.10) | Отзывы внешних тестеров | на проверке в следующей сборке (PR #334) |
| S9-26 | Прицел бомб всё ещё выглядит висящим в воздухе — должен читаться как метка на земле (Kanta 23.10; раньше S7-20, BM-01) | Отзывы внешних тестеров | на проверке в следующей сборке (PR #334) |

## Бой и баланс

Тред «Бой, звук и производительность». Методика баланса — R-10 (раздел «Процесс»).

| ID | Задача | Тред / владелец | Статус |
| --- | --- | --- | --- |
| OT-01 | Operation side objectives (Kanta 06.11, item 3 of the «Подготовка и вылет» message): two objectives per Highlands operation that match what it is about («Перевал» — 3 columns, 2 AA sites; «Сухое русло» — 3 AA sites, 2 columns; «Крепости» — 3 strongholds, 2 columns; «Небо над Шахрисангом» — 2 ace duels, 2 transports), +60 parts each, each operation its own activity order; counters in «Цели вылета», list on the operation card (✓ once ever done), line on the results screen. Optional, no timers; Archipelago waits (on hold). F1 `op_tasks` (R-22). `game/scripts/balance/op_tasks.gd`, `op_tasks.gd` | Добавить внутренние задания в операции | merged 06.11, PR #574 (bot «Перевал» 15 min: both done at 8:08 and 12:10); card list wired by «Подготовка и вылет»; check in s17 |
| EX-01 | 6 мест под модули за вылет: места заняты — выпадают только улучшения взятого; «Быстрая перезарядка» слабее (одна группа подвесов или потолок −40%), так же «весь урон» (Д1 + Д2) | Отзывы внешних тестеров | на проверке в следующей сборке (PR — EX-01/03) |
| EX-03 | Враги без «вальса»: дроны и ракетоносцы заходят и отворачивают вместо орбиты; одновременно атакуют 3–5, остальные ждут на краю; таран — только у помеченного врага (В1 + В2) | Отзывы внешних тестеров | на проверке в следующей сборке (PR — EX-01/03) |
| EX-10 | Потолок живучести в конце вылета: долгий тест 20 мин (Kanta «да» 22.10) показал, что ремонт покрывал 62–98 % полученного урона, главный источник — ремкомплекты с врагов. С 10:00 ремкомплекты падают реже (к 20:00 — 40 %), карточка «Ремкомплект» чинит половину вместо полного ремонта; ремонт стал 51–65 % урона | Отзывы внешних тестеров | на проверке в следующей сборке |
| EX-05 | Проверка, что всё реально собрать: автотест по сценариям «класс × набор оружия» против каждой защиты; методику долгого теста сначала согласовать с Kanta | Отзывы внешних тестеров | готово: все 9 модернизаций собираются, итоги — `docs/playtest/external-2/ex05-results.md` |
| S7-10 | Потолок «напряжения боя» ×4 для сильных билдов — смотреть следующий тест (вариант 2, Kanta) | Бой, звук и производительность | ждёт Kanta (тест после 3.5-s8) |
| S4-09 | Поздний бой: напряжение боя и урон врагов после 7:00 до ×2 к 15:00; проверить по `pk` в минутной строке лога | Бой, звук и производительность | на проверке в сборке 3.5-s8 |
| P5-04 | «Кит» слабее и тяжелее (прочность 250, турели ×1,4, разворот 62%); проверить по логу | Бой, звук и производительность | на проверке в сборке 3.5-s8 |
| B-05 | Вес и грузоподъёмность модулей (штраф за перегруз) — заменит временные эффекты «Планера» и «Узлов подвеса» | геймдизайн | идея |
| B-51 | Эксперименты по кросс-проверке: C1 вариант Б полёта, C2 пороги «Турелей»/«Брони», C3 без прямых очков событий, C4 4 очка перков, C5 веса «Бронебойных»/«Затвора» (`docs/crosscheck/crosscheck-review.md`) — по одному за раз, по методике баланса | геймдизайн | идея |
| GD-01 | Demo player profile in the autotest (plane lvl 1, nodes lvl 2, crew lvl 5) and a sortie metrics table (level at 5/10/15:00, lowest HP, ace fight duration, "would die", repair/taken) — basis for R-10. Review `docs/playtest/gd-review-2026-10-23.md` | Геймдизайн-разбор накопленного опыта | в работе (Геймдизайн-разбор накопленного опыта): method v1 accepted by Kanta 23.10; night runs — noise check and fresh-profile floor |
| GD-02 | First ace (5:00): first-wave ace deals ×0.7 damage to the player, HP unchanged. One balance change per build: after S10-13/EX-10 are checked and measured on the demo profile (GD-01) | Бой: правки по 3.5-s10 | to verify in the next build (PR #412; bot: ace damage −30…45 % counts, HP 5–7 min noise — human check decides) |
| GD-03 | «Кит» bombs: damage +25 % and more ground targets on «Кит»'s path (convoys more often) — bombs give 1.5–9 % of «Кит» damage without modernization. After GD-02, one change per build | Бой: правки по 3.5-s10 | идея (Kanta 23.10, option 1) |
| GD-04 | Late combat for a strong player: threats to dodge instead of thicker enemies (SAM salvos with a warning, bomber wedges, elite waves); the ×4 cap stays (see S7-10) | — | после демо (Kanta 23.10, option 1) |
| GD-05 | Scout (convoy 8×8) to true model scale: length 18 → ~25 px, so its hit zone grows ~40 % and it gets easier to hit. Balance change: after GD-02, one change per build | 3D-модели по плану Kirill | идея (Kanta 24.10) |
| GD-06 | Max HP depends on one card («Бронеплиты»): guarantee it is offered when the plane has none by level 10 (flight analysis of 3.5-s11, Kanta «Б» 25.10; S11-34). One balance change per build | Геймдизайн-разбор накопленного опыта | done (PR #421), next build |
| GD-07 | Remember for later (Kanta «запоминаем на будущее» 25.10): drones and interceptors deal 70–85% of damage to the player, rams are 22–28%; if the target «the player enjoys, not overcomes» needs it, soften drone rams (less damage or a short invulnerability after a ram). Not now: first measure with GD-02, S11-30 and GD-06 | Геймдизайн-разбор накопленного опыта | idea, parked |
| GD-08 | «Fortress» boss HP for «Оса» (605k at k 1.6 against 82k–97k): bot run, class «Оса», max profile, then decide (S11-35) | Геймдизайн-разбор накопленного опыта | done: one share 0.55 for every class (Kanta, option 1), next build |
| GD-09 | «Fortress» phase 1: every live dome turret launches its rail missile once per 12 s (staggered 3 s, cap 4 Fortress missiles in the air), numbers in `balance/fortress.gd`. Bot measurement together with the Fortress phase rework | Геймдизайн-разбор накопленного опыта | done (PR #439 + wing-by-wing PR), next build |
| GD-10 | «Fortress» wing by wing (Kanta 26.10): left wing → right wing + bay → fall. Demo bot in the corridor; upgraded bot not (148 → 180 s, phase 2 50–97 s). After the build: check Kanta's Fortress fights; if phase 2 drags for a human too, candidates are the right domes' fire in phase 2 or the engine point radius (`balance-method.md` §9.2) | Геймдизайн-разбор накопленного опыта | done in code, check in the next build |
| GD-11 | «Оса» dies at the first ace (3.5-s12, 3 of 3): aces flare her missiles at 0.5 (Kanta, card option 2). Bot: flared 36 → 26, ace fight in noise. After the build: check Kanta's «Оса» first-ace fights; if still deadly, next option is the first-ace share cap ≤ 1.0 (`docs/playtest/3.5-s12/osa-first-ace.md`) | Геймдизайн-разбор накопленного опыта | done in code, check in the next build |
| GD-12 | Drones die from 1–2 course-gun hits at any minute (Kanta s13 item 11), `balance/drones.gd`. Bot: «Кит» levels faster, «Грач» would-die 62 → 6. Check in the next build: does the late fight still feel busy, and does pressure stay sane without drones in the measure | Геймдизайн-разбор накопленного опыта | done in code, check in the next build |
| GD-13 | Ace shield regrows only farther than 900 px from the player (Kanta card 27.10, s13 «Кит» vs «Сквозняк» 90 s), `AceBalance.shield_after`. Check in the next build: ace fights of «Кит» and «Грач» near the 24 s target, «Оса» not too short | Геймдизайн-разбор накопленного опыта | done in code, check in the next build |
| GD-14 | s15 item 21, little danger (hull 80–100 % for 15 min, 96 % of damage healed, invulnerable 26 % of the sortie). Options 21.1 post-hit invulnerability 0.7 → 0.55 s (recommended for s16) / 21.2 −20 % top repair source / 21.3 enemy damage ramp from 5:00 / 21.4 keep. Page: https://claude.ai/artifact/UtAJBVVAjweHHDMLXztXX1 | Геймдизайн | done 05.11 (Kanta «сразу»), check s16 log |
| GD-15 | s15 item 22, power spike invisible (damage/min ×10 from min 6 to 14, kills/min flat 200–330: HP ×4 and density ×1.5 caps hit). Options 22.1 density cap 1.5 → 1.8 (after GD-14, FPS check on Kanta's PC) / 22.2 HP cap ×4.8 (not recommended) / 22.3 keep; mostly covered by PG-11 | Геймдизайн | done 05.11 (Kanta «сразу»), check s16 log |
| GD-16 | s15 item 23, 56 card picks per sortie (one per 18 s). Options 23.1 late levels +20 % costlier / 23.2 after lvl 30 one pick per two levels, odd level auto +2 % / 23.3 keep (recommended until the false «ИЛИ-ИЛИ» bug is fixed and the extra picks are traced in the log) | Геймдизайн | done 05.11 (Kanta «сразу»), check s16 log |
| GD-17 | s15 item 24, manual gun 2 % of damage (13k of 579k; vs one ace on «Кит» s13 it was 52k of 61k). Options 24.1 keep (recommended) / 24.2 «обороты» cap +50 → +60 % / 24.3 «Стрелок» archetype in PG-11 | Геймдизайн | ждёт «да» Kanta |
| MD-01 | Medals with small bonuses (Kanta 27.10, option 1): counters, 38 medals, bonuses, hangar tab «НАГРАДЫ», result strip, pictures. Later: liveries/emblems as rewards (art «да»), Steam achievements after the app is registered | Геймдизайн-разбор накопленного опыта | done in code, check in the next build |

**Слито и ждёт проверки Kanta в сборке 3.5-s8** (подробности в архиве, раздел «После теста 3.5-s4: бой»): S4-01, S4-02, S4-03, S4-05…S4-08, S4-10…S4-12 — нырок под самолётами, ловушки асов, цифры урона, ведомые и цель звена, перезарядка ракет, «Крепость», выбор карточки; P5-01…P5-03, P5-05…P5-12, P5-33 — тормоза, тени, бомбы «Кита», ощущение классов, нырок, объёмные взрывы. Статус «на проверке (PR)» в старых таблицах означает, что PR слит до 18.10 (сборка 3.5-s8 собрана из `main` после PR #236); как слияние проверено в игре — не сверялось, это догадка.

## Враги и боссы

| ID | Задача | Тред / владелец | Статус |
| --- | --- | --- | --- |
| EX-04 | Три защиты врагов: броня, помехи, манёвренность — у каждой значок и своё оружие против неё; заход на атаку выгоднее кружения: бонус «на прямой», цели с секторами обстрела и бронёй спереди (А1 + Б1 + Б2) | Отзывы внешних тестеров | броня, манёвренность, помехи и «заход на атаку» — на проверке в следующей сборке (PR — EX-04); звено бомбардировщиков с лобовой бронёй и кормовой турелью (Б2) — на проверке в следующей сборке |
| EX-06 | Механики боссов: щит асов снимается своим способом, опасная атака с предупреждением, подсказки «Крепости» по радио, корпус неуязвим, пока целы турели; убрать «прочность аса = урон игрока за 25–35 с» (Г1) | Отзывы внешних тестеров | на проверке в следующей сборке (PR — EX-06) |
| FB-02 | Резерв: «Твердыня» — наземная крепость в скале как будущий финал (биом 3 или кампания) | геймдизайн | идея (решения нет) |
| P5-21 | Позиция ПВО: бункер стоит, машины прикрывают и сбивают ракеты (запись 15.10; часть сделана в S7-02 и M-37 — актуальность проверить) | Бой, звук и производительность | идея |
| P5-22 | Активности раз в минуту (запись 15.10; актуальность проверить) | Бой, звук и производительность | идея |
| P5-23 | Охота на транспорт под прикрытием (21); свой заправщик уже в игре (B-06), остаток — только охота (запись 15.10) | Бой, звук и производительность | идея |
| B-03 | Мини-боссы на 10-й и 15-й минуте: на Архипелаге есть («Альбатрос», «Сторож»), на Нагорье 15-я минута = финальный босс «Прорыв» — решить, нужны ли мини-боссы Нагорья | геймдизайн | ждёт Kanta |

## Полёт и манёвры

| ID | Задача | Тред / владелец | Статус |
| --- | --- | --- | --- |
| S7-F1…S7-F4 | Наименьший радиус разворота по классу, инерция на виражах, 4 вида манёвров асов, нырок над горами не уходит в рельеф (подробно — архив, «Полёт и манёвры») | Полёт и манёвры | на проверке в сборке 3.5-s8 (в таблице было «В PR» на 18.10; слияние до PR #236 не сверялось — догадка) |
| B-11 | Проверка на геймпаде / Steam Deck (жалоба №1 в жанре) | программист | идея |
| AB-01 | «Битва асов» — тестовый режим (Kanta 26.10, вариант 1): «Оса» с ангарной настройкой против перехватчиков, ракетоносцев и частых асов, тяжёлый полёт, реалистичный урон; план `docs/superpowers/plans/2026-10-26-aces-battle-test.md`. Дальше — ощущения Kanta в игре; PvP решаем после раннего доступа | Продумать режим «Битва асов» | слит #436 26.10, ждёт пробы Kanta в следующей сборке |
| AB-02 | «Битва асов»: не предлагать оружие только против земли (ракета В-З, бомбы, фугасная, плазма), раз наземных целей нет; общее правило по наличию наземных целей (Kanta 04.11) | Убрать ракету В-З из битвы асов | слит #550 04.11, проверить в следующей сборке |
| AB-03 | «Битва асов» после s15: асы прочнее (ракета игрока — не больше 1/4 аса), асы пускают ракеты, уходят от столкновения, чаще заходят в атаку; скорость +20 %, камера дальше; всё за ползунками F1 `aces_*` до «ок» Kanta (04.11) | Убрать ракету В-З из битвы асов | слит #550 04.11, проверить в следующей сборке |
| AB-04 | Разбор s15 п. 16: перехватчики в «Битве асов» тоже отворачивают до тарана (не на 250 пикс.), вместе с AB-03 за ползунком F1 `aces_ai` | Убрать ракету В-З из битвы асов | слит #550 04.11, проверить в следующей сборке |
| AB-05 | Разбор s15 п. 13: радио не повторяет фразу, пока не прозвучат остальные (общая память на всех асов); по 4–6 фраз на событие у асов, по 4 у ведомого («сбит», «иду к вам»); en и zh переведены | Убрать ракету В-З из битвы асов | слит #550 04.11, проверить в следующей сборке |
| AB-06 | Разбор s15 п. 14: совет про таран упоминает «Бронещит», только если он есть у самолёта; в отчёте нет двойных кавычек («ИСТРЕБИТЕЛЬ «ОСА»») | Убрать ракету В-З из битвы асов | слит #550 04.11, проверить в следующей сборке |
| AB-07 | Разбор s15 п. 18: в «Битве асов» на панели нет запчастей, топлива и строки «Серия · опыт» | Убрать ракету В-З из битвы асов | слит #550 04.11, проверить в следующей сборке |
| AB-08 | Разбор s15 п. 19–20: после гибели 35–40 с выбора до нового боя; между асами пусто (впечатление). Kanta 04.11: оба пункта не трогаем (выбор «не бесит»; пустоту смотрим после AB-03) | Убрать ракету В-З из битвы асов | отложено Kanta 04.11 |
| AB-09 | «Битва асов», «Оса»: E — полупетля (выход обратным курсом, носом на врага сзади в ±60°; наверху ракеты теряют цель, пули и таран проходят снизу в средних 70 % манёвра, потом 3 с пушка ×2; прокачка и «Чёртово колесо» разворота сохраняются, скорость на выходе ×0,7, 1,2 с) вместо боевого разворота; V — петля (выход тем же курсом почти в той же точке, ас на хвосте проскакивает; 1,8 с, перезарядка 10 с, скорость ×0,85) вместо нырка. Переключатель F1 `aces_loops` (вкл.), числа — ползунки `aces_*loop*` (Kanta 10.11) | Добавить Осе петлю Иммельмана | слит #617 10.11, ждёт пробы Kanta в следующей сборке |

## Прокачка и ангар

| ID | Задача | Тред / владелец | Статус |
| --- | --- | --- | --- |
| EX-02 | Путь сборки виден игроку (образец «книга эволюций» FatalZone, скриншот Kanta — в плане): справа на экране выбора — оснащение и строки «оружие + модуль = связка» с пустой клеткой; на карточке — к какой связке или модернизации ведёт; справочник показывает, чего не хватает | Отзывы внешних тестеров | на проверке в следующей сборке |
| EX-12 | Карточки улучшений «сочные», как в FatalZone и Sublight: крупный значок, рамка и свечение по редкости, фон по виду, уровень делениями, анимация. Сначала 2–3 макета картинкой рядом с образцами — выбирает Kanta, потом код. Вместе с EX-02 | Отзывы внешних тестеров | на проверке в следующей сборке |
| P-22 | Приоритет каждого ведомого в «Подвесах» (ждёт доработки ведомых в `wingman.gd`) | Бой, звук и производительность | идея |
| P-36b | Связки и навыки с «количеством» ракет (Карусель, Волчья стая, Стальной ёж, «Ёлочка», «Парад») — по логу ракет в воздухе | геймдизайн | идея |
| B-19 | Перки ступеней 3–4, слот навыка 3 (ступень 3 веток оружия сделана — U-07) | геймдизайн | идея |
| PG-01 | Deeper upgrades, stage 1: 3rd hardpoint group (node «Узлы подвеса» lvl 2), short-range heat AAM («Оса 2», hypothesis), guided air-to-ground missile, HE bomb («Кит»), course guns (standard / twin / heavy) and ammo per plane, per-plane weapon sets, wingman timings, Sketchfab weapon models, bomb cart stand, volumetric weapon icons. Merged 24.10 in PR #382 ahead of GD-02/03 (Kanta). Open: missile stands, module/skill icons, «Оса 2» AGM +5 % A/B result | Углубить прокачку для демо | на проверке |
| PG-02 | Deeper upgrades, stage 2: incendiary tanks, air mines, jammer pod; modernizations for the new weapons (anti-radiation missile dropped from this stage, Kanta 24.10 — see PG-04) | Углубить прокачку для демо | после PG-01 |
| PG-04 | Update «Интенсивное облучение» (Kanta 24.10, after the current mechanics are polished): radar synergy — enemy radars on hills raise incoming damage to the player while they illuminate him (HUD warning «облучение» + damage-up marker); anti-radiation missile and the «Ласка» wingman counter them. Not now | — | идея |
| PG-05 | Analyse choice on plane 1 after the weapon-per-plane sets (Kanta 24.10: «Оса 1» and «Кит 1» have 4 hardpoint weapons for 3 groups; short-range missiles only on «Оса 2», so not in the demo). Use balance logs of a build | Углубить прокачку для демо | идея |
| PG-03 | Deeper upgrades, stage 3: hangar «комплектация» (engine, wing, avionics sidegrades), weapon branch tier 1 changes behaviour, 3–4 new synergies | Углубить прокачку для демо | после PG-02 |
| PG-06 | Upgrade variety, package (proposal 31.10, `docs/progression/upgrade-variety-2026-10-31.md`): weapon **profiles** — a fork at weapon lvl 3, 2 profiles in the sortie + a 3rd from the hangar, stage 1 `aam`/`srm`/`agm`/`rockets`; second modernization per weapon + modernizations for `srm`/`agm`/`hebomb`; hangar tier 1 for the new weapons, tier 2 unlocks profile C. Kanta 31.10 «делай»: package А, fork at lvl 3, 2 + hangar, mastery = profile ranks (PG-07 3b folded in). Plan `docs/superpowers/plans/2026-10-31-weapon-profiles.md`, 3 PRs. PR 1 (profiles of `aam`/`srm`/`agm`/`rockets`, flags `--wprofile`, `--profileshot`) merged 31.10 in #509, frames https://claude.ai/artifact/QQ7wvuSM4GGpBcWiFSkZuh; PR 2 (8 modernizations: «Стая», «Молот», «Шершни», «Сторож», «Кувалда», «Кассета», «Землетрясение», «Напалм», flag `--wevo`) merged 31.10 in #528; PR 3 (hangar tiers 1–2 for `srm`/`agm`/`hebomb`, tier 2 opens the 3rd profile, mastery = profile ranks +12 %, flag `--wrank`) merged 31.10 in #530. Numbers are first guesses: balance run per pair after agreeing the method with Kanta | Расширить прокачку: части 2 и 3 | на проверке в игре |
| PG-07 | Mastery after lvl 35 per weapon: 3a own pairs instead of «Скорострел / Калибр» (removes the cause of S14-09) or 3b ranks of the chosen profile after PG-06 (recommended). Kanta 31.10: 3b, done in PG-06 PR 3 (31.10) | Расширить прокачку: части 2 и 3 | на проверке в игре |
| PG-08 | Modules with a behaviour line at lvl 3 (as `msl_head` has): ramming, afterburner after a dodge, reload on an ace kill, blast edge, etc. — proposal §3.4; after PG-06 | Расширить варианты прокачки | ждёт Kanta |
| PG-09 | Sortie doctrine at the course screen (VS arcana): «Налёт», «Одиночка», «Снабжение», «Охота на асов», «Старая школа» — proposal §3.5; Kanta 31.10: after the demo | Расширить варианты прокачки | идея |
| PG-10 | «Битва асов» draft from its own pool, starting at weapon lvl 3 so the first pick is a profile — proposal §3.7; Kanta 31.10: after the demo | Расширить варианты прокачки | идея |
| PG-11 | Build depth (Kanta 04.11: «тупо качай ракеты», wants build collecting). Proposal: Б3 archetypes with rule thresholds at 3/6/9 cards (Ракетчик, Бомбёр, Стрелок, Командир звена, Манёвренный), Б1 synergies need two different weapons/systems (+6–8 new), Б5 build album in the hangar, Б4 3–4 trade-off cards; Б2 target statuses and Б6 doctrine (= PG-09) after the demo. Order s17 Б3+Б4, s18 Б1+Б5. Page: https://claude.ai/artifact/UtAJBVVAjweHHDMLXztXX1. Kanta 05.11: all recommended. Part A (Б3 seven archetypes with per-tag thresholds, Б4 four trade-off cards, F1 `build_arch`) — thread «Добавить архетипы и карты «плюс за минус»»; part B (Б1 + Б5) merged in #554 | Геймдизайн → Прокачка | A: на проверке в игре (s16) |
| MO-01 | Mode «Долгий вылет» (endless after the Fortress, YAZS Endurance): danger grows without a cap, time record and its build in the hangar; after PG-11, s19. Also Р2 challenges and Р4 daily sortie (after the demo) — same page | Геймдизайн | done 05.11 (Kanta «сразу»), check s16 log |
| PG-12 | Card telemetry (genre research 11.11, item 2; Kanta «да»): log every offered and every taken card per level-up (id, rarity, level, minute) in the sortie log; a script in `tools/reports/` prints per card the pick rate when offered and the share of evacuated sorties that had it (the two Slay the Spire metrics). No rule change. Report: https://claude.ai/artifact/SgDypJj81QeVii6ia3qJFB. Done: log l8 column `card_offers` (`CardLog`), report `tools/reports/card_stats.py` | «Сделать первую связку достижимой» | на проверке в игре (ждёт лог s18) |
| PG-13 | «Момент силы» (item 3; Kanta «да»): opening a synergy, an archetype rank III or a modernization is an event — short flash, large name, sound, the effect shown stronger for the first seconds. Presentation only, no numbers; F1 toggle, on by default (R-22) | «Показать «момент силы» в бою» | merged in #620 (F1 `power_moment`, on), waits for a check in the next build |
| PG-14 | First synergy reachable (item 4; Kanta «да»): while the player has no synergy, cards that advance the nearest `SynPairs` recipe are offered more often. Weights are not set: measure with the bot the share of sorties with ≥ 1 synergy by 8:00 per class before and after, numbers go to Kanta as «было → стало». F1 toggle. After PG-12. Done: F1 `first_syn_weight` = 3 (cards toward the specialization, or the nearest recipe before it, ×3 instead of ×1.8 until the first synergy). Bot 11.11 (random picks, demo profile, 36 + 36 sorties of 8 min): share with a synergy by 8:00 «Оса» 42 → 75 %, «Грач» 58 → 75 %, «Кит» 100 → 92 % (noise), all 67 → 81 % | «Сделать первую связку достижимой» | на проверке в игре (ждёт лог s18) |
| PG-15 | Pressure waves before the 5:00 and 10:00 mini-bosses (item 6; Kanta «ок» to «later»): proposal only after the s18 log shows what GD-14 and GD-15 did | Геймдизайн | отложено до разбора s18 |
| PG-16 | Album in combat (genre research item 8; Kanta 11.11 «1, только сразу нормально с картинками и хорошей визуализацией»): (a) a card says which synergy / modernization it opens or advances; (b) the card screen shows the three nearest recipes and what is missing; (c) a key opens the whole album in combat; (d) pause tab «Альбом»: what this plane can build now with recipes on top, unreachable below. Each entry gets a real picture of its effect (in-game capture, no paid generation without Kanta's «да») and proper visual design per `ui-design-system.md`, not placeholders. Sketches: `/mnt/project-files/genre_research/album_example_cards.jpg`, `album_example_pause.jpg` | «Сделать альбом сборок в бою» | merged in #621 (59 pictures, Tab / Q·E), waits for Kanta's look in the next build; open: `evo:gunpod` counted but unreachable (needs Kanta's yes to drop) |
| GD-18 | Build parity measurement (item 5; Kanta 11.11 «1» = yes to the method): bot, demo profile, 3 classes × one focused build per weapon family (missiles, gun, bombs, turrets, wing), 3 sorties each; compare damage per minute and the minute of archetype rank III. Then one «было → стало» package for the weakest build for Kanta's «да» (candidates: slight gun shell homing in a narrow cone, «обороты» cap +50 → +60 % = GD-17, one more source of turret points). Missiles are not nerfed. **11.11 measured** (42 bot sorties + 16 probes on a game copy, page https://claude.ai/artifact/MFD7idvDkQAM1cgEDz9iqL, data /mnt/project-files/balance/gd18-2026-11-11/): weakest is «Кит» bomb build (8.3k dmg/min, lowest of 14; cluster bombs 0.44k/min, same as in its gun build, ground pool is small), then wing on all classes (rank III 1 of 9). Gun and turrets are not weak. Package options: 1 bombs dmg 27.5 → 34.4, cd 6 → 5 s, auto-drop search 600 → 900 px, «Бомбёр» III 30 → 26 (recommended; probe: bombs ×2, ground 1.2 → 2.0k/min, total within noise); 2 bombs also hit planes ×0.5 (rule change; probe: bombs ×3, total within noise); 3 option 1 + patrol column 35 → 25 s | тред «Подтянуть слабые сборки оружия» | ждёт «да» Kanta |
| PG-17 | Gradual first sortie (genre research item 9; Kanta 11.11 «1, т.к. дать пока некому»): in the very first sortie of a profile (`sorties` == 0) the optional operation tasks and the wing commands (G) are hidden; fuel, class task and activities stay. From the second sortie they appear with a «новое» mark and a radio line. F1 toggle, on by default (R-22); 0 — as now. Meant for the demo, works in the full game too. Check with the first new testers when there are any | thread «Упростить первый вылет новичка»; merged #619 (11.11; F1 first_sortie) | ждёт проверки в сборке |
| S5-06 | Прокачка самолёта ур. 1 и ур. 2 раздельная: ур. 2 с нуля, перенос в профиле | Понятность игры для новичков | на проверке в сборке 3.5-s8 (в таблице «в работе» на 18.10 — догадка) |

## Понятность и интерфейс

| ID | Задача | Тред / владелец | Статус |
| --- | --- | --- | --- |
| EX-07 | Задание класса в брифинге операции (вариант 2, Kanta): «Оса» — перехватить бомбардировщики до 12:00, «Грач» — подавить 8 установок ПВО, «Кит» — сжечь 10 машин колонн; награда — редкая карточка и запчасти; видно на экране кампании и в бою | Отзывы внешних тестеров | на проверке в следующей сборке |
| EX-08 | Меню: один экран «В вылет» (операция, самолёт, кнопка), ангар по кнопке «Улучшить», новое открывается постепенно; сначала макет на «да» Kanta (З1). Сделано 22.10: экран «В вылет» вместо карты кампании и выбора самолёта — операции района, брифинг и задачи, три самолёта с честными характеристиками (скорость, манёвр, прочность, урон по воздуху, урон по земле по замеру 22.10), навык, кнопки «Улучшить самолёт (ангар)» и «В ВЫЛЕТ ▶»; от запуска до боя два нажатия | Отзывы внешних тестеров | на проверке в следующей сборке |
| EX-09 | История: диспетчер и ведущий по радио, задания в вылете с последствиями, активность «спасение сбитого пилота», сквозная линия про ведущего звена, сбитого «Бароном»; тексты на «ок» Kanta (И1). Сделано 22.10: радио «Купола» очередью, «Барон» дразнит в «Перевале», спасение пилота в «Сухом русле», сбитый «Барон» в «Крепостях» освобождает «Грома», в «Небе над Шахрисангом» «Гром» летит ведомым; тексты — `docs/playtest/external-2/ex09-story-texts.md` | Отзывы внешних тестеров | на проверке в следующей сборке |
| S5-04, S5-05, S5-07, S5-09 | Описания навыков и связок простыми словами; оружие по классам в ангаре и карточках; текст «Бронещита»; убрать «+1 к лимиту ведомых» (18.10, правки Kanta по 3.5-s5) | Понятность игры для новичков | на проверке в сборке 3.5-s8 (в таблице «в работе» на 18.10 — догадка) |
| U-08, U-10, U-11, U-12, U-13, U-18 | Экспериментальное оружие; боевой разворот и подписи навыков; пауза и итоги; описания навыков в ангаре; боевой интерфейс; подсказки механик ночи (17.10) | Понятность игры для новичков | на проверке в сборке 3.5-s8 |
| DM-06 | Первые 90 секунд демо понятны новичку (проверка на внешних тестерах) | Понятность игры для новичков | идея (до 15.12) |
| UI-01 | Main menu and settings redesign after Sublight (Kanta 24.10): style «Прицел», 5 menu items, «Что нового»/«Отзыв» cards, compact flight log, flexible graphics, controls with rebinding and gamepad; plan `docs/superpowers/plans/2026-10-24-main-menu-settings.md` steps 1–5; Kenney Input Prompts + UI Audio (CC0) approved | Переделать главное меню и настройки | in progress: step 1 (UiStyle + UiFocus merged, PR #367) |
| UI-02 | Combat UI: HUD, pause variant В «Чертёж самолёта», card pick, results (plan steps 6–9), in parallel (Kanta 24.10) | Переделать интерфейс боя | merged 24.10 (PR #372); waiting: frames from the Sublight video on Kanta's PC. Left from review: colour literals → tokens, HUD skill list per-frame allocations, pause DPS by source prefix, 3rd nested term tooltip overlap |
| UI-03 | «Подготовка и вылет» (Kanta 06.11): one menu item for hangar + sortie; hangar → «Приготовиться к вылету» → mission screen (theater, operation, «Вылет ▶»); Archipelago after 3 cleared Highlands operations; slots for operation art (`game/art/ops/<op id>.jpg`) and objectives (`Campaign.OPS[i]["goals"]`) | Объединить ангар и вылет в «Подготовку и вылет» | merged 06.11 (PR #576), also the «Можно улучшить самолёт» reminder (06.11 review p. 4); objectives on the mission screen PR #579 |
| UI-04 | Operation card art (Kanta 06.11, item 2 of the «Подготовка и вылет» message): one comic-style picture per Highlands operation, same style as the cutscene art; Figma AI, 6 generations (op 4 redrawn with two jets — player and Grom in restrained liveries; op 2 redrawn with background explosions). Archipelago has no art (on hold). Page https://claude.ai/artifact/2B63rLGk6t11BsGNfzx2DK | Нарисовать арты к операциям | merged 06.11, PR #580 (`game/art/ops/<op id>.jpg`); check in s17 |

## Нагорье

Тред «Второй биом» (ландшафт) и «3D-модели по плану Kirill» (модели, на паузе).

| ID | Задача | Тред / владелец | Статус |
| --- | --- | --- | --- |
| L-05 | Камни мельче и грудами под скалами (осыпи); скальные выходы и текстуры скал вместо сплошного песка (часть сделана в M-36) | Второй биом / 3D-модели | в работе (Второй биом) — актуальность проверить |
| B-30 | Мелкие детали: кусты, камни, трава — MultiMesh по маске материала; на «Низком» без потерь FPS | программист | идея |
| B-40 | Уровни войны 0–3 и разрушение зданий бомбами и НАР: 3 состояния у зданий, FPS в бюджете | геймдизайн + арт | идея |
| B-44 | Режим фото и витринные кадры биома для Steam: 5 кадров 1920×1080 и 4K без интерфейса | продюсер + арт | идея |
| RV-01 | Разнообразный рельеф, этап 1: районы рельефа (холмы и сопки, средние горы, высокие хребты со снегом, столовые горы с каньонами, широкие долины), разные берега одной долины; план `docs/superpowers/plans/2026-10-24-relief-variety.md` | Разнообразить рельеф Нагорья | готово (PR #361, 24.10; ПВО по настоящему расстоянию до реки и исправлено зависание у кишлаков — там же) |
| RV-02 | Разнообразный рельеф, этап 2: ветвистые овраги и отроги вместо одинакового узора на склонах | Разнообразить рельеф Нагорья | сделано (#366) |
| RV-03 | Скорость после оврагов: расстановка ПВО по сетке готовой земли (92 → 26 мс в облаке). Осталось: загрузка вылета 64 куска 2,3 → 3,3 с в облаке (на ПК ≈ +0,3 с) — ускорять, только если на ПК заметно | Разнообразить рельеф Нагорья | сделано (#376), загрузка — следить по логам ПК |
| RV-04 | Рельеф, этап 3: останцы и скальные столбы, террасы у реки, ущелья; план `docs/superpowers/plans/2026-10-24-relief-stage3.md` | Разнообразить рельеф Нагорья | сделано (#380) |
| RV-05 | Замирание на старте вылета (ПК Kanta 25.10: 3,2–5,0 с по уровню графики): сразу строим только видимые куски, поля — заглушки и фон; ручьи посёлков по клетке. В облаке 7,2 → ~2,1 с (первый старт). Проверить по следующему логу с ПК | Разнообразить рельеф Нагорья | сделано (#397); ПК Kanta 25.10: 3,2 → 1,4 с (gfx 0), 5,0 → 2,2 с (gfx 3) |
| B-36 | Небо и дымка: облака сделаны (M-31, M-40); остаётся дымка в долинах | программист | идея |

## Сюжет и заставки

Тред «Проработать сюжет Нагорья и заставки». Решения Kanta 31.10.2026: глубина 3 (полный сюжет Нагорья), противник «Монолит», правило «катсцены — нет» поправлено, в демо всё для операций 1–2, второй ас «Граф». Документы: `docs/story/highlands-storyline.md`, `docs/story/cutscenes-and-presentation.md`; план `docs/superpowers/plans/2026-10-31-highlands-story.md` — **«да» Kanta 31.10 («Нагорье делаем всё»)**, 10 шагов ≈ 17,5 тред-дней, без деления на «до демо / после».

| ID | Задача | Тред / владелец | Статус |
| --- | --- | --- | --- |
| ST-01 | Мелкие правки: «Штаб» → «Штаб „Монолита“» у «Крепости» (голос противника) и «Купол» у базы, все строки радио через `Loc.t`, фраза про «Грома» в брифинге операции 4 | Сюжет Нагорья и заставки | готово (#503, 31.10) |
| ST-02 | Тексты сюжета (~115 строк: диалоги ангара, радио, итоги, подписи заставок), «Граф», «Почтальон», «Сквозняк», «Штаб „Монолита“»; `.po` EN/ZH через тред перевода | Сюжет Нагорья и заставки → перевод | идея (шаги 5–9) |
| ST-03 | Заставки в движке: класс `Cutscene` (камера по ключам, звено моделей ангара, рамки, подписи, пропуск, настройка, флаги в сохранении кампании, автотест) | Сюжет Нагорья и заставки | готово (#511, 31.10) |
| ST-04 | Интро и финалы операций 1–2 (4 сцены) + сцены ангара H0–H2′ + страница кадров на «ок» | Сюжет Нагорья и заставки | готово (#518, #519, 31.10) |
| ST-05 | «Кино-моменты» в бою (первая «Крепость», сбит «Барон», «Гром» в строю), стингеры и радиотекстура (CC0) | Сюжет Нагорья и заставки | готово (#516, 31.10) |
| ST-06 | Интро и финалы операций 3–4, сцены H3–H4′, эпилог с крючком, огни колонны и посёлков, виньетка операции | Сюжет Нагорья и заставки | готово (#522, #524, #526, 31.10); огни колонны — не делались, окно операции и огни посёлков за F1 `story_vignette` / `story_lights` до «ок» |
| ST-07 | Система диалогов ангара: данные сцен, портреты слева/справа, печать текста, выборы (2 кнопки, геймпад), пропуск, «Журнал» на экране кампании, флаги выборов в сохранении | Сюжет Нагорья и заставки | готово (#513, 31.10) |
| ST-08 | Портреты «Купол», «Гром», «Ключ» в стиле экипажа (бриф и входная картинка на утверждение; кредиты — только после отдельного «да») | Сюжет Нагорья и заставки → Kanta | 02.11: Kanta «Сам делай» → три портрета сгенерированы Figma AI по брифам и слиты (#542, `game/art/portraits/story_*.png`); страница https://claude.ai/artifact/BV1hZihd6xZcKBkC7tUEzy; «ок» Kanta 03.11; кредиты — после отдельного «да» |
| ST-09 | Знак «Монолита» (серая плита) на «Крепости», ПВО и грузовиках — одна наклейка, кадр на «ок» | Сюжет Нагорья и заставки | сделано 31.10 (#529), F1 `story_mark`; «ок» Kanta 02.11 |
| ST-10 | Роль «Грома» в операции 4: выбор игрока (ведомый / второй диспетчер) или всегда ведомый | Сюжет Нагорья и заставки | идея (шаг 7): выбор игрока, пока Kanta не сказал иначе |
| ST-11 | Арт заставок в стиле комикса (Figma AI) вместо живого пролёта: 9 картинок на 12 карточек, медленный наезд, F1 `story_art` | Сюжет Нагорья и заставки | сделано 01.11 (#535), страница https://claude.ai/artifact/UJgv1zmLWqykKdYXQsL7Kj; «ок» Kanta 01.11 |
| ST-12 | Заставки страницей «живого комикса» (вариант 2, Kanta 07.11): 3–4 панели на сцену, облачка, подписи, звуковые слова, дым/вспышки/трассеры движком, самолёты-вырезки летят через панели; F1 `story_comic`; план `docs/superpowers/plans/2026-11-07-comic-cutscenes.md`, варианты https://claude.ai/artifact/1SijbHm6rRwAfmB3fqJFFt | Сделать красочные сюжетные заставки | фаза A слита 07.11 (#609), страница «было/стало» https://claude.ai/artifact/N7o4gw1Gy3qCSGr86Uziku; фаза B (13 новых картинок, 15 вызовов Figma) слита 08.11 (#612), «было/стало» https://claude.ai/artifact/VwiuecHoC3NWoJXawsWWu6; ждёт «ок» Kanta |

## Эффекты боя

Thread «Улучшить эффекты боя» (Kanta 24.10, variant 2). Plan `docs/superpowers/plans/2026-10-24-combat-vfx.md`.

| ID | Задача | Тред / владелец | Статус |
| --- | --- | --- | --- |
| VFX-01 | GPU effect system foundation: `GpuFx`, layers, routing from `Boom3D`, glow; explosions on the GPU, same look (Forward+ only) | Улучшить эффекты боя | готово 24.10, PR #351 |
| VFX-02 | Own flipbooks baked in Blender from above (fire, smoke, Нагорье dust, plasma, flak) with smoke lighting | Улучшить эффекты боя | сделано: бомба #357, наземная цель #358, взрыв в воздухе #360 (Forward+); зенитный разрыв #391 (24.10, влит по «делай» Kanta, ждёт его взгляда) |
| VFX-03 | Smoke: ribbon missile trails, smoke columns over burning targets, damaged-plane smoke, convoy smoke screen | Улучшить эффекты боя | сделано: дым ракет и дым обломков #360, дымовая завеса колонны #363 (Kanta ок 24.10) |
| VFX-04 | Gunfire: muzzle flash, glowing tracers, hit sparks, dust from ground hits | Улучшить эффекты боя | сделано: вспышки у стволов, трассеры, искры попаданий #368 (Kanta ок 24.10); пыль от попаданий в землю #387 (Kanta ок 24.10) |
| VFX-05 | Water: splashes and ripple rings on the river | Улучшить эффекты боя | сделано: всплески бомб, пуль и обломков в реке #389 (24.10, влито по «делай» Kanta, ждёт его взгляда утром) |
| VFX-06 | Decal craters and scorch on slopes, light pool, sparks/debris collide with relief; final fps check | Улучшить эффекты боя | воронки и копоть — декали, новая копоть (#374); свет взрывов и мерцающий свет очагов (#378), Kanta ок 24.10; осталось: fps на ПК Kanta |

## Архипелаг

Тред «Второй биом». Описание биома — `docs/biome2/archipelago.md`.

| ID | Задача | Тред / владелец | Статус |
| --- | --- | --- | --- |
| E-09 | Особенность биома «Шквал»: грозовой фронт с ветром (снос самолёта и пуль) и молниями по отмеченным кругам, бьёт и по врагам | Второй биом | идея |
| E-04 | Каталог моделей Архипелага: список и план — `docs/biome2/models-plan.md`; ждём референсы Kanta, ответы 1–4 и команду на старт | Второй биом → Kanta | ждёт Kanta |
| E-06 | Модели Блендером кодом: суда конвоя, береговая батарея, РЛС, маяк, причал, волнорез, буи, лодки, домики, остовы на мели (часть — в S8-A1…A3) | 3D-модели по плану Kirill | идея (после E-04, тред на паузе) |
| B2-Q00 | Kanta 06.11: Archipelago back in work. Quality bar from the Highlands in one doc — `docs/standards/art-quality-bar.md` | Запустить второй биом Архипелаг | готово 06.11 |
| B2-Q01 | `SeaProps.plan()` reads const Arrays on worker threads (same race as #488) → static `PackedStringArray` copies; `sea_props_thread_test` (race did not reproduce before the fix either: preventive) | Запустить второй биом Архипелаг | готово 06.11 (#589) |
| B2-Q02 | All 41 scenery props: add normal + ORM (roughness) maps with wear, grime, salt (rule S3). 35 weathered by `prop_weather.py`, the rest rebuilt (Q04, Q05, Q07); `a32` unused | Запустить второй биом Архипелаг | готово 06.11 (#589) |
| B2-Q03 | Replace floating battery `e_ship_battery` (box barge, flat disc turrets, no textures). Not spawned by any game script now (same for `e_ship_bulk`): only if it comes back | Запустить второй биом Архипелаг | идея |
| B2-Q04 | Replace shore cliffs `a31_cliff_a`, `a33_rock` («inflated balls») with layered limestone (`shore_cliffs.py`) | Запустить второй биом Архипелаг | готово 06.11 (#589) |
| B2-Q05 | Replace radar mast `a03` (404 tris) and terrace wall `a21` (box with painted stone): lattice tower 2.4k, dry-stone wall 4.5k | Запустить второй биом Архипелаг | готово 06.11 (#589) |
| B2-Q06 | Improve cruiser «Сторож»: real main turrets, armour belt (belt, turret roof detail, per-part wear; 17.8k) | Запустить второй биом Архипелаг | готово 06.11 (#589) |
| B2-Q07 | Improve trees `a37_pine_b` (100-tri card), `a38_tree_leaf`; coastal gun `a01`. Trees done (cypress 7.5k, broadleaf 4k, #589); gun `a01` (wedge shield, ×1.45), olives `a34`/`a35` and stone pine `a36` rebuilt 07.11 | Запустить второй биом Архипелаг | готово 07.11 (#605) |
| B2-Q08 | Improve landing barge, «Крачка», seaplane, tanker, bulk carrier, wrecks `a26`/`a27`; «Левиафан» launcher/ZSU stripes, hull per-part wear bake. Wrecks `a26` (barge) and `a27` (cargo ship in two) rebuilt 07.11 (#605); the rest remain | Запустить второй биом Архипелаг | в работе |
| B2-Q09 | Archipelago close-up review, all 11 defects (Kanta 07.11 «Исправляй все»): whitecaps and glints, stepped water edge, olive/pine crowns, island grass, contact foam at hulls and rocks, lighthouse off the edge, sand grain, coastal gun, bunker turf, wrecks, seabed ripples. F1 `arch_detail`, on by default, VERSION 19. Plus L-02 round relief basins at river loops. Page https://claude.ai/artifact/XLVtxTG921Kjt8yiBE5tUV | Запустить второй биом Архипелаг | готово 07.11 (#605); второй круг → B2-Q10 |
| B2-Q10 | Archipelago second round (Kanta 07.11 screenshots + «сделай картинку живой»): harbour overlap test (capsules), level gun pads, depth field smooth max (no V corners) and eased to full depth (no straight drop-off), shelf width varies along the coast, rocky limestone shores with sand only in coves, grey limestone islands with maquis on rock, detailed gun (a01) and wrecks (a26, a27) at 2048. Page https://claude.ai/artifact/AtZexML4E4gougwYyrAomQ | Запустить второй биом Архипелаг | готово 07.11 (#606); третий круг → B2-Q11 |
| B2-Q11 | Archipelago third round (Kanta 07.11 15:20): gun clutter out of the mount, dug-in pits (earth berm, floor at the highest ground), battery as a line along the contour with a central command post (period coast battery layout), one even muted water gradient, closed lighthouse yard, photo-textured limestone shore. Page https://claude.ai/artifact/GiAf8kWjr1tcH1FezCYBDr | Запустить второй биом Архипелаг | готово 07.11 (#608); четвёртый круг → B2-Q12 |
| B2-Q12 | Archipelago fourth round (Kanta 07.11 20:20–20:22): guns seated on the highest point of a wider pad with a stricter level test; lighthouse yard on a dry-stone terrace seated at its highest corner, trodden earth instead of a paving grid (seam relief off for seam-less prop kinds); shelf narrower and depth linear in distance, wide overlapping colour blends with no edge, no pale shoals mid-strait. Page https://claude.ai/artifact/CAVRR9ZtmSRa8Cw34FtfHD | Запустить второй биом Архипелаг | готово 07.11 (#611), Kanta принял 08.11 |
| B2-A01 | Coastal battery activity (Kanta 08.11 «да», option 1): 4 spread guns replace the skipped fort slot at sea; turret/barrel split of a01 recipe, aim and heavy flak with ground ring, broken model on death, timer and rare-card reward as the fort. Plan with numbers before code | Береговая батарея (новый тред) | готово (#615, числа — «да» Kanta 09.11) |
| W-01 | Archipelago water (Kanta 06.11 «да на план по воде»): baked FFT wave loop (`game/tools/water/water_maps.py`), sky reflection from a CC0 panorama, whitecaps and lace foam, drift; softer depth bands (06.11). F1 `water_v2`, on by default since #603 (R-22 on-first) | Запустить второй биом Архипелаг | готово (#590, #603); close-up review https://claude.ai/artifact/8mrHYUAVTS9hjVuVBCrKFu → B2-Q09 |
| E-02 | Объём раннего доступа: 2 биома, 18 перков, 8–9 видов оружия (вместо 3 / 36 / 12) — на решение | продюсер → Kanta | ждёт Kanta |

Отзывы по сборке 3.5-s8 для E-07, E-08, E-10, E-14 (враги, «Левиафан», кампания, берег и суда) — ждём ответов внешних тестеров; строки в архиве.

## Модели

Тред «3D-модели по плану Kirill» снова в работе с 24.10: приоритет 1 Kanta — Нагорье визуально до идеала (VIS-01), Архипелаг на стопе. Принцип с 22.10 (R-09): модель идёт в сборку только после «ок» Kanta на кадр из игровой камеры в галерее — Нагорье https://claude.ai/artifact/LgNaxFAsSPE2yNtXGU2sMn, Архипелаг https://claude.ai/artifact/SbpzxFY1FhXZXMsr1RUtKm. Незаконченные работы лежат в `/mnt/project-files/wip/s8/` (пакеты `ground`, `props`, `weapons`, `sea_craft`, `leviathan`, `shore`).

| ID | Задача | Тред / владелец | Статус |
| --- | --- | --- | --- |
| VIS-01 | Нагорье — эталонная долина в финальном виде: Forward+, свет и цвет как EVERSPACE, небо, дымка, земля и зелень высокого разрешения, 6–8 детальных моделей со Sketchfab (CC BY, после выбора Kanta); кадры и fps на ПК Kanta, потом перенос на весь биом | 3D-модели по плану Kirill | в работе (3D-модели по плану Kirill) |
| S8-K1 | «Крепость»: спаренные турели turret_twin из имеющихся моделей, корпус матовый (Kanta 23.10) | 3D-модели | готово, принято Kanta 23.10 |
| S8-M1 | РЛС с заметной антенной; вся позиция ПВО в одном стиле с конвоем, матовая окраска (`wip/s8/ground.bundle`) | 3D-модели | готово (#320) |
| S8-M2 | Бункер: качество, размер, окраска под землю Нагорья | 3D-модели | готово (#320) |
| S8-M3 | Конвой: пропорции грузовика с тентом, броневика, пикапа; пикап с ПЗРК — разнести стрелка, второго человека и орудие | 3D-модели | готово (#320) |
| S8-M4 | Дым БМП не виден в бою — проверить и сделать понятным (`docs/proposals/enemy-weapons-s8.md`) | 3D-модели | готово (#328): дым по угрозе, до 2 раз, перерыв 20 с |
| S8-M7 | Фруктовое дерево, куст, пост из мешков — переработать, вернул Kanta на доработку («мультяшно») (`wip/s8/props.bundle`) | 3D-модели | готово (#321), принято Kanta 23.10 |
| S8-M8 | Обломки: 2 раскладки самолёта и вертолёт; у вертолёта лежит над землёй, нет пятна гари | 3D-модели | готово (#321) |
| S8-M10 | Ангар: модели оружия высокого качества, блоки НАР вернул на доработку (`wip/s8/weapons.bundle`) | 3D-модели | готово (#322), принято Kanta 23.10 |
| S8-M11 | Эволюция бомб — шкала размеров «50 → 1000» готова, ждёт слияния вместе с оружием | 3D-модели | готово (#322) |
| S8-A1 | Архипелаг: «Скат», «Крачка», «Буревестник», «Чайка» заново кодом, формы приняты, окраску вернул (почти белая) (`wip/s8/sea_craft.bundle`) | 3D-модели | готово (#323), принято Kanta 23.10 |
| S8-A2 | «Левиафан»: палуба, взорванные башня, пусковая, РЛС, ЗСУ; крышки пусковой открываются (`wip/s8/leviathan.bundle`, не проверено) | 3D-модели | готово (#324), принято Kanta 23.10 |
| S8-A3 | Берег: береговое орудие, бункер, маяк, дом, волнорезы, руины, окраска Архипелага (`wip/s8/shore.bundle`, не проверено) | 3D-модели | готово (#325), принято Kanta 23.10 |
| S8-A4 | Балкер и танкер: естественная, приглушённая окраска (Kanta 23.10) | 3D-модели | готово (#326), принято Kanta 23.10 |
| V-03…V-06 | Предкрылки и закрылки (сделано в PR #46), модули на моделях (сделано M-15), остовы техники (сделано M-21), ловушки и кассетные бомбы (сделано M-13): остаются только пункты, не закрытые другими задачами, — сверить при снятии паузы | 3D-модели | идея |
| M-60 | Убрать окраски «Чёрный с красным» («Кит») и «Гоночная шахматка» (все три самолёта); сохранения с ними — на окраску по умолчанию (Kanta 04.11) | 3D-модели | в работе 04.11: PR с юнит-тестом `livery_removed_test.gd` |
| M-26 | Проба fal.ai (`genmedia`) на одной машине конвоя: сравнение с Meshy по качеству и цене | Kanta | ждёт Kanta (стоп 17.10: нет бесплатного баланса, без трат) |
| PT-01 | Plane tiers 1–5: concept and art direction for Оса / Грач / Кит (Kanta 06.11), page https://claude.ai/artifact/Jcn2GtNbLrRuCVn2xbS9dE | «Придумать концепты новых самолётов по уровням» | done |
| PT-02 | Tier 4–5 models (6): Грач 4 first as pilot, then Оса 4, Кит 4, the tier 5 trio; prototype photos first, matte worn paint, glow only on future systems (shield, emitters) | 3D thread (coordinator assigns) | to do |
| PT-03 | Tier 1 models (3): early swept-wing jet fighter (Оса), light two-seat side-by-side jet strike plane with tip tanks (Грач), piston heavy bomber with coupled engines (Кит) | 3D thread (coordinator assigns) | to do |
| PT-04 | Progression plan for 5 tiers: what each tier unlocks and when, renumbering current planes, experimental weapons to tiers 4–5, hangar shows 4–5 locked; demo = tiers 1–3 (brainstorming → plan → Kanta «да», flak-heaven-game-design); plan docs/superpowers/plans/2026-11-06-plane-tiers.md | thread «Спланировать прокачку самолётов на пять уровней» | stage A merged (#598, 06.11): tiers 1–5, profile v2, hangar strip; next A2 node top rules, B tier-1 models wired (Оса/Грач t1 in main), C heavy/EXP on tiers 4–5 |
| PT-05 | Future systems as mechanics: laser gun, phase shield in dodge, front energy shield, shield dome over wingmen, drone bay (fold into PT-04 plan, numbers only after measurement) | with PT-04 | idea |

## Звук и музыка

Тред «Звук и музыка». Музыка боя и меню выбраны (Kanta 18–19.10), CC0 / CC-BY.

| ID | Задача | Тред / владелец | Статус |
| --- | --- | --- | --- |
| M-04 (звук) | Звуковые эффекты «гибрид» вместо временных: слито (PR #35), ждёт замечаний Kanta на слух | Звук и музыка → Kanta | ждёт Kanta |
| M-01…M-03 (музыка) | Музыка в стиле «гибрид»: 3 варианта с проверкой прав; пилот (меню и бой Нагорья); вся музыка биома 1 (~10 треков к раннему доступу). Часть закрыта подбором CC0-треков (M-06 музыки, архив) | Звук и музыка | идея |
| B-17 | ИИ-звук и музыка: свой саундтрек в генераторе — платно, решает Kanta | Звук и музыка → Kanta | ждёт Kanta |

## Демо

Тред «Демо для Next Fest». План и сроки — `docs/demo-next-fest.md`. Решение Kanta 19.10 (DM-01): вариант А — Нагорье, операции «Перевал» и «Сухое русло», три класса ур. 1, ангар с потолком, демо открываем 11.02, отчёты тестера остаются с согласием игрока. Код стартует в R-14.

| ID | Задача | Тред / владелец | Срок | Статус |
| --- | --- | --- | --- | --- |
| DM-02 | Режим демо в коде: признак `demo` в пресете экспорта, закрытые самолёты, операции, районы, потолок ангара, замки «В полной игре» | Демо для Next Fest | 30.11 | сделано 22.10 (`game/scripts/demo.gd`, ключ `--demo`) |
| DM-03 | Экран «Конец демо», кнопки «Список желаемого» (меню, итоги, финал) | Демо для Next Fest | 30.11 | сделано 22.10: кнопка в меню и на экране «Конец демо»; номер игры в Steam (`Demo.STEAM_APP_ID`) вписать, когда откроется страница, до того кнопка ведёт на flakheaven.com |
| DM-04 | Перенос сохранений демо → игра (одна папка `user://`, Steam Cloud полной игры) | Демо для Next Fest | 15.12 | на одном ПК сделано 22.10 (то же имя проекта — та же папка сохранений); Steam Cloud — при настройке Steamworks (DM-09) |
| DM-05 | Пресет экспорта «Windows Demo», комплект `make_kit.sh` | Демо для Next Fest | 15.12 | пресет готов 22.10 (`tester,demo`); комплект — только по команде на сборку |
| DM-07a | Согласие игрока на отправку статистики: сейчас строка лога уходит сама после каждого вылета (`report.gd`, `queue_run`); в демо — спросить при первом запуске и дать переключатель, без согласия не слать | Отчёт тестера после вылета | 10.01 | идея (код после старта кода демо) |
| DM-07b | Вырезать имя пользователя из хвоста `godot.log` перед отправкой отчёта (`C:/Users/<имя>/…`, `/Users/<имя>/…`, `/home/<имя>/…` → `<user>`) | Отчёт тестера после вылета | 10.01 | идея (код после старта кода демо) |
| DM-08 | Закрытый тест демо в Steam Playtest: медиана времени, доля дошедших до финала, падения, FPS | Набор тестеров + Демо | декабрь — 15.01 | идея |
| DM-12 | Заморозка демо (только исправления), открыть демо, уведомление по списку желаемого | Демо + Kanta | 01.02 / 11.02 | идея |
| M-07 (демо) | Общая строка «Демо к Next Fest»: Нагорье, три класса, проверка Steam до 25.01.2027 | Демо для Next Fest | 25.01 | в работе (Демо для Next Fest): план готов, код — с DM-02 |

## Steam и юридика

Только Kanta, где указано; список с датами — `docs/owner-checklist/kanta-now.md`.

| ID | Задача | Тред / владелец | Статус |
| --- | --- | --- | --- |
| B-13 | Страница Steam (к концу ноября 2026): тексты — `docs/marketing/steam-page.md`, раскрытие ИИ — раздел 8 там же | Маркетинг и реклама + Kanta | в работе (Маркетинг и реклама) |
| MP-01 | Цена в Steamworks: $9,99 в раннем доступе, в России 250 ₽ вручную, остальные регионы — рекомендация Valve; скидка запуска 10% (`docs/marketing/pricing.md`) — ввести при заведении игры в Steamworks | Kanta | ждёт Kanta |
| DM-09 | Steamworks: приложение демо, хранилище, кнопка «Загрузить демо», анкета содержимого (ИИ-модели и звук, V-08) | Kanta + Демо | ждёт Kanta (после страницы Steam, до 15.01) |
| DM-10 | Регистрация игры на Next Fest | Kanta | ждёт Kanta (до 10.01.2027) |
| DM-11 | Трейлер на странице к 18.01; демо и страница на проверку к 25.01 | Маркетинг и реклама / Демо | идея |
| PD-02 | Уведомление Роскомнадзора об обработке персональных данных от ИП Kanta (pd.rkn.gov.ru), значения полей готовы | Kanta | ждёт Kanta (не подано) |
| V-08 | Проверить коммерческие условия Meshy и Hunyuan 3D (модели уже в игре) — до страницы Steam | аналитик → Kanta | ждёт Kanta |
| M-06 (VK Play) | Заявка на VK Play после старта раннего доступа, проверка условий в консоли | Kanta | идея (апрель 2027) |
| ED-01 | Two editions at launch (Kanta 06.11): proposal page — 5 base liveries, 10 author liveries + 10 stickers per class, what else goes into the Deluxe edition, prices; numbered questions to Kanta; page https://claude.ai/artifact/YBjfDTiTE5Zz9qXXXXCJSd | «Продумать два издания на старте продаж» | done 06.11: Kanta «ок» to all recommendations + meme block (journal 06.11) |
| ED-02 | Base game: cut the livery list to the 5 core paints per class; saves with a moved paint fall back to the class default unless the Deluxe pack is owned (unit test like `livery_removed_test.gd`) | 3D-модели (after ED-01 answers) | to do |
| ED-03 | Deluxe liveries: 10 per class (existing extra paints moved + new ones), Blender/code only, no paid generators; gallery on 3 presets for Kanta's «ок» (R-09) | «Продумать два издания на старте продаж» (Kanta 06.11 «бери в работу») | PR #600 (bench only, --liveditions); pictures https://claude.ai/artifact/YBjfDTiTE5Zz9qXXXXCJSd, waits for Kanta's «ок» |
| ED-04 | Deluxe stickers: 10 new per class into the decal atlas (`tools/decal_atlas.py`, `DecalCatalog`); fictional, no real insignia | «Продумать два издания на старте продаж» | PR #600 (bench only); sticker sheets on the same page, waits for Kanta's «ок» |
| ED-05 | DLC ownership check: Steam DLC App ID via the Steam API (GodotSteam `isDLCInstalled`), a debug flag for tests, lock icon and «в дополненном издании» line in the hangar; demo shows no locked items | code thread (after Steam App ID) | to do |
| ED-06 | Steamworks: DLC app «Набор эскадрильи» (own store page, capsules), bundle «Дополненное издание», prices from ED-01 | Kanta + Маркетинг и реклама | waits for App ID and ED-01 |
| ED-08 | «Хулиганский ящик» (Kanta 06.11, memes): 8 meme liveries for all classes + 20 meme stickers, own drawings only; bench pictures for Kanta 07.11 together with ED-03/ED-04 | «Продумать два издания на старте продаж» | PR #600, pictures on the ED-01 page, waits for Kanta's «ок» |
| ED-07 | Deluxe extras: digital artbook (PDF from model renders and concept pages), 4K wallpapers from Forward+ frames; soundtrack only if original music is commissioned (current tracks are CC0 / CC-BY, cannot be sold as ours) | Маркетинг и реклама (after ED-01 answers) | idea |

## Маркетинг

Тред «Маркетинг и реклама» — координатор каналов. Каналы: Telegram https://t.me/FlakHeaven, Discord, Instagram, itch.io; у каждого свой тред и план (`docs/marketing/`). После запуска каналов — один тред (R-13).

| ID | Задача | Тред / владелец | Статус |
| --- | --- | --- | --- |
| R-13 | После запуска каналов: один тред предлагает варианты контроля продвижения, отслеживает результаты, отчитывается еженедельно; после страницы Steam — пересмотр графика и формата | Маркетинг и реклама | в работе с 31.10 (каналы запущены, см. R-25) |
| M-05 (блогеры) | Список 50–100 стримеров и блогеров жанра, пресс-кит | Маркетинг и реклама | идея |
| MK-01 | Недельное условие вылета (как «модификаторы уровня каждую неделю» у Sublight) — повод возвращаться; решает геймдизайн и Kanta (`docs/marketing/sublight-case.md`) | Маркетинг → геймдизайн | идея |
| M-02 (веб) | Пробный веб-экспорт Godot (размер, FPS) — годится ли браузерная версия | программист | идея |
| TS-3…TS-6 | Правила чата, шаблоны постов, кадры, список сообществ для набора тестеров | Набор тестеров | идея |
| TS-7 | Публикация набора в Telegram, Max, VK, Instagram | Набор тестеров | идея (по команде Kanta после подключения аккаунтов) |
| TS-8 | Steam Playtest | Kanta | идея (после выпуска в Steam) |

## Перевод

Тред «Перевод игры».

| ID | Задача | Тред / владелец | Статус |
| --- | --- | --- | --- |
| L-04 | Английский: проверка носителем (кадры интерфейса и записки тестеров готовы) | Перевод игры + Kanta | ждёт Kanta (нужен носитель) |
| L-05 (китайский) | Упрощённый китайский: черновик готов (zh_CN.po, шрифт Noto Sans SC, язык в настройках) | Перевод игры + Kanta | ждёт Kanta (проверка носителем) |

## Сайт

Тред «Сайт: порядок и персональные данные». Сайт https://flakheaven.com (`site/`).

| ID | Задача | Тред / владелец | Статус |
| --- | --- | --- | --- |
| PD-01 | Заявки тестеров — в Яндекс Формы (форма https://forms.yandex.ru/u/6ad66df2c45c0770823c7c1e/ на сайте с 19.10); мелкие правки вопросов — Kanta | Kanta | ждёт Kanta |
| PD-04 | Политика конфиденциальности: реквизиты ИП, почта, Яндекс вместо Tally; черновик на сайте (#256) | Сайт | в работе (Сайт) |
| PD-05 | Старые заявки Tally перенести, затем удалить в Tally (только по «да» Kanta) | Сайт + Kanta | ждёт Kanta (после PD-01) |
| PD-06 | Согласие перед отправкой отчётов из игры и вырезание имени пользователя — передано в DM-07a, DM-07b | Отчёт тестера | в работе (Отчёт тестера после вылета) |
| SITE-02 | Сайт дальше: кнопка Steam (после открытия страницы), видео боя наверху, «Вопросы и ответы», кадры Архипелага и ангара, пресс-кит к Next Fest | Сайт | идея |
| RP-4 | Обновить приёмник отчётов (`tools/reports/apps_script.gs`): новые колонки в листе «Отчёты» | Kanta | ждёт Kanta (по желанию: без обновления ответы приходят в колонке «Комментарий») |

## Процесс

Решения ревью 22.10.2026 — `docs/review/2026-10-22-work-review.md`. Правила — `CLAUDE.md` и `docs/process/project-instructions.md` (15 правил).

| ID | Задача | Исполнитель | Срок | Статус |
| --- | --- | --- | --- | --- |
| R-03 | Бэклог по системам, закрытое — в `docs/backlog-archive.md` | Порядок в документах | 24.10 | готово 22.10 |
| R-04 | Раздел «Правила игры сейчас» в начале `docs/game-context.md`, формат журнала — одна строка на решение (старые длинные записи не переписывались) | Порядок в документах | 24.10 | готово 22.10 |
| R-05 | Инструкции проекта заменить на 15 правил (текст — `docs/process/project-instructions.md`) | координатор (поле настроек проекта) | 22.10 | готово 22.10 |
| R-07 | Список «только Kanta» (`docs/owner-checklist/kanta-now.md`) первым пунктом планёрки: файл и промпт планёрки | координатор | 22.10 | готово 22.10 |
| R-09 | Модели принимаются по галерее до сборки (см. раздел «Модели») | 3D-модели, координатор | с 22.10 | готово как правило; действует с возобновлением треда |
| R-10 | Методика баланса `docs/balance-method.md`: показатели лога `l7`, операция и класс, нормы; правки баланса не чаще раза в сборку с «было → стало»; методику согласует Kanta | Бой, звук и производительность | до следующей сборки | готово 23.10: method v1 accepted (`docs/balance-method.md`); «one change per build» still applies |
| R-12 | Планёрка: строки «цикл сборки» и «дни до Next Fest», раз в неделю — статус ревью | координатор (промпт планёрки) | 22.10 | готово 22.10 |
| R-14 | Запустить EX-01…EX-12 и код демо DM-02…DM-05: после R-03 и R-04 — координатор запускает с учётом лимита (не больше шести тредов на сильной модели с 25.10) | координатор | после R-04 | готово: EX shipped in 3.5-s9 (22.10), DM-02…DM-05 done 22.10 |
| R-15 | Еженедельное ревью работы: пятница 18:00 МСК, отдельный тред, сильная модель; первое 30.10 (23.10 пропускаем); запланированная задача trig_019ogc72sDgnqvRSKPUvjrXY (пятница 17:43 МСК, новый тред) | координатор | 22.10 | готово 22.10, первое ревью 30.10 |
| R-16 | Review 2026-10-30: Superpowers — keep in the repo or install as an account plugin. For the plugin: updates itself, works in every project. Against: the "project rules override skills" lines added to 4 skills are lost on plugin update; not verified whether cloud threads see account plugins (check before the review). Also assess the new short CLAUDE.md (5.9 KB instead of 25.5 KB) | coordinator (review) | 2026-10-30 | idea |
| R-17 | Home PC: one-time Claude permission allowlist for `godot.exe`, build/bench PowerShell scripts, copying into `E:\Claude\FlakHeaven\builds` — builds and benches stop waiting for «Разрешить» (review 30.10, №1) | Собрать тестовую сборку 3.5-s14 | 01.11 | Kanta «Да» 03.11. Done 31.10: allow rules for the two `Godot_v4.4.1-stable_win64*.exe` in `E:\Claude\FlakHeaven\engine` (user `settings.json`, s14 built without prompts). Left: fixed build/bench/copy scripts in `tools/pc/*.ps1` written by the next build session, then one more allow line for that folder only (no blanket PowerShell rule). Kanta action on the PC then: paste that one line |
| R-18 | With every build a page «что проверить» (≤ 15 lines); items Kanta does not flag become «проверено в sN» in the backlog the next day (review 30.10, №2) | Собрать тестовую сборку 3.5-s14 (с s14) | с s14 | в работе |
| R-19 | Posts from the approved weekly plan go out at 12:00 MSK unless Kanta writes «стоп» by 11:00; texts in Kanta's voice (devlog, opinions, replies) still need «ок» (review 30.10, №3) | Маркетинг и реклама | с 01.11 | в работе |
| R-20 | Steamworks fill-in page: S1–S3 fields with decided values, tax form choice, legal ways to pay the $100 fee from Russia (review 30.10, №4) | Еженедельное ревью работы | 31.10 | готово 31.10: Claude Doc https://claude.ai/artifact/STzH3DTeH3JqXe18LNM1DY |
| R-21 | Daily stand-up also updates `docs/owner-checklist/kanta-now.md`, backlog «Где мы сейчас», and a build line in `docs/status-log.md` (review 30.10, №5) | координатор (промпт планёрки) | 01.11 | в работе |
| R-22 | Feel and effects changes Kanta wants to judge (turret firing, flight feel, effects) go into `main` behind an F1/settings toggle, off by default until «ок» (review 30.10, №6) | все треды боя и эффектов; координатор в брифах | с 31.10 | правило, действует |
| R-23 | Build self-check as a script: contact sheet of hangar (classes × planes × weapons × lvl 1/3/5/modernised) and combat (nozzles, barrels, pylons, smoke) on a page attached to every build (review 30.10, №7) | 3D-модели по плану Kirill | до s15 | сделано 31.10 (#521): `nohup tools/ci/selfcheck.sh &`, первый лист https://claude.ai/artifact/68EA7avn1gQuhahhZrsaAK; найденные зазоры чинятся отдельным PR |
| R-24 | Memory cleanup: `MEMORY.md` index under 4 KB, duplicate «Russian names» memories merged; backlog R-10, R-14 statuses fixed (review 30.10, №8) | Еженедельное ревью работы | 31.10 | готово 31.10 |
| R-25 | Weekly marketing numbers (Sunday, one line in the stand-up): Telegram subscribers, Discord members, site visitors without bots, tester applications, posts out vs plan; starts R-13 (review 30.10, №9) | Маркетинг и реклама | с 01.11 | в работе |
| R-26 | Builds go from the cloud straight to itch.io (butler + `ITCH_API_KEY` already in the environment) and Yandex Disk («upload by URL» from the itch.io download link: Disk pulls it server-side). Bottleneck found 06.11: direct PUT cloud → Disk runs at 0.25–0.6 MB/s and the Disk uploader cuts it at ~30 s (502), while the cloud uploads to Google storage at ~18 MB/s. Disk half PROVEN on s17 (06.11): `GET api.itch.io/games/5196484/uploads` → `GET api.itch.io/uploads/<id>/download` (Bearer key, 302 to a signed dl.itch.zone URL) → `POST /v1/disk/resources/upload?url=…&path=…`; both 1.9 GB zips landed in minutes. Note: itch serves its own repacked zip (different size/SHA-256), so SHA256SUMS on the Disk are written from the Disk's own `sha256` field. Butler in the cloud: Kanta allowed it 06.11 («разрешаю butler в облаке»); v15.32.0 from `broth.itch.zone` (`.ovh` fails at the proxy), copy kept in `/mnt/project-files/tools/butler-linux/` (chmod +x, run with `BUTLER_API_KEY=$ITCH_API_KEY`); `butler status kanta2011/flak-heaven` works. Route for s18: cloud export → `butler push` → itch signed URL → Disk upload by URL; push speed to be measured on s18 | Собрать тестовую сборку 3.5-s17 | s18 | ready, first full run on s18 |
| R-27 | Single daily list of asks to Kanta (review 06.11, №2) | — | — | не принято (Kanta 06.11: «не критично») |
| R-28 | Balance = one numbered package per build cycle, each change «было → стало» (review 06.11, №3); CLAUDE.md rule 2, `working-rules.md`, `balance-method.md` updated | Еженедельное ревью работы | 06.11 | готово 06.11 |
| R-29 | Steam page art: 7 capsules (header, small, main, vertical, library capsule, library header, library hero) from key art and Forward+ frames + 8 screenshots of all three classes, one page for Kanta's «ок», no paid generators (review 06.11, №4) | Сделать капсулы и скриншоты для Steam (cmsg_01SdohJnNRxu3TbJs1P3Ny2WL7tQUNACaf3j1DA8bm5TsK) | before ~16.11 | v1 ready 06.11 for Kanta's «ок»: https://claude.ai/artifact/DHNSFkG2NJg1oBb66WDbiH, files /mnt/project-files/marketing/steam-art-v1/ (7 capsules + library logo + 8 screenshots + 1 spare), capture flags PR #597 |
| R-30 | Build cycle: «что проверить» page attached to the build message; 24 h after Kanta's first message about the build, unflagged items = «проверено в sN», list archived; build thread writes the `status-log.md` line (review 06.11, №5) | треды сборок | from s17 | правило записано 06.11 |
| R-31 | Clean-up: old twice-weekly backup routine off (daily Disk backup replaces it), stand-up prompt v3 for Kanta to paste, Steam thread marked as waiting for Valve, `MEMORY.md` under 4 KB (review 06.11, №6) | Еженедельное ревью работы | 06.11 | готово 06.11 (бэкап-рутина выключена, планёрка v3 стоит, MEMORY.md 3,8 КБ) |
| R-32 | Russian-language guard: an English reply is rewritten in Russian before sending; line in project instructions (review 06.11, №7) | координатор (настройки проекта) | 06.11 | готово 06.11 |
| R-33 | Weapons, damage and upgrade work on Opus, Fable only for texts (review 06.11, №8): Kanta asked «Почему?», answer given 06.11, waiting for the decision | координатор (выбор модели тредов) | с 06.11 | правило с 06.11 (Kanta «Ок») |
| T4-06, B-35 | Замер производительности: FPS и треугольники по логам реальных ПК (в облаке рендер программный — FPS не показателен); режим `--bench` в игре есть | Бой, звук и производительность | — | на проверке в сборке 3.5-s8 (колонки лога; прогон на ПК Kanta — по желанию) |
| CI-FLAKY-01 | Flaky test: `village_thread_test.gd` failed once in `unit.sh` on 24.10 after merging main into PR #372, then passed 3 of 3 reruns (threaded village build, timing?) | — | — | flaky test, watch |
| EX-11 | После демо: перки, меняющие правила (Е1), вес самолётов (Ж1), новые боссы (Г2), карта кампании (И2) | — | после демо | идея (отложено) |

R-05, R-07, R-12, R-15 тоже закрыты 22.10 — строки доживают до ближайшего ревью 30.10 и уйдут в архив. R-01, R-02, R-06, R-08, R-11 — правила, действуют с 22.10, закрыты (строка в конце архива). Отзыв внешних тестеров: план — `docs/playtest/external-2/plan.md`, задачи EX-01…EX-12 разложены выше по системам.

## Code review (2026-10-23)

Summary — `docs/review/code-2026-10-23/README.md`, standards — `docs/standards/` (`code.md`, `architecture.md`, `ui-design-system.md`). Thread "Ревью кода и стандарты разработки". Owners are assigned by the coordinator after Kanta answers the thread's questions; until then — idea.

| ID | Task | Thread / owner | Status |
| --- | --- | --- | --- |
| CR-01 | Clicking "Pin"/"Ban" picks the card: search buttons from the end of the list (`hud.gd:98`, `hud_screens.gd:103,147`) + an autotest check that clicks | "Бой: правки по 3.5-s10" (cycle 3.5-s10, Kanta 2026-10-23) | to verify in the next build (PR #341) |
| CR-02 | Empty card offer after pick, course, ban, reroll — screen with no exit: one `refill_offers` with the "repair and parts" branch (`main.gd:425,455,505`) | "Бой: правки по 3.5-s10" (cycle 3.5-s10, Kanta 2026-10-23) | to verify in the next build (PR #341) |
| CR-03 | Profile can be lost: check `rename`, look for `.tmp`/`.bak`, never overwrite a broken file (part of CS-02) | — | idea |
| CR-04 | Sortie row uploaded without player consent (demo too) — consent per DM-07 before the demo | "Демо для Next Fest" | idea |
| CR-05 | Gamepad: 0.3 s input delay on level-up and specialization screens (small, now — "Бой: правки по 3.5-s10", cycle 3.5-s10, Kanta 2026-10-23); focus in menu and screens (CS-11c) | delay: "Бой: правки по 3.5-s10"; focus: not assigned | delay: to verify in the next build (PR #341); focus: idea |
| CR-06 | Report receiver: text starting with `= + - @` gets a `'` prefix (`tools/reports/apps_script.gs`), then Kanta updates the script in the sheet | Kanta (together with RP-4) | idea |
| CS-01 | GDScript type warnings: enable, clean up, raise to errors | — | idea |
| CS-02 | `SaveIO`: atomic write, `.bak`, version, test folder override; `custom_user_dir_name="FlakHeaven"` before any rename | — | idea |
| CS-03 | Event bus `Events` + `RunState` (ADR-02, Kanta 2026-10-23: signals, approach 1): 4 PRs per `docs/superpowers/plans/2026-10-23-events-run-state.md` | thread "Ревью кода и стандарты разработки" | done 2026-10-23: PR #344, #345, #346 |
| CS-04 | One enemy list per frame + shared hit grid | — | idea |
| CS-05 | `DebugFlags`: launch flags read once, cheats only in debug | — | idea |
| CS-06 | Ids instead of Russian strings in logic (damage source, weapon, state, button actions) | — | idea |
| CS-07 | Python: `pyproject.toml` with ruff, `requirements.txt` with versions | — | idea |
| CS-08 | CI: `pick.sh` "all combat except list", smoke catches `ERROR:`/`SHADER ERROR`, `check_po` and `.gd` tools in smoke; tests in a temp `user://` | — | idea |
| CS-09 | Combat preload: operation models in the background, `Boom3D` and materials warmed up at sortie start | — | idea |
| CS-10 | Split `render3d.gd` (after Next Fest) | — | idea (after the demo) |
| CS-11 | UI design system: `UiStyle`, font size ≥ 14, shared buttons and tabs, gamepad focus (`docs/standards/ui-design-system.md` §6) | Переделать главное меню и настройки (with UI-01/UI-02) | in progress: `UiStyle` tokens and `UiFocus` merged 24.10 (PR #367) |
| CS-13 | Balance numbers: `tuning.gd` keeps only F1 sliders, others go to `game/scripts/balance/<system>.gd` when files are touched; update the CLAUDE.md rule (Kanta 2026-10-23, option 2) | every code thread; CLAUDE.md — "Короткий CLAUDE.md" | rule in force |
| CS-12 | Important review findings without their own row: spawner freezes bombers at the cap, bomb lead (`move_vel`), "Skvoznyak" summons without a cap, hints spent on the title screen, `TEST_PICKS` → 2, volume writes balance into `tuning.json`, settings do not fit at 1080, ground shader (13 samplers, `dFdx` in a branch), double explosion lights, `.import` for new models, 334 MB `models/pilot` in git, JPEG 4:2:0 normal map. Details — review README | split across system threads | idea |
| LANG-01 | Move internal text to English (Kanta 2026-10-23, option 2): new code, comments, commits and docs in English right away; existing files translated when touched; a separate pass over key documents — CLAUDE.md, `docs/game-context.md` ("Rules now" section), `docs/backlog.md` header, `docs/process/` | coordinator assigns; CLAUDE.md — thread "Короткий CLAUDE.md" | in progress (standards and CLAUDE.md done 2026-10-23) |

## Укрепрайон (activity 5, Kanta «да» 2026-10-25)

Spec `docs/superpowers/specs/2026-10-25-fortified-area-design.md`, plan `docs/superpowers/plans/2026-10-25-fortified-area.md`. Thread «Сделать активность «Укрепрайон» из крепости» owns `fort_area.gd`, the fort model and the fort parts of `render3d.gd` (coordinated with «Ускорить большие бои»).

| ID | Task | Thread / owner | Status |
| --- | --- | --- | --- |
| FA-01 | Activity logic: spawner `"fort"`, map fort pick, banner, 4 fixed launchers (≤ 4 missiles), 2 yard jeeps, reward, unit tests | Укрепрайон | done (#427) |
| FA-02 | Fort model set Г (procedural fort_build.gd), pieces with broken variants, tower launcher GLB | Укрепрайон | done (#431) |
| FA-03 | Conditional destructibility: piece HP from explosives, state swaps, debris and scorch, stays broken | Укрепрайон | done (#433) |
| FA-04 | Polish: burning citadel and store, smoke columns, yard props (trucks, crates, camo net), final frames on 3 presets | Укрепрайон | done (#434) |

## После Next Fest (процесс, 23.10.2026)

Тред пока не назначен; задачи возьмёт координатор после 25.01. Подробности — `docs/process/early-access.md`.

| ID | Задача | Тред / владелец | Срок | Статус |
| --- | --- | --- | --- | --- |
| EA-01 | Сбор отзывов и вишлистов за фест, один документ-разбор | идея | 08.03 | идея |
| EA-02 | Доводка по отзывам фестиваля и закрытого теста | идея | март | идея |
| EA-03 | Страница раннего доступа: цена, описание, дорожная карта для игроков | Маркетинг | март–апрель | идея |
| EA-04 | Дата выхода: ставим после закрытого теста (догадка: апрель–май) | Kanta | апрель | идея |
| EA-05 | Проверка `BUILD` в `main.gd:81` (`3.4-t1` при последней сборке 3.5-s10) | Бой / координатор | 30.10 | идея |

## Code review (2026-10-30)

Summary — `docs/review/code-2026-10-30.md` (main after the 3.5-s13 base, decals, medals, Highland models, backup). Thread "Провести ревью кода игры". Owners are assigned by the coordinator after Kanta's "готово".

| ID | Task | Thread / owner | Status |
| --- | --- | --- | --- |
| CR2-01 | Medal `aces` counter and class tally count fortresses and warships as aces, fortress twice (`medals.gd:33,43`) | "Провести ревью кода игры" | merged, PR #497 (30.10) — verify in s14 |
| CR2-02 | Empty placeholder `MeshInstance3D` breaks `Livery.apply` when a flare panel / fairing misses the skin (`render3d.gd:1901`) | "Провести ревью кода игры" | merged, PR #497 (30.10) — verify in s14 |
| CR2-03 | Fort pad flattened and wrecks scattered round forts the «Укрепрайон» activity never shows (`terrain3d.gd:18,1074`) | "Провести ревью кода игры" | wrecks: merged, PR #497; the flat pad stays (the fort may appear there later; a rebuild on activity start is a separate task) (fixes after Kanta's «исправляй все» 30.10) |
| CR2-04 | Backup pack: stale refs file → no bundle, "no refs file" note; `--branches` dropped (`tools/backup/make_pack.sh`) | "Провести ревью кода игры" | merged, PR #497 (30.10) — verify in s14 |
| CR2-05 | Small: medal bonus text at zero tiers, drone HP rule into `Drone`, transport caption stale rect, livery cmdline scan per frame, "+ цифра" at 3 digits (R-05, R-08, R-09, R-10, R-12) | "Провести ревью кода игры" | merged, PR #497 (30.10) — verify in s14 |
| CR2-06 | Balance decision: «Бомбы «Кита»» scales all explosions; «Подрывник» blast_dmg outside the dmg cap (R-06, R-07) | "Провести ревью кода игры" | done: option 1 (text + cap), Kanta 30.10 |
