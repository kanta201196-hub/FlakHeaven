# B-17. Инструменты для звука и музыки: стек и план

*Аналитик рынка и инструментов, 10.10.2026. Опирается на `s1-06-sound-brief.md` (33 события, чиптюн с живыми элементами, −16 LUFS) и решение «без найма, оплата только российской картой». Это не юридическая консультация, окончательное решение по лицензиям принимает Kirill.*

## Главное
1. **Эффекты.** Основа — **ChipTone** (результат CC0, бесплатно). «Мясо» для взрывов и попаданий генерируем в **Stable Audio Open 1.0** через уже установленный ComfyUI. Дыры закрываем готовыми CC0-паками Kenney.
2. **Музыка.** Боевые треки пишем в **BeepBox**: каждый канал выгружается отдельно, так что два синхронных слоя `_base` и `_intense` получаются без лишней работы. Для меню, итогов и набросков пробуем **ACE-Step 1.5**: веса под MIT, на результат разрешено коммерческое использование, хватает 4 ГБ видеопамяти.
3. **Доводка** — Audacity: обрезка, нормализация громкости, проверка цикла.
4. **Платить не за что.** Надёжного российского облачного сервиса с коммерческими правами на результат мы не нашли.
5. **ChatGPT** звук и музыку сам не создаёт. Он пишет промпты, настройки и скрипты.

## 1. Таблица инструментов

