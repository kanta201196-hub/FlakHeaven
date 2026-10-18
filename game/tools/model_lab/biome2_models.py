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


# ---------------- В-1 катер ПВО «Скат» (30 м) ----------------
def e_ship_aa():
    L.reset()
    o = L.load(src('V-1_missile_boat.glb'))
    L.place(o, bow='+y', length=30)
    L.xform(o, Matrix.Translation((0, 0, -1.2)))
    # мачта с антеннами, ракетные контейнеры на корме и плоскости-знаки исходника — убрать
    o = L.drop(o, names=('Object_17', 'Object_18', 'Object_42', 'Object_29', 'Object_50', 'Object_10', 'Object_11',
                         'Object_12', 'Object_13', 'Object_45', 'Object_46', 'Object_34', 'Object_26', 'Object_15'))
    L.xform(o, Matrix.Translation((0, -1.4, 0)))   # ось корпуса (без бортового контейнера) — на y = 0
    L.matte(o, 0.75)
    for m in L.mats(o):   # синий камуфляж → ровная серая окраска (контраст пятен почти убран)
        t = L.tex_of(m)
        if t:
            L.regrade(t, HULL, keep=0.15, lo=0.8, hi=1.2)
    sup = L.flat('fh_aa_super', SUPER, 0.7)
    red = L.flat('fh_red', RED, 0.6)
    o += gun_mount(8.2, 0, 4.3, 1.1, sup, red, barrels=2, blen=2.6, name='aa_bow')
    o += gun_mount(-10.0, 0, 4.3, 1.1, sup, red, barrels=2, blen=2.6, name='aa_stern', rz=math.pi)
    # своя мачта: короткая тренога с коробом РЛС и красным топом
    o += [L.cyl((-2.0, 0, 7.0), 0.22, 4.4, sup, 'mast', seg=8),
          L.box((-2.0, 0, 8.4), (0.8, 3.2, 0.6), sup, 'radar'),
          L.cyl((-2.0, 0, 9.4), 0.25, 0.4, red, 'mast_top', seg=8),
          L.box((-7.5, 0, 4.6), (3.0, 3.6, 1.0), L.flat('fh_aa_deck', DECK), 'ammo_box')]
    L.finish(o, battle('e_ship_aa'), target=9000, maxtex=1024)


# ---------------- В-3 экраноплан «Крачка» (70 м) ----------------
def e_ekranoplan():
    L.reset()
    o = L.load(src('V-3_ekranoplan.glb'))
    L.place(o, bow='-x', length=70)
    o = L.drop(o, names=('Object_2', 'Object_3', 'Object_12', 'Object_13', 'Object_14', 'Object_16', 'Object_17',
                         'Object_18', 'Object_15', 'Object_4'))   # приборы кабины — сверху не видны
    L.matte(o, 0.7)
    for m in L.mats(o):   # голубые полосы и бортовой номер — в ровный светло-серый
        t = L.tex_of(m)
        if t:
            L.regrade(t, (0.66, 0.67, 0.69), keep=0.25, lo=0.75, hi=1.15)
    lt = L.flat('fh_ekr_light', (0.70, 0.71, 0.73), 0.7)
    red = L.flat('fh_red', RED, 0.6)
    dark = L.flat('fh_ekr_dark', (0.14, 0.14, 0.15), 0.6)
    # по референсам Kanta: ракетные контейнеры парами на спине, гондолы на концах крыла, шар на киле
    tilt = Matrix.Rotation(math.radians(-12), 3, 'Y')
    for x in (-5.0, -10.5, -16.0):
        for y in (-1.25, 1.25):
            o.append(L.cyl((x, y, 5.6), 0.62, 5.0, L.flat('fh_ekr_tube', (0.47, 0.48, 0.50), 0.7), 'tube', seg=12, axis='X', rot=tilt))
            o.append(L.cyl((x + 2.47, y, 6.13), 0.5, 0.12, red, 'tube_cap', seg=12, axis='X', rot=tilt))
    for y in (-13.9, 13.9):
        o.append(L.cyl((7.5, y, 2.6), 0.85, 9.0, lt, 'tip_pod', seg=12, axis='X'))
        o.append(L.cyl((12.6, y, 2.6), 0.85, 1.6, red, 'tip_nose', seg=12, axis='X', r2=0.1))
    o.append(L.sphere((-30.0, 0, 14.6), 1.25, lt, 'tail_ball', seg=14, scale=(1.6, 1, 1)))
    o.append(L.box((-31.6, 0, 14.6), (0.8, 0.3, 1.0), red, 'tail_tip'))
    L.finish(o, battle('e_ekranoplan'), target=12000, maxtex=1024)


