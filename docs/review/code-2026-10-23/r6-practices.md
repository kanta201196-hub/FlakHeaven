# Лучшие практики для Flak Heaven (Godot 4.4.1, GL Compatibility, GDScript + Python/bash)

Собрано 23.10.2026 по первичным источникам (docs.godotengine.org/en/4.4, godotengine.org/releases, partner.steamgames.com, docs.blender.org, docs.astral.sh, GitHub-репозитории фреймворков).
Формат: правило — почему — источник. «Догадка» — то, что не подтвердил по источнику.

## 0. Что именно есть в 4.4 и чего нет (проверено)
- **Типизированные словари `Dictionary[K, V]` появились в 4.4** — в ядре, GDScript и инспекторе. Можно использовать. — https://godotengine.org/releases/4.4/
- **Файлы `.uid` (4.4) коммитить обязательно**, `*.uid` не добавлять в `.gitignore`. При переносе скрипта или шейдера вне редактора переносить и его `.uid`; после переноса пересохранить зависимые сцены. Без `.uid` ссылки на другой машине ломаются (есть откат на путь с предупреждением, на него не полагаться). — https://godotengine.org/article/uid-changes-coming-to-godot-4-4/
- **`@abstract` (классы и методы) — это 4.5, не 4.4.** Вариативные аргументы `...args`, `duplicate_deep()`, свои логгеры, бэктрейс в релизе — тоже 4.5. В 4.4.1 их не писать. — https://godotengine.org/releases/4.5/
- **`@warning_ignore_start` / `@warning_ignore_restore`** описаны в документации 4.4 — https://docs.godotengine.org/en/4.4/tutorials/scripting/gdscript/warning_system.html (в какой версии добавлены — не нашёл; есть в доках 4.4, значит доступны).
- Вложенные типизированные коллекции (`Array[Array[int]]`) не поддерживаются. — https://docs.godotengine.org/en/4.4/tutorials/scripting/gdscript/static_typing.html
- Тип переменной цикла (`for e: Enemy in enemies:`) — с 4.2. — там же.
- 4.4 добавил: интерполяцию физики в 3D, Jolt (экспериментально), ubershaders против фризов компиляции шейдеров, встроенное окно игры (не на macOS), `@export_tool_button`. — https://godotengine.org/releases/4.4/

## 1. Стиль GDScript
- **Имена:** файлы и функции/переменные `snake_case`, `class_name` и узлы `PascalCase`, константы и значения enum `CONSTANT_CASE`, имя enum в единственном числе, сигналы в прошедшем времени (`health_changed`, `enemy_died`). — https://docs.godotengine.org/en/4.4/tutorials/scripting/gdscript/gdscript_styleguide.html
- **Приватное — с `_`** (поля, функции, виртуальные методы). Так сразу видно, что трогать снаружи нельзя. — там же.
- **Табы, строка < 100 символов (лучше < 80), одна инструкция в строке, `and/or/not` вместо `&&/||/!`.** — там же.
- **Порядок в файле:** `@tool/@icon` → `class_name` → `extends` → `##` doc → сигналы → enum → константы → static var → `@export` → прочие var → `@onready` → `_static_init` → static-методы → `_init/_enter_tree/_ready/_process/_physics_process/прочие виртуальные` → свои переопределения → остальные методы → внутренние классы; внутри группы публичное раньше приватного. Агенты пишут единообразно, ревью легче. — там же.
- **`:=` только когда тип очевиден справа**, иначе явный тип (особенно `get_node()`, `$Node`). — там же.

## 2. Статическая типизация и предупреждения (важно для кода от агентов)
- **Типизировать всё:** переменные, параметры, возвраты, `Array[T]`, `Dictionary[K, V]`. Ошибки ловятся до запуска, а типизированный код быстрее («optimized opcodes when operand/argument types are known»). — https://docs.godotengine.org/en/4.4/tutorials/scripting/gdscript/static_typing.html
- **Включить предупреждения в `project.godot`** (по умолчанию выключены; значения 0 = игнор, 1 = предупреждение, 2 = ошибка — значения кодов: догадка, подтверждено только «int, default 0»):
  `debug/gdscript/warnings/untyped_declaration`, `inferred_declaration` (по желанию), `unsafe_property_access`, `unsafe_method_access`, `unsafe_cast`, `unsafe_call_argument`. `exclude_addons = true` по умолчанию — аддоны не шумят. — https://docs.godotengine.org/en/4.4/classes/class_projectsettings.html
