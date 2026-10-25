# Звуки и музыка

Файл в этой папке заменяет звук-заглушку, если его имя совпадает с именем события.
- Форматы: `.ogg` (лучше), `.wav`, `.mp3`.
- Несколько вариантов одного звука: `explode_1.ogg`, `explode_2.ogg`… Они играют вперемешку.
- Если для события нет своего файла, играет общий звук (столбец «Замена»). Поэтому заменять можно по одному.
- Громкость эффектов, двигателя и музыки настраивается на панели F1.

## События

| Событие | Когда | Замена | Что искать |
| --- | --- | --- | --- |
| engine | гул двигателя (цикл, тон = скорость, на форсаже выше и громче) | — | jet / rocket engine loop |
| engine_prop | гул винтовых моторов «Кита 1» (цикл); нет файла — играет engine | engine | prop / radial engine loop |
| gun_fire | курсовое игрока | shot | machine gun / cannon single shot |
| gunpod_fire | пушечная гондола | shot | autocannon short |
| turret_fire | автотурели | shot | turret / light MG |
| enemy_fire | выстрелы врагов, зениток, асов | shot | laser / blaster / flak short |
| flare | противоракеты | shot | flare / pop |
| aam_launch | ракеты В-В | launch | missile launch |
| rocket_launch | залп НАР | launch | rocket salvo / whoosh |
| missile_enemy | пуск вражеской ракеты | launch | missile launch (ниже тоном) |
| bomb_drop | сброс бомб (щелчок замка держателя и шорох воздуха) | launch | bomb release / shackle |
| bomb | взрыв бомбы | — | explosion heavy |
| explode | взрыв мелкого врага | — | explosion small |
| explode_big | взрыв крупного врага / аса | explode | explosion large |
| player_explode | гибель игрока | explode | explosion + debris |
| hit | попадание по врагу | — | bullet impact metal |
| pass_hit | проход на форсаже | hit | heavy impact / crunch |
| player_hit | попадание по игроку | — | metal hit heavy |
| shield_break | щит аса пробит | explode | glass / energy break |
| lock | захват ракетой | — | missile lock beep |
| radio | реплика по радио | lock | radio beep / squelch |
| roll | бочка | — | whoosh |
| near_miss | «на волоске» | roll | bullet whiz / flyby |
| combat_turn | боевой разворот | roll | swoosh heavy |
| shield | бронещит | lock | force field on |
| afterburner | форсаж | — | afterburner ignition |
| pickup | опыт | — | blip / coin soft |
| repair | ремкомплект | levelup | power up |
| levelup | новый уровень | — | jingle short |
| card | карточка, клик UI | — | ui click / confirm |
| ui_ban | исключение карточки | player_hit | ui error / cancel |
| boss | ас / активность | — | alarm / horn |
| evac | эвакуация успешна | — | success jingle |
| gate | ворота эвакуации | evac | positive chime |
| music_menu | меню, итоги | — | calm / title loop |
| music_battle | бой | — | action loop |
| music_boss | ас, догфайт | — | intense / boss loop |
| dive | «нырок» вниз | roll | dive whoosh / engine pitch down |
| synergy | собрана связка карточек | boss | power chord / stinger |
| cargo | транспортник сбит, груз | evac | loot / reward stinger |
| fuel_low | топливо меньше 10% | lock | low fuel warning beep (кабина) |
| fuel_empty | бак пуст | lock | engine sputter / warning |
| tanker_call | заправщик на подходе | evac | radio call / chime |
| tanker_down | заправщик сбит | shield_break | large aircraft explosion |
| boom_dock | штанга состыковалась | lock | mechanical clunk / latch |
| boom_undock | расстыковка | lock | release / hiss |
| refuel_done | бак полный | evac | positive chime |
| aa_alert | позиция ПВО заметила игрока | lock | radar warning / siren |
| sam_lock | ЗРК берёт на сопровождение | lock | SAM lock tone |
| sam_launch | пуск ЗРК | missile_enemy | heavy missile launch |
| aa_intercept | ЗСУ сбивает ракету игрока | enemy_fire | flak burst |
| fortress_part | «Крепость»: выбита часть | shield_break | metal explosion / debris |
| fortress_ring | «Крепость»: залп кольцом | enemy_fire | multi-cannon burst |

