"""S13-7 (Kanta 27.10: «край крыла у Кита очень грязный»): rebuild the flat slab parts of the silhouette detail GLBs
(models/mech/fh_detail_<key>.glb from bomber_detail.py / attacker2_detail.py) as real lifting surfaces.

The winglets, canted nacelle fins and canards of «Кит» 2, the tailplane endplates of «Кит» 1 and the canards of
«Грач» 2 were 8-vertex boxes (a 4-point outline extruded ± a hair) in one flat «detail_» colour, some with a black
leading-edge face: in the hangar they read as grey cardboard with dark ragged edges, and the winglet root sat
inboard of the wing tip, so the tip's own rough edge showed under it. Here each slab becomes a tapered symmetric
airfoil (NACA 00xx thickness over the local chord, cosine-spaced so the leading edge is round), lofted from its
root chord to its tip chord along the same outline, with smooth normals, a root that runs a little into the skin
it stands on (the winglet's root also drops over the whole wing-tip edge and sits just outboard of it) and closed
end caps. Paint: vertex colours from the part's old colour with weathering (grime at the root and the trailing
edge, worn lighter leading edge, mottling), matte, material «mech_skin_<part>» — WingMech.attach_detail gives it
the skin material and Livery repaints it with the plane like the slats and flaps. The bodies of revolution (tip
tanks and pods) keep their shape and take the same weathered vertex-colour paint; their dark nose cones stay.

numpy only (glb_io reads the source), run from game/tools/blender:
  python3 -I detail_foils.py ../../models/mech/fh_detail_bomber_2.glb ../../models/mech/fh_detail_bomber_2.glb
(also bomber_1, attacker_2). Rerun bomber_detail.py / attacker2_detail.py first only if the outlines change: this
script reads the outline of each slab from the GLB it is given."""
import json
import os
import struct
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glb_io  # noqa: E402

FOILS = ("winglet", "fin", "canard", "endplate")
# thickness / chord per part: winglets and fins carry load, canards and endplates are thinner
T_RATIO = {"winglet": 0.10, "fin": 0.09, "canard": 0.075, "endplate": 0.07}
# how far the root runs below the outline's root edge, as a share of the span (into the skin it stands on)
ROOT_DIP = {"winglet": 0.1, "fin": 0.06, "canard": 0.08, "endplate": 0.0}
WINGLET_OUT = 0.0045   # the winglet moves this far outboard (model units): its root covers the wing-tip edge
NC, NS = 18, 7         # chordwise points per surface, spanwise stations


def _hash(p):
    return np.modf(np.abs(np.sin(p @ np.array([12.9898, 78.233, 37.719])) * 43758.5453))[0]


def _noise(p, f):
    """Smooth-ish mottling from three hashed octaves of the position"""
    return (_hash(np.floor(p * f)) * 0.5 + _hash(np.floor(p * f * 2.3) + 7.0) * 0.3 + _hash(p * 997.0) * 0.2)


def _material(g, mi_, prim):
    m = g.j["materials"][prim["material"]] if "material" in prim else {}
    pbr = m.get("pbrMetallicRoughness", {})
    return m.get("name", ""), np.array(pbr.get("baseColorFactor", [0.6, 0.55, 0.45, 1.0])[:3])


def _outline(P):
    """Mid-plane outline of a slab (8 corner positions): 4 points in polygon order and the plate normal"""
    U = np.unique(np.round(P, 6), axis=0)
    c = U.mean(0)
    _, _, vt = np.linalg.svd(U - c)
    n = vt[2]
    # the slab is the outline offset by ±d (d not exactly along n): one face on each side of the mid-plane,
    # each corner paired with its nearest corner on the other face
    side = (U - c) @ n > 0
    A, B = U[side], U[~side]
    assert len(A) == 4 and len(B) == 4, "slab is not an 8-corner plate: %d/%d" % (len(A), len(B))
    mids = np.array([(a + B[np.argmin(np.linalg.norm(B - a, axis=1))]) * 0.5 for a in A])
    e1 = vt[0]
    e2 = np.cross(n, e1)
    ang = np.arctan2((mids - c) @ e2, (mids - c) @ e1)
    return mids[np.argsort(ang)], n