- **Ошибкой (2) делать постепенно:** сначала `untyped_declaration` как warning, вычистить, потом поднять до error — тогда smoke.sh упадёт на нетипизированном коде агента. Почему: запуск игры блокируют только предупреждения, переведённые в ошибки. — https://docs.godotengine.org/en/4.4/tutorials/scripting/gdscript/warning_system.html (порядок внедрения — догадка/рекомендация).
- **Глушить точечно `@warning_ignore("имя")`**, а не выключать глобально. — там же.
- `UNSAFE_*` покрывают не все «небезопасные строки», которые подсвечивает редактор. — static_typing.html

## 3. Архитектура сцен и узлов
- **Сцены самодостаточны, зависимости даёт родитель:** сигнал ребёнка, вызов метода ребёнка, присвоение Callable, ссылки на Node или NodePath. Соседи не ссылаются друг на друга напрямую, общение — через общего предка («вызов вниз, сигнал вверх» — формулировка сообщества, сама статья её не использует). — https://docs.godotengine.org/en/4.4/tutorials/best_practices/scene_organization.html
- **Структура: Main → World (смена уровней) + GUI (вне World, чтобы не удалялся при переходах).** — там же.
- **Внешние зависимости узла документировать через `@tool` + `_get_configuration_warnings()`** — иконка-предупреждение в дереве сцены. — там же.
- **Автозагрузки — только для систем, которые ведут свои данные и не меняют чужие** (сохранения, настройки, аудио-шина, кампания). Общая логика — `static func`, `class_name`-помощники, `static var`; общие данные — свой `Resource`. Глобальное состояние = баг может прийти откуда угодно. — https://docs.godotengine.org/en/4.4/tutorials/best_practices/autoloads_versus_internal_nodes.html
- **Свойства задавать до `add_child()`** (кроме глобальной позиции) — некоторые сеттеры дорогие в дереве. — https://docs.godotengine.org/en/4.4/tutorials/best_practices/logic_preferences.html
- **`preload` для того, что нужно в горячем коде** (и для `const`); `load` — когда ресурс меняется или его надо освобождать. Не `preload`-ить значение по умолчанию у `@export` — его перезапишет сцена. — там же.
- **Данные:** Array — быстрый перебор/индекс, Dictionary — по ключу; int-enum быстрее строк. — https://docs.godotengine.org/en/4.4/tutorials/best_practices/data_preferences.html
- **Параметры баланса и описания оружия/врагов — в своих `Resource` (`.tres`)** с `@export`: правятся в инспекторе, типизированы, диффятся. — догадка (общепринятая практика; в data_preferences этого нет). У проекта сейчас `tuning.gd` — тоже допустимо, вопрос к Kanta.

## 4. Сигналы
- **Подключать через Callable:** `timer.timeout.connect(_on_timer_timeout)`, испускать `signal.emit(...)` — без строковых имён, с автодополнением. — https://docs.godotengine.org/en/4.4/getting_started/step_by_step/signals.html
- **Сигналы в прошедшем времени, обработчики `_on_<узел>_<сигнал>`.** — там же.
- **Аргументы сигнала типизировать** (`signal damaged(amount: float)`); движок не проверяет то, что передаёт `emit` — проверка на авторе. — там же (типы в объявлении — синтаксис GDScript, в примере статьи без типов).

