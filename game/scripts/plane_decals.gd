class_name PlaneDecals
## Player decals on the own plane (Kanta 27.10: free placement, spec docs/superpowers/specs/2026-10-27-plane-decals-design.md).
## The plane's records (Profile.decals, or the debug samples with `--decals`) are cut out of the hull by
## `DecalMesh` and merged into one mesh with one material — one extra draw call, the same in the hangar, the title
## flight and combat, in Forward+ and GL Compatibility. The mesh hangs under the insignia node, so the
## invulnerability blink covers it. A decal laid over the fin badge hides that badge (Kanta: a personal fin badge
## may replace the class mark); the wing roundels always stay.
## Turret fairings (SkinPatch), silhouette details and the «Кит» tail cabin are extra skin (`hull_of`); the fairings,
## the tail cabin and the battle bay doors are added to the model after its insignia, so when one arrives the mesh is
## rebuilt once (deferred): a decal there lies on it instead of vanishing under it.
## Moving parts (slats, flaps, bay doors: `PlaneHull.parts_of`) get a decal mesh of their own, hung under the part
## and built in its axes, so the piece of a decal on a flap goes down with the flap; on the battle model, where the
## flap plates lie over the wing, the wing under a plate gets no piece (no ghost when the flap goes down).
## Art: one mask atlas (tools/decal_atlas.py): R/G/B weights of the primary, secondary and ink paints, A coverage.

const WEAR := 0.35   ## default weathering: chips and fading of the paint
const PREVIEW_LIFT := 0.0018   ## the editor's live decal sits over the committed ones
const FAIRING := "crown"   ## meta SkinPatch.turret_fairing sets on a fairing (a second one gets a generated name)
## Nodes whose arrival under the model changes the skin decals are cut from (besides fairings)
const WATCH := ["bay_doors", "tail_cabin", "detail", "wing_mech"]
const PART_MESH := "decals_part"   ## the decal mesh under a moving part
const PART_PREVIEW := "decal_preview_part"
## Debug sample art per class (`--decals`), laid on the presets: nose, tally, number, fin, wing, wing turn (radians),
## primary and secondary paint
const SAMPLE_ART := {
	"fighter": ["shark_mouth", "tally_air", "07", "skull_winged", "bolt", 0.35, "bone", "red"],
	"attacker": ["rook", "tally_ground", "312", "skull_wrench", "chevrons", -0.5, "bone", "rust"],
	"bomber": ["whale", "tally_bomb", "45", "ace_card", "sun", 0.25, "sand", "teal"],
}

static var _shader: Shader
static var _flags_read := false
static var _samples := false
static var _sample_tally := 9
static var _wear := WEAR


## True when the debug flag `--decals` puts the sample decals on every own plane (read once)
static func samples_on() -> bool:
	if not _flags_read:
		_flags_read = true
		for a in OS.get_cmdline_user_args():
			if a == "--decals":
				_samples = true
			elif a.begins_with("--decaltally="):
				_sample_tally = clampi(int(a.get_slice("=", 1)), 0, DecalCatalog.TALLY_MAX)
			elif a.begins_with("--decalwear="):
				_wear = clampf(float(a.get_slice("=", 1)), 0.0, 1.0)
	return _samples


## Builds the decal mesh of the own plane `model` (key «fighter_1» and so on) under the insignia node `ins`;
## nothing when the plane has no decals. Called from Insignia.attach for the player's plane only.
static func attach(model: Node3D, key: String, ins: Node3D) -> void:
	if ins == null:
		return
	var cls := key.get_slice("_", 0)
	var lvl := int(key.get_slice("_", 1))
	var records: Array[DecalRecord] = []
	var tally := 0
	if samples_on():
		var hull := PlaneHull.of(model)
		if hull != null:
			records = samples(hull, key)
		tally = _sample_tally
	else:
		records = Profile.decals(cls, lvl)
		tally = Profile.decal_tally(cls)
	if records.is_empty():
		return
	_keep(model, ins, key, records, tally)
	build(model)


