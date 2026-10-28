// Weathered mud plaster shared by the village walls (adobe.gdshader) and the Highland fort (fort.gdshader), so
// the two read as one building tradition: large soft tone patches, plaster fallen off showing mud-brick
// courses, hairline cracks, rain streaks and a warm lift on the vertical faces. Sizes in metres.
// adobe_wear(c, cm, m, n, rough, lift): c — colour so far, cm — what vertical faces drift towards (the
// photo's mean; pass c for no drift), m — position in metres, n — face normal (y up), rough — roughness to
// adjust, lift — the multiplier of fully vertical faces.

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

// Weathered mud plaster at m (metres) on a face with world normal n; c — the clay colour so far
vec3 adobe_wear(vec3 c, vec3 cm, vec3 m, vec3 n, inout float rough, vec3 lift) {
	float vert = 1.0 - smoothstep(0.55, 0.85, abs(n.y));
	c = mix(c, cm, 0.55 * vert);   // the ground photo's polygon cracks read as paving on a wall
	float big = vnoise(m * 0.33) * 0.6 + vnoise(m * 1.1 + 4.0) * 0.4;
	c *= mix(0.86, 1.08, big);
	c *= 0.95 + 0.1 * vnoise(m * 5.0);
	// plaster fallen off: mud-brick courses (11.5 cm), staggered, mortar darker, each brick its own tone
	float ln = vnoise(m * 0.8 + vec3(3.1)) * 0.7 + vnoise(m * 2.7) * 0.3;
	float loss = smoothstep(0.64, 0.67, ln) * vert;
	float u = abs(n.x) > abs(n.z) ? m.z : m.x;
	float row = floor(m.y / 0.115);
	float bu = (u + mod(row, 2.0) * 0.17) / 0.34;
	float dv = abs(fract(m.y / 0.115 + 0.5) - 0.5) * 0.115;
	float du = abs(fract(bu + 0.5) - 0.5) * 0.34;
	float mortar = 1.0 - smoothstep(0.006, 0.014, min(dv, du));
	vec3 brick = c * vec3(0.8, 0.68, 0.56) * (0.85 + 0.3 * hash3(vec3(floor(bu), row, 7.0)));
	brick = mix(brick, c * vec3(0.62, 0.55, 0.48), mortar);
	float lip = (smoothstep(0.6, 0.64, ln) - loss) * vert;
	c = mix(c * (1.0 - 0.15 * lip), brick, loss);
	// hairline cracks and rain streaks down the walls
	float cr = abs(vnoise(m * vec3(0.9, 0.6, 0.9) + vec3(7.0)) - 0.5);
	c *= 1.0 - (1.0 - smoothstep(0.002, 0.007, cr)) * 0.3 * vert * step(0.55, vnoise(m * 0.4));
	float st = vnoise(vec3(m.x * 4.5, m.y * 0.3, m.z * 4.5));
	c *= 1.0 - smoothstep(0.58, 0.85, st) * vert * 0.2;
	// the walls' shaded sides read near black from gameplay height: a warm bounce from the sunlit ground (lift)
	c *= mix(vec3(1.0), lift, vert);
	rough = clamp(rough + 0.05 * (big - 0.5) + 0.03 * loss, 0.0, 1.0);
	return c;
}
