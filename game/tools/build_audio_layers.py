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
    'mine_far': ('2024', 'Pole Position - The Warfare 2 Library/Tank Mine - EXPLOSION - Mounted on Metal Beam - DISTANT - AMBEO BLD'),
})


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


def main():
    out_dir = sys.argv[sys.argv.index('--out') + 1] if '--out' in sys.argv else H.AUDIO
    only = sys.argv[sys.argv.index('--only') + 1].split(',') if '--only' in sys.argv else None
    os.makedirs(out_dir, exist_ok=True)
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
