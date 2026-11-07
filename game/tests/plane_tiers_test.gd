extends SceneTree
## Unit tests for `PlaneTiers` (PT-04, Kanta 06.11): five plane tiers per class — prices, gates, demo cap, node
## catalogs per tier, the tier → model fallback while new models are made, and the migration of a save from the
## two-plane game (old plane 1 → tier 2, old plane 2 → tier 3, tier 1 granted free).
## Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0
var _checks := 0


func _init() -> void:
	_prices_and_gates()
	_can_buy()
	_nodes()
	_models()
	_migration()
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _prices_and_gates() -> void:
	_check(PlaneTiers.MAX == 5, "five tiers")
	_check(PlaneTiers.cost(1) == 0, "tier 1 is free")
	_check([2, 3, 4, 5].map(func(t): return PlaneTiers.cost(t)) == [20000, 50000, 120000, 250000],
		"Kanta 06.11 18:19: tiers 2–5 cost 20 000 / 50 000 / 120 000 / 250 000")
	_check(PlaneTiers.gate_op(2) == 0, "tier 2 opens after operation 1 «Перевал» (Kanta 06.11)")
	_check(PlaneTiers.gate_op(1) == -1, "tier 1 has no gate")
	_check(PlaneTiers.DEMO_MAX == 2, "demo: tier 2 is the last playable one")
	for t in range(2, PlaneTiers.MAX + 1):
		_check(PlaneTiers.cost(t) > PlaneTiers.cost(t - 1), "tier %d costs more than tier %d" % [t, t - 1])
		_check(PlaneTiers.gate_op(t) > PlaneTiers.gate_op(t - 1), "tier %d gate is a later operation" % t)


func _can_buy() -> void:
	var owned := [1]
	_check(PlaneTiers.can_buy(2, owned, 20000, 2, true, false), "tier 2: parts, crew and «Перевал» — can buy")
	_check(not PlaneTiers.can_buy(2, owned, 19999, 2, true, false), "tier 2: one part short")
	_check(not PlaneTiers.can_buy(2, owned, 20000, 1, true, false), "tier 2: crew too low")
	_check(not PlaneTiers.can_buy(2, owned, 20000, 2, false, false), "tier 2: «Перевал» not cleared")
	_check(PlaneTiers.can_buy(2, owned, 20000, 2, true, true), "demo: tier 2 can be bought")
	_check(not PlaneTiers.can_buy(3, [1, 2], 999999, 20, true, true), "demo: tier 3 is visible but locked")
	_check(not PlaneTiers.can_buy(3, owned, 999999, 20, true, false), "tier 3 needs tier 2 first")
	_check(not PlaneTiers.can_buy(2, [1, 2], 999999, 20, true, false), "an owned tier is not sold again")
	_check(not PlaneTiers.can_buy(1, [], 999999, 20, true, false), "tier 1 is never sold")
	_check(not PlaneTiers.can_buy(6, [1, 2, 3, 4, 5], 9999999, 20, true, false), "no tier 6")
	_check(PlaneTiers.lock_reason(3, [1, 2], 0, 1, false, true) == "demo", "demo lock wins over the other reasons")
	_check(PlaneTiers.lock_reason(3, [1], 0, 1, false, false) == "prev", "previous tier first")
	_check(PlaneTiers.lock_reason(3, [1, 2], 0, 9, false, false) == "gate", "then the operation")
	_check(PlaneTiers.lock_reason(3, [1, 2], 0, 1, true, false) == "crew", "then the crew")
	_check(PlaneTiers.lock_reason(3, [1, 2], 0, 9, true, false) == "parts", "then the parts")
	_check(PlaneTiers.lock_reason(3, [1, 2], 50000, 9, true, false) == "", "nothing missing")


