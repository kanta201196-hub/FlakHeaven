#!/usr/bin/env python3
"""Склеивает в GLB примитивы одного меша с одинаковым материалом в один примитив.

Зачем: каждый примитив glTF в Godot — отдельная поверхность, то есть отдельный вызов отрисовки
(и ещё один в проходе теней). Экспорт из Blender (tools/blender/convoy_kit.py) даёт машины конвоя
по 23–36 примитивов при 2 материалах; после склейки — 7–9. Геометрия, UV, нормали и узлы
(колёса, башня) не меняются, LOD и меши теней Godot строит при импорте как раньше.

Запуск: python3 game/tools/glb_merge_prims.py game/models/battle/fh_battle_e_convoy_*.glb
Только стандартная библиотека Python; файл перезаписывается на месте.
"""
import json
import struct
import sys

COMP_SIZE = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
TYPE_N = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}


def read_glb(path):
    d = open(path, "rb").read()
    magic, ver, total = struct.unpack("<III", d[:12])
    assert magic == 0x46546C67 and ver == 2, path
    off = 12
    js = None
    bin_ = b""
    while off < total:
        clen, ctype = struct.unpack("<II", d[off:off + 8])
        chunk = d[off + 8:off + 8 + clen]
        if ctype == 0x4E4F534A:
            js = json.loads(chunk)
        elif ctype == 0x004E4942:
            bin_ = chunk
        off += 8 + clen
    return js, bin_


def write_glb(path, js, bin_):
    jb = json.dumps(js, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    jb += b" " * ((4 - len(jb) % 4) % 4)
    bin_ += b"\0" * ((4 - len(bin_) % 4) % 4)
    total = 12 + 8 + len(jb) + 8 + len(bin_)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(jb), 0x4E4F534A) + jb)
        f.write(struct.pack("<II", len(bin_), 0x004E4942) + bin_)


def elem_size(acc):
    return COMP_SIZE[acc["componentType"]] * TYPE_N[acc["type"]]


def acc_bytes(js, bin_, ai):
    """Плотные байты аксессора (без шага bufferView)."""
    acc = js["accessors"][ai]
    assert "sparse" not in acc, "sparse не поддержан"
    bv = js["bufferViews"][acc["bufferView"]]
    es = elem_size(acc)
    stride = bv.get("byteStride", es)
    base = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    if stride == es:
        return bin_[base:base + es * acc["count"]]
    return b"".join(bin_[base + i * stride:base + i * stride + es] for i in range(acc["count"]))


def indices(js, bin_, ai):
    acc = js["accessors"][ai]
    raw = acc_bytes(js, bin_, ai)
    fmt = {5121: "B", 5123: "H", 5125: "I"}[acc["componentType"]]
    return list(struct.unpack("<%d%s" % (acc["count"], fmt), raw))