## Стиль (решение Kanta 16.10.2026)
**Гибрид:** эффекты похожи на настоящие (пушки, реактивные двигатели, взрывы, писки систем предупреждения в кабине), музыка — электроника с рок-барабанами. Свой огонь — плотная автоматическая пушка, вражеский — глухие далёкие хлопки (другой тембр, не путаются); `missile_enemy`, `lock`, `sam_lock` — самые заметные.

**Что сделано 16.10:** все боевые звуки, манёвры, сигналы кабины, двигатель и 16 событий 3.5 заменены реальными записями из Sonniss GDC — `game/tools/build_audio_hybrid.py` (что откуда взято — в его `PLAN`). Каждый звук выровнен по громкости прежнего, так что баланс в коде не менялся. Звуки подбирал Claude по описаниям и спектрам, без прослушивания: на слух их проверяет Kanta. Чтобы заменить один звук, поменяйте его строку в `PLAN` и запустите скрипт с `--only имя_события`. Музыка — 6 треков CC0 с OpenGameArt: drum and bass / jungle в бою (три трека вперемешку), индастриал-метал у аса, спокойная электроника в меню и на итогах (`--only music`). 17.10 заменены и 8-битные джинглы: новый уровень, ремкомплект, эвакуация, ворота, тревога «ас». Прежними (Kenney) остались только клики интерфейса и подбор опыта.

**Пилот 18.10 (8 эффектов и микшер):** `explode`, `explode_big`, `bomb`, `hit`, `player_hit`, `gun_fire`, `enemy_fire`, `aam_launch` собраны из нескольких слоёв (удар, раскат в стерео, обломки, низкий гул, синтезированный кодом) — `game/tools/build_audio_layers.py`. Громкость удара прежняя, длиннее и богаче только хвост. Микшер в `sfx.gd`: шины SFX (лёгкий компрессор) и Music, лимитер на Master; 24 голоса, у частых звуков предел копий (`VOICE_CAP`), важные сигналы (`PRIORITY`) забирают голос у обычных; крупные события на полсекунды приглушают музыку (`DUCK`). `play(имя, дБ, тон, точка)`: с точкой боя звук идёт слева или справа по месту на экране (сейчас — попадания, взрывы, огонь врагов, бомбы).

**Вторая восьмёрка 18.10:** `engine` (стерео и тихий свист турбины), `afterburner`, `player_explode`, `tanker_down`, `rocket_launch` (залп), `missile_enemy`, `sam_launch`, `flare`. Kanta на слух: все новые варианты лучше прежних. **Фон биома:** `ambient_highland` (горный ветер) и `ambient_sea` (прибой и ветер) — тихий цикл под боем, громкость `AMBIENT_DB` в `sfx.gd`; биом выбирает `Sfx.set_ambient("sea")`.

**Музыка под накал боя (18.10):** звуки боя копят «накал» (`HEAT` в `sfx.gd`), без боя он остывает примерно за 15 с. В затишье музыка боя глуше (срез верха до 900 Гц на шине Music) и на 4 дБ тише, в свалке звучит полностью. У аса и в меню музыка всегда полная. Настраивается в `HEAT`, `HEAT_COOL`, `CALM_CUT_HZ` и `CALM_DB`.

