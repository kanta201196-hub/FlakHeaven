"""S11-02/08/10/11/12: wing mechanisation and the «Kit» bomb bay cut out of the hangar models themselves.

Before (T-1, T-5) slats, flaps and bay doors were thin plates in separate GLBs (wing_mech.py, bay_doors.py) laid over
an intact skin: a lowered flap looked like a plate hinged under a whole wing, and the bombs hung under a closed belly.
Now the moving parts are the model's own skin: every section is cut out of the wing along three planes (hinge line and
two ribs), keeps the wing's triangles, UVs, thickness and edges, and gets flat end caps; the wing gets a dark recess
wall where the section was. The bay of «Kit» 1/2 is a real cavity: the belly skin inside the bay outline becomes two
doors (hinged at the outer edges) and a dark box goes up into the fuselage, so the bombs hang inside it.

Geometry is edited with numpy straight in the GLB (glb_io): the embedded images stay byte for byte the same, so the
textures Godot extracts next to the model (and the paint tones livery.gd SRC is tuned to) do not change.

Output: the same model GLB plus nodes
  wing_mech/slat_l, slat_r, flap_l, flap_r — node origin on the hinge axis, local axes as wing_mech.py plates
  (Blender: X forward along the chord, Y along the hinge to +Y, Z up), so WingMech.pose moves them the same way;
  bay_doors/bay_l, bay_r — as bay_doors.py (X forward along the hinge, open = rotation about X);
  the recess walls and the bay box are a separate primitive with the material "mech_well" in the main mesh.
WingMech.attach / attach_bay use these nodes when the model has them (hangar, title screen); battle models keep the
plates from models/mech/.

Run (bpy 5.x as a module, from game/tools/blender), input = the model BEFORE the cut (e.g. from git history):
  git show <rev>:game/models/hangar/fh_hangar_bomber_1.glb > /tmp/orig.glb
  python3 -I mech_cut.py [--close=x0,x1,y0,y1,z0,z1 ...] /tmp/orig.glb bomber_1 ../../models/hangar/fh_hangar_bomber_1.glb
--close: delete what is baked into the underside inside a box (Blender axes) and cover the hole with skin
(S11-10: the open well with a hanging door Meshy baked into each nacelle of «Kit» 2):
  --close=-0.131,-0.014,0.0425,0.069,-0.09,-0.026 --close=-0.131,-0.014,-0.069,-0.0425,-0.09,-0.026
Recipe of 25.10 (S11): source = the six fh_hangar_*.glb at origin/main 6332ec1, each run as above with its key;
bomber_2 with the two --close boxes; fighter_1 afterwards through f1_glove_pylons.py (S11-07: drops the two baked
glove pylon plates, in and out = the same hangar GLB). Then `godot --headless --path game --import`."""
import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402,F401 — registers mathutils
from mathutils import Vector, geometry  # noqa: E402

import glb_io  # noqa: E402
from mech_spans import SPANS, SLAT_C, FLAP_C  # noqa: E402

# bay outline (Blender X from..to, half width) and the depth of the box above the belly; the bombs (hangar3d "bay")
# hang from its ceiling, so it is deep enough for the tier-3 bomb (diameter ~0.05 of «Kit» 1, ~0.046 of «Kit» 2)
# to stay above the belly line. Bay length as bay_doors.py BAYS.
BAYS = {
    "bomber_1": (-0.16, 0.15, 0.029, 0.044),
    "bomber_2": (-0.31, 0.0, 0.024, 0.040),
}
DOOR_T = 0.0015       # door skin thickness
WELL_COL = (0.035, 0.035, 0.033, 1.0)   # recess walls and bay box (linear: sRGB ~0.2, in shadow as a real well), matte
EPS = 1e-7


def to_b(p):
    """glTF (Y up, Z right) -> Blender axes (Z up, Y left)"""
    return np.stack([p[:, 0], -p[:, 2], p[:, 1]], 1)


def to_g(p):
    return np.stack([p[:, 0], p[:, 2], -p[:, 1]], 1)


