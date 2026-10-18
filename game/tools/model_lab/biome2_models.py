# Модели «Архипелага Таласора»: рецепт на каждую позицию docs/biome2/models-pipeline.md.
#   python3 -I game/tools/model_lab/biome2_models.py <имя|all> [--src=/mnt/project-files/docs/biome2/models_in] [--out=game/models]
# Исходники (Sketchfab, CC BY) — в файлах проекта, в репозиторий не кладём. Каждая модель: упрощение до бюджета,
# знаки и надписи стёрты, 2–3 детали силуэта изменены (мир вымышленный), окраска игры; нос +X, длина 1.
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from mathutils import Vector, Matrix
import b2lib as L

A = sys.argv[1:]
OPT = dict(x[2:].split('=', 1) for x in A if x.startswith('--') and '=' in x)
SRC = OPT.get('src', '/mnt/project-files/docs/biome2/models_in')
MODELS = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'models'))
OUT = OPT.get('out', MODELS)

# окраска врагов — как у крейсера «Сторож»: тёмно-серый корпус, светлая надстройка, красные крыши башен
HULL = (0.31, 0.32, 0.34)
DECK = (0.40, 0.41, 0.42)
SUPER = (0.62, 0.63, 0.65)
RED = (0.78, 0.16, 0.12)
GUN = (0.22, 0.23, 0.24)


def src(name):
    return os.path.join(SRC, name)


def battle(name):
    return os.path.join(OUT, 'battle', 'fh_battle_%s.glb' % name)


def scenery(name):
    return os.path.join(OUT, 'biome2', '%s.glb' % name)


def gun_mount(x, y, z, r, mat_body, mat_roof, barrels=2, blen=None, name='turret', rz=0.0):
    """Башенка: низкий цилиндр, красная крыша, стволы вперёд (по +X, повёрнуто на rz)."""
    blen = blen or r * 2.2
    parts = [L.cyl((x, y, z + r * 0.3), r, r * 0.6, mat_body, name, seg=14),
             L.cyl((x, y, z + r * 0.63), r * 0.82, r * 0.08, mat_roof, name + '_roof', seg=14)]
    for i in range(barrels):
        off = (i - (barrels - 1) / 2) * r * 0.45
        parts.append(L.cyl((x + r * 0.5 + blen / 2, y + off, z + r * 0.35), r * 0.1, blen, GUNM(), name + '_gun', seg=6, axis='X'))
    if rz:
        L.xform(parts, Matrix.Translation((x, y, 0)) @ Matrix.Rotation(rz, 4, 'Z') @ Matrix.Translation((-x, -y, 0)))
    return parts


def GUNM():
    return L.flat('fh_gun', GUN, 0.5, 0.4)


# ---------------- К-3 катер сопровождения (16 м) ----------------
def e_ship_escort():
    L.reset()
    o = L.load(src('K-3_patrol_boat.glb'))
    L.place(o, bow='-x', length=16, water=0.5)
    L.xform(o, Matrix.Scale(0.78, 4, Vector((0, 1, 0))))   # корпус уже, чем у исходника — стремительнее
    L.matte(o)
    # кранцы-покрышки по бортам, купол РЛС и антенны (узнаваемые детали исходника) — убрать
    o = L.kill_parts(o, lambda mn, mx, n: (abs(mn.y) > 1.85 or abs(mx.y) > 1.85) and mx.z - mn.z < 0.75 and mx.x - mn.x < 0.8)
    o = L.kill_parts(o, lambda mn, mx, n: mn.z > 4.2)
    for m in L.mats(o):
        t = L.tex_of(m)
        if t:
            L.regrade(t, HULL, keep=0.8)
    body = L.flat('fh_escort_super', SUPER, 0.7)
    red = L.flat('fh_red', RED, 0.6)
    # свои детали: мачта с красным топом за рубкой, носовая башенка вместо открытого гнезда, кормовая рубка
    add = [L.cyl((-0.6, 0, 4.4), 0.09, 2.6, body, 'mast', seg=6),
           L.box((-0.6, 0, 5.0), (0.12, 1.3, 0.1), body, 'yard'),
           L.cyl((-0.6, 0, 5.75), 0.14, 0.2, red, 'mast_top', seg=8),
           L.box((-4.4, 0, 1.75), (1.8, 1.5, 0.55), L.flat('fh_escort_deck', DECK), 'aft_house')]
    add += gun_mount(5.4, 0, 2.05, 0.62, body, red, barrels=2, blen=1.6, name='bow_turret')
    o += add
    L.finish(o, battle('e_ship_escort'), target=9000, maxtex=1024)


