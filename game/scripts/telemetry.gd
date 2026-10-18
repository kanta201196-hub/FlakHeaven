class_name Telemetry
extends RefCounted
## 3.4: замеры для анализа правок по кросс-проверке (полёт, стрельба, неуязвимость, FPS, ввод).
## Счётчики копятся за вылет и уходят в конец строки лога (RunLog) — а значит, и в отчёт тестера.
## timeline — снимок каждой минуты вылета, компактной строкой.

## Версия набора колонок: меняется — меняется и имя файла лога
const LOG_VER := "l6"   # l6 (тест 3.5-s5): колонка aces перед timeline
const COLS := ["fps_avg", "fps_low1", "slow_frames", "fps_limit", "vsync", "pad_s", "kbm_s", "scheme_changes",
	"gun_rate_max", "gun_multi_frames", "shots_lead", "hits_lead", "lead_nosol", "swept_hits",
	"roll_uses", "invuln_s", "invuln_chain_max", "nm_through", "hitstops", "hitstop_in_slowmo",
	"speed_avg", "speed_max", "turn_max", "twin_extra", "carpet_road_evo", "course_shelter_skipped", "xp_continue",
	"cam_tilt", "tilt_changes", "tilt28_s", "tilt35_s", "tilt45_s", "tilt0_s",
	# T4-03: 3D-картинка и производительность (рельеф, модели биома, тени, качество графики)
	"gfx_start", "gfx", "gfx_drops", "plane_shadow", "tris_avg", "tris_max", "draws_avg", "draws_max", "vram_mb",
	"nodes_max", "enemies_max", "load_ms", "chunks", "chunk_ms_max",
	# 3.5: время жизни асов (с появления до гибели), РУД вернули принудительно, залпы ловушек «Кита», разрешение 3D
	"boss_n", "boss_life_avg", "boss_life_min", "boss_life_max", "throttle_locks", "flare_salvos", "scale3d",
	"dive_uses", "dive_dodged",
	# 3.5 (тред «ИИ врагов и активности»): топливо и заправщик (стыковки штанги), фазы босса «Крепость»
	"fuel_ab_s", "fuel_empty_s", "fuel_fill_s", "fuel_refuels", "fuel_tankers_missed", "fuel_docks", "fuel_undocks",
	"fortress_points", "fortress_phase2_s", "fortress_phase3_s",
	# 3.5 (тред «ИИ врагов и активности»): уклонения врагов, их ловушки и уведённые ими ракеты, сбитые ПВО наши ракеты
	"enemy_evades", "enemy_flares", "enemy_flared_missiles", "aa_shot_down",
	# 3.5: ракеты игрока в воздухе (В-В + НАР; ориентир ≤ 12), перенацеливания ГСН, самоликвидации; звание и черта экипажа
	"msl_air_avg", "msl_air_max", "msl_retarget", "msl_lost", "crew_rank", "crew_xp_lvl", "callsign_idx", "plane_lvl",
	# 3.5: бой на 3D-моделях — сколько самолётов в кадре нарисовано моделями (макс.) и их треугольники
	"units_model_max", "model_tris_max",
	# A-03: наземный конвой — сожжено машин и грузовиков, ушло грузовиков, колонн разбито целиком
	"convoy_vehicles_killed", "convoy_trucks_killed", "convoy_trucks_escaped", "convoy_done"]

## T4-04: автоснижение качества — окна по 20 с с 5-й секунды; FPS ниже порога → пресет ниже (до 3 раз за вылет)
const AUTO_FPS := 35.0
const AUTO_WIN := 20.0

var v := {}
var timeline := PackedStringArray()
var _frames := PackedFloat32Array()
var _device := "kbm"
var _inv_chain := 0.0
var _speed_acc := 0.0
var _speed_n := 0
var _next_min := 60.0
var _snap := {}
var _t0 := 0
var _rs_n := 0            # замеров счётчиков отрисовки
var _auto_t := 0.0        # время и кадры текущего окна автоснижения
var _auto_f := 0
var _auto_win := 0


func reset() -> void:
	v = {}
	timeline = PackedStringArray()
	_frames = PackedFloat32Array()
	_inv_chain = 0.0
	_speed_acc = 0.0
	_speed_n = 0
	_next_min = 60.0
	_snap = {}
	_t0 = Time.get_ticks_msec()
	_rs_n = 0
	_auto_t = 0.0
	_auto_f = 0
	_auto_win = 0
	v["gfx_start"] = float(Settings.gfx)


func add(k: String, n := 1.0) -> void:
	v[k] = float(v.get(k, 0.0)) + n


func maxv(k: String, n: float) -> void:
	v[k] = maxf(float(v.get(k, 0.0)), n)


