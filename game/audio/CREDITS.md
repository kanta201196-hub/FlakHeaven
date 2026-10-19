# Звуки и музыка — источники

## Эффекты (стиль «гибрид», 16.10.2026)
Боевые звуки, манёвры, сигналы кабины, двигатель, награды (новый уровень, ремкомплект, эвакуация, ворота), тревога «ас» и события механик 3.5 — реальные записи из **Sonniss GDC Game Audio Bundle**
(бандлы 2015–2026, https://gdc.sonniss.com). Лицензия Sonniss: можно в коммерческой игре, указывать автора не обязательно,
нельзя распространять сами исходники как библиотеку звуков (в игре — можно). Какой файл из какого пакета взят, с какого места
и как обработан — в `game/tools/build_audio_hybrid.py` (словари `SRC` и `PLAN`); там же пересборка одной командой.

Авторы пакетов (вежливо указать в титрах): Fascinated Sound, Gamemaster Audio, Pole Position Production, Bluezone Corporation,
Sound Spark LLC, SoundMorph, InspectorJ, SmartSoundFX, 344 Audio, Gregor Quendel, The Chris Alan, Airborne Sound, David Dumais Audio,
Articulated Sounds, Sergey Eybog, Olivier Girardot, Gladestock Studios, Justsoundeffects, Mechanical Wave, Epic Stock Media,
Rescopic Sound, Eiravaein Sound, Stefano Cremona, Double Trouble Audio, Chris Logsdon, G4F SFX,
Alexander Kopeikin, SoundBits (пилот 18.10, `game/tools/build_audio_layers.py`),
The Sound Pack Tree, SoundHolder, Soundrangers, Mattia Cellotto, Soundopolis (море Архипелага, 18.10).

## Музыка (стиль «гибрид», 16.10.2026, все CC0 с OpenGameArt)

| Файл | Трек | Автор | Лицензия |
| --- | --- | --- | --- |
| music_menu | Heart of Machine — https://opengameart.org/content/heart-of-machine | Alexandr Zhelanov | **CC-BY 3.0 — автора указать в титрах** |
| music_battle_1 | Unchained Destiny (rock) — https://opengameart.org/content/unchained-destiny-rock | nene | CC0 |
| music_battle_2 | Boss Battle #8 (metal) — https://opengameart.org/content/boss-battle-8-metal | nene | CC0 |
| music_battle_3 | Short Theme (rock/metal) — https://opengameart.org/content/short-theme-rockmetal | nene | CC0 |
| music_boss | Boss Battle #9 (metal) — https://opengameart.org/content/boss-battle-9-metal | nene | CC0 |
| music_result | Remembrance — https://opengameart.org/content/remembrance-0 | bobjt | CC0 |

Меню и итоги — выбор Kanta 19.10. Бой и ас — выбор Kanta 18.10 (рок одного автора), сборка `game/tools/build_audio_layers.py --only music_rock`. Меню и итоги — `game/tools/build_audio_hybrid.py --only music`. Обработка меню и итогов: обрезка длинных треков с затуханием, громкость −16 LUFS.

## Интерфейс (CC0, с 10.10.2026)
Все файлы — CC0 (общественное достояние): указывать авторов не обязательно, но вежливо — укажем в титрах игры.

| Файлы | Источник | Автор | Лицензия |
| --- | --- | --- | --- |
| pickup, card, ui_ban | Interface Sounds — https://kenney.nl/assets/interface-sounds | Kenney | CC0 |

Обработка этих файлов: `game/tools/build_audio.py` (нужен ffmpeg).
