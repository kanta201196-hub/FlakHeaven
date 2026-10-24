class_name SettingsRows
extends RefCounted
## Pure helpers behind the settings list (UI-01 step 2): scroll limits, scrolling that follows
## keyboard/gamepad focus, and slider steps. Kept apart from drawing so the rules have unit
## tests (`game/tests/settings_rows_test.gd`).


## Scroll offset limited to [0, content − view]; a list shorter than the view never scrolls.
static func clamp_scroll(scroll: float, view_h: float, content_h: float) -> float:
	return clampf(scroll, 0.0, maxf(0.0, content_h - view_h))


## Scroll that shows the focused row (`top`…`bottom`, in content coordinates) with `margin`
## above or below it; moves only as far as needed so the list does not jump on every step.
static func follow(scroll: float, top: float, bottom: float, view_h: float, content_h: float, margin: float) -> float:
	var s := scroll
	if bottom + margin > s + view_h:
		s = bottom + margin - view_h
	if top - margin < s:
		s = top - margin
	return clamp_scroll(s, view_h, content_h)


## One left/right press on a slider: `dir` steps of `step`, snapped and kept inside [lo, hi].
static func step_value(v: float, lo: float, hi: float, step: float, dir: int) -> float:
	return clampf(snappedf(v + step * dir, step), lo, hi)