| Инструмент | Что делает | Цена | Можно ли в платной игре | Доступ из РФ | Требования | Оценка |
|---|---|---|---|---|---|---|
| [ChipTone](https://sfbgames.itch.io/chiptone) | ретро-SFX | бесплатно | **да**, все звуки CC0 | да (браузер / Windows) | любой ПК | **5** |
| [jsfxr / sfxr.me](https://sfxr.me/) | ретро-SFX | бесплатно | **да**: «Unrestricted commercial use»; код под [Unlicense](https://github.com/chr15m/jsfxr) | да | браузер | 4 |
| [Stable Audio Open 1.0](https://huggingface.co/stabilityai/stable-audio-open-1.0) | SFX, лупы до 47 с | бесплатно | **да**, если выручка < $1 млн в год, нужна регистрация в Stability ([лицензия](https://stability.ai/community-license-agreement)) | скачивание с HF после принятия условий; ⚠ см. риски | ComfyUI, ~2,3 ГБ модель, 8 ГБ хватает | **4** |
| [Stable Audio Open Small](https://huggingface.co/stabilityai/stable-audio-open-small) | SFX до 11 с | бесплатно | как у 1.0 | как у 1.0 | 0,5B, работает даже на CPU; узла ComfyUI в документации нет | 3 |
| [ACE-Step 1.5](https://github.com/ace-step/ACE-Step-1.5) | музыка, 10 с – 10 мин | бесплатно | **да**: веса MIT, на [карточке модели](https://huggingface.co/ACE-Step/Ace-Step1.5) прямо разрешено коммерческое использование | да (GitHub/HF) | < 4 ГБ видеопамяти; есть portable-сборка для Windows и [нативный узел ComfyUI](https://docs.comfy.org/tutorials/audio/ace-step/ace-step-v1-5) | **4** (чиптюн надо проверить) |
| [YuE](https://github.com/multimodal-art-projection/YuE) | песни с вокалом | бесплатно | да (Apache-2.0) | да | официально 24 ГБ+, на 8 ГБ только квантованные сторонние сборки | 2 |
| [MMAudio](https://github.com/hkchengrex/MMAudio) | SFX | — | **нет**: веса CC-BY-NC | — | 6 ГБ | 0 |
| [MusicGen](https://huggingface.co/facebook/musicgen-small) | музыка | — | **нет**: веса CC-BY-NC | — | — | 0 |
| [AudioLDM 2](https://huggingface.co/cvssp/audioldm2) | SFX | — | **нет**: CC-BY-NC-SA | — | — | 0 |
| [Tango 2](https://huggingface.co/declare-lab/tango2) / [TangoFlux](https://huggingface.co/declare-lab/TangoFlux) | SFX | — | **нет**: NC / только для исследований | — | — | 0 |
| [BeepBox](https://www.beepbox.co/) | чиптюн в браузере | бесплатно | **да**: «songs belong to their authors», код MIT | да | браузер | **5** для новичка |
| [Furnace Tracker](https://github.com/tildearrow/furnace) | чиптюн (NES, Genesis, SNES и др.) | бесплатно | да: лицензия GPL распространяется на программу, а не на созданную в ней музыку | да | Windows | 3 (трудно освоить) |
| [LMMS](https://lmms.io/) | DAW с эмуляцией NES, GameBoy, SID | бесплатно | да | да | Windows | 3 |
| Audacity | доводка, LUFS | бесплатно | да (инструмент) | да | Windows | **5** |
| [GigaChat «Создать песню»](https://kod.ru/gigachat-music-ai-generation) | музыка ~1,5 мин | бесплатно (бета) | **нет**: по [соглашению](https://developers.sber.ru/docs/ru/policies/gigachat/agreement) (п. 3.1) только некоммерческое использование, а Сбер получает лицензию на результат (п. 5.2) | да | — | 0 |
| ChatGPT | промпты, скрипты | уже оплачен | — | Россия не в [списке стран OpenAI](https://platform.openai.com/docs/supported-countries) | — | 3 как помощник |

FamiTracker и Bfxr мы сознательно не включили: условия в их официальных источниках мы не проверили, а BeepBox и Furnace закрывают ту же задачу.

## 2. Рекомендованный стек

**Эффекты (33 события)**
- **ChipTone** даёт основу для `gun_fire`, `enemy_fire`, `pickup`, `levelup`, `lock` и интерфейса. Звук короткий, атаку легко контролировать, лицензия CC0 без оговорок. Тон и тембр задаются точно, поэтому легко выполнить правило «свой огонь ниже и механический, чужой выше и энергетический».
- **Stable Audio Open 1.0 в ComfyUI** даёт плотный «реальный» слой для `explode`, `hit`, `missile_enemy` и `bomb`. Так выполняется требование ТЗ к гибридным эффектам: чистые 8-битные писки теряются в хаосе. ComfyUI у Kirill уже стоит для арта, отдельная установка не нужна.
- **Гибрид** — смешать в Audacity: слой ChipTone (атака) + слой SAO (тело и хвост) + при необходимости CC0 из Kenney.

**Музыка (≈10 мин)**
- **BeepBox** для `music_battle_1/2` и `music_boss`. Это готовый чиптюн: темп и такт точные, цикл получается автоматически, а слои `_base` и `_intense` выгружаются как две копии песни с разными приглушёнными каналами. Порог входа низкий, музыкальное образование не нужно, но для 3 мин материала закладываем 3–5 вечеров на трек.
- **ACE-Step 1.5** для `music_menu`, `music_result` и как генератор идей. Ровный цикл и синхронные стемы от него не гарантированы, поэтому для боевых слоёв он рискованнее. Умение делать чиптюн нигде не заявлено, его проверяем пробой.
- Живые элементы (стиль B): в ACE-Step пробуем теги вроде «chiptune with live drums and electric guitar». Если не выйдет, остаёмся на чистом чиптюне (стиль A).

**Доводка (Audacity, 10–20 мин на звук)**
- обрезать тишину в начале (≤5 мс) и сделать затухание хвоста;
- эффекты перевести в моно, пик ≤ −1 dBTP;
- музыку нормализовать через *Effect → Volume → Loudness Normalization* до −16 LUFS, затем лимитер −1 dB;
- длину цикла сделать кратной такту: длина = 60 / BPM × 4 × число тактов;
- в Godot включить Loop у импортированного OGG и проверить 10 повторов подряд.

## 3. План на 1–2 вечера

**Вечер 1. Эффекты (~3 ч)**
1. Открыть ChipTone в браузере.
2. Скачать с HF [stable-audio-open-1.0.safetensors](https://huggingface.co/stabilityai/stable-audio-open-1.0) (нужно принять условия) и `t5-base.safetensors`. Положить в `ComfyUI/models/checkpoints/` и `ComfyUI/models/text_encoders/`, взять шаблон из [документации ComfyUI](https://docs.comfy.org/tutorials/audio/stable-audio/stable-audio-1).
3. Настройки SAO: в `EmptyLatentAudio` длина **2–3 с** вместо 47 по умолчанию, steps 100, cfg 7. Сделать по 4 сида на промпт и **записать сид** в лог.
4. Сделать 8 эффектов P1 по таблице ниже, по 2–3 варианта каждого. Вставить в `audio/`, сыграть вылет, провести слепой тест «свой и чужой огонь».

| Событие | Инструмент | Промпт SAO / настройки ChipTone |
|---|---|---|
| `gun_fire` | ChipTone (+SAO) | ChipTone: шум + квадрат, низкий тон, атака 0, длина ~0,1 с. SAO-слой: `short punchy autocannon single shot, dry, mechanical, low-pitched, close mic, no reverb, game sound effect` |
| `enemy_fire` | ChipTone | высокий тон, пила или синус со спадом тона вниз («пиу»), ~0,15 с. SAO: `short bright sci-fi laser blaster zap, high-pitched, electric, retro arcade, dry` |
| `explode` | SAO + ChipTone | `mid-size explosion, punchy boom with debris crackle, short tail, 16-bit retro game sound effect`; сверху шумовой «бум» ChipTone для атаки |
| `hit` | SAO / ChipTone | `small metallic bullet impact on armor plate, short tick, dry, game sound effect`; укоротить до ≤0,2 с, атаку смягчить |
| `missile_enemy` | SAO | `missile launch whoosh with rising rocket hiss, aggressive, loud and distinct, arcade game` |
| `lock` | ChipTone | быстрые повторы квадратной волны («пи-пи-пи»), 2–3 кГц, ~0,6 с, вибрато. SAO-альтернатива: `fighter jet radar missile lock-on warning tone, rapid high beeps, alarm` |
| `pickup` | ChipTone | пресет Pickup/Coin, тон вверх, ≤0,15 с, мягкая громкость |
| `levelup` | ChipTone | арпеджио вверх (мажор), 0,6–0,8 с. SAO: `cheerful retro level up jingle, rising arpeggio, 8-bit chiptune` |

Негативный промпт для SAO: `music, speech, voice, reverb, noise floor, low quality`.

**Вечер 2. Боевой луп (~3 ч)**
1. ACE-Step 1.5: в ComfyUI обновиться до последней версии, взять шаблон ACE-Step 1.5 и модель `ace_step_1.5_turbo_aio.safetensors` ([инструкция](https://docs.comfy.org/tutorials/audio/ace-step/ace-step-v1-5)). Альтернатива — portable-сборка с GitHub. Теги: `instrumental, chiptune, 8-bit NES square lead, driving rock drums, electric bass, energetic action shmup, 150 bpm, loopable`, длина 60 с, 4–6 сидов.
2. Параллельно в BeepBox собрать 16–32 такта на 150 BPM: бас + барабаны (это `_base`), лид + перкуссия (это `_intense`). Выгрузить в WAV дважды, с разными приглушёнными каналами.
3. В Audacity нормализовать до −16 LUFS, вырезать цикл кратно такту, сохранить в OGG q6. В игре сравнить ACE-Step и BeepBox: решаем, какой путь берём для 5 треков.

## 4. Чем полезен ChatGPT
- **Не умеет:** создавать музыку и звуковые эффекты. Музыкальный инструмент OpenAI известен только [по слухам о разработке](https://www.digitalmusicnews.com/2025/10/27/openai-music-tool/).
- **Умеет:**
  - писать и варьировать английские промпты для SAO и ACE-Step;
  - расписать структуру трека (такты, BPM, тональность) для BeepBox;
  - написать Python-скрипт для пакетной обработки: обрезка, моно, нормализация через ffmpeg `loudnorm=I=-16:TP=-1`;
  - вести таблицу CREDITS.
- **Важно:** Россия не входит в список поддерживаемых стран OpenAI, поэтому на ChatGPT ничего не завязываем. Всё из этого может сделать и наша команда агентов.

## 5. Риски лицензий и как их снять
| Риск | Что делаем |
|---|---|
| SAO: лицензия Stability требует регистрации для коммерческого использования, условия по выручке < $1 млн и соблюдения экспортного и санкционного законодательства (Trade Control Laws) | До релиза зарегистрироваться через [stability.ai/license](https://stability.ai/license). Если регистрация из РФ невозможна или юридически сомнительна, заменить звуки SAO на ChipTone + CC0. Поэтому SAO используем только как слой, а не как основу |
| Модель с NC-лицензией попадёт в конвейер | Пользоваться только моделями из таблицы с «да». MMAudio, MusicGen, AudioLDM 2, Tango 2 и GigaChat запрещены |
| Сходство ИИ-трека с чужой музыкой | Не писать в промптах имена артистов и игр. Прогнать треки через Shazam или аналог перед релизом |
| Раскрытие ИИ в Steam | В анкете Steam о контенте указать: «звук и музыка частично сгенерированы локальными моделями» |
| Невозможно доказать происхождение | Для каждого файла вести строку в `audio/CREDITS.md` (формат ниже). Исходные WAV и файлы проектов (`.json` из BeepBox, сохранённые настройки ChipTone, workflow ComfyUI) хранить в `audio_src/` |

Формат строки в `audio/CREDITS.md`:
```
explode_1.ogg | SAO 1.0 (Stability Community License) seed 123456, steps 100, cfg 7 | prompt: "..." | + ChipTone (CC0) | правка: Audacity | 2026-10-12
```

**Решение для Kirill:** утвердить стек (ChipTone + SAO для эффектов, BeepBox + проба ACE-Step для музыки) и запустить 2 вечера пробы. Итог пробы — 8 эффектов и 1 боевой луп в `audio/` плюс заполненный CREDITS.