def _edges(Q):
    """root LE, root TE, tip LE, tip TE of a quad outline (nose is +X)"""
    ed = [(i, (i + 1) % 4) for i in range(4)]

    def chordness(e):
        d = Q[e[1]] - Q[e[0]]
        return abs(d[0]) / max(np.linalg.norm(d), 1e-9)
    pair = [(ed[0], ed[2]), (ed[1], ed[3])]
    rt = max(pair, key=lambda pr: chordness(pr[0]) + chordness(pr[1]))
    root, tip = sorted(rt, key=lambda e: -np.linalg.norm(Q[e[1]] - Q[e[0]]))

    def le_te(e):
        a, b = Q[e[0]], Q[e[1]]
        return (a, b) if a[0] > b[0] else (b, a)
    rle, rte = le_te(root)
    tle, tte = le_te(tip)
    return rle, rte, tle, tte


def _foil(kind, Q, n, col, side):
    rle, rte, tle, tte = _edges(Q)
    if kind == "winglet":
        out = np.array([0.0, 0.0, np.sign(side)]) * WINGLET_OUT
        rle, rte, tle, tte = rle + out, rte + out, tle + out, tte + out
    s0 = -ROOT_DIP[kind]
    t = T_RATIO[kind]
    cs = 0.5 * (1.0 - np.cos(np.linspace(0.0, np.pi, NC)))   # 0 at the LE, 1 at the TE, dense at both ends
    yt = 5 * t * (0.2969 * np.sqrt(cs) - 0.1260 * cs - 0.3516 * cs ** 2 + 0.2843 * cs ** 3 - 0.1036 * cs ** 4)
    # top TE→LE, then bottom LE→TE with its own TE point: the trailing edge stays sharp (a shared vertex there
    # averaged the two faces into a bright crease along the span)
    ring_c = np.concatenate([cs[::-1], cs[1:]])
    ring_y = np.concatenate([yt[::-1], -yt[1:]])
    nr = len(ring_c)
    # n points to the side the outline's winding faces; the sign does not matter for a symmetric section
    V, C, F = [], [], []
    for k, s in enumerate(np.linspace(s0, 1.0, NS)):
        le = rle + (tle - rle) * s
        te = rte + (tte - rte) * s
        L = np.linalg.norm(te - le)
        taper = 1.0 if s < 0.9 else 1.0 - 0.45 * (s - 0.9) / 0.1   # a softer tip, not a cut-off slab
        for c, y in zip(ring_c, ring_y):
            V.append(le + (te - le) * c + n * y * L * taper)
            C.append((c, s))
    V = np.array(V)
    for k in range(NS - 1):
        for i in range(nr):
            a, b = k * nr + i, k * nr + (i + 1) % nr
            F.append((a, b, b + nr))
            F.append((a, b + nr, a + nr))
    F = np.array(F)
    # end caps: their own vertices, flat
    caps_v, caps_f = [], []
    for k, flip in ((0, True), (NS - 1, False)):
        base = len(V) + len(caps_v)
        ring = V[k * nr:(k + 1) * nr]
        ctr = ring.mean(0)
        caps_v.extend(list(ring) + [ctr])
        for i in range(nr):
            f = (base + i, base + (i + 1) % nr, base + nr)
            caps_f.append(f[::-1] if flip else f)
        C.extend([(0.5, 0.0 if k == 0 else 1.0)] * (nr + 1))
    V = np.vstack([V, np.array(caps_v)])
    F = np.vstack([F, np.array(caps_f)])
    F = _outward(V, F)
    N = _normals(V, F, smooth_upto=NS * nr)
    cc = np.array(C)
    # weathering: grime at the root and along the trailing edge, a lighter worn leading edge, mottling
    grime = 0.10 * np.clip(1.0 - (cc[:, 1] - s0) / 0.25, 0, 1) + 0.08 * np.clip((cc[:, 0] - 0.75) / 0.25, 0, 1)
    wear = 0.07 * np.clip(1.0 - cc[:, 0] / 0.06, 0, 1)
    mot = (_noise(V, 140.0) - 0.5) * 0.08
    k = np.clip(1.0 - grime + wear + mot, 0.75, 1.12)
    cols = np.clip(col[None, :] * k[:, None], 0, 1)
    return V, N, cols, F


