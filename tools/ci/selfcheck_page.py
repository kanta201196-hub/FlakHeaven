"""Build self-check page (R-23): turns the frames and manifests of tools/ci/selfcheck.sh into one folder.

Reads <out>/manifest_<part>_g<N>.json (written by game/scripts/self_check.gd), <out>/runs.tsv (written by
selfcheck.sh: part, preset, wall seconds, exit code, log, frames of each Godot process), the logs it names (for
SCRIPT ERROR / Parse Error / SHADER ERROR lines) and the JPEG frames, then writes:
  <out>/thumbs/*.jpg   — 480 px previews for the grid,
  <out>/manifest.json  — everything merged (build, commit, presets, runs, frames, issues, failures),
  <out>/index.html     — the sheet in Russian: summary, failures, automatic-check findings, then a grid per section
                         (hangar, weapon store, combat) with a preset switch; a click opens the frame full size
                         with zoom (wheel, drag, arrows, Esc).
Exit code: 0 when every process ended cleanly, every frame was captured and no log has a SCRIPT ERROR; 1 otherwise.
Findings of the automatic checks (gaps, missing nodes) are listed but do not fail the run.

Run: python3 tools/ci/selfcheck_page.py <out dir> [--build 3.5-s14] [--commit abc1234] [--renderer forward_plus]
Dependencies: Python 3.10+, Pillow (thumbnails). Decision: R-23, Kanta 31.10.2026.
"""

from __future__ import annotations

import argparse
import datetime
import html
import json
import re
import sys
from pathlib import Path

from PIL import Image

THUMB_W = 480
LEVELS = {1: "ур. 1", 2: "ур. 3", 3: "ур. 5", 4: "модерн."}
SHOTS = {
    "flight": "в полёте (камера игры)",
    "nozzles": "сопла: факел форсажа",
    "muzzles": "точки вылета (маркеры)",
    "stores": "подвесы снизу (крен)",
    "trails": "следы и дым ракет",
}
PRESETS = {0: "Низкое", 1: "Среднее", 2: "Высокое", 3: "Максимальное"}
PARTS = {"hangar": "ангар и склад", "combat": "бой"}
ERR_RE = re.compile(r"SCRIPT ERROR|Parse Error|SHADER ERROR")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("out", type=Path)
    ap.add_argument("--build", default="")
    ap.add_argument("--commit", default="")
    ap.add_argument("--renderer", default="")
    a = ap.parse_args()
    out: Path = a.out.resolve()
    runs = {"runs": _runs(out), "renderer": a.renderer}
    mans = [_load(p, {}) for p in sorted(out.glob("manifest_*_g*.json"))]
    frames: list[dict] = []
    issues: list[dict] = []
    titles: dict = {}
    wnames: dict = {}
    evos: dict = {}
    for mf in mans:
        frames += mf.get("frames", [])
        issues += mf.get("issues", [])
        titles.update(mf.get("class_titles", {}))
        wnames.update(mf.get("weapon_names", {}))
        evos.update(mf.get("evo_names", {}))
    failures = _failures(out, runs, mans, frames)
    _thumbs(out, frames)
    doc = {
        "build": a.build,
        "commit": a.commit,
        "date": datetime.datetime.now().strftime("%Y-%m-%d %H:%M"),
        "presets": sorted({r["gfx"] for r in runs["runs"]} | {f["gfx"] for f in frames}),
        "renderer": runs.get("renderer", ""),
        "runs": runs["runs"],
        "frames": frames,
        "issues": issues,
        "failures": failures,
        "names": {"classes": titles, "weapons": wnames, "evolutions": evos},
    }
    (out / "manifest.json").write_text(json.dumps(doc, ensure_ascii=False, indent=1), encoding="utf-8")
    (out / "index.html").write_text(_page(doc), encoding="utf-8")
    shot = sum(1 for f in frames if f.get("file"))
    print(f"selfcheck_page: {shot} frames, {len(issues)} findings, {len(failures)} failures -> {out / 'index.html'}")
    return 1 if failures else 0


