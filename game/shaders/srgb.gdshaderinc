// Colour constants written for the look tuned in GL Compatibility (Forward+ switch, 24.10.2026).
// Godot 4.4.1 Compatibility does no colour conversion: plain constants, uniforms without
// `source_color` and vertex colours show as written. Forward+ treats them as linear and they come out
// lighter (0.5 shows as 0.73). SRGB(c) keeps Compatibility unchanged and converts in Forward+, so
// both renderers draw the same colour. `source_color` uniforms and textures already match.
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
#define SRGB(c) (c)
#else
vec3 srgb_to_lin(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}
#define SRGB(c) srgb_to_lin(c)
#endif
