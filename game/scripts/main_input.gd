class_name MainInput
extends RefCounted
## Управление вне полёта и отладка: глобальные клавиши по состояниям, клики интерфейса (ui_click),
## смена приоритета/пуска подвесов, действия ангара. Состояние вылета живёт в Main.

var m: Main


func _init(main: Main) -> void:
	m = main


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
				m._set_state("menu")
			return
		"campaign":
			if Input.is_action_just_pressed("pause"):
				m._set_state("menu")
			elif Input.is_action_just_pressed("ui_accept"):
				m._set_state("class_select")
			elif Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("ui_right"):
				Campaign.select(wrapi(Campaign.index() + (1 if Input.is_action_just_pressed("ui_right") else -1), 0, Campaign.unlocked()))
			else:
				for i in Campaign.OPS.size():
					if Input.is_action_just_pressed("choose_%d" % (i + 1)):
						Campaign.select(i)
			return
		"class_select":
			if Input.is_action_just_pressed("pause"):
				m._set_state("campaign")
				return
			for i in 3:
				if Input.is_action_just_pressed("choose_%d" % (i + 1)):
					m.select_class(PlaneClasses.LIST[i])
					return
			if Input.is_action_just_pressed("toggle_scheme"):
				_cycle_scheme()
			return
		"course_pick":
			for i in m.course_offers.size():
				if Input.is_action_just_pressed("choose_%d" % (i + 1)):
					m.choose_course(i)
					return
			return
		"levelup":
			for i in m.offers.size():
				if Input.is_action_just_pressed("choose_%d" % (i + 1)):
					m.choose_card(i)
					return
			if Input.is_action_just_pressed("reroll"):
				m.reroll()
			return
		"dead", "evac":
			if Input.is_action_just_pressed("restart") and m.result_t < 0.5:
				return
			if Input.is_action_just_pressed("ui_hangar"):
				ui_click("to_hangar")
				return
			if Input.is_action_just_pressed("restart"):
				m.restart()
			elif Input.is_action_just_pressed("change_class"):
				m.restarts += 1
				m.start_run()
				m._set_state("class_select")
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
		m.show_banner("Наклон камеры: %s  [F9]" % tilt_name())
	if (Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("loadout")) and not m.tuning_panel.visible:
		m._set_state("paused" if m.state == "playing" else "playing")
	if m.state == "playing" and Main.DEBUG:
		# Отладка для плейтеста
		if Input.is_action_just_pressed("debug_level"):
			m.pending_levels += 1
		if Input.is_action_just_pressed("debug_skip"):
			var nb := (floorf(m.run_time / Tuning.g("boss_every")) + 1.0) * Tuning.g("boss_every")
			m.run_time = maxf(m.run_time, nb - 10.0)
			m.show_banner("Отладка: перемотка к следующему асу")
		if Input.is_action_just_pressed("debug_activity"):
			m.spawner.start_activity(m.player, m.run_time, true)
		if Input.is_action_just_pressed("debug_god"):
			m.god_mode = not m.god_mode
			m.show_banner("Отладка: неуязвимость %s" % ("ВКЛ" if m.god_mode else "ВЫКЛ"))


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


func ui_click(action: String) -> void:
	if action == "menu_play":
		m._set_state("campaign")
	elif action == "campaign_back":
		m._set_state("menu")
	elif action.begins_with("op:"):
		Campaign.select(int(action.substr(3)))
	elif action == "op_go":
		m._set_state("class_select")
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
		m._set_state("codex")
	elif action == "codex_back":
		m._set_state(m.codex_back)
	elif action.begins_with("cx_tab:"):
		HudCodex.tab = int(action.substr(7))
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
	elif action == "menu_howto":
		m.menu.howto = true
	elif action == "menu_quit":
		m.get_tree().quit()
	elif action == "to_menu":
		m.start_run()
		m._set_state("menu")
	elif action == "class_back":
		m._set_state("campaign")
	elif action.begins_with("skill:"):
		var parts := action.split(":")
		if not Profile.skill_unlocked(parts[1], parts[2]):
			return
		m.skill_pick[parts[1]] = parts[2]
		Profile.set_skill(parts[1], 0, parts[2])
		m.sfx.play("card", -12.0, 1.4)
	elif action.begins_with("class:"):
		m.select_class(action.substr(6))
	elif action.begins_with("course:"):
		m.choose_course(int(action.substr(7)))
	elif action == "change_course":
		m.change_course()
	elif action.begins_with("card:"):
		m.choose_card(int(action.substr(5)))
	elif action.begins_with("prio:"):
		cycle_priority(int(action.substr(5)))
	elif action == "wprio":
		cycle_wing_prio()
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
	elif action == "restart":
		m.restart()
	elif action == "change_class":
		m.restarts += 1
		m.start_run()
		m._set_state("class_select")


func cycle_priority(gi: int) -> void:
	var g: Hardpoint = m.player.groups[gi]
	if g.is_empty() or not Weapons.DEFS[g.weapon]["uses_priority"]:
		return
	var i := Weapons.PRIORITIES.find(g.priority)
	g.priority = Weapons.PRIORITIES[(i + 1) % Weapons.PRIORITIES.size()]
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
			ok = Profile.buy_node(c, p[1])
		"plane2":
			ok = Profile.buy_plane2(c)
		"plane_sel":
			Profile.set_plane(c, int(p[1]))
		"wsel":
			m.hangar_w = p[1]
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
			if int(p[1]) == 0:
				m.skill_pick[c] = p[2]
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
			m._set_state("menu")
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
func cycle_wing_prio() -> void:
	Settings.wing_prio = wrapi(Settings.wing_prio + 1, 0, Settings.WING_PRIO.size())
	Settings.save_settings()
	var t: String = Settings.WING_PRIO[Settings.wing_prio]
	Main.I.radio("Звено", "Принял: %s!" % (t.left(1).to_upper() + t.substr(1)))
