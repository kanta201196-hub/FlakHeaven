# Flak Heaven UI design system

Version 1, 2026-10-23. Produced with the `design:design-system` skill (audit + target) from the [UI review](../review/code-2026-10-23/r4-ui.md), which holds the full inventory with line references. Token values are taken from **what the game already uses most**: the look does not change, it is only gathered in one place. Items marked **[Kanta to decide]** need his choice.

How the UI is built technically (drawn in code, not Control nodes) — [architecture.md, ADR-05](architecture.md). Coding rules — [code.md §12](code.md).

## 1. Audit (2026-10-23)

**Reviewed:** 10 UI files (~3800 lines), every screen: combat HUD, cards, pause, results, hangar, sortie setup, codex, menu, settings. **Score:** 45/100 — the look is coherent "by eye", but it rests on manual precision rather than a system.

### Token coverage

| Category | Defined | Literals in code |
| --- | --- | --- |
| Colors | 8 constants in `Menu`, 4 in `HudCampaign`, 4 in `HudFlight` — three places; none in `HudKit` | 426 `Color(...)`, 214 distinct |
| Font sizes | no scale | 11–54; 14/15/16/17 used for the same role |
| Spacing | no scale | screen margins 16–120, row steps 22–118, gaps 6–36 |
| Panel corner cut | 3 values (14, 18, 22) | — |
| States | hover differs per screen; no pressed or focus | — |

### Same role, different values (main issues)

| Role | Today | Variants |
| --- | --- | --- |
| Accent / heading (amber) | `(0.95, 0.66, 0.2)` — 69 uses; `(1.0, 0.82, 0.29)` — 11; 6 more close shades | 8 |
| Dark text on amber | `(0.08, 0.07, 0.05)`, `(0.06, 0.08, 0.06)`, `(0.1, 0.08, 0.02)` | 3 |
| HUD text backdrop | `(0.02, 0.025, 0.03, 0.55…0.86)` and others | 12 |
| Primary text | cool `(0.92, 0.95, 1.0)` in combat, warm `(0.92, 0.9, 0.84)` in menu | 3 |
| Done / success | `(0.6, 1.0, 0.7)`, `(0.5, 1.0, 0.6)` and 4 more | 6 |
| Tabs | settings, hangar, results, codex — 4 different styles | 4 |
| Buttons | three sets: `HudKit`, `Menu`, ad hoc | 3 |

### Main defects (from the review)
1. Clicking "Pin"/"Ban" on a card picks the card (CR-01) — no "topmost gets the click" rule.
2. No focus and no gamepad navigation (CR-05) — Steam Deck blocker.
3. ~25 places with font size 11–13 — under 9 px on the Deck.
4. Settings do not fit at 1920×1080 — no height-aware layout.
5. Hardcoded key labels — they ignore rebinding and gamepad.

### Priorities
1. Click rule and input delay on screens opened over combat (small, now).
2. `UiStyle` tokens + minimum font size 14.
3. Gamepad focus model on the cards, results and main menu screens (before the demo).
4. Merge primitives into one set; tabs become one component.

## 2. Tokens

They live in one file `game/scripts/ui_style.gd` (`class_name UiStyle`, constants only). `Menu.C_*`, `HudCampaign.C_*` and literals are gradually replaced by references to it.

### 2.1. Color

| Token | Value | Role |
| --- | --- | --- |
| `ACCENT` | `(0.95, 0.66, 0.2)` **[Kanta to decide: which amber is primary]** | Primary button, selected tab, hover border |
| `ACCENT_SOFT` | `(1.0, 0.82, 0.29)` | Screen and section headings on dark |
| `ACCENT_DIM` | `(0.55, 0.36, 0.1)` | Inactive accent, selected background |
| `ON_ACCENT` | `(0.08, 0.07, 0.05)` | Text on amber fill |
| `TEXT` | `(0.92, 0.95, 1.0)` | Primary text in combat and screens |
| `TEXT_WARM` | `(0.92, 0.9, 0.84)` | Primary text in the main menu (warm title theme) |
| `TEXT_2` | `(0.75, 0.8, 0.9)` | Secondary text, captions |
| `TEXT_OFF` | `(0.6, 0.62, 0.68)` | Disabled, locked |
| `OK` | `(0.6, 1.0, 0.7)` | Done, bought, ✓ |
| `DANGER` | `(1.0, 0.35, 0.3)` | HP, threat, boss |
| `BRAND_RED` | `(0.85, 0.24, 0.18)` | Menu button stripe, brand red |
| `PARTS` | `(0.95, 0.85, 0.55)` | Parts (currency) |
| `PANEL` | `(0.085, 0.095, 0.085, 0.95)` | Panel fill |
| `BACKDROP` | `(0.02, 0.025, 0.03, a)` — function `backdrop(a)` | Plate under HUD text on bright ground |
| `SCRIM` | `(0.02, 0.03, 0.025, 0.88)` | Screen dim under a dialog |
| `OUTLINE` | `(0.02, 0.025, 0.03, 0.85)` | HUD text outline |

Gameplay colors (card rarity `Cards.RARITY`, tags `Prog.TAGS`, classes `PlaneClasses`, activities `HudFlight.C_*`) stay in their data — they carry meaning, not style. Rule: one meaning — one color on every screen (already true for activities and rarity).

### 2.2. Type

