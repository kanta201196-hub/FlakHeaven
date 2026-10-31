class_name DialogFlow
extends RefCounted
## Pure rules of a hangar dialogue scene (plan step 3, design `docs/story/highlands-storyline.md` §11): which step
## comes next after the player's choices, how much of a line the typewriter has shown, and how a scene definition
## is checked. No engine state, so everything here is unit-tested (`game/tests/dialog_flow_test.gd`); `Dialog`
## drives the screen with these.
##
## A scene is `{"steps": [...]}`. A step is either a line
##   `{"who": "crew" | "Купол" | "Гром" | "Ключ", "text": "…", "trait": true, "only": ["choice id", "option"]}`
## (`trait` colours the line with the crew member's trait title; `only` shows the line only after that choice) or a
## choice `{"choice": "id", "prompt": "…", "options": [["label", "option"], …]}`. Choices change words only.

## Typewriter speed, characters per second.
const SPEED := 40.0
## Guests with their own portrait file (`res://art/portraits/story_<id>.png`); the crew uses `Profile.portrait`.
## Enemies never get a portrait (red radio plates only).
const GUESTS := {"Купол": "kupol", "Гром": "grom", "Ключ": "klyuch"}


## Index of the first step at or after `from` that is shown with `choices` (`{choice id: option}`); `steps.size()`
## when the scene is over. A line with `only` is skipped unless that choice was made that way.
static func next_step(steps: Array, from: int, choices: Dictionary) -> int:
	var i := maxi(from, 0)
	while i < steps.size():
		var s: Dictionary = steps[i]
		if not s.has("only"):
			return i
		var cond: Array = s["only"]
		if cond.size() == 2 and String(choices.get(String(cond[0]), "")) == String(cond[1]):
			return i
		i += 1
	return steps.size()


## Part of `text` the typewriter has shown after `t` seconds of the step.
static func shown(text: String, t: float) -> String:
	return text.substr(0, mini(text.length(), int(t * SPEED)))


## Whether the whole line is on screen after `t` seconds.
static func typed(text: String, t: float) -> bool:
	return int(t * SPEED) >= text.length()


## Option id of option `k` of a choice step ("" when out of range).
static func option_id(step: Dictionary, k: int) -> String:
	var opts: Array = step.get("options", [])
	if k < 0 or k >= opts.size():
		return ""
	return String((opts[k] as Array)[1])


## Label of the option `option` of choice `choice_id` in `def` (for the story log); "" when the scene has no such option.
static func option_label(def: Dictionary, choice_id: String, option: String) -> String:
	for s: Dictionary in def.get("steps", []):
		if String(s.get("choice", "")) != choice_id:
			continue
		for o: Array in s.get("options", []):
			if String(o[1]) == option:
				return String(o[0])
	return ""


## Focused option after a move of `dir` (±1) among `n` options, wrapping.
static func move_focus(cur: int, dir: int, n: int) -> int:
	if n <= 0:
		return 0
	return wrapi(cur + dir, 0, n)


## Portrait file of a guest speaker ("" for the crew and for names without a picture).
static func portrait_file(who: String) -> String:
	if not GUESTS.has(who):
		return ""
	return "res://art/portraits/story_%s.png" % String(GUESTS[who])


## Checks a scene definition; returns "" when it is sound, else the first problem found. Used by the unit test over
## every scene in `StoryDialogs`, so a typo in a content step fails `unit.sh` instead of showing up in the hangar.
static func validate(def: Dictionary) -> String:
	if not def.has("steps") or not (def["steps"] is Array) or (def["steps"] as Array).is_empty():
		return "no steps"
	var choice_ids := {}
	for k in (def["steps"] as Array).size():
		var s = (def["steps"] as Array)[k]
		if not (s is Dictionary):
			return "step %d is not a Dictionary" % k
		if s.has("choice"):
			var opts: Array = s.get("options", [])
			if opts.size() < 2 or opts.size() > 3:
				return "step %d: a choice needs 2–3 options" % k
			for o in opts:
				if not (o is Array) or (o as Array).size() != 2 or String(o[0]) == "" or String(o[1]) == "":
					return "step %d: an option is [label, id]" % k
			if String(s.get("prompt", "")) == "":
				return "step %d: a choice needs a prompt" % k
			choice_ids[String(s["choice"])] = true
			continue
		if String(s.get("who", "")) == "" or String(s.get("text", "")) == "":
			return "step %d: a line needs who and text" % k
		if String(s["who"]) != "crew" and not GUESTS.has(String(s["who"])):
			return "step %d: unknown speaker %s" % [k, String(s["who"])]
		if String(s["text"]).length() > 220:
			return "step %d: line longer than 220 characters" % k
		if s.has("only"):
			var cond = s["only"]
			if not (cond is Array) or (cond as Array).size() != 2:
				return "step %d: only is [choice id, option]" % k
			if not choice_ids.has(String(cond[0])):
				return "step %d: only refers to a choice not asked before it" % k
	return ""
