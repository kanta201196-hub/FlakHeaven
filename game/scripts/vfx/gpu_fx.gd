class_name GpuFx
extends Node3D
## GPU effect particles (VFX-01, plan docs/superpowers/plans/2026-10-24-combat-vfx.md). Boom3D keeps building
## explosions with the same recipes; every particle of a GPU layer goes here instead of the CPU arrays, so the
## per-frame CPU work of smoke, fire, sparks, flashes and shells disappears. Debris, burning spots and lights
## stay on the CPU for now (few, and they need the terrain height). Forward+ only: `emit_particle` does not
## exist in Compatibility, where Boom3D keeps its CPU path.

## Boom3D layers simulated on the GPU (L_SMOKE, L_FIRE, L_CORE, L_SPARK, L_SHOCK, L_FLASH)
const LAYERS := [0, 1, 2, 4, 5, 6]

## Slots per GPU layer = Boom3D.CAP x SLOTS. A full GPU layer drops the newest particle (emits only take free
## slots), while the CPU path drops the oldest; spare slots keep a fresh explosion whole in a crowded fight.
const SLOTS := 2

## Flipbook layer index (after Boom3D's seven): one camera-facing quad per effect plays a pre-rendered sequence
const L_FLIP := 7
## Flipbooks in flight per effect: a blast plays 3.4 s, so 64 covers a carpet of bombs; when all are busy,
## flip() says no and Boom3D builds that blast from particles
const FLIP_SLOTS := 64

## VFX-02 flipbooks: atlas of FRAMES pictures in COLS columns, rendered from the combat camera (28 deg tilt) and
## lit by the game sun with game/tools/vfx_bake/render_vdb.py. size = quad side per unit of the effect size s
## (Boom3D blast: the fireball at its widest about today's core, 1.5 s); lift = how far up the screen the quad
## centre sits above the ground point, per quad side (in the bake the ground point is 0.20 of the frame below
## the centre); it is applied along the camera's up vector, as the bake is a picture, not a world object;
## life = seconds the whole sequence plays (the simulation is 6.7 s at 30 fps, played about twice as fast).
## The bake matches cam_tilt 28 (F9 also offers 35, 45 and top-down: there the picture leans a little off).
## Visual numbers only, no gameplay effect.
const FLIPS := {
	"blast": {"tex": "res://art/vfx/blast_ground.png", "frames": 64, "cols": 8, "size": 4.0, "lift": 0.20, "life": 3.4, "glow": 0.4},
}