## Shows `records` on `model` instead of what it carries now (the hangar editor after every change); an empty list
## clears the mesh and brings hidden badges back. `tally` — marks for tally decals.
static func show(model: Node3D, key: String, records: Array[DecalRecord], tally: int) -> void:
	var ins := model.get_node_or_null("insignia") as Node3D
	if ins == null:
		return
	_keep(model, ins, key, records, tally)
	build(model)


## The editor's live decal: `r` drawn a little above the others with a pulsing light tint (the decal under the
## cursor, the one being moved or the selected one); null hides it
static func show_preview(model: Node3D, r: DecalRecord, tally: int) -> void:
	var ins := model.get_node_or_null("insignia") as Node3D
	if ins == null:
		return
	var one: Array[DecalRecord] = []
	if r != null:
		one.append(r)
	var hull := hull_of(model) if r != null else null
	var parts := PlaneHull.parts_of(model)
	var mesh: ArrayMesh = null
	if hull != null:
		mesh = DecalMesh.build(hull, one, tally, PREVIEW_LIFT, _part_hulls(parts))
	_put(ins, "decal_preview", mesh, 1.0)
	for pt: Dictionary in parts:
		var pm: ArrayMesh = null
		if r != null:
			pm = DecalMesh.build(pt["hull"], one, tally, PREVIEW_LIFT, [] as Array[PlaneHull], pt["to_local"])
		_put(pt["node"], PART_PREVIEW, pm, 1.0)


## The skin decals are cut from: the hull with the turret fairings, silhouette details and tail cabin as extra skin
## (null for a model without one). Kept on the model while those stay the same, since the editor casts a ray on it
## every frame.
static func hull_of(model: Node3D) -> PlaneHull:
	var more := PlaneHull.statics_of(model)
	var sig := ",".join(PackedStringArray(more.map(func(m: MeshInstance3D) -> String: return str(m.get_instance_id()))))
	var kept: Array = model.get_meta("decal_hull", [])
	if kept.size() == 2 and String(kept[0]) == sig:
		return kept[1]
	var hull := PlaneHull.of(model)
	if hull == null:
		return null
	if not more.is_empty():
		hull = hull.with_extra(PlaneHull.from_meshes(more, model, false))
	model.set_meta("decal_hull", [sig, hull])
	return hull


## What the editor's cursor and the presets land on: `hull_of` plus the moving parts at rest (the editor holds the
## flaps up and the bay shut), so a click on a flap puts the decal on the flap, not on the skin behind it
static func cursor_hull(model: Node3D) -> PlaneHull:
	var hull := hull_of(model)
	if hull == null:
		return null
	var parts := PlaneHull.parts_of(model)
	if parts.is_empty():
		return hull
	var kept: Array = model.get_meta("decal_cursor", [])
	if kept.size() == 2 and kept[0] == hull:
		return kept[1]
	var ph := PlaneHull.new()
	for pt: Dictionary in parts:
		var h: PlaneHull = pt["hull"]
		ph.pos.append_array(h.pos)
		ph.nrm.append_array(h.nrm)
	var chain := ph if hull.extra == null else hull.extra.with_extra(ph)
	var cur := hull.with_extra(chain)
	model.set_meta("decal_cursor", [hull, cur])
	return cur


## Stores what `build` draws on the insignia node and watches the model for turret fairings
static func _keep(model: Node3D, ins: Node3D, key: String, records: Array[DecalRecord], tally: int) -> void:
	ins.set_meta("decal_records", records)
	ins.set_meta("decal_tally", tally)
	ins.set_meta("decal_key", key)
	model.set_meta("decal_ins", ins)
	if not model.has_meta("decal_watch"):   # the battle model is reused from a pool: connect once
		model.set_meta("decal_watch", true)
		model.child_entered_tree.connect(_on_child.bind(model))


