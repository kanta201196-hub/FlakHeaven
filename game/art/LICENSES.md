# Лицензии внешних ассетов

Все наборы ниже — **CC0** (общественное достояние): можно в коммерческой игре, указание авторства не требуется. Авторы перечислены из уважения.
Решение об источнике — журнал решений `docs/game-context.md`, 15.10.2026.

## Текстуры земли (`game/art/ground/pbr/`), Poly Haven — https://polyhaven.com/license

Подготовка: `game/tools/terrain/prep_ground.py` (цвет 2K; нормаль OpenGL в R,G + высота в B).

| Файлы | Набор | Авторы | Страница |
| --- | --- | --- | --- |
| `pbr/sand_*` | Gravelly Sand (`gravelly_sand`) | Dario Barresi | https://polyhaven.com/a/gravelly_sand |
| `pbr/clay_*` | Mud Cracked Dry Riverbed 002 (`mud_cracked_dry_riverbed_002`) | Dario Barresi, Dimitrios Savva | https://polyhaven.com/a/mud_cracked_dry_riverbed_002 |
| `pbr/gravel_*` | Dry Ground Rocks (`dry_ground_rocks`) | Rob Tuytel | https://polyhaven.com/a/dry_ground_rocks |
| `pbr/river_*` | River Small Rocks (`river_small_rocks`) | Rob Tuytel, Rico Cilliers | https://polyhaven.com/a/river_small_rocks |
| `pbr/rock_*` | Cliff Side (`cliff_side`) | James Ray Cock, Jenelle van Heerden, Dario Barresi | https://polyhaven.com/a/cliff_side |

## Текстуры крепости «Укрепрайон» (`game/art/fort/`), Poly Haven — https://polyhaven.com/license

Набор Г «Штукатурка с камнем» (выбор Kanta 25.10.2026). 1K jpg без изменений: цвет (`_color`), нормаль OpenGL (`_normal`), AO/шероховатость/металл (`_arm`). Модель — `game/scripts/fort_build.gd`.

| Файлы | Набор | Авторы | Страница |
| --- | --- | --- | --- |
| `fort/plaster_*` | Plaster Stone Wall 01 (`plaster_stone_wall_01`) | Charlotte Baglioni | https://polyhaven.com/a/plaster_stone_wall_01 |
| `fort/stone_*` | Old Stone Wall (`old_stone_wall`) | Charlotte Baglioni | https://polyhaven.com/a/old_stone_wall |
| `fort/brick_*` | Brown Brick 02 (`brown_brick_02`) | Rob Tuytel | https://polyhaven.com/a/brown_brick_02 |
| `fort/conc_*` | Concrete Wall 008 (`concrete_wall_008`) | Dario Barresi, Charlotte Baglioni | https://polyhaven.com/a/concrete_wall_008 |
| `fort/wood_*` | Old Planks 02 (`old_planks_02`) | Rob Tuytel | https://polyhaven.com/a/old_planks_02 |

## Портреты экипажа (`portraits/*.png`)
Сгенерированы владельцем проекта в ChatGPT по промптам из `/mnt/project-files/progression/portraits_chatgpt_prompts.md` (2026-10-16). Уменьшены до 256×384. Оригиналы (1024×1536; «Оса» v2 — 1448×1086, обрезка по центру 2:3) хранятся в общей папке проекта (`progression/portraits/`).

## Эффекты боя (`game/art/vfx/`), JangaFX free VDB animations — CC0

Объёмные симуляции JangaFX (сделаны в EmberGen), лицензия CC0 (текст в архиве набора: «You are free to use these VDBs in any project however you please, both commercially and non-commercially»). Раскадровки отрендерены нами в Blender с камерой и солнцем игры: `game/tools/vfx_bake/render_vdb.py` → `pack_atlas.py` (VFX-02, 2026-10-24).

| Файлы | Набор | Автор | Страница |
| --- | --- | --- | --- |
| `vfx/blast_ground.png` | Ground Explosion | JangaFX | https://jangafx.com/software/embergen/download/free-vdb-animations |
| `vfx/blast_air.png` | Mid-Air Explosion (Midair_Explosion_01, every 2nd frame) | JangaFX | https://jangafx.com/software/embergen/download/free-vdb-animations |
| `vfx/blast_flak.png` | Mid-Air Explosion (same frames, black-grey smoke and a dull flame, VFX-02 flak burst) | JangaFX | https://jangafx.com/software/embergen/download/free-vdb-animations |

## Копоть от взрывов (`game/art/vfx/scorch.png`), Poly Haven — CC0

Цвет и мелкая фактура — фото выжженной земли; маска (тёмная середина, рваный край, лучи сажи) построена скриптом `game/tools/vfx_bake/make_scorch.py` (VFX-06, 2026-10-24).

| Файл | Набор | Автор | Страница |
| --- | --- | --- | --- |
| `vfx/scorch.png` | Burned Ground 01 (`burned_ground_01`, diffuse 1K) | Rob Tuytel | https://polyhaven.com/a/burned_ground_01 |

## Значки кнопок геймпада (`game/art/glyphs/`), Kenney Input Prompts 1.5 — CC0

Белые значки 64×64 из папок `Default` наборов Xbox Series, PlayStation Series и Steam Deck, переименованы в общие имена (`a`, `b`, `lb`, `rt`, `dup`, `l_left`…), чтобы одна таблица кнопок работала для всех трёх наборов. Решение — Kanta, 24.10.2026 (тред «Переделать главное меню и настройки», UI-01 шаг 4).

| Папка | Набор | Автор | Страница |
| --- | --- | --- | --- |
| `glyphs/xbox/` | Input Prompts — Xbox Series | Kenney | https://kenney.nl/assets/input-prompts |
| `glyphs/ps/` | Input Prompts — PlayStation Series | Kenney | https://kenney.nl/assets/input-prompts |
| `glyphs/deck/` | Input Prompts — Steam Deck | Kenney | https://kenney.nl/assets/input-prompts |