# ---------------- В-4 гидросамолёт-ракетоносец «Буревестник» (14 м, два мотора) ----------------
def e_seaplane():
    L.reset()
    o = L.load(src('V-4_seaplane.glb'))
    L.place(o, bow='+y', length=14)
    # винт и кок в носу убираем: два мотора на крыле, нос — остеклённый (штурманский)
    o = L.drop(o, names=('Cessna172 SeaPlane.006_11Mtl_0',))
    o = L.kill_parts(o, lambda mn, mx, n: mn.x > 6.1 and mx.z - mn.z < 0.9)
    L.matte(o, 0.65)
    for m in L.mats(o):
        t = L.tex_of(m)
        if t:   # белый с бордовым и бортовыми буквами → ровный серый (буквы и полосы пропадают)
            L.regrade(t, (0.60, 0.62, 0.65), keep=0.03, lo=0.9, hi=1.05)
    grey = L.flat('fh_sea_grey', (0.55, 0.57, 0.60), 0.65)
    dark = L.flat('fh_sea_dark', (0.12, 0.13, 0.15), 0.4)
    red = L.flat('fh_red', RED, 0.6)
    o.append(L.cyl((6.75, 0, 3.4), 0.62, 1.1, dark, 'glass_nose', seg=12, axis='X', r2=0.18))
    for y in (-3.7, 3.7):
        o.append(L.cyl((3.4, y, 4.3), 0.6, 5.0, grey, 'nacelle', seg=12, axis='X', r2=0.45))
        o.append(L.cyl((6.05, y, 4.3), 0.34, 0.5, red, 'spinner', seg=10, axis='X', r2=0.05))
        o.append(L.cyl((5.9, y, 4.3), 1.5, 0.06, dark, 'prop_disc', seg=16, axis='X'))
        for yy in (y * 1.45, y * 1.95):
            o.append(L.cyl((2.4, yy, 3.75), 0.26, 3.0, grey, 'rocket', seg=8, axis='X'))
            o.append(L.cyl((4.05, yy, 3.75), 0.26, 0.4, red, 'rocket_tip', seg=8, axis='X', r2=0.02))
    o.append(L.box((-5.75, 0, 5.25), (0.9, 0.22, 0.6), red, 'fin_tip'))
    L.finish(o, battle('e_seaplane'), target=9000, maxtex=1024, center=True)


# ---------------- В-2 баржа-батарея (40 м, кодом) ----------------
def _barge_ring(x, b, zb, zd, ch=0.6):
    """Сечение плоскодонного корпуса: днище zb, палуба zd, полуширина b, скула ch."""
    return [(x, -b + ch, zb), (x, b - ch, zb), (x, b, zb + ch), (x, b, zd), (x, -b, zd), (x, -b, zb + ch)]


def e_ship_battery():
    L.reset()
    hull_m = L.flat('fh_hull', HULL, 0.8)
    deck_m = L.flat('fh_deck', DECK, 0.85)
    sup = L.flat('fh_super', SUPER, 0.7)
    red = L.flat('fh_red', RED, 0.6)
    rust = L.flat('fh_rust', (0.42, 0.26, 0.18), 0.9)
    crate = L.flat('fh_crate', (0.38, 0.40, 0.30), 0.9)
    # корпус: скошенные нос и корма как у понтона, на палубе — фальшборт
    secs = [_barge_ring(-20, 5.0, 0.9, 2.0), _barge_ring(-17, 5.5, -1.4, 2.0), _barge_ring(16, 5.5, -1.4, 2.0),
            _barge_ring(20, 5.0, 0.9, 2.2)]
    o = [L.loft(secs, hull_m, 'hull'),
         L.box((0, 0, 2.05), (39.0, 10.6, 0.1), deck_m, 'deck'),
         L.box((-1.0, 5.35, 2.5), (35.0, 0.25, 0.9), hull_m, 'bulwark_l'),
         L.box((-1.0, -5.35, 2.5), (35.0, 0.25, 0.9), hull_m, 'bulwark_r'),
         L.box((0, 0, 0.6), (33.0, 11.08, 0.35), rust, 'rust_band')]
    # три зенитные спарки на круглых площадках с бруствером
    for x in (12.5, 0.0, -12.5):
        o += [L.cyl((x, 0, 2.4), 3.2, 0.7, deck_m, 'platform', seg=20),
              L.cyl((x, 0, 2.95), 3.4, 0.5, hull_m, 'parapet', seg=20)]
        o += gun_mount(x, 0, 2.8, 1.5, sup, red, barrels=2, blen=3.6, name='aa', rz=math.radians(25 if x > 0 else -25 if x < 0 else 90))
    # рубка, мачта с РЛС, ящики боезапаса
    o += [L.box((-17.0, 0, 3.6), (4.0, 6.0, 3.0), sup, 'house'),
          L.box((-15.0, 0, 4.4), (0.15, 5.2, 0.7), L.flat('fh_window', (0.12, 0.16, 0.2), 0.3), 'house_win'),
          L.cyl((-17.5, 0, 7.4), 0.2, 4.8, sup, 'mast', seg=8),
          L.box((-17.5, 0, 8.6), (0.8, 3.0, 0.5), sup, 'radar'),
          L.cyl((-17.5, 0, 9.95), 0.22, 0.4, red, 'mast_top', seg=8)]
    for x, y in ((6.2, 3.4), (6.2, -3.4), (-6.2, 3.6), (-6.2, -3.4), (17.0, 2.0)):
        o.append(L.box((x, y, 2.55), (1.8, 1.2, 0.9), crate, 'ammo'))
    for x in (-19.0, 18.5):   # кнехты и плотики
        for y in (-4.2, 4.2):
            o.append(L.cyl((x, y, 2.4), 0.3, 0.7, GUNM(), 'bollard', seg=8))
    for y in (-4.6, 4.6):
        o.append(L.cyl((-11.8 if y > 0 else -12.8, y, 3.2), 0.6, 2.6, L.flat('fh_raft', (0.85, 0.45, 0.12), 0.8), 'raft', seg=10, axis='X'))
    o.append(L.cyl((18.6, 0, 2.6), 0.6, 2.4, GUNM(), 'windlass', seg=10, axis='Y'))
    L.finish(o, battle('e_ship_battery'), target=6000, maxtex=1024)


