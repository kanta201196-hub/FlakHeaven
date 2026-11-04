class_name RadioPick
extends RefCounted
## Picks a radio line so the same phrase does not come back soon (s15 review п. 13: «Ну здравствуй, новичок»
## four times in five minutes, every ace saying the same «Проскочил… бывает»). Lines are shared by all speakers of
## a table, so the memory is per table key, not per ace. Pure logic: `tests/radio_pick_test.gd`.

## Remembered lines per key: key → Array of the last lines said, newest last.
static var _recent := {}


## A random line of `lines` that is not among the last `keep` said under `key` (`keep` defaults to all but one,
## so a table of N lines cycles through N − 1 others before a repeat); remembers it. "" for an empty table.
static func pick(key: String, lines: Array, keep := -1) -> String:
	if lines.is_empty():
		return ""
	var k := lines.size() - 1 if keep < 0 else mini(keep, lines.size() - 1)
	var recent: Array = _recent.get(key, [])
	var fresh := lines.filter(func(l): return not recent.slice(maxi(0, recent.size() - k)).has(l))
	var line: String = String(fresh[randi() % fresh.size()] if not fresh.is_empty() else lines[randi() % lines.size()])
	recent.append(line)
	if recent.size() > lines.size():
		recent.pop_front()
	_recent[key] = recent
	return line


## Forgets every remembered line (tests; a new game session starts fresh anyway).
static func reset() -> void:
	_recent.clear()
