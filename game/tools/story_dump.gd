extends SceneTree
## Prints the Highlands story tables as one JSON object (dialogues by `StoryDialogs.ORDER`, intros, outros, epilogue
## cards, radio, accents, result lines, per-operation enemy lines) for the review page that numbers every text
## (story plan step 9). Run from the repository root:
##   godot --headless --path game --script res://tools/story_dump.gd > /tmp/story.json


func _init() -> void:
	var out := {
		"order": StoryDialogs.ORDER,
		"dialogs": StoryDialogs.SCENES,
		"intro": _scenes(StoryScenes.INTRO),
		"outro": _scenes(StoryScenes.OUTRO),
		"epilogue": _scenes(StoryScenes.EPILOGUE),
		"radio": StoryText.RADIO,
		"accents": StoryText.ACCENTS,
		"result": StoryText.RESULT,
		"op_lines": StoryText.OP_LINES,
	}
	print(JSON.stringify(out))
	quit(0)


## Scene tables without engine values (Vector2 camera keys are not JSON): duration, light and the captions.
static func _scenes(table: Dictionary) -> Dictionary:
	var o := {}
	for k in table:
		var d: Dictionary = table[k]
		o[k] = {"dur": d.get("dur", 0.0), "light": d.get("light", "day"), "black": d.get("black", false), "lines": d.get("lines", [])}
	return o