def merge(path):
    js, bin_ = read_glb(path)
    new_data = []           # (bytes, target) — новые bufferViews, допишутся в конец
    before = sum(len(m["primitives"]) for m in js["meshes"])
    for mesh in js["meshes"]:
        groups = {}
        order = []
        for p in mesh["primitives"]:
            key = (p.get("material"), p.get("mode", 4), tuple(sorted(p["attributes"])), "indices" in p,
                   "targets" in p, tuple((k, js["accessors"][v]["componentType"], js["accessors"][v]["type"],
                                          js["accessors"][v].get("normalized", False)) for k, v in sorted(p["attributes"].items())))
            if key not in groups:
                groups[key] = []
                order.append(key)
            groups[key].append(p)
        prims = []
        for key in order:
            g = groups[key]
            if len(g) == 1 or key[1] != 4 or not key[3] or key[4]:
                prims.extend(g)
                continue
            out = {"attributes": {}, "indices": None}
            if key[0] is not None:
                out["material"] = key[0]
            vtx_off = 0
            idx = []
            attr_raw = {k: [] for k in g[0]["attributes"]}
            for p in g:
                n = js["accessors"][p["attributes"]["POSITION"]]["count"]
                for k, ai in p["attributes"].items():
                    attr_raw[k].append(acc_bytes(js, bin_, ai))
                idx.extend(i + vtx_off for i in indices(js, bin_, p["indices"]))
                vtx_off += n
            for k, parts in attr_raw.items():
                src = js["accessors"][g[0]["attributes"][k]]
                acc = {"componentType": src["componentType"], "type": src["type"], "count": vtx_off}
                if src.get("normalized"):
                    acc["normalized"] = True
                if k == "POSITION":
                    mins = [min(js["accessors"][p["attributes"][k]]["min"][c] for p in g) for c in range(3)]
                    maxs = [max(js["accessors"][p["attributes"][k]]["max"][c] for p in g) for c in range(3)]
                    acc["min"], acc["max"] = mins, maxs
                acc["bufferView"] = ("new", len(new_data))
                new_data.append((b"".join(parts), 34962))
                js["accessors"].append(acc)
                out["attributes"][k] = len(js["accessors"]) - 1
            big = vtx_off > 65535
            raw = struct.pack("<%d%s" % (len(idx), "I" if big else "H"), *idx)
            js["accessors"].append({"componentType": 5125 if big else 5123, "type": "SCALAR", "count": len(idx),
                                    "bufferView": ("new", len(new_data))})
            new_data.append((raw, 34963))
            out["indices"] = len(js["accessors"]) - 1
            prims.append(out)
        mesh["primitives"] = prims
    after = sum(len(m["primitives"]) for m in js["meshes"])
    if after == before:
        print("%s: %d примитивов, склеивать нечего" % (path, before))
        return
    # Пересборка: только используемые аксессоры и bufferViews, буфер плотно
    used_acc = []
    for m in js["meshes"]:
        for p in m["primitives"]:
            used_acc.extend(p["attributes"].values())
            if "indices" in p:
                used_acc.append(p["indices"])
    for s in js.get("skins", []):
        if "inverseBindMatrices" in s:
            used_acc.append(s["inverseBindMatrices"])
    for a in js.get("animations", []):
        for s in a["samplers"]:
            used_acc += [s["input"], s["output"]]
    acc_map = {}
    accs = []
    for ai in sorted(set(used_acc)):
        acc_map[ai] = len(accs)
        accs.append(js["accessors"][ai])
    out_bin = bytearray()
    views = []
    view_map = {}

    def add_view(data, target=None, stride=None):
        while len(out_bin) % 4:
            out_bin.append(0)
        v = {"buffer": 0, "byteOffset": len(out_bin), "byteLength": len(data)}
        if target:
            v["target"] = target
        if stride:
            v["byteStride"] = stride
        out_bin.extend(data)
        views.append(v)
        return len(views) - 1

    def old_view(vi):
        if vi not in view_map:
            bv = js["bufferViews"][vi]
            o = bv.get("byteOffset", 0)
            view_map[vi] = add_view(bin_[o:o + bv["byteLength"]], bv.get("target"), bv.get("byteStride"))
        return view_map[vi]

    for acc in accs:
        bv = acc["bufferView"]
        if isinstance(bv, tuple):
            data, target = new_data[bv[1]]
            acc["bufferView"] = add_view(data, target)
        else:
            acc["bufferView"] = old_view(bv)
    for img in js.get("images", []):
        if "bufferView" in img:
            img["bufferView"] = old_view(img["bufferView"])
    js["accessors"] = accs
    js["bufferViews"] = views
    for m in js["meshes"]:
        for p in m["primitives"]:
            p["attributes"] = {k: acc_map[v] for k, v in p["attributes"].items()}
            if "indices" in p:
                p["indices"] = acc_map[p["indices"]]
    for s in js.get("skins", []):
        if "inverseBindMatrices" in s:
            s["inverseBindMatrices"] = acc_map[s["inverseBindMatrices"]]
    for a in js.get("animations", []):
        for s in a["samplers"]:
            s["input"], s["output"] = acc_map[s["input"]], acc_map[s["output"]]
    js["buffers"] = [{"byteLength": len(out_bin)}]
    write_glb(path, js, bytes(out_bin))
    print("%s: примитивов %d → %d" % (path, before, after))


if __name__ == "__main__":
    for a in sys.argv[1:]:
        merge(a)