## 5. Производительность bullet heaven
- **Сначала профайлер, потом оптимизация;** мерить среднее по многим прогонам; профайлер сам замедляет игру. — https://docs.godotengine.org/en/4.4/tutorials/performance/cpu_optimization.html
- **Каждый узел стоит денег:** меньше узлов, больше работы в каждом (один менеджер пуль обходит массив, а не 2000 узлов с `_process`). Удалять из дерева выгоднее, чем прятать/паузить. — там же.
- **Пули/частицы/гильзы рисовать через `MultiMeshInstance3D`:** один вызов отрисовки на тип; заранее выделить максимум `instance_count`, менять `visible_instance_count`; `transform_format` задавать до `instance_count`. Отсечение — только целиком, поэтому большой мир делить на несколько MultiMesh. — https://docs.godotengine.org/en/4.4/tutorials/performance/using_multimesh.html
- **Логика пуль — в плотных массивах** (Packed*Array/typed Array), не в узлах; данные линейно — меньше промахов кэша. — cpu_optimization.html
- **Тысячи объектов каждый кадр — кандидаты на `RenderingServer`/`PhysicsServer2D` напрямую,** но только если профайлер показал проблему. RID освобождать вручную (`free_rid`), держать ссылку на ресурс. **Не читать значения с сервера каждый кадр** — это синхронизация и сильная просадка; вызовы — «только запись». — https://docs.godotengine.org/en/4.4/tutorials/performance/using_servers.html
- **Пул объектов вместо `instantiate()/queue_free()` в бою:** проблема не среднее время, а пик в кадре массового спавна. Пулить заранее (на загрузке), выключать у неактивных обработку и столкновения, не только `hide()`. — сообщество, официальной страницы о пулах в 4.x нет: https://uhiyama-lab.com/en/notes/godot/godot-object-pooling-basics/ , https://forum.godotengine.org/t/performance-drops-when-instantiating-thousands-of-objects/105227
- **GPU:** переиспользовать материалы (одинаковые фичи StandardMaterial3D = один шейдер), склеивать статичные меши заранее, меньше прозрачности (сортировка и fill rate), LOD, без треугольников мельче пикселя. Проверка fill rate: выключить V-Sync, сравнить FPS в большом и маленьком окне. — https://docs.godotengine.org/en/4.4/tutorials/performance/gpu_optimization.html
- **Физику оставить 60 Гц**, простые формы столкновений; при рывках включить интерполяцию физики (в 3D — с 4.4). — cpu_optimization.html, releases/4.4
- **Загрузка тяжёлого (следующая операция, ангар) — `ResourceLoader.load_threaded_request` → проверять `load_threaded_get_status` → `load_threaded_get`.** `load_threaded_get` до готовности блокирует как `load`. — https://docs.godotengine.org/en/4.4/tutorials/io/background_loading.html
- Производительность мерить на реальных ПК / Steam Deck — совпадает с правилом проекта; доки: «Test early and often on target devices». — gpu_optimization.html

## 6. GL Compatibility — ограничения
- **Нет:** SDFGI, VoxelGI, SSIL, SSAO, SSR, объёмного тумана, декалей, DOF, TAA, FSR2, FXAA (в 4.4), compute-шейдеров, RenderingDevice, CompositorEffects, 2D HDR, subsurface scattering, проекторов света, PCSS. — https://docs.godotengine.org/en/4.4/tutorials/rendering/renderers.html
- **Есть:** MSAA 3D, glow, туман по глубине и высоте. — там же.
- **Свет: обычный forward, до 8 omni/spot на меш, до 8 directional, до 2 reflection probe на меш** — много вспышек-огней от взрывов не делать настоящими OmniLight; эмиссия + glow или спрайт. — там же (совет про вспышки — догадка).
- Forward+/Mobile сами откатываются на Compatibility без Vulkan/D3D12/Metal (настраивается). — releases/4.4
- На macOS Compatibility работает через ANGLE/Metal или OpenGL — **догадка**, проверить по логам тестеров.

## 7. Сохранения и настройки
- **Только `user://`.** — https://docs.godotengine.org/en/4.4/tutorials/io/saving_games.html
- **Настройки игрока — `ConfigFile`**, прогресс — JSON (читаемо) или `FileAccess.store_var/get_var` (компактно, поддерживает Vector2/Color). JSON не знает Vector2/Color и т.п. — раскладывать вручную. — там же.
- **Хранить версию формата сохранения и мигрировать** — догадка (общепринятая практика, в статье нет).
- **Не грузить объекты из недоверенных файлов** (`get_var(allow_objects=true)`, `str_to_var` с объектами) — может выполнить код. — догадка по API (в статье не описано), см. https://docs.godotengine.org/en/4.4/classes/class_fileaccess.html
- **В JSON целые читаются как float** — догадка (известное поведение `JSON.parse`, на странице не подтвердил).

