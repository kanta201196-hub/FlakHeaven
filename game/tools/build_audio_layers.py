"""Пилот звука (18.10.2026): 8 эффектов, собранных из нескольких слоёв, вместо одной обрезанной записи.

Что не так было в гибриде 16.10 (build_audio_hybrid.py): у каждого звука один источник, всё моно,
взрывы обрезаны до 0,7–1,6 с (хвост рвётся), у пушки и попаданий 3 одинаковых варианта.
Здесь звук — это слои: «удар» (короткая атака), «тело», «хвост» (стерео, раскат и эхо),
«обломки» (металл/камень сыплется после взрыва) и «саб» — низкий гул, синтезированный кодом.

Громкость удара (первые 50 мс) выравнивается так же, как в гибриде (REF_PUNCH), поэтому баланс
в коде (volume_db в вызовах Sfx.play) не меняется: длиннее и богаче становится только хвост.
Источники — Sonniss GDC (та же лицензия, что у гибрида), саб — синтез, без лицензии.

Запуск (нужны ffmpeg, numpy, сеть):
  python3 game/tools/build_audio_layers.py [--out ПАПКА] [--only событие,событие]
"""
import os, sys, glob, subprocess
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_audio_hybrid as H  # noqa: E402

SR = H.SR

# Новые источники (год бандла, путь без расширения) — в дополнение к SRC гибрида
H.SRC.update({
    'expl_far': ('2017', 'Gamemaster Audio -  Explosion Sound Pack/explosion_far_distant_02'),
    'expl_longtail': ('2017', 'Gamemaster Audio -  Explosion Sound Pack/explosion_med_long_tail_01'),
    'expl_out_large': ('2020', 'Bluezone - Tank - Explosion Sound Effects/Bluezone_BC0271_explosion_outdoors_large_005'),
    'debris_rock': ('2020', 'Bluezone - Tank - Explosion Sound Effects/Bluezone_BC0271_debris_falling_rock_dust_002'),
    'metal_debris': ('2018', 'Bluezone Corporation - Metal Debris/Bluezone_BC0236_metal_debris_055'),
    'expl_farsc': ('2020', 'Stefano Cremona - Explosions/FarExplosion03'),
    'low_hit': ('2019', '344 Audio - Low Frequency Elements/Explosive Hit 10 Filtered, Low End'),
    'drone_expl': ('2023', 'BluezoneCorp - Combat Drone/Bluezone_BC0288_combat_drone_weapon_explosion_004'),
    'rattle': ('2015', 'Mechanical Wave - Undoing-Computer/Drop Fall Metal Rattle Scrap Debris_UC 10'),
    'plate_hit': ('2017', 'Double Trouble Audio - Medieval Armor and Impacts/Plate_Impact_Hard_02'),
    'rust_hit': ('2016', 'Alexander Kopeikin - Black Metal/dry hard metal impact with rust debris 20'),
    'metal_crash': ('2017', 'SoundBits - Just Impacts - Extension II/Metal_Hit_Crash_090'),
    'bimp16': ('2020', 'Olivier Girardot - Hand Guns Sound Effects Pack/Bullet Impact 16 - Light Version'),
    'shell_traj': ('2020', 'Bluezone - Tank - Explosion Sound Effects/Bluezone_BC0271_shell_trajectory_004'),
    'f22': ('2018', 'Airborne Sound - Variety 1 Sound Effects/Jet,Fighter,F-22,Raptor,By,Slow,Crackle'),
    'expl_bigsc': ('2020', 'Stefano Cremona - Explosions/BigExplosion02'),
    'wind_gusty': ('2016', 'Pole Position Production - The Snow & Ice Textures Library/snow_ambience_wind_strong_08_gusty'),
    'wind_alt': ('2017', 'Charlie Atanasyan - Indonesia sound library by Faunethic/Forest cold wind in alitude the morning_120208_00'),
    'sea_wash': ('2016', 'Shutter Sound - Worldwide Ambience/South Pacific, Exterior, Atmosphere, Desert Island sea wash light, distant crickets'),
    'mine_far': ('2024', 'Pole Position - The Warfare 2 Library/Tank Mine - EXPLOSION - Mounted on Metal Beam - DISTANT - AMBEO BLD'),
    # Море (Архипелаг): чайки у гавани, гудок, всплеск и скрежет тонущего судна
    'gulls_harbor': ('2019', 'The Sound Pack Tree - Sonic Seaside/205300 - Crazy Harbor Seagulls - Loop'),
    'gulls_nest': ('2017', 'SoundHolder -  Cormorants/animals cormorants nest loud seagulls mono DPA4061'),
    'narrow_horn': ('2019', 'Pole Position - Narrowboat Gardner 4LW 1960/narrowboat_t23_var_sfx_horn_various_XY_RSM191'),
    'uw_splash': ('2018', 'Soundrangers - Hydrology Underwater/underwater_splash_large_06'),
    'uw_blast': ('2018', 'Soundrangers - Hydrology Underwater/explosion_underwater_blast_04'),
    'water_expl': ('2023', 'David Dumais Audio - Magic Sound FX Pack 2/MagicPack2_WaterExplosions_Explosion2-004'),
    'rock_splash': ('2016', 'Mattia Cellotto - Rocks Momentum/Glacial Lake - Large Size Rock Splashes - 5 Meters. Water,Splash,Large,Rock,Impact,Various_06'),
    'hull_creak': ('2016', 'Alexander Kopeikin - Black Metal/metal, heavy creaks, shipwreck, submarine deformation under pressure 07'),
    'hull_scrape': ('2017', 'Alexander Kopeikin - Black Metal/metal, heavy creaks, shipwreck, ship scraping its broadside 02'),
    'bubbles_deep': ('2015', 'Soundopolis - Underwater/Underwater_Bubbles_Deep_Fienup_016'),
})

