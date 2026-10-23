#!/usr/bin/env python3
"""Sortie metrics for balance runs (GD-01, method R-10, docs/balance-method.md).

Reads sortie logs playtest_log_*.csv (the same l7 line testers send) and prints Markdown:
one row per sortie, then a per-class summary of metrics M1–M7 with the corridor check.
With --before, also "before → after" per class: the median difference and its bootstrap 90 % interval;
the change counts only when the interval does not include 0.

Usage:
  python3 tools/ci/balance_table.py <dir or csv> [...]
  python3 tools/ci/balance_table.py <after dir or csv> [...] --before <before dir or csv> [...]
A dir is a balance.sh OUT folder (op*/godot/app_userdata/*/playtest_log_*.csv inside).
"""
import glob
import os
import random
import re
import statistics
import sys

CLASSES = ["fighter", "attacker", "bomber"]
# M7: signature weapon of the class (log fields summed)
SIGNATURE = {"fighter": ["dealt_aam"], "attacker": ["dealt_rockets"], "bomber": ["dealt_bombs", "dealt_carpet"]}
# Corridors approved by Kanta on 2026-10-23 (docs/balance-method.md, section 3): metric -> (low, high), None = open
CORRIDORS = {
    "L5": (20, 26), "L10": (30, 38), "L15": (38, 48),
    "M2": (35, None), "M3": (35, None), "M4": (20, 45), "M5": (None, 30), "M6": (0.6, 0.95), "M7": (20, None),
}
METRICS = ["L5", "L10", "L15", "M2", "M3", "M4", "M5", "M6", "M7"]
NAMES = {"L5": "Lvl 5:00", "L10": "Lvl 10:00", "L15": "Lvl 15:00", "M2": "HP ≤ 5:00, %", "M3": "HP 5–7:00, %",
         "M4": "Ace fight, s", "M5": "Would die", "M6": "Repair / taken", "M7": "Signature, %"}


def minutes(timeline):
    """Minute rows of the timeline: {minute: {"L": level, "hp": percent}} (the last row of a minute wins)."""
    out = {}
    for seg in timeline.split(" | "):
        if ":" not in seg:
            continue
        mi, rest = seg.split(":", 1)
        vals = dict(re.findall(r"(?<![a-z])(L|hp)(-?[\d.]+)", rest))
        if mi.isdigit() and "L" in vals:
            out[int(mi)] = {"L": int(float(vals["L"])), "hp": float(vals.get("hp", 0))}
    return out


def num(m, k):
    try:
        return float(m.get(k) or 0)
    except ValueError:
        return 0.0


def row(m):
    tl = minutes(m.get("timeline", ""))
    taken = sum(num(m, k) for k in ("taken_bullets", "taken_missiles", "taken_ram"))
    cls = m.get("class", "?")
    total = max(num(m, "dealt_total"), 1.0)
    hp_in = lambda a, b: min((v["hp"] for t, v in tl.items() if a <= t <= b), default=None)
    ace = num(m, "boss_life_avg")
    return {
        "op": m.get("op", "?").split("/")[0], "cls": cls,
        "L5": tl[5]["L"] if 5 in tl else None, "L10": tl[10]["L"] if 10 in tl else None,
        "L15": tl[15]["L"] if 15 in tl else None,
        "M2": hp_in(0, 5), "M3": hp_in(5, 7),
        "M4": ace if ace > 0 else None, "M4max": num(m, "boss_life_max"),
        "M5": None,
        "M6": num(m, "healed") / max(taken, 1.0),
        "M7": 100.0 * sum(num(m, k) for k in SIGNATURE.get(cls, [])) / total,
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
    return [int(x) for x in re.findall(r"would-die (\d+)", text)]


def csvs(args):
    out = []
    for a in args:
        if os.path.isdir(a):
            out += sorted(glob.glob(os.path.join(a, "op*", "godot", "app_userdata", "*", "playtest_log_*.csv")))
        else:
            out.append(a)
    return out


def load(args):
    rows = []
    for p in csvs(args):
        lines = open(p, encoding="utf-8").read().splitlines()
        if not lines:
            continue
        hdr = lines[0].split(";")
        part = [row(dict(zip(hdr, ln.split(";")))) for ln in lines[1:] if ln.strip()]
        for r, d in zip(part, would_die(p)):
            r["M5"] = d
        rows += part
    return rows


def fmt(v, k):
    if v is None:
        return "—"
    return "%.2f" % v if k == "M6" else "%.0f" % v


def values(rows, cls, k):
    return [r[k] for r in rows if r["cls"] == cls and r[k] is not None]


def in_corridor(v, k):
    lo, hi = CORRIDORS[k]
    return (lo is None or v >= lo) and (hi is None or v <= hi)


def boot(before, after, n=4000):
    """Bootstrap 90 % interval of median(after) − median(before)."""
    rnd = random.Random(1)
    ds = sorted(statistics.median(rnd.choices(after, k=len(after))) - statistics.median(rnd.choices(before, k=len(before)))
                for _ in range(n))
    return ds[int(n * 0.05)], ds[int(n * 0.95)]


def print_sorties(rows):
    print("| Operation | Class | " + " | ".join(NAMES[k] for k in METRICS) + " |")
    print("| --- | --- |" + " --- |" * len(METRICS))
    for r in rows:
        print("| %s | %s | %s |" % (r["op"], r["cls"], " | ".join(fmt(r[k], k) for k in METRICS)))


def print_summary(rows):
    print("\nPer class: median [min–max], ✗ — outside the corridor.\n")
    print("| Metric | Corridor | " + " | ".join("%s (%d)" % (c, sum(1 for r in rows if r["cls"] == c)) for c in CLASSES) + " |")
    print("| --- | --- |" + " --- |" * len(CLASSES))
    for k in METRICS:
        lo, hi = CORRIDORS[k]
        cor = ("%s–%s" % (lo, hi)) if lo is not None and hi is not None else (("≥ %s" % lo) if lo is not None else ("≤ %s" % hi))
        cells = []
        for c in CLASSES:
            v = values(rows, c, k)
            if not v:
                cells.append("—")
                continue
            med = statistics.median(v)
            cells.append("%s [%s–%s]%s" % (fmt(med, k), fmt(min(v), k), fmt(max(v), k), "" if in_corridor(med, k) else " ✗"))
        print("| %s | %s | %s |" % (NAMES[k], cor, " | ".join(cells)))


def print_compare(before, after):
    print("\nBefore → after: median, 90 % interval of the difference; **counts** only if it excludes 0.\n")
    print("| Metric | " + " | ".join(CLASSES) + " |")
    print("| --- |" + " --- |" * len(CLASSES))
    for k in METRICS:
        cells = []
        for c in CLASSES:
            b, a = values(before, c, k), values(after, c, k)
            if len(b) < 2 or len(a) < 2:
                cells.append("—")
                continue
            lo, hi = boot(b, a)
            real = lo > 0 or hi < 0
            cells.append("%s → %s [%+.1f…%+.1f]%s" % (fmt(statistics.median(b), k), fmt(statistics.median(a), k), lo, hi,
                                                      " **counts**" if real else ""))
        print("| %s | %s |" % (NAMES[k], " | ".join(cells)))


def main(argv):
    if "--before" in argv:
        i = argv.index("--before")
        after, before = load(argv[:i]), load(argv[i + 1:])
    else:
        after, before = load(argv), None
    print_sorties(after)
    print_summary(after)
    if before is not None:
        print_compare(before, after)


if __name__ == "__main__":
    main(sys.argv[1:])
