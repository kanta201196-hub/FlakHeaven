shader_type canvas_item;
// Земля биома: 4 бесшовные текстуры, смешанные пятнами по шуму в мировых координатах.

uniform sampler2D t_sand : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D t_clay : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D t_gravel : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D t_river : source_color, repeat_enable, filter_linear_mipmap;
uniform float tex_world = 460.0;   // сколько мировых пикселей занимает одна плитка текстуры
uniform float patch_world = 1500.0; // размер пятен смешивания
uniform float sharp = 9.0;
uniform float seed = 0.0;

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) { return vnoise(p) * 0.65 + vnoise(p * 2.7 + 17.0) * 0.35; }

void fragment() {
	vec2 q = world / patch_world;
	float w0 = fbm(q + vec2(0.0, 0.0));
	float w1 = fbm(q + vec2(31.7, 7.3));
	float w2 = fbm(q + vec2(-13.1, 41.9));
	float w3 = fbm(q * 1.3 + vec2(57.2, -21.4)) * 0.88;
	float m = max(max(w0, w1), max(w2, w3));
	vec4 e = exp((vec4(w0, w1, w2, w3) - m) * sharp);
	e /= (e.x + e.y + e.z + e.w);
	vec2 uv = world / tex_world;
	vec3 c = texture(t_sand, uv).rgb * e.x
		+ texture(t_clay, uv * 1.03 + 0.37).rgb * e.y
		+ texture(t_gravel, uv * 0.97 + 0.61).rgb * e.z
		+ texture(t_river, uv + 0.13).rgb * e.w;
	float macro = 0.9 + 0.18 * vnoise(world / 2600.0 + 5.0);
	COLOR = vec4(c * macro, 1.0);
}
