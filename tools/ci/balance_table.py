#!/usr/bin/env python3
"""Sortie metrics table for balance runs (GD-01, method R-10).

Reads sortie logs playtest_log_*.csv (the same l7 line testers send) and prints a Markdown table:
level at 5 / 10 / 15:00, lowest HP by minute, ace fight duration, "would die" count, repair / damage taken.
Usage: python3 tools/ci/balance_table.py <csv> [<csv> ...]
"""
import re
import statistics
import sys


def minutes(timeline):
    """Minute rows of the timeline: {minute: {"L": level, "hp": percent}} (the last row of a minute wins)."""
    out = {}
    for seg in timeline.split(" | "):
        if ":" not in seg:
            continue
        mi, rest = seg.split(":", 1)
        vals = dict(re.findall(r"(L|hp)(-?[\d.]+)", rest))
        if mi.isdigit() and "L" in vals:
            out[int(mi)] = {"L": int(float(vals["L"])), "hp": float(vals.get("hp", 0))}
    return out


def row(m):
    tl = minutes(m.get("timeline", ""))
    lvl = lambda t: str(tl[t]["L"]) if t in tl else "—"
    taken = sum(float(m.get(k) or 0) for k in ("taken_bullets", "taken_missiles", "taken_ram"))
    return {
        "op": m.get("op", "?").split("/")[0],
        "cls": m.get("class", "?"),
        "l5": lvl(5), "l10": lvl(10), "l15": lvl(15),
        "hp_min": min((v["hp"] for v in tl.values()), default=0),
        "hp_min_at": min(tl, key=lambda t: tl[t]["hp"]) if tl else 0,
        "ace": "%s / %s" % (m.get("boss_life_avg", "—"), m.get("boss_life_max", "—")),
        "die": "—",
        "heal": float(m.get("healed") or 0) / max(taken, 1.0),
    }


def would_die(csv_path):
    """"Would die" per sortie, in order, from the Godot output next to the profile folder (balance.sh layout:
    <out>/opN_K.log and <out>/opN_K/godot/...). The count is not in the l7 line, only in the autotest output."""
    m = re.search(r"^(.*)/(op\d+(?:_\d+)?)/godot/", csv_path)
    if not m:
        return []
    try:
        text = open("%s/%s.log" % (m.group(1), m.group(2)), encoding="utf-8").read()
    except OSError:
        return []
    return re.findall(r"would-die (\d+)", text)


def main(paths):
    rows = []
    for p in paths:
        lines = open(p, encoding="utf-8").read().splitlines()
        if not lines:
            continue
        hdr = lines[0].split(";")
        part = [row(dict(zip(hdr, ln.split(";")))) for ln in lines[1:] if ln.strip()]
        for r, d in zip(part, would_die(p)):
            r["die"] = d
        rows += part
    print("| Operation | Class | Lvl 5:00 | Lvl 10:00 | Lvl 15:00 | Lowest HP, % (minute) | Ace fight avg / max, s | Would die | Repair / taken |")
    print("| --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    for r in rows:
        print("| %s | %s | %s | %s | %s | %.0f (%d) | %s | %s | %.2f |" % (
            r["op"], r["cls"], r["l5"], r["l10"], r["l15"], r["hp_min"], r["hp_min_at"], r["ace"], r["die"], r["heal"]))
    if rows:
        print("\nSorties: %d. Median repair / taken: %.2f. Sorties with HP ≤ 10 %% at some minute: %d." % (
            len(rows), statistics.median(r["heal"] for r in rows), sum(1 for r in rows if r["hp_min"] <= 10)))


if __name__ == "__main__":
    main(sys.argv[1:])
