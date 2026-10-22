class_name MainDebug
extends RefCounted
## Отладочные режимы Main: автотест (-- --autotest), скриншоты (--shots), проверки --fxtest,
## --reporttest, --mesatest, стенд картинки --visual (visual_bench.gd). Работают только по флагам командной строки.
## Быстрая проверка правки (--smoke, вместе с --autotest): один вылет одним классом с перемоткой к боссу,
## затем выход с кодом 0 («SMOKE: ok») или 1 («SMOKE: FAIL»). Обёртка с поиском SCRIPT ERROR — tools/ci/smoke.sh.

var m: Main
var _fx_t := 0.0
var _fx_at := 0.0
var _fx_fired := false
var _autotest_t := 0.0
var _visual: VisualBench
var _boom: BoomBench


func _init(main: Main) -> void:
	m = main
	# Main._args ещё не заполнен: флаг читаем напрямую — зерно нужно до создания мира
	if OS.get_cmdline_user_args().has("--visual"):
		VisualBench.seed_world()
		_visual = VisualBench.new(m)
	if OS.get_cmdline_user_args().has("--boombench"):   # 3.5: стенд 3D-взрывов (boom_bench.gd)
		VisualBench.seed_world()
		_boom = BoomBench.new(m)


func process(delta: float) -> void:
	if m._args.has("--exittest") and _exit_test():
		return
	if m._autotest:
		_run_autotest(delta)
		if m._args.has("--smoke"):
			_smoke_check()
	if m._args.has("--shots"):
		_debug_screenshots(delta)
	if m.state == "playing" and m._args.has("--aaflat") and not _shots_done.has("aaflat") and m.run_time > 3.0:
		_shots_done["aaflat"] = true
		_aa_flat_test()
	if _visual != null:
		_visual.process(delta)
	if _boom != null:
		_boom.process(delta)

	if m._args.has("--fxtest") and m.state == "playing" and is_instance_valid(m.player):
		_fx_t += delta
		if _fx_t > 1.0 and not _shots_done.has("fx_a"):
			if not _fx_fired:
				_fx_fired = true
				_fx_at = _fx_t
				var c := m.player.global_position + Vector2(260, -120)
				m.fx.explosion(c, 34.0)
				m.fx.explosion(c + Vector2(-420, 160), 16.0)
				m.projectiles.aoe(c + Vector2(120, 260), 130.0, 0.0, "тест")
			elif _fx_t - _fx_at > 0.12:
				_shot("fx_a")
		elif _shots_done.has("fx_a") and not _shots_done.has("fx_b") and _fx_t - _fx_at > 0.45:
			_shot("fx_b")
		elif _shots_done.has("fx_b") and not _shots_done.has("fx_c") and _fx_t - _fx_at > 1.1:
			_shot("fx_c")
			m.get_tree().quit()


# ---------- Скриншоты для проверки сборки (-- --autotest --god --fast --shots) ----------

var _shot_t := 0.0
var _shots_done := {}


func _shot(name: String) -> void:
	if not m._args.has("--shots") or _shots_done.has(name):
		return
	_shots_done[name] = true
	m.get_viewport().get_texture().get_image().save_png("user://shot_%s.png" % name)
	print("SHOT ", name)


var _ui_phase := 0

