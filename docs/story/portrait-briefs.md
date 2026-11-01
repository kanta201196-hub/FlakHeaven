# Story portraits: «Купол», «Гром», «Ключ» — briefs (ST-08, story plan step 10)

Three new faces for the hangar dialogue scenes (`HudDialog`, right-hand portrait). Until the pictures exist the
scenes show a plate with a silhouette and the callsign (`DialogFlow.portrait_file` → `res://art/portraits/story_<id>.png`,
loaded when present). No generator credits are spent by the thread: Kanta makes the pictures the same way as the 15
crew portraits (`docs/progression/portraits_chatgpt_prompts.md`) or says «no», and the plates stay.

| File | Who | Where it appears |
| --- | --- | --- |
| `art/portraits/story_kupol.png` | «Купол», base controller | every hangar scene (H0–H4′), HX |
| `art/portraits/story_grom.png` | «Гром», the player's flight leader | H3′ (on crutches), H4, H4′ |
| `art/portraits/story_klyuch.png` | «Ключ», base mechanic | H4′ (and later hangar humour) |

Format as the crew: vertical 2:3, shoulders up, dark vignetted background, the same semi-realistic painted style
(style reference `portrait_style_ref.png` = «Сокол-2»). Cropped and fitted by the thread after delivery; the HUD draws
them at 230×345. Hard rules of the world apply: fictional people, no flags, emblems, letters or insignia.

## How to make them (for Kanta, Russian — the prompts go to ChatGPT as they are)

Открой **тот же чат**, где делались 15 портретов экипажа (или новый, с «Сообщением 1» из
`docs/progression/portraits_chatgpt_prompts.md` и картинкой-образцом). Отправь три промпта по одному, сохрани файлы под
именами из таблицы выше и пришли в тред сюжета. Правила те же: вымышленные люди, без флагов, эмблем, букв и нашивок.

1. `story_kupol.png` — **«Купол»**, диспетчер базы.
```
Портрет «Купола»: женщина лет 50, диспетчер базы горной авиации. Не лётчик: без шлема. Крупная гарнитура с микрофоном у губ, короткие седеющие тёмные волосы, зачёсанные назад, узкое спокойное лицо, тонкие губы, внимательные серые глаза, взгляд прямо в зрителя — ровный, без эмоций, как голос в наушниках. Тёплый вязаный свитер под расстёгнутой тёмно-оливковой курткой без знаков, на шее на шнурке простые очки. Фон темнее обычного, еле угадывается подсвеченный снизу край радиопульта. Настроение: сухое спокойствие и усталость человека, который всю ночь держал связь. Три четверти вправо.
```
2. `story_grom.png` — **«Гром»**, ведущий звена, только что вернулся из плена.
```
Портрет «Грома»: мужчина лет 38, ведущий звена, неделю назад сбит и только что вернулся. Без шлема: короткие тёмные волосы с пробивающейся сединой у висков, многодневная щетина, заживающая ссадина на скуле и небольшой пластырь над бровью, обветренное смуглое лицо, тёплые карие глаза с усталой полуулыбкой — рад, что дома. На плечах чужая слишком большая куртка поверх застиранной лётной рубашки, в кадре видна верхняя часть костыля у плеча. Голова чуть наклонена, смотрит на зрителя как на своего. Анфас, лёгкий поворот влево.
```
3. `story_klyuch.png` — **«Ключ»**, механик базы.
```
Портрет «Ключа»: мужчина лет 60, старший механик базы. Без шлема: лысеющая голова с седым венчиком волос, широкое загорелое лицо в морщинах, седые густые усы, маленькие хитрые прищуренные глаза, добродушная усмешка. Тёмно-синий рабочий комбинезон в масляных пятнах, поверх — потёртый кожаный фартук, на шее ветошь, за ухом карандаш, в руке большой разводной ключ, поднятый как указка. Фон — тёмный ангар с размытыми бликами на обшивке самолёта. Настроение: ворчливое тепло человека, который чинит всё, что летает. Три четверти влево.
```

If a picture comes out too similar to a crew member: «Сделай другое лицо и телосложение, сохрани стиль» in the same chat.

## After delivery (thread)
1. Crop to 2:3, 460×690, export PNG to `game/art/portraits/story_<id>.png`; `godot --headless --path game --import`.
2. `--dialog` test scene and `--storyshots` frames: the plate is replaced automatically; check H3′ (Grom) and H4′ (Klyuch).
3. Credits row in `CREDITS.md` as for the crew portraits.
