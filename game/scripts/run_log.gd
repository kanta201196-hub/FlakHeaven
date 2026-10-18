class_name RunLog
extends RefCounted
## Лог плейтеста: строка CSV на каждый вылет (вызывается из Main при гибели и эвакуации).

# ---------- Лог плейтеста ----------
## Каждый вылет (гибель или эвакуация) дописывается в user://playtest_log_v2.csv

## Источники нанесённого урона — отдельной колонкой каждый (2.4)
const LOG_DEALT := ["курсовое (авто)", "курсовое (ручн.)", "турели", "ракеты В-В", "НАР", "гондола", "бомбы",
	"огненный ковёр", "ведомые", "проход на форсаже", "бронещит", "щит аса", "противоракеты"]


static func write(m: Main, outcome: String) -> void:
	m.menu.add_record(PlaneClasses.DATA[m.cls_id]["title"], outcome, m.run_time, m.level, m.kills)
	# 3.4: новые колонки — новый файл (версия набора колонок в имени), чтобы не смешивать заголовки
	var path := "user://playtest_log_%s_%s.csv" % [Main.BUILD, Telemetry.LOG_VER]
	var exists := FileAccess.file_exists(path)
	var f := FileAccess.open(path, FileAccess.READ_WRITE if exists else FileAccess.WRITE)
	if f == null:
		return
	var head := "datetime;class;scheme;outcome;run_seconds;level;level_at_5min;kills;bosses;activities;parts_kept;restart_index"
	head += ";taken_ram;taken_bullets;taken_missiles;missile_hits;healed;dealt_total"
	for k in ["gun_auto", "gun_manual", "turrets", "aam", "rockets", "gunpod", "bombs", "carpet", "wingmen", "afterburner_pass", "shield_ram", "ace_shield", "flares_mirror"]:
		head += ";dealt_" + k
	head += ";shots;hits;peak_rev;near_misses;best_streak;tail_kills;banned;cards;synergies;max_hp"
	head += ";skill3;skill3_lvl;skill3_uses;tags;patches;evolutions;wingmen;intercepted;dealt_detail;taken_by"
	head += ";skill2;course_log;syn_open;course_pts;crew_lvl;crew_xp_gain;parts_total;nodes;plane2;perks;wbranch;meta_k"
	# 3.4: замеры для анализа правок по кросс-проверке (Telemetry); timeline — последняя колонка
	head += ";log_ver;" + ";".join(PackedStringArray(Telemetry.COLS)) + ";aces;timeline"
	m.last_log_header = head
	if exists:
		f.seek_end()
	else:
		f.store_line(head)
	var row := PackedStringArray([Time.get_datetime_string_from_system(), m.cls_id, str(int(Tuning.g("scheme"))), outcome,
		"%.1f" % m.run_time, str(m.level), str(m.level_at_5), str(m.kills), str(m.bosses_killed), str(m.activities_done), str(m.parts_kept), str(m.restarts),
		str(m.stat("taken", "таран")), str(m.stat("taken", "пули")), str(m.stat("taken", "ракеты")),
		str(int(m.counters.get("missile_hits", 0))), str(int(m.counters.get("healed", 0))), str(m.total("dealt"))])
	for k in LOG_DEALT:
		row.append(str(m.stat("dealt", k)))
	row.append_array(PackedStringArray([str(m.shots), str(m.hits), str(int(round(m.peak_rev * 100.0))), str(m.near_misses), str(m.best_streak),
		str(m.tail_kills), " | ".join(PackedStringArray(m.banned.values())), " | ".join(PackedStringArray(m.player.cards_log)),
		kv(m.player.syn), str(int(m.player.max_hp))]))
	# 3.1: навык, теги, нашивки (время), эволюции (время), ведомые, перехваты, урон по всем источникам
	var wl := PackedStringArray()
	for w in m.player.wingmen:
		wl.append("%s%d%s" % [(w as Wingman).type, (w as Wingman).lvl, "t" if (w as Wingman).temp else ""])
	var icp := int(m.counters.get("intercepted", 0)) + int(m.counters.get("intercepted_turrets", 0)) + int(m.counters.get("intercepted_skill", 0)) + int(m.counters.get("intercepted_wingmen", 0))
	row.append_array(PackedStringArray([m.player.skill3, str(m.player.s3_lvl()), str(int(m.counters.get("skill3_uses", 0))),
		kv(m.player.tags), kv(m.player.patch_times), kv(m.player.evo_times), " ".join(wl), str(icp),
		kv(m.stats["dealt"]), kv(m.stats["taken_by"])]))
	var wb := PackedStringArray()
	for w in Profile.WEAPON_ORDER:
		wb.append("%s=%s%s" % [w, Profile.tier_state(w, 1), Profile.tier_state(w, 2)])
	row.append_array(PackedStringArray([m.player.skill_b, " | ".join(PackedStringArray(m.course_log)), kv(m.player.syn), str(m.player.course_pts),
		str(Profile.crew_lvl(m.cls_id)), str(int(m.meta_award.get("xp_add", 0))), str(Profile.parts()), kv(Profile.nodes_of(m.cls_id)),
		str(Profile.plane2(m.cls_id)), ",".join(PackedStringArray(Profile.cls(m.cls_id)["perks"])), " ".join(wb), str(Tuning.g("meta_k"))]))
	m.tele.v["xp_continue"] = float(m.meta_award.get("xp_continue", 0))
	row.append(Telemetry.LOG_VER)
	row.append_array(m.tele.row(m))
	row.append(aces(m))
	row.append(" | ".join(m.tele.timeline))
	m.last_log_row = ";".join(row)
	m.last_outcome = outcome
	f.store_line(m.last_log_row)
	f.close()
	m.report.queue_run(m.last_log_header, m.last_log_row) # 3.5: строка вылета уходит в таблицу сама


## Тест 3.5-s5 (п. 10): асы вылета — «вид@время появления hp=прочность со щитом k=доля урона по одиночной цели
## жил=с (сбит) или жив=с, урон по оружию» (урон до щита и потолка, не больше остатка прочности)
static func aces(m: Main) -> String:
	var out := PackedStringArray()
	for e: Dictionary in m.ace_log:
		var life := float(e["life"])
		var st := ("жил=%d" % int(life)) if life >= 0.0 else ("жив=%d" % int(m.run_time - float(e["t"])))
		var dsum := 0.0
		for v in (e["dmg"] as Dictionary).values():
			dsum += float(v)
		out.append("%s@%d hp=%d k=%.2f %s урон=%d: %s" % [e["v"], int(e["t"]), int(e["hp"]), float(e["k"]), st, int(dsum), kv(e["dmg"]).replace(" | ", ", ")])
	return " || ".join(out)


static func kv(d: Dictionary) -> String:
	var out := PackedStringArray()
	for k in d:
		var v = d[k]
		out.append("%s=%s" % [k, str(int(round(float(v)))) if (v is float or v is int) else str(v)])
	return " | ".join(out)