## Правки 15–16: длинный вылет без боя — 120 карточек в журнале, пауза (Tab) и итоги.
## godot --path game --rendering-driver opengl3 -- --autotest --shots --uitest
func _ui_test() -> void:
	if _ui_phase == 0 and m.state == "playing" and m.run_time > 2.0:
		var names := ["Ракеты «воздух-воздух»: улучшение", "ГСН «Глазастик»", "Блок НАР: улучшение", "Боевая часть", "Двигатели ракет",
			"Форсаж: доводка", "Механизация крыла", "Форсированный двигатель", "Усиленная БЧ", "Пусковое устройство", "Быстрая перезарядка",
			"Радиостанция «Болтушка»", "Сборщик трофеев", "Осколочная рубашка", "Облегчённый затвор", "Бронебойные снаряды", "Бронеплиты",
			"Бочка: тренировка", "Звено: слётанность — Стриж 1", "Ведомый: «Стриж» — прикрытие", "СВЯЗКА «Карусель» — слот 1",
			"МОДЕРНИЗАЦИЯ: «Ливень»", "МОДЕРНИЗАЦИЯ: «Дятел»", "Боевой разворот: тренировка"]
		var lv := {}
		for i in 120:
			var nm: String = names[i % names.size()] if i < 48 else names[randi() % 18]
			var r: String = Cards.RARITY[randi() % Cards.RARITY.size()]["name"]
			var l := int(lv.get(nm, 1))
			if i >= names.size() and l < 5 and not nm.begins_with("МОДЕРНИЗАЦИЯ") and not nm.begins_with("СВЯЗКА"):
				m.player.cards_log.append("%s (%d → %d) [%s]" % [nm, l, l + 1, r])
				lv[nm] = l + 1
			else:
				m.player.cards_log.append("%s [%s]" % [nm, r])
		m._set_state("paused")
		_ui_phase = 1
	elif _ui_phase == 1 and m.state == "paused" and m._state_t > 0.8:
		_shot("ui_pause")
		m._set_state("playing")
		# итоги как после длинного вылета: урон по источникам, полученный, сбитые
		m.run_time = 975.0
		m.stats["dealt"] = {"ракеты В-В": 263378.0, "турели": 70320.0, "уязвимые точки «Крепости»": 64448.0, "курсовое (авто)": 60960.0,
			"ведомые: стриж": 41590.0, "связка: стальной ёж": 29627.0, "ведомые: грачонок": 26890.0, "НАР": 15360.0, "бомбы": 9000.0}
		m.stats["taken"] = {"таран": 292.0, "пули": 1010.0, "ракеты": 120.0}
		m.stats["taken_by"] = {"дроны": 536.0, "перехватчики": 300.0, "ракетоносцы": 45.0, "ПВО": 51.0, "ас-соперник": 12.0, "асы": 355.0, "ПЗРК": 15.0, "пикап": 12.0}
		m.stats["taken_kind"] = {"пушки истребителей": 836.0, "пушки асов": 162.0, "пулемёт пикапа": 12.0, "ракеты самолётов": 45.0, "ЗРК": 60.0, "ПЗРК": 15.0}
		m.stats["kills_by"] = {"дроны": 2890.0, "перехватчики": 519.0, "ракетоносцы": 43.0, "асы": 3.0}
		m.kills = 3455
		m.bosses_killed = 3
		m.shots = 4000
		m.hits = 1480
		m.on_evac_success()
		_ui_phase = 2
	elif _ui_phase == 2 and m.state == "evac" and m.result_t > 4.0:
		_shot("ui_result")
		m.result_tab = 1
		_ui_phase = 3
		_hud_at = Time.get_ticks_msec()
	elif _ui_phase == 3 and Time.get_ticks_msec() - _hud_at > 800:
		_shot("ui_result_dmg")
		m.result_tab = 2
		_ui_phase = 4
		_hud_at = Time.get_ticks_msec()
	elif _ui_phase == 4 and Time.get_ticks_msec() - _hud_at > 800:
		_shot("ui_result_build")
		HudCodex.tab = 3
		m.codex_back = "menu"
		m._set_state("codex")
		_ui_phase = 5
		_hud_at = Time.get_ticks_msec()
	elif _ui_phase == 5 and Time.get_ticks_msec() - _hud_at > 800:
		_shot("ui_codex_info")
		m.get_tree().quit()


var _hud_phase := 0

