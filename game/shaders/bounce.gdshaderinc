// Warm bounce light from the sunlit ground onto the shaded walls of mud buildings (village, oasis, fort).
// The game's sun comes from the north-west (Render3D: it travels along (0.62, -0.85, 0.75)), so the camera,
// looking north, sees the south and east faces, the ones in shade. Lit only by the cool sky ambient they read
// near black from gameplay height, while on a real sunny day the bright sand throws warm light back up into them.
// This adds that light as emission on vertical faces turned away from the sun, so it brightens only the shade
// side and never the lit faces or the roofs (a fill, not a change of the global lighting).
// Declares two uniforms: `bounce` (strength, 0 = off: the shader's default) and `bounce_tint` (the sand's colour).
// bounce_fill(alb, n): alb — the surface's albedo (linear), n — its world normal (unit).

uniform float bounce = 0.0;
uniform vec3 bounce_tint : source_color = vec3(1.0, 0.9, 0.78);

// horizontal direction the sun's light travels (Render3D sun basis), normalised in xz
const vec2 BOUNCE_SUN_XZ = vec2(0.6370, 0.7708);

vec3 bounce_fill(vec3 alb, vec3 n) {
	float vert = 1.0 - smoothstep(0.5, 0.85, abs(n.y));
	vec2 h = n.xz;
	float hl = length(h);
	float away = hl > 0.001 ? smoothstep(-0.3, 0.55, dot(h / hl, BOUNCE_SUN_XZ)) : 0.0;
	return alb * bounce_tint * (bounce * vert * away);
}
