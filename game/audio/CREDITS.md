# Звуки и музыка — источники

## Эффекты (стиль «гибрид», 16.10.2026)
Боевые звуки, манёвры, сигналы кабины, двигатель и события механик 3.5 — реальные записи из **Sonniss GDC Game Audio Bundle**
(бандлы 2015–2026, https://gdc.sonniss.com). Лицензия Sonniss: можно в коммерческой игре, указывать автора не обязательно,
нельзя распространять сами исходники как библиотеку звуков (в игре — можно). Какой файл из какого пакета взят, с какого места
и как обработан — в `game/tools/build_audio_hybrid.py` (словари `SRC` и `PLAN`); там же пересборка одной командой.

Авторы пакетов (вежливо указать в титрах): Fascinated Sound, Gamemaster Audio, Pole Position Production, Bluezone Corporation,
Sound Spark LLC, SoundMorph, InspectorJ, SmartSoundFX, 344 Audio, Gregor Quendel, The Chris Alan, Airborne Sound, David Dumais Audio,
Articulated Sounds, Sergey Eybog, Olivier Girardot, Gladestock Studios, Justsoundeffects, Mechanical Wave, Epic Stock Media,
Rescopic Sound, Eiravaein Sound, Stefano Cremona, Double Trouble Audio.

## Интерфейс, джинглы, музыка (CC0, с 10.10.2026)
Все файлы — CC0 (общественное достояние): указывать авторов не обязательно, но вежливо — укажем в титрах игры.

| Файлы | Источник | Автор | Лицензия |
| --- | --- | --- | --- |
| pickup, card, ui_ban | Interface Sounds — https://kenney.nl/assets/interface-sounds | Kenney | CC0 |
| levelup, boss, evac, gate | Music Jingles — https://kenney.nl/assets/music-jingles | Kenney | CC0 |
| repair | Digital Audio — https://kenney.nl/assets/digital-audio | Kenney | CC0 |
| music_menu, music_battle_1/2, music_boss, music_result | 5 Chiptunes (Action) — https://opengameart.org/content/5-chiptunes-action | Juhani Junkala | CC0 |

Обработка этих файлов: `game/tools/build_audio.py` (нужен ffmpeg). Музыку по стилю «гибрид» ещё предстоит заменить.
