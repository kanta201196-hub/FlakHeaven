class_name Sfx
extends Node
## Звуки-заглушки, сгенерированные кодом (без файлов): выстрел, попадание, взрыв,
## захват цели ракетой, бочка, форсаж и гул двигателя, который меняется со скоростью.
## Позже заменяются на звуки от фрилансера — названия событий останутся теми же.

const RATE := 22050

var streams := {}
var players: Array[AudioStreamPlayer] = []
var engine: AudioStreamPlayer


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
	for i in 12:
		var a := AudioStreamPlayer.new()
		add_child(a)
		players.append(a)
	engine = AudioStreamPlayer.new()
	engine.stream = _tone(55.0, 1.0, 0.45, 0.0, 0.4, false, true)
	engine.volume_db = -22.0
	add_child(engine)
	_load_overrides()
	engine.play()


## Замена звуков файлами: положите в папку audio/ файл с именем события
## (shot.ogg, explode.wav …) или несколько вариантов (explode_1.ogg, explode_2.ogg) —
## они заменят заглушку, варианты играются случайно. engine.* — зацикленный гул двигателя.
var variants := {}


func _load_overrides() -> void:
	for name in streams.keys() + FALLBACK.keys() + ["engine"]:
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
		if name == "engine":
			var e = found[0]
			if e is AudioStreamOggVorbis or e is AudioStreamMP3:
				e.loop = true
			elif e is AudioStreamWAV:
				e.loop_mode = AudioStreamWAV.LOOP_FORWARD
				e.loop_end = int(e.get_length() * e.mix_rate)
			engine.stream = e
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
}


func play(sound: String, db := 0.0, pitch := 1.0) -> void:
	if not variants.has(sound) and not streams.has(sound):
		if FALLBACK.has(sound):
			play(FALLBACK[sound], db, pitch)
		return
	db += Tuning.g("sfx_db")
	# Для звуков из файлов высоту тона не трогаем (её подбирали под заглушки) — кроме «лесенок»
	if variants.has(sound) and not KEEP_PITCH.has(sound):
		pitch = 1.0
	for a in players:
		if not a.playing:
			a.stream = (variants[sound] as Array).pick_random() if variants.has(sound) else streams[sound]
			a.volume_db = db
			a.pitch_scale = pitch * randf_range(0.94, 1.06)
			a.play()
			return


func set_engine(speed_ratio: float, alive: bool) -> void:
	if engine == null:
		return
	engine.pitch_scale = clampf(0.7 + 0.5 * speed_ratio, 0.5, 2.0)
	engine.volume_db = (-22.0 + Tuning.g("sfx_db") + Tuning.g("engine_db")) if alive else -80.0


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


# ---------- Музыка ----------
## Файлы audio/music_menu.*, music_battle.*, music_boss.* (зацикливаются).
## Нет файла — тишина. Переключение плавное (кроссфейд 1,5 с).
var _music: Array[AudioStreamPlayer] = []
var _music_cur := 0
var _music_track := ""
var _music_streams := {}


func _init_music() -> void:
	for i in 2:
		var a := AudioStreamPlayer.new()
		a.volume_db = -80.0
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
	if track == _music_track:
		return
	_music_track = track
	var old := _music[_music_cur]
	_music_cur = 1 - _music_cur
	var nw := _music[_music_cur]
	var tw := create_tween().set_parallel(true)
	tw.tween_property(old, "volume_db", -80.0, 1.5)
	if track == "result" and not _music_streams.has("result"):
		track = "menu"
	if _music_streams.has(track):
		nw.stream = (_music_streams[track] as Array).pick_random() # несколько треков боя — случайный
		nw.volume_db = -60.0
		nw.play()
		tw.tween_property(nw, "volume_db", Tuning.g("music_db"), 1.5)
