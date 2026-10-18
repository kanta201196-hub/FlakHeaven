class_name Sfx
extends Node
## Звуки-заглушки, сгенерированные кодом (без файлов): выстрел, попадание, взрыв,
## захват цели ракетой, бочка, форсаж и гул двигателя, который меняется со скоростью.
## Звуки из файлов в audio/ заменяют их по имени события (см. audio/README.md).

const RATE := 22050

var streams := {}
## Пилот звука (18.10): голоса — AudioStreamPlayer2D, чтобы звук из точки боя шёл слева или справа
## (громкость от расстояния не меняется — только панорама). Голосов 24, у частых звуков свой предел.
var players: Array[AudioStreamPlayer2D] = []
var _voice_ev: Array[String] = []   # какое событие играет голос
var _voice_t: Array[float] = []     # когда начал (для замены самого старого)
var _duck := 0.0                    # приглушение музыки, дБ (возвращается само)
var _heat := 0.0                    # накал боя 0…1 по звукам боя (взрывы, огонь по нам, захваты), сам остывает
var _heat_s := 0.0                  # он же, сглаженный: от него открывается музыка боя
var engine: AudioStreamPlayer
var engine_jet: AudioStream       # гул реактивного двигателя
var engine_prop: AudioStream      # правка 3.5-s4: четыре винтовых мотора («Кит 1»), если есть файл
var _eng_pitch := 1.0
var _eng_db := -22.0


func _ready() -> void:
	streams["shot"] = _tone(950.0, 0.05, 0.35, 60.0, 0.5)
	streams["hit"] = _tone(320.0, 0.07, 0.6, 50.0, 0.6)
	streams["explode"] = _tone(70.0, 0.45, 0.9, 7.0, 0.9)
	streams["player_hit"] = _tone(140.0, 0.3, 0.7, 10.0, 0.9)
	streams["lock"] = _tone(1300.0, 0.18, 0.0, 4.0, 0.5, true)
	streams["launch"] = _tone(200.0, 0.3, 0.8, 8.0, 0.6)
	streams["roll"] = _tone(500.0, 0.2, 0.9, 12.0, 0.4)
	streams["afterburner"] = _tone(90.0, 0.5, 0.8, 4.0, 0.6)
	streams["pickup"] = _tone(1500.0, 0.04, 0.0, 60.0, 0.25, true)
	streams["levelup"] = _tone(660.0, 0.35, 0.0, 6.0, 0.5, true)
	streams["card"] = _tone(880.0, 0.12, 0.1, 20.0, 0.5, true)
	streams["boss"] = _tone(110.0, 1.2, 0.3, 2.0, 0.8, true)
	streams["evac"] = _tone(520.0, 0.6, 0.0, 3.0, 0.5, true)
	streams["bomb"] = _tone(55.0, 0.5, 0.95, 6.0, 0.9)
	_setup_buses()
	var dk := Ducker.new()
	dk.sfx = self
	dk.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(dk)
	for i in VOICES:
		var a := AudioStreamPlayer2D.new()
		a.bus = "SFX"
		a.attenuation = 0.0          # без затухания: баланс громкости — как в вызовах play()
		a.max_distance = 100000.0
		a.panning_strength = 1.6     # заметная, но не жёсткая панорама (общая сила 0,5 в проекте)
		add_child(a)
		players.append(a)
		_voice_ev.append("")
		_voice_t.append(0.0)
	engine = AudioStreamPlayer.new()
	engine.stream = _tone(55.0, 1.0, 0.45, 0.0, 0.4, false, true)
	engine.volume_db = -22.0
	engine.bus = "SFX"
	add_child(engine)
	_load_overrides()
	# Гул включается только в полёте (set_engine), в меню и ангаре его нет


## Замена звуков файлами: положите в папку audio/ файл с именем события
## (shot.ogg, explode.wav …) или несколько вариантов (explode_1.ogg, explode_2.ogg) —
## они заменят заглушку, варианты играются случайно. engine.* — зацикленный гул двигателя.
var variants := {}


