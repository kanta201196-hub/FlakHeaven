// Aircraft hangar round the weapon store view (S14-12, Kanta 31.10: "a beautiful background for the weapon view:
// the plane hangar"). One shader for the hall's big surfaces (HangarHall), picked by `part`:
//   0 floor   — sealed concrete slabs with sawn joints, aggregate and mottling, oil stains, tyre tracks, worn
//               yellow taxi line and the hatched loading bay round the weapon, soft contact shadows under the
//               parked planes and kit (`blobs`), daylight spilling in from the open doors; outside the doors
//               (`outside`) the sunlit apron;
//   1 wall    — corrugated sheet in painted panels, rust and rain streaks from the fasteners, grime along the
//               foot, a concrete plinth;
//   2 roof    — the dark corrugated underside of the arched roof.
// Sizes are in metres (`m_per_unit` metres per hall unit; the weapon is about 3 m long). The hall is lit by the
// store's own lights; colour constants go through SRGB(), so both renderers draw the same colours.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/srgb.gdshaderinc"

uniform int part = 0;
uniform bool outside = false;
uniform float m_per_unit = 4.8;
uniform vec3 door = vec3(0.0, 9.0, 5.6);   // door centre x, door wall z, half width (hall units, local)
uniform vec4 bay = vec4(0.0, 0.0, 0.62, 0.46);   // hatched loading bay: centre xz, half size xz (hall units)
uniform vec4 blobs[12];   // contact shadows: centre xz, radius along x, along z (hall units, local); r 0 — unused
uniform float taxi_x = 0.0;   // the taxi line runs along z at this x (hall units)
uniform float hall_turn = 0.0;   // the hall's turn round Y in the view (HangarHall.TURN): world → hall axes

varying vec3 lp;   // local position, hall units
varying vec3 ln;   // local normal

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm2(vec2 p) {
	return vnoise(vec3(p, 0.5)) * 0.5 + vnoise(vec3(p * 2.03 + 7.1, 1.5)) * 0.3 + vnoise(vec3(p * 4.1 + 3.3, 2.5)) * 0.2;
}

mat3 turn_y(float a) {
	return mat3(vec3(cos(a), 0.0, -sin(a)), vec3(0.0, 1.0, 0.0), vec3(sin(a), 0.0, cos(a)));
}