def _runs(out: Path) -> list[dict]:
    """The Godot processes of runs.tsv, each with the error lines of its log: SCRIPT ERROR and the like (with the
    «at:» line after them) fail the run; other engine «ERROR:» lines are only counted."""
    rows: list[dict] = []
    tsv = out / "runs.tsv"
    if not tsv.exists():
        return rows
    for line in tsv.read_text(encoding="utf-8").splitlines():
        f = line.split("\t")
        if len(f) < 6:
            continue
        r = {"part": f[0], "gfx": int(f[1]), "seconds": int(f[2]), "exit": int(f[3]), "log": f[4], "frames": int(f[5])}
        errs: list[str] = []
        other = 0
        try:
            lines = (out / r["log"]).read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            lines = []
        for i, ln in enumerate(lines):
            if ERR_RE.search(ln):
                at = lines[i + 1].strip() if i + 1 < len(lines) and "at:" in lines[i + 1] else ""
                errs.append(f"{ln.strip()} {at}".strip())
            elif ln.startswith("ERROR:"):
                other += 1
        r["script_errors"] = errs
        r["other_errors"] = other
        rows.append(r)
    return rows


def _load(p: Path, default: dict) -> dict:
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return default


def _failures(out: Path, runs: dict, mans: list[dict], frames: list[dict]) -> list[str]:
    """Everything that makes the run fail: a process that did not end cleanly, a missing manifest, a frame that was
    not captured, a SCRIPT ERROR in a log."""
    bad: list[str] = []
    have = {(m.get("part"), m.get("gfx")): m for m in mans}
    for r in runs["runs"]:
        name = f"{PARTS.get(r['part'], r['part'])}, пресет {r['gfx']}"
        if r.get("exit", 0) != 0:
            bad.append(f"{name}: процесс Godot завершился с кодом {r['exit']} (лог {r['log']})")
        mf = have.get((r["part"], r["gfx"]))
        if mf is None:
            bad.append(f"{name}: нет манифеста — кадры этой части не сняты (лог {r['log']})")
        elif not mf.get("complete"):
            bad.append(f"{name}: прогон оборвался — сняты не все кадры (лог {r['log']})")
        for line in r.get("script_errors", []):
            bad.append(f"{name}: {line} (лог {r['log']})")
    for f in frames:
        if not f.get("na") and not f.get("file"):
            bad.append(f"кадр не снят: {_label(f, {}, {})}")
        elif f.get("file") and not (out / f["file"]).exists():
            bad.append(f"файла кадра нет: {f['file']}")
    return bad


def _thumbs(out: Path, frames: list[dict]) -> None:
    td = out / "thumbs"
    td.mkdir(exist_ok=True)
    for f in frames:
        src = out / f["file"] if f.get("file") else None
        if src is None or not src.exists():
            continue
        dst = td / f["file"]
        if dst.exists() and dst.stat().st_mtime >= src.stat().st_mtime:
            continue
        with Image.open(src) as im:
            im.thumbnail((THUMB_W, THUMB_W))
            im.save(dst, "JPEG", quality=80)


def _plane(f: dict, titles: dict) -> str:
    t = titles.get(f["cls"], f["cls"])
    return f"{t} {f['lvl']}" if f.get("lvl") else t


def _label(f: dict, titles: dict, wnames: dict) -> str:
    parts = [_plane(f, titles)]
    if f.get("weapon"):
        parts.append(wnames.get(f["weapon"], f["weapon"]))
    if f.get("tier"):
        parts.append(LEVELS.get(f["tier"], str(f["tier"])))
    if f.get("shot"):
        parts.append(SHOTS.get(f["shot"], f["shot"]))
    parts.append(f"пресет {f.get('gfx')}")
    return " · ".join(parts)