func _load_overrides() -> void:
	for name in streams.keys() + FALLBACK.keys() + ["engine", "engine_prop"]:
		var found: Array = []
		for suffix in [""] + range(1, 9).map(func(i): return "_%d" % i):
			for ext in ["ogg", "wav", "mp3"]:
				var path := "res://audio/%s%s.%s" % [name, suffix, ext]
				if ResourceLoader.exists(path):
					var st = load(path)
					if st != null:
						found.append(st)
		if found.is_empty():
			continue
		if name == "engine" or name == "engine_prop":
			var e = found[0]
			if e is AudioStreamOggVorbis or e is AudioStreamMP3:
				e.loop = true
			elif e is AudioStreamWAV:
				e.loop_mode = AudioStreamWAV.LOOP_FORWARD
				e.loop_end = int(e.get_length() * e.mix_rate)
			if name == "engine":
				engine.stream = e
				engine_jet = e
			else:
				engine_prop = e
		else:
			variants[name] = found
	if not variants.is_empty():
		print("Sfx: заменены звуки ", variants.keys())


## Тонкие события: если для них нет своего файла, играет общий звук-заглушка.
## Так можно постепенно заменять звуки — например, сначала один «shot», потом отдельно gun_fire, turret_fire…
const KEEP_PITCH := ["gate", "pickup"]
const FALLBACK := {
	"gun_fire": "shot", "gunpod_fire": "shot", "turret_fire": "shot", "enemy_fire": "shot", "flare": "shot",
	"aam_launch": "launch", "rocket_launch": "launch", "missile_enemy": "launch", "bomb_drop": "launch",
	"explode_big": "explode", "player_explode": "explode", "shield_break": "explode",
	"pass_hit": "hit", "near_miss": "roll", "combat_turn": "roll", "shield": "lock", "radio": "lock",
	"gate": "evac", "repair": "levelup", "ui_ban": "player_hit",
	# 3.5: свои события для новых механик; пока нет файла — играет прежний звук
	"dive": "roll", "synergy": "boss", "cargo": "evac",
	"fuel_low": "lock", "fuel_empty": "lock", "tanker_call": "evac", "tanker_down": "shield_break",
	"boom_dock": "lock", "boom_undock": "lock", "refuel_done": "evac",
	"aa_alert": "lock", "sam_lock": "lock", "sam_launch": "missile_enemy", "aa_intercept": "enemy_fire",
	"fortress_part": "shield_break", "fortress_ring": "enemy_fire",
}


const VOICES := 24
## Сколько копий звука может звучать одновременно; новая копия сверх предела заменяет самую старую.
## Остальные события — до 4 копий.
const VOICE_CAP := {
	"gun_fire": 3, "gunpod_fire": 2, "turret_fire": 2, "enemy_fire": 4, "hit": 4, "pickup": 3,
	"explode": 5, "explode_big": 3, "bomb": 4, "aam_launch": 3, "rocket_launch": 3, "card": 2,
}
## Важные сигналы: если свободных голосов нет, забирают голос у самого старого обычного звука
## (раньше в плотном бою писк захвата и попадание по игроку могли просто не прозвучать).
const PRIORITY := ["lock", "missile_enemy", "sam_lock", "sam_launch", "aa_alert", "player_hit", "player_explode",
	"fuel_low", "fuel_empty", "boss", "levelup", "evac", "gate", "tanker_down", "shield_break", "radio", "card"]
## Музыка под накал боя (18.10): каждый звук боя добавляет накала, за ~15 с без боя он остывает.
## Спокойно — музыка боя глуше (срез верха до ~900 Гц) и на 4 дБ тише, в свалке — полный звук.
## У аса и в меню музыка всегда полная.
const HEAT := {"enemy_fire": 0.02, "hit": 0.01, "explode": 0.06, "explode_big": 0.2, "bomb": 0.05,
	"player_hit": 0.15, "lock": 0.1, "missile_enemy": 0.12, "aa_alert": 0.15, "sam_lock": 0.15, "sam_launch": 0.1}
