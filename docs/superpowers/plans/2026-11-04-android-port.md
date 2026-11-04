# Android port — feasibility and plan (draft)

Asked by Kanta 2026-11-04: an Android version sized for a phone of roughly iPhone 11 class
(2019–2021 mid-range: ~4 GB RAM, mobile GPU, GLES3/Vulkan 1.1). Status: **experiment on branch
`claude/project-thread-djefod`; nothing merged into the PC game.** Large work (new platform) —
waits for Kanta's "yes" before it touches `main`.

## What the draft branch has

| Piece | File | Notes |
| --- | --- | --- |
| Export preset «Android Draft» | `game/export_presets.cfg` (preset.5) | arm64 only, no Gradle build, debug-signed, landscape, immersive |
| Renderer on phones | `project.godot` `rendering_method.mobile="gl_compatibility"` (already on main) | Same fallback PCs without Vulkan get; Forward+ is desktop-only |
| Texture formats | `textures/vram_compression/import_etc2_astc=true` (already on main) | Godot imports ETC2/ASTC next to BC7, so no per-file change is needed |
| Mobile graphics mix | `game/scripts/mobile/mobile_mode.gd` | Preset «Низкое» + low shadows, 1024 atlas, 70 % render scale, no glow, auto-drop off |
| Touch controls | `game/scripts/mobile/touch_controls.gd` | Floating stick (left half) → `move_*`; buttons Бочка / Форсаж / Пауза; guns are auto |

On PC `MobileMode` removes itself on start (`OS.has_feature("mobile")` is false), so desktop
behaviour is unchanged. `--mobile` on PC shows the overlay for a mouse check.

## Draft results (2026-11-04)

- APK `FlakHeaven_android_draft_0.1.apk`, 372 MB, arm64, Android 5.0+ (SDK 21), GLES 3.0, debug-signed,
  `apksigner verify` passes. Project files: `builds/android-draft/`.
- Size history: full textures 2.8 GB → all ≤ 1024 px 1.4 GB → models ≤ 512 px, turrets ≤ 256 px,
  ETC2 instead of high-quality ASTC: 372 MB. Turret paint variants were ~70 % of texture bytes.
- Mobile copy with the same caps, Compatibility renderer, `--mobile`: smoke fighter ok, `--shots`
  run with 0 `SCRIPT ERROR` (cloud, llvmpipe). **Not yet run on a real phone.**
- Not done in the draft: launcher icon (Godot default), touch UI for hover tooltips, keyboard
  prompts in the HUD, `--perf` log export from the phone.

## Cloud build — what works

- Godot 4.4.1 + export templates, Android SDK (platform-tools, build-tools 34, platform 34) and a
  debug keystore install in the cloud container in ~3 min (GitHub and dl.google.com are reachable).
- Build: `tools/android/build_draft_apk.sh` (copy of `game/` with texture caps, ~30 min cold,
  ~2 min warm). Editor settings need `export/android/android_sdk_path` and a debug keystore.
- A debug-signed APK needs no Kanta PC. A Play Store release would need an upload keystore kept as
  an environment secret and an AAB (Gradle build) — out of scope for the draft.

## Known risks for the full port

1. **Memory.** The PC build is ~0.5 GB packed, combat VRAM 0.6–1.1 GB on the PC presets. A 4 GB
   phone gives a game ~1.5–2 GB. 169 textures (hangar, weapons/hq) stay lossless; on phones they
   should be ASTC too, and big model textures need a mobile size cap (e.g. 1024 px).
2. **CPU.** Big fights are CPU-bound on the PC (GDScript + 800+ draw calls, 1.4 M triangles at 60
   enemies). A phone CPU is ~3–4× slower: expect 20–30 fps in big fights without cuts (guess).
3. **Shaders.** Compatibility draws a simpler look (no SSAO, SSIL, volumetric effects).
4. **UI.** Hover-based tooltips, small text and keyboard prompts were made for PC; menus work by
   tap but need a pass for thumbs.
5. **APK size.** Expect hundreds of MB; Google Play needs AAB + asset packs above 200 MB.

## Proposed steps after Kanta's "yes"

1. Measure on a real phone: fps log (`--perf`), RAM, load time — the draft APK prints the same logs.
2. Mobile texture cap and ASTC for the lossless textures (import presets per platform).
3. Mobile preset in `GfxPresets` (move `MOBILE_OPTS` there, unit tests) and lighter prop/enemy caps.
4. Touch UI pass: button layout settings, card pick by tap, hangar without hover.
5. Release signing, AAB, Play Console (money and store decisions: Kanta).
