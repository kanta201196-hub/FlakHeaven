class_name MainDebug
extends RefCounted
## Отладочные режимы Main: автотест (-- --autotest), скриншоты (--shots), проверки --fxtest,
## --reporttest, --mesatest. Работают только по флагам командной строки.

var m: Main
var _fx_t := 0.0
var _fx_at := 0.0
var _fx_fired := false
var _autotest_t := 0.0


func _init(main: Main) -> void:
	m = main


func process(delta: float) -> void:
	if m._autotest:
		_run_autotest(delta)
	if m._args.has("--shots"):
		_debug_screenshots(delta)

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


func _debug_screenshots(delta: float) -> void:
	_shot_t += delta / maxf(Engine.time_scale, 0.01)
	if m._state_t < 0.6:
		return
	if m.state == "menu" and m._state_t > 1.0 and m.menu.howto:
		_shot("howto")
		m.menu.close_howto()
	elif m.state == "menu" and m._state_t > 1.0:
		_shot("menu")
	if m.state == "settings":
		_shot("settings")
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
	if (m.state == "evac" or m.state == "dead") and m.result_t > 3.5:
		_shot("result")
		m.get_tree().quit()


# ---------- Автотест (-- --autotest): бот летает, берёт карточки, умирает/эвакуируется и начинает заново ----------

var _bot_wait := 0.0
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
				if m._args.has("--shots") and not _shots_done.has("hangar_crew"):
					Profile.debug_parts(3000)
					Profile.debug_level("fighter")
					Profile.debug_level("fighter")
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
				elif not _shots_done.has("hangar_weapons"):
					_shot("hangar_weapons")
					m.hangar_tab = "crew"
					m.input_ctl.hangar_action("perk:f_msl1")
				elif not _shots_done.has("hangar_crew"):
					_shot("hangar_crew")
				else:
					m.input_ctl.hangar_action("back")
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
				print("AUTOTEST: %s at %.1f s, class %s, level %d, kills %d, bosses %d" % [m.state, m.run_time, m.cls_id, m.level, m.kills, m.bosses_killed])
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
	if is_instance_valid(m.evac) and not m._args.has("--noevac"):
		goal = m.evac.target_pos() # бот летит через ворота эвакуации
	elif is_instance_valid(m.spawner.activity_node) and m.spawner.activity_node is AASite:
		goal = (m.spawner.activity_node as Node2D).global_position # бот летит штурмовать ПВО
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
	_tap("sharp_turn", phase == 8)
	_tap("toggle_fire_mode", phase == 9 and int(_autotest_t) % 24 == 4)
	if phase >= 9:
		Input.action_press("fire")
	else:
		Input.action_release("fire")
	if m._args.has("--shots") and m.run_time < Tuning.g("boss_every") - 20.0 and m.run_time > 110.0:
		m.run_time = Tuning.g("boss_every") - 20.0


func _tap(action: String, on: bool) -> void:
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)
