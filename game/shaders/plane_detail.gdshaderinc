// Hangar detail layer of the player planes (PlaneDetail, Livery.apply with detail on). The hangar models carry
// soft generator textures with no panel work, so close up they read as plastic. This layer draws engraved panel
// lines, rivet rows, panel-to-panel paint variation, chipped edges and a glossier clear coat procedurally in the
// model's own axes (nose +X, up +Y, plane length 1): crisp at any zoom, no texture budget, the same for every
// livery. Off in battle (detail_k = 0): the battle camera is far too high for it to show.
//
// Layout follows how real airframes are skinned: frames and spars (lines across the flow, swept with the wing
// outboard of the fuselage), stringer seams and ribs (lines along the flow: constant |z| on top and bottom faces,
// constant y on the sides), panels staggered bay by bay like brickwork, rivet rows beside the seams. Every line
// width is at least one pixel and fades when it would be thinner (fwidth), so there are no stairs and no shimmer.
// Mirror-symmetric in z: both wings carry the same panels.

uniform float detail_k = 0.0;   // 0 — off (battle), 1 — full hangar detail
// fuselage axis height, fuselage half-width (wings start outboard of it), spar sweep (tan, x back per |z|),
// pattern scale (Livery.CLASS_SCALE: a bigger plane has relatively smaller panels)
uniform vec4 pd_shape = vec4(-0.04, 0.06, 0.4, 1.0);
uniform float pd_gloss = 0.0;   // 0 — paint roughness as the livery has it, 1 — hangar clear coat
uniform mat4 from_model = mat4(1.0);   // inverse of to_model: model-space normals back to the mesh's own axes

const float PD_FRAME = 0.052;   // frame / spar spacing, model units (≈ 0.8 m on a 15 m fighter)
const float PD_SEAM = 0.042;    // stringer seam / rib spacing
const float PD_LINE_W = 0.00055;   // half-width of a panel line
const float PD_DEPTH = 0.00022;    // groove depth (only its slope matters for the normal)
const float PD_RIVET_STEP = 0.005;    // rivet pitch along a row
const float PD_RIVET_R = 0.0006;      // rivet head radius
const float PD_RIVET_OFF = 0.0016;    // rivet row offset from its seam

float pd_hash(float n) { return fract(sin(n * 127.1 + 311.7) * 43758.5453); }

// Nearest line of an irregular family along coordinate u: lines near every multiple of s, each moved by up to
// ±0.3 s (seeded), so panels are not graph paper. x — signed distance to the line, y — index of the panel cell u is
// in (the cell after line k is k).
vec2 pd_line(float u, float s, float seed) {
	float c = floor(u / s);
	float best = 1e9;
	float cell = c;
	for (int i = -1; i <= 1; i++) {
		float k = c + float(i);
		float pos = (k + 0.5 + 0.6 * (pd_hash(k * 1.37 + seed) - 0.5)) * s;
		float d = u - pos;
		float closer = step(abs(d), abs(best));
		best = mix(best, d, closer);
		cell = mix(cell, d >= 0.0 ? k : k - 1.0, closer);
	}
	return vec2(best, cell);
}

// Groove of one line: x — height (≤ 0), y — dh/du, z — groove mask for the cavity (0…1, faded when sub-pixel).
// fw — pixel footprint of u
vec3 pd_groove(float d, float fw) {
	float w = max(PD_LINE_W, fw * 0.9);
	float fade = clamp(PD_LINE_W / w, 0.0, 1.0);
	fade *= fade;   // sub-pixel seams fade fast: from afar the skin reads clean, not as graph paper
	float t = clamp(abs(d) / w, 0.0, 1.0);
	float s = t * t * (3.0 - 2.0 * t);
	float g = (1.0 - s) * fade;
	float dh = PD_DEPTH * 6.0 * t * (1.0 - t) / w * sign(d) * fade;
	return vec3(-PD_DEPTH * (1.0 - s) * fade, dh, g);
}

// Rivet row beside a line: d — signed distance to the line, v — coordinate along it, fwv / fwd — pixel footprints.
// x — head mask, yz — dh/d(d), dh/d(v) of the dome. Rows on one or both sides by `sides` (1 — both).
vec3 pd_rivets(float d, float v, float fwd, float fwv, float sides) {
	float side = sides > 0.5 ? 1.0 : step(0.0, d);
	float du = abs(d) - PD_RIVET_OFF;
	float dv = (fract(v / PD_RIVET_STEP) - 0.5) * PD_RIVET_STEP;
	float r = length(vec2(du, dv));
	float aa = max(fwd, fwv) * 0.75;
	float fade = clamp(PD_RIVET_R / max(aa, 1e-6) - 0.6, 0.0, 1.0);
	float m = (1.0 - smoothstep(PD_RIVET_R - aa, PD_RIVET_R + aa, r)) * fade * side;
	vec2 gr = -2.0 * PD_DEPTH * 0.6 * vec2(du * sign(d), dv) / (PD_RIVET_R * PD_RIVET_R) * m;
	return vec3(m, gr);
}

