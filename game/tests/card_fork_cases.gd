extends RefCounted
## Checks for `card_fork_test.gd` (see there): when the level-up row is the «or-or» fork.

var _failed := 0
var _checks := 0


## Run every check; returns [checks, failed]
func run() -> Array:
	var br := {"kind": "branch", "first": true}
	var rank := {"kind": "branch", "first": false}
	var prof := {"kind": "profile"}
	var up := {"kind": "weapon_up"}
	var mod := {"kind": "module"}
	_check(not Cards.is_fork([]), "empty row is not a fork")
	_check(Cards.is_fork([br, br]), "two first-branch cards are the mastery fork")
	_check(Cards.is_fork([prof, prof]), "two profile cards are the profile fork")
	_check(Cards.is_fork([prof, prof, prof]), "three profiles (third from the hangar) are a fork")
	_check(not Cards.is_fork([br, up, mod, up]), "s15: one profile-rank card among ordinary ones is not a fork")
	_check(not Cards.is_fork([up, br, mod]), "a first-branch card later in the row is not a fork either")
	_check(not Cards.is_fork([br]), "a lone first-branch card is not a fork")
	_check(not Cards.is_fork([rank, rank]), "branch rank cards are ordinary cards")
	_check(not Cards.is_fork([prof, up]), "profile with an ordinary card is not a fork")
	return [_checks, _failed]


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)
