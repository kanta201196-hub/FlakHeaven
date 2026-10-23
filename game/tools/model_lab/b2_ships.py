# Окраска судов каравана «Архипелага» — К-1 балкер и К-2 танкер (замечание Kanta 23.10: «слишком яркая, неестественная»).
# Форма — рецепты e_ship_bulk / e_ship_tanker в biome2_models.py; здесь — запекание цвета на одну текстуру (b2_shore.bake):
# выгоревший приглушённый борт с пятнами подкраски, потёки ржавчины от клюзов и шпигатов, соляная кромка над грязной
# тёмной ватерлинией, подводная часть — приглушённый сурик, тёмная палуба в грязи, грязно-кремовая надстройка с копотью.
# Потом b2lib.finish() → natural(): матовое (roughness ≥ 0,88), металл 0, без чисто белого.
# Надписей, номеров, флагов и знаков нет — мир вымышленный.
import os
import numpy as np
import bpy
import b2lib as L
from b2_shore import bake, unwrap, fbm, vnoise, cell, mix, col, weather

RUST = (0.44, 0.27, 0.16)        # ржавчина: потёки, сколы
RUST_DK = (0.29, 0.18, 0.12)     # сердцевина потёка
ANTIFOUL = (0.34, 0.22, 0.19)    # подводная часть — сурик, выгоревший
BOOT = (0.14, 0.14, 0.13)        # ватерлиния — тёмная, в мазуте
ALGAE = (0.20, 0.22, 0.16)       # налёт у воды
SALT = (0.64, 0.63, 0.58)        # соляная кромка
DIRT = (0.22, 0.21, 0.19)        # грязь на палубе
SOOT = (0.12, 0.115, 0.11)       # копоть трубы
METAL = (0.30, 0.30, 0.28)       # механизмы на палубе, лебёдки
WIN = (0.10, 0.12, 0.13)


def _streaks(P, srcs, seed):
    """Потёки вниз от точек srcs = [(x, z, полуширина, длина, сила)]: сужаются и бледнеют книзу, край рваный."""
    s = np.zeros(len(P))
    x, z = P[:, 0], P[:, 2]
    wob = vnoise(P * np.array([0.3, 0.0, 1.0]), 0.7, seed) - 0.5
    for xs, zs, w, ln, k in srcs:
        below = zs - z
        near = np.abs(x - xs) < w * 3
        if not near.any():
            continue
        t = np.clip(below / ln, 0, 1)
        ww = w * (1.0 - 0.55 * t) * (0.8 + 0.4 * wob)
        d = (x - xs + 0.35 * w * np.sin(z * 1.7 + xs)) / np.maximum(ww, 1e-3)
        v = np.exp(-d * d * 1.6) * (below > -w * 0.4) * (1 - t) ** 0.8 * k
        s = np.maximum(s, np.where(near, v, 0))
    n = vnoise(P * np.array([2.5, 2.5, 0.25]), 1.0, seed + 1)      # волокна потёка вдоль вертикали
    return np.clip(s * (0.6 + 0.6 * n), 0, 1)


def hull_paint(P, N, hull, z_deck, boot, salt_h, streak_src, seed, patch_x=7.0):
    """Борт: выгоревшая краска (светлее к палубе), пятна подкраски, сколы, потёки ржавчины; ниже — ватерлиния и сурик."""
    n = len(P)
    z = P[:, 2]
    c = col(hull, n)
    fade = np.clip(z / max(z_deck, 1e-3), 0, 1)
    c = c * (0.93 + 0.12 * fade)[:, None]                             # верх борта выгорел сильнее
    pi = np.floor(P[:, 0] / patch_x + cell(np.floor(z / 2.2), np.floor(z / 2.2), seed) * 0.6)
    patch = cell(pi, np.floor(z / 2.2) + 50, seed + 1)
    c = c * (1 + 0.07 * (patch - 0.5) * 2 * (patch > 0.55))[:, None]   # пятна подкраски другим тоном
    c = weather(c, P, N, seed=seed + 2, stain=0.10, grain=0.05, streak=0.10, grime=0.0, dust=0.0)
    chip = np.clip((fbm(P, 1.4, 4, seed + 3) - 0.68) * 5, 0, 1)
    c = mix(c, col(RUST, n), 0.6 * chip)
    st = _streaks(P, streak_src, seed + 4) * np.clip(1 - np.abs(N[:, 2]) * 1.6, 0, 1)
    c = mix(c, col(RUST, n), st)
    c = mix(c, col(RUST_DK, n), 0.7 * np.clip(st * 1.6 - 0.5, 0, 1))
    return waterline(c, P, boot, salt_h, seed + 5)