class Mesh:
    """Triangles of the hangar model in Blender axes: P positions, N normals, UV, T triangles, prim — the glTF
    primitive (0 skin, 1 glass) of every triangle. Seams of the UV atlas are duplicated vertices; canon() welds them by
    position, so cuts stay crack-free across seams."""

    def __init__(self, P, N, UV, T, prim):
        self.P, self.N, self.UV, self.T, self.prim = P, N, UV, T, prim

    @property
    def T(self):
        return self._T

    @T.setter
    def T(self, v):
        self._T = v
        self._bb = None     # column() cache

    def canon(self):
        q = np.round(self.P / 1e-6).astype(np.int64)
        _, inv = np.unique(q, axis=0, return_inverse=True)
        return inv.reshape(-1)

    def add_vert(self, p, n, uv):
        self.P = np.vstack([self.P, p])
        self.N = np.vstack([self.N, n])
        self.UV = np.vstack([self.UV, uv])
        return len(self.P) - 1

    # ---------- cutting ----------
    def split(self, n, d, box):
        """Split every triangle with a vertex inside box (x0,x1,y0,y1,z0,z1) that crosses the plane n·p = d; then fix
        T-junctions in the neighbours. New vertices on an edge are shared by both triangles of that edge."""
        n = np.asarray(n, float)
        s = self.P @ n - d
        sg = np.where(s > EPS, 1, np.where(s < -EPS, -1, 0))
        P = self.P
        inb = ((P[:, 0] > box[0]) & (P[:, 0] < box[1]) & (P[:, 1] > box[2]) & (P[:, 1] < box[3])
               & (P[:, 2] > box[4]) & (P[:, 2] < box[5]))
        st = sg[self.T]
        cross = (st.max(1) == 1) & (st.min(1) == -1) & inb[self.T].any(1)
        canon = self.canon()
        emap = {}     # (va, vb) sorted actual ids -> new vertex
        ckey = {}     # canonical edge -> (point position) for T-junction fixing
        newP, newN, newUV = [], [], []
        base = len(self.P)

        def edge_vert(a, b):
            k = (a, b) if a < b else (b, a)
            if k in emap:
                return emap[k]
            # position from the canonically ordered endpoints: seam duplicates get the very same point
            ca, cb = canon[a], canon[b]
            lo, hi = (a, b) if ca < cb else (b, a)
            t = s[lo] / (s[lo] - s[hi])
            p = P[lo] + t * (P[hi] - P[lo])
            nn = self.N[lo] + t * (self.N[hi] - self.N[lo])
            nn = nn / max(np.linalg.norm(nn), 1e-12)
            uv = self.UV[lo] + t * (self.UV[hi] - self.UV[lo])
            newP.append(p)
            newN.append(nn)
            newUV.append(uv)
            emap[k] = base + len(newP) - 1
            ckey[(min(ca, cb), max(ca, cb))] = emap[k]
            return emap[k]

        out, outp = [], []
        for ti in np.nonzero(cross)[0]:
            tri = self.T[ti]
            pos, neg = [], []
            for i in range(3):
                vi, vj = tri[i], tri[(i + 1) % 3]
                if sg[vi] >= 0:
                    pos.append(vi)
                if sg[vi] <= 0:
                    neg.append(vi)
                if sg[vi] * sg[vj] == -1:
                    m = edge_vert(vi, vj)
                    pos.append(m)
                    neg.append(m)
            for poly in (pos, neg):
                for k in range(1, len(poly) - 1):
                    out.append((poly[0], poly[k], poly[k + 1]))
                    outp.append(self.prim[ti])
        if newP:
            self.P = np.vstack([self.P, np.array(newP)])
            self.N = np.vstack([self.N, np.array(newN)])
            self.UV = np.vstack([self.UV, np.array(newUV)])
        keepT = self.T[~cross]
        keepp = self.prim[~cross]
        # T-junctions: a kept triangle whose edge (by position) got a new point. Keep the welded ids ckey was built
        # with and give the new points ids of their own (seam duplicates share one)
        qd, ext, nid = {}, [], int(canon.max()) + 1
        for p in newP:
            kq = tuple(np.round(np.asarray(p) / 1e-6).astype(np.int64))
            if kq not in qd:
                qd[kq] = nid
                nid += 1
            ext.append(qd[kq])
        canon = np.concatenate([canon, np.array(ext, np.int64)])
        fixT, fixp, rest = [], [], np.ones(len(keepT), bool)
        if ckey:
            ce = canon[keepT]
            for ti in range(len(keepT)):
                tri = keepT[ti]
                hit = False
                for i in range(3):
                    a, b = ce[ti, i], ce[ti, (i + 1) % 3]
                    if (min(a, b), max(a, b)) in ckey:
                        hit = True
                        break
                if not hit:
                    continue
                rest[ti] = False
                stack = [tuple(tri)]
                while stack:
                    t3 = stack.pop()
                    done = True
                    for i in range(3):
                        a, b, c = t3[i], t3[(i + 1) % 3], t3[(i + 2) % 3]
                        k = (min(canon[a], canon[b]), max(canon[a], canon[b]))
                        if k in ckey:
                            m = ckey[k]
                            # the point must lie strictly inside this sub-edge
                            pa, pb, pm = self.P[a], self.P[b], self.P[m]
                            ab = pb - pa
                            tt = np.dot(pm - pa, ab) / max(np.dot(ab, ab), 1e-20)
                            if 1e-6 < tt < 1 - 1e-6:
                                mv = self.add_vert(pm, self.N[a] + tt * (self.N[b] - self.N[a]),
                                                   self.UV[a] + tt * (self.UV[b] - self.UV[a]))
                                canon = np.append(canon, canon[m])
                                stack.append((a, mv, c))
                                stack.append((mv, b, c))
                                done = False
                                break
                    if done:
                        fixT.append(t3)
                        fixp.append(keepp[ti])
        parts = [keepT[rest]]
        pp = [keepp[rest]]
        if out:
            parts.append(np.array(out, np.int64))
            pp.append(np.array(outp))
        if fixT:
            parts.append(np.array(fixT, np.int64))
            pp.append(np.array(fixp))
        self.T = np.vstack(parts)
        self.prim = np.concatenate(pp)

    # ---------- queries ----------
    def column(self, x, y, prim=0):
        """Vertical line through (x, y): [(z, triangle)] from the top down"""
        if self._bb is None:
            A = self.P[self.T]
            self._bb = (A[:, :, :2].min(1), A[:, :, :2].max(1))
        self._lo, self._hi = self._bb
        m = (self._lo[:, 0] <= x) & (self._hi[:, 0] >= x) & (self._lo[:, 1] <= y) & (self._hi[:, 1] >= y) & (self.prim == prim)
        out = []
        for ti in np.nonzero(m)[0]:
            a, b, c = self.P[self.T[ti]]
            v0, v1, v2 = b[:2] - a[:2], c[:2] - a[:2], np.array([x, y]) - a[:2]
            den = v0[0] * v1[1] - v1[0] * v0[1]
            if abs(den) < 1e-14:
                continue
            u = (v2[0] * v1[1] - v1[0] * v2[1]) / den
            w = (v0[0] * v2[1] - v2[0] * v0[1]) / den
            if u < -1e-9 or w < -1e-9 or u + w > 1 + 1e-9:
                continue
            out.append((a[2] + u * (b[2] - a[2]) + w * (c[2] - a[2]), ti))
        return sorted(out, key=lambda h: -h[0])

    def region(self, mask, seeds):
        """Triangles in mask connected (through shared edges, by position) to the seed triangles"""
        canon = self.canon()
        idx = np.nonzero(mask)[0]
        edges = {}
        for ti in idx:
            c = canon[self.T[ti]]
            for i in range(3):
                k = (min(c[i], c[(i + 1) % 3]), max(c[i], c[(i + 1) % 3]))
                edges.setdefault(k, []).append(ti)
        seen = set(s for s in seeds if mask[s])
        stack = list(seen)
        while stack:
            ti = stack.pop()
            c = canon[self.T[ti]]
            for i in range(3):
                k = (min(c[i], c[(i + 1) % 3]), max(c[i], c[(i + 1) % 3]))
                for nb in edges.get(k, ()):
                    if nb not in seen:
                        seen.add(nb)
                        stack.append(nb)
        out = np.zeros(len(self.T), bool)
        out[list(seen)] = True
        # slivers left by T-junction fixes can drop out of the walk: take in every masked triangle that only plugs
        # a tiny hole of the region
        for lp in self.loops(out):
            if len(lp) > 6:
                continue
            ring = set(canon[lp])
            for ti in idx:
                if not out[ti] and set(canon[self.T[ti]]) <= ring:
                    out[ti] = True
        return out

    def loops(self, sel):
        """Boundary loops of the triangle set sel (positions welded): lists of vertex ids in winding order"""
        canon = self.canon()
        rep = {}
        nxt = {}
        cnt = {}
        for ti in np.nonzero(sel)[0]:
            t = self.T[ti]
            for i in range(3):
                a, b = t[i], t[(i + 1) % 3]
                ca, cb = canon[a], canon[b]
                rep.setdefault(ca, a)
                k = (min(ca, cb), max(ca, cb))
                cnt[k] = cnt.get(k, 0) + 1
                nxt.setdefault(ca, []).append(cb)
        bnd = {}
        for ca, lst in nxt.items():
            for cb in lst:
                if cnt[(min(ca, cb), max(ca, cb))] == 1:
                    bnd.setdefault(ca, []).append(cb)
        out = []
        used = set()
        for start in list(bnd):
            if start in used:
                continue
            loop = [start]
            used.add(start)
            cur = start
            while True:
                nx = [c for c in bnd.get(cur, []) if c not in used or (c == start and len(loop) > 2)]
                if not nx:
                    break
                cur = nx[0]
                if cur == start:
                    break
                loop.append(cur)
                used.add(cur)
            out.append([rep[c] for c in loop])
        return out