# Новое событие моря: удар как у взрыва крупного врага
H.REF_PUNCH['ship_sink'] = H.REF_PUNCH['explode_big']


def load_st(path):
    """Стерео-загрузка (моно-источник дублируется в оба канала)."""
    raw = subprocess.run(['ffmpeg', '-v', 'quiet', '-i', path, '-ac', '2', '-ar', str(SR), '-f', 'f32le', '-'],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).copy()


def ff(x, af):
    """Фильтр ffmpeg над стерео-массивом (срез низа/верха и т. п.)."""
    r = subprocess.run(['ffmpeg', '-v', 'quiet', '-f', 'f32le', '-ar', str(SR), '-ac', '2', '-i', '-', '-af', af,
                        '-f', 'f32le', '-'], input=x.astype(np.float32).tobytes(), capture_output=True, check=True)
    return np.frombuffer(r.stdout, dtype=np.float32).reshape(-1, 2)[:len(x)].copy()


def sub(f0, f1, dur, decay):
    """Саб: синус, падающий по тону f0 → f1 Гц, мягкая атака 4 мс и экспоненциальный спад."""
    t = np.arange(int(dur * SR)) / SR
    f = f0 * (f1 / f0) ** (t / dur)
    y = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * decay)
    a = int(0.004 * SR)
    y[:a] *= np.linspace(0, 1, a)
    y[-int(0.05 * SR):] *= np.linspace(1, 0, int(0.05 * SR))
    return np.stack([y, y], 1).astype(np.float32) * 0.5


def layer(key, start, dur, fout, pitch=1.0, mono=False, af=None):
    x = load_st(H.fetch(key))
    if isinstance(start, str):
        start = H.find_start(x.mean(1), start)
    s = int(start * SR)
    y = x[s:s + int(dur * pitch * SR)].copy()
    if pitch != 1.0:
        idx = np.arange(0, len(y) - 1, pitch)
        y = np.stack([np.interp(idx, np.arange(len(y)), y[:, c]) for c in (0, 1)], 1).astype(np.float32)
    if mono:
        y[:] = y.mean(1, keepdims=True)
    if af:
        y = ff(y, af)
    fi = min(len(y), int(0.002 * SR))
    y[:fi] *= np.linspace(0, 1, fi)[:, None]
    fo = min(len(y), int(fout * SR))
    y[len(y) - fo:] *= (np.linspace(1, 0, fo) ** 2)[:, None]
    return y


def norm_peak(y, db=0.0):
    """Слой к пику db дБ — так проще задавать соотношение слоёв."""
    return y * (10 ** (db / 20) / (np.abs(y).max() + 1e-9))


