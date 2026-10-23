class_name ReportPanel
extends CanvasLayer
## 3.3-t2: «Отчёт тестера» — анкета после вылета + статистика вылета + хвост журнала Godot.
## Отправка: POST JSON на веб-приложение Google Apps Script (Main.REPORT_URL) → строки в Google Таблице.
## Нет сети — отчёт ложится в очередь user://report_queue.json и уходит при следующей отправке или запуске игры.
## 3.5: строка лога каждого вылета уходит сама, без анкеты (queue_run → лист «Вылеты»), очередь user://run_queue.json.

const TOKEN := "fh-tester-2026"
const QUEUE := "user://report_queue.json"
const TESTER_FILE := "user://tester_id"
const LOG_TAIL_LINES := 150
const RUN_TOKEN := "fh-run-2026"   # свой токен: старый приёмник без листа «Вылеты» ответит bad token и ничего не запишет
const RUN_QUEUE := "user://run_queue.json"
const RUN_QUEUE_MAX := 40

var _http: HTTPRequest
var _http_runs: HTTPRequest
var _runs_busy := false
var _root: Control
## Короткие вопросы кнопками: ключ, вопрос, варианты, ширина кнопки (0 — по тексту).
## «why» показывается только при досрочном выходе в меню.
## После теста 3.5-s7 (Kanta, 18.10): добавлены сложность, темп, улучшения, звук и «что понравилось».
const WHY_Q := ["why", "Почему закончили раньше?", ["Стало скучно", "Слишком сложно", "Нет времени", "Баг или тормоза", "Другое"], 0]
const CHOICE_Q := [
	["rating", "Как вам вылет? (1 — плохо, 5 — отлично)", ["1", "2", "3", "4", "5"], 64],
	["again", "Хочется сразу сыграть ещё?", ["Да", "Может быть", "Нет"], 0],
	["diff", "Сложность", ["Легко", "В самый раз", "Сложно"], 0],
	["pace", "Темп вылета", ["Затянуто", "В самый раз", "Слишком суетно"], 0],
	["cards", "Выбор улучшений интересный?", ["Да", "Так себе", "Нет"], 0],
	["sound", "Звук и музыка (1–5)", ["1", "2", "3", "4", "5"], 64],
	# T4-03: картинка, камера, читаемость пуль и тормоза
	["pic", "Как вам картинка? (1–5)", ["1", "2", "3", "4", "5"], 64],
	["cam", "Какой наклон камеры удобнее? (F9)", ["28°", "35°", "45°", "Сверху", "Не пробовал(а)"], 0],
	["bullets", "Пули и ракеты врагов видно?", ["Всегда", "Иногда терялись", "Часто терялись"], 0],
	["lag", "Игра тормозила?", ["Нет", "Иногда", "Часто"], 0],
]
## ключи, которые уходят и отдельными полями, и строкой «Короткие ответы» (старый приёмник новых полей не знает)
const SHORT_KEYS := ["why", "diff", "pace", "cards", "sound", "pic", "cam", "bullets", "lag"]
var _ans := {}
var _q_btns := {}
var _why_row: Control
var _title: Label
var _sub: Label
var _liked: TextEdit
var _boring: TextEdit
var _unclear: TextEdit
var _comment: TextEdit
var _status: Label
var _cancel_btn: Button
var _skip_btn: Button
var _send_btn: Button
var _busy := false
var _flush_after_open := false
## досрочный выход из вылета в меню: анкета перед выходом, после неё — главное меню
var _exit_mode := false


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_http = HTTPRequest.new()
	_http.timeout = 25.0
	_http.max_redirects = 0   # Apps Script отвечает 302 уже после записи — редирект нам не нужен
	_http.request_completed.connect(_on_done)
	add_child(_http)
	_http_runs = HTTPRequest.new()
	_http_runs.timeout = 25.0
	_http_runs.max_redirects = 0
	_http_runs.request_completed.connect(_on_run_done)
	add_child(_http_runs)
	_build()
	# тихо досылаем то, что не ушло в прошлый раз
	if Main.REPORT_URL != "":
		call_deferred("_flush")
		call_deferred("_flush_runs")


