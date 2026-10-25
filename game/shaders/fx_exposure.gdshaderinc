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