void vertex() {
	mat3 back = turn_y(-hall_turn);
	lp = back * (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	ln = normalize(back * (MODEL_NORMAL_MATRIX * NORMAL));
}

// anti-aliased line mask: 1 within half width `hw` of 0 (`d` distance, `fw` its screen footprint)
float aa_line(float d, float hw, float fw) {
	return 1.0 - smoothstep(hw - fw, hw + fw, abs(d));
}

void fragment() {
	vec3 m = lp * m_per_unit;   // metres
	vec3 fwm = fwidth(m);
	float fwl = max(fwm.x, fwm.z);
	vec3 alb;
	float rough;
	float spec = 0.4;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	vec3 nrm = ln;
	if (part == 0) {
		// ---- floor ----
		float big = fbm2(m.xz * 0.07);
		float mid = fbm2(m.xz * 0.45 + 13.0);
		float fine = vnoise(vec3(m.xz * 7.0, 0.0)) * 0.6 + vnoise(vec3(m.xz * 23.0, 1.0)) * 0.4;
		alb = SRGB(vec3(0.35, 0.345, 0.33)) * mix(0.8, 1.08, big) * mix(0.92, 1.05, mid) * (0.94 + 0.12 * fine);
		// aggregate: small light and dark grains, faded where they get smaller than a pixel
		float grain = hash3(floor(vec3(m.xz * 60.0, 0.0)));
		float gk = 1.0 - smoothstep(0.004, 0.02, fwl);
		alb *= 1.0 + (step(0.93, grain) * 0.16 - step(grain, 0.05) * 0.14) * gk;
		rough = mix(0.62, 0.86, mid) - big * 0.08;
		if (outside) {
			alb *= SRGB(vec3(1.06, 1.03, 0.98));
			rough = 0.9;
		}
		// sawn joints of 6 m slabs, sealant a little darker on both sides
		vec2 jd = abs(fract(m.xz / 6.0 + 0.5) - 0.5) * 6.0;
		float joint = max(aa_line(jd.x, 0.008, fwm.x * 0.7), aa_line(jd.y, 0.008, fwm.z * 0.7));
		float jhalo = max(exp(-jd.x / 0.05), exp(-jd.y / 0.05));
		alb *= (1.0 - 0.55 * joint) * (1.0 - 0.08 * jhalo);
		// oil stains: dark, smoother, with a soaked rim
		// (a slow mask keeps them to a few places: under parked planes' engines, by the kit)
		float oil_n = fbm2(m.xz * 0.3 + 41.0) + (fbm2(m.xz * 0.05 + 2.0) - 0.5) * 0.5 + (fbm2(m.xz * 2.2) - 0.5) * 0.18;
		float oil = smoothstep(0.66, 0.74, oil_n) * (outside ? 0.4 : 1.0);
		float rim = smoothstep(0.62, 0.66, oil_n) - smoothstep(0.66, 0.74, oil_n);
		alb = mix(alb, alb * SRGB(vec3(0.66, 0.64, 0.6)), oil * 0.65 + rim * 0.2);
		rough = mix(rough, 0.35, oil * 0.8);
		// tyre tracks along the taxi line: two dark bands of rubber, streaky
		float tx = abs(abs(lp.x - taxi_x) - 0.42);
		float tyre = (1.0 - smoothstep(0.03, 0.09, tx)) * smoothstep(0.35, 0.75, vnoise(vec3(m.x * 3.0, m.z * 0.25, 4.0)));
		alb *= 1.0 - 0.22 * tyre;
		// painted markings, worn in patches
		float wear = smoothstep(0.35, 0.7, fbm2(m.xz * 1.6 + 5.0)) * 0.6 + smoothstep(0.7, 0.9, fine) * 0.4;
		float paint = aa_line(lp.x - taxi_x, 0.04, fwidth(lp.x) * 0.7);   // taxi line, 0.4 m
		vec2 bq = abs(lp.xz - bay.xy) - bay.zw;
		float edge = max(bq.x, bq.y);
		float frame_m = aa_line(edge, 0.016, fwidth(edge) * 0.7) * step(-0.05, edge);
		float in_band = step(edge, 0.0) * step(-0.07, edge);
		float hatch = step(0.5, fract((lp.x + lp.z) * 7.0)) * in_band;
		float yellow = clamp(max(paint * (1.0 - step(abs(lp.z - bay.y), bay.w + 0.3)), max(frame_m, hatch)), 0.0, 1.0);
		yellow *= 1.0 - wear * 0.75;
		yellow *= outside ? 0.0 : 1.0;
		alb = mix(alb, SRGB(vec3(0.62, 0.48, 0.1)) * (0.85 + 0.2 * mid), yellow);
		rough = mix(rough, 0.55, yellow);
		// contact shadows under the parked planes and kit
		float occ = 0.0;
		for (int i = 0; i < 12; i++) {
			vec4 b = blobs[i];
			if (b.z > 0.0) {
				vec2 q = (lp.xz - b.xy) / b.zw;
				occ = max(occ, exp(-dot(q, q) * 2.2));
			}
		}
		// along the walls the floor gets darker (no bounce from the walls' foot)
		alb *= 1.0 - 0.32 * occ;
		// daylight from the open doors: a soft pool on the floor in front of them, and the sunlit apron
		float dz = door.y - lp.z;
		float across = 1.0 - smoothstep(door.z * 0.7, door.z * 1.3, abs(lp.x - door.x));
		float pool = exp(-max(dz, 0.0) / 3.2) * across;
		emit = alb * SRGB(vec3(1.0, 0.95, 0.86)) * (outside ? 0.75 : pool * 0.42);
	} else if (part == 1) {
		// ---- corrugated wall ----
		vec3 t = normalize(cross(vec3(0.0, 1.0, 0.0), ln));
		float u = dot(m, t);   // along the wall, metres
		float h = m.y + 0.2 * m_per_unit;  // over the floor (floor at -0.2 units)
		float ph = u * TAU / 0.2;   // 200 mm corrugation pitch
		float wk = 1.0 - smoothstep(0.02, 0.06, abs(fwidth(u)));   // the waves fade out with distance
		nrm = normalize(ln + t * cos(ph) * 0.45 * wk);
		float panel = floor(u / 1.1);
		float row = floor(h / 3.0);
		float tone = hash3(vec3(panel, row, 3.0));
		alb = SRGB(vec3(0.5, 0.53, 0.5)) * mix(0.9, 1.06, tone) * (0.97 + 0.06 * sin(ph) * wk);
		// panel laps and fastener rows
		float lap = aa_line(fract(u / 1.1 + 0.5) - 0.5, 0.004, fwidth(u / 1.1));
		float rowl = aa_line(fract(h / 3.0 + 0.5) - 0.5, 0.006, fwidth(h / 3.0));
		alb *= 1.0 - 0.3 * max(lap, rowl);
		// rust and rain streaks running down from the fastener rows
		float sk = vnoise(vec3(u * 3.1, h * 0.35, 9.0)) * 0.7 + vnoise(vec3(u * 9.0, h * 1.1, 2.0)) * 0.3;
		float below = fract(h / 3.0);
		float streak = smoothstep(0.62, 0.85, sk) * (1.0 - below) * 0.9;
		alb = mix(alb, alb * SRGB(vec3(0.62, 0.45, 0.32)), streak * 0.6);
		// grime along the foot, concrete plinth below 0.9 m
		alb *= mix(0.62, 1.0, smoothstep(0.0, 2.4, h));
		float plinth = 1.0 - step(0.9, h);
		vec3 conc = SRGB(vec3(0.4, 0.4, 0.38)) * (0.88 + 0.2 * vnoise(vec3(m.xz * 2.0, h * 2.0)));
		alb = mix(alb, conc, plinth);
		nrm = normalize(mix(nrm, ln, plinth));
		rough = mix(0.62 + 0.18 * sk, 0.9, plinth);
		metal = mix(0.25, 0.0, plinth);
		spec = 0.45;
	} else {
		// ---- roof underside ----
		float ph = m.x * TAU / 0.25;
		float wk = 1.0 - smoothstep(0.02, 0.07, fwidth(m.x));
		nrm = normalize(ln + vec3(cos(ph) * 0.4 * wk, 0.0, 0.0));
		alb = SRGB(vec3(0.24, 0.25, 0.26)) * (0.85 + 0.25 * vnoise(vec3(m * 0.3)));
		rough = 0.75;
		metal = 0.3;
	}
	ALBEDO = alb;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	METALLIC = metal;
	SPECULAR = spec;
	EMISSION = emit;
	NORMAL = normalize((VIEW_MATRIX * vec4(turn_y(hall_turn) * nrm, 0.0)).xyz);
}
