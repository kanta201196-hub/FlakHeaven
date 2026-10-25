class_name MainInput
extends RefCounted
## Управление вне полёта и отладка: глобальные клавиши по состояниям, клики интерфейса (ui_click),
## смена приоритета/пуска подвесов, действия ангара. Состояние вылета живёт в Main.

var m: Main
## CR-05: A/X/B/Y are both combat actions and "pick card 1–4"; a press held from the fight must not
## blindly pick a card on the level-up or course screen, so input waits this long after it opens.
## Kanta 25.10: long enough that a click or key mashed in the fight lands before the cards
## are live (keys, gamepad and mouse alike — Main checks it too); the cards fade in meanwhile.
const CARD_INPUT_DELAY := 0.6


func _init(main: Main) -> void:
	m = main


## Per-frame keys and gamepad buttons outside flight control, dispatched by game state:
## menus, card pick, pause, results, global toggles and debug keys.
func handle_global_input() -> void:
	if m.report != null and m.report.visible:
		return
	match m.state:
		"menu", "settings":
			return
		"codex":
			if Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("loadout"):
				m._set_state(m.codex_back)
			return
		"hangar":
			if Input.is_action_just_pressed("pause"):
				m.start_run()
				m._set_state(m.hangar_back)
			return
		"campaign":
			# EX-08: экран «В вылет». Enter — в бой (не тем же нажатием, что открыло экран из меню),
			# ↑ / ↓ — операция, 1 / 2 / 3 и ← / → — самолёт
			if Input.is_action_just_pressed("pause"):
				m._set_state("menu")
			elif Input.is_action_just_pressed("ui_accept") and m._state_t > 0.25:
				m.select_class(m.cls_id)
			elif Input.is_action_just_pressed("ui_up") or Input.is_action_just_pressed("ui_down"):
				# по открытым операциям биома выбранной операции
				var ids := Campaign.ops_of(Campaign.biome_of(Campaign.index())).filter(func(i: int) -> bool: return Campaign.is_open(i))
				var k := ids.find(Campaign.index())
				Campaign.select(ids[wrapi(k + (1 if Input.is_action_just_pressed("ui_down") else -1), 0, ids.size())])
			elif Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("ui_right"):
				var k := PlaneClasses.LIST.find(m.cls_id)
				m.cls_id = PlaneClasses.LIST[wrapi(k + (1 if Input.is_action_just_pressed("ui_right") else -1), 0, 3)]
			elif Input.is_action_just_pressed("toggle_scheme"):
				_cycle_scheme()
			else:
				for i in 3:
					if Input.is_action_just_pressed("choose_%d" % (i + 1)):
						m.cls_id = PlaneClasses.LIST[i]
			return
		"course_pick":
			if m._state_t < CARD_INPUT_DELAY:
				return
			for i in m.course_offers.size():
				if Input.is_action_just_pressed("choose_%d" % (i + 1)):
					m.choose_course(i)
					return
			return
		"levelup":
			if m._state_t < CARD_INPUT_DELAY:
				return
			# Enter / gamepad A take the focused card (A is also "choose_1": focus starts on card 1)
			if _accept_pressed():
				m.choose_card(HudCards.focus)
				return
			for i in m.offers.size():
				if Input.is_action_just_pressed("choose_%d" % (i + 1)):
					m.choose_card(i)
					return
			if Input.is_action_just_pressed("reroll"):
				m.reroll()
			elif Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("ui_right"):
				HudCards.move_focus(1 if Input.is_action_just_pressed("ui_right") else -1, m.offers.size())
			elif Input.is_action_just_pressed("card_lock"):
				m.lock_card(HudCards.focus)
			elif Input.is_action_just_pressed("card_ban"):
				m.ban_card(HudCards.focus)
			return
		"dead", "evac":
			if Demo.end_open:   # экран «Конец демо» поверх итогов: Enter / Esc — к итогам
				if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("ui_cancel"):
					Demo.end_open = false
				return
			if Input.is_action_just_pressed("restart") and m.result_t < 0.5:
				return
			# Enter / gamepad A press the focused button (A is also "choose_1", so it goes first)
			if _accept_pressed():
				var a := HudResult.accept()
				if a != "":
					ui_click(a)
				return
			for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				if Input.is_action_just_pressed(_DIR_ACTIONS[d]):
					HudResult.move_focus(d)
			for i in 2:
				if Input.is_action_just_pressed("choose_%d" % (i + 1)):
					m.result_tab = i
			if Input.is_action_just_pressed("ui_hangar"):
				ui_click("to_hangar")
				return
			if Input.is_action_just_pressed("restart"):
				m.restart()
			elif Input.is_action_just_pressed("change_class"):
				m.restarts += 1
				m.start_run()
				m._set_state("campaign")
			return
	if Input.is_action_just_pressed("toggle_tuning") and Main.DEBUG:
		m.tuning_panel.toggle()
	if Input.is_action_just_pressed("wing_prio") and m.state == "playing" and is_instance_valid(m.player) and not m.player.wingmen.is_empty():
		cycle_wing_prio()
	if Input.is_action_just_pressed("toggle_numbers"):
		Tuning.set_param("damage_numbers", 1.0 - Tuning.g("damage_numbers"))
	if Input.is_action_just_pressed("toggle_sprites") and Main.DEBUG:
		Tuning.set_param("sprites", 1.0 - Tuning.g("sprites"))
	if Input.is_action_just_pressed("toggle_scheme"):
		_cycle_scheme()
	if Input.is_action_just_pressed("cycle_tilt"):
		cycle_tilt(1)
		Events.banner.emit("Наклон камеры: %s  [F9]" % tilt_name(), 3.0)
	if m.state == "paused" and not m.tuning_panel.visible:
		_pause_nav()
	if (Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("loadout")) and not m.tuning_panel.visible:
		m._set_state("paused" if m.state == "playing" else "playing")
	if m.state == "playing" and Main.DEBUG:
		# Отладка для плейтеста
		if Input.is_action_just_pressed("debug_level"):
			m.run.debug_set(&"pending_levels", m.run.pending_levels + 1)
		if Input.is_action_just_pressed("debug_skip"):
			var nb := (floorf(m.run_time / Tuning.g("boss_every")) + 1.0) * Tuning.g("boss_every")
			m.run_time = maxf(m.run_time, nb - 10.0)
			Events.banner.emit("Отладка: перемотка к следующему асу", 3.0)
		if Input.is_action_just_pressed("debug_activity"):
			m.spawner.start_activity(m.player, m.run_time, true)
		if Input.is_action_just_pressed("debug_god"):
			m.god_mode = not m.god_mode
			Events.banner.emit("Отладка: неуязвимость %s" % ("ВКЛ" if m.god_mode else "ВЫКЛ"), 3.0)