def _page(d: dict) -> str:
    titles = d["names"]["classes"]
    wnames = d["names"]["weapons"]
    evos = d["names"]["evolutions"]
    frames = d["frames"]
    by_file: dict[str, list[dict]] = {}
    for i in d["issues"]:
        by_file.setdefault(i.get("file", ""), []).append(i)
    shot = [f for f in frames if f.get("file")]
    presets = d["presets"]
    e = html.escape
    pre_txt = ", ".join(f"{p} ({PRESETS.get(p, p)})" for p in presets)
    run_rows = "".join(
        f"<tr><td>{e(PARTS.get(r['part'], r['part']))}</td><td>{r['gfx']}</td><td>{r['seconds'] // 60} мин {r['seconds'] % 60} с</td>"
        f"<td>{r.get('frames', 0)}</td><td>{'ok' if r.get('exit', 0) == 0 else 'код ' + str(r['exit'])}</td>"
        f"<td>{len(r.get('script_errors', []))}</td><td>{r.get('other_errors', 0)}</td></tr>"
        for r in d["runs"]
    )
    fail_html = (
        "<p class='ok'>Сбоев нет: все кадры сняты, SCRIPT ERROR в логах нет.</p>"
        if not d["failures"]
        else "<ul class='bad'>" + "".join(f"<li>{e(x)}</li>" for x in d["failures"]) + "</ul>"
    )
    if d["issues"]:
        rows = []
        for i in d["issues"]:
            f = i.get("file", "")
            link = f"<a href='#' data-open='{e(f)}'>{e(f)}</a>" if f else "—"
            rows.append(f"<tr><td>{e(_label(i, titles, wnames))}</td><td>{e(i['text'])}</td><td>{link}</td></tr>")
        iss_html = (
            f"<p>{len(d['issues'])} находок (на кадрах — красная рамка). Не валят прогон: это то, что надо глазами проверить.</p>"
            "<table class='iss'><tr><th>Кадр</th><th>Что</th><th>Файл</th></tr>" + "".join(rows) + "</table>"
        )
    else:
        iss_html = "<p class='ok'>Автопроверки ничего не нашли.</p>"

    def cell(f: dict | None, sub: str) -> str:
        if f is None:
            return "<div class='cell na'><span>—</span></div>"
        if f.get("na"):
            return f"<div class='cell na'><span>{e(sub)}</span><small>нет модернизации</small></div>"
        if not f.get("file"):
            return f"<div class='cell miss'><span>{e(sub)}</span><small>кадр не снят</small></div>"
        iss = by_file.get(f["file"], [])
        tip = e(_label(f, titles, wnames) + ("\n" + "\n".join(i["text"] for i in iss) if iss else ""))
        cls = "cell bad" if iss else "cell"
        badge = f"<b class='badge'>{len(iss)}</b>" if iss else ""
        return (
            f"<figure class='{cls}' data-gfx='{f['gfx']}'><a href='{e(f['file'])}' data-full='{e(f['file'])}' title='{tip}'>"
            f"<img loading='lazy' src='thumbs/{e(f['file'])}' alt='{tip}'></a>{badge}<figcaption>{e(sub)}</figcaption></figure>"
        )

    def grid(section: str, rows: list[tuple[str, dict]], cols: list, col_name) -> str:
        out = []
        for g in presets:
            body = []
            for title, key in rows:
                cells = []
                for c in cols:
                    f = next((x for x in frames if x["section"] == section and x["gfx"] == g
                              and all(x.get(k) == v for k, v in key.items()) and _col(x, c)), None)
                    cells.append(cell(f, col_name(c, key)))
                body.append(f"<div class='row'><div class='rh'>{e(title)}</div>{''.join(cells)}</div>")
            out.append(f"<div class='preset' data-gfx='{g}'>{''.join(body)}</div>")
        return "".join(out)

    def _col(x: dict, c) -> bool:
        return x.get("tier") == c if isinstance(c, int) else x.get("shot") == c

    hangar_rows = []
    seen = set()
    for f in frames:
        if f["section"] == "hangar":
            k = (f["cls"], f["lvl"], f["weapon"])
            if k not in seen:
                seen.add(k)
                hangar_rows.append((f"{_plane(f, titles)} — {wnames.get(f['weapon'], f['weapon'])}",
                                    {"cls": f["cls"], "lvl": f["lvl"], "weapon": f["weapon"]}))
    store_rows = []
    seen = set()
    for f in frames:
        if f["section"] == "store":
            k = (f["cls"], f["weapon"])
            if k not in seen:
                seen.add(k)
                own = f" (склад: {titles.get(f['cls'], f['cls'])})" if f["weapon"] in ("turret", "bombs") else ""
                store_rows.append((f"{wnames.get(f['weapon'], f['weapon'])}{own}", {"cls": f["cls"], "weapon": f["weapon"]}))
    combat_rows = []
    seen = set()
    for f in frames:
        if f["section"] == "combat":
            k = (f["cls"], f["lvl"])
            if k not in seen:
                seen.add(k)
                combat_rows.append((_plane(f, titles), {"cls": f["cls"], "lvl": f["lvl"]}))

    def lvl_name(t: int, key: dict) -> str:
        if t == 4:
            ev = evos.get(key.get("weapon", ""), "")
            return f"модерн. {ev}".strip()
        return LEVELS[t]

    sections = []
    if hangar_rows:
        sections.append(("hangar", "Ангар: самолёт с оружием (вкладка «САМОЛЁТ»)",
                         "Каждый самолёт с каждым своим оружием на тех узлах, куда его ставит игра; ур. 1 / 3 / 5 и модернизация. "
                         "Турели встроены и видны на всех кадрах своего класса. Подвесное оружие снято снизу "
                         "(самый низкий угол камеры ангара), турели и ловушки — с угла по умолчанию.",
                         grid("hangar", hangar_rows, [1, 2, 3, 4], lvl_name)))
    if store_rows:
        sections.append(("store", "Склад оружия (вкладка «ОРУЖИЕ»)",
                         "Оружие на своих подставках: должно лежать на ложементах, а не висеть.",
                         grid("store", store_rows, [1, 2, 3, 4], lvl_name)))
    if combat_rows:
        sections.append(("combat", "Бой (камера игры, наклон 28°, «Перевал»)",
                         "Полный подвес ур. 5 на всех узлах. Сопла — с форсажем; маркеры — розовые точки, откуда летят снаряды "
                         "курсовой пушки, турелей, ракет и бомб; подвесы — самолёт в крене брюхом к камере.",
                         grid("combat", combat_rows, list(SHOTS), lambda c, k: SHOTS[c])))
    nav = "".join(f"<a href='#{s[0]}'>{e(s[1].split(' (')[0].split(':')[0])}</a>" for s in sections)
    sec_html = "".join(f"<section id='{s[0]}'><h2>{e(s[1])}</h2><p class='note'>{e(s[2])}</p>{s[3]}</section>" for s in sections)
    pbtn = "".join(f"<button data-gfx='{p}'>{p} · {e(PRESETS.get(p, str(p)))}</button>" for p in presets)
    counts = {s: sum(1 for f in shot if f["section"] == s) for s in ("hangar", "store", "combat")}
    status = "СБОИ" if d["failures"] else "ok"
    return PAGE.format(
        build=e(d["build"] or "?"), commit=e(d["commit"] or "?"), date=e(d["date"]), presets=e(pre_txt),
        renderer=e(d["renderer"] or "?"), total=len(shot), hangar=counts["hangar"], store=counts["store"],
        combat=counts["combat"], nfail=len(d["failures"]), niss=len(d["issues"]), status=status,
        status_cls="bad" if d["failures"] else "ok", runs=run_rows, fails=fail_html, issues=iss_html, nav=nav,
        sections=sec_html, pbtn=pbtn, first=presets[0] if presets else 0,
    )