## Читаемость HUD: 15-я минута, 80 карточек (подвесы, звено, связки), кадр боя.
## godot --path game --rendering-driver opengl3 -- --autotest --shots --hudtest
func _hud_test() -> void:
	var p := m.player
	if _hud_phase == 0 and m.run_time > 2.0:
		seed(7)
		for i in 80:
			if Cards.need_course(p):
				var co := Cards.course_options(p)
				p.course = co[0] if not co.is_empty() else "-"
				continue
			var offs := Cards.offer(p, 3, {}, {}, 0)
			if offs.is_empty():
				break
			Cards.apply(p, offs[randi() % offs.size()])
		m.level = 84
		m.kills = 8730
		m.parts = 38386.0
		m.run_time = 905.0
		m.streak = 120
		m.streak_t = 2.0
		_hud_phase = 1
		_hud_at = Time.get_ticks_msec()
	elif _hud_phase == 1 and Time.get_ticks_msec() - _hud_at > 4500 and m.radio_t <= 0.5:
		m.radio("Барон", "Ещё один охотник? Посмотрим, сколько продержишься.", true)
	elif _hud_phase == 1 and Time.get_ticks_msec() - _hud_at > 6000:
		_shot("hud_late")
		m.get_tree().quit()


var _hud_at := 0


var _rep_phase := 0

## 3.3-t2: отладка — заполнить и отправить отчёт с экрана итогов
func _report_test() -> void:
	if _rep_phase == 0:
		_shot("results_report_btn")
		m.report.open()
		m.report._set_rating(4)
		m.report._set_again("Да")
		m.report._boring.text = "Тест: середина вылета однообразная"
		m.report._unclear.text = "Тест: что даёт курс"
		m.report._comment.text = "Тест отправки, кириллица ёЁ, кавычки \" ; и перевод\nстроки"
		_rep_phase = 1
	elif _rep_phase == 1:
		_shot("report_form")
		m.report._send()
		_rep_phase = 2
	elif _rep_phase == 2 and not m.report._busy:
		_shot("report_done")
		print("REPORT status: ", m.report._status.text, " sent=", m.report_sent)
		_rep_phase = 3


var _exit_phase := 0

## После теста 3.5-s7: досрочный выход из паузы в меню — анкета, строка лога «выход», главное меню.
## Запуск: --autotest --exittest --report-url=http://127.0.0.1:PORT (приёмник tools/reports/mock_receiver.py).
## true — автотест на этом кадре не трогаем (идёт анкета).
func _exit_test() -> bool:
	if _exit_phase == 0 and m.state == "playing" and m.run_time > 3.0:
		m.run_time = maxf(m.run_time, 30.0)   # быстрее порога ABORT_MIN_S, чтобы не ждать в медленном режиме кадров
		m._set_state("paused")
		m.ui_click("to_menu")
		print("EXITTEST: report open=%s exit_mode=%s" % [m.report.visible, m.report._exit_mode])
		_exit_phase = 1
		return true
	if _exit_phase == 1:
		m.report._set_ans("why", "Стало скучно")
		m.report._set_ans("diff", "Легко")
		m.report._set_rating(3)
		m.report._liked.text = "Тест: взрывы"
		_exit_phase = 4   # кадр с отмеченными ответами — на следующем шаге
		return true
	if _exit_phase == 4:
		_shot("report_exit")
		m.report._send()
		_exit_phase = 2
		return true
	if _exit_phase == 2:
		if m.state == "menu":
			print("EXITTEST: ok, menu, outcome=%s, row=%d chars" % [m.last_outcome, m.last_log_row.length()])
			_exit_phase = 3
			# для кадра: пустой экран итогов с кнопкой отчёта (подсветка первые секунды)
			m.result_t = 0.0
			m._set_state("dead")
		return true
	if _exit_phase == 3 and m.result_t > 1.0:
		_shot("results_report_btn")
		_exit_phase = 5
		m.get_tree().quit()
	return _exit_phase >= 3


var _mesa_phase := 0
var _mesa_at := 0.0

## 3.3: отладка — ставим самолёт прямо над горой и снимаем кадр (гора не должна пересекать самолёт)
func _mesa_test() -> void:
	if _mesa_phase == 0 and m.run_time > 4.0:
		var CH := Background.CHUNK
		for r in range(0, 12):
			for cx in range(-r, r + 1):
				for cy in range(-r, r + 1):
					var o := m.background.chunk_object(cx, cy)
					if not o.is_empty() and o["name"] == "o_mesa":
						m.player.global_position = o["pos"]
						m.camera.global_position = o["pos"]
						_mesa_phase = 1
						_mesa_at = m.run_time
						print("MESA at ", o["pos"], " size ", o["size"])
						return
	elif _mesa_phase == 1 and m.run_time - _mesa_at > 0.4:
		_shot("mesa_over")
		_mesa_phase = 2