## (Re)builds the decal mesh of `model` from the records kept on its insignia node, turret fairings included
static func build(model: Node3D) -> void:
	var ins: Node3D = model.get_meta("decal_ins", null)
	if ins == null or not is_instance_valid(ins) or ins.get_parent() != model:
		return
	var records: Array[DecalRecord] = ins.get_meta("decal_records", [] as Array[DecalRecord])
	var t0 := Time.get_ticks_usec()
	var tally := int(ins.get_meta("decal_tally", 0))
	var hull := hull_of(model) if not records.is_empty() else null
	var parts := PlaneHull.parts_of(model)
	var mesh := DecalMesh.build(hull, records, tally, DecalMesh.LIFT, _part_hulls(parts)) if hull != null else null
	var part_tris := 0
	for pt: Dictionary in parts:
		var pm: ArrayMesh = null
		if hull != null:
			pm = DecalMesh.build(pt["hull"], records, tally, DecalMesh.LIFT, [] as Array[PlaneHull], pt["to_local"])
		_put(pt["node"], PART_MESH, pm, 0.0)
		part_tris += int(pm.surface_get_array_len(0) / 3.0) if pm != null else 0
	_put(ins, "decals", mesh, 0.0)
	_hide_covered_badges(ins, records)
	if mesh == null:
		return
	if _samples:
		var fairing_tris := hull.extra.triangles() if hull.extra != null else 0
		print("DECALS %s: %d decals, %d extra skin triangles, %d triangles (+%d on moving parts), hull %d triangles, %.1f ms" % [
			String(ins.get_meta("decal_key", "")), records.size(), fairing_tris,
			int(mesh.surface_get_array_len(0) / 3.0), part_tris, hull.triangles(), (Time.get_ticks_usec() - t0) / 1000.0])


## The moving parts' skins (model axes at rest): the body's decal gets no piece under them
static func _part_hulls(parts: Array) -> Array[PlaneHull]:
	var out: Array[PlaneHull] = []
	for pt: Dictionary in parts:
		out.append(pt["hull"])
	return out


## Puts `mesh` into the decal mesh node `name` under `parent` (made on first use, with the decal material;
## `highlight` 1 — the editor's preview); a null mesh hides the node under the insignia, which is kept so the editor
## can fill it again in the same frame. Under a moving part an empty node is removed instead: the part is repainted
## by Livery.apply, which walks every MeshInstance3D outside the insignia and expects a mesh on each.
static func _put(parent: Node3D, node_name: String, mesh: ArrayMesh, highlight: float) -> void:
	var mi := parent.get_node_or_null(node_name) as MeshInstance3D
	if mesh == null:
		if mi != null and String(parent.name) != "insignia":
			parent.remove_child(mi)
			mi.queue_free()
		elif mi != null:
			mi.mesh = null
			mi.visible = false
		return
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = node_name
		mi.material_override = material(highlight)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
	mi.mesh = mesh
	mi.visible = true


## A turret fairing, the tail cabin or the bay doors joined the model: rebuild once at the end of the frame (both
## wing fairings come together)
static func _on_child(node: Node, model: Node3D) -> void:
	if node.get_parent() != model or not (node.has_meta(FAIRING) or String(node.name) in WATCH) \
			or model.get_meta("decal_dirty", false):
		return
	model.set_meta("decal_dirty", true)
	_rebuild_later.call_deferred(model)


static func _rebuild_later(model: Node3D) -> void:
	if not is_instance_valid(model):
		return
	model.set_meta("decal_dirty", false)
	build(model)


## The debug sample decals of plane `key`, laid on the presets (a missed ray drops that decal)
static func samples(hull: PlaneHull, key: String) -> Array[DecalRecord]:
	var out: Array[DecalRecord] = []
	var art: Array = SAMPLE_ART.get(key.get_slice("_", 0), [])
	if art.is_empty():
		return out
	for side in [-1, 1]:
		_add(out, DecalPresets.record(hull, key, "nose", side, String(art[0])), art, 0.0, "")
		_add(out, DecalPresets.record(hull, key, "number", side, DecalCatalog.NUMBER), art, 0.0, String(art[2]))
		_add(out, DecalPresets.record(hull, key, "tally", side, String(art[1])), art, 0.0, "")
	_add(out, DecalPresets.record(hull, key, "fin", 1, String(art[3])), art, 0.0, "")
	_add(out, DecalPresets.record(hull, key, "wing", 1, String(art[4])), art, float(art[5]), "")   # the lit side
	return out


static func _add(out: Array[DecalRecord], r: DecalRecord, art: Array, angle: float, text: String) -> void:
	if r == null:
		return
	r.angle = angle
	r.c1 = String(art[6])
	r.c2 = String(art[7])
	if text != "":
		r.text = text
	DecalLoadout.add(out, r)