## Pause screen keys and gamepad: ↑/↓ walk hardpoint rows and menu items, ←/→ change the
## focused row's target, Enter/A activates (focus lives in HudPause).
func _pause_nav() -> void:
	for d: Vector2i in [Vector2i.UP, Vector2i.DOWN]:
		if Input.is_action_just_pressed("ui_up" if d == Vector2i.UP else "ui_down"):
			HudPause.move_focus(d)
	for dir: int in [-1, 1]:
		if Input.is_action_just_pressed("ui_left" if dir < 0 else "ui_right"):
			var a := HudPause.side(dir)
			if a != "":
				ui_click(a)
	if _accept_pressed():
		var a := HudPause.accept()
		if a != "":
			ui_click(a)


const _DIR_ACTIONS := {Vector2i.UP: "ui_up", Vector2i.DOWN: "ui_down", Vector2i.LEFT: "ui_left", Vector2i.RIGHT: "ui_right"}


## Enter / gamepad A on screens over combat. Space is left out although Godot puts it in
## `ui_accept`: it is the roll key players mash in a fight, and must not pick a card or press
## «Покинуть вылет». The press is also taken off "roll" (A is both), so leaving the screen in
## this frame does not start a barrel roll.
func _accept_pressed() -> bool:
	if not Input.is_action_just_pressed("ui_accept") or Input.is_physical_key_pressed(KEY_SPACE):
		return false
	Input.action_release("roll")
	return true


## B-47: варианты наклона камеры для тестовой сборки (решение владельца — после теста)
const TILTS := [28.0, 35.0, 45.0, 0.0]


static func tilt_name() -> String:
	var t := Tuning.g("cam_tilt")
	return "сверху" if t < 0.5 else "%d°" % int(round(t))


func cycle_tilt(dir: int) -> void:
	var i := TILTS.find(Tuning.g("cam_tilt"))
	Tuning.set_param("cam_tilt", TILTS[wrapi(i + dir if i >= 0 else 0, 0, TILTS.size())])
	Tuning.save_params()
	if m.tele != null:
		m.tele.add("tilt_changes")


func _cycle_scheme() -> void:
	m.tele.add("scheme_changes")
	Tuning.set_param("scheme", float((int(Tuning.g("scheme")) + 1) % 3))


## Короче этого вылет не логируем и анкету при выходе не показываем: случайный старт, не тест
const ABORT_MIN_S := 20.0
var _abort_logged := false