# ---------- интерфейс ----------

func _build() -> void:
	var th := Theme.new()
	th.default_font = Hud.ui_font()
	th.default_font_size = 20
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = th
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.025, 0.02, 0.85)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.115, 0.105)
	sb.border_color = Menu.C_AMBER
	sb.set_border_width_all(2)
	sb.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(1680, 0)
	var center := CenterContainer.new()   # высота панели — по содержимому, по центру экрана
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.add_child(panel)
	_root.add_child(center)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 32)
	_title.add_theme_color_override("font_color", Menu.C_AMBER)
	v.add_child(_title)
	_sub = Label.new()
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub.add_theme_font_size_override("font_size", 17)
	_sub.add_theme_color_override("font_color", Menu.C_DIM)
	v.add_child(_sub)

	# досрочный выход: причина — отдельной строкой сверху
	_why_row = _question(WHY_Q)
	v.add_child(_why_row)
	# остальные вопросы кнопками — по два в ряд
	for i in range(0, CHOICE_Q.size(), 2):
		var hq := HBoxContainer.new()
		hq.add_theme_constant_override("separation", 30)
		for q in CHOICE_Q.slice(i, i + 2):
			hq.add_child(_question(q))
		v.add_child(hq)

	# свободные ответы — сеткой 2×2
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 4)
	_liked = _area()
	_boring = _area()
	_unclear = _area()
	_comment = _area()
	for pair in [["Что понравилось больше всего?", _liked], ["Что было скучно или раздражало?", _boring],
			["Что было непонятно?", _unclear], ["Баги, вылеты, тормоза, идеи и всё остальное", _comment]]:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(_caption(pair[0]))
		col.add_child(pair[1])
		grid.add_child(col)
	v.add_child(grid)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 17)
	hb.add_child(_status)
	_cancel_btn = Button.new()
	_cancel_btn.custom_minimum_size = Vector2(220, 54)
	_cancel_btn.pressed.connect(close)
	hb.add_child(_cancel_btn)
	_skip_btn = Button.new()
	_skip_btn.text = "Выйти без отчёта"
	_skip_btn.custom_minimum_size = Vector2(240, 54)
	_skip_btn.pressed.connect(_exit_to_menu)
	hb.add_child(_skip_btn)
	_send_btn = Button.new()
	_send_btn.custom_minimum_size = Vector2(280, 54)
	var sbs := StyleBoxFlat.new()
	sbs.bg_color = Menu.C_AMBER
	_send_btn.add_theme_stylebox_override("normal", sbs)
	var sbh := StyleBoxFlat.new()
	sbh.bg_color = Menu.C_AMBER.lightened(0.15)
	_send_btn.add_theme_stylebox_override("hover", sbh)
	_send_btn.add_theme_color_override("font_color", Color(0.08, 0.07, 0.05))
	_send_btn.add_theme_color_override("font_hover_color", Color(0.08, 0.07, 0.05))
	_send_btn.pressed.connect(_send)
	hb.add_child(_send_btn)
	v.add_child(hb)


## Вопрос с кнопками-вариантами: подпись и ряд переключателей
func _question(q: Array) -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	col.add_child(_caption(q[1]))
	var hb2 := HBoxContainer.new()
	hb2.add_theme_constant_override("separation", 6)
	var btns: Array[Button] = []
	for t in q[2]:
		var b := _toggle(t, Vector2(q[3], 40))
		b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(_set_ans.bind(q[0], t))
		btns.append(b)
		hb2.add_child(b)
	_q_btns[q[0]] = btns
	col.add_child(hb2)
	return col


func _caption(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 19)
	return l


