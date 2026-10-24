class_name Terms
extends RefCounted
## Game terms highlighted in card texts on the card pick screen (combat UI v2, step 8,
## Kanta's Sublight reference «описание умений»): hovering a term opens its explanation,
## and terms inside an explanation open the next one. Card texts stay as they are in the
## translation tables: terms are found by their word forms in the current language, so no
## `.po` key changes. Explicit `[[id]]` or `[[id|shown text]]` markup is also understood
## for texts written later. Titles and explanations are translation keys (`Loc.t`).
## Unit tests: game/tests/terms_test.gd.

## Segment kinds returned by `parse`
const TEXT := &"text"
const TERM := &"term"
const NUM := &"num"

## id → title, explanation (Russian keys) and word forms by language. A form ending in `*`
## is a stem and matches any ending; a plain form matches only the whole word. Chinese has
## no spaces, so its forms match anywhere.
const DICT := {
	&"salvo": {"title": "Залп", "desc": "Несколько ракет или бомб уходят разом. Перезарядка идёт на весь залп, а не на каждую ракету.",
		"forms": {"ru": ["залп*"], "en": ["salvo*"], "zh": ["齐射"]}},  # i18n-skip
	&"reload": {"title": "Перезарядка", "desc": "Время между пусками оружия или применениями навыка. Чем она короче, тем чаще бьёт.",
		"forms": {"ru": ["перезаряд*"], "en": ["reload*", "cooldown*"], "zh": ["装填", "冷却"]}},  # i18n-skip
	&"homing": {"title": "Самонаведение", "desc": "Ракета сама находит цель и доворачивает за ней. Уклонение и ловушки сбивают такой захват у вражеских ракет.",
		"forms": {"ru": ["самонаводящ*", "наводящ*"], "en": ["homing"], "zh": ["追踪"]}},  # i18n-skip
	&"module": {"title": "Модуль", "desc": "Деталь самолёта: усиливает пушку, ракеты, двигатель или броню. Мест под модули немного, занятые видны в паузе.",
		"forms": {"ru": ["модул*"], "en": ["module*"], "zh": ["模块"]}},  # i18n-skip
	&"evolution": {"title": "Модернизация", "desc": "Оружие 5-го уровня вместе с нужными модулями превращается в новое, более сильное. Рецепты — в справочнике.",
		"forms": {"ru": ["модернизац*"], "en": ["upgrade*"], "zh": ["改装"]}},  # i18n-skip
	&"synergy": {"title": "Связка", "desc": "Сильный бонус, который открывается, когда в специализации набрано достаточно очков тегов.",
		"forms": {"ru": ["связк*"], "en": ["synerg*"], "zh": ["羁绊", "联动"]}},  # i18n-skip
	&"course": {"title": "Специализация", "desc": "Выбранное направление сборки: карточки её тегов ведут к связке. Сменить можно на экране выбора за один переброс.",
		"forms": {"ru": ["специализац*"], "en": ["specialization*"], "zh": ["专精"]}},  # i18n-skip
	&"reroll": {"title": "Переброс", "desc": "Показать другие карточки вместо этих. За каждого сбитого аса добавляется ещё один.",
		"forms": {"ru": ["переброс*"], "en": ["reroll*"], "zh": ["重抽"]}},  # i18n-skip
	&"afterburner": {"title": "Форсаж", "desc": "Короткий рывок на большой скорости, потом перезарядка.",
		"forms": {"ru": ["форсаж*"], "en": ["afterburner*"], "zh": ["加力"]}},  # i18n-skip
	&"evade": {"title": "Уклонение", "desc": "Бочка в сторону: несколько мгновений вы неуязвимы, а ракеты на хвосте теряют захват.",
		"forms": {"ru": ["уклонени*"], "en": ["evade*", "evading", "evasion"], "zh": ["闪避"]}},  # i18n-skip
	&"flares": {"title": "Ловушки", "desc": "Тепловые ловушки: вражеская ракета уходит на вспышку и рвётся возле неё.",
		"forms": {"ru": ["ловушк*"], "en": ["flare*"], "zh": ["干扰弹"]}},  # i18n-skip
	&"pierce": {"title": "Пробитие", "desc": "Снаряд проходит цель насквозь и бьёт следующую на линии.",
		"forms": {"ru": ["пробива*", "пробитие*"], "en": ["pierce*", "piercing"], "zh": ["穿透"]}},  # i18n-skip
	&"ground": {"title": "Наземные цели", "desc": "ПВО, колонны, техника и укрытия на земле. Самолёты к ним не относятся.",
		"forms": {"ru": ["наземн*"], "en": ["ground target*"], "zh": ["地面目标"]}},  # i18n-skip
	&"wingman": {"title": "Ведомый", "desc": "Самолёт вашего звена: держит строй и бьёт сам. Кого он атакует первым, выбирается в паузе.",
		"forms": {"ru": ["ведом*"], "en": ["wingm*"], "zh": ["僚机"]}},  # i18n-skip
	&"ace": {"title": "Ас", "desc": "Сильный вражеский пилот со своей полосой прочности. Сбитый ас добавляет переброс и исключение карточки.",
		"forms": {"ru": ["ас", "аса", "асу", "асом", "асе", "асы", "асов", "асам", "асами", "асах"], "en": ["ace", "aces"], "zh": ["王牌"]}},  # i18n-skip
}