## Draw shader of the flipbook layer: camera-facing quad (like Boom3D.BILLBOARD, without rotation), frame from
## the particle age with a blend to the next frame, baked light (unshaded), soft fade where it meets the scene;
## the hottest fire pixels are pushed above 1.0 so the Forward+ glow catches them
const FLIP_SH := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float frames = 64.0;
uniform float cols = 8.0;
// pulled towards the camera by this share of the quad side, so the slope under a ground blast does not cut the
// picture; the soft fade (share of the side) hides what is left of the cut
uniform float pull = 0.5;
uniform float soft = 0.08;
varying float side;
varying vec4 cd;
void vertex() {
	cd = INSTANCE_CUSTOM;
	float sc = length(MODEL_MATRIX[0].xyz);
	side = sc;
	// slide the quad along the ray to the camera and shrink it by the same ratio: same place and size on screen
	vec3 c = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
	float L = length(c);
	float k = max(L - sc * pull, L * 0.25) / L;
	MODELVIEW_MATRIX = mat4(vec4(sc * k, 0.0, 0.0, 0.0), vec4(0.0, sc * k, 0.0, 0.0), vec4(0.0, 0.0, sc * k, 0.0), vec4(c * k, 1.0));
}
vec2 cell(float f, vec2 uv) { return (vec2(mod(f, cols), floor(f / cols)) + uv * 0.996 + 0.002) / cols; }
void fragment() {
	float f = clamp(cd.y, 0.0, 1.0) * (frames - 1.0);
	float f0 = floor(f);
	vec4 a = mix(texture(atlas, cell(f0, UV)), texture(atlas, cell(min(f0 + 1.0, frames - 1.0), UV)), f - f0);
	float hot = smoothstep(0.6, 1.0, max(a.r, a.g)) * smoothstep(0.08, 0.35, a.r - a.b);
	ALBEDO = a.rgb * (1.0 + hot * cd.w);
	float z = texture(depth_tex, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, z, 1.0);
	float gap = VERTEX.z - v.z / v.w;   // distance in front of the scene behind this pixel
	ALPHA = a.a * COLOR.a * clamp(gap / max(side * soft, 1.0), 0.0, 1.0);
}
"""

var _layers := {}
## Flipbook layers by effect id (FLIPS keys); only those whose atlas loaded
var _flips := {}
## Same layers as a typed list, so per-frame loops do not build an Array from the dictionary
var _list: Array[FxLayer] = []


## True when the GPU path can run: Forward+ renderer and no `--oldfx` (CPU path forced for comparisons)
static func active() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus" \
		and not OS.get_cmdline_user_args().has("--oldfx")


## Creates one FxLayer per GPU layer with Boom3D's meshes, draw materials and slot counts
func build(meshes: Array, mats: Array, caps: Array) -> void:
	for L in LAYERS:
		var fl := FxLayer.new()
		fl.setup(L, caps[L] * SLOTS, meshes[L], mats[L])
		add_child(fl)
		_layers[L] = fl
		_list.append(fl)
	for fx_id in FLIPS:
		var f: Dictionary = FLIPS[fx_id]
		var tex := load(String(f["tex"])) as Texture2D
		if tex == null:
			continue   # atlas not imported yet: Boom3D keeps the particle recipe for this effect
		var sh := Shader.new()
		sh.code = FLIP_SH
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.render_priority = 2
		mat.set_shader_parameter("atlas", tex)
		mat.set_shader_parameter("frames", float(f["frames"]))
		mat.set_shader_parameter("cols", float(f["cols"]))
		var fl := FxLayer.new()
		fl.setup(L_FLIP, FLIP_SLOTS, meshes[Boom3D.L_FLASH], mat)
		add_child(fl)
		_flips[fx_id] = fl
		_list.append(fl)


## True if this Boom3D layer is drawn on the GPU
func has_layer(L: int) -> bool:
	return _layers.has(L)


## Plays flipbook `fx_id` on the ground point g for an effect of size s (Boom3D units); false if there is no
## such flipbook or all its slots are busy, so the caller builds the effect from particles instead
func flip(fx_id: String, g: Vector3, s: float) -> bool:
	var fl: FxLayer = _flips.get(fx_id)
	if fl == null or fl.alive() >= FLIP_SLOTS:
		return false
	var f: Dictionary = FLIPS[fx_id]
	var side := float(f["size"]) * s
	var up := Vector3.UP
	if Render3D.I != null and Render3D.I.cam != null:
		up = Render3D.I.cam.global_transform.basis.y
	fl.emit({"p": g + up * side * float(f["lift"]), "life": float(f["life"]),
		"r0": side * 0.5, "r1": side * 0.5, "glow": float(f["glow"]), "c": Color(1, 1, 1, 1)})
	return true


## Emits one Boom3D particle record into its GPU layer
func emit(L: int, q: Dictionary) -> void:
	(_layers[L] as FxLayer).emit(q)


## Per frame: game time step (0 when paused) and camera forward for velocity-aligned sparks
func tick(dt: float, cam_f: Vector3) -> void:
	for fl in _list:
		fl.tick(dt, cam_f)


## Estimated GPU particles alive, all layers
func alive() -> int:
	var n := 0
	for fl in _list:
		n += fl.alive()
	return n


## Estimated particles alive per Boom3D layer (0 for CPU layers), for the perf log; flipbooks are not listed
func counts() -> Array:
	var pc := [0, 0, 0, 0, 0, 0, 0]
	for fl in _list:
		if fl.layer < pc.size():
			pc[fl.layer] = fl.alive()
	return pc