## 8. Локализация
- **gettext `.po` лучше CSV:** файл на язык (меньше конфликтов в Git), стандарт для Poedit/Weblate, удобнее многострочные строки. — https://docs.godotengine.org/en/4.4/tutorials/i18n/localization_using_gettext.html
- **POT генерировать в редакторе** (Project Settings → Localization → POT Generation) после каждого изменения строк; `msgmerge --update` для языков; снимать `fuzzy` (Godot их игнорирует); `msgfmt --check` в CI. — там же.
- **Контекст — второй аргумент `tr("…", "ctx")`, множественное — `tr_n()`.** Для русского и китайского форм множественного числа разное число — без `tr_n` нельзя. — там же.
- **`# TRANSLATORS:` — заметка переводчику, `# NO_TRANSLATE` — исключить строку.** Константные `text`, `tooltip_text`, `add_item()` попадают в POT сами. — там же.
- **`.po` в Git, `*.translation` — в `.gitignore`.** — та же страница + https://docs.godotengine.org/en/4.4/tutorials/best_practices/version_control_systems.html

## 9. Интерфейс: тема как дизайн-система, геймпад
- **Одна проектная `Theme` (`.tres`) — источник шрифтов, цветов, StyleBox**; переопределения на отдельных узлах не плодить. Тему сохранять отдельным файлом, а не встроенной в сцену. — https://docs.godotengine.org/en/4.4/tutorials/ui/gui_using_theme_editor.html
- **Варианты — через Theme Type Variation** (`theme_type_variation = "DangerButton"` с базой `Button`): «токены» дизайн-системы, наследуются, можно цепочкой. — https://docs.godotengine.org/en/4.4/tutorials/ui/gui_theme_type_variations.html
- Подключение проектной темы через настройку `gui/theme/custom` — догадка по имени (на странице не подтвердил).
- **Навигация с геймпада:** в `_ready()` каждого экрана `grab_focus()` на первую кнопку, иначе геймпад «ничего не делает»; соседей фокуса задавать явно, где авто-угадывание ошибается; у не-кнопок `focus_mode`. **`ui_*` действия не использовать в игровом коде.** — https://docs.godotengine.org/en/4.4/tutorials/ui/gui_navigation.html

## 10. Steam Deck (для бейджа Verified)
- **Полное управление с геймпада по умолчанию**, без смены настроек в игре. — https://partner.steamgames.com/doc/steamdeck/compat
- **Подсказки-кнопки должны соответствовать активному вводу** (не показывать клавиши мыши/клавиатуры при геймпаде). — там же.
- **Ввод текста — Steamworks API или свой ввод, работающий только геймпадом.** — там же.
- **Самый мелкий символ не меньше 9 px по высоте при 1280×800, цель — 12 px.** — там же.
- **Разрешение, поддерживаемое Deck; рекомендовано родное 1280×800 (16:10).** — там же (16:10 — вывод из 1280×800).
- **Не показывать «устройство не поддерживается»; лаунчер не запрещён, но должен соответствовать требованиям, сильно не рекомендуется.** — там же.
- **30 FPS при 800p в настройках по умолчанию.** — там же.
- **Через Proton (Windows-сборка) — без блокирующих багов Proton.** Нативная Linux-сборка Godot — тоже вариант; выбор — догадка, проверить на устройстве. — там же.

## 11. Тесты и линтинг GDScript
- **GUT 9.4.0 — для Godot 4.3–4.4** (9.5.0 — уже 4.5). Двойники, параметризованные тесты, CLI, JUnit XML. — https://github.com/bitwes/Gut
- **gdUnit4 v5.x — для Godot 4.4/4.4.1** (v6 — уже не 4.4). Scene runner (имитация ввода, ожидание сигналов), моки/шпионы, CLI и GitHub Action, MIT. — https://github.com/godot-gdunit-labs/gdUnit4
- Под задачу TDD «формулы урона/опыта» хватит любого; для ровно 4.4.1 версию фиксировать (GUT 9.4.0 или gdUnit4 5.x). Выбор между ними — догадка/на решение.
- **gdtoolkit 4.x:** `pip install "gdtoolkit==4.*"` → `gdlint`, `gdformat`, `gdradon cc` (сложность). Поддержку свежего синтаксиса 4.4 (типизированные словари) проверить на своём коде перед включением в CI — не подтвердил. — https://github.com/Scony/godot-gdscript-toolkit
- **Дешёвый «линтер» без новых зависимостей:** `godot --headless --check-only --script <файл>` — догадка (флаг существует в CLI Godot, в этой сессии не проверял); вместе с предупреждениями-ошибками из раздела 2 даёт проверку типов в smoke.