// The whole layer at model point p with model normal n. Out: model-space height gradient (bump), cavity (0 — open
// skin, 1 — in a groove), rivet heads, edge (closeness to a seam, for chipping), panel id (0…1, for the per-panel
// paint variation).
void pd_eval(vec3 p, vec3 n, out vec3 grad, out float cavity, out float rivet, out float edge, out float pid) {
	float sc = pd_shape.w;
	float az = abs(p.z);
	float sz = p.z >= 0.0 ? 1.0 : -1.0;
	float top = smoothstep(0.45, 0.75, abs(n.y));   // top and bottom faces vs. sides
	// frames and spars: across the flow, swept outboard of the fuselage
	float wing = max(az - pd_shape.y, 0.0);
	float u = p.x + pd_shape.z * wing;
	vec3 du_dp = vec3(1.0, 0.0, pd_shape.z * sz * step(pd_shape.y, az));
	float fwu = fwidth(u);
	vec2 lx = pd_line(u, PD_FRAME / sc, 3.1);
	vec3 gx = pd_groove(lx.x, fwu);
	// seams along the flow: |z| on top faces (stringers on the fuselage, ribs on the wings), y on the sides; their
	// positions change bay by bay (cell of the frame family), so panels stagger like brickwork
	float bay = lx.y;
	// on the wing the ribs run further apart than the fuselage stringers: long spanwise panels between the spars
	float wing_k = step(pd_shape.y, az);
	vec2 lt = pd_line(az, PD_SEAM * (1.0 + 0.9 * wing_k) / sc, 11.7 + bay * 5.3 + wing_k * 2.0);
	vec2 ls = pd_line(p.y - pd_shape.x, PD_SEAM * 0.8 / sc, 23.9 + bay * 7.1);
	float fwz = fwidth(az);
	float fwy = fwidth(p.y);
	vec3 gt = pd_groove(lt.x, fwz);
	vec3 gs = pd_groove(ls.x, fwy);
	// not every bay has every seam: whole panels span two cells
	float has_t = step(0.3, pd_hash(lt.y * 3.7 + bay * 1.9));
	float has_s = step(0.3, pd_hash(ls.y * 4.1 + bay * 2.3));
	gt *= has_t * top;
	gs *= has_s * (1.0 - top);
	float fwx = fwidth(p.x);
	// rivets: beside every frame (along it: z on top faces, y on the sides) and beside some seams (along x)
	float rv_x = pd_hash(lx.y * 2.9 + 0.7);
	vec3 rxt = pd_rivets(lx.x, p.z, fwu, fwidth(p.z), step(0.5, rv_x)) * top;
	vec3 rxs = pd_rivets(lx.x, p.y, fwu, fwy, step(0.5, rv_x)) * (1.0 - top);
	vec3 rt = pd_rivets(lt.x, p.x, fwz, fwx, 0.0) * has_t * top * step(0.45, pd_hash(lt.y + bay * 3.3));
	vec3 rs = pd_rivets(ls.x, p.x, fwy, fwx, 0.0) * has_s * (1.0 - top) * step(0.45, pd_hash(ls.y + bay * 4.7));
	vec3 rx = rxt + rxs;
	// gradients back to model axes: dh/du · ∇u
	grad = gx.y * du_dp
		+ gt.y * vec3(0.0, 0.0, sz)
		+ gs.y * vec3(0.0, 1.0, 0.0)
		+ rx.y * du_dp + rxt.z * vec3(0.0, 0.0, 1.0) + rxs.z * vec3(0.0, 1.0, 0.0)
		+ rt.y * vec3(0.0, 0.0, sz) + rt.z * vec3(1.0, 0.0, 0.0)
		+ rs.y * vec3(0.0, 1.0, 0.0) + rs.z * vec3(1.0, 0.0, 0.0);
	cavity = clamp(max(gx.z, max(gt.z, gs.z)), 0.0, 1.0);
	rivet = clamp(rx.x + rt.x + rs.x, 0.0, 1.0);
	float dmin = min(abs(lx.x), mix(1.0, abs(lt.x), step(0.5, has_t * top)));
	dmin = min(dmin, mix(1.0, abs(ls.x), step(0.5, has_s * (1.0 - top))));
	edge = 1.0 - smoothstep(0.0, 0.006 / sc, dmin);
	pid = pd_hash(lx.y * 7.13 + (top > 0.5 ? lt.y * 3.71 : ls.y * 5.17 + 91.0));
}

// Model-space normal tilted by the height gradient (only the part along the surface)
vec3 pd_bump(vec3 n, vec3 grad, float k) {
	vec3 gs = grad - dot(grad, n) * n;
	return normalize(n - gs * k);
}
