class_name TuningPanel
extends CanvasLayer
## Панель параметров (F1): ползунки для всех цифр полёта, оружия и врагов.
## Пока панель открыта, игра на паузе. «Сохранить» пишет значения в user://tuning.json —
## при следующем запуске они подхватятся автоматически.

var _sliders := {}
var _values := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	visible = false

	var theme := Theme.new()
	theme.default_font = Hud.ui_font()
	theme.default_font_size = 16

	var panel := PanelContainer.new()
	panel.theme = theme
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.09, 0.12, 0.97)
	bg.set_content_margin_all(14)
	bg.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", bg)
	panel.position = Vector2(20, 20)
	add_child(panel)

	var outer := VBoxContainer.new()
	panel.add_child(outer)

	var title := Label.new()
	title.text = "Параметры прототипа (F1 — закрыть)"
	outer.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(700, 760)
	outer.add_child(scroll)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)

	for key in Tuning.RANGES:
		var info: Array = Tuning.RANGES[key]
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = info[4]
		l.custom_minimum_size.x = 400
		var s := HSlider.new()
		s.min_value = info[0]
		s.max_value = info[1]
		s.step = info[2]
		s.custom_minimum_size.x = 220
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.value = Tuning.g(key)
		var v := Label.new()
		v.custom_minimum_size.x = 70
		v.text = _fmt(s.value)
		s.value_changed.connect(func(val: float) -> void:
			Tuning.set_param(key, val)
			v.text = _fmt(val))
		row.add_child(l)
		row.add_child(s)
		row.add_child(v)
		vb.add_child(row)
		_sliders[key] = s
		_values[key] = v

	var buttons := HBoxContainer.new()
	outer.add_child(buttons)
	var save := Button.new()
	save.text = "Сохранить"
	save.pressed.connect(func() -> void: Tuning.save_params())
	buttons.add_child(save)
	var reset := Button.new()
	reset.text = "Сбросить к стандартным"
	reset.pressed.connect(func() -> void:
		Tuning.reset()
		_refresh())
	buttons.add_child(reset)
	var close := Button.new()
	close.text = "Закрыть"
	close.pressed.connect(toggle)
	buttons.add_child(close)


func toggle() -> void:
	visible = not visible
	if visible:
		_refresh()
	get_tree().paused = visible


func _refresh() -> void:
	for key in _sliders:
		var s: HSlider = _sliders[key]
		s.set_value_no_signal(Tuning.g(key))
		var v: Label = _values[key]
		v.text = _fmt(s.value)


func _fmt(val: float) -> String:
	if absf(val - round(val)) < 0.0001:
		return str(int(round(val)))
	return "%.2f" % val
