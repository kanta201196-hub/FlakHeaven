// Hit flash and elite tint over an enemy's 3D model on Forward+ (Render3D, material_overlay; S11-24, S11-29).
// The model's own lit colour is multiplied by `k` per channel, so the paint, its shading and its markings stay
// and only get lighter or warmer. A see-through fill (the Compatibility overlay) added a fixed colour instead:
// in Forward+'s linear HDR frame, raised in exposure, it flooded the enemies' dark paint (elite drones flat
// yellow, the Fortress under fire flat white). Values above 1 brighten: the frame buffer is floating point.
shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, cull_back, fog_disabled;

// Per-channel multiplier of the model's colour (linear).
uniform vec3 k = vec3(1.0);

void fragment() {
	ALBEDO = k;
}