func _toggle(t: String, sz: Vector2) -> Button:
	var b := Button.new()
	b.text = t
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(maxf(sz.x, 64.0), sz.y)
	# невыбранный вариант — видимая плашка с отступами, чтобы кнопки не сливались в строку текста
	var off := StyleBoxFlat.new()
	off.bg_color = Color(1, 1, 1, 0.07)
	off.border_color = Color(Menu.C_AMBER.r, Menu.C_AMBER.g, Menu.C_AMBER.b, 0.35)
	off.set_border_width_all(1)
	off.set_content_margin_all(6)
	off.content_margin_left = 14
	off.content_margin_right = 14
	b.add_theme_stylebox_override("normal", off)
	var offh := off.duplicate() as StyleBoxFlat
	offh.bg_color = Color(1, 1, 1, 0.14)
	offh.border_color = Menu.C_AMBER
	b.add_theme_stylebox_override("hover", offh)
	var on := StyleBoxFlat.new()
	on.bg_color = Menu.C_AMBER
	on.set_content_margin_all(6)
	on.content_margin_left = 14
	on.content_margin_right = 14
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_color_override("font_pressed_color", Color(0.08, 0.07, 0.05))
	b.add_theme_color_override("font_hover_pressed_color", Color(0.08, 0.07, 0.05))
	return b


func _area() -> TextEdit:
	var te := TextEdit.new()
	te.custom_minimum_size = Vector2(0, 70)
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	te.placeholder_text = "можно оставить пустым"
	return te


func _set_ans(key: String, t: String) -> void:
	_ans[key] = t
	for b in _q_btns[key]:
		(b as Button).button_pressed = (b.text == t)


func _set_rating(n: int) -> void:
	if n <= 0:
		_ans.erase("rating")
		for b in _q_btns["rating"]:
			(b as Button).button_pressed = false
	else:
		_set_ans("rating", str(n))


func _set_again(t: String) -> void:
	_set_ans("again", t)


## Короткие ответы одной строкой: «diff: Сложно; lag: Нет»
func _short_text() -> String:
	var parts := PackedStringArray()
	for k in SHORT_KEYS:
		if _ans.has(k):
			parts.append("%s: %s" % [k, _ans[k]])
	return "; ".join(parts)


## exit_mode — открыт из паузы кнопкой «В главное меню»: после анкеты игра уходит в меню.
func open(exit_mode := false) -> void:
	if Main.REPORT_URL == "":
		return
	_exit_mode = exit_mode
	_ans.clear()
	for k in _q_btns:
		for b in _q_btns[k]:
			(b as Button).button_pressed = false
	for te in [_liked, _boring, _unclear, _comment]:
		(te as TextEdit).text = ""
	_why_row.visible = exit_mode
	_skip_btn.visible = exit_mode
	if exit_mode:
		_title.text = "ВЫХОД ИЗ ВЫЛЕТА"
		_sub.text = "Пара кнопок перед выходом очень поможет: почему закончили и как было. Можно выйти и без отчёта — строка статистики вылета всё равно уйдёт."
		_cancel_btn.text = "Вернуться в бой"
		_send_btn.text = "ОТПРАВИТЬ И ВЫЙТИ"
	else:
		_title.text = "ОТЧЁТ ТЕСТЕРА"
		_sub.text = "Уйдёт организатору теста: ваши ответы, статистика этого вылета, ОС и видеокарта, технический журнал игры. Личных данных нет. Отвечайте только на то, что хочется."
		_cancel_btn.text = "Отмена"
		_send_btn.text = "ОТПРАВИТЬ"
	_status.text = ""
	_status.remove_theme_color_override("font_color")
	_send_btn.disabled = false
	visible = true
	_liked.grab_focus()


## Закрыли окно посреди вылета: строка лога ложится в очередь и уйдёт при следующем запуске
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and Main.I != null and Main.I.input_ctl != null:
		Main.I.input_ctl.log_abort("закрыл игру")


func close() -> void:
	visible = false


## Досрочный выход: строка лога вылета (итог «выход») и главное меню
func _exit_to_menu() -> void:
	visible = false
	_exit_mode = false
	Main.I.input_ctl.abort_run()


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()