**Море Архипелага (18.10, по просьбе треда «Второй биом»):** `ship_horn` (гудок крупного судна: запись гудка катера на две октавы ниже, синтез того же тона и эхо над водой), `gulls_1…3` (чайки у гавани, тихий фон по 7 с, играть без убавления громкости), `ship_sink_1…2` (водяной взрыв, всплеск, стон корпуса, пузыри). События только из файлов (`FILE_ONLY` в `sfx.gd`), вызовы ставит тред биома. Пересборка: `build_audio_layers.py --only sea,ship_sink`.

**Музыка боя и аса — рок (18.10, выбор Kanta):** три трека боя и тема аса от одного автора (nene, CC0), `build_audio_layers.py --only music_rock`. Треки боя идут по очереди, а не одной петлёй. Меню — Heart of Machine (Alexandr Zhelanov, CC-BY), итоги — Remembrance (bobjt, CC0), выбор Kanta 19.10.

**Очередь автотурели (25.10, турели «как в Sublight»):** `turret_burst_1…3` — 4 выстрела через ~45 мс в одном файле (хлопок автомата + низкий удар + сухой щелчок, отзвук у последнего), один `play("turret_burst")` на очередь. Громкость удара — как у `turret_fire`. Пересборка: `build_audio_layers.py --only turret_burst`.

## Источники 10.10.2026 (до гибрида; лицензии проверены 10.10.2026)

Без указания автора, можно в платной игре:
1. **Kenney — Sci-fi Sounds** (CC0): двигатель (`spaceEngine*`, `thrusterFire*`), взрывы (`explosionCrunch*`, `lowFrequency_explosion*`), выстрелы врагов (`laser*`), щит (`forceField*`). https://kenney.nl/assets/sci-fi-sounds
2. **Kenney — Impact Sounds** (CC0): попадания (`impactMetal*`, `impactPlate*`). https://kenney.nl/assets/impact-sounds
3. **Kenney — Interface Sounds** (CC0): клики, подтверждения, ошибки. https://kenney.nl/assets/interface-sounds
4. **Kenney — Music Jingles** (CC0): новый уровень, эвакуация, ворота. https://kenney.nl/assets/music-jingles
5. **Kenney — Digital Audio** (CC0): подбор, писки радио и захвата. https://kenney.nl/assets/digital-audio
6. **The Free Firearm Sound Library** (CC0, 194 МБ): записанные очереди автоматического оружия для курсового, гондолы и турелей. https://opengameart.org/content/the-free-firearm-sound-library
7. **Impacts — Eldritch Grim** (CC0): тяжёлые удары для тарана и прохода на форсаже. https://opengameart.org/content/impactsgunsfx
8. **Rocket engine — theMinesAreShakin** (CC0, зацикливается): гул двигателя. https://opengameart.org/content/rocket-engine
9. **Soundpack 03 — crazyduckgames** (CC0): ретро-взрывы, если нужен 8-битный стиль. https://opengameart.org/content/soundpack-03
10. **Музыка: 5 Chiptunes (Action) — Juhani Junkala** (CC0): `title screen` → music_menu, `level1/2` → music_battle, `level3` → music_boss. https://opengameart.org/content/5-chiptunes-action
11. **Музыка: Fast fight / battle music (looped)** (CC0): вариант для music_boss. https://opengameart.org/node/55385

С указанием автора (CC-BY: автора записываем в CREDITS.md):
- dklon — Rocket launch pack (4 пуска) → aam_launch / rocket_launch. https://opengameart.org/content/rocket-launch-pack
- dklon — Jet engine takeoff / Fighter engine flyby → afterburner. https://opengameart.org/content/jet-engine-takeoff
- Michel Baradari — 4 projectile launches → rocket_launch. https://opengameart.org/content/4-projectile-launches

Для качества ближе к релизу: **Sonniss GDC Bundle** (бесплатный, без указания автора, около 7,5 ГБ: оружие, взрывы, техника). https://gdc.sonniss.com

Нельзя: CC-BY-NC (запрет коммерции), CC-BY-SA и GPL (обязывают раскрывать или лицензировать производные работы).