func _nodes() -> void:
	_check(PlaneTiers.nodes(1) == ["frame", "engine", "armor", "pylons"], "tier 1: four basic nodes")
	_check(PlaneTiers.nodes(2) == ["frame", "engine", "armor", "wing", "pylons", "tank"], "tier 2: today's six nodes")
	_check(PlaneTiers.nodes(3).size() == 7 and PlaneTiers.nodes(3).has("avionics"), "tier 3: seven nodes with avionics")
	_check(PlaneTiers.nodes(4).has("power") and not PlaneTiers.nodes(4).has("tank"), "tier 4: power plant, tank folded")
	_check(PlaneTiers.cap(1) == 3 and PlaneTiers.cap(2) == 4 and PlaneTiers.cap(3) == 5, "node caps 3 / 4 / 5")
	# tier 2 is today's plane 1: same prices and the same per-level effects, so a carried-over save flies the same
	_check(PlaneTiers.node_cost(2, 0) == 160 and PlaneTiers.node_cost(2, 4) == 5800, "tier 2 node prices unchanged")
	_check(PlaneTiers.node_cost(1, 0) == 80, "tier 1 node prices ×0.5")
	_check(PlaneTiers.node_cost(5, 0) == 320, "tier 5 node prices ×2")
	_check(PlaneTiers.fx(2, "frame") == {"man_cd": -0.04}, "tier 2 frame: today's −4 %")
	_check(PlaneTiers.fx(2, "engine") == {"speed": 0.02}, "tier 2 engine: today's +2 %")
	_check(PlaneTiers.fx(2, "armor") == {"hp": 0.05}, "tier 2 armor: today's +5 %")
	_check(PlaneTiers.fx(2, "wing") == {"turn": 0.03}, "tier 2 wing: today's +3 %")
	_check(PlaneTiers.fx(2, "pylons") == {"hp_dmg": 0.04}, "tier 2 pylons: today's +4 %")
	_check(PlaneTiers.fx(2, "tank") == {"fuel": 0.08}, "tier 2 tank: today's +8 %")
	_check(PlaneTiers.fx(3, "frame") == {"man_cd": -0.04, "hp": 0.02}, "tier 3 composite frame")
	_check(PlaneTiers.fx(1, "wing").is_empty(), "no wing node on tier 1")
	for t in range(1, PlaneTiers.MAX + 1):
		for id in PlaneTiers.nodes(t):
			var d := PlaneTiers.node_def(t, id)
			_check(String(d.get("title", "")) != "" and String(d.get("step", "")) != "", "tier %d %s has a title and a step" % [t, id])
			for key in PlaneTiers.fx(t, id):
				_check(PlaneTiers.FX_KEYS.has(key), "tier %d %s effect %s is one the game applies" % [t, id, key])


func _models() -> void:
	_check(PlaneTiers.model(1) == "t1", "tier 1 flies its own model (stage B)")
	_check(PlaneTiers.model(2) == "1", "tier 2 is today's plane 1, art paths unchanged")
	_check(PlaneTiers.model(3) == "2", "tier 3 is today's plane 2, art paths unchanged")
	_check(PlaneTiers.model(4) == "t4" and PlaneTiers.model(5) == "t5", "tiers 4–5 fly their own models (PT-02)")
	var own := true
	for t in range(1, 6):
		own = own and PlaneTiers.has_own_model(t)
	_check(own, "every tier owns its model (no «модель в работе» in the hangar)")
	_check(PlaneTiers.model_keys() == ["t1", "1", "2", "t4", "t5"], "model keys in tier order, each once")
	_check(PlaneTiers.model_tier("t1") == 1 and PlaneTiers.model_tier("1") == 2 and PlaneTiers.model_tier("2") == 3
		and PlaneTiers.model_tier("t4") == 4 and PlaneTiers.model_tier("t5") == 5,
		"each model belongs to the first tier drawn with it")
	_check(PlaneTiers.model_tier("t9") == 0, "unknown model: no tier")
	_check(PlaneTiers.art_key("fighter", "t1") == "fighter_t1" and PlaneTiers.art_key("bomber", "2") == "bomber_2",
		"art keys match the GLB and sprite names")


func _migration() -> void:
	var n1 := {"frame": 3, "engine": 2}
	var n2 := {"frame": 1}
	var old := {"plane2": true, "plane_sel": 2, "nodes": n1, "nodes2": n2, "kit1": {"gun": "a"}, "kit2": {"gun": "b"},
		"decals1": {"v": 1, "items": [1]}, "decals2": {"v": 1, "items": [2]}}
	var m := PlaneTiers.migrate_class(old)
	_check(m["tiers"] == [1, 2, 3], "old plane 2 owner: tiers 1, 2, 3")
	_check(int(m["plane_sel"]) == 3, "flew old plane 2 → flies tier 3")
	_check(m["nodes_t2"] == n1 and m["nodes_t3"] == n2, "nodes move with their plane")
	_check(m["kit_t2"] == {"gun": "a"} and m["kit_t3"] == {"gun": "b"}, "course gun kits move with their plane")
	_check(not m.has("decals_t2"), "decals stay keyed by model (decals1 / decals2)")
	var m2 := PlaneTiers.migrate_class({"plane2": false, "plane_sel": 2, "nodes": n1})
	_check(m2["tiers"] == [1, 2], "old plane 1 only: tiers 1 and 2")
	_check(int(m2["plane_sel"]) == 2, "plane 2 selected but not owned → flies tier 2")
	var m3 := PlaneTiers.migrate_class({"plane2": true, "plane_sel": 1})
	_check(int(m3["plane_sel"]) == 2, "flew old plane 1 → flies tier 2")
	_check(not m3.has("nodes_t2"), "a missing old key is not invented")


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)
