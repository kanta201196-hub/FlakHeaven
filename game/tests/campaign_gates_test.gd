extends SceneTree
## Unit tests for `CampaignGates` («Подготовка и вылет», Kanta 06.11): the first biome is always open; every other
## biome opens once BIOME_UNLOCK_OPS operations of the first biome are cleared; the first operation of an open biome
## is the one the mission screen falls back to.
## Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0
var _checks := 0


func _init() -> void:
	var n := CampaignGates.BIOME_UNLOCK_OPS
	_check(n == 3, "Kanta 06.11: the second biome needs 3 operations of the first")
	_check(CampaignGates.biome_open("highland", "highland", 0), "first biome: open on a fresh profile")
	_check(not CampaignGates.biome_open("archipelago", "highland", 0), "second biome: closed on a fresh profile")
	_check(not CampaignGates.biome_open("archipelago", "highland", n - 1), "second biome: closed one operation short")
	_check(CampaignGates.biome_open("archipelago", "highland", n), "second biome: open after the 3rd operation")
	_check(CampaignGates.biome_open("archipelago", "highland", n + 1), "second biome: stays open after more")
	_check(CampaignGates.left(0) == n and CampaignGates.left(2) == 1 and CampaignGates.left(5) == 0, "operations left to open")
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)