# ---------------- В-5 дрон «Чайка» (3 м, кодом, рой — дёшево) ----------------
def e_drone_sea():
    L.reset()
    grey = L.flat('fh_drone_grey', (0.62, 0.64, 0.67), 0.6)
    dark = L.flat('fh_drone_dark', (0.25, 0.26, 0.28), 0.6)
    red = L.flat('fh_red', RED, 0.6)
    o = [L.cyl((0.1, 0, 0), 0.17, 2.4, grey, 'fuselage', seg=8, axis='X'),
         L.cyl((1.5, 0, 0), 0.17, 0.6, red, 'nose', seg=8, axis='X', r2=0.03),
         L.cyl((-1.25, 0, 0), 0.12, 0.3, dark, 'motor', seg=8, axis='X', r2=0.17),
         L.cyl((-1.45, 0, 0), 0.55, 0.03, dark, 'prop_disc', seg=10, axis='X'),
         # крыло «чайкой»: изломом вверх у корня
         L.hull([(0.45, 0.1, 0.0), (-0.05, 0.1, 0.0), (0.25, 0.75, 0.16), (-0.15, 0.75, 0.16),
                 (0.45, 0.1, 0.05), (-0.05, 0.1, 0.05), (0.25, 0.75, 0.2), (-0.15, 0.75, 0.2)], grey, 'wing_l1'),
         L.hull([(0.25, 0.75, 0.16), (-0.15, 0.75, 0.16), (0.05, 1.75, 0.05), (-0.2, 1.75, 0.05),
                 (0.25, 0.75, 0.2), (-0.15, 0.75, 0.2), (0.05, 1.75, 0.09), (-0.2, 1.75, 0.09)], grey, 'wing_l2'),
         L.box((-0.08, 1.74, 0.07), (0.28, 0.06, 0.1), red, 'tip_l')]
    mir = [ob.copy() for ob in o if ob.name.startswith(('wing_l', 'tip_l'))]
    for ob in mir:
        ob.data = ob.data.copy(); bpy.context.scene.collection.objects.link(ob)
        ob.data.transform(Matrix.Scale(-1, 4, Vector((0, 1, 0)))); ob.data.flip_normals()
    o += mir
    for sgn in (-1, 1):   # V-образное оперение
        o.append(L.hull([(-0.8, 0, 0.1), (-1.15, 0, 0.1), (-1.0, 0.45 * sgn, 0.42), (-1.2, 0.45 * sgn, 0.42),
                         (-0.8, 0, 0.13), (-1.15, 0, 0.13), (-1.0, 0.45 * sgn, 0.45), (-1.2, 0.45 * sgn, 0.45)], grey, 'tail'))
    L.finish(o, battle('e_drone_sea'), target=800, maxtex=256, center=True)


RECIPES = {f.__name__: f for f in [e_ship_escort, e_ship_tanker, e_ship_landing, a22_buoy_red, a23_buoy_green, e_ship_aa, e_ekranoplan, e_seaplane, e_ship_battery, e_drone_sea]}

if __name__ == '__main__':
    names = [a for a in A if not a.startswith('--')]
    for n in (RECIPES if names == ['all'] else names):
        RECIPES[n]()