## Строка лога для вылета, прерванного выходом в меню или закрытием игры (итог «выход»). Один раз за вылет.
func log_abort(outcome := "выход") -> void:
	# в меню и ангаре run_time = 0 (start_run его обнуляет), итоги гибели и эвакуации уже записаны
	if _abort_logged or m.state in ["dead", "evac"] or m.run_time < ABORT_MIN_S:
		return
	if not is_instance_valid(m.player) or m.is_dead:
		return
	_abort_logged = true
	RunLog.write(m, outcome)


## Выход из вылета в главное меню (из паузы или после анкеты)
func abort_run() -> void:
	log_abort()
	_abort_logged = false
	m.start_run()
	m._set_state("menu")


func ui_click(action: String) -> void:
	if action == "menu_play":
		m._set_state("campaign")
	elif action == "campaign_back":
		m._set_state("menu")
	elif action.begins_with("op:"):
		Campaign.select(int(action.substr(3)))
	elif action.begins_with("biome:"):
		HudCampaign.switch_biome(action.substr(6))
	elif action.begins_with("menu_biome:"):   # заставка: район вылета — мир за меню пересобирается в новом биоме
		HudCampaign.switch_biome(action.substr(11))
		m.start_run()
		m._set_state("menu")
	elif action == "op_go":   # EX-08: «В ВЫЛЕТ ▶» — выбранный самолёт сразу в бой
		m.select_class(m.cls_id)
	elif action == "sortie_hangar":   # «Улучшить самолёт» с экрана вылета — и обратно на него
		m.hangar_back = "campaign"
		m.hangar_cls = m.cls_id
		m._set_state("hangar")
	elif action == "menu_hangar" or action == "to_hangar":
		m.hangar_back = "menu"
		if m.state in ["dead", "evac"]:
			m.start_run()
		m.hangar_cls = m.cls_id if action == "to_hangar" else m.hangar_cls
		m._set_state("hangar")
	elif action.begins_with("hg:"):
		hangar_action(action.substr(3))
	elif action == "menu_codex" or action == "codex":
		m.codex_back = "menu" if m.state == "menu" else "paused"
		HudCodex.hints_reset_done = false
		m._set_state("codex")
	elif action == "codex_back":
		m._set_state(m.codex_back)
	elif action.begins_with("cx_tab:"):
		HudCodex.tab = int(action.substr(7))
	elif action == "cx_hints":
		Hints.reset()
		HudCodex.hints_reset_done = true
	elif action == "cx_all":
		HudCodex.show_all = not HudCodex.show_all
	elif action == "menu_settings":
		m.menu.open_settings("menu")
	elif action == "pause_settings":
		m.menu.open_settings("paused")
	elif action == "report_open":
		m.report.open()
	elif action == "menu_logs":
		OS.shell_open(ProjectSettings.globalize_path("user://"))
	elif action == "menu_howto":   # «Как играть» lives in the codex now (UI-01)
		HudCodex.tab = HudCodex.TAB_HOWTO
		m.codex_back = "menu"
		m._set_state("codex")
	elif action == "wishlist":   # M-07: демо — страница игры в Steam
		Demo.open_store()
	elif action == "demo_end_close":
		Demo.end_open = false
	elif action == "menu_quit":
		m.get_tree().quit()
	elif action == "to_menu":
		# досрочный выход из вылета: сначала короткая анкета (с кнопкой «Выйти без отчёта»), иначе данные теряются
		if m.state == "paused" and m.run_time >= ABORT_MIN_S and Main.REPORT_URL != "" and (not m._autotest or m._args.has("--exittest")):
			m.report.open(true)
		else:
			abort_run()
	elif action.begins_with("skill:"):
		var parts := action.split(":")
		if not Profile.skill_unlocked(parts[1], parts[2]):
			return
		m.skill_pick[parts[1]] = parts[2]
		Profile.set_skill(parts[1], 0, parts[2])
		m.sfx.play("card", -12.0, 1.4)
	elif action.begins_with("class:"):   # экран «В вылет»: клик по карточке выбирает самолёт, в бой — кнопкой
		m.cls_id = action.substr(6)
	elif action.begins_with("course:"):
		m.choose_course(int(action.substr(7)))
	elif action == "change_course":
		m.change_course()
	elif action.begins_with("card:"):
		m.choose_card(int(action.substr(5)))
	elif action.begins_with("prio:"):
		cycle_priority(int(action.substr(5)))
	elif action.begins_with("prioback:"):
		cycle_priority(int(action.substr(9)), -1)
	elif action == "wprio":
		cycle_wing_prio()
	elif action == "wprioback":
		cycle_wing_prio(-1)
	elif action.begins_with("trig:"):
		var g: Hardpoint = m.player.groups[int(action.substr(5))]
		g.trigger = "button" if g.trigger == "auto" else "auto"
		m.sfx.play("card", -14.0, 1.3)
	elif action.begins_with("lock:"):
		m.lock_card(int(action.substr(5)))
	elif action.begins_with("ban:"):
		m.ban_card(int(action.substr(4)))
	elif action == "reroll":
		m.reroll()
	elif action == "resume":
		m._set_state("playing")
	elif action.begins_with("rtab:"):
		m.result_tab = int(action.substr(5))
	elif action == "restart":
		m.restart()
	elif action == "change_class":
		m.restarts += 1
		m.start_run()
		m._set_state("campaign")