## --aaflat: есть ли на сетке биома равнины под позицию ПВО и куда встают её машины (правка 3.5-s7).
## Склон — машина выше дна долины больше чем на AA_FLAT_H или наклон больше AA_FLAT_K
func _aa_flat_test() -> void:
	var tr := Terrain3D.active()
	if tr == null:
		print("AAFLAT: нет рельефа")
		m.get_tree().quit()
		return
	var flat := 0
	var all := 0
	for j in range(-60, 61):
		for i in range(-60, 61):
			var q := Vector2(i * 150.0, j * 150.0)
			all += 1
			if tr.flat_at(q):
				flat += 1
	print("AAFLAT grid: равнина %.1f %% точек (сетка 150 px, 18 × 18 км)" % (100.0 * flat / all))
	var bad := 0
	var cars := 0
	var worst := 0.0
	var dist := 0.0
	seed(7)
	var t0 := Time.get_ticks_usec()
	for k in 120:
		var at := Vector2.from_angle(randf() * TAU) * randf_range(0.0, 8000.0)
		var site := AASite.new()
		site.setup(at, 1.0)
		dist += site.anchor.distance_to(at)
		for g: GroundTarget in site.targets:
			cars += 1
			var h := tr.height(g.position.x, g.position.y)
			worst = maxf(worst, h)
			if not tr.flat_at(g.position, 0.0):
				bad += 1
				if m._args.has("--verbose-bot"):
					print("AAFLAT bad ", g.variant, " h=%.0f rf=%.0f v=%.0f h0=%.0f" % [h, tr.river_field(g.position.x, g.position.y), tr.valley(g.position.x, g.position.y), tr.height(site.anchor.x, site.anchor.y)])
			g.free()
		site.free()
	print("AAFLAT sites: 120, машин %d, на склоне %d (%.1f %%), макс. высота над дном %.0f px, сдвиг центра в среднем %.0f px, %.1f мс на позицию" % [cars, bad, 100.0 * bad / cars, worst, dist / 120.0, (Time.get_ticks_usec() - t0) / 120000.0])
	m.get_tree().quit()


func _debug_screenshots(delta: float) -> void:
	_shot_t += delta / maxf(Engine.time_scale, 0.01)
	if m._state_t < 0.6:
		return
	if m._args.has("--uitest") and m.state in ["playing", "paused", "evac", "levelup", "codex"]:
		_ui_test()
		return
	if m._args.has("--hudtest") and m.state == "playing":
		_hud_test()
		return
	if m.state == "menu" and m._state_t > 1.0 and m.menu.howto:
		_shot("howto")
		m.menu.close_howto()
	elif m.state == "menu" and m._state_t > 1.0:
		_shot("menu")
	if m.state == "settings":
		_shot("settings")
	if m.state == "campaign":
		_shot("campaign")
	if m.state == "class_select":
		_shot("class")
	if m.state == "levelup" and m.level >= 4:
		_shot("levelup")
	if m.state == "paused":
		_shot("loadout")
	if m.state == "codex":
		_shot("codex")
	if m.state == "playing" and m.run_time > 1.0 and m.run_time < 3.0:
		_shot("biome_banner")
	if m._args.has("--reporttest") and m.state in ["dead", "evac"] and m.result_t > 1.5:
		_report_test()
	if m.state == "playing" and m._args.has("--mesatest"):
		_mesa_test()
	if m.state == "playing" and m.run_time > 25.0:
		_shot("game_early")
	if m.state == "playing" and m.run_time > 100.0:
		_shot("game")
	if m.state == "playing" and m.player.plane_lvl == 2 and m.player._upgrade_flash > 0.6:
		_shot("upgrade")
	if m.state == "playing" and m.boss_alive() and m.run_time > Tuning.g("boss_every") + 6.0:
		_shot("boss")
	if m.state == "playing" and is_instance_valid(m.evac) and m.evac.passed >= 1:
		_shot("evac_zone")
	if m.state == "playing" and is_instance_valid(m.spawner.activity_node):
		var an: Node = m.spawner.activity_node
		if an is AASite and (an as AASite).active and (an as AASite).left() < 5:
			_shot("aa_site")
		if an is RivalAce and (an as Node2D).global_position.distance_to(m.player.global_position) < 500.0:
			_shot("dogfight")
		if an is Transport and (an as Node2D).global_position.distance_to(m.player.global_position) < 450.0:
			_shot("transport")
		if an is Convoy and (an as Convoy).alarm and (an as Node2D).global_position.distance_to(m.player.global_position) < 500.0:
			_shot("convoy")
	if m.state == "playing" and m._args.has("--heli") and m._args.has("--shots"):   # вертолёт «Сарыч» вблизи (проверка по флагу --heli)
		for n in m.get_tree().get_nodes_in_group("enemies"):
			if n is Helicopter and (n as Node2D).global_position.distance_to(m.player.global_position) < 260.0:
				_shot("helicopter")
				break
	if m.state == "playing" and m.spawner != null and m.spawner.fuel != null and is_instance_valid(m.spawner.fuel.tanker) and m.spawner.fuel.tanker.filling:
		_shot("tanker")
	# M-07: демо (--demo) — кадр экрана «Конец демо» перед кадром итогов
	if (m.state == "evac" or m.state == "dead") and m.result_t > 3.5 and Demo.on and not _shots_done.has("demo_end"):
		if Demo.end_open:
			_shot("demo_end")
			Demo.end_open = false
		else:
			Demo.end_open = true
		return
	if (m.state == "evac" or m.state == "dead") and m.result_t > 3.5:
		_shot("result")
		m.get_tree().quit()