## 12. Репозиторий
- **`.gitignore`: `.godot/` и `*.translation`** (для 4.1+). — https://docs.godotengine.org/en/4.4/tutorials/best_practices/version_control_systems.html
- **`.gitattributes` с LF** (Project → Version Control → Generate Version Control Metadata). На Windows при этом не нужен `core.autocrlf`; без метаданных — `core.autocrlf input`. — там же.
- **Коммитить `.uid`, `.import`, `.tscn/.tres`, `project.godot`, `export_presets.cfg`** (без секретов) — `.uid` подтверждён (раздел 0); остальное — догадка/общепринятое (`.import` хранит настройки импорта).
- **Бинарники (GLB, PNG, WAV, OGG) — через Git LFS или вне репозитория** (у проекта — вне, в файлах проекта). Docs Godot про LFS молчат — догадка/общепринятое.
- **`export_credentials.cfg` в Git не класть** — догадка (в 4.x пароли экспорта вынесены в `.godot/export_credentials.cfg`, который и так в `.godot/`).
- **Маленькие коммиты; Conventional Commits** (`feat:`, `fix:`, `docs:`) — https://www.conventionalcommits.org/ (для проекта — по желанию, сейчас правило: на русском, что и зачем).

## 13. Python-инструменты
- **PEP 8** (стиль) — https://peps.python.org/pep-0008/ ; **аннотации типов PEP 484** — https://peps.python.org/pep-0484/ (проверка — mypy/pyright, по желанию).
- **ruff — линтер+форматтер вместо flake8/black/isort:** `ruff check --fix`, `ruff format` (`--check` в CI), настройка `[tool.ruff]` в `pyproject.toml`, длина строки 88 по умолчанию, `target-version` из `requires-python`. — https://docs.astral.sh/ruff/ , https://docs.astral.sh/ruff/configuration/
- **`pathlib.Path` вместо строк путей, `argparse` для CLI, `if __name__ == "__main__":`, код выхода ≠ 0 при ошибке** — догадка/общепринятое (стандартная библиотека: https://docs.python.org/3/library/pathlib.html , https://docs.python.org/3/library/argparse.html ).
- **Файлы читать/писать с `encoding="utf-8"`** — у проекта русские тексты, на Windows кодировка по умолчанию другая. — догадка/общепринятое (PEP 686 делает UTF-8 по умолчанию только с Python 3.15).

## 14. Blender (bpy) в облаке
- **Запуск без UI:** `blender --background --factory-startup --python-exit-code 1 --python script.py -- <аргументы>`. `-b` без интерфейса; `--factory-startup` не берёт пользовательский startup.blend (воспроизводимо); `--python-exit-code` — ненулевой код при исключении (иначе CI «зелёный» при падении); после `--` аргументы идут в `sys.argv` скрипта. **Аргументы выполняются по порядку** — `.blend` ставить до `--python`. — https://docs.blender.org/manual/en/latest/advanced/command_line/arguments.html
- **Предпочитать data API (`bpy.data`, `mesh.from_pydata`, `bmesh`) операторам `bpy.ops`:** операторы работают от контекста, в фоне часто падают на `poll()` без понятной причины. Если оператор неизбежен — `bpy.context.temp_override(...)`. — https://docs.blender.org/api/current/info_gotchas_operators.html
- **Потоки Python в Blender не поддерживаются.** — https://docs.blender.org/api/current/info_gotcha.html
- **Не хранить ссылки на объекты bpy между undo/добавлениями данных, а имена могут получить суффикс `.001`** — проверять фактическое имя после создания. — догадка (раздел «Internal Data & Their Python Objects» на той же странице, текст не прочитал).

## 15. Bash CI
- **`set -euo pipefail`, `shellcheck` на скрипты, кавычки вокруг переменных** — догадка/общепринятое (https://www.shellcheck.net/ ).
- **Godot в CI — `--headless`, падение на первой `SCRIPT ERROR`** — уже так в `tools/ci/smoke.sh`; дополнить проверкой предупреждений-ошибок (раздел 2) — рекомендация.
