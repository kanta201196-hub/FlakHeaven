# Звуки и музыка

Файл в этой папке заменяет звук-заглушку, если его имя совпадает с именем события.
- Форматы: `.ogg` (лучше), `.wav`, `.mp3`.
- Несколько вариантов одного звука: `explode_1.ogg`, `explode_2.ogg`… Они играют вперемешку.
- Если для события нет своего файла, играет общий звук (столбец «Замена»). Поэтому заменять можно по одному.
- Громкость эффектов, двигателя и музыки настраивается на панели F1.

## События

| Событие | Когда | Замена | Что искать |
| --- | --- | --- | --- |
| engine | гул двигателя (цикл, тон = скорость) | — | jet / rocket engine loop |
| gun_fire | курсовое игрока | shot | machine gun / cannon single shot |
| gunpod_fire | пушечная гондола | shot | autocannon short |
| turret_fire | автотурели | shot | turret / light MG |
| enemy_fire | выстрелы врагов, зениток, асов | shot | laser / blaster / flak short |
| flare | противоракеты | shot | flare / pop |
| aam_launch | ракеты В-В | launch | missile launch |
| rocket_launch | залп НАР | launch | rocket salvo / whoosh |
| missile_enemy | пуск вражеской ракеты | launch | missile launch (ниже тоном) |
| bomb_drop | ковровый удар | launch | bomb release / whistle |
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

## Подобранные источники (лицензии проверены 10.10.2026)

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