def _outward(V, F):
    """Wind every triangle so its normal faces away from the part's centroid line (closed, convex-ish solids)"""
    c = V.mean(0)
    a, b, d = V[F[:, 0]], V[F[:, 1]], V[F[:, 2]]
    fn = np.cross(b - a, d - a)
    fc = (a + b + d) / 3
    bad = np.einsum("ij,ij->i", fn, fc - c) < 0
    F = F.copy()
    F[bad] = F[bad][:, [0, 2, 1]]
    return F


def _normals(V, F, smooth_upto):
    """Area-weighted vertex normals; the caps (vertices from smooth_upto on) get their face normal"""
    a, b, d = V[F[:, 0]], V[F[:, 1]], V[F[:, 2]]
    fn = np.cross(b - a, d - a)
    N = np.zeros_like(V)
    for i in range(3):
        np.add.at(N, F[:, i], fn)
    N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-12)
    return N


def _weather_body(V, col):
    """Tip tanks and pods: soot and grime toward the tail, mottling"""
    x0, x1 = V[:, 0].min(), V[:, 0].max()
    q = (V[:, 0] - x0) / max(x1 - x0, 1e-6)   # 0 at the tail
    k = 1.0 - 0.12 * np.clip(1.0 - q / 0.35, 0, 1) + (_noise(V, 140.0) - 0.5) * 0.08
    return np.clip(col[None, :] * np.clip(k, 0.75, 1.1)[:, None], 0, 1)


class Writer:
    """Minimal GLB writer: nodes with one mesh each, positions in model axes (no node transforms)"""

    def __init__(self):
        self.j = {"asset": {"version": "2.0", "generator": "detail_foils.py"}, "scene": 0, "scenes": [{"nodes": []}],
                  "nodes": [], "meshes": [], "materials": [], "accessors": [], "bufferViews": [],
                  "buffers": [{"byteLength": 0}]}
        self.bin = bytearray()

    def _acc(self, arr, kind, target, comp=5126):
        arr = np.ascontiguousarray(arr, dtype={5126: np.float32, 5125: np.uint32, 5123: np.uint16}[comp])
        while len(self.bin) % 4:
            self.bin.append(0)
        self.j["bufferViews"].append({"buffer": 0, "byteOffset": len(self.bin), "byteLength": int(arr.nbytes),
                                      "target": target})
        self.bin += arr.tobytes()
        a = {"bufferView": len(self.j["bufferViews"]) - 1, "componentType": comp, "count": int(arr.shape[0]),
             "type": kind}
        if kind == "VEC3" and comp == 5126:
            a["min"] = [float(v) for v in arr.min(0)]
            a["max"] = [float(v) for v in arr.max(0)]
        self.j["accessors"].append(a)
        return len(self.j["accessors"]) - 1

    def material(self, name, col, rough, metal):
        self.j["materials"].append({"name": name, "pbrMetallicRoughness": {
            "baseColorFactor": [float(col[0]), float(col[1]), float(col[2]), 1.0],
            "roughnessFactor": float(rough), "metallicFactor": float(metal)}})
        return len(self.j["materials"]) - 1

    def prim(self, V, N, F, mat, cols=None):
        at = {"POSITION": self._acc(V, "VEC3", 34962), "NORMAL": self._acc(N, "VEC3", 34962)}
        if cols is not None:
            at["COLOR_0"] = self._acc(np.c_[cols, np.ones(len(cols))], "VEC4", 34962)
        idx = np.asarray(F).reshape(-1)
        comp = 5123 if idx.max() < 65535 else 5125
        return {"attributes": at, "indices": self._acc(idx.reshape(-1, 1), "SCALAR", 34963, comp), "material": mat}

    def node(self, name, prims):
        self.j["meshes"].append({"name": name, "primitives": prims})
        self.j["nodes"].append({"name": name, "mesh": len(self.j["meshes"]) - 1})
        self.j["scenes"][0]["nodes"].append(len(self.j["nodes"]) - 1)

    def save(self, path):
        while len(self.bin) % 4:
            self.bin.append(0)
        self.j["buffers"][0]["byteLength"] = len(self.bin)
        js = json.dumps(self.j, separators=(",", ":")).encode()
        while len(js) % 4:
            js += b" "
        with open(path, "wb") as f:
            f.write(b"glTF" + struct.pack("<II", 2, 12 + 8 + len(js) + 8 + len(self.bin)))
            f.write(struct.pack("<I", len(js)) + b"JSON" + js)
            f.write(struct.pack("<I", len(self.bin)) + b"BIN\x00" + bytes(self.bin))


