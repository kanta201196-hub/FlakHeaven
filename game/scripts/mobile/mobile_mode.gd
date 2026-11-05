extends Node
## Android draft (experiment, branch only): on a phone or tablet the game starts with the
## «мобильный» graphics mix and a touch overlay; on PC this node removes itself at once, so the
## desktop game is untouched. Target: a 2019–2021 mid-range phone (about 4 GB RAM, GLES3-class
## GPU), which is why the Compatibility renderer (`rendering_method.mobile`) and the lowest preset.

## Start mix: preset «Низкое» with cheaper shadows and a 70 % render scale. Whatever preset the
## player picks later is still held under MobileRules.MAX. Lives here, not in GfxPresets, while
## the port is a draft; it moves there if the port gets Kanta's «да».
const MOBILE_OPTS := {"scale": 2, "shadows": GfxPresets.SHADOWS_LOW, "shadow_res": 0, "props": 0,
	"terrain": 0, "effects": 0, "glow": 0}


func _ready() -> void:
	if not is_mobile():
		queue_free()
		return
	MobileRules.on = true
	Settings.set_preset(0)
	Settings.gfx_opts.merge(MOBILE_OPTS, true)
	Settings.gfx_auto = false
	Settings.show_fps = true
	Settings.apply_gfx()
	DisplayServer.screen_set_keep_on(true)
	add_child(preload("res://scripts/mobile/touch_controls.gd").new())


## True on Android/iOS exports, or on PC with `--mobile` (to look at the overlay with a mouse).
static func is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.get_cmdline_user_args().has("--mobile")