# ---------- Быстрая проверка (-- --autotest --smoke [--class=bomber]) ----------
# Вылет: ~40 с обычного боя, перемотка к боссу, 25 с боя с боссом. Лимит по реальному времени — SMOKE_WALL_S.

const SMOKE_WARMUP_S := 40.0
const SMOKE_BOSS_S := 25.0
const SMOKE_WALL_S := 300.0
var _smoke_skipped := false


func _smoke_check() -> void:
	var wall := Time.get_ticks_msec() / 1000.0
	if wall > SMOKE_WALL_S:
		_smoke_end(1, "timeout %.0f s, state %s, run %.1f s" % [wall, m.state, m.run_time])
		return
	if m.state == "dead" or m.state == "evac":
		_smoke_end(0, "%s at %.1f s" % [m.state, m.run_time])
		return
	if m.state != "playing":
		return
	if not _smoke_skipped and m.run_time > SMOKE_WARMUP_S:
		_smoke_skipped = true
		m.run_time = maxf(m.run_time, Tuning.g("boss_every") - 5.0)
	elif _smoke_skipped and m.run_time > Tuning.g("boss_every") + (SMOKE_FORTRESS_S if m._args.has("--fortress") else SMOKE_BOSS_S):
		_smoke_end(0, "boss %s" % ("alive" if m.boss_alive() else "killed"))
	elif _smoke_skipped and m._args.has("--fortress"):
		_fortress_log()


## FB-01: смоук с «--fortress» — бой с «Крепостью» до 180 с, раз в 10 с — фаза, точки, расстояние до базы
const SMOKE_FORTRESS_S := 180.0
var _flog_t := 0.0


func _fortress_log() -> void:
	if m.run_time < _flog_t:
		return
	_flog_t = m.run_time + 10.0
	for n in m.get_tree().get_nodes_in_group("enemies"):
		var f := n as Fortress
		if f == null:
			continue
		var pts := []
		for pt in f.points:
			pts.append(int(float(pt["hp"])))
		print("FORTRESS: t %.0f phase %d total %.2f hull %.0f/%.0f points %s base %.0f hits %d dist_player %.0f" % [m.run_time, f.phase, f.total_frac(), f.hp, f.max_hp, str(pts),
			f.global_position.distance_to(f.base_pos) if f.base_pos != Vector2.INF else -1.0, f.base_hits, f.global_position.distance_to(m.player.global_position)])


