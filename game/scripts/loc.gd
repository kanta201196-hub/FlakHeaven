class_name Loc
## Перевод (docs/localization.md): ключ — русская фраза. Строки с числами и склейки
## переводятся до подстановки: Loc.t("Прочность %d / %d") % [hp, max_hp].
## Без таблицы перевода (или для русского) строка возвращается как есть.


static func t(s: String) -> String:
	return TranslationServer.translate(s)


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
