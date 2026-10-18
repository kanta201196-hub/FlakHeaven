class_name Loc
## Перевод (docs/localization.md): ключ — русская фраза. Строки с числами и склейки
## переводятся до подстановки: Loc.t("Прочность %d / %d") % [hp, max_hp].
## Без таблицы перевода (или для русского) строка возвращается как есть.


static func t(s: String) -> String:
	return TranslationServer.translate(s)
