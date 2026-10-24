class_name FxLayer
extends GPUParticles3D
## One layer of GPU effect particles (VFX-01): the simulation `Boom3D._tick` / `_write` did on the CPU now runs
## in a particle shader, and the layer is drawn with the same spatial shaders Boom3D uses, so the look stays.
## Particles come only from code (`emit_particle`). Checked on a Forward+ frame 2026-10-24: emits show with
## `emitting = true` and not with `emitting = false`. In 4.4.1 the first emit switches the server-side emitter
## off and clears it, and later emits take free slots; slots started before that die at once (identity
## transform unpacks to life 0). So never call `restart()` or set `emitting` again: the next emit would clear
## every live particle. `amount_ratio = 0` is only a guard (the custom shader does not read it).
## Godot 4.4 `ParticleProcessMaterial` ignores the colour passed to `emit_particle` (no preserve-colour flag
## before 4.5), hence the custom particle shader. Emitted data is packed into the transform basis and custom:
## basis x = (r0, r1, life), y = (buoyancy, gravity, drag), z = (wind, rotation, spin), custom = per layer (below).
## When all `amount` slots are busy the engine drops the new particle (GpuFx gives spare slots for that).
## Draws in world space (`local_coords = false`), the CPU path in Boom3D's local space: both match while
## Render3D and Boom3D stay at the origin.

## Which Boom3D layer this is (Boom3D.L_* index) — selects the size/colour rules in the shader
var layer := 0
## Live-particle estimate for budgets and the perf log
var counter := FxCounter.new()
var _clock := 0.0
## Emits made before the particle buffers exist on the GPU are lost (Boom3D is created by the first explosion),
## so the first frames queue them and replay them once the layer has been processed (they lose those ~2 frames
## of delay, invisible at explosion start)
var _pending: Array = []
var _ready_frames := 0

const SIM := """
shader_type particles;
render_mode disable_force, disable_velocity;
uniform vec3 wind;   // Boom3D.WIND, set in setup()
uniform vec3 cam_f = vec3(0.0, -1.0, 0.0);
uniform float game_dt;   // game time step of this frame (0 when paused), see tick()
// USERDATA1 = (r0, r1, life, buoyancy); USERDATA2 = (gravity, drag, wind, spin); USERDATA3 = emitted custom;
// USERDATA4 = (position, age); USERDATA5 = (velocity, rotation); USERDATA6 = base colour
vec3 to_linear(vec3 s) {
	return mix(pow((s + 0.055) / 1.055, vec3(2.4)), s / 12.92, lessThanEqual(s, vec3(0.04045)));
}
void start() {
	USERDATA1 = vec4(TRANSFORM[0].xyz, TRANSFORM[1].x);
	USERDATA2 = vec4(TRANSFORM[1].yz, TRANSFORM[2].x, TRANSFORM[2].z);
	USERDATA3 = CUSTOM;
	USERDATA4 = vec4(TRANSFORM[3].xyz, -CUSTOM.z);
	USERDATA5 = vec4(VELOCITY, TRANSFORM[2].y);
	// Boom3D colours were tuned by eye in Compatibility, which treats them as sRGB; Forward+ reads them as
	// linear, so dark smoke came out near-white (frames 24.10). Converting keeps the tuned look.
	USERDATA6 = vec4(to_linear(COLOR.rgb), COLOR.a);
	TRANSFORM = mat4(vec4(0.0), vec4(0.0), vec4(0.0), vec4(USERDATA4.xyz, 1.0));
}
void process() {
	float life = USERDATA1.z;
	float t = USERDATA4.w + game_dt;
	vec3 p = USERDATA4.xyz;
	vec3 v = USERDATA5.xyz;
	float rot = USERDATA5.w;
	if (t >= life) {
		ACTIVE = false;
	}
	if (t >= 0.0) {
		v.y += (USERDATA1.w - USERDATA2.x) * game_dt;
		v *= 1.0 - min(USERDATA2.y * game_dt, 0.9);
		p += (v + wind * USERDATA2.z) * game_dt;
		rot += USERDATA2.w * game_dt;
	}
	USERDATA4 = vec4(p, t);
	USERDATA5 = vec4(v, rot);
	float k = clamp(t / life, 0.0, 1.0);
	float r0 = USERDATA1.x;
	float r1 = USERDATA1.y;
	vec4 e = USERDATA3;
	vec4 c = USERDATA6;
	vec4 cd = vec4(0.0);
	vec3 o = p;
	mat3 b = mat3(1.0);
%s
	if (t < 0.0) {
		b = mat3(0.0);   // not born yet (delay)
	}
	TRANSFORM = mat4(vec4(b[0], 0.0), vec4(b[1], 0.0), vec4(b[2], 0.0), vec4(o, 1.0));
	COLOR = c;
	CUSTOM = cd;
}
"""

