"""Crashed-plane wrecks for the Highland biome: solid hulks on the ground (test 3.5-s4 item 18; layouts — test
3.5-s8, Kanta 19.10: "two more wreck layouts and a helicopter wreck"). Made from one of the game's battle models
("inspired by", no markings): the hull is cut into parts by face position, the parts are thrown about, turned
over and laid on the ground (z = 0), with small debris round them.

Layouts:
  a    — the plane broke up where it fell: nose, wings and tail next to the fuselage, one wing upside down;
  b    — belly landing: the plane in one piece with a broken wing, the tail torn off at the start of the slide
         and lying at the end of the furrow (along -X; the battle scene draws a burnt strip there, terrain3d.gd);
  c    — fuselage broken in two: the front half with one wing, the rear with the tail turned and on its side,
         the other wing torn off and lying apart upside down;
  heli — helicopter on its side, the tail boom broken off, the main rotor blades thrown out (some bent).

Weak-props list (29.10.2026: "the shards are paper-thin; give the panels thickness, torn metal edges, burnt and
sooty paint and a scorched ground patch"): every cut edge is refined and torn (teeth, rips, petals curled off
the surface), the skin gets a real thickness with the torn rim and the burnt-out inside as their own surfaces,
the debris are bent torn plates instead of boxes; the whole wreck (parts, debris, furrow) is one mesh with one
burnt atlas baked by turret_paint (own-colour mode, as vehicle_wreck.py): the battle model's paint faded and
blistered, burnt through to grey skin and pale ash toward the fire, burnt off round every tear, raw metal on the
torn rims, soot plumes, primer and soot inside, a smashed sooty canopy, dust and drifted sand; matte, with a
relief map (dents, blisters, clods). Under it a larger scorched ground patch (tex_lib.scorch: charcoal core with
ash, burnt earth round it, soot fingers, a ragged alpha edge).

Units as the biome models (tools/model_lab/biome_prep.py): standing on z = 0 (Godot y = 0), centred, largest size
in plan = 1 (the furrow in b reaches beyond that, behind) — the game scales it (biome_props.gd, render3d.gd
o_wreck).

Run (bpy 5.x, numpy, scipy, Pillow; ~3 min on 2 threads): python3 plane_wreck.py <battle model.glb> <out.glb>
[seed] [layout]
  b11_wreck_plane   = fh_battle_e_interceptor.glb 3 a
  b11_wreck_plane_b = fh_battle_e_rival.glb 5 b
  b11_wreck_plane_c = fh_battle_attacker_1.glb 8 c
  b11_wreck_heli    = fh_battle_e_helicopter.glb 4 heli"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import bpy, bmesh
from mathutils import Vector, Matrix, Euler, noise

args = [a for a in sys.argv[1:]]
src, dst = args[0], args[1]
seed = int(args[2]) if len(args) > 2 else 3
layout = args[3] if len(args) > 3 else "a"
rng = np.random.default_rng(seed)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
sc = bpy.context.scene
obs = [o for o in sc.objects if o.type == "MESH"]
for o in obs:   # подвижные узлы (винты) — в общие координаты до слияния
    o.data.transform(o.matrix_world)
for o in obs:
    o.parent = None
    o.matrix_world = Matrix.Identity(4)


def join(lst):
    bpy.ops.object.select_all(action="DESELECT")
    for o in lst:
        o.select_set(True)
    bpy.context.view_layer.objects.active = lst[0]
    if len(lst) > 1:
        bpy.ops.object.join()
    return bpy.context.view_layer.objects.active


rotor = None
if layout == "heli":
    rotor = next(o for o in obs if o.name.startswith("rotor") and not o.name.startswith("rotor_"))
    obs.remove(rotor)
body = join(obs)
for o in list(sc.objects):
    if o.type != "MESH":
        bpy.data.objects.remove(o, do_unlink=True)


def weld(ob):
    """Merge the vertices glTF import split at UV seams and hard edges: otherwise every seam is an open edge
    and the tears, the ragged bites and the solidify rim would run along all of them, not just the cuts"""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(ob.data)
    bm.free()


def mark_open(ob):
    """Flag the model's own open edges (panel gaps, a triangle-soup hull) as "orig_bnd": only the edges the
    crash cut open are torn, or a soup model like attacker_1 grows tens of thousands of torn teeth"""
    weld(ob)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    lay = bm.edges.layers.bool.get("orig_bnd") or bm.edges.layers.bool.new("orig_bnd")
    for e in bm.edges:
        e[lay] = e.is_boundary
    bm.to_mesh(ob.data)
    bm.free()


weld(body)
if layout == "heli":
    # 18 тыс. треугольников боевой модели — для остова в биоме вдвое меньше
    md = body.modifiers.new("dec", "DECIMATE")
    md.ratio = 0.45
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.modifier_apply(modifier="dec")
    # the main rotor's 7 thousand triangles too: five thin blades, each doubled by the skin's thickness
    weld(rotor)
    md = rotor.modifiers.new("dec", "DECIMATE")
    md.ratio = 0.35
    bpy.context.view_layer.objects.active = rotor
    bpy.ops.object.modifier_apply(modifier="dec")
mark_open(body)
if rotor is not None:
    mark_open(rotor)


def split(ob, part_of, names):
    """Разрезать объект по граням: part_of(центр грани) → имя части; первая часть остаётся в ob"""
    out = {}
    for name in names[1:]:
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if part_of(f.calc_center_median()) != name], context="FACES")
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        for m in ob.data.materials:
            me.materials.append(m)
        o = bpy.data.objects.new(name, me)
        sc.collection.objects.link(o)
        out[name] = o
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if part_of(f.calc_center_median()) != names[0]], context="FACES")
    bm.to_mesh(ob.data)
    bm.free()
    ob.name = names[0]
    out[names[0]] = ob
    # no ragged bites here any more: on the welded hull they took whole wings (a wing is a few dozen long
    # slivers); tear() makes the torn edge instead
    return out


def ragged(ob, passes=1, prob=0.3):
    """Рваный край разреза: грани у открытой кромки выкусываются случайно (2 прохода)"""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    # big faces are never bitten off: on a welded part a wing is a few dozen long triangles, and one bite or
    # "needle" taken out of it would take half the wing (torn edges come from tear() instead)
    big = 0.03 * sum(f.calc_area() for f in bm.faces)
    for _ in range(passes):
        edge = set()
        for e in bm.edges:
            if e.is_boundary:
                for f in e.link_faces:
                    edge.add(f)
        gone = [f for f in edge if rng.random() < prob and f.calc_area() < big]
        if gone and len(gone) < len(bm.faces) * 0.3:
            bmesh.ops.delete(bm, geom=gone, context="FACES")
    # иглы: длинные узкие треугольники на кромке после выкусывания — убрать, край рваный, но без «шипов»
    for _ in range(3):
        sl = []
        for f in bm.faces:
            if not any(e.is_boundary for e in f.edges) or f.calc_area() >= big:
                continue
            longest = max(e.calc_length() for e in f.edges)
            if longest > 1e-6 and f.calc_area() / (longest * longest) < 0.12:
                sl.append(f)
        if not sl or len(sl) > len(bm.faces) * 0.25:
            break
        bmesh.ops.delete(bm, geom=sl, context="FACES")
    bm.to_mesh(ob.data)
    bm.free()


def holes(ob, sel, prob):
    """Пробоины: случайные грани, где sel(центр грани, материал) — выбиты"""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    mats = [m.name for m in ob.data.materials]
    gone = [f for f in bm.faces if sel(f.calc_center_median(), mats[f.material_index] if mats else "") and rng.random() < prob]
    bmesh.ops.delete(bm, geom=gone, context="FACES")
    bm.to_mesh(ob.data)
    bm.free()


def place(ob, dx, dy, yaw, roll, pitch, squash=0.75, sink=0.008, pivot=None, ground_pct=18, dent=0.01):
    """Повернуть часть вокруг её центра (или pivot), сдвинуть и положить на землю, приплюснуть (смята ударом)"""
    me = ob.data
    if len(me.vertices) == 0:
        return
    cen = Vector(pivot) if pivot else sum((v.co for v in me.vertices), Vector()) / len(me.vertices)
    rot = Euler((math.radians(roll), math.radians(pitch), math.radians(yaw)), "XYZ").to_matrix().to_4x4()
    me.transform(Matrix.Translation(cen) @ rot @ Matrix.Translation(-cen))
    me.transform(Matrix.Translation((dx, dy, 0)))
    # лечь на землю всем весом: земля — на уровне нижних 20 % вершин, всё, что ниже, смято в землю
    # (не висит на законцовках и пилонах); вмятины — шумом по обшивке
    zs = np.array([v.co.z for v in me.vertices])
    g = float(np.percentile(zs, ground_pct))
    for v in me.vertices:
        z = v.co.z - g
        if z < 0:
            z = z * 0.08
        dn = noise.noise(v.co * 23.0 + Vector((seed, 0, 0)))
        v.co.z = z * squash - sink + dent * dn
        v.co.x += dent * 0.5 * noise.noise(v.co * 17.0 + Vector((0, seed, 0)))


def bend(ob, axis_pt, along, k):
    """Изогнуть часть: вершины дальше от axis_pt по направлению along опускаются/закручиваются (крыло подломлено)"""
    a = Vector(axis_pt)
    d = Vector(along).normalized()
    for v in ob.data.vertices:
        t = max(0.0, (v.co - a).dot(d))
        v.co.z -= k * t * t


parts = {}
if layout == "heli":
    # фюзеляж: кабина и середина (x > −0,14) и хвостовая балка с рулевым винтом
    parts = split(body, lambda c: "boom" if c.x < -0.14 else "cabin", ["cabin", "boom"])
    hub = Vector((0.209, 0.0, 0.261))
    def blade_of(c):
        d = Vector((c.x - hub.x, c.y - hub.y))
        if d.length < 0.07:
            return "hub"
        a = math.atan2(d.y, d.x) % (2 * math.pi)
        return "blade%d" % int(((a + math.pi / 5) % (2 * math.pi)) / (2 * math.pi / 5))
    parts.update(split(rotor, blade_of, ["hub"] + ["blade%d" % i for i in range(5)]))
    # кабина разбита: остекление выбито почти целиком, в носу и по крыше — пробоины
    holes(parts["cabin"], lambda c, m: "glass" in m, 0.8)
    holes(parts["cabin"], lambda c, m: c.x > 0.25 or c.z > 0.3, 0.22)
    holes(parts["boom"], lambda c, m: True, 0.08)
    ragged(parts["cabin"], 2, 0.35)
    # кабина на левом боку (крен 82°), смята; балка отломана и развёрнута; втулка с мачтой — у бывшего верха кабины
    place(parts["cabin"], 0.0, 0.0, 6.0, -82.0, 2.0, squash=0.7, ground_pct=30, dent=0.014)
    place(parts["boom"], -0.12, 0.13, 32.0, -25.0, 4.0, squash=0.75, ground_pct=25)
    place(parts["hub"], 0.17, -0.33, 0.0, -80.0, 0.0, squash=0.9)
    hubp = sum((v.co for v in parts["hub"].data.vertices), Vector()) / max(len(parts["hub"].data.vertices), 1)
    # лопасти — в стороны от втулки по земле: две согнуты, одна сломана и отброшена
    fan = [(-150, 0.0, 0.0), (-95, 0.06, 0.0), (-40, 0.0, 0.5), (15, 0.0, 0.0), (140, 0.32, 1.2)]
    for i in range(5):
        b = parts["blade%d" % i]
        me = b.data
        if len(me.vertices) == 0:
            continue
        # лопасть — вдоль радиуса: уложить плашмя, комлем к втулке, по направлению веера
        cen = sum((v.co for v in me.vertices), Vector()) / len(me.vertices)
        d0 = Vector((cen.x - hub.x, cen.y - hub.y, 0)).normalized()
        a0 = math.atan2(d0.y, d0.x)
        ang, throw, curl = fan[i]
        ang = math.radians(ang) + rng.uniform(-0.12, 0.12)
        me.transform(Matrix.Translation(-hub))
        me.transform(Matrix.Rotation(ang - a0, 4, "Z"))
        d = Vector((math.cos(ang), math.sin(ang), 0))
        # плашмя: убрать конусность (кончик был выше комля) — лопасть лежит на земле по всей длине
        ts = np.array([v.co.dot(d) for v in me.vertices])
        zs = np.array([v.co.z for v in me.vertices])
        kz = np.polyfit(ts, zs, 1)
        bury = rng.uniform(0.35, 0.7)          # где лопасть ушла под пыль/грунт
        for v, t0 in zip(me.vertices, ts):    # изгиб: лопасть загибается вбок от комля (ударилась о землю)
            t = max(0.0, t0 - 0.12)
            side = Vector((-d.y, d.x, 0))
            v.co += side * curl * t * t
            v.co.z = (v.co.z - (kz[0] * t0 + kz[1])) * 0.6 - (0.006 if abs(t0 / 0.6 - bury) < 0.12 else 0.0)
        me.transform(Matrix.Translation(Vector((hubp.x, hubp.y, 0)) + d * (0.04 + throw)))
        zs = sorted(v.co.z for v in me.vertices)
        me.transform(Matrix.Translation((0, 0, -zs[len(zs) // 5] - 0.002)))
else:
    def part_of(c):
        if c.x < -0.27:
            return "tail"
        if c.x > 0.3:
            return "nose"
        if c.y > 0.13:
            return "wing_l"
        if c.y < -0.13:
            return "wing_r"
        return "body"

    if layout == "a":
        parts = split(body, part_of, ["body", "tail", "nose", "wing_l", "wing_r"])
        # длинные треугольники крыла заходили за линию разлома «зубьями» — подрезать по линии с неровностью
        cut = {"wing_l": (1, 0.115, 1), "wing_r": (1, -0.115, -1), "tail": (0, -0.25, -1), "nose": (0, 0.28, 1)}
        for name, (ax, lim, sg) in cut.items():
            for v in parts[name].data.vertices:
                c = v.co[ax]
                j = 0.012 * math.sin(v.co[1 - ax] * 97.0) + 0.008 * math.sin(v.co[1 - ax] * 211.0)
                if (c - (lim + j)) * sg < 0:
                    v.co[ax] = lim + j
        # разброс: (сдвиг x, y, поворот вокруг вертикали, крен, тангаж) — градусы
        LAYOUT = {
            "body":   (0.0, 0.0, 0.0, 22.0, 3.0),
            "nose":   (0.1, 0.04, 28.0, 40.0, -6.0),
            "wing_l": (0.0, 0.07, -8.0, -9.0, 0.0),
            "wing_r": (-0.08, -0.3, 55.0, 172.0, 0.0),    # оторвано и перевёрнуто
            "tail":   (-0.17, 0.03, -38.0, 14.0, 0.0),     # хвост отломан, лёг с креном
        }
        for name, ob in parts.items():
            place(ob, *LAYOUT[name])
    elif layout == "b":
        # хвост — отдельно (x < −0,33), остальное — одним куском на брюхе, правое крыло подломлено
        # и законцовку левого крыла оторвало при юзе — лежит у борозды перевёрнутой
        parts = split(body, lambda c: "tail" if c.x < -0.33 else ("tip" if c.y > 0.26 else "body"), ["body", "tail", "tip"])
        # правое крыло подломлено вниз — законцовка в земле, корпус на брюхе с креном на это крыло
        for v in parts["body"].data.vertices:
            t = max(0.0, -v.co.y - 0.15)
            v.co.z -= 0.55 * t * t
            v.co.x -= 0.25 * t * t   # и загнуто назад
        place(parts["body"], 0.18, 0.0, 9.0, -4.0, 2.0)
        place(parts["tail"], -0.62, 0.1, 118.0, 24.0, 0.0)
        place(parts["tip"], -0.42, 0.02, 150.0, 170.0, 0.0)
    elif layout == "c":
        # перелом по x = −0,06: перед с левым крылом; зад с оперением развёрнут и на боку; правое крыло — в стороне
        def pc(c):
            if c.y < -0.13 and -0.33 < c.x < 0.1:
                return "wing_r"
            return "front" if c.x > -0.06 else "rear"
        parts = split(body, pc, ["front", "rear", "wing_r"])
        place(parts["front"], 0.08, -0.02, -14.0, -12.0, -4.0)
        place(parts["rear"], -0.2, 0.17, 47.0, 28.0, 0.0)
        place(parts["wing_r"], 0.05, -0.38, -125.0, 176.0, 0.0)
        bend(parts["wing_r"], (0, -0.38, 0), (1, 0, 0), -0.08)


# --- torn metal and thickness (weak-props list, 29.10.2026: "the shards are paper-thin"). The battle model is a
# single skin, so a cut part was an open sheet with no edge. Every cut edge is first refined and torn: its
# vertices pushed in and out along the sheet (teeth and rips) and curled off the surface (petalled metal); then
# the skin gets a real thickness (solidify, 8 cm on a 20 m plane) with the cut rim as its own surface (raw torn
# metal) and the inside as burnt-out interior. The torn edge points are kept for the paint (bare metal and
# blistered paint near a tear)
TEAR_PTS = []
THICK = {"heli": 0.0035}


def tear(ob, amp=0.011, curl=0.008, cuts=2):
    """Refine and tear the open edges of ob in place; their points go to TEAR_PTS"""
    weld(ob)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    lay = bm.edges.layers.bool.get("orig_bnd")
    be = [e for e in bm.edges if e.is_boundary and not (lay is not None and e[lay])]
    if not be:
        bm.free()
        return
    bmesh.ops.subdivide_edges(bm, edges=be, cuts=cuts, use_grid_fill=False)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    bm.normal_update()
    bverts = {v for e in bm.edges if e.is_boundary and not (lay is not None and e[lay]) for v in e.verts}
    moves = {}
    sv = Vector((seed * 3.1, seed * 1.7, len(TEAR_PTS) * 0.37))
    for v in bverts:
        out = Vector()
        for e in v.link_edges:
            if e.is_boundary and e.link_faces:
                out += v.co - e.link_faces[0].calc_center_median()
        n = v.normal
        out -= n * out.dot(n)
        if out.length < 1e-9:
            continue
        out.normalize()
        k1 = noise.noise(v.co * 70.0 + sv)
        k2 = noise.noise(v.co * 16.0 + sv * 0.5)
        moves[v] = out * amp * (0.65 * k1 + 0.35 * k2) + n * curl * (0.6 + 0.4 * k2) * (0.5 + 0.5 * k1)
    ring = {}
    for v, d in moves.items():   # the metal next to the tear bends with it
        for e in v.link_edges:
            o = e.other_vert(v)
            if o not in bverts:
                ring[o] = ring.get(o, Vector()) + d * 0.35
    for v, d in moves.items():
        v.co += d
    for v, d in ring.items():
        v.co += d
    for v in bverts:
        TEAR_PTS.append(tuple(v.co))
    bm.to_mesh(ob.data)
    bm.free()


def thicken(ob, t):
    """Give the skin of ob a thickness t inward: slots [own…, inner…, rim…] (material offsets of the solidify)"""
    me = ob.data
    own = list(me.materials)
    n = len(own)
    if n == 0:
        return
    for _ in range(n):
        me.materials.append(M_INNER)
    for _ in range(n):
        me.materials.append(M_TORN)
    md = ob.modifiers.new("thick", "SOLIDIFY")
    md.thickness = t
    md.offset = -1.0
    md.use_rim = True
    md.use_even_offset = False   # even thickness divides by the angle: spikes metres long at the torn teeth
    md.use_quality_normals = True
    md.material_offset = n
    md.material_offset_rim = 2 * n
    dg = bpy.context.evaluated_depsgraph_get()
    new = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    ob.modifiers.remove(md)
    old = ob.data
    ob.data = new
    bpy.data.meshes.remove(old)


def flat_mat(name, rgb):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1.0)
    return m


M_INNER = flat_mat("wk_inner", (0.035, 0.032, 0.028))   # burnt-out inside, primer where it survived (layers)
M_TORN = flat_mat("wk_torn", (0.3, 0.29, 0.27))         # raw metal of the tear
M_DEBRIS = flat_mat("wk_debris", (0.07, 0.065, 0.06))
M_EARTH = flat_mat("wk_earth", (0.1, 0.08, 0.06))
for m in bpy.data.materials:   # the canopy is baked into the wreck atlas (turret_paint keeps "glass" apart)
    if "glass" in m.name:
        m.name = m.name.replace("glass", "canopy")

for ob in [o for o in sc.objects if o.type == "MESH"]:
    if layout != "heli" and len(ob.data.polygons) > 400:
        # after the cut and the ragged bites (which need the fine mesh): a third fewer triangles, since the torn
        # rims and the skin's thickness add back more than that; the cut edges are kept as they are
        md = ob.modifiers.new("dec", "DECIMATE")
        md.ratio = 0.6
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.modifier_apply(modifier="dec")
    tear(ob, 0.006 if ob.name.startswith("blade") else 0.011, 0.004 if ob.name.startswith("blade") else 0.008, 1)
    thicken(ob, 0.002 if ob.name.startswith("blade") else THICK.get(layout, 0.004))
craft = [o for o in sc.objects if o.type == "MESH"]


# --- small debris: torn, bent skin plates with a thickness, scattered round the wreck (dark burnt metal)
def debris(n, cx, cy, rx, ry, smin, smax):
    for i in range(n):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(0.35, 1.0)
        s = rng.uniform(smin, smax)
        bm = bmesh.new()
        k = 5
        pts = []
        for j in range(k):   # an irregular torn outline
            t = 2 * math.pi * j / k + rng.uniform(-0.4, 0.4)
            q = s * rng.uniform(0.55, 1.0)
            pts.append(bm.verts.new((math.cos(t) * q * rng.uniform(1.0, 2.0), math.sin(t) * q, 0.0)))
        f = bm.faces.new(pts)
        bmesh.ops.triangulate(bm, faces=[f])
        bend_k = rng.uniform(-6.0, 6.0)
        for v in bm.verts:   # bent across
            v.co.z += bend_k * v.co.x * v.co.x
        r2 = bmesh.ops.extrude_face_region(bm, geom=list(bm.faces))
        for v in [g for g in r2["geom"] if isinstance(g, bmesh.types.BMVert)]:
            v.co.z += 0.0035
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        me = bpy.data.meshes.new("debris")
        bm.to_mesh(me)
        bm.free()
        me.materials.append(M_DEBRIS)
        ob = bpy.data.objects.new("debris", me)
        sc.collection.objects.link(ob)
        rot = Euler((rng.uniform(-0.35, 0.35), rng.uniform(-0.35, 0.35), rng.uniform(0, math.pi))).to_matrix().to_4x4()
        me.transform(Matrix.Translation((cx + math.cos(a) * r * rx, cy + math.sin(a) * r * ry, s * 0.12)) @ rot)


if layout == "a":
    debris(18, 0, 0, 0.45 * 1.1, 0.45 * 0.8, 0.012, 0.045)
elif layout == "b":
    debris(10, 0.15, 0, 0.4, 0.35, 0.012, 0.04)
    for i in range(8):   # along the furrow: what tore off in the slide
        debris(1, -0.25 - i * 0.07, rng.uniform(-0.05, 0.05), 0.03, 0.03, 0.01, 0.03)
elif layout == "c":
    debris(14, -0.05, 0.05, 0.35, 0.3, 0.012, 0.04)
else:
    debris(16, 0.0, 0.0, 0.45, 0.42, 0.012, 0.04)

# --- skid furrow: the ground torn up, a dark bottom between banks of earth, just above the model's zero (the game
#     sinks the wreck by 1 % of its width). Plane b long, c and the helicopter shorter
FURROW = {"b": (0.02, -0.72, 0.1, 0.07), "c": (-0.12, -0.62, -0.06, 0.06), "heli": (-0.02, -0.5, 0.05, 0.075)}
if layout in FURROW:
    x0, x1, bendy, half0 = FURROW[layout]
    bm = bmesh.new()
    n = 18
    prof = [(-1.0, 0.0), (-0.7, 0.014), (-0.4, 0.003), (0.0, -0.003), (0.4, 0.003), (0.7, 0.014), (1.0, 0.0)]
    rows = []
    for i in range(n + 1):
        t = i / n
        x = x0 + (x1 - x0) * t
        half = half0 * (1.0 - 0.45 * t) + 0.01 * noise.noise((x * 9, 0.3, 0))
        yc = bendy * t * t + 0.01 * noise.noise((x * 5, 1.7, 0))
        rows.append([bm.verts.new((x, yc + sd * half, 0.014 + z * (1.0 - 0.3 * t))) for sd, z in prof])
    for i in range(n):
        for j in range(len(prof) - 1):
            bm.faces.new([rows[i][j], rows[i][j + 1], rows[i + 1][j + 1], rows[i + 1][j]])
    me = bpy.data.meshes.new("furrow")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(M_EARTH)
    for p in me.polygons:
        p.use_smooth = True
    sc.collection.objects.link(bpy.data.objects.new("furrow", me))

# --- normalise on the craft itself (no furrow, no debris): centred, largest plan size 1, standing on z = 0
allv = [ob.matrix_world @ v.co for ob in craft for v in ob.data.vertices]
lo = Vector((min(v.x for v in allv), min(v.y for v in allv), min(v.z for v in allv)))
hi = Vector((max(v.x for v in allv), max(v.y for v in allv), max(v.z for v in allv)))
k = 1.0 / max(hi.x - lo.x, hi.y - lo.y)
T = Matrix.Diagonal((k, k, k, 1)) @ Matrix.Translation((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -max(lo.z, 0.0)))
for ob in sc.objects:
    if ob.type == "MESH":
        ob.data.transform(T @ ob.matrix_world)
        ob.matrix_world = Matrix.Identity(4)
# the parts and debris rest on the scorch, not under it: the scorch disc lies at z 0.006-0.012 (2 mm above the
# ground once the game sinks the model by 1 % of its width), and its alpha-blended soot would hide every wing
# lying flat on the ground beneath it. The furrow already sits at 0.014
LIFT = 0.013
for ob in sc.objects:
    if ob.type == "MESH" and not ob.name.startswith("furrow"):
        ob.data.transform(Matrix.Translation((0, 0, LIFT)))
T = Matrix.Translation((0, 0, LIFT)) @ T
TEAR = np.array([tuple(T @ Vector(p)) for p in TEAR_PTS], np.float32)
MPU = 20.0 / k   # metres per model unit: the battle model was ~20 m long at length 1

# --- one mesh, one burnt atlas (vehicle_wreck.py's way): parts, debris and furrow joined, surfaces by class
for ob in [o for o in sc.objects if o.type == "MESH" and len(o.data.polygons) == 0]:
    bpy.data.objects.remove(ob, do_unlink=True)
wreck = join([o for o in sc.objects if o.type == "MESH"])
wreck.name = "wreck"
SKIN, CANOPY, INNER, TORN, DEBRIS, EARTH = range(6)


def part_id(m):
    n = m.name if m is not None else ""
    if n.startswith("wk_"):
        return {"wk_inner": INNER, "wk_torn": TORN, "wk_debris": DEBRIS, "wk_earth": EARTH}[n.split(".")[0]]
    return CANOPY if "canopy" in n else SKIN


import scipy.spatial  # noqa: E402
import turret_paint as TP  # noqa: E402

BSC = 0.15   # turret_paint units per model unit: bevel radius ~2 cm, AO reach ~0.4 m on a plane
tree = scipy.spatial.cKDTree(TEAR) if len(TEAR) else None
SCORCH = np.array([0.08, 0.065, 0.055], np.float32)
BURNT = np.array([0.33, 0.31, 0.29], np.float32)     # burnt-through aluminium skin, grey with a warm cast
ASH = np.array([0.56, 0.54, 0.5], np.float32)
SOOT = np.array([0.035, 0.032, 0.03], np.float32)
DUST = np.array([0.62, 0.55, 0.43], np.float32)
PRIMER = np.array([0.3, 0.31, 0.19], np.float32)     # interior primer, yellow-green
RAW = np.array([0.6, 0.59, 0.56], np.float32)        # fresh tear in the metal
HOT = 0.6 if layout == "heli" else 0.5               # the helicopter burnt out worse


def layers(P, N, B, AO, part, S):
    Pk = P * BSC                       # model units
    Pm = (Pk * MPU).astype(np.float32)  # metres
    z = Pk[:, 2]
    up = np.clip(N[:, 2], 0, 1)
    t, bb = TP._frame(N)
    skin, canopy, inner, torn, deb, earth = [part == i for i in range(6)]
    d_tear = tree.query(Pk, k=1)[0].astype(np.float32) * MPU if tree is not None else np.full(len(P), 99, np.float32)
    burn = np.clip(HOT + 0.45 * (TP.fbm(Pm, 0.12, seed + 1, 3) - 0.5) + 0.2 * (TP.fbm(Pm, 0.5, seed + 2, 2) - 0.5)
                   + 0.25 * np.exp(-np.hypot(Pk[:, 0], Pk[:, 1]) / 0.25) + 0.3 * np.exp(-d_tear / 0.6), 0, 1)
    col = S.copy()
    mott = TP.fbm(Pm, 0.7, seed + 3, 4)
    # paint: faded and chalky where it survived, blistered, then burnt through: dark scorch → grey burnt skin →
    # pale ash oxide; around every tear the paint is burnt off in a ragged band
    lum = col @ np.array([0.3, 0.59, 0.11], np.float32)
    faded = col * 0.6 + (lum[:, None] * 0.7 + 0.03) * 0.4
    blist = TP.sstep(0.6, 0.7, TP.fbm(Pm, 4.0, seed + 4, 2)) * TP.sstep(0.25, 0.45, burn)
    faded = faded * (1 - 0.4 * blist[:, None])
    e = burn + 0.15 * (TP.fbm(Pm, 2.0, seed + 5, 2) - 0.5) + 0.35 * np.exp(-d_tear / 0.25)
    burnt = BURNT * (0.75 + 0.5 * TP.fbm(Pm, 1.5, seed + 6, 3))[:, None]
    ash = ASH * (0.85 + 0.3 * TP.fbm(Pm, 3.0, seed + 7, 2))[:, None]
    c = faded
    c = c * (1 - TP.sstep(0.36, 0.46, e)[:, None]) + SCORCH * TP.sstep(0.36, 0.46, e)[:, None]
    c = c * (1 - TP.sstep(0.5, 0.64, e)[:, None]) + burnt * TP.sstep(0.5, 0.64, e)[:, None]
    c = c * (1 - (0.6 * TP.sstep(0.78, 0.95, e))[:, None]) + ash * (0.6 * TP.sstep(0.78, 0.95, e))[:, None]
    col = np.where(skin[:, None], c, col)
    # canopy: smashed, crazed and sooted glass over a dark cockpit
    col = np.where(canopy[:, None], np.array([0.05, 0.05, 0.05], np.float32) * (0.7 + 0.8 * mott)[:, None], col)
    # inside: soot black, primer showing in patches the fire did not reach
    pr = TP.sstep(0.55, 0.7, TP.fbm(Pm, 0.8, seed + 8, 3)) * (1 - burn)
    c_in = SOOT * (0.8 + 0.6 * mott)[:, None] * (1 - pr[:, None]) + PRIMER * 0.7 * pr[:, None]
    col = np.where(inner[:, None], c_in, col)
    # the tear's rim: raw metal, bright where freshly ripped, heat-darkened and sooted in places
    c_t = RAW * (0.7 + 0.45 * TP.fbm(Pm, 6.0, seed + 9, 2))[:, None]
    c_t = c_t * (1 - 0.6 * TP.sstep(0.55, 0.75, burn)[:, None]) + SOOT * (0.6 * TP.sstep(0.55, 0.75, burn))[:, None]
    col = np.where(torn[:, None], c_t, col)
    col = np.where(deb[:, None], burnt * 0.5 * (1 - 0.5 * TP.sstep(0.4, 0.6, mott))[:, None]
                   + SOOT * TP.sstep(0.4, 0.6, mott)[:, None], col)
    clod = TP.fbm(Pm, 2.5, seed + 10, 3)
    col = np.where(earth[:, None], col * (0.75 + 0.6 * clod)[:, None] * (0.7 + 0.5 * up)[:, None], col)
    # soot: plumes rising over the burnt core and the openings, heavy along tears that faced the fire
    soot = np.clip(0.55 * TP.sstep(0.5, 0.85, burn) * (0.5 + 0.8 * (TP.fbm(Pm, 0.9, seed + 11, 3) - 0.3))
                   + 0.4 * np.exp(-d_tear / 0.35) * up, 0, 0.85) * (skin | torn | deb)
    col = col * (1 - soot[:, None]) + SOOT * soot[:, None]
    # dust and sand: settled on top, drifted at the foot, cavity grime from the baked AO
    cav = 1.0 - AO
    col = col * (1 - 0.4 * cav[:, None]) + SOOT * (0.4 * cav)[:, None]
    dust = up * np.clip(0.12 + (TP.fbm(Pm, 0.6, seed + 12, 3) - 0.45) * 0.7, 0, 0.32) * (1 - earth) * (1 - 0.6 * deb)
    zg = (z - LIFT) * MPU   # metres above the ground the parts rest on
    foot = (1 - TP.sstep(0.0, 0.15 + 0.25 * TP.fbm(Pm, 1.2, seed + 13, 2), zg)) * 0.4 * (1 - earth)
    dust = np.clip(np.maximum(dust, foot), 0, 0.7)
    col = col * (1 - dust[:, None]) + DUST * dust[:, None]
    speck = TP.sstep(0.7, 0.76, TP.fbm(Pm, 9.0, seed + 14, 2)) * up * TP.sstep(0.5, 0.8, burn) * skin
    col = col * (1 - 0.5 * speck[:, None]) + ASH * (0.5 * speck)[:, None]
    col = col * (0.6 + 0.4 * AO ** 0.8)[:, None]
    rough = np.select([skin, canopy, inner, torn, deb, earth], [0.9, 0.5, 0.97, 0.62, 0.9, 1.0], 0.92).astype(np.float32)
    rough = np.clip(rough + 0.06 * (TP.fbm(Pm, 3.0, seed + 15, 2) - 0.5) + 0.08 * dust + 0.05 * soot, 0.4, 1.0)
    metal = (0.35 * torn * (1 - soot) + 0.08 * skin * TP.sstep(0.6, 0.8, e) * (1 - soot) * (1 - dust)).astype(np.float32)

    def height(Q):
        """Relief in metres: dents and buckles in the skin, blistered paint, clods in the furrow"""
        h = (skin | torn | deb | inner) * (0.012 * TP.fbm(Q, 0.9, seed + 16, 3) + 0.004 * TP.fbm(Q, 3.5, seed + 17, 2))
        h = h + skin * 0.0015 * TP.sstep(0.6, 0.7, TP.fbm(Q, 4.0, seed + 4, 2)) * TP.sstep(0.25, 0.45, burn)
        return h + earth * 0.02 * TP.fbm(Q, 2.5, seed + 10, 3)
    e2 = 0.01
    hu = (height(Pm + t * e2) - height(Pm - t * e2)) / (2 * e2)
    hv = (height(Pm + bb * e2) - height(Pm - bb * e2)) / (2 * e2)
    nn = B - (hu[:, None] * t + hv[:, None] * bb) * 1.0
    nn /= np.linalg.norm(nn, axis=1, keepdims=True) + 1e-8
    return np.clip(col, 0, 1), rough, metal, nn


sc.render.threads_mode = "FIXED"
sc.render.threads = 2
for p in wreck.data.polygons:
    p.use_smooth = False
wreck.select_set(True)
bpy.context.view_layer.objects.active = wreck
TP.bake_set([wreck], {"own": True, "seed": seed, "part": part_id, "layers": layers, "uv_margin": 0.0012}, 2048,
            "wreck_" + layout, scale=BSC)

# --- scorched ground under the wreck: burnt earth with ash, soot fingers thrown out by the fire and a ragged
#     edge (alpha), larger than the wreck; a fan of slightly lowered rim points so it hugs bumpy ground
import tex_lib as TL  # noqa: E402
sp = TL.scorch("wreck_scorch", seed)
m_sc = bpy.data.materials.new("scorch")
m_sc.use_nodes = True
nt = m_sc.node_tree
bs = nt.nodes["Principled BSDF"]
img = bpy.data.images.load(sp)
img.pack()
tx = nt.nodes.new("ShaderNodeTexImage")
tx.image = img
nt.links.new(tx.outputs["Color"], bs.inputs["Base Color"])
nt.links.new(tx.outputs["Alpha"], bs.inputs["Alpha"])
bs.inputs["Metallic"].default_value = 0.0
bs.inputs["Roughness"].default_value = 1.0
ex = (hi.x - lo.x) * k * 0.62
ey = (hi.y - lo.y) * k * 0.62
bm = bmesh.new()
uvl = bm.loops.layers.uv.new("UVMap")
segs = 40
cen = bm.verts.new((0, 0, 0.012))
mid = [bm.verts.new((math.cos(2 * math.pi * i / segs) * ex * 0.55, math.sin(2 * math.pi * i / segs) * ey * 0.55, 0.011))
       for i in range(segs)]
ring = [bm.verts.new((math.cos(2 * math.pi * i / segs) * ex, math.sin(2 * math.pi * i / segs) * ey, 0.006))
        for i in range(segs)]
for i in range(segs):
    j = (i + 1) % segs
    for f in (bm.faces.new([cen, mid[i], mid[j]]), bm.faces.new([mid[i], ring[i], ring[j], mid[j]])):
        for lp in f.loops:
            co = lp.vert.co
            lp[uvl].uv = (0.5 + co.x / (2 * ex), 0.5 + co.y / (2 * ey))
me = bpy.data.meshes.new("scorch")
bm.to_mesh(me)
bm.free()
me.materials.append(m_sc)
sc.collection.objects.link(bpy.data.objects.new("scorch", me))

bpy.ops.object.select_all(action="DESELECT")
bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_image_format="JPEG", export_jpeg_quality=90,
                          export_tangents=True)   # the atlas goes as JPEG; the scorch keeps its alpha (PNG)
tris = sum(sum(len(p.vertices) - 2 for p in ob.data.polygons) for ob in sc.objects if ob.type == "MESH")
print("WRECK %s (%s): %d triangles, height %.2f" % (dst, layout, tris, (hi.z - lo.z) * k))
