#!/usr/bin/env python3
"""Card telemetry report (PG-12, genre research 11.11, item 2; Kanta «да» 2026-11-11).

Reads sortie logs playtest_log_*.csv (log l8 and later: column `card_offers`, one entry per card screen,
format of `game/scripts/card_log.gd`: «<second> L<level>: key/rarity, key/rarity*, …», « ~» — left by a reroll)
and prints Markdown, per card key:
  offered — card screens that showed it; taken — times it was picked; pick % — taken / offered;
  evac % — of the evacuated sorties, the share that took the card at least once (Slay the Spire's two metrics).
With --syn-by S it prints instead, per class, the share of sorties with at least one synergy open by second S
(column `synergies`, «id=second | …»; works on l7 logs too) — the PG-14 measurement. With --before, «было → стало».

Usage:
  python3 tools/reports/card_stats.py <dir or csv> [...] [--cls fighter] [--min 5]
  python3 tools/reports/card_stats.py <after dir or csv> [...] --syn-by 480 [--before <dir or csv> ...]
A dir is searched recursively for playtest_log_*.csv (a tools/ci/balance.sh OUT folder works as is).
No dependencies beyond the standard library.
"""

from __future__ import annotations

import argparse
import sys
from collections import defaultdict
from pathlib import Path

CLASSES = ["fighter", "attacker", "bomber"]
EVAC = "эвакуация"


def csvs(args: list[str]) -> list[Path]:
    """Every sortie log among `args`: csv files as given, dirs searched recursively."""
    out: list[Path] = []
    for a in args:
        p = Path(a)
        out += sorted(p.rglob("playtest_log_*.csv")) if p.is_dir() else [p]
    return out


def load(args: list[str]) -> list[dict[str, str]]:
    """Sortie rows as {column: value} from every log in `args` (each file has its own header)."""
    rows: list[dict[str, str]] = []
    for p in csvs(args):
        lines = p.read_text(encoding="utf-8").splitlines()
        if not lines:
            continue
        hdr = lines[0].split(";")
        rows += [dict(zip(hdr, ln.split(";"))) for ln in lines[1:] if ln.strip()]
    return rows


def parse_screen(s: str) -> tuple[list[str], str]:
    """One `card_offers` entry -> (offered keys, taken key or "" for a reroll screen)."""
    head, _, body = s.strip().partition(": ")
    body = body.removesuffix(" ~")
    keys, taken = [], ""
    for part in body.split(", "):
        if not part:
            continue
        k = part[: part.rfind("/")]
        keys.append(k)
        if part.endswith("*"):
            taken = k
    return keys, taken


def card_table(rows: list[dict[str, str]], min_offered: int) -> str:
    """Markdown table of pick rate and evac share per card key, most offered first."""
    offered: dict[str, int] = defaultdict(int)
    taken: dict[str, int] = defaultdict(int)
    evac_with: dict[str, int] = defaultdict(int)
    n_evac = 0
    n_logged = 0
    for r in rows:
        col = r.get("card_offers", "")
        if not col:
            continue
        n_logged += 1
        got: set[str] = set()
        for scr in col.split(" | "):
            keys, t = parse_screen(scr)
            for k in keys:
                offered[k] += 1
            if t:
                taken[t] += 1
                got.add(t)
        if r.get("outcome") == EVAC:
            n_evac += 1
            for k in got:
                evac_with[k] += 1
    out = [f"Sorties with card telemetry: {n_logged}, evacuated: {n_evac}", "",
           "| Card | Offered | Taken | Pick, % | In evac sorties, % |", "| --- | ---: | ---: | ---: | ---: |"]
    for k in sorted(offered, key=lambda x: -offered[x]):
        if offered[k] < min_offered:
            continue
        ev = f"{100 * evac_with[k] / n_evac:.0f}" if n_evac else "—"
        out.append(f"| {k} | {offered[k]} | {taken[k]} | {100 * taken[k] / offered[k]:.0f} | {ev} |")
    return "\n".join(out)


def first_syn(r: dict[str, str]) -> float | None:
    """Second of the first synergy of a sortie (None — none opened)."""
    times = []
    for kv in r.get("synergies", "").split(" | "):
        if "=" in kv:
            try:
                times.append(float(kv.split("=", 1)[1]))
            except ValueError:
                pass
    return min(times) if times else None


def syn_share(rows: list[dict[str, str]], by: float) -> dict[str, tuple[int, int]]:
    """Per class (and «all»): (sorties with a synergy by second `by`, sorties that lasted at least `by`)."""
    out: dict[str, list[int]] = {c: [0, 0] for c in CLASSES + ["all"]}
    for r in rows:
        try:
            if float(r.get("run_seconds") or 0) < by:
                continue
        except ValueError:
            continue
        t = first_syn(r)
        for c in (r.get("class", "?"), "all"):
            if c not in out:
                out[c] = [0, 0]
            out[c][1] += 1
            if t is not None and t <= by:
                out[c][0] += 1
    return {c: (v[0], v[1]) for c, v in out.items()}


def pct(v: tuple[int, int]) -> str:
    """«k of n (p %)»."""
    return f"{v[0]} of {v[1]} ({100 * v[0] / v[1]:.0f} %)" if v[1] else "—"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("paths", nargs="+", help="sortie logs or folders")
    ap.add_argument("--before", nargs="+", default=[], help="logs of the «before» run (with --syn-by)")
    ap.add_argument("--syn-by", type=float, default=0.0, help="second for the synergy share (PG-14), e.g. 480")
    ap.add_argument("--cls", default="", help="only this class (fighter / attacker / bomber)")
    ap.add_argument("--min", type=int, default=1, help="hide cards offered fewer times")
    a = ap.parse_args()
    rows = [r for r in load(a.paths) if not a.cls or r.get("class") == a.cls]
    if a.syn_by > 0:
        after = syn_share(rows, a.syn_by)
        before = syn_share(load(a.before), a.syn_by) if a.before else None
        print(f"Sorties with ≥ 1 synergy by {int(a.syn_by) // 60}:{int(a.syn_by) % 60:02d}\n")
        print("| Class | " + ("Before | After |" if before else "Share |"))
        print("| --- | " + ("--- | --- |" if before else "--- |"))
        for c in CLASSES + ["all"]:
            print(f"| {c} | " + (f"{pct(before[c])} | {pct(after[c])} |" if before else f"{pct(after[c])} |"))
        return 0
    print(card_table(rows, a.min))
    return 0


if __name__ == "__main__":
    sys.exit(main())
