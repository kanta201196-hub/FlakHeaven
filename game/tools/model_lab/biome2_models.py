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


# ================= Берег и инфраструктура (game/models/biome2, наибольший размер по горизонтали = 1) =================
STONE = (0.80, 0.76, 0.66)      # известняк
WHITE = (0.90, 0.88, 0.83)      # побелка
TILE = (0.70, 0.36, 0.22)       # черепица
WOOD = (0.45, 0.33, 0.22)
CONCRETE = (0.62, 0.61, 0.58)


# ---------------- Т-1 береговая батарея: орудие (10 м) и бункер (25 м) ----------------
def a01_battery_gun():
    L.reset()
    o = L.load(src('T-1_gun_102mm.glb'))
    L.place(o, length=10)
    L.matte(o, 0.7)
    for m in L.mats(o):
        t = L.tex_of(m)
        if t:
            L.regrade(t, HULL, keep=0.6)
    red = L.flat('fh_red', RED, 0.6)
    mn, mx = L.bounds(o)
    # своё: красная крыша щита, бетонный дворик-кольцо с бруствером (позиция видна сверху)
    conc = L.flat('fh_concrete', CONCRETE, 0.95)
    o += [L.box((-0.5, 0, mx.z + 0.05), (3.2, 4.4, 0.12), red, 'roof'),
          L.cyl((-0.8, 0, 0.1), 6.2, 0.2, conc, 'pit_floor', seg=24),
          L.ring((-0.8, 0, 0), 6.8, 6.0, 1.1, conc, 'parapet')]
    L.finish(o, scenery('a01_battery_gun'), target=4000, maxtex=1024, fit='xy')


def a02_bunker_coast():
    L.reset()
    o = L.load(src('T-1_bunker.glb'))
    L.place(o, bow='-y', length=25)
    for m in L.mats(o):
        t = L.tex_of(m)
        if t:
            t.scale(2048, 2048)
            L.degraffiti(t)
    L.matte(o, 0.95)
    # своё: антенна связи и бруствер из мешков у входа — силуэт отличается от исходного бункера
    mn, mx = L.bounds(o)
    sand = L.flat('fh_sandbag', (0.66, 0.58, 0.42), 0.95)
    o += [L.cyl((2.0, 2.0, mx.z + 2.5), 0.12, 5.0, L.flat('fh_gun', GUN, 0.5, 0.4), 'antenna', seg=6)]
    for k in range(5):
        o.append(L.box((6.5, -3.0 + k * 1.2, mx.z - 2.2), (1.0, 1.15, 0.55), sand, 'sandbag'))
    L.finish(o, scenery('a02_bunker_coast'), target=8000, maxtex=2048, fit='xy')


# ---------------- Т-2 РЛС на решётчатой мачте (20 м, кодом) ----------------
def a03_radar_mast():
    L.reset()
    steel = L.flat('fh_steel', (0.55, 0.57, 0.58), 0.6, 0.3)
    conc = L.flat('fh_concrete', CONCRETE, 0.95)
    red = L.flat('fh_red', RED, 0.6)
    o = [L.box((0, 0, 0.15), (7.0, 7.0, 0.3), conc, 'pad'),
         L.box((-4.8, 0.0, 1.4), (3.0, 4.0, 2.8), L.flat('fh_hut', WHITE, 0.9), 'hut'),
         L.box((-4.8, 0.0, 2.9), (3.3, 4.3, 0.2), conc, 'hut_roof')]
    h = 16.0
    for sx in (-1, 1):   # четыре ноги, сходятся кверху
        for sy in (-1, 1):
            o.append(L.loft([[(sx * 2.0 - 0.15, sy * 2.0 - 0.15, 0.3), (sx * 2.0 + 0.15, sy * 2.0 - 0.15, 0.3),
                              (sx * 2.0 + 0.15, sy * 2.0 + 0.15, 0.3), (sx * 2.0 - 0.15, sy * 2.0 + 0.15, 0.3)],
                             [(sx * 0.7 - 0.1, sy * 0.7 - 0.1, h), (sx * 0.7 + 0.1, sy * 0.7 - 0.1, h),
                              (sx * 0.7 + 0.1, sy * 0.7 + 0.1, h), (sx * 0.7 - 0.1, sy * 0.7 + 0.1, h)]], steel, 'leg'))
    for k in range(1, 6):   # пояса и раскосы
        z = h * k / 6.0; w = 2.0 - 1.3 * k / 6.0
        for rz in (0, 90, 180, 270):
            r = math.radians(rz)
            c = Matrix.Rotation(r, 3, 'Z') @ Vector((w, 0, z))
            o.append(L.box(c, (0.1, 2 * w, 0.1), steel, 'belt', rz=r))
    o += [L.box((0, 0, h + 0.15), (2.2, 2.2, 0.3), steel, 'platform'),
          L.box((0, 0, h + 1.4), (0.5, 6.5, 1.8), L.flat('fh_radar', (0.85, 0.86, 0.86), 0.5), 'antenna', rz=math.radians(20)),
          L.cyl((0, 0, h + 0.8), 0.3, 1.0, steel, 'rotor', seg=8),
          L.cyl((0, 0, h + 3.0), 0.15, 0.3, red, 'beacon', seg=8)]
    L.finish(o, scenery('a03_radar_mast'), target=2500, fit='xy')


# ---------------- Т-3 маяк (25 м) с домиком смотрителя ----------------
def a04_lighthouse():
    L.reset()
    o = L.load(src('T-3_lighthouse.glb'))
    L.place(o, length=10)   # исходник в метрах: башня 25 м, основание 10 м
    o = L.drop(o, names=('Object_8',))   # ручка-«ворот» у подножия
    L.matte(o, 0.85)
    for m in L.mats(o):
        t = L.tex_of(m)
        if t:
            L.regrade(t, WHITE, keep=0.35)
        elif m.name.startswith('Concrete_material'):
            L.solid(m, WHITE)
        elif m.name.startswith('railings'):
            L.solid(m, (0.18, 0.18, 0.2))
    red = L.flat('fh_lh_red', (0.72, 0.15, 0.12), 0.6)
    # своё: красный купол фонаря, красный пояс, домик смотрителя с черепицей и двор
    tower = next(ob for ob in o if ob.name == 'Object_4')
    def rad(z):   # радиус башни на высоте z — пояс ложится на стену, а не «юбкой»
        return max((Vector((v.co.x, v.co.y)).length for v in tower.data.vertices if abs(v.co.z - z) < 0.6), default=4.0)
    o += [L.cyl((0.2, 0, 24.3), 2.0, 1.0, red, 'dome', seg=16, r2=0.5),
          L.cyl((0, 0, 9.0), rad(8.0) + 0.06, 2.0, red, 'band', seg=24, r2=rad(10.0) + 0.06)]
    o += [L.box((10.5, 0, 2.0), (8.0, 6.0, 4.0), L.flat('fh_white', WHITE, 0.9), 'house'),
          L.hull([(6.3, -3.2, 4.0), (14.7, -3.2, 4.0), (6.3, 3.2, 4.0), (14.7, 3.2, 4.0), (6.3, 0, 5.8), (14.7, 0, 5.8)],
                 L.flat('fh_tile', TILE, 0.85), 'roof'),
          L.box((8.0, 0, 0.08), (22.0, 14.0, 0.16), L.flat('fh_yard', (0.74, 0.70, 0.60), 0.95), 'yard'),
          L.box((8.0, 7.0, 0.5), (22.0, 0.4, 1.0), L.flat('fh_stone', STONE, 0.95), 'wall_n'),
          L.box((8.0, -7.0, 0.5), (22.0, 0.4, 1.0), L.flat('fh_stone', STONE, 0.95), 'wall_s')]
    L.finish(o, scenery('a04_lighthouse'), target=6000, maxtex=1024, fit='xy')