const HEAT_COOL := 0.07   # накал в секунду
const CALM_CUT_HZ := 900.0
const CALM_DB := -4.0
## Крупные события ненадолго приглушают музыку (дБ), чтобы удар был слышен
const DUCK := {"explode_big": 4.0, "bomb": 3.0, "player_hit": 3.0, "player_explode": 8.0, "tanker_down": 6.0,
	"fortress_part": 4.0, "boss": 4.0}


## pos — точка в мире боя: звук смещается влево/вправо по положению на экране. Без pos — по центру.
func play(sound: String, db := 0.0, pitch := 1.0, pos := Vector2.INF) -> void:
	if not variants.has(sound) and not streams.has(sound):
		if FALLBACK.has(sound):
			play(FALLBACK[sound], db, pitch, pos)
		return
	db += Tuning.g("sfx_db")
	# Для звуков из файлов высоту тона не трогаем (её подбирали под заглушки) — кроме «лесенок»
	if variants.has(sound) and not KEEP_PITCH.has(sound):
		pitch = 1.0
	var a := _voice(sound)
	if a == null:
		return
	var i := players.find(a)
	_voice_ev[i] = sound
	_voice_t[i] = Time.get_ticks_msec() / 1000.0
	a.stream = (variants[sound] as Array).pick_random() if variants.has(sound) else streams[sound]
	a.volume_db = db
	a.pitch_scale = pitch * randf_range(0.94, 1.06)
	var c := _screen_center()
	a.global_position = c if pos == Vector2.INF else pos
	a.play()
	if DUCK.has(sound):
		_duck = maxf(_duck, DUCK[sound])
	_heat = minf(1.0, _heat + HEAT.get(sound, 0.0))


## Голос для звука: свободный; сверх предела копий — самый старый того же звука;
## для важного сигнала — самый старый обычный. Нет голоса — звук пропускается.
func _voice(sound: String) -> AudioStreamPlayer2D:
	var cap: int = VOICE_CAP.get(sound, 4)
	var same := 0
	var oldest_same := -1
	var oldest_any := -1
	var free := -1
	for i in players.size():
		if not players[i].playing:
			if free < 0:
				free = i
			continue
		if _voice_ev[i] == sound:
			same += 1
			if oldest_same < 0 or _voice_t[i] < _voice_t[oldest_same]:
				oldest_same = i
		elif not PRIORITY.has(_voice_ev[i]) and (oldest_any < 0 or _voice_t[i] < _voice_t[oldest_any]):
			oldest_any = i
	if same >= cap and oldest_same >= 0:
		players[oldest_same].stop()
		return players[oldest_same]
	if free >= 0:
		return players[free]
	if PRIORITY.has(sound) and oldest_any >= 0:
		players[oldest_any].stop()
		return players[oldest_any]
	return null


## Центр экрана в координатах боя (туда ставится звук без точки — он звучит по центру)
func _screen_center() -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return Vector2.ZERO
	return vp.get_canvas_transform().affine_inverse() * (vp.get_visible_rect().size * 0.5)


## Шины: SFX (лёгкий компрессор) и Music → Master с лимитером, чтобы сумма взрывов не хрипела
func _setup_buses() -> void:
	for bus_name in ["SFX", "Music"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var b := AudioServer.bus_count - 1
			AudioServer.set_bus_name(b, bus_name)
			AudioServer.set_bus_send(b, "Master")
			if bus_name == "SFX":
				var comp := AudioEffectCompressor.new()
				comp.threshold = -14.0
				comp.ratio = 3.0
				comp.attack_us = 2000.0
				comp.release_ms = 180.0
				AudioServer.add_bus_effect(b, comp)
			else:
				var lp := AudioEffectLowPassFilter.new()
				lp.cutoff_hz = 20000.0
				AudioServer.add_bus_effect(b, lp)
	var has_lim := false
	for e in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, e) is AudioEffectHardLimiter:
			has_lim = true
	if not has_lim:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -1.0
		lim.release = 0.12
		AudioServer.add_bus_effect(0, lim)