# Слой: (источник | ('sub', f0, f1, dur, decay), начало с | 'auto' | 'loud', длит. с, затухание с,
#        уровень пика дБ, задержка с, опции {pitch, mono, af})
A = 'auto'
LO = 'lowpass=f=%d'
HI = 'highpass=f=%d'
LAYERS = {
    # Взрыв мелкого врага в воздухе: короткий удар + раскат 1,8 с + сыплющиеся обломки + саб
    'explode': [
        [('expl_notail', 0.0, 0.5, 0.3, 0, 0), ('expl_longtail', A, 1.9, 1.2, -7, 0.02, {'af': HI % 80}),
         ('metal_debris', 0.25, 1.4, 0.9, -17, 0.12, {'af': HI % 1200}), (('sub', 70, 38, 0.45, 7), 0, 0, 0, -12, 0)],
        [('expl_mortar', 0.0, 0.5, 0.3, 0, 0), ('expl_out_large', A, 1.9, 1.2, -6, 0.02, {'af': HI % 80}),
         ('rattle', 0.08, 0.8, 0.5, -18, 0.15, {'af': HI % 1500}), (('sub', 66, 36, 0.45, 7), 0, 0, 0, -12, 0)],
        [('expl_real', 0.01, 0.5, 0.3, 0, 0), ('expl_far', A, 1.9, 1.2, -6, 0.03),
         ('metal_debris', 1.15, 1.2, 0.8, -18, 0.14, {'af': HI % 1200}), (('sub', 72, 40, 0.4, 8), 0, 0, 0, -12, 0)],
        [('drone_expl', A, 0.6, 0.35, 0, 0), ('expl_longtail', 0.4, 1.6, 1.0, -8, 0.05, {'af': HI % 80}),
         ('rattle', 0.08, 0.8, 0.5, -19, 0.2, {'af': HI % 1500, 'pitch': 1.1}), (('sub', 64, 34, 0.45, 7), 0, 0, 0, -12, 0)],
    ],
    # Крупный враг / ас: тяжёлый удар, длинный раскат 3 с, металлический лом, саб глубже
    'explode_big': [
        [('expl_urban', 0.0, 1.2, 0.6, 0, 0), ('expl_out_large', A, 3.0, 1.8, -8, 0.04),
         ('metal_debris', 0.0, 2.4, 1.4, -13, 0.18, {'af': HI % 900}), (('sub', 58, 28, 0.9, 4), 0, 0, 0, -8, 0)],
        [('expl_l07', 0.05, 1.2, 0.6, 0, 0), ('expl_farsc', A, 3.0, 1.8, -8, 0.05),
         ('metal_crash', 'loud', 1.6, 1.0, -14, 0.2, {'af': HI % 700}), (('sub', 55, 26, 0.9, 4), 0, 0, 0, -8, 0)],
        [('expl_l08', 0.44, 1.2, 0.6, 0, 0), ('expl_longtail', A, 2.8, 1.7, -8, 0.04),
         ('metal_debris', 1.1, 2.2, 1.3, -13, 0.16, {'af': HI % 900}), (('sub', 60, 30, 0.9, 4), 0, 0, 0, -8, 0)],
    ],
    # Бомба: взрыв на земле, слышен сверху — глухой, с долгим раскатом, камни и пыль, саб в грудь
    'bomb': [
        [('expl_deep', A, 1.4, 0.8, 0, 0, {'af': LO % 5000}), ('expl_farsc', A, 3.2, 2.0, -8, 0.06),
         ('debris_rock', 0.1, 2.0, 1.2, -16, 0.35, {'af': HI % 400}), (('sub', 50, 24, 1.1, 3.2), 0, 0, 0, -7, 0)],
        [('mine_far', A, 3.2, 1.8, 0, 0, {'af': LO % 6000}), ('expl_deep', A, 1.2, 0.8, -4, 0, {'af': LO % 3000}),
         ('debris_rock', 0.1, 2.0, 1.2, -17, 0.4, {'af': HI % 400}), (('sub', 48, 24, 1.1, 3.2), 0, 0, 0, -7, 0)],
        [('expl_out_large', A, 3.2, 1.8, 0, 0, {'af': LO % 4500}), ('low_hit', A, 1.4, 0.8, -3, 0),
         ('debris_rock', 0.1, 2.0, 1.2, -16, 0.3, {'af': HI % 400}), (('sub', 52, 26, 1.1, 3.2), 0, 0, 0, -7, 0)],
    ],
    # Попадание по врагу (звучит очень часто): металлический щелчок + искра, 5 разных вариантов
    'hit': [
        [('imp_metal', 0.01, 0.2, 0.1, 0, 0, {'mono': True})],
        [('imp_22', 0.02, 0.2, 0.1, 0, 0, {'mono': True})],
        [('iron_hit', 1.805, 0.2, 0.1, 0, 0, {'mono': True}), ('bimp16', A, 0.15, 0.08, -10, 0.0, {'mono': True, 'af': HI % 2500})],
        [('bimp16', A, 0.2, 0.1, 0, 0, {'mono': True}), ('plate_hit', A, 0.18, 0.12, -9, 0.0, {'mono': True, 'pitch': 1.3})],
        [('plate_hit', A, 0.22, 0.14, 0, 0, {'mono': True, 'pitch': 1.15}), ('imp_metal', 0.01, 0.15, 0.08, -8, 0.0, {'mono': True, 'af': HI % 2000})],
    ],
    # Попадание по игроку: тяжёлый удар по обшивке + дребезг + низкий толчок (больнее, чем раньше)
    'player_hit': [
        [('rust_hit', A, 0.55, 0.35, 0, 0), ('barrel', 2.15, 0.45, 0.3, -5, 0), ('rattle', 0.08, 0.5, 0.35, -14, 0.06, {'af': HI % 1500}),
         (('sub', 90, 45, 0.25, 12), 0, 0, 0, -8, 0)],
        [('plate_hit', A, 0.5, 0.3, 0, 0, {'pitch': 0.85}), ('barrel', 4.58, 0.45, 0.3, -4, 0), ('rattle', 0.2, 0.45, 0.3, -15, 0.05, {'af': HI % 1500}),
         (('sub', 85, 42, 0.25, 12), 0, 0, 0, -8, 0)],
        [('metal_crash', 'loud', 0.55, 0.35, 0, 0), ('barrel', 6.87, 0.45, 0.3, -5, 0), (('sub', 95, 48, 0.25, 12), 0, 0, 0, -8, 0)],
    ],
    # Курсовое: та же 30-мм пушка, но 4 варианта с разной высотой и «телом» (низкий толчок от пушки танка)
    'gun_fire': [
        [('mk44', 0.305, 0.17, 0.09, 0, 0, {'mono': True}), ('tank_cannon', A, 0.14, 0.09, -12, 0, {'mono': True, 'af': LO % 300})],
        [('mk44', 0.305, 0.17, 0.09, 0, 0, {'mono': True, 'pitch': 1.06}), ('tank_cannon', A, 0.14, 0.09, -13, 0, {'mono': True, 'af': LO % 260})],
        [('mk44', 0.305, 0.17, 0.09, 0, 0, {'mono': True, 'pitch': 0.95}), ('tank_cannon', A, 0.14, 0.09, -12, 0, {'mono': True, 'af': LO % 320})],
        [('mk44', 0.305, 0.16, 0.09, 0, 0, {'mono': True, 'pitch': 1.02, 'af': 'equalizer=f=3000:t=q:w=1:g=-3'}),
         ('tank_cannon', A, 0.14, 0.09, -11, 0, {'mono': True, 'af': LO % 280})],
    ],
    # Вражеский огонь и зенитки: далёкий хлопок + глухой «бум» зенитного разрыва, 4 варианта
    'enemy_fire': [
        [('cannon_far', 0.515, 0.22, 0.12, 0, 0), (('sub', 120, 70, 0.12, 25), 0, 0, 0, -14, 0)],
        [('cannon_far', 0.715, 0.22, 0.12, 0, 0), (('sub', 110, 65, 0.12, 25), 0, 0, 0, -14, 0)],
        [('cannon_far', 2.935, 0.22, 0.12, 0, 0), (('sub', 125, 72, 0.12, 25), 0, 0, 0, -14, 0)],
        [('cannon_far', 0.515, 0.22, 0.12, 0, 0, {'pitch': 0.9}), ('expl_far', A, 0.25, 0.15, -12, 0.01, {'af': LO % 1500})],
    ],
    # Ракета В-В: поджиг + шипение уходящей ракеты (затихает и темнеет), 1,3 с
    'aam_launch': [
        [('jet_ign', 0.075, 0.6, 0.35, 0, 0), ('shell_traj', 'loud', 1.3, 0.9, -8, 0.08, {'af': LO % 6000})],
        [('flare_shot', 0.0, 0.6, 0.35, 0, 0), ('shell_traj', 'loud', 1.3, 0.9, -8, 0.06, {'af': LO % 5000, 'pitch': 1.1})],
        [('jet_ign', 0.075, 0.6, 0.35, 0, 0, {'pitch': 1.06}), ('fw_launch', A, 1.0, 0.7, -6, 0.05)],
    ],
    # --- Вторая восьмёрка (18.10)
    # Гибель игрока: взрыв с металлом, длинный раскат, лом сыплется, глубокий саб — 3 с
    'player_explode': [
        [('expl_metal', A, 2.0, 1.0, 0, 0), ('expl_out_large', A, 3.0, 1.8, -7, 0.05),
         ('metal_debris', 0.0, 2.6, 1.5, -11, 0.2, {'af': HI % 800}), (('sub', 50, 22, 1.2, 2.6), 0, 0, 0, -5, 0)],
        [('expl_bigsc', A, 3.0, 1.8, 0, 0), ('metal_crash', 'loud', 1.6, 1.0, -9, 0.08, {'af': HI % 700}),
         ('metal_debris', 1.1, 2.2, 1.3, -12, 0.3, {'af': HI % 900}), (('sub', 48, 22, 1.2, 2.6), 0, 0, 0, -5, 0)],
    ],
    # Противоракеты: хлопок пиропатрона и шипение горящей ловушки, 3 варианта
    'flare': [
        [('fw_launch', A, 0.5, 0.3, 0, 0), ('air_hiss', 'loud', 0.6, 0.4, -9, 0.03, {'af': HI % 2000})],
        [('fw_launch', A, 0.5, 0.3, 0, 0, {'pitch': 1.1}), ('air_hiss', 'loud', 0.6, 0.4, -10, 0.03, {'af': HI % 2500, 'pitch': 1.1})],
        [('flare_shot', 0.0, 0.45, 0.3, 0, 0, {'pitch': 1.15}), ('air_hiss', 'loud', 0.6, 0.4, -9, 0.02, {'af': HI % 2000, 'pitch': 0.92})],
    ],
    # Залп НАР: два пуска один за другим и шипение уходящих ракет — слышно, что это залп
    'rocket_launch': [
        [('rocket_shot', A, 0.45, 0.25, 0, 0), ('rocket_shot', A, 0.45, 0.25, -4, 0.07, {'pitch': 1.08}),
         ('shell_traj', 'loud', 0.9, 0.6, -9, 0.05, {'af': LO % 5000})],
        [('rocket_shot', A, 0.45, 0.25, 0, 0, {'pitch': 0.95}), ('rocket_shot', A, 0.45, 0.25, -5, 0.06, {'pitch': 1.12}),
         ('shell_traj', 'loud', 0.9, 0.6, -9, 0.05, {'af': LO % 4500, 'pitch': 1.1})],
    ],
    # Пуск вражеской ракеты: ниже и тяжелее нашей, с низким толчком — опасность слышна сразу
    'missile_enemy': [
        [('jet_ign', 0.075, 0.9, 0.5, 0, 0, {'pitch': 0.82}), ('shell_traj', 'loud', 1.2, 0.8, -6, 0.08, {'pitch': 0.85, 'af': LO % 4000}),
         (('sub', 80, 40, 0.3, 9), 0, 0, 0, -12, 0)],
        [('rocket_shot', A, 0.7, 0.4, 0, 0, {'pitch': 0.8}), ('shell_traj', 'loud', 1.2, 0.8, -6, 0.08, {'pitch': 0.8, 'af': LO % 4000}),
         (('sub', 75, 38, 0.3, 9), 0, 0, 0, -12, 0)],
    ],
    # Пуск ЗРК: тяжёлый стартовый ускоритель — глухой удар снизу и долгий рёв ракеты
    'sam_launch': [
        [('rocket_shot', A, 1.0, 0.5, 0, 0, {'pitch': 0.68}), ('expl_far', A, 0.5, 0.3, -9, 0.0, {'af': LO % 1500}),
         ('shell_traj', 'loud', 1.6, 1.0, -5, 0.1, {'pitch': 0.75, 'af': LO % 3500})],
    ],
    # Заправщик сбит: большой самолёт — взрыв, раскат, металл и глубокий гул
    'tanker_down': [
        [('expl_8', A, 2.2, 1.2, 0, 0), ('expl_bigsc', A, 3.2, 2.0, -5, 0.1), ('metal_crash', 'loud', 1.6, 1.0, -10, 0.25, {'af': HI % 700}),
         (('sub', 45, 22, 1.4, 2.4), 0, 0, 0, -5, 0)],
    ],
    # Судно тонет (Архипелаг): водяной взрыв, всплеск, стон и скрежет корпуса, пузыри и низкий гул
    'ship_sink': [
        [('water_expl', A, 2.4, 1.4, 0, 0), ('uw_splash', A, 2.0, 1.2, -6, 0.08),
         ('hull_creak', 0.6, 3.2, 1.6, -9, 0.45, {'pitch': 0.8, 'af': LO % 2500}),
         ('bubbles_deep', 0.0, 3.0, 1.0, -15, 1.7, {'af': LO % 3000}), (('sub', 52, 24, 1.3, 2.6), 0, 0, 0, -7, 0)],
        [('uw_blast', A, 2.6, 1.5, 0, 0), ('rock_splash', 'loud', 1.6, 1.0, -5, 0.05),
         ('hull_scrape', 'loud', 3.2, 1.6, -10, 0.55, {'pitch': 0.75, 'af': LO % 2000}),
         ('bubbles_deep', 0.4, 2.6, 1.0, -15, 1.9, {'af': LO % 3000}), (('sub', 48, 22, 1.3, 2.6), 0, 0, 0, -7, 0)],
    ],
    # Форсаж: поджиг и треск реактивной струи
    'afterburner': [
        [('fire_ign', A, 1.5, 0.7, 0, 0), ('f22', 'loud', 1.3, 0.8, -7, 0.1, {'af': HI % 300})],
    ],
}