# ---------------- П-3 колокольня (15 м), без религиозных символов ----------------
def a20_bell_tower():
    L.reset()
    o = L.load(src('P-3_bell_tower.glb'))
    L.place(o, length=4.3)   # высота 34,6 → 15 м
    mn, mx = L.bounds(o)
    # шпиль на куполе (мог нести символ) — срезаем, вместо него простой шар
    o = L.kill_faces(o, lambda c, n: c.z > mx.z - 2.6 and Vector((c.x, c.y)).length < 0.3)
    m2 = L.bounds(o)[1]
    o.append(L.sphere((0, 0, m2.z + 0.15), 0.22, L.flat('fh_stone', STONE, 0.9), 'finial', seg=10))
    L.matte(o, 0.9)
    for m in L.mats(o):
        t = L.tex_of(m)
        if t:
            t.scale(1024, 1024)
            L.regrade(t, (0.86, 0.82, 0.72), keep=0.6)
    L.finish(o, scenery('a20_bell_tower'), target=5000, maxtex=1024, fit='xy')


# ---------------- Т-4 причалы (40 м) ----------------
def a05_pier_a():
    L.reset()
    o = L.load(src('T-4a_pier_simple.glb'))
    L.place(o, bow='+y', water=1.9)   # исходник в метрах, настил на 1,4 м над водой
    o = L.drop(o, names=('Cube.002_Baked*', 'Cylinder.001_Baked*'))   # щит-вывеска и верёвочные леера
    o = L.kill_faces(o, lambda c, n: c.z > 3.0)   # высокие столбы под вывеску — срезать по настил
    L.xform(o, Matrix.Scale(40.0 / 29.4, 4, Vector((1, 0, 0))))   # длиннее исходника, ширина прежняя
    L.matte(o, 0.9)
    # своё: швартовные тумбы и ящики на конце
    gun = GUNM()
    for x in (-16, -6, 4, 14):
        for y in (-2.6, 2.6):
            o.append(L.cyl((x, y, 1.65), 0.22, 0.5, gun, 'bollard', seg=8))
    o += [L.box((17.0, 1.2, 1.85), (1.4, 1.2, 0.9), L.flat('fh_crate', (0.50, 0.40, 0.26), 0.9), 'crate'),
          L.box((17.3, -1.0, 1.75), (1.0, 1.0, 0.7), L.flat('fh_crate', (0.50, 0.40, 0.26), 0.9), 'crate')]
    L.finish(o, scenery('a05_pier_a'), target=4000, maxtex=1024, fit='xy')


def a06_pier_b():
    L.reset()
    seg = L.load(src('T-4b_pier_old.glb'))
    L.place(seg, bow='+y', length=6.5)
    L.xform(seg, Matrix.Translation((0, 0, -1.2)))
    mn, mx = L.bounds(seg)
    L.matte(seg, 0.9)
    # старый причал на сваях с покрышками: секция 6,5 м × 6 = 39 м
    o = list(seg)
    for k in range(1, 6):
        for ob in seg:
            c = ob.copy(); c.data = ob.data.copy(); bpy.context.scene.collection.objects.link(c)
            c.data.transform(Matrix.Translation((k * (mx.x - mn.x) * 0.98, 0, 0)))
            o.append(c)
    L.xform(o, Matrix.Translation((-2.5 * (mx.x - mn.x), 0, 0)))
    L.finish(o, scenery('a06_pier_b'), target=6000, maxtex=1024, fit='xy')


# ---------------- Т-5 волнорез: тетрапод (4 м, ставится россыпью) ----------------
def a07_tetrapod():
    L.reset()
    o = L.load(src('T-5_tetrapod.glb'))
    o = L.drop(o, names=('Line001_Standardmaterial_0',))
    L.place(o, length=4.0)
    L.matte(o, 0.95)
    for m in L.mats(o):
        t = L.tex_of(m)
        if t:
            L.regrade(t, (0.70, 0.69, 0.65), keep=0.8)
    L.finish(o, scenery('a07_tetrapod'), target=1000, maxtex=512, fit='xy')


