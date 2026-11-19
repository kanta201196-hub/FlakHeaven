"""3.5-s19 recheck (Kanta 19.11 on «Кит» 1 = bomber_t1: «проверь модель логически, нет ли чего-то лишнего?
пулемётов там каких-то?»). The Meshy hull carries two bare barrels with no mount and no gunner behind them: a chin
gun hanging under the nose (x 0.438…0.48, y −0.09…−0.08, on the centre line), where the bombardier's ball-mount gun
in the glazed nose (HangarCockpit) already covers the front, and a belly gun just aft of it (x 0.322…0.353, angled
down under the cockpit). Both are loose pieces of the body primitive, so dropping them leaves no hole. The tail gun,
the twin guns of the dorsal turret and the ventral guns aft of the bomb bay stay: each has its gunner's station.

glb_io: only the body's triangle list changes; vertices, UV and the embedded images stay byte for byte.
Run from the repo root:
  python3 game/tools/blender/kit1_fix.py game/models/hangar/fh_hangar_bomber_t1.glb <out.glb>
then rebake the battle model from it (battle_bake.py)."""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glb_io  # noqa: E402

# the chin gun's box and the belly gun's box (glTF axes: nose +X, up +Y), measured on the hangar model
CHIN_GUN = ((0.434, -0.094, -0.004), (0.484, -0.076, 0.004))
BELLY_GUN = ((0.318, -0.118, -0.004), (0.356, -0.08, 0.004))


def drop_chin_gun(src, dst):
    """Removes every connected piece of the body lying wholly inside CHIN_GUN or BELLY_GUN"""
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import connected_components
    g = glb_io.load(src)
    prims = g.j["meshes"][0]["primitives"]
    names = [g.j["materials"][p["material"]]["name"] for p in prims]
    bi = next(i for i, n in enumerate(names) if n.endswith("_body"))
    bp, bt = g.mesh_world(0, bi)
    # pieces: triangles joined through vertices at the same place (the Meshy mesh splits vertices at UV seams)
    key = np.round(bp / 1e-5).astype(np.int64)
    inv = np.unique(key, axis=0, return_inverse=True)[1].ravel()
    a = np.concatenate([bt[:, 0], bt[:, 1], bt[:, 2]])
    b = np.concatenate([bt[:, 1], bt[:, 2], bt[:, 0]])
    n = int(inv.max()) + 1
    lab = connected_components(coo_matrix((np.ones(len(a)), (inv[a], inv[b])), shape=(n, n)), directed=False)[1]
    tl = lab[inv[bt[:, 0]]]
    drop = np.zeros(len(bt), bool)
    for box in (CHIN_GUN, BELLY_GUN):
        lo, hi = np.array(box[0]), np.array(box[1])
        for piece in np.unique(tl):
            vs = bp[np.unique(bt[tl == piece])]
            if (vs.min(0) >= lo).all() and (vs.max(0) <= hi).all():
                drop |= tl == piece
    g.set_indices(0, bi, bt[~drop])
    g.save(dst)
    print("kit1_fix: chin and belly guns, %d triangles in %d pieces removed"
          % (int(drop.sum()), len(np.unique(tl[drop]))))


if __name__ == "__main__":
    drop_chin_gun(sys.argv[1], sys.argv[2])