## Per-layer size, alpha and draw data, line for line from Boom3D._write (same curves, same packing of cd)
const WRITE := {
	0: """
	float r = mix(r0, r1, 1.0 - pow(1.0 - k, 2.2));   // smoke; e = (tile, glow, delay, fade-to-grey)
	b = mat3(r * 2.0);
	c.a *= smoothstep(0.0, 0.08, k) * (1.0 - k * k);
	if (e.w > 0.0) {
		float gk = smoothstep(0.1, 0.9, k) * 0.75;
		c.rgb = mix(c.rgb, to_linear(vec3(e.w, e.w * 0.97, e.w * 0.93)), gk);   // grey is sRGB like c was
	}
	cd = vec4(rot, k, e.x, e.y * max(0.0, 1.0 - k * 3.5));
""",
	1: """
	float r = mix(r0, r1, 1.0 - pow(1.0 - k, 2.0));   // fire; e = (tile, heat, delay, -)
	b = mat3(r * 2.0);
	c.a *= smoothstep(0.0, 0.05, k);
	cd = vec4(rot, k, e.x, e.y);
""",
	2: """
	float r = mix(r0, r1, 1.0 - pow(1.0 - k, 2.6));   // fireball core; e = (seed, heat, delay, squash)
	b = mat3(vec3(r, 0.0, 0.0), vec3(0.0, r * e.w, 0.0), vec3(0.0, 0.0, r));
	cd = vec4(k, e.x, e.y, 0.0);
""",
	4: """
	float w = e.x;   // spark streak along screen velocity; e = (width, -, delay, -)
	vec3 vd = v - cam_f * dot(v, cam_f);
	float ln = clamp(length(vd) * 0.05, w * 3.0, 70.0);
	vec3 xd = length(vd) > 0.1 ? normalize(vd) : vec3(1.0, 0.0, 0.0);
	vec3 yd = normalize(cross(cam_f, xd)) * w * (1.0 - k * 0.5);
	b = mat3(xd * ln, yd, cam_f);
	o = p - xd * ln * 0.5;
	c.a *= 1.0 - k;
""",
	5: """
	float r = mix(r0, r1, 1.0 - pow(1.0 - k, 1.6));   // shock shell; e = (seed, -, delay, squash)
	b = mat3(vec3(r, 0.0, 0.0), vec3(0.0, r * e.w, 0.0), vec3(0.0, 0.0, r));
	c.a *= 1.0 - k;
	cd = vec4(k, e.x, 0.0, 0.0);
""",
	6: """
	float r = mix(r0, r1, sqrt(k));   // flash disc; e = (-, -, delay, -)
	b = mat3(r * 2.0);
	c.a *= (1.0 - k) * (1.0 - k);
""",
}


## Builds the layer: L = Boom3D layer index, n = particle slots, mesh and draw material as Boom3D uses them
func setup(L: int, n: int, mesh: Mesh, draw: Material) -> void:
	layer = L
	amount = n
	lifetime = 30.0   # upper bound only: the shader ends each particle at its own life
	amount_ratio = 0.0
	emitting = true
	local_coords = false
	explosiveness = 0.0
	fixed_fps = 0
	interpolate = false
	visibility_aabb = AABB(Vector3(-1e6, -1e4, -1e6), Vector3(2e6, 2e4, 2e6))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sh := Shader.new()
	sh.code = SIM % WRITE[L]
	var pm := ShaderMaterial.new()
	pm.shader = sh
	pm.set_shader_parameter("wind", Boom3D.WIND)
	process_material = pm
	draw_pass_1 = mesh
	material_override = draw


## Emits one particle from a Boom3D particle record (the dictionary Boom3D._add receives)
func emit(q: Dictionary) -> void:
	if _ready_frames < 2:
		_pending.append(q)
		return
	var delay := -float(q.get("t", 0.0))
	var life := float(q["life"])
	var e := Color(0, 0, delay, 0)
	match layer:
		0: e = Color(q.get("tile", 0), q.get("glow", 0.0), delay, q.get("fade", 0.0))
		1: e = Color(q.get("tile", 0), q.get("h", 1.0), delay, 0.0)
		2: e = Color(q.get("seed", 0.0), q.get("h", 1.0), delay, q.get("sq", 1.0))
		4: e = Color(q.get("w", 1.5), 0.0, delay, 0.0)
		5: e = Color(q.get("seed", 0.0), 0.0, delay, q.get("sq", 1.0))
	var basis := Basis(Vector3(q.get("r0", 0.0), q.get("r1", 0.0), life),
		Vector3(q.get("b", 0.0), q.get("g", 0.0), q.get("drag", 0.0)),
		Vector3(q.get("wind", 0.0), q.get("rot", 0.0), q.get("spin", 0.0)))
	emit_particle(Transform3D(basis, q["p"]), q.get("v", Vector3.ZERO), q.get("c", Color(1, 1, 1, 1)), e,
		EMIT_FLAG_POSITION | EMIT_FLAG_ROTATION_SCALE | EMIT_FLAG_VELOCITY | EMIT_FLAG_COLOR | EMIT_FLAG_CUSTOM)
	counter.add(_clock, life + delay)


## Advances the layer clock (game time, paused with the game) and passes this frame's game time step and the
## camera direction to the shader. The shader steps by that uniform, not by DELTA: the renderer's frame time
## is not the game's delta (on the slow cloud renderer smoke aged visibly faster than Boom3D, bench frames 24.10), and with
## fixed_fps = 0 the process shader runs once per drawn frame, like Boom3D._tick.
func tick(dt: float, cam_f: Vector3) -> void:
	_clock += dt
	if _ready_frames < 2:
		_ready_frames += 1
		if _ready_frames == 2:
			for q in _pending:
				emit(q)
			_pending.clear()
	var pm := process_material as ShaderMaterial
	pm.set_shader_parameter("game_dt", maxf(dt, 0.0))
	if layer == 4:
		pm.set_shader_parameter("cam_f", cam_f)


## Estimated particles alive in this layer
func alive() -> int:
	return counter.alive(_clock)