def waterline(c, P, boot, salt_h, seed):
    """boot = (низ, верх) полосы ватерлинии, м. Над ней — рваная соляная кромка, ниже — сурик в налёте."""
    n = len(P)
    z = P[:, 2]
    lo, hi = boot
    edge = hi + 0.12 * (vnoise(P * np.array([1, 1, 0]), 0.45, seed) - 0.5) * 2 * (hi - lo)
    # соляная кромка: тонкая светлая полоса, рваная, бледнеет кверху
    s = np.clip((z - edge) / max(salt_h, 1e-3), 0, 1)
    sm = (z > edge) * (1 - s) ** 1.5 * np.clip((fbm(P * np.array([1, 1, 2.5]), 0.9, 3, seed + 1) - 0.3) * 2.2, 0, 1)
    c = mix(c, col(SALT, n), 0.7 * sm)
    # ватерлиния: тёмная, в мазуте и налёте
    b = col(BOOT, n) * (0.85 + 0.3 * fbm(P, 0.7, 3, seed + 2))[:, None]
    b = mix(b, col(ALGAE, n), 0.45 * np.clip((fbm(P, 0.5, 3, seed + 3) - 0.4) * 3, 0, 1))
    c = np.where((z <= edge)[:, None], b, c)
    # подводная часть: сурик, темнее у ватерлинии, в водорослях
    a = col(ANTIFOUL, n) * (0.9 + 0.15 * fbm(P, 0.3, 3, seed + 4))[:, None]
    a = mix(a, col(ALGAE, n), 0.35 * np.clip((lo + 0.8 - z) / 0.8, 0, 1) * np.clip((fbm(P, 0.8, 3, seed + 5) - 0.35) * 2.5, 0, 1))
    return np.where((z < lo)[:, None], a, c)


def deck_paint(P, N, deck, seed):
    """Палуба: тёмная краска, протёртая, в грязи и ржавых пятнах, у комингсов и надстройки темнее."""
    n = len(P)
    c = col(deck, n) * (0.9 + 0.2 * fbm(P, 0.25, 3, seed))[:, None]
    c = mix(c, col(DIRT, n), 0.65 * np.clip((fbm(P, 0.45, 4, seed + 1) - 0.35) * 2.2, 0, 1))
    c = mix(c, col(RUST, n), 0.5 * np.clip((fbm(P, 0.9, 4, seed + 2) - 0.62) * 4, 0, 1))
    return c * (1 + 0.06 * (vnoise(P, 3.0, seed + 3) - 0.5))[:, None]


def super_paint(P, N, cream, z0, seed, soot_pts=()):
    """Надстройка: грязно-кремовая, в потёках под окнами, грязь снизу, ржавые потёки, копоть у трубы."""
    n = len(P)
    c = col(cream, n) * (0.94 + 0.1 * fbm(P, 0.3, 3, seed))[:, None]
    c = weather(c, P, N, seed=seed + 1, stain=0.12, grain=0.05, streak=0.28, grime_h=1.6, grime=0.45, dust=0.0, z0=z0)
    wall = np.clip(1 - np.abs(N[:, 2]) * 1.4, 0, 1)
    rs = np.clip((vnoise(P * np.array([1.6, 1.6, 0.12]), 1.0, seed + 2) - 0.72) * 4, 0, 1) * wall
    c = mix(c, col(RUST, n), 0.45 * rs)
    for pt, r in soot_pts:
        d = np.linalg.norm(P - np.array(pt), axis=1) / r
        c = mix(c, col(SOOT, n), 0.6 * np.clip(1.2 - d, 0, 1) * (0.5 + 0.5 * fbm(P, 1.0, 3, seed + 3)))
    return c


def painted(base_rgb, P, N, seed, rust=0.5, z0=0.0):
    """Мелкие крашеные детали (краны, шлюпки, трубы, леера): выгоревший цвет, сколы, грязь снизу."""
    n = len(P)
    c = col(base_rgb, n)
    c = weather(c, P, N, seed=seed, stain=0.12, grain=0.06, streak=0.15, grime_h=1.0, grime=0.3, dust=0.0, z0=z0)
    return mix(c, col(RUST, n), rust * np.clip((fbm(P, 1.6, 4, seed + 1) - 0.62) * 4, 0, 1))


