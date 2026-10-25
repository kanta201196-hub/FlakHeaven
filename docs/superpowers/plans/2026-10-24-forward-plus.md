# Forward+ switch (VIS-01 renderer part)

Kanta's "yes": 24.10, thread «Перевести игру на Forward+» ("Да запускай тут"). Decision log 24.10 (VIS-01):
Forward+ becomes the main renderer and Compatibility stays as the low-quality fallback.

## Goal
The game starts in Forward+ on any PC that has Vulkan (or D3D12). The picture is at least as good as the
Compatibility one: the same light and colour, with no white smoke and no red-shifted ground. The graphics options
that were greyed out (SSAO, SSIL, glow, FXAA, TAA, FSR) start working, and the quality presets use them.

## Steps
1. **Baseline.** `--visual --op=1` frames (fixed seed, 6 camera points) at `--gfx=0/2/3` in Compatibility,
   and the same frames in Forward+ with nothing else changed (lavapipe in the cloud).
2. **Switch.** In `project.godot`: `renderer/rendering_method="forward_plus"`, and `.mobile` stays Compatibility.
   Godot's fallback to OpenGL 3 stays on, so PCs without Vulkan/D3D12 still start in Compatibility.
   `Settings.forward_plus()` already reads the active method.
3. **Colour pass.** Match the Compatibility look in Forward+ (tonemap, exposure, ambient, adjustment, glow).
   Fix whatever reads differently (Boom3D smoke, terrain tint) where the cause is the renderer. Shader fixes in
   Boom3D and GpuFx go through the effects thread, and terrain/model shaders through the 3D thread.
4. **Presets.** Use the Forward+ options in `GfxPresets.PRESETS`. Low keeps Compatibility-like cost, and high/max
   add SSAO, glow and TAA/MSAA. Unit tests updated (`gfx_presets_test.gd`).
5. **Checks.** Frames at 3 presets for both renderers side by side on a zoomable page, plus `unit`,
   `smoke all` and `full.sh`.
6. **FPS on Kanta's PC** for each preset (Remote Control, from the repository, no export), then tune the presets.

## Not in scope
GpuFx effect work (effects thread), new models and terrain shaders (3D thread), balance.

## Risks
- Shader compile stutter on first use in Forward+: watch the first-sortie logs.
- Weak PCs and the Steam Deck: Forward+ costs more. The low preset and the automatic drop (`gfx_auto`) must keep 60 fps.
  The Deck itself runs Vulkan.