# ---------- данные ----------

func _tester_id() -> String:
	if FileAccess.file_exists(TESTER_FILE):
		var f := FileAccess.open(TESTER_FILE, FileAccess.READ)
		if f:
			var id := f.get_as_text().strip_edges()
			if id != "":
				return id
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var nid := "%08x" % rng.randi()
	var w := FileAccess.open(TESTER_FILE, FileAccess.WRITE)
	if w:
		w.store_string(nid)
	return nid


func _log_tail() -> String:
	var path := "user://logs/godot.log"
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var lines := f.get_as_text().split("\n")
	var from := maxi(0, lines.size() - LOG_TAIL_LINES)
	return "\n".join(lines.slice(from))


func _comment_full() -> String:
	var pre := PackedStringArray()
	if _short_text() != "":
		pre.append("[%s]" % _short_text())
	if _liked.text.strip_edges() != "":
		pre.append("[Понравилось: %s]" % _liked.text.strip_edges())
	pre.append(_comment.text.strip_edges())
	return " ".join(pre).strip_edges()


func _payload() -> Dictionary:
	var m := Main.I
	var syn := PackedStringArray()
	if is_instance_valid(m.player):
		for id in m.player.syn:
			syn.append(String(Cards.syn_def(m.player, id)["title"]))
	var scr := DisplayServer.screen_get_size()
	return {
		"token": TOKEN,
		"build": Demo.tag(Main.BUILD),
		"tester": _tester_id(),
		"sent_at": Time.get_datetime_string_from_system(),
		"cls": String(PlaneClasses.DATA[m.cls_id]["title"]) if PlaneClasses.DATA.has(m.cls_id) else m.cls_id,
		"outcome": "эвакуация" if m.last_outcome == "evac" else ("гибель" if m.last_outcome == "dead" else m.last_outcome),
		"run_seconds": int(m.run_time),
		"level": m.run.level,
		"kills": m.run.kills,
		"synergies": ", ".join(syn),
		"rating": int(_ans["rating"]) if _ans.has("rating") else "",
		"again": _ans.get("again", ""),
		"boring": _boring.text.strip_edges(),
		"unclear": _unclear.text.strip_edges(),
		"liked": _liked.text.strip_edges(),
		"why": _ans.get("why", ""),
		"diff": _ans.get("diff", ""),
		"pace": _ans.get("pace", ""),
		"cards": _ans.get("cards", ""),
		"sound": _ans.get("sound", ""),
		# короткие ответы — и отдельными полями, и строкой, и в начале комментария вместе с «понравилось»
		# (уже развёрнутый приёмник новых полей не знает, так ничего не потеряется)
		"visual": _short_text(),
		"comment": _comment_full(),
		"os": "%s %s" % [OS.get_name(), OS.get_version()],
		"gpu": "%s (%s)" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor()],
		"screen": "%dx%d" % [scr.x, scr.y],
		"fps": int(round(m.avg_fps())),
		"run_header": m.last_log_header,
		"run_row": m.last_log_row,
		"log_tail": _log_tail(),
	}


# ---------- лог каждого вылета (без анкеты) ----------

## Вызывается из RunLog.write после записи строки CSV. В автотесте и без адреса приёмника — ничего не шлём.
func queue_run(header: String, row: String) -> void:
	if Main.REPORT_URL == "" or Main.I._autotest:
		return
	var scr := DisplayServer.screen_get_size()
	var q := _read_json_array(RUN_QUEUE)
	q.append({
		"token": RUN_TOKEN,
		"kind": "run",
		"build": Demo.tag(Main.BUILD),
		"tester": _tester_id(),
		"sent_at": Time.get_datetime_string_from_system(),
		"os": "%s %s" % [OS.get_name(), OS.get_version()],
		"gpu": "%s (%s)" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor()],
		"screen": "%dx%d" % [scr.x, scr.y],
		"run_header": header,
		"run_row": row,
	})
	while q.size() > RUN_QUEUE_MAX:
		q.remove_at(0)
	_write_json(RUN_QUEUE, q)
	_flush_runs()


