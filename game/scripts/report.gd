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
var _rating := 0
var _again := ""
var _rate_btns: Array[Button] = []
var _again_btns: Array[Button] = []
## T4-03: вопросы про картинку, камеру, читаемость пуль и тормоза — ключ → ответ / кнопки
const VIS_Q := [
	["pic", "Как вам картинка? (1–5)", ["1", "2", "3", "4", "5"], 64],
	["cam", "Какой наклон камеры удобнее? (F9)", ["28°", "35°", "45°", "Сверху", "Не пробовал(а)"], 0],
	["bullets", "Пули и ракеты врагов видно?", ["Всегда", "Иногда терялись", "Часто терялись"], 0],
	["lag", "Игра тормозила?", ["Нет", "Иногда", "Часто"], 0],
]
var _vis := {}
var _vis_btns := {}
var _boring: TextEdit
var _unclear: TextEdit
var _comment: TextEdit
var _status: Label
var _send_btn: Button
var _busy := false
var _flush_after_open := false


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
	sb.set_content_margin_all(36)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(1180, 0)
	panel.position = Vector2(-590, -500)
	panel.size = Vector2(1180, 1000)
	_root.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	var title := Label.new()
	title.text = "ОТЧЁТ ТЕСТЕРА"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Menu.C_AMBER)
	v.add_child(title)
	var sub := Label.new()
	sub.text = "Уйдёт организатору теста: ваши ответы, статистика этого вылета, ОС и видеокарта, технический журнал игры. Личных данных нет."
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 17)
	sub.add_theme_color_override("font_color", Menu.C_DIM)
	v.add_child(sub)

	v.add_child(_caption("Как вам вылет? (1 — плохо, 5 — отлично)"))
	var hr := HBoxContainer.new()
	hr.add_theme_constant_override("separation", 10)
	for i in 5:
		var b := _toggle(str(i + 1), Vector2(80, 46))
		b.pressed.connect(_set_rating.bind(i + 1))
		_rate_btns.append(b)
		hr.add_child(b)
	v.add_child(hr)

	v.add_child(_caption("Хочется сразу сыграть ещё?"))
	var ha := HBoxContainer.new()
	ha.add_theme_constant_override("separation", 10)
	for t in ["Да", "Может быть", "Нет"]:
		var b := _toggle(t, Vector2(170, 46))
		b.pressed.connect(_set_again.bind(t))
		_again_btns.append(b)
		ha.add_child(b)
	v.add_child(ha)

	# картинка и камера: по два вопроса в ряд
	for row in [[0, 1], [2, 3]]:
		var hq := HBoxContainer.new()
		hq.add_theme_constant_override("separation", 30)
		for qi in row:
			var q: Array = VIS_Q[qi]
			var col := VBoxContainer.new()
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			col.add_child(_caption(q[1]))
			var hb2 := HBoxContainer.new()
			hb2.add_theme_constant_override("separation", 6)
			var btns: Array[Button] = []
			for t in q[2]:
				var b := _toggle(t, Vector2(q[3], 42))
				b.add_theme_font_size_override("font_size", 17)
				b.pressed.connect(_set_vis.bind(q[0], t))
				btns.append(b)
				hb2.add_child(b)
			_vis_btns[q[0]] = btns
			col.add_child(hb2)
			hq.add_child(col)
		v.add_child(hq)

	v.add_child(_caption("Что было скучно или раздражало?"))
	_boring = _area()
	v.add_child(_boring)
	v.add_child(_caption("Что было непонятно?"))
	_unclear = _area()
	v.add_child(_unclear)
	v.add_child(_caption("Баги, вылеты, тормоза и всё остальное"))
	_comment = _area()
	v.add_child(_comment)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 17)
	hb.add_child(_status)
	var cancel := Button.new()
	cancel.text = "Отмена"
	cancel.custom_minimum_size = Vector2(170, 54)
	cancel.pressed.connect(close)
	hb.add_child(cancel)
	_send_btn = Button.new()
	_send_btn.text = "ОТПРАВИТЬ"
	_send_btn.custom_minimum_size = Vector2(240, 54)
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


func _caption(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 20)
	return l


