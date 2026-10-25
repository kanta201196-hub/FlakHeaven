class_name Unit3D
extends RefCounted
## One plane or vehicle shown in the 3D scene (an entry of Render3D._units, also built by
## TitleFlight). It used to be a Dictionary with string keys. In a big fight Render3D reads
## and writes ~60 of them per unit per frame, and that lookup was most of the ~40 µs each
## enemy cost. Typed fields are plain member reads. Fields that a unit gets only when it needs
## them (parts found on the model, a shadow, a wreck) stay null / empty / NAN until then; the
## comments say what "not set yet" looks like.

# --- always set (Render3D._ensure / _pool_take / TitleFlight) ---
var node: Node3D = null
var mi: MeshInstance3D = null
## "player", "wing", "ally", "enemy", "title"
var kind := ""
var tex: Texture2D = null
## Battle model scene; null when the unit is a mesh made from its picture
var bm: PackedScene = null
## World units per picture pixel (model length 1 = picture width)
var k := 1.0
## Last heading and smoothed bank (Render3D._turn_bank)
var ph := 0.0
var bank := 0.0
## Seen in this frame's sync; units not seen are crashed, pooled or freed
var seen := true
## Weapon models on the hardpoints and their layout cache (Render3D._sync_weapons)
var weapons := {}
var wcache := {}
## Engine flames and props (PlaneFx.attach); empty when none
var fx := {}

# --- shadow (Render3D._place_shadow) ---
## Own shadow mesh (own planes, ground targets) or the picture whose MultiMesh draws it (enemy planes)
var sh: MeshInstance3D = null
var shb: Texture2D = null
## Shadow casting mode applied to the model and the child count it was applied at (-1 — not yet)
var cs := -1
var cs_n := -1
## Shadow alpha last sent to the material (-1 — never)
var sh_a := -1.0
## Ground sample under the shadow: slope normal (valid once `sh_ok`), offset, height, frame phase
var sh_ok := false
var sh_n := Vector3.UP
var sh_off := Vector2.ZERO
var sh_y := 0.0
var sh_f := -1
## Slope tilt of the shadow from `sh_n` (rebuilt with each sample, not every frame)
var sh_b := Basis.IDENTITY

# --- flight over the relief (Render3D._relief_alt) ---
## True once the unit flies over the relief: _place then puts it on the camera ray at `alt`
var has_alt := false
var alt := 0.0
var alt_to := 0.0
var alt_next := 0.0
var pitch := 0.0

# --- ground vehicles (Render3D._ground_parts, _sam_launcher, _convoy_parts, _drive_tilt) ---
## Hull heading; NAN until the parts were looked up on the model
var hull := NAN
var turret: Node3D = null
var antenna: Node3D = null
var launcher: Node3D = null
var launcher_yaw: Node3D = null
var launcher_pitch: Node3D = null
var cells: Array = []
## Last position (Vector2) and smoothed tilt (Vector2); null until the first frame
var lastp: Variant = null
var tilt: Variant = null
var sam_el := 0.0
var sam_n := 0
var sam_kick := 0.0
## Convoy wheels / turret / launcher found on the model (Dictionary); null until looked up
var cv: Variant = null

# --- parts looked up on first use (null — not yet) ---
## Helicopter rotors [rotor, tail_rotor]
var rot: Variant = null
## Propeller nodes prop_*
var props3: Variant = null
## Fortress parts (Dictionary)
var fparts: Variant = null
## Tanker refuelling boom; `boom_done` — looked up (the model may have none)
var boom_done := false
var boom: Node3D = null
var boom_tube: Node3D = null
var boom_tip: Node3D = null
## Leviathan parts state (LeviathanParts.update); empty until attached
var lev := {}

# --- own planes: model add-ons (WingMech, ModuleParts, Insignia, PlaneFx) ---
var modp: Node3D = null
var mech: Node3D = null
var detail: Node3D = null
var ins: Node3D = null
var bay: Node3D = null
var tail: Node3D = null
var kit: Node3D = null
var props: Node3D = null
## Bomb bay doors open share (1 — open), afterburner glow
var bay_t := 1.0
## Bomb group cooldowns last frame, by group name (a drop opens the bay)
var bay_cd := {}
var ab := 0.0
## Wingman this unit shows (crash on loss)
var ref: WeakRef = null

# --- wrecks (Render3D._sync_wrecks) ---
var wreck := false
var wsmoke: CPUParticles3D = null
var sink_t := 0.0

# --- debug ---
## Triangle count of the model (-1 — not counted yet)
var tris := -1

# --- title screen flight (TitleFlight) ---
var cls := ""
var slot := Vector2.ZERO
var rel := 1.0