# ---------------- Т-6 склады у порта (30 м) ----------------
def a08_warehouse_a():
    L.reset()
    o = L.load(src('T-6a_warehouses.glb'))
    L.place(o, length=30)
    L.matte(o, 0.9)
    for m in L.mats(o):   # красный кирпич → охристая штукатурка, как в средиземноморских портах
        t = L.tex_of(m)
        if t:
            import numpy as np
            a = L.pixels(t)
            red = (a[..., 0] > a[..., 2] * 1.35)
            l = a[..., 0] * 0.3 + a[..., 1] * 0.59 + a[..., 2] * 0.11
            k = np.clip(l / max(1e-3, float(l[red].mean() if red.any() else 0.5)), 0.6, 1.3) ** 0.6
            for c, v in enumerate((0.80, 0.64, 0.44)):
                a[..., c] = np.where(red, np.clip(v * k, 0, 1), a[..., c])
            L.put_pixels(t, a)
    # своё: бочки и штабели ящиков у торца
    crate = L.flat('fh_crate', (0.50, 0.40, 0.26), 0.9)
    drum = L.flat('fh_drum', (0.25, 0.36, 0.30), 0.7)
    mn, mx = L.bounds(o)
    o += [L.box((mx.x + 1.8, -2.0, 0.6), (2.4, 2.4, 1.2), crate, 'crates'),
          L.box((mx.x + 1.8, 1.2, 0.45), (2.0, 2.0, 0.9), crate, 'crates')]
    for k in range(4):
        o.append(L.cyl((mx.x + 1.2 + (k % 2) * 1.0, mn.y + 1.0 + (k // 2) * 1.0, 0.45), 0.45, 0.9, drum, 'drum', seg=10))
    L.finish(o, scenery('a08_warehouse_a'), target=3500, maxtex=1024, fit='xy')


def a09_warehouse_b():
    L.reset()
    o = L.load(src('T-6b_warehouse.glb'))
    o = L.drop(o, names=('Object_3',))   # провода
    L.place(o, length=24)
    L.matte(o, 0.9)
    for m in L.mats(o):
        t = L.tex_of(m)
        if t:
            L.regrade(t, (0.80, 0.74, 0.60), keep=0.75)
    L.finish(o, scenery('a09_warehouse_b'), target=3500, maxtex=1024, fit='xy')


# ---------------- Т-7 портовый кран (30 м, ниже исходника) ----------------
def a10_crane():
    L.reset()
    o = L.load(src('T-7_port_crane.glb'))
    L.place(o, length=30)
    o = L.drop(o, keep=lambda ob: L.bounds([ob])[0].x < 13.5 or L.bounds([ob])[1].z > 19.0)   # трос и крюк
    L.xform(o, Matrix.Scale(0.75, 4, Vector((0, 0, 1))))   # по высоте ниже, как бункер Нагорья
    L.matte(o, 0.8)
    for m in L.mats(o):   # жёлтая стрела → светло-серая, красные ноги → тёмно-синие
        t = L.tex_of(m)
        if t:
            import numpy as np
            a = L.pixels(t)
            yel = (a[..., 0] > 0.45) & (a[..., 1] > 0.35) & (a[..., 2] < a[..., 1] * 0.6)
            red = (a[..., 0] > 0.35) & (a[..., 1] < a[..., 0] * 0.5) & (a[..., 2] < a[..., 0] * 0.5)
            l = a[..., 0] * 0.3 + a[..., 1] * 0.59 + a[..., 2] * 0.11
            for c, (vy, vr) in enumerate(((0.78, 0.22), (0.80, 0.32), (0.82, 0.46))):
                a[..., c] = np.where(yel, np.clip(vy * (0.6 + l * 0.6), 0, 1), np.where(red, np.clip(vr * (0.7 + l), 0, 1), a[..., c]))
            L.put_pixels(t, a)
    L.finish(o, scenery('a10_crane'), target=6000, maxtex=1024, fit='xy')


# ---------------- Т-8 руины крепости (20 м): три башни и стены между ними ----------------
def a11_tower_ruins():
    L.reset()
    o = L.load(src('T-8_towers_ruins.glb'))
    L.place(o, length=10)   # исходник: башни Ø10 в ряд
    for m in L.mats(o):
        t = L.tex_of(m)
        if t:
            t.scale(1024, 1024)
            L.regrade(t, STONE, keep=0.7)
    L.matte(o, 0.95)
    # башни ставим треугольником, высоту и размер уменьшаем (башня Ø6), между ними — стены с проломами
    pos = {'Object_3': (-5.5, 6.0), 'Object_2': (6.5, 0.0), 'Object_4': (-5.5, -6.0)}
    for ob in o:
        mn, mx = L.bounds([ob]); c = (mn + mx) / 2
        ob.data.transform(Matrix.Translation((pos[ob.name][0], pos[ob.name][1], 0)) @ Matrix.Scale(0.6, 4) @
                          Matrix.Translation((-c.x, -c.y, 0)))
    st = L.flat('fh_ruin_stone', (0.70, 0.66, 0.56), 0.95)
    def wall(a, b, h, gap=None):
        a, b = Vector(a), Vector(b); d = b - a; n = d.length; r = math.atan2(d.y, d.x)
        pieces = [(0.0, 1.0)] if gap is None else [(0.0, gap[0]), (gap[1], 1.0)]
        for t0, t1 in pieces:
            c = a + d * (t0 + t1) / 2
            o.append(L.box((c.x, c.y, h / 2), ((t1 - t0) * n, 1.4, h), st, 'wall', rz=r))
    wall((-5.5, 6.0), (6.5, 0.0), 5.0)
    wall((6.5, 0.0), (-5.5, -6.0), 3.5, gap=(0.45, 0.62))
    wall((-5.5, -6.0), (-5.5, 6.0), 4.2, gap=(0.3, 0.5))
    for k in range(9):   # осыпь камней у пролома
        o.append(L.box((1.6 + (k % 3) * 0.9, -3.4 + (k // 3) * 0.7, 0.3), (0.9, 0.7, 0.6), st, 'rubble', rz=k * 0.7))
    L.finish(o, scenery('a11_tower_ruins'), target=8000, maxtex=1024, fit='xy')


# ---------------- П-1, П-2 дома посёлка (8–14 м, кодом) ----------------
# Набор «Village on Stilts» оказался деревянными хижинами на сваях с жестяными крышами — к Средиземноморью
# не подходит, поэтому дома собраны кодом: белёные стены, плоская крыша с террасой или черепичная двускатная/вальмовая.
WALLS = [(0.93, 0.91, 0.86), (0.90, 0.86, 0.76), (0.92, 0.89, 0.82), (0.86, 0.78, 0.64)]
SHUT = [(0.22, 0.42, 0.36), (0.45, 0.30, 0.20), (0.30, 0.45, 0.50), (0.55, 0.40, 0.22)]


def _windows(o, x0, x1, y0, y1, floors, fh, shut, rng, door_side=None):
    win = L.flat('fh_window', (0.12, 0.13, 0.15), 0.4)
    sm = L.flat('fh_shutter_%d' % SHUT.index(shut), shut, 0.8)
    for f in range(floors):
        z = f * fh + fh * 0.58
        for side, (a, b, c, axis) in {'s': (x0, x1, y0, 'x'), 'n': (x0, x1, y1, 'x'), 'w': (y0, y1, x0, 'y'), 'e': (y0, y1, x1, 'y')}.items():
            n = max(1, int((b - a) / 3.4))
            for k in range(n):
                t = a + (b - a) * (k + 0.5) / n
                if f == 0 and side == door_side and k == n // 2:
                    if axis == 'x':
                        o.append(L.box((t, c, 1.1), (1.1, 0.16, 2.2), sm, 'door'))
                    else:
                        o.append(L.box((c, t, 1.1), (0.16, 1.1, 2.2), sm, 'door'))
                    continue
                if rng.random() < 0.12:
                    continue
                if axis == 'x':
                    o += [L.box((t, c, z), (0.8, 0.14, 1.1), win, 'win'),
                          L.box((t - 0.62, c, z), (0.4, 0.18, 1.1), sm, 'shut'), L.box((t + 0.62, c, z), (0.4, 0.18, 1.1), sm, 'shut')]
                else:
                    o += [L.box((c, t, z), (0.14, 0.8, 1.1), win, 'win'),
                          L.box((c, t - 0.62, z), (0.18, 0.4, 1.1), sm, 'shut'), L.box((c, t + 0.62, z), (0.18, 0.4, 1.1), sm, 'shut')]


def _house(name, w, d, floors, roof, seed, wing=None, extra=()):
    import random
    rng = random.Random(seed)
    L.reset()
    wall = L.flat('fh_wall_%d' % (seed % len(WALLS)), WALLS[seed % len(WALLS)], 0.9)
    tile = L.flat('fh_tile', TILE, 0.85)
    tile2 = L.flat('fh_tile2', (0.62, 0.32, 0.20), 0.85)
    trim = L.flat('fh_trim', (0.80, 0.77, 0.70), 0.9)
    shut = SHUT[seed % len(SHUT)]
    fh = 3.0
    h = floors * fh
    o = [L.box((0, 0, h / 2), (w, d, h), wall, 'block'),
         L.box((0, 0, 0.2), (w + 0.2, d + 0.2, 0.4), trim, 'plinth')]
    _windows(o, -w / 2 - 0.02, w / 2 + 0.02, -d / 2 - 0.02, d / 2 + 0.02, floors, fh, shut, rng, door_side='s')
    blocks = [(0, 0, w, d, h)]
    if wing:   # пристройка ниже на этаж: (dx, dy, w, d, этажей)
        dx, dy, ww, wd, wf = wing
        wh = wf * fh
        o += [L.box((dx, dy, wh / 2), (ww, wd, wh), wall, 'wing'), L.box((dx, dy, 0.2), (ww + 0.2, wd + 0.2, 0.4), trim, 'plinth')]
        _windows(o, dx - ww / 2 - 0.02, dx + ww / 2 + 0.02, dy - wd / 2 - 0.02, dy + wd / 2 + 0.02, wf, fh, shut, rng)
        blocks.append((dx, dy, ww, wd, wh))
    for bi, (cx, cy, bw, bd, bh) in enumerate(blocks):
        r = roof if bi == 0 else ('flat' if roof == 'flat' else 'flat_terrace')
        if r in ('flat', 'flat_terrace'):   # плоская крыша с парапетом; на главном — будка лестницы и навес
            o += [L.box((cx, cy, bh + 0.05), (bw + 0.1, bd + 0.1, 0.1), trim, 'roof')]
            for sx, sy, lx, ly in ((0, 1, bw + 0.1, 0.3), (0, -1, bw + 0.1, 0.3), (1, 0, 0.3, bd + 0.1), (-1, 0, 0.3, bd + 0.1)):
                o.append(L.box((cx + sx * bw / 2, cy + sy * bd / 2, bh + 0.45), (lx, ly, 0.7), wall, 'parapet'))
            if bi == 0:
                o += [L.box((cx - bw / 2 + 1.5, cy + bd / 2 - 1.5, bh + 1.2), (2.4, 2.4, 2.4), wall, 'stair_hut'),
                      L.box((cx - bw / 2 + 1.5, cy + bd / 2 - 1.5, bh + 2.45), (2.6, 2.6, 0.12), trim, 'stair_roof'),
                      L.cyl((cx + bw / 2 - 1.2, cy + bd / 2 - 1.2, bh + 0.75), 0.6, 1.3, L.flat('fh_tank', (0.25, 0.26, 0.27), 0.6), 'water_tank', seg=10)]
                if rng.random() < 0.7:   # навес-пергола из жердей с виноградом
                    green = L.flat('fh_vine', (0.36, 0.48, 0.24), 0.95)
                    o.append(L.box((cx + bw / 4, cy - bd / 4, bh + 2.3), (bw / 2.2, bd / 2.2, 0.15), green, 'pergola'))
                    for px in (-1, 1):
                        for py in (-1, 1):
                            o.append(L.box((cx + bw / 4 + px * bw / 4.6, cy - bd / 4 + py * bd / 4.6, bh + 1.15), (0.15, 0.15, 2.3), L.flat('fh_wood', WOOD, 0.9), 'post'))
        else:   # черепица: двускатная (gable) или вальмовая (hip), свес 0,4 м
            ov = 0.45; rh = min(bw, bd) * 0.32
            x0, x1, y0, y1 = cx - bw / 2 - ov, cx + bw / 2 + ov, cy - bd / 2 - ov, cy + bd / 2 + ov
            if bw >= bd:
                ridge = [(x0 if r == 'gable' else cx - bw / 2 + bd / 2, cy, bh + rh), (x1 if r == 'gable' else cx + bw / 2 - bd / 2, cy, bh + rh)]
            else:
                ridge = [(cx, y0 if r == 'gable' else cy - bd / 2 + bw / 2, bh + rh), (cx, y1 if r == 'gable' else cy + bd / 2 - bw / 2, bh + rh)]
            o.append(L.hull([(x0, y0, bh - 0.1), (x1, y0, bh - 0.1), (x0, y1, bh - 0.1), (x1, y1, bh - 0.1)] + ridge,
                            tile if (seed + bi) % 2 == 0 else tile2, 'roof'))
            if r == 'gable':   # фронтоны
                pass
            if bi == 0:
                o.append(L.box((cx + bw / 4, cy + bd / 5, bh + rh * 0.8), (0.7, 0.7, rh * 1.4), wall, 'chimney'))
    for e in extra:
        e(o, w, d, h, rng)
    L.finish(o, scenery(name), target=3000, fit='xy')


def _balcony(o, w, d, h, rng):
    o += [L.box((0, -d / 2 - 0.7, 3.0), (w * 0.5, 1.4, 0.15), L.flat('fh_trim', (0.80, 0.77, 0.70), 0.9), 'balcony'),
          L.box((0, -d / 2 - 1.35, 3.55), (w * 0.5, 0.08, 0.9), L.flat('fh_rail', (0.2, 0.2, 0.22), 0.6), 'rail')]


def _yard(o, w, d, h, rng):   # дворик с каменной оградой и деревцем в кадке
    st = L.flat('fh_stone', STONE, 0.95)
    o += [L.box((w / 2 + 2.0, 0, 0.6), (0.4, d, 1.2), st, 'yard_wall'),
          L.box((w / 4 + 1.0, d / 2 - 0.2, 0.6), (w / 2 + 2.0, 0.4, 1.2), st, 'yard_wall'),
          L.box((w / 4 + 1.0, -d / 2 + 0.2, 0.6), (w / 2 + 2.0, 0.4, 1.2), st, 'yard_wall'),
          L.sphere((w / 2 + 0.8, d / 4, 2.2), 1.3, L.flat('fh_vine', (0.36, 0.48, 0.24), 0.95), 'tree', seg=8),
          L.cyl((w / 2 + 0.8, d / 4, 0.8), 0.15, 1.6, L.flat('fh_wood', WOOD, 0.9), 'trunk', seg=6)]


def a12_house_1():
    _house('a12_house_1', 8, 7, 1, 'flat', 1)


def a13_house_2():
    _house('a13_house_2', 10, 8, 2, 'flat', 2, extra=(_balcony,))


def a14_house_3():
    _house('a14_house_3', 9, 7, 2, 'flat', 3, wing=(6.5, -1.0, 4.0, 5.0, 1))


def a15_house_4():
    _house('a15_house_4', 8, 6, 1, 'gable', 4, extra=(_yard,))


def a16_house_5():
    _house('a16_house_5', 11, 8, 2, 'hip', 5, extra=(_balcony,))


def a17_house_6():
    _house('a17_house_6', 9, 8, 2, 'gable', 6, wing=(-6.5, 1.5, 4.0, 5.0, 1))


def a18_house_7():
    _house('a18_house_7', 12, 9, 3, 'hip', 7)


def a19_house_8():
    _house('a19_house_8', 7, 7, 1, 'hip', 8, extra=(_yard,))


# ---------------- П-4 стена террасы, сухая кладка (10 м, кодом) ----------------
def a21_terrace_wall():
    import random
    rng = random.Random(21)
    L.reset()
    o = []
    mats = [L.flat('fh_dry_%d' % k, c, 0.95) for k, c in enumerate(((0.74, 0.70, 0.60), (0.68, 0.63, 0.53), (0.80, 0.76, 0.66)))]
    z = 0.0
    for row in range(4):   # ряды камней разного размера, с лёгким наклоном внутрь
        x = -5.0 + rng.random() * 0.4
        hgt = 0.35 + rng.random() * 0.15
        while x < 5.0:
            lw = min(0.5 + rng.random() * 0.7, 5.0 - x)
            o.append(L.box((x + lw / 2, -row * 0.06, z + hgt / 2), (lw - 0.04, 0.7 - row * 0.05, hgt), rng.choice(mats), 'stone',
                           rz=(rng.random() - 0.5) * 0.08))
            x += lw
        z += hgt
    o.append(L.box((0, 0.65, z / 2), (10.0, 0.7, z), L.flat('fh_soil', (0.55, 0.45, 0.32), 1.0), 'fill'))
    L.finish(o, scenery('a21_terrace_wall'), target=1500, fit='xy')


# ================= Вода и мелочь =================
def _hue_map(img, rules):
    """Перекраска по цвету: rules — [(условие(r,g,b) → маска, новый rgb)], яркость сохраняется."""
    import numpy as np
    a = L.pixels(img)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    l = r * 0.3 + g * 0.59 + b * 0.11
    for cond, rgb in rules:
        m = cond(r, g, b)
        k = np.clip(l / max(1e-3, float(l[m].mean()) if m.any() else 0.5), 0.5, 1.4)
        for i in range(3):
            a[..., i] = np.where(m, np.clip(rgb[i] * k, 0, 1), a[..., i])
    L.put_pixels(img, a)


# ---------------- М-2 рыбацкие лодки ----------------
def a24_boat_a():
    L.reset()
    o = L.load(src('M-2a_fishing_boat.glb'))
    L.place(o, bow='+x', length=10)
    L.xform(o, Matrix.Translation((0, 0, -0.9)))
    o = L.kill_parts(o, lambda mn, mx, n: mx.z - mn.z > 2.0 and mx.x - mn.x < 0.25 and mx.y - mn.y < 0.25)   # тонкие стрелы-удочки
    L.matte(o, 0.8)
    for m in L.mats(o):   # красно-белая окраска → бирюзовый корпус с охристой рубкой (местная гамма)
        t = L.tex_of(m)
        if t:
            _hue_map(t, [(lambda r, g, b: (r > g * 1.6) & (r > b * 1.6) & (r > 0.25), (0.16, 0.48, 0.50))])
    L.finish(o, scenery('a24_boat_a'), target=4000, maxtex=1024, fit='xy')


def a25_boat_b():
    L.reset()
    o = L.load(src('M-2b_fishing_boat.glb'))
    L.place(o, bow='+y', length=5.0)
    L.xform(o, Matrix.Translation((0, 0, -0.2)))
    L.matte(o, 0.85)
    # своё: мачта с убранным парусом — лодка отличается от исходной вёсельной
    wood = L.flat('fh_wood', WOOD, 0.9)
    o += [L.cyl((0.9, 0, 1.7), 0.06, 3.0, wood, 'mast', seg=6),
          L.cyl((0.1, 0, 0.7), 0.12, 1.8, L.flat('fh_sail', (0.86, 0.80, 0.66), 0.95), 'sail_furled', seg=6, axis='X')]
    L.finish(o, scenery('a25_boat_b'), target=2500, maxtex=1024, fit='xy')


# ---------------- М-3 остовы на мели (сканы, сильно упрощены) ----------------
def a26_wreck_a():
    L.reset()
    o = L.load(src('M-3a_wreck_small.glb'))
    L.place(o, length=30)
    # песчаное дно под остовом (скан стоит с наклоном): плоскость по всем точкам, грани у самой плоскости — убрать
    import numpy as np
    P = np.array([tuple(v.co) for ob in o for v in ob.data.vertices])
    A = np.c_[P[:, 0], P[:, 1], np.ones(len(P))]
    k = np.linalg.lstsq(A, P[:, 2], rcond=None)[0]
    o = L.kill_faces(o, lambda c, n: c.z - (k[0] * c.x + k[1] * c.y + k[2]) < 0.7)
    o = L.kill_parts(o, lambda mn, mx, n: n < 60)   # оторванные крошки скана
    L.place(o)
    L.xform(o, Matrix.Translation((0, 0, -0.6)))
    L.matte(o, 0.95)
    for m in L.mats(o):
        t = L.tex_of(m)
        if t:
            t.scale(2048, 2048)
    L.finish(o, scenery('a26_wreck_a'), target=7000, maxtex=1024, fit='xy')


def a27_wreck_b():
    L.reset()
    o = L.load(src('M-3b_wreck_ship.glb'))
    L.place(o, bow='+y', length=80)
    L.xform(o, Matrix.Translation((0, 0, -2.5)))   # нижняя часть борта под водой
    L.matte(o, 0.9)
    for m in L.mats(o):
        t = L.tex_of(m)
        if t:
            t.scale(2048, 2048)
            L.degraffiti(t, sat=0.35)   # надписи и полосы на борту
    L.finish(o, scenery('a27_wreck_b'), target=9000, maxtex=1024, fit='xy')


# ---------------- М-4 обломки самолёта на воде (из b11 Нагорья) ----------------
def a28_wreck_plane_sea():
    L.reset()
    o = L.load(os.path.join(MODELS, 'biome', 'b11_wreck_plane.glb'))
    L.place(o, length=15)
    L.xform(o, Matrix.Translation((0, 0, -0.5)) @ Matrix.Rotation(math.radians(4), 4, 'X'))   # осел в воду, лёгкий крен
    for m in L.mats(o):   # мокрый — темнее
        t = L.tex_of(m)
        if t:
            import numpy as np
            a = L.pixels(t); a[..., :3] *= 0.72; L.put_pixels(t, a)
    L.finish(o, scenery('a28_wreck_plane_sea'), target=4000, maxtex=1024, fit='xy')


# ---------------- М-5 противодесантный ёж (2 м) ----------------
def a29_hedgehog():
    L.reset()
    o = L.load(src('M-5_hedgehog.glb'))
    L.place(o, length=2.0)
    L.matte(o, 0.8)
    for m in L.mats(o):
        t = L.tex_of(m)
        if t:
            L.regrade(t, (0.42, 0.26, 0.17), keep=0.8)
    L.finish(o, scenery('a29_hedgehog'), target=900, maxtex=512, fit='xy')


# ---------------- М-6 бон с сетью у входа в бухту (40 м, кодом) ----------------
def a30_boom_net():
    L.reset()
    fl = L.flat('fh_float', (0.86, 0.50, 0.14), 0.7)
    dark = L.flat('fh_net', (0.18, 0.19, 0.2), 0.8)
    o = []
    for k in range(17):   # поплавки-бочки через 2,5 м, трос между ними, сеть уходит под воду
        x = -20 + k * 2.5
        o.append(L.cyl((x, 0, 0.05), 0.45, 1.3, fl, 'float', seg=10, axis='Y'))
    o += [L.box((0, 0, 0.3), (40.0, 0.08, 0.08), dark, 'cable'),
          L.box((0, 0, -1.0), (40.0, 0.04, 2.0), dark, 'net'),
          L.cyl((-20.8, 0, 0.6), 0.7, 2.0, L.flat('fh_red', RED, 0.6), 'end_buoy', seg=10),
          L.cyl((20.8, 0, 0.6), 0.7, 2.0, L.flat('fh_red', RED, 0.6), 'end_buoy', seg=10)]
    L.finish(o, scenery('a30_boom_net'), target=1500, fit='xy')


# ================= Природа: известняк, оливы, сосны =================
def _limestone(objs, rgb=STONE, keep=0.8):
    L.matte(objs, 0.95)
    for m in L.mats(objs):
        t = L.tex_of(m)
        if t:
            if max(t.size) > 2048:
                t.scale(2048, 2048)
            L.regrade(t, rgb, keep=keep)


def a31_cliff_a():
    L.reset()
    o = L.load(src('N-1a_cliff.glb'))
    L.place(o, length=60)
    _limestone(o, (0.54, 0.51, 0.44), keep=0.9)   # тёмный базальт → светлый известняк
    L.finish(o, scenery('a31_cliff_a'), target=5000, maxtex=1024, fit='xy')


def a32_cliff_b():
    L.reset()
    o = L.load(src('N-1c_cliff_rock.glb'))
    L.place(o, length=30)
    L.xform(o, Matrix.Scale(0.55, 4, Vector((0, 0, 1))))   # скала-столб ниже — как обрыв над водой, а не шпиль
    _limestone(o, (0.68, 0.64, 0.55))
    L.finish(o, scenery('a32_cliff_b'), target=5000, maxtex=1024, fit='xy')


def a33_rock():
    L.reset()
    o = L.load(src('N-1b_rock.glb'))
    L.place(o, bow='-y', length=40)
    _limestone(o, (0.64, 0.60, 0.52), keep=0.45)
    L.finish(o, scenery('a33_rock'), target=4000, maxtex=1024, fit='xy')


OLIVE = (0.47, 0.53, 0.38)


def _tree(name, path, leaf_names, height, n, seed, crown_rgb, trunk_target=900, flat=0.75):
    L.reset()
    o = L.load(src(path))
    L.place(o)
    mn, mx = L.bounds(o)
    L.xform(o, Matrix.Scale(height / (mx.z - mn.z), 4))
    leaves = [ob for ob in o if any(ob.data.materials and ob.data.materials[0].name.startswith(k) for k in leaf_names)]
    trunk = [ob for ob in o if ob not in leaves]
    L.matte(trunk, 0.95)
    for m in L.mats(trunk):
        t = L.tex_of(m)
        if t and max(t.size) > 1024:
            t.scale(1024, 1024)
    L.budget(trunk, trunk_target)
    cr = L.crown(leaves, L.flat('fh_crown_' + name, crown_rgb, 0.95), n=n, seed=seed, flat=flat, seg=12)
    L.smooth(cr, 80)
    for ob in leaves:
        bpy.data.objects.remove(ob)
    L.finish(trunk + cr, scenery(name), target=trunk_target + n * 120, maxtex=1024, fit='xy')


def a34_olive_a():
    _tree('a34_olive_a', 'N-2a_olive.glb', ('OliveSingleLeaf', 'OliveLeaf'), 7.0, 12, 34, OLIVE)


def a35_olive_b():
    _tree('a35_olive_b', 'N-2b_olive_old.glb', ('olive-leaves',), 6.0, 11, 35, (0.50, 0.55, 0.40))


def a36_pine_a():
    """Пиния (сосна «зонтиком», кодом): голый наклонный ствол, плоская широкая крона из нескольких «подушек»."""
    import random
    rng = random.Random(36)
    L.reset()
    bark = L.flat('fh_pine_bark', (0.42, 0.32, 0.24), 0.95)
    green = L.flat('fh_pine_crown', (0.27, 0.40, 0.22), 0.95)
    o = [L.cyl((0.4, 0, 4.0), 0.35, 8.0, bark, 'trunk', seg=8, r2=0.22, rot=Matrix.Rotation(math.radians(6), 3, 'Y')),
         L.cyl((1.4, 0.4, 7.4), 0.14, 2.6, bark, 'branch', seg=6, rot=Matrix.Rotation(math.radians(50), 3, 'Y')),
         L.cyl((-0.4, -0.5, 7.6), 0.14, 2.4, bark, 'branch', seg=6, rot=Matrix.Rotation(math.radians(-45), 3, 'X'))]
    for k in range(7):
        a = k / 7 * 2 * math.pi + rng.random() * 0.4
        rr = 0 if k == 0 else 2.6 + rng.random()
        sph = L.sphere((0.9 + rr * math.cos(a), rr * math.sin(a), 8.6 + rng.random() * 0.6), 2.6, green, 'pad', seg=10,
                       scale=(1.0, 1.0, 0.38))
        for v in sph.data.vertices:
            v.co += Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.5, 0.5))) * 0.25
        o.append(sph)
    L.finish(o, scenery('a36_pine_a'), target=2000, fit='xy')


def a37_pine_b():
    """Кипарис из средней ели набора N-3b: уже и темнее."""
    L.reset()
    o = L.load(src('N-3b_pine_pack.glb'))
    L.place(o)
    mid = [ob for ob in o if abs((L.bounds([ob])[0].x + L.bounds([ob])[1].x) / 2) < 3.0]
    for ob in o:
        if ob not in mid:
            bpy.data.objects.remove(ob)
    o = mid
    L.place(o)
    mn, mx = L.bounds(o)
    L.xform(o, Matrix.Scale(10.0 / (mx.z - mn.z), 4) )
    L.xform(o, Matrix.Scale(0.55, 4, Vector((1, 0, 0))) @ Matrix.Scale(0.55, 4, Vector((0, 1, 0))))
    L.matte(o, 0.95)
    for m in L.mats(o):
        t = L.tex_of(m)
        if t:
            L.regrade(t, (0.22, 0.33, 0.20), keep=0.8)
    L.finish(o, scenery('a37_pine_b'), target=600, maxtex=512, fit='xy')


def a38_tree_leaf():
    L.reset()
    o = L.load(src('N-3a_leaf_tree.glb'))
    L.place(o)
    mn, mx = L.bounds(o)
    L.xform(o, Matrix.Scale(9.0 / (mx.z - mn.z), 4))
    L.matte(o, 0.95)
    L.finish(o, scenery('a38_tree_leaf'), target=1800, maxtex=512, fit='xy')


# ---------------- Н-4 камыш (кодом) и куст (перекраска b06 Нагорья) ----------------
def a39_reed():
    import random
    rng = random.Random(39)
    L.reset()
    mats = [L.flat('fh_reed_%d' % k, c, 0.95) for k, c in enumerate(((0.55, 0.56, 0.32), (0.62, 0.58, 0.36), (0.45, 0.50, 0.28)))]
    o = []
    for k in range(26):   # пучок стеблей, наклонённых наружу, метёлки сверху
        a = rng.random() * 2 * math.pi; r = rng.random() * 0.9
        h = 1.4 + rng.random() * 0.9
        tilt = Matrix.Rotation(r * 0.35, 3, Vector((-math.sin(a), math.cos(a), 0)))
        base = Vector((r * math.cos(a), r * math.sin(a), 0))
        top = base + tilt @ Vector((0, 0, h))
        o.append(L.cyl(tuple((base + top) / 2), 0.03, h, rng.choice(mats), 'stem', seg=4, rot=tilt))
        if rng.random() < 0.6:
            o.append(L.cyl(tuple(top), 0.06, 0.3, mats[1], 'tuft', seg=4, rot=tilt))
    L.finish(o, scenery('a39_reed'), target=1200, fit='xy')


def a40_shrub():
    L.reset()
    o = L.load(os.path.join(MODELS, 'biome', 'b06_shrub.glb'))
    L.place(o)
    for m in L.mats(o):   # маквис: серо-зелёный, суше, чем куст Нагорья
        t = L.tex_of(m)
        if t:
            L.regrade(t, (0.45, 0.50, 0.34), keep=0.8)
    L.finish(o, scenery('a40_shrub'), target=900, maxtex=512, fit='xy')


# ================= Боссы =================
# ---------------- Б-1 летающая лодка «Альбатрос» (45 м): четыре мотора на крыле, турели во все стороны ----------------
def e_albatross():
    L.reset()
    o = L.load(src('B-1_flying_boat.glb'))
    L.place(o, bow='-x', length=45)
    # внутренности (ящики, патроны), два винта над корпусом, тросы-расчалки — убрать
    o = L.drop(o, names=('Cube.016_box_mat*', 'Cube.016_ammo*', 'Cube.019*', 'Cube.020*', 'Icosphere*', 'Cube.015*', 'Cube.014*'))
    o = L.kill_parts(o, lambda mn, mx, n: sorted(mx - mn)[1] < 0.35)
    # оставшиеся расчалки от хвоста к крылу: всё между крылом и оперением вне корпуса и балок
    o = L.kill_faces(o, lambda c, n: -19.5 < c.x < 0.3 and abs(c.y) > 3.2 and not (9.3 < abs(c.y) < 11.3))
    L.matte(o, 0.7)
    for m in L.mats(o):
        t = L.tex_of(m)
        if t:
            t.scale(2048, 2048)
            L.regrade(t, (0.60, 0.62, 0.64), keep=0.25, lo=0.75, hi=1.15)
    grey = L.flat('fh_alb_grey', (0.52, 0.54, 0.57), 0.65)
    dark = L.flat('fh_alb_dark', (0.12, 0.13, 0.15), 0.4)
    red = L.flat('fh_red', RED, 0.6)
    sup = L.flat('fh_super', SUPER, 0.7)
    for y in (-16.0, -8.0, 8.0, 16.0):   # мотогондолы на передней кромке крыла
        o += [L.cyl((6.5, y, 9.4), 1.15, 9.0, grey, 'nacelle', seg=14, r2=0.85, axis='X'),
              L.cyl((11.3, y, 9.4), 0.6, 0.9, red, 'spinner', seg=10, axis='X', r2=0.08),
              L.cyl((11.0, y, 9.4), 3.0, 0.08, dark, 'prop_disc', seg=18, axis='X')]
    # турели: носовая, две на спине, хвостовая между балками
    o += gun_mount(18.5, 0, 5.6, 1.1, sup, red, barrels=2, blen=2.4, name='nose_turret')
    o += gun_mount(13.0, 0, 6.6, 1.2, sup, red, barrels=2, blen=2.6, name='dorsal_1', rz=math.radians(30))
    o += gun_mount(-6.0, 0, 6.6, 1.2, sup, red, barrels=2, blen=2.6, name='dorsal_2', rz=math.radians(160))
    o += gun_mount(-21.0, 0, 8.6, 1.0, sup, red, barrels=2, blen=2.2, name='tail_turret', rz=math.pi)
    L.finish(o, battle('e_albatross'), target=15000, maxtex=2048, center=True)


# ---------------- Б-3 «Левиафан» и его части — в b2_leviathan.py (переделка по замечаниям Kanta 19.10) ----------------
from b2_leviathan import e_leviathan, e_lev_turret, e_lev_launcher, e_lev_radar, e_lev_zsu   # noqa: E402


# ---------------- К-1 балкер (120 м, кодом по форме K-1: исходник 1,6 млн треуг. из сотен деталей) ----------------
def _bulk_ring(x, b, zb, z0, z1):
    """Сечение корпуса между высотами z0..z1: плоское днище zb, скула, борт."""
    ch = min(1.6, b * 0.45)
    lo = max(zb, z0)
    if zb >= z0:
        return [(x, -b, lo), (x, b, lo), (x, b, z1), (x, -b, z1)]
    return [(x, -b + ch, zb), (x, b - ch, zb), (x, b, min(zb + ch, z1)), (x, b, z1), (x, -b, z1), (x, -b, min(zb + ch, z1))]


def e_ship_bulk():
    L.reset()
    black = L.flat('fh_bulk_black', (0.11, 0.11, 0.12), 0.8)
    bottom = L.flat('fh_bulk_bottom', (0.45, 0.13, 0.10), 0.85)
    deck_m = L.flat('fh_bulk_deck', (0.42, 0.22, 0.17), 0.9)
    hatch = L.flat('fh_bulk_hatch', (0.60, 0.50, 0.32), 0.8)      # крышки трюмов охристые, не красные как у исходника
    coam = L.flat('fh_bulk_coaming', (0.34, 0.20, 0.16), 0.9)
    hatch_dk = L.flat('fh_bulk_hatch_dk', (0.50, 0.41, 0.26), 0.85)
    rail = L.flat('fh_bulk_rail', (0.75, 0.75, 0.73), 0.7)
    white = L.flat('fh_bulk_white', (0.86, 0.86, 0.84), 0.7)
    win = L.flat('fh_window', (0.12, 0.16, 0.2), 0.3)
    crane_m = L.flat('fh_bulk_crane', (0.80, 0.62, 0.18), 0.7)   # жёлтые грузовые краны — свои, у исходника их нет
    red = L.flat('fh_red', RED, 0.6)
    # станции корпуса: x, полуширина, днище, палуба (нос с подъёмом и развалом, корма — транец)
    st = [(-60.0, 7.4, 1.2, 9.0), (-58.0, 8.8, -1.5, 8.6), (-52.0, 9.5, -3.0, 8.0), (36.0, 9.5, -3.0, 8.0),
          (45.0, 9.0, -3.0, 8.2), (51.0, 7.4, -2.9, 8.7), (55.5, 5.0, -2.4, 9.3), (58.5, 2.6, -1.4, 9.9),
          (60.0, 0.6, 0.0, 10.2)]
    BOOT = 0.7
    o = [L.loft([_bulk_ring(x, b, zb, -9, BOOT) for x, b, zb, zd in st if zb < BOOT], bottom, 'hull_low'),
         L.loft([_bulk_ring(x, b, zb, BOOT, zd) for x, b, zb, zd in st], black, 'hull_top'),
         L.loft([[(x, -b + 0.35, zd - 0.1), (x, b - 0.35, zd - 0.1), (x, b - 0.35, zd + 0.06), (x, -b + 0.35, zd + 0.06)]
                 for x, b, zb, zd in st[:-1]], deck_m, 'deck')]
    # бак: фальшборт и полубак на носу
    o.append(L.hull([(47, -8.6, 8.0), (47, 8.6, 8.0), (58.6, -2.4, 9.9), (58.6, 2.4, 9.9),
                     (47, -8.6, 9.6), (47, 8.6, 9.6), (58.6, -2.4, 11.0), (58.6, 2.4, 11.0)], deck_m, 'forecastle'))
    o.append(L.cyl((53.0, 0, 11.3), 0.7, 0.6, GUNM(), 'windlass', seg=10, axis='Y'))
    o.append(L.cyl((55.0, 0, 13.5), 0.18, 5.0, white, 'fore_mast', seg=8))
    # пять трюмов (у исходника семь): комингс + двускатная крышка
    for i, x in enumerate((36.0, 20.5, 5.0, -10.5, -26.0)):
        o.append(L.box((x, 0, 8.6), (12.6, 13.0, 1.3), coam, 'coaming'))
        o.append(L.hull([(x - 6.0, -6.2, 9.25), (x + 6.0, -6.2, 9.25), (x - 6.0, 6.2, 9.25), (x + 6.0, 6.2, 9.25),
                         (x - 6.0, -5.6, 9.7), (x + 6.0, -5.6, 9.7), (x - 6.0, 5.6, 9.7), (x + 6.0, 5.6, 9.7),
                         (x - 6.0, 0, 10.3), (x + 6.0, 0, 10.3)], hatch, 'hatch'))
        o.append(L.box((x, 0, 10.3), (12.0, 0.25, 0.12), coam, 'hatch_seam'))
        for r in range(-5, 6, 2):                      # рёбра жёсткости поперёк крышки
            o.append(L.box((x + r * 1.0, 0, 9.85), (0.18, 12.0, 0.5), hatch_dk, 'hatch_rib'))
        for y in (-7.2, 7.2):                          # вентиляторы трюма у комингса
            o.append(L.cyl((x + 5.0, y, 8.9), 0.35, 1.6, white, 'vent', seg=8))
    # четыре палубных крана между трюмами: тумба, кабина, стрела к корме под углом
    for k, x in enumerate((28.25, 12.75, -2.75, -18.25)):
        y = 3.2 if k % 2 == 0 else -3.2
        o += [L.cyl((x, y, 10.0), 1.1, 4.0, crane_m, 'crane_post', seg=10),
              L.box((x, y, 12.9), (2.8, 2.4, 2.0), crane_m, 'crane_cab'),
              L.box((x + 0.9, y, 13.2), (0.15, 1.6, 0.8), win, 'crane_win')]
        ang = math.radians(9)
        jl = 15.0     # стрела уложена к корме, как у стоящего у причала судна
        rot = Matrix.Rotation(math.radians(180), 3, 'Z') @ Matrix.Rotation(-ang, 3, 'Y')
        o.append(L.cyl((x - math.cos(ang) * jl / 2, y, 13.0 + math.sin(ang) * jl / 2), 0.32, jl, crane_m, 'crane_jib', seg=6, axis='X', rot=rot))
        o.append(L.box((x - 13.0, y, 11.2), (0.4, 0.4, 2.6), crane_m, 'jib_rest'))
    # кормовая надстройка: 5 ярусов, крылья мостика, своя труба (наклонная, с красным поясом)
    xs = -47.0
    for lv in range(5):
        w = 15.0 if lv < 4 else 18.6
        o.append(L.box((xs, 0, 10.0 + lv * 2.6), (9.0 - lv * 0.4, w if lv == 4 else w - lv * 0.4, 2.5), white, 'house'))
        o.append(L.box((xs + 4.55 - lv * 0.2, 0, 10.3 + lv * 2.6), (0.12, w - 2.0 - lv * 0.4, 0.8), win, 'house_win'))
    o.append(L.box((xs, 0, 22.5), (6.0, 11.0, 0.4), white, 'bridge_roof'))
    o.append(L.cyl((xs + 1.0, 0, 25.5), 0.2, 6.0, white, 'mast', seg=8))
    o.append(L.box((xs + 1.0, 0, 26.0), (0.6, 3.4, 0.25), white, 'yard'))
    o.append(L.box((xs + 1.0, 0, 27.2), (0.9, 2.6, 0.35), GUNM(), 'radar'))
    o.append(L.hull([(xs - 9.5, -2.0, 10.0), (xs - 9.5, 2.0, 10.0), (xs - 4.5, -2.0, 10.0), (xs - 4.5, 2.0, 10.0),
                     (xs - 10.5, -1.7, 21.0), (xs - 10.5, 1.7, 21.0), (xs - 7.0, -1.7, 21.0), (xs - 7.0, 1.7, 21.0)], white, 'funnel'))
    o.append(L.hull([(xs - 10.3, -1.75, 18.0), (xs - 10.3, 1.75, 18.0), (xs - 6.6, -1.75, 18.0), (xs - 6.6, 1.75, 18.0),
                     (xs - 10.55, -1.8, 19.5), (xs - 10.55, 1.8, 19.5), (xs - 6.95, -1.8, 19.5), (xs - 6.95, 1.8, 19.5)], red, 'funnel_band'))
    o.append(L.box((xs - 8.75, 0, 21.1), (3.2, 3.1, 0.2), GUNM(), 'funnel_top'))
    # шлюпки по бортам надстройки (оранжевые), кнехты на корме
    for y in (-8.2, 8.2):
        o.append(L.cyl((xs + 1.0, y, 13.2), 1.1, 6.5, L.flat('fh_raft', (0.85, 0.45, 0.12), 0.8), 'lifeboat', seg=10, axis='X'))
        for x in (-57.0, 44.0):
            o.append(L.cyl((x, y * 0.95, 8.4), 0.35, 0.8, GUNM(), 'bollard', seg=8))
    # леера по бортам, трубопровод вдоль палубы, люки и поперечные переходы
    for x0, x1, b in ((-56.0, 36.0, 9.25), (36.0, 46.5, 8.9)):
        for y in (-b, b):
            o.append(L.box(((x0 + x1) / 2, y, 8.55), (x1 - x0, 0.08, 0.08), rail, 'rail'))
            for xp in range(int(x0), int(x1), 4):
                o.append(L.box((xp, y, 8.3), (0.08, 0.08, 0.6), rail, 'stanchion'))
    o.append(L.cyl((4.0, -7.6, 8.35), 0.22, 78.0, L.flat('fh_bulk_pipe', (0.30, 0.42, 0.30), 0.7), 'pipe', seg=6, axis='X'))
    for x in (28.25, 12.75, -2.75, -18.25):
        o.append(L.box((x, 0, 8.2), (1.2, 18.0, 0.25), coam, 'walkway'))
    for lv in range(4):                                # иллюминаторы по бортам надстройки
        for y in (-7.52 + lv * 0.2, 7.52 - lv * 0.2):
            o.append(L.box((xs, y, 10.3 + lv * 2.6), (6.0 - lv * 0.4, 0.06, 0.6), win, 'side_win'))
    L.smooth([ob for ob in o if ob.name.startswith('hull')], 40)
    L.finish(o, battle('e_ship_bulk'), target=12000, maxtex=1024)


RECIPES = {f.__name__: f for f in [e_ship_bulk, e_ship_escort, e_ship_tanker, e_ship_landing, a22_buoy_red, a23_buoy_green, e_ship_aa, e_ekranoplan, e_seaplane, e_ship_battery, e_drone_sea,
                                    a01_battery_gun, a02_bunker_coast, a03_radar_mast, a04_lighthouse, a20_bell_tower,
                                    a05_pier_a, a06_pier_b, a07_tetrapod, a08_warehouse_a, a09_warehouse_b, a10_crane, a11_tower_ruins,
                                    a12_house_1, a13_house_2, a14_house_3, a15_house_4, a16_house_5, a17_house_6,
                                    a18_house_7, a19_house_8, a21_terrace_wall,
                                    a24_boat_a, a25_boat_b, a26_wreck_a, a27_wreck_b, a28_wreck_plane_sea, a29_hedgehog,
                                    a30_boom_net, a31_cliff_a, a32_cliff_b, a33_rock, a34_olive_a, a35_olive_b, a36_pine_a,
                                    a37_pine_b, a38_tree_leaf, a39_reed, a40_shrub, e_albatross,
                                    e_leviathan, e_lev_turret, e_lev_launcher, e_lev_radar, e_lev_zsu]}

# катер «Скат», экраноплан «Крачка», «Буревестник», «Чайка» — переделаны кодом (замечания Kanta 19.10): b2_sea_craft.py
import b2_sea_craft
RECIPES.update(b2_sea_craft.RECIPES)

if __name__ == '__main__':
    names = [a for a in A if not a.startswith('--')]
    for n in (RECIPES if names == ['all'] else names):
        RECIPES[n]()