# ---------------- К-2 танкер (90 м) ----------------
def e_ship_tanker():
    L.reset()
    o = L.load(src('K-2_tanker_ship.glb'))
    L.place(o, bow='+y', length=90)
    L.xform(o, Matrix.Translation((0, 0, -2.9)))   # ватерлиния — граница красного днища
    # мелочь меньше 1,2 м и красная полоса посреди палубы
    o = L.drop(o, names=('Object_79', 'Object_77', 'Object_16'), mindiag=1.2)
    for ob in o:   # вставки палубы и борта (белые плоскости исходника) — в цвет палубы и корпуса
        if ob.name in ('Object_8', 'Object_9'):
            L.assign(ob, L.flat('fh_tanker_deck', (0.47, 0.24, 0.17)))
        if ob.name in ('Object_6', 'Object_10'):
            L.assign(ob, L.flat('fh_tanker_hull', (0.20, 0.32, 0.29)))
    L.matte(o, 0.75)
    # красное пятно посреди палубы (тот же материал, что днище) — убрать
    o = L.kill_faces(o, lambda c, n: c.z > 1.5, mat='Material.001')
    for m in L.mats(o):   # гражданская окраска: корпус тёмно-зелёный вместо чёрного, надстройка кремовая
        c = L.bsdf(m).inputs['Base Color'].default_value
        if max(c[:3]) < 0.02:
            L.solid(m, (0.20, 0.32, 0.29))
        elif min(c[:3]) > 0.7:
            L.solid(m, (0.86, 0.83, 0.74))
        elif c[0] > 0.55 and c[1] < 0.1:   # ярко-красная палуба → ржаво-коричневая
            L.solid(m, (0.47, 0.24, 0.17))
    cream = L.flat('fh_tanker_cream', (0.86, 0.83, 0.74))
    band = L.flat('fh_tanker_band', (0.85, 0.55, 0.12))
    dark = L.flat('fh_tanker_dark', (0.16, 0.16, 0.17))
    rust = L.flat('fh_tanker_rust', (0.52, 0.22, 0.12))
    # свой силуэт: высокая труба с охристой полосой за надстройкой, носовая мачта, бак с надстройкой
    win = L.flat('fh_window', (0.12, 0.16, 0.2), 0.3)
    o += [L.box((-35.6, 0, 6.6), (5.6, 9.4, 8.0), cream, 'bridge'),
          L.box((-32.75, 0, 9.4), (0.12, 9.0, 0.8), win, 'bridge_win'),
          L.box((-34.6, 0, 9.4), (2.6, 9.52, 0.8), win, 'bridge_win_side'),
          L.box((-34.0, 0, 10.4), (2.4, 12.4, 0.25), cream, 'bridge_wings'),
          L.cyl((-39.8, 0, 8.0), 1.5, 10.8, cream, 'funnel', seg=16, r2=1.3),
          L.cyl((-39.8, 0, 11.5), 1.42, 1.3, band, 'funnel_band', seg=16),
          L.cyl((-39.8, 0, 13.45), 1.3, 0.2, dark, 'funnel_top', seg=16),
          L.cyl((32.0, 0, 8.8), 0.25, 8.0, cream, 'fore_mast', seg=8),
          L.box((32.0, 0, 10.6), (0.3, 4.0, 0.25), cream, 'fore_yard'),
          L.box((38.5, 0, 3.7), (5.0, 7.0, 2.2), rust, 'forecastle'),
          L.box((-12.0, 0, 3.4), (3.0, 7.0, 1.6), cream, 'pump_house')]
    L.finish(o, battle('e_ship_tanker'), target=16000, maxtex=1024)