PAGE = """<!doctype html>
<html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Самопроверка сборки</title>
<style>
:root {{ --bg:#15171a; --fg:#e8e6e1; --mut:#9aa0a8; --card:#1f2226; --line:#30343a; --acc:#f2a93b; --bad:#ff5a5a; --ok:#7ed491; }}
* {{ box-sizing:border-box; }}
body {{ margin:0; background:var(--bg); color:var(--fg); font:15px/1.45 system-ui, sans-serif; }}
header {{ padding:20px 24px 8px; }}
h1 {{ margin:0 0 6px; font-size:24px; }} h2 {{ margin:28px 0 4px; font-size:20px; color:var(--acc); }}
.meta {{ color:var(--mut); }} .meta b {{ color:var(--fg); }}
.ok {{ color:var(--ok); }} .bad, .bad a {{ color:var(--bad); }}
main {{ padding:0 24px 40px; }}
table {{ border-collapse:collapse; margin:8px 0; }} td, th {{ border:1px solid var(--line); padding:4px 8px; text-align:left; }}
th {{ color:var(--mut); font-weight:500; }}
table.iss td:first-child {{ white-space:nowrap; }}
nav {{ position:sticky; top:0; z-index:5; background:var(--bg); padding:8px 24px; border-bottom:1px solid var(--line);
  display:flex; gap:14px; flex-wrap:wrap; align-items:center; }}
nav a {{ color:var(--fg); }} nav .sp {{ flex:1; }}
nav button {{ background:var(--card); color:var(--fg); border:1px solid var(--line); padding:4px 10px; border-radius:6px; cursor:pointer; }}
nav button.on {{ background:var(--acc); color:#111; border-color:var(--acc); }}
.note {{ color:var(--mut); margin:0 0 10px; }}
.row {{ display:grid; grid-template-columns:200px repeat(5, minmax(0, 1fr)); gap:8px; margin:0 0 10px; align-items:start; }}
.rh {{ font-weight:600; padding-top:4px; }}
.cell {{ margin:0; position:relative; background:var(--card); border:2px solid transparent; border-radius:6px; overflow:hidden; }}
.cell img {{ width:100%; display:block; aspect-ratio:16/9; object-fit:cover; }}
.cell figcaption {{ font-size:13px; padding:3px 6px; color:var(--mut); }}
.cell.bad {{ border-color:var(--bad); }}
.cell.na, .cell.miss {{ aspect-ratio:16/9; display:flex; flex-direction:column; align-items:center; justify-content:center; color:var(--mut); }}
.cell.miss {{ border-color:var(--bad); color:var(--bad); }}
.badge {{ position:absolute; top:6px; right:6px; background:var(--bad); color:#fff; border-radius:10px; padding:0 7px; font-size:13px; }}
.preset {{ display:none; }} .preset.on {{ display:block; }}
#lb {{ position:fixed; inset:0; background:rgba(0,0,0,.92); display:none; z-index:10; overflow:hidden; cursor:grab; }}
#lb.on {{ display:block; }}
#lb img {{ position:absolute; left:0; top:0; transform-origin:0 0; user-select:none; -webkit-user-drag:none; }}
#lbcap {{ position:fixed; left:0; right:0; bottom:0; padding:8px 16px; background:rgba(0,0,0,.7); font-size:14px; z-index:11; white-space:pre-line; }}
#lbx {{ position:fixed; top:10px; right:16px; font-size:28px; z-index:11; cursor:pointer; color:#fff; }}
@media (max-width: 900px) {{ .row {{ grid-template-columns:1fr 1fr; }} .rh {{ grid-column:1 / -1; }} header, main {{ padding-left:16px; padding-right:16px; }} }}
</style></head><body>
<header>
<h1>Самопроверка сборки Flak Heaven — <span class="{status_cls}">{status}</span></h1>
<div class="meta">Сборка <b>{build}</b> · коммит <b>{commit}</b> · {date} · пресеты: <b>{presets}</b> · отрисовка: <b>{renderer}</b></div>
<div class="meta">Кадров: <b>{total}</b> (ангар {hangar}, склад {store}, бой {combat}) · сбоев: <b class="{status_cls}">{nfail}</b> · находок автопроверок: <b>{niss}</b></div>
</header>
<nav>{nav}<span class="sp"></span>Пресет: {pbtn}</nav>
<main>
<h2>Прогоны</h2>
<table><tr><th>Часть</th><th>Пресет</th><th>Время</th><th>Кадров</th><th>Выход</th><th>SCRIPT ERROR</th><th>прочие ERROR</th></tr>{runs}</table>
<h2>Сбои</h2>{fails}
<h2>Автопроверки</h2>
<p class="note">Зазор детали до обшивки (пилон, турель, точка вылета) больше 1% длины самолёта; факел без обода сопла вокруг;
оружие на складе не на подставке; нет узла (модели, факела, точки пушки); число турелей не по уровню.</p>
{issues}
{sections}
</main>
<div id="lb"><img id="lbimg" alt=""><div id="lbx" title="Закрыть (Esc)">✕</div><div id="lbcap"></div></div>
<script>
(function () {{
  var gfx = {first};
  function show(g) {{
    gfx = g;
    document.querySelectorAll('.preset').forEach(function (p) {{ p.classList.toggle('on', +p.dataset.gfx === g); }});
    document.querySelectorAll('nav button').forEach(function (b) {{ b.classList.toggle('on', +b.dataset.gfx === g); }});
  }}
  document.querySelectorAll('nav button').forEach(function (b) {{ b.onclick = function () {{ show(+b.dataset.gfx); }}; }});
  show(gfx);
  var lb = document.getElementById('lb'), im = document.getElementById('lbimg'), cap = document.getElementById('lbcap');
  var list = [], idx = 0, s = 1, x = 0, y = 0, drag = null;
  function fit() {{
    var k = Math.min(innerWidth / im.naturalWidth, innerHeight / im.naturalHeight);
    s = k; x = (innerWidth - im.naturalWidth * k) / 2; y = (innerHeight - im.naturalHeight * k) / 2; draw();
  }}
  function draw() {{ im.style.transform = 'translate(' + x + 'px,' + y + 'px) scale(' + s + ')'; }}
  function open(a) {{
    list = Array.prototype.slice.call(document.querySelectorAll('.preset.on a[data-full]'));
    idx = Math.max(0, list.indexOf(a));
    load();
    lb.classList.add('on');
  }}
  function load() {{
    var a = list[idx]; if (!a) return;
    im.onload = fit; im.src = a.dataset.full; cap.textContent = a.title + '   [' + (idx + 1) + ' / ' + list.length + ']';
  }}
  document.addEventListener('click', function (ev) {{
    var a = ev.target.closest('a[data-full]');
    if (a) {{ ev.preventDefault(); open(a); return; }}
    var o = ev.target.closest('a[data-open]');
    if (o) {{
      ev.preventDefault();
      var t = document.querySelector('a[data-full="' + o.dataset.open + '"]');
      if (t) {{ var pr = t.closest('.preset'); show(+pr.dataset.gfx); open(t); }}
    }}
  }});
  document.getElementById('lbx').onclick = function () {{ lb.classList.remove('on'); }};
  lb.addEventListener('wheel', function (ev) {{
    ev.preventDefault();
    var k = ev.deltaY < 0 ? 1.2 : 1 / 1.2;
    x = ev.clientX - (ev.clientX - x) * k; y = ev.clientY - (ev.clientY - y) * k; s *= k; draw();
  }}, {{ passive: false }});
  lb.addEventListener('mousedown', function (ev) {{ if (ev.target === im) {{ drag = [ev.clientX - x, ev.clientY - y]; ev.preventDefault(); }} }});
  addEventListener('mousemove', function (ev) {{ if (drag) {{ x = ev.clientX - drag[0]; y = ev.clientY - drag[1]; draw(); }} }});
  addEventListener('mouseup', function () {{ drag = null; }});
  im.addEventListener('dblclick', function (ev) {{
    var full = Math.abs(s - 1) < 0.01;
    if (full) {{ fit(); return; }}
    x = ev.clientX - (ev.clientX - x) / s; y = ev.clientY - (ev.clientY - y) / s; s = 1; draw();
  }});
  lb.addEventListener('click', function (ev) {{ if (ev.target === lb) lb.classList.remove('on'); }});
  addEventListener('keydown', function (ev) {{
    if (!lb.classList.contains('on')) return;
    if (ev.key === 'Escape') lb.classList.remove('on');
    if (ev.key === 'ArrowRight') {{ idx = (idx + 1) % list.length; load(); }}
    if (ev.key === 'ArrowLeft') {{ idx = (idx - 1 + list.length) % list.length; load(); }}
    if (ev.key === '0') fit();
  }});
  addEventListener('resize', function () {{ if (lb.classList.contains('on')) fit(); }});
}})();
</script>
</body></html>
"""


if __name__ == "__main__":
    sys.exit(main())
