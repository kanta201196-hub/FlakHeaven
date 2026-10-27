// Cumulus for the hangar's flight backdrop (Hangar3D: the sky's cloud sea and the near drifting layers).
// s13 (Kanta: «фон квадратами»): the old value noise hashed with sin() of large arguments, which loses
// precision on many GPUs and shows as blocks; this hash has no sin(), and the drift offset wraps, so the
// noise input stays small however long the hangar is open. Needs srgb.gdshaderinc included first.
float cloud_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float cloud_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(cloud_hash(i), cloud_hash(i + vec2(1.0, 0.0)), u.x),
		mix(cloud_hash(i + vec2(0.0, 1.0)), cloud_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
// rotated octaves: no axis-aligned grid shows through
float cloud_fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 r = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 5; i++) {
		v += a * cloud_noise(p);
		p = r * p * 2.03 + vec2(17.0, 9.0);
		a *= 0.5;
	}
	return v;
}
// drift along x, wrapped at 512 noise cells: one jump every 20+ minutes instead of losing precision
float cloud_time(float t, float speed) {
	return mod(t * speed, 512.0);
}
// cloud colour at p: sunlit tops toward sun_xz, blue-grey hollows; thin parts (near cover) go grey
vec3 cloud_col(vec2 p, vec2 sun_xz, float cover) {
	float n0 = cloud_fbm(p);
	float n1 = cloud_fbm(p + sun_xz * 0.12);
	float lit = clamp((n0 - n1) * 5.0 + 0.55, 0.0, 1.0);
	float dense = smoothstep(cover, cover + 0.3, n0);
	vec3 shade = SRGB(vec3(0.58, 0.64, 0.74));
	vec3 light = SRGB(vec3(1.0, 0.98, 0.95));
	vec3 gap = SRGB(vec3(0.46, 0.53, 0.62));   // haze between the clouds, far below
	return mix(gap, mix(shade, light, lit), dense);
}
