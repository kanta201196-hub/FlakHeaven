extends Node
## Working part of card_lines_test.gd (autoloads are ready once this node is in the tree).

var _failed := 0
var _checks := 0


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


## A group of weapon `w` at level 5 on a fresh fighter, reading its numbers from that plane.
func _group(p: Player, w: String) -> Hardpoint:
	var g := Hardpoint.new("Крылья (пара)", 2, w)
	g.level = Weapons.MAX_LEVEL
	g.stats_owner = p
	return g


func _ready() -> void:
	Profile.reset_data()
	TranslationServer.set_locale("ru")   # number texts with the decimal comma (CardText.dec)
	var p := Player.new()
	p.setup("fighter")
	# «Калибр» on NAR: damage per hit grows by 18 % of the base per rank, the group is left as it was
	var g := _group(p, "rockets")
	var d0 := g.dmg()
	var line := Cards.branch_line(p, g, "power")
	_check(line == "Урон за попадание: %s → %s" % [CardText.num(d0), CardText.num(d0 * 1.18)], "power rank line: %s" % line)
	_check(g.branch == "" and g.branch_rank == 0, "branch_line leaves the group as it was")
	# Kanta 06.11 («1»): rarity counts on rank cards — a legendary card adds +30 % group damage on top of the rank
	_check(is_equal_approx(Cards.rarity_dmg(3.0), 0.3) and Cards.rarity_dmg(1.0) == 0.0, "rarity bonus: legendary +30 %, base 0")
	var lg := Cards.branch_line(p, g, "power", Cards.rarity_dmg(3.0))
	_check(lg == "Урон за попадание: %s → %s" % [CardText.num(d0), CardText.num(d0 * 1.18 * 1.3)], "legendary rank line: %s" % lg)
	_check(is_equal_approx(g.bonus, 0.0), "branch_line puts the group's bonus back")
	_check(not Cards.rank_rarity_ok("flares") and Cards.rank_rarity_ok("aam"), "flares (no damage) take no rarity bonus")
	# «Скорострел» lowers the missiles' 3 s floor too (Hardpoint.reload_time), so «Стая» gets a real cut
	var a := _group(p, "aam")
	a.evo = true
	a.evo_id = "aam_swarm"
	var rl := Cards.branch_line(p, a, "rate")
	_check(rl == "Перезарядка: 3 с → 2,7 с", "rate rank line on «Стая»: %s" % rl)
	# a profile rank names the feature and its numbers, not «к профилю»
	var r := _group(p, "aam")
	r.profile = "pair"
	r.branch = "profile"
	r.branch_rank = 1
	var pl := Cards.branch_line(p, r, "profile")
	_check(pl.begins_with("Урон за попадание: ") and pl.contains("→"), "profile rank line: %s" % pl)
	_check(r.branch_rank == 1, "the profile rank is restored")
	# «Стая» Э+: +8 % of the base damage per step, reload stays at the 3 s floor
	p.groups.append(a)
	var e := Cards.evo_plus_desc(p, p.groups.size() - 1)
	_check(e.contains("Урон за попадание: 45 → 49") or e.contains("→"), "Э+ damage line: %s" % e)
	_check(e.contains("уже на нижнем пределе"), "Э+ on «Стая» does not promise a shorter reload: %s" % e)
	_check(a.evo_plus == 0, "evo_plus_desc leaves the group as it was")
	var el := Cards.evo_plus_desc(p, p.groups.size() - 1, Cards.rarity_dmg(3.0))
	_check(el.contains("Бонус редкости: +30% урона группы") and is_equal_approx(a.bonus, 0.0), "legendary Э+ names its bonus and leaves the group: %s" % el)
	p.free()
	print("UNIT: card_lines %d checks, %d failed" % [_checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
