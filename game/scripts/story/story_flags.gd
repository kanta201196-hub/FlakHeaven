class_name StoryFlags
extends RefCounted
## Pure rules of the Highlands story (plan `docs/superpowers/plans/2026-10-31-highlands-story.md`, step 1):
## when a story scene plays and which «again» line a recurring enemy pilot says. No engine state here, so the
## rules are unit-tested (`game/tests/story_flags_test.gd`); `Campaign` keeps the flags and calls these.

## Setting «Заставки»: on the first clear of an operation only / always / never.
const MODE_FIRST := 0
const MODE_ALWAYS := 1
const MODE_NEVER := 2
const MODES := ["при первом прохождении", "всегда", "никогда"]


## Whether a scene (intro, outro, hangar dialogue) plays now. `seen` — the scene was shown before (campaign flag).
## The player's setting wins over the flag: «всегда» replays scenes already seen, «никогда» skips even new ones.
static func scene_due(mode: int, seen: bool) -> bool:
	match mode:
		MODE_ALWAYS:
			return true
		MODE_NEVER:
			return false
		_:
			return not seen


## Index of the radio line for a pilot met `met` times before, out of `n` lines: the first line is for the first
## meeting only, later meetings cycle through the rest so the line changes from sortie to sortie. One line: always 0.
static func line_index(met: int, n: int) -> int:
	if n <= 1 or met <= 0:
		return 0
	return 1 + (met - 1) % (n - 1)


## Key of a per-operation story line: `<speaker>.<op id>.<moment>`, e.g. "postman.pass.spawn".
static func line_key(speaker: String, op_id: String, moment: String) -> String:
	return "%s.%s.%s" % [speaker, op_id, moment]