# ---------- GLB ----------
def load(path):
    g = glb_io.load(path)
    mesh = g.j["meshes"][0]
    prims = mesh["primitives"]
    a0 = prims[0]["attributes"]
    pos = g.accessor(a0["POSITION"]).astype(np.float64)
    nrm = g.accessor(a0["NORMAL"]).astype(np.float64)
    uv = g.accessor(a0["TEXCOORD_0"]).astype(np.float64)
    T, prim = [], []
    shared = len(prims) > 1 and prims[1]["attributes"]["POSITION"] == a0["POSITION"]
    for pi, p in enumerate(prims):
        if pi > 0 and not shared:
            continue
        t = g.accessor(p["indices"]).reshape(-1, 3).astype(np.int64)
        T.append(t)
        prim.append(np.full(len(t), pi))
    m = Mesh(to_b(pos), to_b(nrm), uv, np.vstack(T), np.concatenate(prim))
    return g, m, shared


def _acc(g, arr, typ, ctype, target=None, minmax=False):
    arr = np.ascontiguousarray(arr)
    while len(g.bin) % 4:
        g.bin.append(0)
    off = len(g.bin)
    g.bin += arr.tobytes()
    bv = {"buffer": 0, "byteOffset": off, "byteLength": int(arr.nbytes)}
    if target:
        bv["target"] = target
    g.j["bufferViews"].append(bv)
    a = {"bufferView": len(g.j["bufferViews"]) - 1, "componentType": ctype, "count": int(len(arr)), "type": typ}
    if minmax:
        a["min"] = [float(v) for v in arr.min(0)]
        a["max"] = [float(v) for v in arr.max(0)]
    g.j["accessors"].append(a)
    return len(g.j["accessors"]) - 1


def prim_dict(g, P, N, UV, T, mat):
    """New primitive from arrays in Blender axes"""
    attrs = {"POSITION": _acc(g, to_g(P).astype(np.float32), "VEC3", 5126, 34962, True),
             "NORMAL": _acc(g, to_g(N).astype(np.float32), "VEC3", 5126, 34962)}
    if UV is not None:
        attrs["TEXCOORD_0"] = _acc(g, UV.astype(np.float32), "VEC2", 5126, 34962)
    flat = np.asarray(T).reshape(-1)
    idx = flat.astype(np.uint32) if flat.max() >= 65535 else flat.astype(np.uint16)
    return {"attributes": attrs, "indices": _acc(g, idx, "SCALAR", 5125 if idx.dtype == np.uint32 else 5123, 34963),
            "material": mat}