def shade_ship(roles, pal, seed):
    """shade для b2_shore.bake: роль детали — по имени материала (roles), цвета — pal.
    pal: hull, deck, cream, z_deck, boot=(низ, верх), salt, streaks=[...], z_house, soot=[...], + цвета мелких ролей."""
    def f(base, P, N, M, names):
        out = base.copy()
        rl = np.array([roles.get(nm, roles.get('*', 'metal')) for nm in names])[M]
        up = N[:, 2]
        z = P[:, 2]
        # горизонтальный верх «борта» выше ватерлинии — палуба; вертикальные стенки палубы и бака — борт
        rl = np.where((rl == 'hull') & (up > 0.7) & (z > pal['boot'][1] + 0.5), 'deck', rl)
        rl = np.where((rl == 'deck') & (np.abs(up) < 0.5), 'hull', rl)
        rl = np.where((rl == 'bottom') & (z > pal['boot'][0]), 'hull', rl)   # «красный» выше ватерлинии — тоже борт
        for r in np.unique(rl):
            sel = rl == r
            p, nn = P[sel], N[sel]
            if r in ('hull', 'bottom'):
                out[sel] = hull_paint(p, nn, pal['hull'], pal['z_deck'], pal['boot'], pal['salt'], pal['streaks'], seed)
            elif r == 'deck':
                out[sel] = deck_paint(p, nn, pal['deck'], seed + 10)
            elif r == 'super':
                out[sel] = super_paint(p, nn, pal['cream'], pal['z_house'], seed + 20, pal.get('soot', ()))
            elif r == 'win':
                out[sel] = col(WIN, len(p))
            elif r == 'soot':
                out[sel] = col(SOOT, len(p)) * (0.9 + 0.2 * fbm(p, 1.0, 2, seed + 30))[:, None]
            elif r == 'metal':
                l = np.clip(base[sel] @ np.array([0.3, 0.59, 0.11]), 0.08, 0.5)
                c = col(METAL, len(p)) * (0.55 + 0.9 * l)[:, None]
                out[sel] = painted(np.clip(c.mean(0), 0, 1), p, nn, seed + 40, rust=0.4)
            else:
                out[sel] = painted(pal[r], p, nn, seed + 50 + len(r), rust=pal.get('rust_' + r, 0.4))
        return out
    return f


def unwrap_ship(ob, z_low, hull_mats=(), k=0.2):
    """Развёртка 'paint' с плотностью по видимости: грани целиком под водой, смотрящие вниз (днище, изнанка палубы)
    и горизонтальные крышки корпуса (под настилом палубы) в k раз мельче — их в игре не видно,
    а борт и палуба получают больше текселей (потёки, кромка, ватерлиния)."""
    import bmesh
    from mathutils import Vector
    hidx = {i for i, m in enumerate(ob.data.materials) if m and m.name in hull_mats}
    unwrap(ob, 0.003, 60)
    bm = bmesh.new(); bm.from_mesh(ob.data)
    uvl = bm.loops.layers.uv['paint']
    n = 0
    for f in bm.faces:
        if (max(v.co.z for v in f.verts) < z_low - 0.3 or f.normal.z < -0.5
                or (f.material_index in hidx and f.normal.z > 0.7)):
            c = sum((l[uvl].uv for l in f.loops), Vector((0.0, 0.0))) / len(f.loops)
            for l in f.loops:
                l[uvl].uv = c + (l[uvl].uv - c) * k
            n += 1
    bm.to_mesh(ob.data); bm.free()
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.select_all(action='SELECT')
    bpy.ops.uv.pack_islands(rotate=True, margin=0.003)
    bpy.ops.object.mode_set(mode='OBJECT')
    print("UNWRAP", ob.name, "граней мельче:", n, "из", len(ob.data.polygons))


def paint_finish(objs, out, roles, pal, seed, target, size=2048, maxtex=1024):
    """Упростить, склеить, запечь окраску и записать GLB (b2lib.finish: длина 1, glTF +Y вверх, ватерлиния z = 0)."""
    objs = [o for o in objs if o.name in bpy.data.objects and len(o.data.polygons)]
    L.budget(objs, int(target * 1.1))
    name = os.path.basename(out)[len('fh_battle_'):-len('.glb')] if os.path.basename(out).startswith('fh_battle_') else 'ship'
    ob = L.join(objs, name)
    L.weld([ob], 1e-5)
    unwrap_ship(ob, pal['boot'][0], pal.get('hidden_caps', ()))
    bake(ob, shade_ship(roles, pal, seed), size=size, name=name, rough=0.9)
    ob = L.finish([ob], out, target=target, maxtex=maxtex)
    bl = os.environ.get('FH_BLEND_DIR')   # исходник .blend (в файлы проекта, не в репозиторий)
    if bl:
        os.makedirs(bl, exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(bl, name + '.blend'), compress=True)
    return ob
