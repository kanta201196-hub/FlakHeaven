extends SceneTree
## Unit tests for `Terms.parse`: the card-pick text markup (combat UI v2, step 8). Rules
## pinned here: a term is found by its word forms in the current language (a stem marked
## with `*` matches any ending, a plain form only the whole word); only the first mention
## of each term is highlighted; explicit `[[id]]` / `[[id|text]]` markup wins; numbers with
## their sign, ×, % are a separate kind; a term never links to itself; the segments always
## join back to the visible text.
## Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0
var _checks := 0


func _init() -> void:
	_test_plain_text()
	_test_stem_forms()
	_test_whole_word_forms()
	_test_first_mention_only()
	_test_explicit_markup()
	_test_numbers()
	_test_self_link()
	_test_other_languages()
	_test_join_back()
	_test_every_term_has_text()
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


## Kinds and texts of segments as "kind:text" strings, for compact asserts.
func _flat(segs: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for s: Dictionary in segs:
		out.append("%s:%s" % [s["kind"], s["text"]])
	return out


func _ids(segs: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for s: Dictionary in segs:
		if s["kind"] == Terms.TERM:
			out.append(String(s["id"]))
	return out


func _join(segs: Array) -> String:
	var s := ""
	for g: Dictionary in segs:
		s += String(g["text"])
	return s


func _test_plain_text() -> void:
	var segs := Terms.parse("Просто текст без терминов", "ru")
	_check(segs.size() == 1 and segs[0]["kind"] == Terms.TEXT, "plain text is one text segment")
	_check(Terms.parse("", "ru").is_empty(), "empty text gives no segments")


func _test_stem_forms() -> void:
	var segs := Terms.parse("Каждый 3-й залп ракет", "ru")
	_check(_ids(segs) == PackedStringArray(["salvo"]), "stem «залп*» finds «залп»")
	segs = Terms.parse("Ракета залпа прилипает", "ru")
	_check(_ids(segs) == PackedStringArray(["salvo"]) and "term:залпа" in _flat(segs), "stem keeps the ending inside the term")
	segs = Terms.parse("Залпы ракет", "ru")
	_check("term:Залпы" in _flat(segs), "match ignores case and keeps the original case")
	segs = Terms.parse("подзалп", "ru")
	_check(_ids(segs).is_empty(), "a stem only matches at the start of a word")


func _test_whole_word_forms() -> void:
	var segs := Terms.parse("Урон по асам +50%", "ru")
	_check(_ids(segs) == PackedStringArray(["ace"]), "whole-word form «асам» found")
	segs = Terms.parse("Асфальт и касание", "ru")
	_check(_ids(segs).is_empty(), "whole-word form does not match inside longer words")


func _test_first_mention_only() -> void:
	var segs := Terms.parse("Залп, ещё залп и снова залп", "ru")
	_check(_ids(segs).size() == 1, "only the first mention of a term is highlighted")


func _test_explicit_markup() -> void:
	var segs := Terms.parse("Берите [[module|детали]] на нос", "ru")
	_check(_flat(segs) == PackedStringArray(["text:Берите ", "term:детали", "text: на нос"]), "[[id|text]] shows the text as the term")
	_check(_ids(segs) == PackedStringArray(["module"]), "[[id|text]] keeps the id")
	segs = Terms.parse("[[salvo]] готов", "ru")
	_check(_flat(segs)[0] == "term:" + Terms.title("salvo"), "[[id]] shows the term title")
	segs = Terms.parse("[[nope|слово]] тут", "ru")
	_check(_flat(segs)[0] == "text:слово", "unknown id falls back to plain text")


func _test_numbers() -> void:
	var segs := Terms.parse("урон +30 %, радиус ×1,5 и −10%", "ru")
	var nums := PackedStringArray()
	for s: Dictionary in segs:
		if s["kind"] == Terms.NUM:
			nums.append(String(s["text"]))
	_check(nums == PackedStringArray(["+30 %", "×1,5", "−10%"]), "numbers keep sign, ×, decimal comma and percent: %s" % [nums])
	segs = Terms.parse("Скорость 113% → 134%", "ru")
	_check("num:113%" in _flat(segs) and "num:134%" in _flat(segs), "both sides of an arrow are numbers")
	segs = Terms.parse("3-й залп", "ru")
	_check("num:3" in _flat(segs), "an ordinal keeps its digits as a number")


func _test_self_link() -> void:
	var segs := Terms.parse(Terms.desc("salvo"), "ru", &"salvo")
	_check(not _ids(segs).has("salvo"), "a term's own description does not link to itself")


func _test_other_languages() -> void:
	var segs := Terms.parse("Forward rocket salvo, ×3 damage to ground targets", "en")
	_check(_ids(segs) == PackedStringArray(["salvo", "ground"]), "English forms, multi-word form: %s" % [_ids(segs)])
	segs = Terms.parse("向前齐射火箭弹，对地面目标伤害×3", "zh_CN")
	_check(_ids(segs) == PackedStringArray(["salvo", "ground"]), "Chinese forms match inside text without spaces")
	segs = Terms.parse("Каждый залп", "en")
	_check(_ids(segs).is_empty(), "Russian forms are not used for English")


func _test_join_back() -> void:
	for t: String in ["Ракета залпа прилипает и через 0,5 с даёт объёмный взрыв 130 пикс. (урон ×1,5)",
			"[[module|Модуль]]: +18% урона, перезарядка −10%", "Asphalt aces, ×2", "齐射×3"]:
		var segs := Terms.parse(t, "ru" if t.contains("а") else "en")
		var want := t.replace("[[module|Модуль]]", "Модуль")
		_check(_join(segs) == want, "segments join back to the visible text: " + t)


func _test_every_term_has_text() -> void:
	for id: StringName in Terms.DICT:
		_check(Terms.title(id) != "" and Terms.desc(id) != "", "term %s has title and description" % id)
		var f: Dictionary = Terms.DICT[id]["forms"]
		_check(f.has("ru") and f.has("en") and f.has("zh"), "term %s has forms in ru, en and zh" % id)
