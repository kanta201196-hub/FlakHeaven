class_name Cinematic
extends RefCounted
## In-combat «кино-моменты» of the story (plan step 4, design `docs/story/cutscenes-and-presentation.md` §3.3): a
## banner, 1.5 s of slow-motion that eases back (`AccentCurve`), a music duck and a stinger. No camera move, no loss of
## control, and enemies slow down with the player, so nothing fires that would not have fired anyway. At most three per
## campaign: the first Fortress sighting, Baron down, Grom joining; each once per sortie. The F1 switch
## `story_accents` turns the slow-motion and stinger off (R-22: feel changes stay behind a switch) — the banner stays.
## The autotest log gets `ACCENT <id>`; `BANNER` lines come from the HUD as before.

static var _shown := {}   # accent id → true, this sortie


## New sortie: every accent may play again.
static func reset() -> void:
	_shown.clear()


## Plays accent `id` with banner `text` (a `StoryText.ACCENTS` entry); the second call in a sortie only shows the banner.
static func accent(m: Main, id: String, text: String) -> void:
	Events.banner.emit(text, 3.0)
	if _shown.has(id) or Tuning.g("story_accents") <= 0.0 or m.state != "playing":
		return
	_shown[id] = true
	if OS.get_cmdline_user_args().has("--autotest"):
		print("ACCENT %.0f: %s" % [m.run_time, id])
	m.start_accent()
	m.sfx.duck(AccentCurve.DUCK_DB)
	m.sfx.play("sting_" + id, -6.0)