## S8 «eweap»: урон по видам оружия врагов (дошедший и «сырой» с --god) — для замера баланса в автотесте
func print_taken(tag: String) -> void:
	print("%s: taken_kind %s · raw_in(god) %s · taken_by %s · decoy_resisted %d · sam_frag %d · пущено ПЗРК %d / самолёт %d / ЗРК %d" % [tag, RunLog.kv(m.stats["taken_kind"]),
		RunLog.kv(m.stats["raw_in"]), RunLog.kv(m.stats["taken_by"]), int(m.counters.get("decoy_resisted", 0)), int(m.counters.get("sam_frag_hits", 0)), int(m.counters.get("msl_manpads", 0)), int(m.counters.get("msl_aam", 0)), int(m.counters.get("msl_sam", 0))])


func _smoke_end(code: int, why: String) -> void:
	print_taken("SMOKE")
	print("SMOKE: dealt %s · rail %d · emp %d · laser burned %d · mastery +%d" % [str(m.stats["dealt"]), int(m.counters.get("rail_shots", 0)), int(m.counters.get("emp_pulses", 0)), int(m.counters.get("laser_burned", 0)), int(m.tele.g("mastery_dmg"))])
	print("SMOKE: %s class %s, level %d, kills %d, %s, %.0f s real" % ["ok" if code == 0 else "FAIL", m.cls_id, m.level, m.kills, why, Time.get_ticks_msec() / 1000.0])
	m.get_tree().quit(code)


# ---------- Автотест (-- --autotest): бот летает, берёт карточки, умирает/эвакуируется и начинает заново ----------

var _bot_wait := 0.0
var _runs_done := 0
var _loadout_opened := false


