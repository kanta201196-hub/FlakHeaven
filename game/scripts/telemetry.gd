class_name Telemetry
extends RefCounted
## 3.4: замеры для анализа правок по кросс-проверке (полёт, стрельба, неуязвимость, FPS, ввод).
## Счётчики копятся за вылет и уходят в конец строки лога (RunLog) — а значит, и в отчёт тестера.
## timeline — снимок каждой минуты вылета, компактной строкой.

## Версия набора колонок: меняется — меняется и имя файла лога
const LOG_VER := "l3"
const COLS := ["fps_avg", "fps_low1", "slow_frames", "fps_limit", "vsync", "pad_s", "kbm_s", "scheme_changes",
	"gun_rate_max", "gun_multi_frames", "shots_lead", "hits_lead", "lead_nosol", "swept_hits",
	"roll_uses", "invuln_s", "invuln_chain_max", "nm_through", "hitstops", "hitstop_in_slowmo",
	"speed_avg", "speed_max", "turn_max", "twin_extra", "carpet_road_evo", "course_shelter_skipped", "xp_continue",
	"cam_tilt", "tilt_changes", "tilt28_s", "tilt35_s", "tilt45_s", "tilt0_s"]

var v := {}
var timeline := PackedStringArray()
var _frames := PackedFloat32Array()
var _device := "kbm"
var _inv_chain := 0.0
var _speed_acc := 0.0
var _speed_n := 0
var _next_min := 60.0
var _snap := {}


func reset() -> void:
	v = {}
	timeline = PackedStringArray()
	_frames = PackedFloat32Array()
	_inv_chain = 0.0
	_speed_acc = 0.0
	_speed_n = 0
	_next_min = 60.0
	_snap = {}


func add(k: String, n := 1.0) -> void:
	v[k] = float(v.get(k, 0.0)) + n


func maxv(k: String, n: float) -> void:
	v[k] = maxf(float(v.get(k, 0.0)), n)


func g(k: String) -> float:
	return float(v.get(k, 0.0))


## Последнее устройство ввода (геймпад или клавиатура/мышь) — для доли времени
func input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.3):
		_device = "pad"
	elif event is InputEventKey or event is InputEventMouseButton:
		_device = "kbm"


## Каждый кадр вылета (игра не на паузе)
func frame(delta: float, m: Main) -> void:
	var real := delta / maxf(Engine.time_scale, 0.01)
	_frames.append(real)
	if real > 0.05:
		add("slow_frames")
	add(_device + "_s", real)
	add("tilt%d_s" % int(round(Tuning.g("cam_tilt"))), real)   # B-47: сколько секунд при каждом наклоне
	var p := m.player
	if not is_instance_valid(p):
		return
	if p.roll_t > 0.0 or p.invuln > 0.0:
		add("invuln_s", delta)
		_inv_chain += delta
		maxv("invuln_chain_max", _inv_chain)
	else:
		_inv_chain = 0.0
	var spd := p.velocity.length()
	_speed_acc += spd
	_speed_n += 1
	maxv("speed_max", spd)
	maxv("turn_max", rad_to_deg(p.turn_rate()))
	if m.run_time >= _next_min:
		_minute(m)
		_next_min += 60.0


func _minute(m: Main) -> void:
	var p := m.player
	var now := {"dealt": m.total("dealt"), "taken": m.total("taken"), "kills": m.kills, "shots": m.shots, "hits": m.hits,
		"nm": m.near_misses, "inv": g("invuln_s"), "frames": _frames.size()}
	var d := {}
	for k in now:
		d[k] = float(now[k]) - float(_snap.get(k, 0.0))
	var ft := 0.0
	for i in range(int(_snap.get("frames", 0)), _frames.size()):
		ft += _frames[i]
	var fps := float(d["frames"]) / maxf(ft, 0.001)
	var main_tag := 0
	if p.has_course():
		main_tag = p.tag(Cards.syn_def(p, p.course)["tag"])
	timeline.append("%d:L%d hp%d fps%d dmg%d tk%d k%d sh%d/%d nm%d inv%.1f v%d syn%d c=%s/%d t%d" % [int(m.run_time / 60.0), m.level,
		int(round(100.0 * p.hp / maxf(p.max_hp, 1.0))), int(round(fps)), int(d["dealt"]), int(d["taken"]), int(d["kills"]),
		int(d["shots"]), int(d["hits"]), int(d["nm"]), float(d["inv"]), int(round(p.velocity.length())), p.syn.size(),
		p.course if p.course != "" else "-", main_tag, int(round(Tuning.g("cam_tilt")))])
	_snap = now


## Значения колонок COLS для строки лога
func row(m: Main) -> PackedStringArray:
	if is_instance_valid(m.player) and m.run_time - (_next_min - 60.0) >= 5.0:
		_minute(m) # хвост вылета после последней полной минуты
		_next_min += 60.0
	var sorted := _frames.duplicate()
	sorted.sort()
	var total := 0.0
	for f in _frames:
		total += f
	v["fps_avg"] = _frames.size() / maxf(total, 0.001)
	# «1 % худших»: FPS по кадру на границе 99-го процентиля длительности
	v["fps_low1"] = 1.0 / maxf(sorted[mini(int(sorted.size() * 0.99), sorted.size() - 1)], 0.001) if sorted.size() > 0 else 0.0
	v["fps_limit"] = float(Settings.FPS_LIMITS[Settings.fps_limit])
	v["vsync"] = 1.0 if Settings.vsync else 0.0
	v["speed_avg"] = _speed_acc / maxf(_speed_n, 1)
	v["cam_tilt"] = Tuning.g("cam_tilt")
	var out := PackedStringArray()
	for k in COLS:
		var x := g(k)
		out.append(("%.1f" % x) if k in ["invuln_s", "invuln_chain_max", "pad_s", "kbm_s", "tilt28_s", "tilt35_s", "tilt45_s", "tilt0_s"] else str(int(round(x))))
	return out