Typeface follows the player's setting (`Settings.font`: PT Sans, Inter, Exo 2, system) + Noto Sans SC fallback for Chinese. Bold for headings and buttons **on every screen**, not only the menu.

| Token | Size | Role |
| --- | --- | --- |
| `FS_MIN` | 14 | Floor for any text (Deck: 14 × 0.667 ≈ 9.3 px) |
| `FS_CAPTION` | 14 | Small captions, "requires: …", chips |
| `FS_BODY` | 16 | Descriptions, bottom-of-screen hints |
| `FS_LABEL` | 18 | List rows, values, regular buttons |
| `FS_H3` | 22 | Block heading, large button |
| `FS_H2` | 28 | Section heading |
| `FS_H1` | 40 | Screen title (HANGAR, PAUSE, LEVEL UP, SORTIE, CODEX, results) |
| `FS_HERO` | 54 | Special screens (end of demo) |

`HudKit._text`/`_para` and `Menu._txt` clamp the size to `FS_MIN` themselves. A "UI scale" setting (font multiplier 0.9–1.3) — after the demo.

### 2.3. Spacing and shape

| Token | Value |
| --- | --- |
| Spacing scale `SP_*` | 4, 8, 12, 16, 24, 32, 48, 64 |
| Screen margin `MARGIN` | 64 (combat — 20, minimap — 16) |
| Panel padding `PAD` | 16 (large panel — 24) |
| List row step | 28 (dense — 24, settings row — 50) |
| Corner cut `CUT` | 14 (small buttons — 12) |
| Border | 1.5 px normal, 2.5 px hover/focus |

## 3. Components

One primitive set in `HudKit` (the menu moves onto it too). Every component registers its click rect and can take focus.

| Component | Variants | States | Today |
| --- | --- | --- | --- |
| `button` | primary (amber fill), secondary (panel + border), danger (red stripe), small | default, hover, focus, pressed, disabled | `_button`, `_menu_button`, `_small_button`, ad hoc |
| `panel` | plain, accented, riveted (menu) | default, hover | `HudKit._panel`, `Menu._panel` |
| `tabs` | — | default, selected, hover, focus | 4 styles → one `_tabs(rects, labels, current, prefix)` |
| `card_frame` | level-up card, hangar tier | default, hover (lift 6 px), focus, locked | two near copies → one component |
| `chip` | condition, tag, reward | default, done | `_cond_chips`, `_card_chips` |
| `check`, `option «‹ value ›»`, `slider` | — | default, hover, focus, disabled | menu only → shared |
| `text`, `para` | outlined (HUD) / plain (menu) | — | `HudKit._text/_para`, `Menu._txt` |

### States (identical everywhere)

| State | Look | Behavior |
| --- | --- | --- |
| default | `PANEL` fill, `ACCENT` border at 40 % | — |
| hover / focus | `ACCENT` border at 100 %, 2.5 px; primary gets a lighter fill | focus = hover for gamepad |
| pressed | `ACCENT_DIM` fill for 0.1 s | fires on release |
| disabled | `TEXT_OFF` text, no border; the reason as a caption next to it | not registered for click or focus |
| selected | `ACCENT` fill, `ON_ACCENT` text | — |

## 4. Patterns

1. **Click:** the button list is searched from the end — what is drawn last (on top) gets the click. The click rect does not include the hover lift.
2. **Focus and gamepad:** every screen has a default focus; `ui_up/down/left/right` move focus to the nearest button in that direction, `ui_accept` = click, `ui_cancel` = back. A screen opened over combat (level up, specialization) ignores input for the first 0.3 s. Gamepad buttons for reroll and ban are separate from combat buttons.
3. **Key labels:** `HudKit.key_label(action)` — by the last input device (keyboard or gamepad) and respecting rebinding.
4. **Exit from every screen:** every state has a way back (Esc/B); an empty screen without a "Continue" button is not allowed.
5. **Height-aware layout:** vertical lists compute available height and wrap into a second column or scroll. Check with `--shots` screenshots at 1920×1080 and 1920×1200 (Deck).
6. **Text on bright ground:** in combat — `OUTLINE` or a `BACKDROP` plate; no yellow or amber for important text on sand (already done for activities).
7. **Numbers in text** come from rule constants, never typed into strings.

## 5. Do / don't

| ✅ Do | ❌ Don't |
| --- | --- |
| `UiStyle.ACCENT`, `UiStyle.FS_LABEL` | `Color(1.0, 0.85, 0.4)` "by eye" |
| Build a new screen from `button`, `panel`, `tabs` | A new button style for one screen |
| Check the screen with a gamepad and at 1920×1200 | Assume "works with the mouse — done" |
| `Loc.t("+%d запчастей") % n` | `"+40 запчастей"` as a literal |
| Font size ≥ 14 | Size 11–13 "for a caption" |

## 6. Migration (no big-bang rewrite)

1. CS-11a (small): click rule from the end of the list, input delay on `levelup`/`course_pick`, `FS_MIN` in the primitives.
2. CS-11b: `ui_style.gd` with tokens; `Menu.C_*` and `HudCampaign.C_*` become references to it; literals are replaced when a screen is touched.
3. CS-11c: focus model in `HudKit`/`Menu`, starting with cards, results and main menu.
4. CS-11d: shared `tabs` and `card_frame`, menu on `HudKit` primitives.
5. After Next Fest: "UI scale", revisit ADR-05 (Control + Theme for menu and hangar).