def build(spec):
    parts = []
    for L in spec:
        src, start, dur, fout, lvl, delay = L[:6]
        o = L[6] if len(L) > 6 else {}
        if isinstance(src, tuple) and src[0] == 'sub':
            y = sub(*src[1:])
        else:
            y = layer(src, start, dur, fout, o.get('pitch', 1.0), o.get('mono', False), o.get('af'))
        parts.append((norm_peak(y, lvl), int(delay * SR)))
    n = max(len(y) + d for y, d in parts)
    out = np.zeros((n, 2), dtype=np.float32)
    for y, d in parts:
        out[d:d + len(y)] += y
    return out


def limit_st(y):
    r = subprocess.run(['ffmpeg', '-v', 'quiet', '-f', 'f32le', '-ar', str(SR), '-ac', '2', '-i', '-',
                        '-af', 'alimiter=limit=0.89:attack=0.5:release=40:level=disabled', '-f', 'f32le', '-'],
                       input=np.pad(y, ((0, SR // 10), (0, 0))).tobytes(), capture_output=True, check=True)
    return np.frombuffer(r.stdout, dtype=np.float32).reshape(-1, 2)[:len(y)].copy()


def write_ogg_st(y, path, mono=False):
    ch = '1' if mono else '2'
    data = y.mean(1) if mono else y
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'f32le', '-ar', str(SR), '-ac', ch, '-i', '-',
                    '-c:a', 'libvorbis', '-q:a', '5', path], input=data.astype(np.float32).tobytes(), check=True)


def loop_st(x, xf):
    """Стерео-цикл: конец плавно переходит в начало (кроссфейд xf с)."""
    n = int(xf * SR)
    fade = np.linspace(0, 1, n)[:, None]
    return np.concatenate([x[:n] * fade + x[-n:] * (1 - fade), x[n:-n]]).astype(np.float32)


def krms(y):
    return 10 * np.log10(np.mean(H.kweight(y.mean(1)).astype(np.float64) ** 2) + 1e-12)


def build_engine(out_dir):
    """Двигатель в стерео: прежний рёв (правка 3.5-s4, ровная громкость) — в левом канале с начала цикла,
    в правом со сдвигом на полцикла (звучит шире, не «в одной точке») + тихий свист турбины 1,9 и 3,8 кГц
    (тон в игре растёт со скоростью вместе с рёвом). Громкость — как у прежнего цикла."""
    x = H.load(H.fetch('blast_off'))
    m = H.flatten(x[int(1.0 * SR):int(6.5 * SR)])
    n = int(0.5 * SR)
    fade = np.linspace(0, 1, n)
    m = np.concatenate([m[:n] * fade + m[-n:] * (1 - fade), m[n:-n]])
    t = np.arange(len(m)) / SR
    k = round(1900 * len(m) / SR) / (len(m) / SR)  # целое число периодов — шов цикла без щелчка
    whine = (np.sin(2 * np.pi * k * t) + 0.4 * np.sin(4 * np.pi * k * t)) * (1 + 0.15 * np.sin(2 * np.pi * 3 * t / t[-1]))  # лёгкое «плавание», 3 волны за цикл
    whine *= np.abs(m).mean() * 0.12
    y = np.stack([m + whine, np.roll(m, len(m) // 2) + whine], 1).astype(np.float32)
    y *= 10 ** ((H.ENGINE_RMS - krms(y)) / 20)
    if np.abs(y).max() > 0.89:
        y *= 0.89 / np.abs(y).max()
    write_ogg_st(y, os.path.join(out_dir, 'engine.ogg'))
    print('engine         стерео-цикл %.1f с, K-RMS %.1f dB' % (len(y) / SR, krms(y)))


# Фон биома под боем (цикл 30 с, тихо, громкость в sfx.gd): ключ -> слои (источник, начало, уровень дБ, срез низа)
AMBIENT = {
    'ambient_highland': [('wind_gusty', 10.0, 0, 120), ('wind_alt', 20.0, -8, 200)],   # Нагорье: порывистый горный ветер
    'ambient_sea': [('sea_wash', 20.0, 0, 90), ('wind_alt', 40.0, -6, 200)],            # Архипелаг: прибой и ветер над морем
}


def build_ambient(out_dir):
    for name, layers in AMBIENT.items():
        y = None
        for key, start, lvl, hp in layers:
            x = load_st(H.fetch(key))[int(start * SR):int((start + 33) * SR)]
            x = ff(x, 'highpass=f=%d' % hp)
            x = x * 10 ** ((-24 + lvl - krms(x)) / 20)
            y = x if y is None else y[:len(x)] + x[:len(y)]
        y = loop_st(y, 3.0)
        y *= 10 ** ((-24 - krms(y)) / 20)
        write_ogg_st(y, os.path.join(out_dir, name + '.ogg'))
        print('%-16s цикл %.1f с, K-RMS %.1f dB' % (name, len(y) / SR, krms(y)))


def reverb_st(y, sec, decay, wet):
    """Простая «даль»: свёртка с затухающим шумом (каналы разные — эхо над водой широкое)."""
    rng = np.random.default_rng(7)
    n = int(sec * SR)
    t = np.arange(n) / SR
    out = np.pad(y, ((0, n), (0, 0)))
    for c in (0, 1):
        ir = rng.standard_normal(n) * np.exp(-t * decay)
        ir[:int(0.03 * SR)] = 0  # первое отражение — через 30 мс
        m = len(y) + n
        w = np.fft.irfft(np.fft.rfft(y[:, c], m) * np.fft.rfft(ir, m), m)[:len(out)]
        out[:, c] += w * (wet * np.abs(y).max() / (np.abs(w).max() + 1e-9))
    return out.astype(np.float32)


def build_horn():
    """Гудок корабля: запись гудка катера на две октавы ниже (~90 Гц) + синтез того же тона
    (гармоники, мягкая атака, лёгкое «плавание»), срез верха и эхо над водой."""
    x = layer('narrow_horn', 0.3, 3.0, 0.0, 0.25)           # 0,75 с записи -> 3 с, тон 360 -> 90 Гц
    n = len(x)
    t = np.arange(n) / SR
    f = 90.0 * (1 - 0.03 * np.exp(-t * 6)) * (1 + 0.002 * np.sin(2 * np.pi * 4.5 * t))  # чуть ниже на старте
    ph = 2 * np.pi * np.cumsum(f) / SR
    tone = sum(np.sin(k * ph) / k ** 0.9 for k in range(1, 30))
    y = norm_peak(x, -4) + norm_peak(np.stack([tone, tone], 1), -2)
    env = np.minimum(1, t / 0.18) * np.minimum(1, (t[-1] - t) / 0.35)
    y = ff(y * env[:, None], 'highpass=f=45,lowpass=f=1800')
    return reverb_st(y, 2.8, 2.2, 0.35)


def build_gulls():
    """Чайки у гавани: три отрезка по ~7 с из двух записей, без низа (гул порта), с плавным входом и уходом."""
    out = []
    for key, start in (('gulls_harbor', 4.0), ('gulls_harbor', 52.0), ('gulls_nest', 20.0)):
        y = layer(key, start, 7.0, 1.5, af='highpass=f=500')
        a = int(1.2 * SR)
        y[:a] *= np.linspace(0, 1, a)[:, None]
        out.append(y)
    return out


# Звуки моря: громкость удара (как REF_PUNCH). Чайки — фон, тихие сами по себе (play без -дБ)
SEA_PUNCH = {'ship_horn': -12.0, 'gulls': -24.0}


def build_sea(out_dir):
    for name, ys in (('ship_horn', [build_horn()]), ('gulls', build_gulls())):
        for f in glob.glob(os.path.join(out_dir, name + '.ogg')) + glob.glob(os.path.join(out_dir, name + '_[0-9].ogg')):
            os.remove(f)
        for i, y in enumerate(ys, 1):
            y = y * 10 ** ((SEA_PUNCH[name] - H.punch_db(y.mean(1))) / 20)
            if np.abs(y).max() > 0.89:
                y = limit_st(y)
            fn = name if len(ys) == 1 else '%s_%d' % (name, i)
            write_ogg_st(y, os.path.join(out_dir, fn + '.ogg'))
            print('%-14s %.2f с  got %.1f dB' % (fn, len(y) / SR, H.punch_db(y.mean(1))))


def main():
    out_dir = sys.argv[sys.argv.index('--out') + 1] if '--out' in sys.argv else H.AUDIO
    only = sys.argv[sys.argv.index('--only') + 1].split(',') if '--only' in sys.argv else None
    os.makedirs(out_dir, exist_ok=True)
    if only is None or 'engine' in only:
        build_engine(out_dir)
    if only is None or 'ambient' in only:
        build_ambient(out_dir)
    if only is None or 'sea' in only:
        build_sea(out_dir)
    for event, variants in LAYERS.items():
        if only is not None and event not in only:
            continue
        target = H.REF_PUNCH[event]
        for f in glob.glob(os.path.join(out_dir, event + '.ogg')) + glob.glob(os.path.join(out_dir, event + '_[0-9].ogg')):
            os.remove(f)
        for i, spec in enumerate(variants, 1):
            y = build(spec)
            g = 10 ** ((target - H.punch_db(y.mean(1))) / 20)
            y = y * g
            for _ in range(2):  # лимитер срезает пик и чуть убавляет удар — добираем и снова режем
                if np.abs(y).max() > 0.89:
                    y = limit_st(y)
                d = target - H.punch_db(y.mean(1))
                if d < 0.3:
                    break
                y = y * 10 ** (d / 20)
            if np.abs(y).max() > 0.89:
                y = limit_st(y)
            mono = all(len(L) > 6 and L[6].get('mono') for L in spec if not isinstance(L[0], tuple))
            name = event if len(variants) == 1 else '%s_%d' % (event, i)
            write_ogg_st(y, os.path.join(out_dir, name + '.ogg'), mono)
            print('%-14s %d слоя  %.2f с  ref %.1f dB  got %.1f dB  %s' % (
                name, len(spec), len(y) / SR, target, H.punch_db(y.mean(1)), 'моно' if mono else 'стерео'))


if __name__ == '__main__':
    main()