func boss_killed(life: float) -> void:
	add("boss_n")
	add("boss_life_sum", life)
	v["boss_life_min"] = minf(float(v.get("boss_life_min", life)), life)
	maxv("boss_life_max", life)


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
	if _frames.size() == 3:
		v["load_ms"] = float(Time.get_ticks_msec() - _t0)   # от старта вылета до третьего кадра: рельеф и модели вокруг
	if _frames.size() % 15 == 0:
		_render_stats(m)
	_auto_gfx(real, m)
	var p := m.player
	if not is_instance_valid(p):
		return
	if p.roll_inv > 0.0 or p.invuln > 0.0:
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
	var air := m.projectiles.pmissiles.size() + m.projectiles.rockets.size()
	add("msl_air_sum", air)
	maxv("msl_air_max", air)
	if m.run_time >= _next_min:
		_minute(m)
		_next_min += 60.0


## Счётчики отрисовки за прошлый кадр — раз в 15 кадров
func _render_stats(m: Main) -> void:
	var tris := float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	var draws := float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	_rs_n += 1
	add("tris_sum", tris)
	add("draws_sum", draws)
	maxv("tris_max", tris)
	maxv("draws_max", draws)
	maxv("vram_mb", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0)
	maxv("nodes_max", Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	if Render3D.I != null:
		var mc := Render3D.I.model_units()
		maxv("units_model_max", mc.x)
		maxv("model_tris_max", mc.y)
	if _rs_n % 4 == 0:
		maxv("enemies_max", m.get_tree().get_nodes_in_group("enemies").size())


## Кусок рельефа с моделями собран за ms (Terrain3D)
func chunk_built(ms: float) -> void:
	add("chunks")
	maxv("chunk_ms_max", ms)


## Автоснижение «Качества графики», пока игрок не выбрал его сам
func _auto_gfx(real: float, m: Main) -> void:
	if not Settings.gfx_auto or Settings.gfx == 0 or _auto_win >= 3 or m.run_time < 5.0 or m._autotest:
		return
	_auto_t += real
	_auto_f += 1
	if _auto_t < AUTO_WIN:
		return
	var fps := _auto_f / _auto_t
	_auto_t = 0.0
	_auto_f = 0
	_auto_win += 1
	var cap := float(Settings.FPS_LIMITS[Settings.fps_limit])
	if fps >= AUTO_FPS or (cap > 0.0 and cap < AUTO_FPS + 5.0):
		_auto_win = 3   # FPS в норме — больше не проверяем в этом вылете
		return
	Settings.gfx -= 1
	Settings.save_settings()
	Settings.apply_gfx()
	add("gfx_drops")
	m.show_banner("Качество графики снижено до «%s» (%d к/с). Изменить: «Настройки» → «Графика»" % [Settings.GFX[Settings.gfx], int(fps)], 5.0)


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
	timeline.append("%d:L%d hp%d fps%d dmg%d tk%d k%d sh%d/%d nm%d inv%.1f v%d syn%d c=%s/%d t%d g%d tr%dk e%d pk%.1f" % [int(m.run_time / 60.0), m.level,
		int(round(100.0 * p.hp / maxf(p.max_hp, 1.0))), int(round(fps)), int(d["dealt"]), int(d["taken"]), int(d["kills"]),
		int(d["shots"]), int(d["hits"]), int(d["nm"]), float(d["inv"]), int(round(p.velocity.length())), p.syn.size(),
		p.course if p.course != "" else "-", main_tag, int(round(Tuning.g("cam_tilt"))), Settings.gfx,
		int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1000),
		m.get_tree().get_nodes_in_group("enemies").size(), m.spawner.pressure_k if is_instance_valid(m.spawner) else 1.0])
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
	v["gfx"] = float(Settings.gfx)
	v["plane_shadow"] = Tuning.g("plane_shadow")
	v["tris_avg"] = g("tris_sum") / maxf(_rs_n, 1)
	v["draws_avg"] = g("draws_sum") / maxf(_rs_n, 1)
	v["boss_life_avg"] = g("boss_life_sum") / maxf(g("boss_n"), 1.0)
	v["scale3d"] = 100.0 * float(Render3D.GFX_SCALE[clampi(Settings.gfx, 0, 3)])
	v["msl_air_avg"] = g("msl_air_sum") / maxf(_speed_n, 1)
	v["crew_rank"] = float(Profile.crew_lvl(m.cls_id))
	v["plane_lvl"] = float(m.player.plane_lvl) if is_instance_valid(m.player) else 0.0
	v["crew_xp_lvl"] = float(Profile.xp_lvl(m.cls_id))
	v["callsign_idx"] = float((Profile.CALLSIGNS[m.cls_id] as Array).find(Profile.cls(m.cls_id)["callsign"]))
	var out := PackedStringArray()
	for k in COLS:
		var x := g(k)
		out.append(("%.1f" % x) if k in ["msl_air_avg", "invuln_s", "invuln_chain_max", "pad_s", "kbm_s", "tilt28_s", "tilt35_s", "tilt45_s", "tilt0_s", "boss_life_avg", "boss_life_min", "boss_life_max"] else str(int(round(x))))
	return out
