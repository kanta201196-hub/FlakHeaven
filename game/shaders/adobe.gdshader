shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;
// Village and oasis mesh (AdobeBuild): the StandardMaterial3D it replaces (clay photo in world-space triplanar,
// vertex colour as albedo, matte), plus own surfaces picked by the vertex colour's alpha (AdobeBuild.ID_*):
//   ~1.0  walls, roofs, yards — exactly the old material;
//   0.25  sandbags — hessian cloth with its weave in the normal (Kanta 26.10: "replace the sandbag textures if they are bad");
//   0.42…0.58 trench strip — packed soil, darker and lower in the middle, plank revetment along both edges;
//   0.67…0.83 street strip — packed earth or a photo lane set (--roadtex), frayed into the yard ground at the edges.
// For the strips the alpha also runs across the strip (edge to edge), so the shader knows where the middle is.
// Walls and heaps (alpha 1) are weathered mud plaster (weak-models list, item 1, 28.10): the ground photo's
// polygon cracks are toned down on the walls, with large soft tone patches, plaster fallen off in places showing
// mud-brick courses, hairline cracks, rain streaks, and a warm bounce lift on the walls (their shaded sides read
// near black from above). The foot and crest tones come from the vertex colours (AdobeBuild._wall_run).
// Sizes are in metres: `px_per_m` world px per metre.

uniform vec4 albedo : source_color = vec4(1.0, 0.95, 0.88, 1.0);
uniform sampler2D clay_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 uv_scale = vec3(0.00625);   // 1 / 160 world px, as the old uv1_scale
uniform float roughness = 0.95;
uniform float specular = 0.15;           // Kanta 19.10: clay and roofs fully matte
uniform float wear = 1.0;                // walls and heaps weathered (0 — the old plain clay)
uniform float px_per_m = 6.94;           // world px per metre (AdobeBuild.M_PER_UNIT)
uniform float px_scale = 1.0;            // world px per engine unit: 1 in the game; the model studio shows a scaled-down village

uniform bool bag_tex_on = true;
uniform sampler2D bag_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bag_nh : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float bag_tile = 9.0;            // world px per weave repeat
uniform vec3 bag_color : source_color = vec3(0.57, 0.48, 0.35);
uniform float bag_mean = 0.195;          // mean linear brightness of the hessian photo

uniform bool trench_tex = true;
uniform sampler2D soil_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_nh : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D plank_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float soil_tile = 40.0;
uniform float plank_tile = 14.0;

uniform bool lane_tex = false;
uniform sampler2D lane_tex_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D lane_nh : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float lane_tile = 24.0;
uniform vec3 lane_tint : source_color = vec3(1.0);
uniform float lane_sat = 0.75;

varying vec3 tri_pos;
varying vec3 tri_w;
varying vec3 wpos;
varying vec3 wnrm;
varying float mat_id;

void vertex() {
	vec3 n = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	mat_id = COLOR.a;
	if (!OUTPUT_IS_SRGB) {   // vertex_color_is_srgb
		COLOR.rgb = mix(pow((COLOR.rgb + vec3(0.055)) * (1.0 / (1.0 + 0.055)), vec3(2.4)), COLOR.rgb * (1.0 / 12.92), lessThan(COLOR.rgb, vec3(0.04045)));
	}
	tri_w = abs(n);
	tri_w /= dot(tri_w, vec3(1.0));
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz * px_scale;
	wnrm = n;
	tri_pos = wpos * uv_scale * vec3(1.0, -1.0, 1.0);
}

#include "res://shaders/adobe_wear.gdshaderinc"

vec4 triplanar(sampler2D s, vec3 w, vec3 p) {
	return texture(s, p.xy) * w.z + texture(s, p.xz) * w.y + texture(s, p.zy * vec2(-1.0, 1.0)) * w.x;
}

// world-space normal from a top-down (xz) tangent-space map: R → +x, G → −z (OpenGL green up = north)
vec3 top_normal(vec2 nrg, float k) {
	vec2 t = (nrg * 2.0 - 1.0) * k;
	return normalize(vec3(t.x, 1.0, -t.y));
}