## Steps the target mode of hardpoint group `gi` forward (`dir` 1) or back (-1); the pause
## screen's `‹ ›` selector and ←/→ use both directions.
func cycle_priority(gi: int, dir := 1) -> void:
	if gi < 0 or gi >= m.player.groups.size():
		return
	var g: Hardpoint = m.player.groups[gi]
	if g.is_empty() or not Weapons.DEFS[g.weapon]["uses_priority"]:
		return
	var i := Weapons.PRIORITIES.find(g.priority)
	g.priority = Weapons.PRIORITIES[wrapi(i + dir, 0, Weapons.PRIORITIES.size())]
	m.sfx.play("card", -14.0, 1.3)


func hangar_action(a: String) -> void:
	var p := a.split(":")
	var c := m.hangar_cls
	var ok := true
	match p[0]:
		"cls":
			m.hangar_cls = p[1]
		"tab":
			m.hangar_tab = p[1]
		"node":
			ok = Profile.buy_node(c, p[1], int(p[2]) if p.size() > 2 else 0)
		"plane2":
			ok = Profile.buy_plane2(c)
		"plane_sel":
			Profile.set_plane(c, int(p[1]))
		"livery":
			Profile.set_livery(c, p[1])
		"wsel":
			m.hangar_w = p[1]
		"start":   # S11-09: put on / take off the start list (at most start_cap kinds)
			ok = Profile.toggle_start(c, p[1])
		"gun":   # PG-01: owned — select for free, otherwise buy (selects it)
			if Profile.guns(c).has(p[1]):
				Profile.set_gun(c, p[1])
			else:
				ok = Profile.buy_gun(c, p[1])
		"ammo":   # PG-01: same rule as the gun
			if Profile.ammos(c).has(p[1]):
				Profile.set_ammo(c, p[1])
			else:
				ok = Profile.buy_ammo(c, p[1])
		"tier":
			var w := p[1]
			var t := int(p[2])
			if Profile.tier_state(w, t) == "?":
				Profile.choose_paid(w, t, p[3])
			else:
				ok = Profile.pick_tier(w, t, p[3])
		"redo":
			ok = Profile.redo_tier(p[1], int(p[2]))
		"perk":
			Profile.toggle_perk(c, p[1])
		"perk_reset":
			Profile.cls(c)["perks"] = []
			Profile.save()
		"slot":
			Profile.set_skill(c, int(p[1]), p[2])
			m.skill_pick[c] = Profile.skills(c)[0] # правка 7: выбор в полёте всегда совпадает с ангаром
		"callsign":
			Profile.next_callsign(c)
		"promote":
			ok = Profile.can_promote(c)
			Profile.promote(c)
		"fly":
			m.skill_pick[c] = Profile.skills(c)[0]
			m.select_class(c)
			return
		"back":
			m.start_run()
			m._set_state(m.hangar_back)
			return
		"dbg_parts":
			Profile.debug_parts(1000)
		"dbg_lvl":
			Profile.debug_level(c)
		"dbg_all":
			Profile.debug_all()
		"dbg_wipe":
			Profile.wipe()
	m.sfx.play("card" if ok else "ui_ban", -10.0, 1.2 if ok else 0.8)


## Правка 3.5-s4: цель звена — по кругу; ведущий слышит ответ по радио
## Steps the wingmen's target forward (`dir` 1) or back (-1) and says it on the radio.
func cycle_wing_prio(dir := 1) -> void:
	Settings.wing_prio = wrapi(Settings.wing_prio + dir, 0, Settings.WING_PRIO.size())
	Settings.save_settings()
	var t: String = Settings.WING_PRIO[Settings.wing_prio]
	Events.radio.emit("Звено", "Принял: %s!" % (t.left(1).to_upper() + t.substr(1)), false)