## Fin and side insignia under a decal are hidden (the wing roundels never are); a badge hidden here before comes
## back once no decal covers it (the editor moves decals away). Badges hidden by Insignia itself are left alone.
static func _hide_covered_badges(ins: Node3D, records: Array[DecalRecord]) -> void:
	for c in ins.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var n := String(mi.name) if not String(mi.name).begins_with("Mesh") else String(mi.get_parent().name)
		if not (n.begins_with("fin") or n.begins_with("side")) or mi.mesh == null:
			continue
		var centre := PlaneHull.rel_transform(mi, ins) * mi.mesh.get_aabb().get_center()
		var covered := false
		for r in records:
			if r.pos.distance_to(centre) < maxf(r.size * 0.6, 0.02):
				covered = true
				break
		if covered and mi.visible:
			mi.visible = false
			mi.set_meta("decal_hid", true)
		elif not covered and mi.get_meta("decal_hid", false):
			mi.visible = true
			mi.remove_meta("decal_hid")


## The decal material (one per plane; the shader is shared); `highlight` 1 — the editor's pulsing light tint
static func material(highlight := 0.0) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("atlas", load(DecalCatalog.ATLAS_PATH))
	var pal := PackedVector3Array()
	for col in DecalCatalog.palette():
		pal.append(Vector3(col.r, col.g, col.b))
	while pal.size() < 16:   # the shader's array is fixed at 16
		pal.append(Vector3.ZERO)
	m.set_shader_parameter("palette", pal)
	m.set_shader_parameter("ink", DecalCatalog.palette().size() - 1)
	m.set_shader_parameter("wear", _wear)
	m.set_shader_parameter("highlight", highlight)
	return m


const SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/srgb.gdshaderinc"

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 palette[16];   // DecalCatalog paints (sRGB), then the ink
uniform int ink = 12;
uniform float wear = 0.35;  // 0 — fresh, 1 — chipped and faded
uniform float highlight = 0.0;  // editor preview: pulses towards a light tint so the live decal stands out

varying vec3 lp;
varying flat vec2 paint;

float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float vnoise3(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash3(i), hash3(i + vec3(1.0, 0.0, 0.0)), u.x), mix(hash3(i + vec3(0.0, 1.0, 0.0)), hash3(i + vec3(1.0, 1.0, 0.0)), u.x), u.y);
	float b = mix(mix(hash3(i + vec3(0.0, 0.0, 1.0)), hash3(i + vec3(1.0, 0.0, 1.0)), u.x), mix(hash3(i + vec3(0.0, 1.0, 1.0)), hash3(i + vec3(1.0)), u.x), u.y);
	return mix(a, b, u.z);
}

void vertex() {
	lp = VERTEX;
	paint = UV2;
}

void fragment() {
	vec4 t = texture(atlas, UV);
	vec3 w = t.rgb / max(t.r + t.g + t.b, 1e-3);
	vec3 col = w.r * SRGB(palette[int(paint.x + 0.5)]) + w.g * SRGB(palette[int(paint.y + 0.5)]) + w.b * SRGB(palette[ink]);
	// weathering in model space (does not swim with the projection): chips show the paint below, the rest fades
	// towards a dusty grey and gets grime blotches
	float chip = vnoise3(lp * 900.0) * 0.6 + vnoise3(lp * 260.0) * 0.4;
	float cover = t.a * COLOR.a * step(wear * 0.42, chip);   // COLOR.a: DecalMesh fades it out on a steep skin
	float grime = vnoise3(lp * 120.0 + 3.7);
	float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(col, vec3(l) * vec3(1.02, 0.98, 0.9), 0.25 * wear);
	col *= 1.0 - 0.18 * wear * smoothstep(0.45, 0.8, grime);
	float pulse = highlight * (0.5 + 0.5 * sin(TIME * 5.0));
	col = mix(col, SRGB(vec3(1.0, 0.92, 0.6)), 0.35 * pulse);
	ALBEDO = col;
	EMISSION = col * 0.25 * pulse;
	ROUGHNESS = 0.82 + 0.1 * grime;
	METALLIC = 0.0;
	ALPHA = cover;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
"""
