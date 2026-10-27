// Flush flare-dispenser panel on a plane's skin (S13, Kanta 27.10: countermeasures are built into the airframe, not
// boxes on top). The mesh (SkinPatch.panel) follows the skin; this shader draws the dispenser on it: a recessed
// block of cartridge cells, rows x columns, each a square cell with a round cartridge cap and a dark firing port,
// inside a raised frame with fastener dots. Weathered and matte: soot from the cartridges, darkest behind the
// cells (UV.x = 0 is the aft end), worn paint on the frame edges, dust in the cell corners, uneven roughness.
// UV: x along the panel from aft (0) to front (1), y across it.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/srgb.gdshaderinc"

uniform vec4 frame_col : source_color = vec4(0.30, 0.31, 0.28, 1.0);
uniform vec4 cell_col : source_color = vec4(0.17, 0.17, 0.16, 1.0);
uniform vec4 cap_col : source_color = vec4(0.36, 0.33, 0.27, 1.0);
uniform int cols = 6;
uniform int rows = 2;
uniform float seed = 0.0;
uniform float aspect = 2.6;   // panel length / width, keeps the cells square

float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 17.3) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 uv = UV;
	vec2 q = vec2(uv.x * aspect, uv.y);   // square units across the panel
	float fine = vnoise(q * 40.0) * 0.6 + vnoise(q * 110.0) * 0.4;
	float big = vnoise(q * 6.0);
	// frame: a band around the edge; the cell block sits inside it
	float m = 0.12;
	vec2 d = min(uv, 1.0 - uv) * vec2(aspect, 1.0);
	float edge = min(d.x, d.y);
	float inner = smoothstep(m * 0.85, m, edge);
	vec3 c = frame_col.rgb * mix(0.86, 1.06, big) * (0.94 + 0.12 * fine);
	float rough = 0.78 + 0.1 * fine;
	// worn paint on the frame's outer lip: lighter primer and bare metal flecks
	float wear = (1.0 - smoothstep(0.0, m * 0.35, edge)) * smoothstep(0.55, 0.8, vnoise(q * 55.0 + 3.0));
	c = mix(c, SRGB(vec3(0.55, 0.54, 0.5)), wear * 0.55);
	// fastener dots along the frame
	vec2 fp = vec2(uv.x * float(cols) * 1.5, uv.y);
	float fx = abs(fract(fp.x) - 0.5);
	float on_band = 1.0 - smoothstep(0.02, 0.05, abs(edge - m * 0.5));
	float dot_f = (1.0 - smoothstep(0.06, 0.12, fx)) * on_band;
	c = mix(c, c * 0.55, dot_f * 0.8);
	// cell block
	vec2 cb = (uv - vec2(m / aspect, m)) / (vec2(1.0) - 2.0 * vec2(m / aspect, m));
	vec2 g = cb * vec2(float(cols), float(rows));
	vec2 cell = fract(g) - 0.5;
	vec2 id = floor(g);
	float cw = 0.5 - 0.07;   // cell wall
	float in_cell = (1.0 - smoothstep(cw - 0.03, cw, max(abs(cell.x), abs(cell.y)))) * inner;
	float r = length(cell);
	float spent = step(0.72, hash2(id + 4.0));   // some cartridges fired: open dark ports
	float cap = 1.0 - smoothstep(0.30, 0.34, r);
	float port = 1.0 - smoothstep(0.12, 0.16, r);
	vec3 cellc = cell_col.rgb * (0.9 + 0.2 * fine);
	vec3 capc = cap_col.rgb * mix(0.85, 1.1, hash2(id)) * (0.92 + 0.16 * fine);
	capc = mix(capc, SRGB(vec3(0.05, 0.045, 0.04)), spent);
	vec3 cc = mix(cellc, capc, cap);
	cc = mix(cc, SRGB(vec3(0.02, 0.02, 0.02)), port * (0.6 + 0.4 * spent));
	// dust in the cell corners
	float corner = smoothstep(0.3, 0.45, max(abs(cell.x), abs(cell.y)));
	cc = mix(cc, SRGB(vec3(0.42, 0.37, 0.3)), corner * 0.25 * (0.5 + fine));
	c = mix(c, cc, in_cell);
	// soot: the burning cartridges blacken the panel, most at its aft end and in streaks along the flow
	float streak = vnoise(vec2(uv.y * 14.0, uv.x * 2.0));
	float soot = (1.0 - smoothstep(0.0, 0.85, uv.x)) * (0.35 + 0.65 * streak) * 0.55;
	c *= 1.0 - soot;
	rough = mix(rough, 0.9, in_cell * 0.6) + soot * 0.08;
	ALBEDO = clamp(c, vec3(0.0), vec3(1.0));
	ROUGHNESS = clamp(rough, 0.0, 1.0);
	METALLIC = 0.12 * (1.0 - in_cell) + wear * 0.3;
	SPECULAR = 0.3;
}
