"""Чтение и перезапись GLB без Blender: геометрия меняется, картинки остаются байт в байт.
Зачем: у моделей Meshy текстуры извлекает Godot (`embedded_image_handling=1`), а окраска (splinter_camo.py)
лежит только в извлечённых *_0.png / *_Image_0.jpg. Если картинка в GLB не изменилась (тот же md5 пикселей),
Godot извлечённый файл не перезаписывает — окраска сохраняется. Экспорт из Blender кодирует картинки заново,
поэтому для правки геометрии готовой модели лучше этот модуль.

load(path) -> Glb; g.mesh_world(mesh_i, prim_i) -> (позиции в мире модели, индексы треугольников);
g.set_indices(mesh_i, prim_i, новые индексы); g.save(path)."""
import json
import struct
import numpy as np

CT = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def _quat_mat(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def _node_mat(n):
    m = np.eye(4)
    if "matrix" in n:
        return np.array(n["matrix"]).reshape(4, 4).T
    r = _quat_mat(n.get("rotation", [0, 0, 0, 1]))
    s = np.diag(n.get("scale", [1, 1, 1]))
    m[:3, :3] = r @ s
    m[:3, 3] = n.get("translation", [0, 0, 0])
    return m


class Glb:
    def __init__(self, path):
        d = open(path, "rb").read()
        assert d[:4] == b"glTF"
        jl = struct.unpack("<I", d[12:16])[0]
        self.j = json.loads(d[20:20 + jl])
        o = 20 + jl
        bl = struct.unpack("<I", d[o:o + 4])[0]
        self.bin = bytearray(d[o + 8:o + 8 + bl])

    def accessor(self, i):
        a = self.j["accessors"][i]
        bv = self.j["bufferViews"][a["bufferView"]]
        dt = CT[a["componentType"]]
        nc = NC[a["type"]]
        off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        stride = bv.get("byteStride", 0)
        isz = np.dtype(dt).itemsize * nc
        if stride and stride != isz:
            raw = np.frombuffer(bytes(self.bin[off:off + stride * a["count"]]), np.uint8).reshape(a["count"], stride)
            return raw[:, :isz].copy().view(dt).reshape(a["count"], nc)
        return np.frombuffer(bytes(self.bin[off:off + isz * a["count"]]), dt).reshape(a["count"], nc).copy()

    def world_of_mesh(self, mesh_i):
        nodes = self.j["nodes"]
        parent = {}
        for i, n in enumerate(nodes):
            for c in n.get("children", []):
                parent[c] = i
        for i, n in enumerate(nodes):
            if n.get("mesh") == mesh_i:
                m = _node_mat(n)
                k = i
                while k in parent:
                    k = parent[k]
                    m = _node_mat(nodes[k]) @ m
                return m
        return np.eye(4)

    def mesh_world(self, mesh_i=0, prim_i=0):
        p = self.j["meshes"][mesh_i]["primitives"][prim_i]
        pos = self.accessor(p["attributes"]["POSITION"]).astype(np.float64)
        m = self.world_of_mesh(mesh_i)
        w = pos @ m[:3, :3].T + m[:3, 3]
        idx = self.accessor(p["indices"]).reshape(-1, 3).astype(np.int64)
        return w, idx

    def set_indices(self, mesh_i, prim_i, tris):
        """Новые индексы — в конец буфера отдельным bufferView (старые байты остаются, но на них никто не ссылается
        после compact())."""
        p = self.j["meshes"][mesh_i]["primitives"][prim_i]
        a = self.j["accessors"][p["indices"]]
        flat = np.asarray(tris).reshape(-1)
        flat = flat.astype(np.uint16 if flat.max() < 65535 else np.uint32)
        a["componentType"] = 5123 if flat.dtype == np.uint16 else 5125
        a["count"] = int(flat.size)
        a.pop("byteOffset", None)
        a.pop("max", None)
        a.pop("min", None)
        while len(self.bin) % 4:
            self.bin.append(0)
        off = len(self.bin)
        self.bin += flat.tobytes()
        self.j["bufferViews"].append({"buffer": 0, "byteOffset": off, "byteLength": int(flat.nbytes), "target": 34963})
        a["bufferView"] = len(self.j["bufferViews"]) - 1
        self.compact()

    def compact(self):
        """Выкидывает bufferView, на которые никто не ссылается, и упаковывает буфер заново."""
        used = set()
        for a in self.j["accessors"]:
            if "bufferView" in a:
                used.add(a["bufferView"])
        for im in self.j.get("images", []):
            if "bufferView" in im:
                used.add(im["bufferView"])
        old = self.j["bufferViews"]
        remap, nb, newv = {}, bytearray(), []
        for i, bv in enumerate(old):
            if i not in used:
                continue
            while len(nb) % 4:
                nb.append(0)
            o = bv.get("byteOffset", 0)
            chunk = self.bin[o:o + bv["byteLength"]]
            nbv = dict(bv)
            nbv["byteOffset"] = len(nb)
            nb += chunk
            remap[i] = len(newv)
            newv.append(nbv)
        for a in self.j["accessors"]:
            if "bufferView" in a:
                a["bufferView"] = remap[a["bufferView"]]
        for im in self.j.get("images", []):
            if "bufferView" in im:
                im["bufferView"] = remap[im["bufferView"]]
        self.j["bufferViews"] = newv
        self.bin = nb
        self.j["buffers"][0]["byteLength"] = len(nb)

    def save(self, path):
        while len(self.bin) % 4:
            self.bin.append(0)
        js = json.dumps(self.j, separators=(",", ":")).encode()
        while len(js) % 4:
            js += b" "
        total = 12 + 8 + len(js) + 8 + len(self.bin)
        with open(path, "wb") as f:
            f.write(b"glTF" + struct.pack("<II", 2, total))
            f.write(struct.pack("<I", len(js)) + b"JSON" + js)
            f.write(struct.pack("<I", len(self.bin)) + b"BIN\x00" + bytes(self.bin))


def load(path):
    return Glb(path)
