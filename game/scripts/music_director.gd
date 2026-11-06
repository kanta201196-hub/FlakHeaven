class_name MusicDirector
extends RefCounted
## Decides which music family plays, from the family Main wants this frame (S16-02).
## Main asks every frame; in s16 the battle and boss/ace music flipped the moment a boss or an ace duel appeared or
## ended, so a sortie with three bosses and several duels changed track a dozen times. The boss music now starts at
## once, but the battle music comes back only after BOSS_HOLD seconds without a boss or ace, and the swap between the
## two fades slower. Pure logic, no audio nodes: `Sfx` owns the players and asks this class.

## Seconds without a boss or ace before the battle music returns.
const BOSS_HOLD := 8.0
## Crossfade between the battle and boss music, s (other swaps keep the s16 1.5 s).
const FADE_COMBAT := 3.0
const FADE_DEFAULT := 1.5

## False = the s16 behaviour (Tuning "music_steady" = 0).
var steady := true
## Family that should play now ("menu", "battle", "boss", "result").
var track := ""
var _calm_t := 0.0


## Takes the wanted family and the real (unscaled) time since the last call; returns the family to play.
func step(want: String, dt: float) -> String:
	if steady and track == "boss" and want == "battle":
		_calm_t += dt
		if _calm_t < BOSS_HOLD:
			return track
	_calm_t = 0.0
	track = want
	return track


## Crossfade length for a swap between two families.
static func fade_time(from: String, to: String, steady_on: bool) -> float:
	var combat := ["battle", "boss"]
	if steady_on and from in combat and to in combat:
		return FADE_COMBAT
	return FADE_DEFAULT