func _flush_runs() -> void:
	if _runs_busy or Main.REPORT_URL == "":
		return
	var q := _read_json_array(RUN_QUEUE)
	if q.is_empty():
		return
	_runs_busy = true
	if _http_runs.request(Main.REPORT_URL, PackedStringArray(["Content-Type: application/json"]),
			HTTPClient.METHOD_POST, JSON.stringify(q[0])) != OK:
		_runs_busy = false


func _on_run_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_runs_busy = false
	var ok := (result == HTTPRequest.RESULT_SUCCESS or result == HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED) and code >= 200 and code < 400
	# старый приёмник (без листа «Вылеты») отвечает bad token — строка остаётся в очереди до обновления скрипта
	if not ok or body.get_string_from_utf8().begins_with("bad token"):
		return
	var q := _read_json_array(RUN_QUEUE)
	if not q.is_empty():
		q.remove_at(0)
	_write_json(RUN_QUEUE, q)
	if not q.is_empty():
		_flush_runs()


static func _read_json_array(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Array else []


static func _write_json(path: String, v: Variant) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(v))


# ---------- очередь и отправка ----------

func _load_queue() -> Array:
	if not FileAccess.file_exists(QUEUE):
		return []
	var f := FileAccess.open(QUEUE, FileAccess.READ)
	if f == null:
		return []
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Array else []


func _save_queue(q: Array) -> void:
	var f := FileAccess.open(QUEUE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(q))


func _send() -> void:
	if _busy:
		return
	if _exit_mode:
		# сначала строка лога вылета (итог «выход») — она нужна отчёту, потом анкета в очередь и сразу в меню;
		# отправка идёт в фоне, при неудаче отчёт уйдёт при следующем запуске
		Main.I.input_ctl.log_abort()
	var q := _load_queue()
	q.append(_payload())
	_save_queue(q)
	_send_btn.disabled = true
	if _exit_mode:
		_flush_after_open = false
		_status.text = "Спасибо! Отчёт отправляется…"
		_status.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
		_flush()
		get_tree().create_timer(0.9, true, false, true).timeout.connect(_exit_to_menu)
		return
	_status.text = "Отправляем…"
	_flush_after_open = true
	_flush()


func _flush() -> void:
	if _busy or Main.REPORT_URL == "":
		return
	var q := _load_queue()
	if q.is_empty():
		return
	_busy = true
	var err := _http.request(Main.REPORT_URL, PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST, JSON.stringify(q[0]))
	if err != OK:
		_busy = false
		_fail(Loc.t("не удалось начать отправку (%d)") % err)


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	# Apps Script пишет строку и отвечает 302 → при max_redirects = 0 это RESULT_REDIRECT_LIMIT_REACHED
	var ok := (result == HTTPRequest.RESULT_SUCCESS or result == HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED) and code >= 200 and code < 400
	var txt := body.get_string_from_utf8()
	if ok and txt.begins_with("bad token"):
		ok = false
	if not ok:
		_fail(Loc.t("нет связи с сервером (код %d / %d)") % [result, code])
		return
	var q := _load_queue()
	if not q.is_empty():
		q.remove_at(0)
	_save_queue(q)
	if not q.is_empty():
		_flush()
		return
	if _flush_after_open:
		_flush_after_open = false
		Main.I.report_sent = true
		_status.text = "Отправлено — спасибо!"
		_status.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
		get_tree().create_timer(1.2, true, false, true).timeout.connect(close)


func _fail(why: String) -> void:
	if _flush_after_open:
		_flush_after_open = false
		_status.text = Loc.t("Не отправилось: %s. Отчёт сохранён и уйдёт при следующей отправке или запуске игры.") % why
		_status.add_theme_color_override("font_color", Color(1.0, 0.7, 0.4))
		Main.I.report_sent = true   # сохранён в очереди — повторно заполнять не нужно