# ---------------- К-5 десантная баржа с грузом (14 м) ----------------
def e_ship_landing():
    L.reset()
    o = L.load(src('K-5_landing_boat.glb'))
    L.place(o, bow='-y', length=14)
    L.xform(o, Matrix.Translation((0, 0, -0.8)))
    o = L.drop(o, mindiag=0.3)
    o = L.kill_parts(o, lambda mn, mx, n: mn.z > 2.9 and mx.x - mn.x < 0.4)   # флажок и мелочь на корме
    o = L.kill_faces(o, lambda c, n: c.x > 4.55)   # откинутая аппарель — убрать, ставим закрытую
    L.matte(o, 0.8)
    grey = {'NEUTRE': HULL, 'Camouflage_de_l_US_NAVY': (0.36, 0.38, 0.40), 'LCVP_Texture': HULL,
            'Gris_Fonc': DECK, 'Gris_anthracite': GUN, 'Noir': GUN, 'vert_mat': GUN, 'Texture_chargeur_m1919': GUN}
    for m in L.mats(o):   # все текстуры (камуфляж, номера, ромбы) заменены сплошной серой окраской
        base = m.name.split('.')[0]
        if base in grey:
            L.solid(m, grey[base])
    # груз: грузовик колонны Нагорья и штабель ящиков под брезентом
    truck = L.load(os.path.join(MODELS, 'battle', 'fh_battle_e_convoy_truck.glb'))
    L.place(truck, length=6.2)
    L.xform(truck, Matrix.Translation((1.6, 0, 0.45)))
    crate = L.flat('fh_crate', (0.45, 0.36, 0.22))
    tarp = L.flat('fh_tarp', (0.38, 0.40, 0.30))
    ramp = L.flat('fh_ramp', (0.36, 0.38, 0.40))
    o += [L.box((4.5, 0, 1.2), (0.25, 3.0, 1.5), ramp, 'ramp')]
    o += truck + [L.box((-2.4, 0.55, 0.85), (1.8, 1.0, 0.8), crate, 'crate'),
                  L.box((-2.4, -0.6, 0.75), (1.6, 0.9, 0.6), crate, 'crate'),
                  L.box((-3.2, 0, 1.15), (1.0, 2.0, 0.35), tarp, 'tarp'),
                  L.cyl((-1.0, -0.8, 0.85), 0.32, 0.8, L.flat('fh_drum', (0.25, 0.32, 0.22)), 'drum', seg=10)]
    L.finish(o, battle('e_ship_landing'), target=9000, maxtex=1024)


# ---------------- М-1 буи фарватера: красный (знак-цилиндр) и зелёный (знак-конус) ----------------
def a22_buoy_red():
    _buoy('a22_buoy_red', (0.80, 0.14, 0.10), cone=False)


def a23_buoy_green():
    _buoy('a23_buoy_green', (0.12, 0.52, 0.24), cone=True)


def _buoy(name, rgb, cone):
    L.reset()
    o = L.load(src('M-1_buoy.glb'))
    L.place(o, length=2.0, water=-0.5)
    L.matte(o, 0.6)
    for m in L.mats(o):
        t = L.tex_of(m)
        if t:
            L.regrade(t, rgb, keep=0.9)
    mn, mx = L.bounds(o)
    mark = L.flat(name + '_mark', rgb, 0.6)
    top = mx.z
    if cone:
        o.append(L.cyl((0, 0, top + 0.3), 0.32, 0.6, mark, 'topmark', seg=12, r2=0.0))
    else:
        o.append(L.cyl((0, 0, top + 0.28), 0.26, 0.5, mark, 'topmark', seg=12))
    L.finish(o, scenery(name), target=1500, maxtex=512)


RECIPES = {f.__name__: f for f in [e_ship_escort, e_ship_tanker, e_ship_landing, a22_buoy_red, a23_buoy_green]}

if __name__ == '__main__':
    names = [a for a in A if not a.startswith('--')]
    for n in (RECIPES if names == ['all'] else names):
        RECIPES[n]()