func _run_autotest(delta: float) -> void:
	_autotest_t += delta
	_bot_wait -= delta / maxf(Engine.time_scale, 0.01)
	if m._args.has("--shots") and m.state != "playing" and m._state_t < 1.0:
		return # в режиме скриншотов даём экрану постоять
	match m.state:
		"menu":
			if _bot_wait <= 0.0:
				_bot_wait = 1.5
				_shot("menu")
				if m._args.has("--shots") and not _shots_done.has("hangar_crew"):
					Profile.debug_parts(8000)
					Campaign.debug_open_all() # U-05/U-07: на скриншотах открыты все операции и ступень 3
					Profile.debug_level("fighter")
					Profile.debug_level("fighter")
					# 3.5: опыта — на звание выше, чтобы на скриншоте была кнопка «Повысить в звании»
					Profile.cls("fighter")["crew_xp"] = int(Profile.CREW_CUM[mini(Profile.crew_lvl("fighter"), Profile.CREW_CUM.size() - 1)])
					Profile.buy_plane2("fighter") # 3.5: на скриншоте — выбор самолёта на вылет
					m.ui_click("menu_hangar")
				elif m._args.has("--shots") and not _shots_done.has("settings"):
					m.menu.tab = 1
					m.menu.open_settings("menu")
				else:
					m.ui_click("menu_play")
			return
		"settings":
			if _bot_wait <= 0.0:
				_bot_wait = 1.0
				m.menu.close_settings()
			return
		"hangar":
			if _bot_wait <= 0.0:
				_bot_wait = 1.0
				if not _shots_done.has("hangar_plane"):
					if m.hangar_tab != "plane":
						m.hangar_tab = "plane"
						m.input_ctl.hangar_action("node:armor")
						return
					_shot("hangar_plane")
					m.hangar_tab = "weapons"
					m.input_ctl.hangar_action("tier:aam:1:a")
					m.input_ctl.hangar_action("tier:aam:2:b")
				elif not _shots_done.has("hangar_weapons"):
					_shot("hangar_weapons")
					m.hangar_tab = "crew"
					m.input_ctl.hangar_action("perk:f_msl1")
				elif not _shots_done.has("hangar_crew"):
					_shot("hangar_crew")
					var lv0 := Profile.crew_lvl("fighter")
					m.input_ctl.hangar_action("promote")
					print("AUTOTEST: promote %d -> %d, parts %d" % [lv0, Profile.crew_lvl("fighter"), Profile.parts()])
				else:
					m.input_ctl.hangar_action("back")
			return
		"campaign":
			# U-05: операция кампании — по --op=N (1–4; открывает все), иначе текущая
			if _bot_wait <= 0.0:
				_bot_wait = 1.0
				for a in m._args:
					if String(a).begins_with("--op="):
						Campaign.debug_open_all()
						Campaign.select(clampi(int(String(a).substr(5)) - 1, 0, Campaign.OPS.size() - 1))
				print("AUTOTEST: operation %d %s" % [Campaign.index() + 1, Campaign.op()["id"]])
				m.ui_click("op_go")
			return
		"class_select":
			if _bot_wait <= 0.0:
				_bot_wait = 1.5
				var forced := ""
				for a in m._args:
					if String(a).begins_with("--class="):
						forced = String(a).substr(8)
				var cid: String = forced if forced != "" else PlaneClasses.LIST[m.restarts % 3]
				var sk := ""
				for a in m._args:
					if String(a).begins_with("--skill="):
						sk = String(a).substr(8)
				if sk == "":
					sk = PlaneClasses.CLASS_SKILLS[cid][randi() % 3]
				m.skill_pick[cid] = sk
				print("AUTOTEST: class %s skill %s" % [cid, sk])
				m.select_class(cid)
			return
		"course_pick":
			if _bot_wait <= 0.0:
				_bot_wait = 0.3
				_shot("course")
				m.choose_course(0)
			return
		"levelup":
			if _bot_wait <= 0.0:
				_bot_wait = 0.3
				if m._args.has("--bot=course"):
					for ci in m.offers.size():
						if m.offers[ci].get("course", false) or m.offers[ci]["kind"] in ["synergy", "skill_syn"]:
							m.choose_card(ci)
							return
				if m._args.has("--bot=missiles"):
					# 3.5: проверка ракет — берём ракеты В-В, НАР, их уровни и ракетные модули
					for pass_i in 2:
						for ci in m.offers.size():
							var o: Dictionary = m.offers[ci]
							var w := String(o.get("weapon", ""))
							if o["kind"] == "weapon_up" and m.player.groups.size() > int(o.get("group", 99)):
								w = String((m.player.groups[int(o["group"])] as Hardpoint).weapon)
							var want := (w in ["aam", "rockets"]) if pass_i == 0 else (String(o["id"]) in ["seeker", "msl_head", "msl_motor", "launcher", "reload"])
							if want:
								m.choose_card(ci)
								return
				if m._args.has("--shots") and m.level >= 6 and not _shots_done.has("loadout") and not _loadout_opened:
					_loadout_opened = true
					# один раз заглянуть в подвесы для скриншота
					m.choose_card(randi() % m.offers.size())
					m._set_state("paused")
					return
				# проверка переброса / закрепления / исключения
				if m.level == 3 and m.bans > 0:
					m.ban_card(0)
				elif m.level == 4 and m.rerolls > 0:
					m.reroll()
				elif m.level == 5:
					m.lock_card(1)
				m.choose_card(randi() % m.offers.size())
			return
		"paused":
			if _bot_wait <= 0.0 and _shots_done.has("loadout"):
				if m._args.has("--shots") and not _shots_done.has("codex"):
					m.ui_click("codex")
					return
				m.input_ctl.cycle_priority(0)
				m._set_state("playing")
			return
		"codex":
			if _shots_done.has("codex"):
				m.ui_click("codex_back")
			return
		"dead", "evac":
			if _bot_wait <= 0.0:
				_bot_wait = 1.0
				print("AUTOTEST: %s at %.1f s, class %s, level %d, kills %d, bosses %d, mastery t%d +%d" % [m.state, m.run_time, m.cls_id, m.level, m.kills, m.bosses_killed,
					int(m.tele.g("mastery_t")), int(m.tele.g("mastery_dmg"))])
				print_taken("AUTOTEST")
				print("AUTOTEST: modules %d/%d %s, hp_cd %.2f" % [Cards.mod_slots_used(m.player), Cards.MOD_SLOTS, m.player.taken, float(m.player.mods["hp_cd"])])
				_runs_done += 1
				for a in m._args:   # --runs=N: полный автотест заканчивается сам после N вылетов (tools/ci/full.sh)
					if String(a).begins_with("--runs=") and _runs_done >= int(String(a).substr(7)):
						print("AUTOTEST: done %d runs, %.0f s real" % [_runs_done, Time.get_ticks_msec() / 1000.0])
						m.get_tree().quit(0)
						return
				if not m._args.has("--shots"):
					m.ui_click("change_class") # следующий вылет — другим классом
			return
	if int(_autotest_t * 10.0) % 100 == 0 and m._args.has("--verbose-bot"):
		for n in m.get_tree().get_nodes_in_group("enemies"):
			if (n as Enemy).is_boss:
				print("BOSS hp %.0f shield %.0f dist %.0f t=%.0f" % [n.hp, n.shield, n.global_position.distance_to(m.player.global_position), m.run_time])
	# Короткая проверка РУД в схеме «влево/вправо»: 20–22 с держим W
	if m.run_time > 20.0 and m.run_time < 22.0:
		Tuning.set_param("scheme", 1)
		Input.action_press("move_up")
		return
	if m.run_time >= 22.0 and m.run_time < 22.1:
		print("AUTOTEST: throttle after W = %.2f" % m.player.throttle)
	Tuning.set_param("scheme", 0)
	for a in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(a)
	var phase := int(_autotest_t * 2.0) % 12
	var goal := Vector2.ZERO
	var tk: Tanker = m.spawner.fuel.tanker if m.spawner != null and m.spawner.fuel != null else null
	if is_instance_valid(tk) and tk.alive() and not tk.leaving:
		goal = tk.global_position # 3.5: бот идёт за заправщиком (он сам выходит вперёд)
	elif is_instance_valid(m.evac) and not m._args.has("--noevac"):
		goal = m.evac.target_pos() # бот летит через ворота эвакуации
	elif is_instance_valid(m.spawner.activity_node) and (m.spawner.activity_node is AASite or m.spawner.activity_node is Transport or m.spawner.activity_node is Convoy):
		goal = (m.spawner.activity_node as Node2D).global_position # бот летит штурмовать ПВО (и колонну)
	elif m.boss_alive():
		for n in m.get_tree().get_nodes_in_group("enemies"):
			if (n as Enemy).is_boss:
				goal = (n as Node2D).global_position # бот атакует аса
	elif int(_autotest_t) % 6 < 4:
		# бот собирает опыт: летит к ближайшему ромбу
		var best := 1200.0
		for it in m.pickups.items:
			var d := m.player.global_position.distance_to(it["p"])
			if d < best:
				best = d
				goal = it["p"]
	if goal != Vector2.ZERO:
		var to := goal - m.player.global_position
		Input.action_press("move_right" if to.x > 0 else "move_left", minf(1.0, absf(to.x) / 200.0))
		Input.action_press("move_down" if to.y > 0 else "move_up", minf(1.0, absf(to.y) / 200.0))
	elif phase < 6:
		Input.action_press("move_left")
	else:
		Input.action_press("move_up")
	_tap("roll", phase == 2)
	_tap("afterburner", phase == 5)
	_tap("dive", phase == 7)
	_tap("sharp_turn", phase == 8)
	_tap("toggle_fire_mode", phase == 9 and int(_autotest_t) % 24 == 4)
	if phase >= 9:
		Input.action_press("fire")
	else:
		Input.action_release("fire")
	if m._args.has("--shots") and m.run_time < Tuning.g("boss_every") - 20.0 and m.run_time > 110.0:
		m.run_time = Tuning.g("boss_every") - 20.0
	# съёмка клипов для канала: --skip=N перематывает время вылета к секунде N один раз (например, к боссу)
	for a in m._args:
		if String(a).begins_with("--skip=") and not _shots_done.has("skip") and m.run_time > 3.0:
			_shots_done["skip"] = true
			m.run_time = maxf(m.run_time, float(String(a).substr(7)))


func _tap(action: String, on: bool) -> void:
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)