def compact_mesh(m, sel):
    """Vertices and triangles of the selected triangles, renumbered"""
    T = m.T[sel]
    used, inv = np.unique(T.reshape(-1), return_inverse=True)
    return m.P[used].copy(), m.N[used].copy(), m.UV[used].copy(), inv.reshape(-1, 3)


# ---------- skin colour ----------
_TEX = {}


def load_tex(g):
    """Base colour image of the skin material (embedded in the GLB) as a float array, rows bottom-up like UV"""
    import io
    from PIL import Image
    mat = g.j["materials"][g.j["meshes"][0]["primitives"][0].get("material", 0)]
    ti = mat["pbrMetallicRoughness"]["baseColorTexture"]["index"]
    im = g.j["images"][g.j["textures"][ti]["source"]]
    bv = g.j["bufferViews"][im["bufferView"]]
    o = bv.get("byteOffset", 0)
    img = Image.open(io.BytesIO(bytes(g.bin[o:o + bv["byteLength"]]))).convert("RGB")
    img = img.resize((512, 512))
    _TEX["px"] = np.asarray(img, np.float32)[::-1] / 255.0


def skin_uv(m, verts):
    """UV of the vertex whose texel is the median brightness among verts: a flat face mapped there gets the usual
    skin tone, not a panel line or a dark smudge"""
    verts = list(verts)
    if "px" not in _TEX or not verts:
        return m.UV[verts[0]]
    px = _TEX["px"]
    h, w = px.shape[:2]
    uv = m.UV[verts]
    # glTF UV: v down from the top; the array rows run bottom-up
    xs = np.clip((uv[:, 0] % 1.0) * (w - 1), 0, w - 1).astype(int)
    ys = np.clip((1.0 - uv[:, 1] % 1.0) * (h - 1), 0, h - 1).astype(int)
    lum = px[ys, xs].mean(1)
    return uv[np.argsort(lum)[len(lum) // 2]]


# ---------- caps ----------
def plane_runs(P, loop, planes):
    """For every plane: the parts of the closed loop lying on it, in loop order, joined into one polygon"""
    on = np.array([[abs(np.dot(P[v], n) - d) < 2e-6 for (n, d) in planes] for v in loop])
    polys = []
    for k in range(len(planes)):
        col = on[:, k]
        if col.all() or not col.any():
            polys.append([] if not col.all() else list(loop))
            continue
        st = int(np.nonzero(~col)[0][0])     # start the walk off the plane
        order = loop[st:] + loop[:st]
        oc = list(col[st:]) + list(col[:st])
        runs, cur = [], []
        for v, c in zip(order, oc):
            if c:
                cur.append(v)
            elif cur:
                runs.append(cur)
                cur = []
        if cur:
            runs.append(cur)
        poly = [v for r in runs if len(r) >= 2 for v in r]
        polys.append(poly)
    free = int((~on.any(1)).sum())
    return polys, free


def tess(P, poly, n):
    """Triangles (ids into poly) of a planar polygon with the normal n, wound so that they face n"""
    n = np.asarray(n, float)
    u = np.cross(n, [0, 0, 1.0]) if abs(n[2]) < 0.9 else np.cross(n, [1.0, 0, 0])
    u /= np.linalg.norm(u)
    v = np.cross(n, u)
    pts = [Vector((float(np.dot(P[i], u)), float(np.dot(P[i], v)), 0.0)) for i in poly]
    # drop consecutive duplicates (scanfill dislikes them)
    tris = geometry.tessellate_polygon([pts])
    out = []
    for a, b, c in tris:
        pa, pb, pc = P[poly[a]], P[poly[b]], P[poly[c]]
        if np.dot(np.cross(pb - pa, pc - pa), n) < 0:
            b, c = c, b
        out.append((a, b, c))
    return out


class Parts:
    """Collects the cut-out parts and the well geometry for writing"""

    def __init__(self):
        self.nodes = []     # (group, name, P, N, UV, T, origin, basis 3x3 Blender)
        self.well = [[], [], []]   # P, N, T lists

    def add_well(self, P, N, T):
        o = sum(len(p) for p in self.well[0])
        self.well[0].append(np.asarray(P, float))
        self.well[1].append(np.asarray(N, float))
        self.well[2].append(np.asarray(T, np.int64) + o)


def cap_geometry(m, loop, planes, outward, uv_of, flip=False):
    """Flat caps of the loop parts lying on the planes. outward[k] — normal of the cap on plane k facing out of the
    cut part; flip — the other side (recess wall of the remaining skin). Returns P, N, UV, T"""
    polys, free = plane_runs(m.P, loop, planes)
    P, N, UV, T = [], [], [], []
    for k, poly in enumerate(polys):
        if len(poly) < 3:
            continue
        n = np.asarray(outward[k], float) * (-1 if flip else 1)
        tris = tess(m.P, poly, n)
        o = len(P)
        uv = uv_of(poly)
        for v in poly:
            P.append(m.P[v])
            N.append(n)
            UV.append(uv)
        for a, b, c in tris:
            T.append((o + a, o + b, o + c))
    return np.array(P).reshape(-1, 3), np.array(N).reshape(-1, 3), np.array(UV).reshape(-1, 2), np.array(T, np.int64).reshape(-1, 3), free


def frame(origin, along):
    """Node frame (Blender): Y along the hinge towards +Y, X forward across it, Z up"""
    ay = np.asarray(along, float)
    ay = ay / np.linalg.norm(ay)
    if ay[1] < 0:
        ay = -ay
    ax = np.array([1.0, 0, 0]) - ay * ay[0]
    ax /= np.linalg.norm(ax)
    az = np.cross(ax, ay)
    return np.asarray(origin, float), np.stack([ax, ay, az], 1)


def frame_x(origin, along):
    """Bay door frame (bay_doors.py): X forward along the hinge, Z up, Y = Z x X"""
    ax = np.asarray(along, float)
    ax = ax / np.linalg.norm(ax)
    if ax[0] < 0:
        ax = -ax
    az = np.array([0, 0, 1.0]) - ax * ax[2]
    az /= np.linalg.norm(az)
    ay = np.cross(az, ax)
    return np.asarray(origin, float), np.stack([ax, ay, az], 1)


def edges_at(m, y, xm):
    """Leading and trailing edge of the wing on the section y: the solid run of the silhouette around xm"""
    def inside(x):
        return len(m.column(x, y)) > 0
    if not inside(xm):
        raise SystemExit("no wing at y=%.3f x=%.3f" % (y, xm))
    le = xm
    while le < 0.6 and inside(le + 0.001):
        le += 0.001
    te = xm
    while te > -0.6 and inside(te - 0.001):
        te -= 0.001
    return le, te


def cut_section(m, parts, key, kind, side, seg, name):
    """Cut one slat or flap out of the wing (see module doc); the cut triangles leave m"""
    y0, y1, xm0, xm1 = seg
    st = []
    for y, xm in ((y0, xm0), (y1, xm1)):
        le, te = edges_at(m, y * side, xm)
        c = le - te
        xh = te + FLAP_C * c if kind == "flap" else le - SLAT_C * c
        st.append((y * side, le, te, xh))
    (ya, lea, tea, xha), (yb, leb, teb, xhb) = st
    d = np.array([xhb - xha, yb - ya, 0.0])
    nh = np.array([d[1], -d[0], 0.0]) / np.linalg.norm(d)
    if (nh[0] < 0) == (kind == "flap"):     # out of a flap = forward, out of a slat = aft
        nh = -nh
    ph = np.array([xha, ya, 0.0])
    out_in = np.array([0.0, -side, 0.0])     # towards the fuselage
    out_out = np.array([0.0, side, 0.0])
    planes = [(nh, float(np.dot(nh, ph))), (out_in, float(np.dot(out_in, [0, ya, 0]))),
              (out_out, float(np.dot(out_out, [0, yb, 0])))]
    edge_a = tea if kind == "flap" else lea
    edge_b = teb if kind == "flap" else leb
    # wing thickness range along the section
    zs = []
    for t in np.linspace(0, 1, 7):
        y = ya + (yb - ya) * t
        xc = ((xha + edge_a) + ((xhb + edge_b) - (xha + edge_a)) * t) * 0.5
        h = m.column(xc, y)
        if len(h) >= 2:
            zs += [h[0][0], h[1][0]]
    z0, z1 = min(zs), max(zs)
    xs = [lea, leb, tea, teb]
    box = (min(xs) - 0.02, max(xs) + 0.02, min(ya, yb) - 0.02, max(ya, yb) + 0.02, z0 - 0.02, z1 + 0.02)
    for n, dd in planes:
        m.split(n, dd, box)
    # seeds: the skin hit at the middle of the section, top and bottom
    ym = (ya + yb) * 0.5
    xc = ((xha + xhb) * 0.5 + (edge_a + edge_b) * 0.5) * 0.5
    h = m.column(xc, ym)
    if len(h) < 2:
        raise SystemExit("%s: no skin at the middle" % name)
    if len(h) > 2:
        print("  %s: %d surfaces on the middle ray, taking the top two" % (name, len(h)))
    cen = m.P[m.T].mean(1)
    mask = (m.prim == 0) & (cen[:, 2] > z0 - 0.01) & (cen[:, 2] < z1 + 0.01)
    for n, dd in planes:
        mask &= cen @ n - dd < 0
    if kind == "flap":
        mask &= cen[:, 0] > min(tea, teb) - 0.01
    else:
        mask &= cen[:, 0] < max(lea, leb) + 0.01
    sel = m.region(mask, [h[0][1], h[1][1]])
    lps = m.loops(sel)
    outward = [p[0] for p in planes]

    def uv_top(poly):
        return skin_uv(m, poly)
    capP, capN, capUV, capT = [], [], [], []
    freeall = 0
    ncap = 0
    for lp in lps:
        cp, cn, cu, ct, free = cap_geometry(m, lp, planes, outward, uv_top)
        freeall += free
        capT.append(ct + ncap)
        ncap += len(cp)
        capP.append(cp)
        capN.append(cn)
        capUV.append(cu)
        wp, wn, wu, wt, _ = cap_geometry(m, lp, planes, outward, uv_top, flip=True)
        parts.add_well(wp, wn, wt)
    # hinge axis: flap — lower corners of the hinge plane (its top opens a slot when it goes down), slat — upper
    on_h = [v for lp in lps for v in lp if abs(np.dot(m.P[v], planes[0][0]) - planes[0][1]) < 2e-6]
    if not on_h:
        raise SystemExit("%s: no hinge edge" % name)
    Ph = m.P[on_h]
    ends = []
    for yy in (ya, yb):
        c = Ph[np.abs(Ph[:, 1] - yy) < 2e-6]
        if len(c) == 0:
            c = Ph[np.argsort(np.abs(Ph[:, 1] - yy))[:2]]
        ends.append(c[np.argmin(c[:, 2])] if kind == "flap" else c[np.argmax(c[:, 2])])
    origin, R = frame((ends[0] + ends[1]) * 0.5, ends[1] - ends[0])
    P, N, UV, T = compact_mesh(m, sel)
    o = len(P)
    nsk = len(T)
    P = np.vstack([P] + capP)
    N = np.vstack([N] + capN)
    UV = np.vstack([UV] + capUV)
    T = np.vstack([T] + [t + o for t in capT])
    parts.nodes.append(("wing_mech", name, P, N, UV, T, origin, R))
    m.T = m.T[~sel]
    m.prim = m.prim[~sel]
    print("  %s: %d tris + %d cap, %d loops, %d loose boundary verts, z %.4f..%.4f, hinge x %.3f..%.3f"
          % (name, nsk, len(T) - nsk, len(lps), freeall, z0, z1, xha, xhb))


def cut_bay(m, parts, key):
    """«Kit»: belly skin inside the bay -> two doors, a dark box up into the fuselage instead"""
    X0, X1, W, D = BAYS[key]
    xc = (X0 + X1) * 0.5
    h = m.column(xc, 0.0)
    zb = h[-1][0]
    tops = [m.column(x, y)[0][0] for x in (X0, X1) for y in (-W, W)]
    print("  bay: belly z %.4f, ceiling %.4f, top skin over the corners %.4f" % (zb, zb + D, min(tops)))
    planes = [(np.array([-1.0, 0, 0]), -X0), (np.array([1.0, 0, 0]), X1), (np.array([0, 1.0, 0]), W),
              (np.array([0, -1.0, 0]), W)]
    box = (X0 - 0.03, X1 + 0.03, -W - 0.03, W + 0.03, zb - 0.03, zb + 0.02)
    for n, dd in planes + [(np.array([0, 1.0, 0]), 0.0)]:
        m.split(n, dd, box)
    h = m.column(xc + 0.003, 0.004)
    hr = m.column(xc + 0.003, -0.004)
    cen = m.P[m.T].mean(1)
    nz = np.cross(m.P[m.T[:, 1]] - m.P[m.T[:, 0]], m.P[m.T[:, 2]] - m.P[m.T[:, 0]])[:, 2]
    mask = (m.prim == 0) & (cen[:, 2] < zb + 0.015)
    for n, dd in planes:
        mask &= cen @ n - dd < 0
    sel = m.region(mask, [h[-1][1], hr[-1][1]])
    lps = m.loops(sel)
    print("  bay: %d belly tris, %d hole loops %s" % (int(sel.sum()), len(lps), [len(lp) for lp in lps]))
    loop = max(lps, key=len)
    for lp in lps:
        if lp is not loop:
            print("    extra loop", len(lp), m.P[lp].min(0).round(4), m.P[lp].max(0).round(4))
    zc = zb + D
    # box walls: from the hole edge straight up to the ceiling, facing into the bay
    WP, WN, WT = [], [], []
    ctr = np.array([xc, 0.0, zb + D * 0.5])
    for i in range(len(loop)):
        a, b = m.P[loop[i]], m.P[loop[(i + 1) % len(loop)]]
        q = [a, b, np.array([b[0], b[1], zc]), np.array([a[0], a[1], zc])]
        n = np.cross(q[1] - q[0], q[3] - q[0])
        if np.linalg.norm(n) < 1e-12:
            continue
        n /= np.linalg.norm(n)
        o = len(WP)
        if np.dot(n, ctr - (a + b) * 0.5) < 0:
            n = -n
            WT += [(o, o + 3, o + 2), (o, o + 2, o + 1)]
        else:
            WT += [(o, o + 1, o + 2), (o, o + 2, o + 3)]
        WP += q
        WN += [n] * 4
    ring = np.array([[m.P[v][0], m.P[v][1], zc] for v in loop])
    tris = tess(ring, list(range(len(ring))), np.array([0, 0, -1.0]))
    o = len(WP)
    WP += list(ring)
    WN += [np.array([0, 0, -1.0])] * len(ring)
    WT += [(o + a, o + b, o + c) for a, b, c in tris]
    parts.add_well(np.array(WP), np.array(WN), np.array(WT))
    # doors: the belly skin of each half, with an inner face DOOR_T above and a rim
    for side, nm in ((1, "bay_l"), (-1, "bay_r")):
        half = sel & (cen[:, 1] * side > 0)
        P, N, UV, T = compact_mesh(m, half)
        sub = Mesh(P, N, UV, T, np.zeros(len(T), int))
        dl = max(sub.loops(np.ones(len(T), bool)), key=len)
        n0 = len(P)
        allP = np.vstack([P, P + np.array([0, 0, DOOR_T])])
        allN = np.vstack([N, -N])
        allUV = np.vstack([UV, UV])
        rim = []
        for i in range(len(dl)):
            a, b = dl[i], dl[(i + 1) % len(dl)]
            rim += [(b, a, a + n0), (b, a + n0, b + n0)]
        allT = np.vstack([T, T[:, ::-1] + n0, np.array(rim, np.int64)])
        Pout = sub.P[dl]
        hinge = Pout[np.abs(np.abs(Pout[:, 1]) - W) < 2e-6]
        a, b = hinge[np.argmin(hinge[:, 0])], hinge[np.argmax(hinge[:, 0])]
        origin, R = frame_x((a + b) * 0.5, b - a)
        parts.nodes.append(("bay_doors", nm, allP, allN, allUV, allT, origin, R))
    m.T = m.T[~sel]
    m.prim = m.prim[~sel]


def close_box(m, box):
    """S11-10: delete everything baked into the underside inside the vertical prism x0..x1, y0..y1 between z0 and z1
    (Blender axes) — an open bay or well with its hanging door — and close the hole with a smooth cover: a Coons patch
    through the cut edges on the four sides, in the usual skin colour of its edge (skin_uv), facing down."""
    x0, x1, y0, y1, z0, z1 = box
    planes = [(np.array([-1.0, 0, 0]), -x0), (np.array([1.0, 0, 0]), x1), (np.array([0, -1.0, 0]), -y0),
              (np.array([0, 1.0, 0]), y1)]
    lim = (x0 - 0.02, x1 + 0.02, y0 - 0.02, y1 + 0.02, z0 - 0.01, z1 + 0.01)
    for n, d in planes:
        m.split(n, d, lim)
    cen = m.P[m.T].mean(1)
    sel = ((m.prim == 0) & (cen[:, 0] > x0) & (cen[:, 0] < x1) & (cen[:, 1] > y0) & (cen[:, 1] < y1)
           & (cen[:, 2] > z0) & (cen[:, 2] < z1))
    lps = m.loops(sel)
    loop = max(lps, key=len)
    L = m.P[loop]
    for lp in lps:
        if lp is not loop:
            print("    extra loop", len(lp), m.P[lp].min(0).round(4), m.P[lp].max(0).round(4))
    print("  close %s: %d tris, %d hole loops %s" % (box, int(sel.sum()), len(lps), [len(lp) for lp in lps]))

    def side(axis, val):
        """z along one side of the hole, as a function of the other coordinate"""
        on = np.abs(L[:, axis] - val) < 2e-6
        q = L[on]
        o = 1 - axis
        k = np.argsort(q[:, o])
        return q[k, o], q[k, 2]
    sx0, sx1, sy0, sy1 = side(0, x0), side(0, x1), side(1, y0), side(1, y1)

    def zc(x, y):
        u, v = (x - x0) / (x1 - x0), (y - y0) / (y1 - y0)
        zW, zE = np.interp(y, *sx0), np.interp(y, *sx1)
        zS, zN = np.interp(x, *sy0), np.interp(x, *sy1)
        c00, c10 = np.interp(y0, *sx0), np.interp(y0, *sx1)
        c01, c11 = np.interp(y1, *sx0), np.interp(y1, *sx1)
        return ((1 - v) * zS + v * zN + (1 - u) * zW + u * zE
                - ((1 - u) * (1 - v) * c00 + u * (1 - v) * c10 + (1 - u) * v * c01 + u * v * c11))
    pts = [Vector((p[0], p[1])) for p in L]
    inner = []
    nx, ny = max(3, int((x1 - x0) / 0.004)), max(3, int((y1 - y0) / 0.004))
    for i in range(1, nx):
        for j in range(1, ny):
            x, y = x0 + (x1 - x0) * i / nx, y0 + (y1 - y0) * j / ny
            inner.append((x, y, zc(x, y)))
            pts.append(Vector((x, y)))
    r = geometry.delaunay_2d_cdt(pts, [], [list(range(len(loop)))], 1, 1e-7)
    src = np.vstack([L, np.array(inner).reshape(-1, 3)])
    # coincident input points come out merged: take every output point from its first input point
    P = np.array([src[ids[0]] if len(ids) else (v[0], v[1], zc(v[0], v[1])) for v, ids in zip(r[0], r[3])])
    T = []
    for f in r[2]:
        for k in range(1, len(f) - 1):
            a, b, c = f[0], f[k], f[k + 1]
            if np.cross(P[b] - P[a], P[c] - P[a])[2] > 0:     # face down, out of the nacelle
                b, c = c, b
            T.append((a, b, c))
    T = np.array(T, np.int64)
    N = np.zeros_like(P)
    for a, b, c in T:
        fn = np.cross(P[b] - P[a], P[c] - P[a])
        N[[a, b, c]] += fn
    N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-12)
    uv = skin_uv(m, loop)
    m.T = m.T[~sel]
    m.prim = m.prim[~sel]
    base = len(m.P)
    m.P = np.vstack([m.P, P])
    m.N = np.vstack([m.N, N])
    m.UV = np.vstack([m.UV, np.repeat(uv[None], len(P), 0)])
    m.T = np.vstack([m.T, T + base])
    m.prim = np.concatenate([m.prim, np.zeros(len(T), int)])


# ---------- write ----------
def gc_accessors(g):
    """Drop accessors no mesh uses any more, then the buffer views behind them"""
    used = set()
    for me in g.j["meshes"]:
        for p in me["primitives"]:
            used.update(p["attributes"].values())
            if "indices" in p:
                used.add(p["indices"])
    remap, acc = {}, []
    for i, a in enumerate(g.j["accessors"]):
        if i in used:
            remap[i] = len(acc)
            acc.append(a)
    g.j["accessors"] = acc
    for me in g.j["meshes"]:
        for p in me["primitives"]:
            p["attributes"] = {k: remap[v] for k, v in p["attributes"].items()}
            if "indices" in p:
                p["indices"] = remap[p["indices"]]
    g.compact()


def quat(Rb):
    """glTF rotation (x, y, z, w) of a Blender-axes rotation matrix"""
    C = np.array([[1.0, 0, 0], [0, 0, 1.0], [0, -1.0, 0]])
    R = C @ Rb @ C.T
    w = np.sqrt(max(0.0, 1 + R[0, 0] + R[1, 1] + R[2, 2])) / 2
    x = np.sqrt(max(0.0, 1 + R[0, 0] - R[1, 1] - R[2, 2])) / 2
    y = np.sqrt(max(0.0, 1 - R[0, 0] + R[1, 1] - R[2, 2])) / 2
    z = np.sqrt(max(0.0, 1 - R[0, 0] - R[1, 1] + R[2, 2])) / 2
    x = np.copysign(x, R[2, 1] - R[1, 2])
    y = np.copysign(y, R[0, 2] - R[2, 0])
    z = np.copysign(z, R[1, 0] - R[0, 1])
    q = np.array([x, y, z, w])
    return [float(v) for v in q / np.linalg.norm(q)]


def _idx(g, T):
    flat = np.asarray(T).reshape(-1)
    idx = flat.astype(np.uint32) if flat.max() >= 65535 else flat.astype(np.uint16)
    return _acc(g, idx, "SCALAR", 5125 if idx.dtype == np.uint32 else 5123, 34963)


def save(g, m, shared, parts, dst):
    """Main mesh with the new vertex arrays (glass too when it shares them), the well primitive, the part nodes"""
    prims = g.j["meshes"][0]["primitives"]
    p0 = prim_dict(g, m.P, m.N, m.UV, m.T[m.prim == 0], prims[0].get("material"))
    prims[0]["attributes"] = p0["attributes"]
    prims[0]["indices"] = p0["indices"]
    if shared:
        for pi in range(1, len(prims)):
            prims[pi]["attributes"] = dict(p0["attributes"])
            prims[pi]["indices"] = _idx(g, m.T[m.prim == pi])
    mats = g.j["materials"]
    mats.append({"name": "mech_well", "pbrMetallicRoughness": {"baseColorFactor": list(WELL_COL), "metallicFactor": 0.0,
                                                               "roughnessFactor": 0.92}})
    if parts.well[0]:
        prims.append(prim_dict(g, np.vstack(parts.well[0]), np.vstack(parts.well[1]), None, np.vstack(parts.well[2]),
                               len(mats) - 1))
    skin_mat = prims[0].get("material")
    groups = {}
    for grp, name, P, N, UV, T, origin, R in parts.nodes:
        local = (P - origin) @ R
        ln = N @ R
        g.j["meshes"].append({"name": name, "primitives": [prim_dict(g, local, ln, UV, T, skin_mat)]})
        g.j["nodes"].append({"name": name, "mesh": len(g.j["meshes"]) - 1,
                             "translation": [float(v) for v in to_g(origin[None])[0]], "rotation": quat(R)})
        groups.setdefault(grp, []).append(len(g.j["nodes"]) - 1)
    for grp, kids in groups.items():
        g.j["nodes"].append({"name": grp, "children": kids})
        g.j["scenes"][g.j.get("scene", 0)]["nodes"].append(len(g.j["nodes"]) - 1)
    gc_accessors(g)
    g.save(dst)


def main() -> int:
    ap = argparse.ArgumentParser(description="Cut slats, flaps and the bomb bay out of a hangar model (S11-02/10/11).")
    ap.add_argument("src", help="hangar model BEFORE the cut (e.g. git show <rev>:game/models/hangar/<name>.glb)")
    ap.add_argument("key", choices=sorted(SPANS), help="plane: fighter_1 … bomber_2")
    ap.add_argument("dst", help="output GLB (not the input)")
    ap.add_argument("--close", action="append", default=[], metavar="x0,x1,y0,y1,z0,z1",
                    help="delete what is baked into the underside in this box (Blender axes) and cover the hole")
    a = ap.parse_args()
    if os.path.abspath(a.src) == os.path.abspath(a.dst):
        raise SystemExit("input and output must differ")
    g, m, shared = load(a.src)
    load_tex(g)
    if any(n.get("name") in ("wing_mech", "bay_doors") for n in g.j["nodes"]):
        raise SystemExit("%s already has cut-out parts: pass the model from before the cut" % a.src)
    print("%s: %d verts, %d tris, glass shares vertices: %s" % (a.key, len(m.P), len(m.T), shared))
    parts = Parts()
    for box in a.close:
        close_box(m, [float(v) for v in box.split(",")])
    for kind in ("slat", "flap"):
        for side, s in ((1, "l"), (-1, "r")):
            for i, seg in enumerate(SPANS[a.key][kind]):
                cut_section(m, parts, a.key, kind, side, seg, "%s_%s%s" % (kind, s, "" if i == 0 else str(i + 1)))
    if a.key in BAYS:
        cut_bay(m, parts, a.key)
    save(g, m, shared, parts, a.dst)
    print("saved %s: %d tris in the skin, %d parts" % (a.dst, int((m.prim == 0).sum()), len(parts.nodes)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