void fragment() {
	vec4 base = triplanar(clay_tex, tri_w, tri_pos) * COLOR;
	vec3 alb = albedo.rgb * base.rgb;
	vec3 wn = FRONT_FACING ? wnrm : -wnrm;   // the side the camera sees, as the engine flips it
	bool own_n = false;
	float rough = roughness;
	if (mat_id < 0.33 && bag_tex_on) {
		// sandbags: hessian weave in three projections, the weave also in the normal
		vec3 bp = wpos / bag_tile;
		vec4 hx = texture(bag_tex, bp.zy);
		vec4 hy = texture(bag_tex, bp.xz);
		vec4 hz = texture(bag_tex, bp.xy);
		vec3 hc = (hx * tri_w.x + hy * tri_w.y + hz * tri_w.z).rgb;
		vec2 nx = texture(bag_nh, bp.zy).rg * 2.0 - 1.0;
		vec2 ny = texture(bag_nh, bp.xz).rg * 2.0 - 1.0;
		vec2 nz = texture(bag_nh, bp.xy).rg * 2.0 - 1.0;
		// whiteout-style blend: each projection tilts the normal in its own plane
		wn = normalize(wn + (vec3(0.0, nx.y, nx.x) * tri_w.x + vec3(ny.x, 0.0, ny.y) * tri_w.y + vec3(nz.x, nz.y, 0.0) * tri_w.z) * 0.35);
		own_n = true;
		// dusty khaki burlap; the weave only shades it (its mean brightness is bag_mean)
		float hl = dot(hc, vec3(0.333)) / bag_mean;
		alb = bag_color * mix(1.0, hl, 0.6);
		// the sides in shade read near black: lift them, warmer (sun-bounced sand, not sky). Rounded bags
		// (AdobeBuild._bag, 26.10) catch a little more light than the old flat-sided blocks, so the lift is a bit milder
		alb *= mix(vec3(1.8, 1.45, 1.08), vec3(1.0), tri_w.y);
		rough = 0.98;
	} else if (mat_id < 0.62 && trench_tex) {
		float across = clamp((mat_id - 0.5) / 0.08, -1.0, 1.0);   // −1 … 1 edge to edge
		vec2 sp = wpos.xz / soil_tile;
		vec3 sc = texture(soil_tex, sp).rgb;
		vec4 sn = texture(soil_nh, sp);
		// trench: deeper (darker) in the middle
		float depth = 1.0 - smoothstep(0.35, 1.0, abs(across));
		vec3 soil = mix(vec3(dot(sc, vec3(0.333))), sc, 0.75) * mix(0.62, 0.42, depth) * 1.6;
		// plank revetment: a band of boards along both walls, seen from above
		float wall = smoothstep(0.55, 0.75, abs(across)) * (1.0 - smoothstep(0.92, 1.0, abs(across)));
		vec3 pc = texture(plank_tex, wpos.xz / plank_tile).rgb;
		alb = mix(soil, pc * 0.85, wall * 0.85);
		wn = top_normal(sn.rg, 0.8 * (1.0 - wall));
		own_n = true;
		rough = 1.0;
	} else if (mat_id < 0.9 && lane_tex) {
		float across = clamp((mat_id - 0.75) / 0.08, -1.0, 1.0);
		vec2 lp = wpos.xz / lane_tile;
		vec3 lc = texture(lane_tex_a, lp).rgb;
		vec4 ln = texture(lane_nh, lp);
		vec3 lane = mix(vec3(dot(lc, vec3(0.333))), lc, lane_sat) * lane_tint;
		// edges fray into the plain packed earth by the set's height (stones stick out, dust in the hollows)
		float body = clamp((1.0 - abs(across)) * 2.2 + (ln.b - 0.5) * 1.2, 0.0, 1.0);
		alb = mix(alb, lane, body);
		wn = normalize(mix(wn, top_normal(ln.rg, 1.0), body));
		own_n = true;
		rough = mix(rough, 0.9, body);
	}
	if (mat_id > 0.9 && wear > 0.0) {
		vec3 cm = albedo.rgb * textureLod(clay_tex, tri_pos.xz, 12.0).rgb * COLOR.rgb;   // the photo's mean
		alb = mix(alb, adobe_wear(alb, cm, wpos / px_per_m, wn, rough, vec3(1.5, 1.38, 1.22)), wear);
	}
	ALBEDO = alb;
	if (own_n) {   // own surfaces only: walls and roofs keep the engine's normal, as before
		NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	}
	METALLIC = 0.0;
	SPECULAR = specular;
	ROUGHNESS = rough;
}
