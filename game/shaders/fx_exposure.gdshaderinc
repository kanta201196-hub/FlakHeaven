// Exposure take-back for unshaded effect shaders (Boom3D, GpuFx), 25.10.2026.
// Forward+ raises tonemap exposure by Render3D.FP_EXPOSURE_K (1.5) to lift the SRGB-corrected terrain. Effects
// were tuned and approved in Forward+ before that, and unshaded fire, flashes and smoke then clipped to
// white, so FX_EXP divides the factor back out. Keep the number equal to 1 / FP_EXPOSURE_K.
// Compatibility has no extra exposure and draws effects unchanged.
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
#define FX_EXP 1.0
#else
#define FX_EXP (1.0 / 1.5)
#endif

// Player clear zone, Kanta s12 (26.10): late in a run blasts, fire, missile smoke and the fan of a missile salvo
// covered the player's plane completely. Render3D sets fx_clear each frame: xy = the player on screen (0..1),
// z = zone radius as a share of the viewport height, w = how much of the effect is taken away at the centre
// (0 = off). Effect alpha multiplied by fx_clear_k() thins out over the plane and is full again at the zone edge.
global uniform vec4 fx_clear;
float fx_clear_k(vec2 suv, vec2 vsize) {
	if (fx_clear.w <= 0.0) {
		return 1.0;
	}
	vec2 d = (suv - fx_clear.xy) * vec2(vsize.x / max(vsize.y, 1.0), 1.0);
	return 1.0 - fx_clear.w * (1.0 - smoothstep(fx_clear.z * 0.45, fx_clear.z, length(d)));
}
