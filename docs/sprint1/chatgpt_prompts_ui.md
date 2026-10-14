# Промпты для ChatGPT — интерфейс Flak Heaven

К плану `sprint1/s2-ui-visual-plan.md`. Стиль интерфейса: «приборная доска / лётный планшет» — графит, янтарь `#F2A833`, красные метки `#D93D2E` только для опасности, трафарет, срезанные углы.

## Как работать
1. **Отдельный чат «UI»** (не тот, где самолёты: там ChatGPT тянет реалистичный рендер, а иконкам нужна плоская графика).
2. По **одному промпту за сообщение**. Скачайте PNG в `art\inbox\ui\` под именем из скобок.
3. ChatGPT отдаёт 1024×1024 (или 1536×1024 для широких) — это нормально, до нужного размера уменьшит студия спрайтов.
4. Если фон получился не прозрачным — допишите: «Make the background fully transparent (alpha), no white or checkerboard». Не вышло со второй попытки — оставьте чисто чёрный фон, студия вырежет.
5. **Иконки:** сначала попробуйте **лист № 0** (все 12 на одной картинке — стиль совпадёт гарантированно). Если какая-то иконка на листе вышла плохо — переделайте её отдельным промптом № 1–12, **прикрепив готовый лист** как образец.
6. Портреты: после первого удачного прикрепляйте его к следующим — так совпадут манера и палитра.
7. Если ChatGPT вставил надписи, цифры, звёзды, флаги, эмблемы — попросите: «Remove all text, numbers, stars, flags and emblems».

**Запрет во всём наборе:** реальные бренды и логотипы, флаги, звёзды и круги-опознавательные знаки, бортовые номера, надписи (кроме логотипа № 17), реальные лица и узнаваемые люди.

---

## А. Иконки оружия, модулей и навыков — 12 шт.

Хвост иконок (уже вставлен в каждый промпт):
`Flat monochrome game UI icon in a single solid amber color (#F2A833) on a fully transparent background. Bold, clean, slightly stencil-like silhouette with a few thin cut-out lines for internal detail, uniform line weight, no gradients, no shading, no outline in another color, no background shape, no frame, no text, no letters, no numbers. Centered with about 12% empty padding on each side. Square 1024×1024. Part of a consistent set of military aviation icons. No national insignia, no stars, no flags, no brand logos.`

### 0. Лист из 12 иконок (ui_icon_sheet.png) — рекомендую начать с него
A sheet of 12 game UI icons arranged in a strict 4×3 grid with equal cells and generous empty space between them, for a top-down military aviation roguelike. Row 1: an air-to-air missile; a pod of unguided rockets; a pair of aerial bombs; a gun pod under a wing. Row 2: flares bursting from a jet; a rotating gun turret with two barrels; a stack of armor plates; a jet engine with a glowing nozzle. Row 3: a wing with extended slats and flaps; a circular reload arrow around a missile; two small jets flying in formation; a wrench crossed with a jet silhouette. Every icon is a flat monochrome silhouette in a single solid amber color (#F2A833) on a fully transparent background, bold, clean, slightly stencil-like with thin cut-out lines for detail, uniform line weight across all twelve, no gradients, no shading, no text, no letters, no numbers, no frames, no grid lines. Wide image 1536×1024. No national insignia, no stars, no flags, no brand logos.

### 1. Ракеты «воздух–воздух» (i_aam.png)
A single air-to-air missile seen diagonally, pointing to the upper right: slim body, pointed seeker nose, small canards near the nose, four tail fins, a short motion streak behind it. + хвост

### 2. НАР — неуправляемые ракеты (i_rockets.png)
A cylindrical rocket pod seen from the front-side, with the open honeycomb of tube openings visible on its face and three small unguided rockets flying out of it toward the upper right. + хвост

### 3. Бомбы (i_bombs.png)
Two classic finned aerial bombs side by side, falling straight down, noses pointing to the bottom, with short vertical motion lines above them. + хвост

### 4. Пушечная гондола (i_gunpod.png)
A streamlined gun pod hanging from a short pylon, seen from the side, with a long gun barrel at the front and three short muzzle-flash lines at the tip. + хвост

### 5. Противоракеты / ловушки (i_flares.png)
A small delta-wing jet silhouette at the top seen from above, with six bright flares bursting out behind it in two curved fans like angel wings, each flare a small star-burst dot with a curved trail. + хвост

### 6. Турели (i_turret.png)
A round aircraft gun turret seen from directly above: circular base ring, a central dome, two parallel gun barrels pointing to the upper right, a dashed arc showing its rotation. + хвост

### 7. Бронеплиты (i_armor.png)
Three overlapping thick armor plates with bevelled edges and visible bolts in the corners, slightly fanned out like a stack of cards, a small chevron mark on the top plate. + хвост

### 8. Форсированный двигатель (i_engine.png)
A jet engine seen from the side and slightly behind: compressor intake on the left, cylindrical body, adjustable nozzle on the right with a short flame cone and three speed lines. + хвост

### 9. Механизация крыла (i_wing.png)
A swept aircraft wing seen from above with its leading-edge slats and trailing-edge flaps extended and slightly separated from the wing, small curved airflow arrows passing over it. + хвост

### 10. Быстрая перезарядка (i_reload.png)
A circular arrow forming almost a full ring, with a small missile placed inside the ring pointing upward, and two short speed ticks on the arrowhead. + хвост

### 11. Ведомый (i_wingman.png)
Two small identical jet silhouettes seen from directly above flying in echelon formation, the leader slightly ahead on the left, the wingman behind on the right, with a thin dashed line connecting them. + хвост

### 12. Ремонт в воздухе (i_repair.png)
A wrench diagonally crossed over a small jet silhouette seen from above, with a small plus sign shape made of two short bars near the wrench head (a shape, not a letter). + хвост

---

## Б. Портреты пилотов — 3 шт.

Манера: графический эскиз — тушь и сухая кисть по тонированной бумаге, штриховка, ограниченная палитра (графит, тёплый серый, **один янтарный акцент**). Добрый юмор, персонажи вымышленные. Как в Sublight по ощущению «нарисовано в блокноте», но свой материал: лётный планшет, полевая тетрадь, пустынная пыль.

Хвост портретов (уже вставлен):
`Graphic novel sketch style: confident ink lines and dry-brush hatching on warm toned paper, limited palette of graphite black, warm grays and a single amber (#F2A833) accent, visible pencil construction lines at the edges, subtle paper grain. Head-and-shoulders portrait, three-quarter view, character looking slightly off-camera, centered, plain toned paper background that fades to transparent at the edges. A completely fictional character, not resembling any real person or celebrity. Generic flight gear with no national insignia, no stars, no flags, no patches with text, no names, no numbers, no brand logos. Portrait 1024×1536.`

### 13. Пилот «Осы» — позывной «Искра» (p_iskra.png)
A young fighter pilot woman in her late twenties with a confident, slightly cocky grin and one raised eyebrow, short messy hair sticking out from under a pushed-back flight helmet, an oxygen mask hanging loose on one side, a small sticking plaster on her nose, a lollipop stick in the corner of her mouth. A plain flight jacket with a fur collar. The amber accent is the visor reflection on her helmet. + хвост

### 14. Пилот «Грача» — позывной «Батя» (p_batya.png)
A stocky middle-aged attack pilot with a big bushy mustache, kind tired eyes with deep laugh wrinkles and a calm, unimpressed half-smile, an old scuffed leather flight helmet with goggles on his forehead, a scarf around his neck, holding a steaming tin mug. A small desert lizard sits on his shoulder like a mascot. The amber accent is the steam glow and the goggle lenses. + хвост

### 15. Пилот «Кита» — позывной «Профессор» (p_professor.png)
A tall, thin, middle-aged bomber navigator with round wire glasses, a neat little beard and a thoughtful, slightly absent-minded expression, wearing a headset over a soft flight cap, a pencil tucked behind his ear and a folded paper map sticking out of his chest pocket, holding a thermos. The amber accent is the glint on his glasses. + хвост

---

## В. Фон ангара и логотип

### 16. Фон ангара (ui_hangar_bg.png)
Interior of a large military aircraft hangar at a remote desert airfield, seen from above at a steep isometric angle. Worn concrete floor with faded yellow parking lines and a large empty marked parking spot in the center of the image (keep the center completely empty — an aircraft will be placed there by the game). Around the edges: tool carts, a ladder, coiled fuel hoses, crates of spare parts, a missile on a loading trolley, a workbench with a lamp. Wide hangar doors open at the top of the image showing bright ochre desert and distant mountains, warm sunlight falling in a long shaft across the floor, fine dust in the air. Realistic, slightly painterly, muted colors: concrete gray, graphite, ochre, with warm amber lamp light. Keep the left third of the image darker and calmer (interface panels will be placed there). No aircraft, no people, no text, no numbers, no signs, no flags, no stars, no brand logos. Wide image 1536×1024.

Если ChatGPT всё же поставит самолёт в центр — допишите: «Remove the aircraft, the central parking spot must be empty floor».

### 17. Логотип «FLAK HEAVEN» (ui_logo.png)
A game title logo with the exact text "FLAK HEAVEN" in two words on one line, in a bold military stencil typeface with visible stencil bridges in the letters, slightly condensed. The letters are painted in warm off-white (#EBE6D6) with subtle worn, chipped paint and fine sand-blasted texture, as if spray-painted through a stencil on a metal panel. Underneath the text, a thin amber (#F2A833) horizontal bar styled like an aircraft instrument scale with small tick marks, and a single small red (#D93D2E) triangle marker on the scale. Clean flat front view, no perspective, no 3D extrusion. Fully transparent background, no panel behind the text. Only the words "FLAK HEAVEN", no other text, no slogans, no stars, no flags, no emblems. Wide image 1536×1024, logo centered, filling about 85% of the width.

Проверить: буквы именно F-L-A-K H-E-A-V-E-N, без лишних. Если перекосило — «Fix the spelling: exactly FLAK HEAVEN».

---

## Г. Рамка карточки уровня

**Рекомендация:** генерируем **одну серую рамку (№ 18)**, а цвет редкости задаёт код (`modulate`) — так 5 вариантов совпадут идеально, и цвета можно будет менять без новой генерации. Промпты № 19а–д — запасной путь, если окраска кодом будет выглядеть плоско.

Цвета редкостей (из стайл-гайда): Базовая `#A9AEB5`, Обычная `#7FBF5F`, Уникальная `#5AA6E0`, Исключительная `#B07AE8`, Легендарная `#FF8A1F`.

### 18. Рамка — серая база (ui_card_frame.png)
A vertical game card frame for an aviation roguelike, styled like a metal instrument panel: a thin bevelled metal border in neutral light gray, the top-right and bottom-left corners cut off at 45 degrees, small round rivets along the top edge, a narrow horizontal header strip at the top with fine instrument-scale tick marks, and a small empty square slot near the top center for an icon. The inside of the card is completely empty and fully transparent. Flat front view, no perspective. Neutral grayscale only, no color. No text, no numbers, no symbols, no stars, no flags. Fully transparent background. Portrait 1024×1536, frame filling about 90% of the image.

### 19а–д. Рамка — цветные варианты (ui_card_frame_r0.png … ui_card_frame_r4.png)
Прикрепите готовую № 18 и отправляйте по одному:

- **19а (ui_card_frame_r0.png), Базовая:** Recolor the attached card frame: keep the exact same shape, size and details, change the metal border to brushed steel gray (#A9AEB5) with one rivet highlighted. Inside and background stay fully transparent. No text.
- **19б (ui_card_frame_r1.png), Обычная:** Recolor the attached card frame: keep the exact same shape, size and details, change the border to muted olive green (#7FBF5F) painted metal, two rivets highlighted. Inside and background stay fully transparent. No text.
- **19в (ui_card_frame_r2.png), Уникальная:** Recolor the attached card frame: keep the exact same shape, size and details, change the border to instrument blue (#5AA6E0) anodized metal with a faint blue glow along the edge, three rivets highlighted. Inside and background stay fully transparent. No text.
- **19г (ui_card_frame_r3.png), Исключительная:** Recolor the attached card frame: keep the exact same shape, size and details, change the border to violet (#B07AE8) anodized metal with a soft violet glow along the edge, four rivets highlighted. Inside and background stay fully transparent. No text.
- **19д (ui_card_frame_r4.png), Легендарная:** Recolor the attached card frame: keep the exact same shape, size and details, change the border to hot orange (#FF8A1F) metal glowing as if heated, with a bright highlight sweeping along the top edge, all five rivets highlighted. Inside and background stay fully transparent. No text.

---

## Сводка файлов

| № | Файл | Размер исходника → в игре | Куда |
|---|---|---|---|
| 0 | `ui_icon_sheet.png` | 1536×1024 → нарезка 12 × 512 | карточки, HUD, ангар |
| 1–12 | `i_aam`, `i_rockets`, `i_bombs`, `i_gunpod`, `i_flares`, `i_turret`, `i_armor`, `i_engine`, `i_wing`, `i_reload`, `i_wingman`, `i_repair` `.png` | 1024 → 512 | то же |
| 13–15 | `p_iskra`, `p_batya`, `p_professor` `.png` | 1024×1536 → 512×768 | ангар (Пилот), выбор самолёта |
| 16 | `ui_hangar_bg.png` | 1536×1024 → 1920×1080 (под панелями) | ангар |
| 17 | `ui_logo.png` | 1536×1024 → обрезка по буквам | главное меню, капсула Steam (черновик) |
| 18 | `ui_card_frame.png` | 1024×1536 → 9-slice | карточки уровня |
| 19а–д | `ui_card_frame_r0…r4.png` | запасной | карточки уровня |

Итого: 1 лист (или 12 иконок) + 3 портрета + 1 фон + 1 логотип + 1 рамка = **7 генераций минимум**, ~1–1,5 ч с переделками.