static var _markup := RegEx.create_from_string("\\[\\[([a-z_0-9]+)(?:\\|([^\\]]*))?\\]\\]")
## Number with sign, decimal comma or point, optional % (also after a space), or ×N
static var _num := RegEx.create_from_string("×\\d+(?:[.,]\\d+)?|[+−-]?\\d+(?:[.,]\\d+)?(?:[  ]?%)?")


## Translated title of term `id`.
static func title(id: StringName) -> String:
	return Loc.t(String(DICT[id]["title"])) if DICT.has(id) else ""


## Translated explanation of term `id`.
static func desc(id: StringName) -> String:
	return Loc.t(String(DICT[id]["desc"])) if DICT.has(id) else ""


## Splits visible text into segments {kind, text, id}: TEXT, TERM (first mention of each
## term) and NUM. `lang` — locale ("" = current); `skip` — a term not to link (the one
## whose explanation is being parsed). Markup brackets are removed from the result.
static func parse(text: String, lang := "", skip: StringName = &"") -> Array:
	if lang == "":
		lang = TranslationServer.get_locale()
	var lk := "zh" if lang.begins_with("zh") else ("en" if lang.begins_with("en") else "ru")
	var out: Array = []
	var seen := {skip: true}
	var pos := 0
	for m in _markup.search_all(text):
		_auto(text.substr(pos, m.get_start() - pos), lk, seen, out)
		var id := StringName(m.get_string(1))
		var shown := m.get_string(2) if m.get_string(2) != "" else title(id)
		if DICT.has(id) and not seen.has(id):
			seen[id] = true
			out.append({"kind": TERM, "text": shown, "id": id})
		else:
			_numbers(shown if DICT.has(id) else m.get_string(2), out)
		pos = m.get_end()
	_auto(text.substr(pos), lk, seen, out)
	return out


## Finds term forms in a markup-free piece and appends text, term and number segments.
static func _auto(s: String, lk: String, seen: Dictionary, out: Array) -> void:
	if s == "":
		return
	var low := s.to_lower()
	var hits: Array = []   # [start, end, id]
	for id: StringName in DICT:
		if seen.has(id):
			continue
		var best: Array = []
		for f: String in DICT[id]["forms"][lk]:
			var h := _find(low, f, lk == "zh")
			if not h.is_empty() and (best.is_empty() or h[0] < best[0]):
				best = h
		if not best.is_empty():
			hits.append([best[0], best[1], id])
	hits.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] > b[1]))
	var pos := 0
	for h: Array in hits:
		if int(h[0]) < pos:
			continue   # overlaps an earlier term
		_numbers(s.substr(pos, int(h[0]) - pos), out)
		out.append({"kind": TERM, "text": s.substr(int(h[0]), int(h[1]) - int(h[0])), "id": h[2]})
		seen[h[2]] = true
		pos = int(h[1])
	_numbers(s.substr(pos), out)


## First match of form `f` in lower-case `low`: [start, end] or []. Word boundaries are
## checked unless `anywhere` (Chinese).
static func _find(low: String, f: String, anywhere: bool) -> Array:
	var stem := f.ends_with("*")
	var w := f.trim_suffix("*")
	var at := low.find(w)
	while at >= 0:
		var end := at + w.length()
		if anywhere:
			return [at, end]
		if at == 0 or not _letter(low[at - 1]):
			if stem:
				while end < low.length() and _letter(low[end]):
					end += 1
				return [at, end]
			if end >= low.length() or not _letter(low[end]):
				return [at, end]
		at = low.find(w, at + 1)
	return []


## True for letters of cased alphabets (Latin, Cyrillic) and digits; CJK counts as a
## boundary, which is fine because Chinese forms skip boundary checks.
static func _letter(c: String) -> bool:
	return c.to_lower() != c.to_upper() or c.is_valid_int()


## Appends `s` split into TEXT and NUM segments.
static func _numbers(s: String, out: Array) -> void:
	if s == "":
		return
	var pos := 0
	for m in _num.search_all(s):
		if m.get_start() > pos:
			out.append({"kind": TEXT, "text": s.substr(pos, m.get_start() - pos), "id": &""})
		out.append({"kind": NUM, "text": m.get_string(), "id": &""})
		pos = m.get_end()
	if pos < s.length():
		out.append({"kind": TEXT, "text": s.substr(pos), "id": &""})
