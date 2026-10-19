class_name Loc
## Перевод (docs/localization.md): ключ — русская фраза. Строки с числами и склейки
## переводятся до подстановки: Loc.t("Прочность %d / %d") % [hp, max_hp].
## Без таблицы перевода (или для русского) строка возвращается как есть.


static func t(s: String) -> String:
	return TranslationServer.translate(s)


## Вывод на экран: перевод + в нерусских языках «ёлочки» → “лапки” (часть кавычек стоит в шаблонах без
## русских букв, например "«%s»", и в таблицу перевода не попадает)
static func out(s: String) -> String:
	if TranslationServer.get_locale().begins_with("ru"):
		return TranslationServer.translate(s)
	if _out_cache.has(s):
		return _out_cache[s]
	var res := TranslationServer.translate(s)
	if res == s and _CYR.search(s) != null:
		res = _deep(s)
	res = res.replace("«", "\u201c").replace("»", "\u201d")
	if _out_cache.size() > 4000:
		_out_cache.clear()
	_out_cache[s] = res
	return res


## Строка, собранная в коде из кусков, целиком в таблице не найдена: переводим по частям.
## Уровни разделителей: сначала крупные (« · », перенос, «: »), потом мелкие (скобки, «→», запятые, кавычки).
## Кусок пробуем: как есть, без пробелов по краям, как название карточки, с числами через %d,
## без числового хвоста («Звено 1/11» → «Звено» + « 1/11»)
const _SEPS := ["( · |\\n|\n|: |：|  | — )", "(\\(|\\)|（|）|，|、| → |, | \\+ |«|»|“|”|\\[|\\])"]
static var _CYR := RegEx.create_from_string("[\u0410-\u044f\u0401\u0451]")
static var _SEP := [RegEx.create_from_string(_SEPS[0]), RegEx.create_from_string(_SEPS[1])]
static var _NUM := RegEx.create_from_string("\\d+")
static var _TAIL := RegEx.create_from_string("^(.*?[\u0410-\u044f\u0401\u0451.»)])(\\s*[\\d/×:.,%+−-]+\\s*✓?)$")
static var _out_cache := {}


static func _deep(s: String) -> String:
	var t := title(s)
	return t if t != s else _split(s, 0)


static func _split(s: String, lvl: int) -> String:
	var out := ""
	var last := 0
	for m in (_SEP[lvl] as RegEx).search_all(s):
		out += _piece(s.substr(last, m.get_start() - last), lvl) + m.get_string()
		last = m.get_end()
	return out + _piece(s.substr(last), lvl)


static func _piece(p: String, lvl: int) -> String:
	if p.strip_edges() == "" or _CYR.search(p) == null:
		return p
	var r := _try(p)
	if r != "":
		return r
	var core := p.strip_edges()
	var lead := p.substr(0, p.length() - p.lstrip(" ").length())
	var trail := p.substr(p.rstrip(" ").length())
	if core.begins_with("✓ "):
		lead += "✓ "
		core = core.substr(2)
	if core.ends_with(" ✓"):
		trail = " ✓" + trail
		core = core.left(-2)
	r = _try(core)
	if r == "":
		var m := _TAIL.search(core)
		if m != null:
			var h := _try(m.get_string(1))
			if h != "":
				r = h + m.get_string(2)
	if r == "" and lvl == 0:
		r = _split(core, 1)
	return lead + (r if r != "" else core) + trail


## Перевод куска или "" если не нашёлся
static func _try(p: String) -> String:
	var r := TranslationServer.translate(p)
	if r != p:
		return r
	r = title(p)
	if r != p:
		return r
	if _NUM.search(p) != null:
		var nums := []
		for m in _NUM.search_all(p):
			nums.append(int(m.get_string()))
		var tpl := _NUM.sub(p, "%d", true)
		var tr2 := TranslationServer.translate(tpl)
		if tr2 != tpl and tpl.count("%") == nums.size() and tr2.count("%d") == nums.size():
			return tr2 % nums
	return ""


## Названия карточек собираются по шаблонам («%s: уровень %d», «… (1 → 2)») и в таком виде
## пишутся в лог тестера, поэтому переводятся только на выводе: находим шаблон, переводим его
## и каждую вставку (вставки — тоже названия, рекурсивно)
const TITLE_FORMATS := [
	"%s: улучшение", "%s: уровень %d", "Ведомый: %s", "%s Э+ (%d → %d)", "«Дятел» Э+ (%d → %d)",
	"Звено: слётанность — %s %d (ур. %d → %d)", "МОДЕРНИЗАЦИЯ: %s", "СВЯЗКА «%s» — слот %d", "МАСТЕРСТВО: %s",
	"%s (%d → %d)",   # последним: общий хвост «(1 → 2)»
]
static var _title_re: Array = []


static func title(s: String) -> String:
	var res := TranslationServer.translate(s)
	if res != s or TranslationServer.get_locale().begins_with("ru"):
		return res
	if _title_re.is_empty():
		for f in TITLE_FORMATS:
			var rx := ""
			for ch in f:
				rx += ("\\" + ch) if "()[].*+?^$|\\{}".contains(ch) else ch
			rx = rx.replace("%s", "(.+?)").replace("%d", "(\\d+)")
			_title_re.append([f, RegEx.create_from_string("^" + rx + "$")])
	for fr in _title_re:
		var m: RegExMatch = fr[1].search(s)
		if m == null:
			continue
		var f: String = fr[0]
		var args := []
		var kinds := RegEx.create_from_string("%[sd]").search_all(f)
		for i in kinds.size():
			var v := m.get_string(i + 1)
			args.append(title(v) if kinds[i].get_string() == "%s" else int(v))
		return TranslationServer.translate(f) % args
	return s