func _toggle(t: String, sz: Vector2) -> Button:
	var b := Button.new()
	b.text = t
	b.toggle_mode = true
	b.custom_minimum_size = sz
	var on := StyleBoxFlat.new()
	on.bg_color = Menu.C_AMBER
	on.set_content_margin_all(6)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_color_override("font_pressed_color", Color(0.08, 0.07, 0.05))
	b.add_theme_color_override("font_hover_pressed_color", Color(0.08, 0.07, 0.05))
	return b


func _area() -> TextEdit:
	var te := TextEdit.new()
	te.custom_minimum_size = Vector2(0, 72)
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	te.placeholder_text = "можно оставить пустым"
	return te


func _set_rating(n: int) -> void:
	_rating = n
	for i in _rate_btns.size():
		_rate_btns[i].button_pressed = (i + 1 == n)


func _set_vis(key: String, t: String) -> void:
	_vis[key] = t
	for b in _vis_btns[key]:
		(b as Button).button_pressed = (b.text == t)


func _vis_text() -> String:
	var parts := PackedStringArray()
	for q in VIS_Q:
		if _vis.has(q[0]):
			parts.append("%s: %s" % [q[0], _vis[q[0]]])
	return "; ".join(parts)


func _set_again(t: String) -> void:
	_again = t
	for b in _again_btns:
		b.button_pressed = (b.text == t)


func open() -> void:
	if Main.REPORT_URL == "":
		return
	_set_rating(0)
	_set_again("")
	_vis.clear()
	for k in _vis_btns:
		for b in _vis_btns[k]:
			(b as Button).button_pressed = false
	for te in [_boring, _unclear, _comment]:
		(te as TextEdit).text = ""
	_status.text = ""
	_status.remove_theme_color_override("font_color")
	_send_btn.disabled = false
	visible = true
	_boring.grab_focus()


func close() -> void:
	visible = false


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


func _payload() -> Dictionary:
	var m := Main.I
	var syn := PackedStringArray()
	if is_instance_valid(m.player):
		for id in m.player.syn:
			syn.append(String(Cards.syn_def(m.player, id)["title"]))
	var scr := DisplayServer.screen_get_size()
	return {
		"token": TOKEN,
		"build": Main.BUILD,
		"tester": _tester_id(),
		"sent_at": Time.get_datetime_string_from_system(),
		"cls": String(PlaneClasses.DATA[m.cls_id]["title"]) if PlaneClasses.DATA.has(m.cls_id) else m.cls_id,
		"outcome": "эвакуация" if m.last_outcome == "evac" else ("гибель" if m.last_outcome == "dead" else m.last_outcome),
		"run_seconds": int(m.run_time),
		"level": m.level,
		"kills": m.kills,
		"synergies": ", ".join(syn),
		"rating": _rating if _rating > 0 else "",
		"again": _again,
		"boring": _boring.text.strip_edges(),
		"unclear": _unclear.text.strip_edges(),
		# ответы про картинку — и отдельным полем, и в начале комментария (уже развёрнутый приёмник их не знает)
		"visual": _vis_text(),
		"comment": ("[%s] " % _vis_text() if _vis_text() != "" else "") + _comment.text.strip_edges(),
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
		"build": Main.BUILD,
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
	var q := _load_queue()
	q.append(_payload())
	_save_queue(q)
	_send_btn.disabled = true
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
		_fail("не удалось начать отправку (%d)" % err)


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	# Apps Script пишет строку и отвечает 302 → при max_redirects = 0 это RESULT_REDIRECT_LIMIT_REACHED
	var ok := (result == HTTPRequest.RESULT_SUCCESS or result == HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED) and code >= 200 and code < 400
	var txt := body.get_string_from_utf8()
	if ok and txt.begins_with("bad token"):
		ok = false
	if not ok:
		_fail("нет связи с сервером (код %d / %d)" % [result, code])
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
		_status.text = "Не отправилось: %s. Отчёт сохранён и уйдёт при следующей отправке или запуске игры." % why
		_status.add_theme_color_override("font_color", Color(1.0, 0.7, 0.4))
		Main.I.report_sent = true   # сохранён в очереди — повторно заполнять не нужно
