class_name HudCutscene
extends HudKit
## Letterbox and captions of a story scene (`Cutscene`): black bars top and bottom, a title or a radio-style
## caption (speaker plate + text) in the lower bar, the skip hint after a second, black fades at both ends.
## Step 11: when the scene has key art (`Cutscene.art`) it is drawn first, covering the screen with a slow push-in
## (`CutsceneKeys.art_rect`), and a soft dark gradient above the lower bar keeps the title readable on any picture.
## Drawn in code like every screen (ADR-05); tokens from UiStyle.

const BAR := 0.12          # bar height, share of the screen
const HINT_FROM := 1.0     # s before «Пропустить» shows
const HINT_TO := 4.5       # s when it has faded
const ART_FOOT := 0.22     # share of the screen: the dark gradient above the lower bar when key art is shown
const ART_FOOT_STEPS := 14


func draw(m: Main, size: Vector2) -> void:
	var bar := size.y * BAR
	var t := Cutscene.t
	if bool(Cutscene.def.get("black", false)):   # step 8: the epilogue card — captions over black, no world
		ctrl.draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	if Cutscene.art != null:   # step 11: key art under the captions — covers the screen, slow push-in, dark foot for the title
		var dim := 0.8 if bool(Cutscene.def.get("black", false)) else 1.0
		ctrl.draw_texture_rect(Cutscene.art, CutsceneKeys.art_rect(size, Cutscene.art.get_size(), t, float(Cutscene.def.get("dur", 1.0))), false, Color(dim, dim, dim))
		var foot := size.y * ART_FOOT
		for i in ART_FOOT_STEPS:
			var y0 := size.y - bar - foot + foot * i / ART_FOOT_STEPS
			ctrl.draw_rect(Rect2(0, y0, size.x, foot / ART_FOOT_STEPS + 1.0), Color(0, 0, 0, 0.55 * pow(float(i + 1) / ART_FOOT_STEPS, 1.6)))
	ctrl.draw_rect(Rect2(0, 0, size.x, bar), Color.BLACK)
	ctrl.draw_rect(Rect2(0, size.y - bar, size.x, bar), Color.BLACK)
	var line := Cutscene.line_at(Cutscene.def, t)
	if not line.is_empty():
		var a := float(line[2])
		var speaker := String(line[0])
		var text := String(line[1])
		if speaker == "":
			# title card: large, centred over the picture, just above the lower bar
			_ctext(size.y - bar - 92.0, Loc.out(text).to_upper(), 40, Color(UiStyle.ACCENT, a))
		else:
			var y := size.y - bar + bar * 0.5 - 24.0
			var font := ui_font()
			var plate := Loc.out("«%s»" % speaker)
			var w := font.get_string_size(plate, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
			var tw := minf(size.x * 0.62, 980.0)
			var x := (size.x - tw) * 0.5
			var enemy := line.size() > 3 and bool(line[3])   # step 7: an enemy voice (Baron) gets the red plate
			_text(Vector2(x, y), plate, 18, Color(UiStyle.DANGER if enemy else UiStyle.ACCENT, a))
			_para(Vector2(x + w + 18.0, y - 2.0), text, tw - w - 18.0, 22, Color(1, 1, 1, a))
	if t > HINT_FROM:
		var ha := clampf(1.0 - (t - HINT_FROM) / (HINT_TO - HINT_FROM), 0.0, 1.0) * 0.7
		if ha > 0.0:
			_text(Vector2(size.x - 24.0, bar * 0.5 - 10.0), Loc.t("Пропустить — любая клавиша"), 16, Color(0.85, 0.88, 0.95, ha), HORIZONTAL_ALIGNMENT_RIGHT, 500.0)
	var fade := Cutscene.fade_at(t, float(Cutscene.def.get("dur", 1.0)))
	if fade > 0.0:
		ctrl.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, fade))