## Приглушение музыки уходит за полсекунды–секунду; считается и на паузе (выбор карточки),
## иначе музыка осталась бы тише на всё время паузы.
class Ducker extends Node:
	var sfx: Sfx
	func _process(delta: float) -> void:
		var mb := AudioServer.get_bus_index("Music")
		if mb < 0:
			return
		sfx._duck = move_toward(sfx._duck, 0.0, delta * 6.0)
		sfx._heat = maxf(0.0, sfx._heat - delta * Sfx.HEAT_COOL)
		sfx._heat_s = lerpf(sfx._heat_s, sfx._heat, 1.0 - exp(-delta * 1.5))
		var open := 1.0 if sfx._music_track != "battle" else pow(sfx._heat_s, 0.7)
		var lp := AudioServer.get_bus_effect(mb, 0) as AudioEffectLowPassFilter
		if lp != null:
			lp.cutoff_hz = Sfx.CALM_CUT_HZ * pow(20000.0 / Sfx.CALM_CUT_HZ, open)
		AudioServer.set_bus_volume_db(mb, -sfx._duck + Sfx.CALM_DB * (1.0 - open))


## Гул двигателя. speed_ratio — скорость / крейсерская, ab — форсаж 0…1, prop — винтовой самолёт.
## Правка 3.5-s4: тон и громкость меняются плавно (без скачков на виражах), на форсаже двигатель
## заметно выше и громче; у винтового — свой звук и узкий диапазон тона (винт не «визжит»).
func set_engine(speed_ratio: float, alive: bool, ab := 0.0, prop := false, delta := 0.016) -> void:
	if engine == null:
		return
	if not alive:
		if engine.playing:
			engine.stop()
		return
	var want: AudioStream = engine_prop if prop and engine_prop != null else engine_jet
	if want != null and engine.stream != want:
		engine.stream = want
		engine.stop()
	var r := clampf(speed_ratio, 0.3, 2.0)
	var pitch := (0.9 + 0.18 * r + 0.08 * ab) if prop and engine_prop != null else (0.75 + 0.35 * r + 0.18 * ab)
	var db := -22.0 + 3.0 * clampf(r - 1.0, -1.0, 0.6) + 4.0 * ab
	var k := 1.0 - exp(-delta * 3.0)
	_eng_pitch = lerpf(_eng_pitch, pitch, k)
	_eng_db = lerpf(_eng_db, db, k)
	engine.pitch_scale = clampf(_eng_pitch, 0.5, 2.0)
	engine.volume_db = _eng_db + Tuning.g("sfx_db") + Tuning.g("engine_db")
	if not engine.playing:
		engine.play()


