class_name DecalRecord
extends RefCounted
## One free-placed decal on a plane (Kanta 27.10): which picture, where on the skin, how big, turned and painted.
## Position and normal are in the plane model's own axes (nose +X, up +Y, left wing −Z, length 1), the same for the
## hangar and the battle model, so one record fits both. Saved as a small dictionary (`to_dict`), read back
## through `from_dict`, which checks every field (code.md §9.5) and returns null for anything it cannot trust.

const SIZE_MIN := 0.008   ## decal height, model units (plane length 1)
const SIZE_MAX := 0.25
const POS_MAX := 0.75     ## a position further than this from the model centre is not on the plane
const TEXT_MAX := 3       ## digits in a side number

var id := ""              ## DecalCatalog image id
var pos := Vector3.ZERO   ## centre on the skin
var normal := Vector3(0.0, 0.0, -1.0)   ## outward skin normal at `pos` (unit)
var angle := 0.0          ## turn around the normal, radians; 0 — the picture's top towards the sky (or the nose)
var size := 0.04          ## height; the width follows the picture
var mirror := false       ## flipped left–right
var c1 := DecalCatalog.DEFAULT_C1   ## primary paint id
var c2 := DecalCatalog.DEFAULT_C2   ## secondary paint id
var text := ""            ## digits of a side number (`id` == "number")


## Right and up of the decal on the skin: [right, up], both unit and perpendicular to the normal. Angle 0 points
## the picture's top along the model's up projected on the skin; on a near-horizontal skin (wing, spine) up is
## undefined, so the top points to the nose instead, as the wing roundels do.
func basis_vectors() -> Array[Vector3]:
	var n := normal.normalized()
	var ref := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.9 else Vector3(1.0, 0.0, 0.0)
	var up := (ref - n * ref.dot(n)).normalized().rotated(n, angle)
	var right := up.cross(n).normalized()
	return [right, up]


## Saved form (JSON-friendly)
func to_dict() -> Dictionary:
	var d := {"id": id, "p": [pos.x, pos.y, pos.z], "n": [normal.x, normal.y, normal.z], "a": angle, "s": size,
		"c1": c1, "c2": c2}
	if mirror:
		d["m"] = true
	if id == DecalCatalog.NUMBER:
		d["t"] = text
	return d


## A record from its saved form, or null if the entry is broken (unknown picture, bad numbers, nothing to draw)
static func from_dict(d: Variant) -> DecalRecord:
	if not (d is Dictionary):
		return null
	var src: Dictionary = d
	var r := DecalRecord.new()
	r.id = String(src.get("id", ""))
	if not DecalCatalog.has_image(r.id):
		return null
	var p: Variant = _vec3(src.get("p"))
	var n: Variant = _vec3(src.get("n"))
	if p == null or n == null:
		return null
	r.pos = p
	if r.pos.length() > POS_MAX:
		return null
	if (n as Vector3).length() < 1e-4:
		return null
	r.normal = (n as Vector3).normalized()
	var a: Variant = src.get("a", 0.0)
	r.angle = wrapf(float(a), -PI, PI) if (a is float or a is int) else 0.0
	var s: Variant = src.get("s", 0.04)
	r.size = clampf(float(s), SIZE_MIN, SIZE_MAX) if (s is float or s is int) else 0.04
	r.mirror = src.get("m", false) == true
	r.c1 = _paint(src.get("c1"), DecalCatalog.DEFAULT_C1)
	r.c2 = _paint(src.get("c2"), DecalCatalog.DEFAULT_C2)
	if r.id == DecalCatalog.NUMBER:
		r.text = digits_of(String(src.get("t", "")))
		if r.text == "":
			return null
	return r


## Only the digits of `s`, at most TEXT_MAX of them
static func digits_of(s: String) -> String:
	var out := ""
	for ch in s:
		if ch >= "0" and ch <= "9" and out.length() < TEXT_MAX:
			out += ch
	return out


static func _paint(v: Variant, fallback: String) -> String:
	return String(v) if (v is String and DecalCatalog.PAINTS.has(v)) else fallback


static func _vec3(v: Variant) -> Variant:
	if not (v is Array) or (v as Array).size() != 3:
		return null
	var a: Array = v
	for x: Variant in a:
		if not (x is float or x is int) or is_nan(float(x)) or is_inf(float(x)):
			return null
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