def main() -> int:
    src, dst = sys.argv[1], sys.argv[2]
    g = glb_io.load(src)
    w = Writer()
    for ni, nd in enumerate(g.j["nodes"]):
        if "mesh" not in nd:
            continue
        mi_ = nd["mesh"]
        name = nd.get("name", "part%d" % ni)
        kind = next((k for k in FOILS if name.startswith(k)), "")
        M = g.world_of_mesh(mi_)
        prims_src = g.j["meshes"][mi_]["primitives"]
        mname, col = _material(g, mi_, prims_src[0])
        if kind:
            P = np.vstack([g.mesh_world(mi_, k)[0] for k in range(len(prims_src))])
            side = np.sign(P[:, 2].mean()) or 1.0   # which wing: outboard is ±Z in model axes
            Q, n = _outline(P)
            V, N, cols, F = _foil(kind, Q, n, col, side)
            mat = w.material("mech_skin_" + name, (1, 1, 1), 0.82, 0.08)
            w.node(name, [w.prim(V, N, F, mat, cols)])
            print("%s: foil %d verts, %d tris (was %d tris)" % (name, len(V), len(F),
                                                              sum(len(g.mesh_world(mi_, k)[1]) for k in range(len(prims_src)))))
            continue
        prims = []
        for k, p in enumerate(prims_src):
            V, F = g.mesh_world(mi_, k)
            Nn = g.accessor(p["attributes"]["NORMAL"]).astype(np.float64) @ np.linalg.inv(M[:3, :3])
            Nn /= np.maximum(np.linalg.norm(Nn, axis=1, keepdims=True), 1e-12)
            pn, pc = _material(g, mi_, p)
            m0 = g.j["materials"][p["material"]] if "material" in p else {}
            pbr = m0.get("pbrMetallicRoughness", {})
            if pn.startswith("detail_dark"):
                mat = w.material(pn, pc, pbr.get("roughnessFactor", 0.5), pbr.get("metallicFactor", 0.3))
                prims.append(w.prim(V, Nn, F, mat))
            else:   # the body: weathered vertex colours, matte, painted by Livery like the skin
                mat = w.material("mech_skin_" + name, (1, 1, 1), 0.82, 0.08)
                prims.append(w.prim(V, Nn, F, mat, _weather_body(V, pc)))
        w.node(name, prims)
        print("%s: kept, %d prims repainted" % (name, len(prims)))
    w.save(dst)
    print("saved", dst)
    return 0


if __name__ == "__main__":
    sys.exit(main())