func _tone(freq: float, dur: float, noise: float, decay: float, vol: float, square := false, loop := false) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * decay)
		phase += freq / RATE
		var wave := sin(phase * TAU)
		if square:
			wave = signf(wave) * 0.6
		var s := wave * (1.0 - noise) + randf_range(-1.0, 1.0) * noise
		var v := int(clampf(s * env * vol, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = n
	return w


# ---------- Фон биома ----------
## Тихий цикл под боем: ветер в Нагорье, прибой над морем (файлы audio/ambient_<биом>.ogg).
## Биом переключает set_ambient("sea") — например, при старте вылета в «Архипелаге».
const AMBIENT_DB := -20.0
var ambient_biome := "highland"
var _amb: AudioStreamPlayer
var _amb_name := ""
var _amb_tw: Tween


func set_ambient(biome: String) -> void:
	ambient_biome = biome
	if _amb != null and _amb.playing:
		_amb_name = ""
		_ambient_on(true)


func _ambient_on(on: bool) -> void:
	var want := ("ambient_" + ambient_biome) if on else ""
	if want == _amb_name:
		return
	_amb_name = want
	if _amb == null:
		_amb = AudioStreamPlayer.new()
		_amb.bus = "SFX"
		_amb.volume_db = -60.0
		add_child(_amb)
	if _amb_tw != null and _amb_tw.is_valid():
		_amb_tw.kill()
	_amb_tw = create_tween()
	if want == "":
		_amb_tw.tween_property(_amb, "volume_db", -60.0, 1.5)
		_amb_tw.tween_callback(_amb.stop)
		return
	var path := "res://audio/%s.ogg" % want
	if not ResourceLoader.exists(path):
		_amb.stop()
		return
	var st = load(path)
	if st is AudioStreamOggVorbis:
		st.loop = true
	_amb.stream = st
	_amb.volume_db = -60.0
	_amb.play()
	_amb_tw.tween_property(_amb, "volume_db", AMBIENT_DB + Tuning.g("sfx_db"), 2.0)


# ---------- Музыка ----------
## Файлы audio/music_menu.*, music_battle.*, music_boss.* (зацикливаются).
## Нет файла — тишина. Переключение плавное (кроссфейд 1,5 с).
var _music: Array[AudioStreamPlayer] = []
var _music_cur := 0
var _music_track := ""
var _music_streams := {}
var _music_tw: Tween


## Ползунок до упора влево — музыка выключена
func music_db() -> float:
	var db := Tuning.g("music_db")
	return -80.0 if db <= -40.0 else db


## Ползунок «Музыка» в настройках: громкость играющего трека меняется сразу
func apply_music_volume() -> void:
	if _music.is_empty() or _music_track == "":
		return
	if _music_tw != null and _music_tw.is_valid():
		_music_tw.kill()
	for i in _music.size():
		var a := _music[i]
		if i == _music_cur and a.playing:
			a.volume_db = music_db()
		else:
			a.volume_db = -80.0
			a.stop()


func _init_music() -> void:
	for i in 2:
		var a := AudioStreamPlayer.new()
		a.volume_db = -80.0
		a.bus = "Music"
		a.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(a)
		_music.append(a)
	for t in ["menu", "battle", "boss", "result"]:
		var found: Array = []
		for suffix in [""] + range(1, 6).map(func(i): return "_%d" % i):
			for ext in ["ogg", "mp3", "wav"]:
				var path := "res://audio/music_%s%s.%s" % [t, suffix, ext]
				if ResourceLoader.exists(path):
					var st = load(path)
					if st is AudioStreamOggVorbis or st is AudioStreamMP3:
						st.loop = true
					elif st is AudioStreamWAV:
						st.loop_mode = AudioStreamWAV.LOOP_FORWARD
						st.loop_end = int(st.get_length() * st.mix_rate)
					found.append(st)
		if not found.is_empty():
			_music_streams[t] = found
	if not _music_streams.is_empty():
		print("Sfx: музыка ", _music_streams.keys())


func music(track: String) -> void:
	if _music.is_empty():
		_init_music()
	_ambient_on(track == "battle" or track == "boss")
	if track == _music_track:
		return
	_music_track = track
	var old := _music[_music_cur]
	_music_cur = 1 - _music_cur
	var nw := _music[_music_cur]
	if _music_tw != null and _music_tw.is_valid():
		_music_tw.kill()
	var tw := create_tween().set_parallel(true)
	_music_tw = tw
	tw.tween_property(old, "volume_db", -80.0, 1.5)
	if track == "result" and not _music_streams.has("result"):
		track = "menu"
	if _music_streams.has(track):
		nw.stream = (_music_streams[track] as Array).pick_random() # несколько треков боя — случайный
		nw.volume_db = -60.0
		nw.play()
		tw.tween_property(nw, "volume_db", music_db(), 1.5)
