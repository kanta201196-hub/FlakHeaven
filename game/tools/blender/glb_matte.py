"""Матовая краска у готовых GLB без пересборки (Kanta 19.10: «окраска реалистичная и матовая, без блеска»).
Меняет только множители материалов (roughnessFactor / metallicFactor), картинки остаются байт в байт (glb_io) —
Godot извлечённые текстуры не перезаписывает. Материалы стекла/фар (имя содержит glass) — полуматовые.
Запуск: python3 glb_matte.py <файл.glb> [...] [--rough=0.9] [--metal=0.0]"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glb_io

rough, metal = 0.9, 0.0
files = []
for a in sys.argv[1:]:
    if a.startswith("--rough="):
        rough = float(a.split("=")[1])
    elif a.startswith("--metal="):
        metal = float(a.split("=")[1])
    else:
        files.append(a)
for f in files:
    g = glb_io.load(f)
    for m in g.j.get("materials", []):
        pbr = m.setdefault("pbrMetallicRoughness", {})
        glass = "glass" in m.get("name", "").lower()
        pbr["roughnessFactor"] = 0.35 if glass else rough
        pbr["metallicFactor"] = 0.05 if glass else metal
    g.save(f)
    print(f, [(m.get("name"), m["pbrMetallicRoughness"]["roughnessFactor"]) for m in g.j.get("materials", [])])
