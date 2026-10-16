"""Звуки в стиле «гибрид» (решение Kanta 16.10.2026): реальные записи из Sonniss GDC Game Audio Bundle.

Лицензия Sonniss GDC: можно в коммерческой игре, указывать автора не нужно, нельзя распространять
сами исходники как библиотеку звуков. Исходники берутся с зеркала archive.org
(sonniss-gdc-<год>-game-audio-bundle-normalized) и кешируются в ~/.cache/flak_sonniss.

Громкость: каждый звук выравнивается по «пробивной» громкости (макс. K-взвешенный RMS в окне 50 мс)
прежнего звука того же события (для новых событий 3.5 — звука, который играл вместо них),
поэтому баланс в коде (volume_db в вызовах Sfx.play) не меняется. Пики выше -1 dBFS срезает лимитер.

Запуск (нужны ffmpeg, numpy, сеть):
  python3 game/tools/build_audio_hybrid.py [--out ПАПКА] [--only событие,событие]
Результат по умолчанию — сразу в game/audio/. Интерфейсные звуки, джинглы и музыка здесь не трогаются.
"""
import os, subprocess, sys, glob, urllib.parse, urllib.request
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AUDIO = os.path.join(ROOT, 'audio')
CACHE = os.path.join(os.path.expanduser('~'), '.cache', 'flak_sonniss')
SR = 44100

# Громкость прежних звуков (Kenney и др., CC0): среднее по вариантам, дБ макс. K-взвешенного RMS за 50 мс.
# Для engine — средний K-взвешенный RMS всего цикла.
REF_PUNCH = {
    'gun_fire': -16.0, 'gunpod_fire': -17.0, 'turret_fire': -20.9, 'enemy_fire': -7.8, 'flare': -11.6,
    'aam_launch': -14.7, 'rocket_launch': -15.5, 'missile_enemy': -14.1, 'bomb_drop': -6.0, 'bomb': -11.4,
    'explode': -13.0, 'explode_big': -9.7, 'player_explode': -9.7, 'hit': -12.5, 'pass_hit': -11.2,
    'player_hit': -16.7, 'shield_break': -20.0, 'lock': -7.7, 'radio': -11.1, 'roll': -16.4,
    'near_miss': -13.6, 'combat_turn': -16.4, 'shield': -6.0, 'afterburner': -15.1, 'boss': -12.2, 'evac': -9.5,
}
# Новые события 3.5 (PR #33) — громкость того звука, который до сих пор играл вместо них (FALLBACK в sfx.gd)
for _ev, _fb in {'dive': 'roll', 'synergy': 'boss', 'cargo': 'evac', 'fuel_low': 'lock', 'fuel_empty': 'lock',
                 'tanker_call': 'evac', 'tanker_down': 'shield_break', 'boom_dock': 'lock', 'boom_undock': 'lock',
                 'refuel_done': 'evac', 'aa_alert': 'lock', 'sam_lock': 'lock', 'sam_launch': 'missile_enemy',
                 'aa_intercept': 'enemy_fire', 'fortress_part': 'shield_break', 'fortress_ring': 'enemy_fire'}.items():
    REF_PUNCH[_ev] = REF_PUNCH[_fb]
ENGINE_RMS = -17.8

# Ключ -> (год бандла, путь без расширения). Имена — как в бандле, в игре нигде не показываются.
SRC = {
    'mk44': ('2016', 'Fascinated Sound - The Gun Locker SFX Pack/Automatic Cannon - MK44 - 03 - Single Shot with Report 03'),
    'smg': ('2017', 'Gamemaster Audio -  Gun Sound Pack/gun_submachine_auto_shot_00_automatic_preview_01'),
    'cannon_far': ('2017', 'Pole Position - The Warfare Library/warfare_t1b_cannon_firing_forest_distant_MKH8060_2'),
    'tank_cannon': ('2020', 'Bluezone - Tank - Explosion Sound Effects/Bluezone_BC0271_tank_artillery_cannon_shot_012'),
    'tank_battle': ('2017', 'Double Trouble Audio - Tanks and Jet/TAJ - Tank Battle Cannon Fire [XY Stereo]-001'),
    'jet_ign': ('2020', 'Sound Spark LLC - Hyperdrive- Futuristic Vehicle Elements/Stutter_Jet_Accelerate_03'),
    'flare_shot': ('2024', 'BluezoneCorp - Steampunk Weapon And Textures/Bluezone_BC0296_steampunk_weapon_flare_shot_explosion_003'),
    'rocket_shot': ('2018', 'SoundMorph - STEAMPUNK WEAPONS/Steampunk Weapons - Rocket Launcher - Shot - 04'),
    'fw_launch': ('2023', 'InspectorJ - Essentials 03 Fireworks/FRWKComr_InsJ_Fireworks_Launch_Close_01-03'),
    'whistle_down': ('2023', 'SmartSoundFX - Cartoon & Infotainment/WHISTLE Down Long'),
    'blast_off': ('2026', '344 Audio - Air Designed/AEROJet_Blast Off Clean_344 Audio_Air Designed'),
    'fire_ign': ('2018', 'Gregor Quendel – Designed Fire/Designed Fire - Impacts - Large, ignition 03'),
    'lock_on': ('2019', 'The Chris Alan - Analog Synthesized UI & SFX/Analog Synthesized UI - Lock On Engage'),
    'beep_x4': ('2018', 'Airborne Sound - Beeps and Buzzers/Beep,Clean,Pure,Simple,High,x4,Fast'),
    'cockpit_alarm': ('2019', 'BlueZone - Cargo Spaceship Sound Effects/Bluezone_BC0243_cockpit_alarm_006'),
    'stall_short': ('2020', 'Articulated Sounds - Boeing 737 Airplane Cockpit/ALARM AIRCRAFT Mechanical Stall Warning Short 01, Aircraft Control Board'),
    'stall_horn': ('2024', 'Pole Position - Beechcraft Baron 58 1969/Beechcraft Baron 58 - t12 - VAR SFX - Stall Warning - MS Decoded - RSM191'),
    'radio_beep': ('2020', 'Bluezone - Interception - Radio Transmission/Bluezone_BC0266_radio_beep_walkie_talkie_002'),
    'walkie': ('2016', 'Sergey Eybog - Handheld Tranceivers/Walkie Talkie,Cobra MicroTalk,Radio Communication,End,Noise Squelch,Beep,Series'),
    'imp_metal': ('2017', 'Gamemaster Audio -  Bullet Impact Sounds/bullet_impact_metal_heavy_08'),
    'imp_22': ('2018', 'Olivier Girardot - Guns & Explosions/Bullet Impact 22'),
    'iron_hit': ('2024', 'Pole Position - The Metal Hit Sweeteners Library/Iron - Thick - HIT - Hammer'),
    'barrel': ('2024', 'Pole Position - The Metal Hit Sweeteners Library/Oil Barrel - HIT - Hammer - Take 2'),
    'cannonball': ('2023', 'Gladestock Studios - Naval Warfare/GS cannonball impact 005'),
    'shield_hits': ('2024', 'Justsoundeffects - Melee Weapons/WEAPArmr_Metal Shield Block Hits_JSE_MW'),
    'glass_break': ('2024', 'Mechanical Wave - Glass/GLASBrk_Glass Break Hit_04_MWSFX_GL'),
    'scrap_hit': ('2015', 'Mechanical Wave - Undoing-Computer/Hit Impact Hard Metal Scrap Debris_UC 01'),
    'latch': ('2026', 'Epic Stock Media - HD Lock And Mechanism Sound Design Kit/MECHLtch_Click Deep Mechanism Latch Button Nearfield Thunk 02_ESM_HDLM'),
    'air_hiss': ('2017', 'Fascinated Sound - Scene Shop Tool Box/Compressed Air 06 Hiss and Spurt'),
    'confirm': ('2024', 'Rescopic Sound - User Interaction/UIAlert_Confirm Middle 12_RSCPC_USIN'),
    'loot': ('2017', 'Eiravaein Sound - Latchlocker/Latchlocker,design,FutureLoot,score,plunder'),
    'stinger': ('2026', 'Epic Stock Media - Anime Game/DSGNStngr_Power Up Bright Positive Successful Light Saturation Crash Shimmer 05_ESM_AG'),
    'power_up': ('2018', 'Gamemaster Audio - Sci-Fi Sounds and Sci-Fi Weapons/sci-fi_device_item_power_up_flash_01'),
    'flyby': ('2017', 'Gamemaster Audio -  Bullet Impact Sounds/bullet_flyby_fast_05'),
    'whoosh_forceful': ('2019', 'Airborne Sound - Airy Whooshes/Whoosh,Sound Design,Airy,Full,Forceful,Soft'),
    'whoosh_buffet': ('2019', 'Airborne Sound - Airy Whooshes/Whoosh,Sound Design,Airy,Full,Soft,Buffet,Medium'),
    'jet_whip': ('2019', 'Airborne Sound - Jet Fighter Maneuvers/Jet,Fighter,F-16,Fighting Falcon,Medium Distant,By,Whip,Buffet'),
    'expl_notail': ('2017', 'Gamemaster Audio -  Explosion Sound Pack/explosion_large_no_tail_03'),
    'expl_mortar': ('2023', 'BluezoneCorp - Detonation - Explosion/Bluezone_BC0277_explosion_mortar_002_01'),
    'expl_real': ('2024', 'DavidDumais - Explosion SFX Pack/EXPLReal_Medium Realistic Explosion 15_DDUMAIS_NONE'),
    'expl_urban': ('2023', 'BluezoneCorp - Detonation - Explosion/Bluezone_BC0277_explosion_urban_004_02'),
    'expl_l07': ('2018', 'Gamemaster Audio - Guns, Bullets and Explosions/explosion_large_07'),
    'expl_l08': ('2017', 'Gamemaster Audio -  Explosion Sound Pack/explosion_large_08'),
    'expl_deep': ('2020', 'Stefano Cremona - Explosions/DeepExplosion02'),
    'expl_8': ('2018', 'Olivier Girardot - Guns & Explosions/Explosion 8'),
    'expl_metal': ('2024', 'DavidDumais - Explosion SFX Pack/DESTRCrsh_Designed Car Explosion With Metal Breaking And Glass Shattering  06_DDUMAIS_NONE'),
}

A = 'auto'  # начало = первый громкий удар в файле
# событие -> варианты: (источник, начало с, длительность с, затухание с, высота тона)
PLAN = {
    # --- Стрельба
    # Курсовое: 30-мм автоматическая пушка, короткий «удар» без хвоста (стреляет часто)
    'gun_fire': [('mk44', 0.305, 0.17, 0.09, 1.0), ('mk44', 0.305, 0.17, 0.09, 1.07), ('mk44', 0.305, 0.17, 0.09, 0.94)],
    # Гондола: та же пушка, выше и короче
    'gunpod_fire': [('mk44', 0.305, 0.13, 0.07, 1.15), ('mk44', 0.305, 0.13, 0.07, 1.22)],
    # Автотурели: лёгкий автомат, отдельные выстрелы очереди
    'turret_fire': [('smg', 0.055, 0.075, 0.04, 1.0), ('smg', 0.16, 0.075, 0.04, 1.0), ('smg', 0.26, 0.075, 0.04, 1.0)],
    # Враги и зенитки: глухие далёкие хлопки пушки (очередь из трёх) — ниже и мягче нашего, не путается с ним
    'enemy_fire': [('cannon_far', 0.515, 0.19, 0.1, 1.0), ('cannon_far', 0.715, 0.19, 0.1, 1.0), ('cannon_far', 2.935, 0.19, 0.1, 1.0)],
    # Противоракеты: хлопок и шипение отстрела
    'flare': [('fw_launch', A, 0.35, 0.2, 1.0)],
    # --- Ракеты и бомбы
    'aam_launch': [('jet_ign', 0.075, 0.8, 0.45, 1.0), ('flare_shot', 0.0, 0.7, 0.35, 1.0)],
    'rocket_launch': [('rocket_shot', A, 0.4, 0.25, 1.0)],
    # Вражеская ракета: тот же поджиг, но ниже и тяжелее — слышно, что это не наша
    'missile_enemy': [('jet_ign', 0.075, 0.9, 0.5, 0.82), ('rocket_shot', A, 0.7, 0.4, 0.8)],
    'bomb_drop': [('whistle_down', A, 1.0, 0.3, 1.0)],
    # --- Взрывы
    'explode': [('expl_notail', 0.0, 0.7, 0.35, 1.0), ('expl_mortar', 0.0, 0.8, 0.45, 1.0), ('expl_real', 0.01, 0.75, 0.4, 1.0)],
    'explode_big': [('expl_urban', 0.0, 1.6, 0.9, 1.0), ('expl_l07', 0.05, 1.5, 0.8, 1.0), ('expl_l08', 0.44, 1.5, 0.8, 1.0)],
    'bomb': [('expl_deep', A, 1.4, 0.8, 1.0)],
    # Гибель игрока: взрыв с разлетающимся металлом
    'player_explode': [('expl_metal', A, 2.0, 1.0, 1.0)],
    # --- Попадания
    'hit': [('imp_metal', 0.01, 0.2, 0.1, 1.0), ('imp_22', 0.02, 0.2, 0.1, 1.0), ('iron_hit', 1.805, 0.2, 0.1, 1.0)],
    # Попадание по игроку: тяжёлый удар по металлической бочке — ниже и «больнее» попадания по врагу
    'player_hit': [('barrel', 2.15, 0.5, 0.3, 1.0), ('barrel', 4.58, 0.5, 0.3, 1.0), ('barrel', 6.87, 0.5, 0.3, 1.0)],
    # Проход на форсаже (таран): ядро в металл
    'pass_hit': [('cannonball', A, 0.5, 0.3, 1.0), ('shield_hits', A, 0.5, 0.3, 1.0)],
    'shield_break': [('glass_break', A, 0.8, 0.4, 1.0)],
    # --- Сигналы
    # Захват: синтезированный «lock on» (сигналы кабины в гибриде электронные)
    'lock': [('lock_on', 0.03, 0.42, 0.08, 1.0)],
    'radio': [('radio_beep', A, 0.4, 0.15, 1.0)],
    'shield': [('power_up', A, 0.6, 0.3, 1.0)],
    # --- Манёвры
    'roll': [('whoosh_forceful', A, 0.45, 0.25, 1.0)],
    'near_miss': [('flyby', A, 0.4, 0.2, 1.0)],
    'combat_turn': [('jet_whip', 'loud', 0.7, 0.4, 1.0)],
    'afterburner': [('fire_ign', A, 1.5, 0.7, 1.0)],
    # --- Новые события 3.5
    'dive': [('whoosh_buffet', A, 0.6, 0.35, 0.9)],
    'synergy': [('stinger', A, 1.2, 0.5, 1.0)],
    'cargo': [('loot', A, 0.8, 0.3, 1.0)],
    # Топливо: писк-предупреждение кабины; пустой бак — тревожный гудок сваливания
    'fuel_low': [('stall_short', A, 0.6, 0.15, 1.0)],
    'fuel_empty': [('stall_horn', A, 1.0, 0.25, 1.0)],
    'tanker_call': [('walkie', A, 0.6, 0.2, 1.0)],
    'tanker_down': [('expl_8', A, 2.2, 1.2, 1.0)],
    'boom_dock': [('latch', A, 0.4, 0.15, 1.0)],
    'boom_undock': [('air_hiss', A, 0.6, 0.3, 1.0)],
    'refuel_done': [('confirm', A, 0.7, 0.25, 1.0)],
    # ПВО: заметили — короткий сигнал тревоги; ЗРК ведёт — частый писк (не путается с нашим захватом)
    'aa_alert': [('cockpit_alarm', A, 0.7, 0.2, 1.0)],
    'sam_lock': [('beep_x4', A, 0.38, 0.05, 1.0)],
    'sam_launch': [('rocket_shot', A, 1.0, 0.5, 0.68)],
    'aa_intercept': [('tank_cannon', A, 0.5, 0.3, 1.0)],
    'fortress_part': [('scrap_hit', A, 1.0, 0.5, 1.0)],
    'fortress_ring': [('tank_battle', A, 0.65, 0.35, 1.0)],
}


def fetch(key):
    year, path = SRC[key]
    os.makedirs(CACHE, exist_ok=True)
    dst = os.path.join(CACHE, key + '.flac')
    if not os.path.exists(dst):
        url = 'https://archive.org/download/sonniss-gdc-%s-game-audio-bundle-normalized/%s' % (year, urllib.parse.quote(path + '.flac'))
        urllib.request.urlretrieve(url, dst)
    return dst


def load(path):
    raw = subprocess.run(['ffmpeg', '-v', 'quiet', '-i', path, '-ac', '1', '-ar', str(SR), '-f', 'f32le', '-'], capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).copy()


def kweight(x):
    """Приближение K-взвешивания (как в LUFS): срез низа и подъём верха — громкость «на слух»."""
    r = subprocess.run(['ffmpeg', '-v', 'quiet', '-f', 'f32le', '-ar', str(SR), '-ac', '1', '-i', '-',
                        '-af', 'highpass=f=60,highshelf=f=1500:g=4', '-f', 'f32le', '-'], input=x.astype(np.float32).tobytes(), capture_output=True, check=True)
    return np.frombuffer(r.stdout, dtype=np.float32)


def window_db(x, win):
    h = int(SR * win)
    if len(x) < h:
        x = np.pad(x, (0, h - len(x)))
    c = np.cumsum(np.concatenate([[0.0], x.astype(np.float64) ** 2]))
    return 10 * np.log10((c[h:] - c[:-h]) / h + 1e-12)


def punch_db(x):
    return float(window_db(kweight(x), 0.05).max())


def find_start(x, mode):
    """auto — первый удар (огибающая поднялась до -12 дБ от максимума); loud — самое громкое место."""
    e = window_db(x, 0.005)[::int(SR * 0.005)]
    if mode == 'loud':
        return max(0.0, float(np.argmax(window_db(x, 0.3))) / SR - 0.1)
    i = int(np.argmax(e > e.max() - 12))
    while i > 0 and e[i - 1] < e[i] and e[i - 1] > e.max() - 30:  # отступаем к началу подъёма
        i -= 1
    return max(0.0, i * 0.005 - 0.005)


def clip(x, start, dur, fout, pitch):
    s = int(start * SR)
    y = x[s:s + int(dur * pitch * SR)].copy()
    if pitch != 1.0:
        idx = np.arange(0, len(y) - 1, pitch)
        y = np.interp(idx, np.arange(len(y)), y).astype(np.float32)
    fi = min(len(y), int(0.002 * SR))
    y[:fi] *= np.linspace(0, 1, fi)
    fo = min(len(y), int(fout * SR))
    y[len(y) - fo:] *= np.linspace(1, 0, fo) ** 2
    return y


def limit(x):
    """Лимитер с быстрой атакой: пики не выше -1 dBFS, громкость на слух почти не меняется."""
    r = subprocess.run(['ffmpeg', '-v', 'quiet', '-f', 'f32le', '-ar', str(SR), '-ac', '1', '-i', '-',
                        '-af', 'alimiter=limit=0.89:attack=0.5:release=40:level=disabled', '-f', 'f32le', '-'],
                       input=np.pad(x, (0, SR // 10)).tobytes(), capture_output=True, check=True)
    return np.frombuffer(r.stdout, dtype=np.float32)[:len(x)].copy()


def write_ogg(y, path):
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'f32le', '-ar', str(SR), '-ac', '1', '-i', '-',
                    '-c:a', 'libvorbis', '-q:a', '5', path], input=y.astype(np.float32).tobytes(), check=True)


def build_engine(out_dir):
    """Гул двигателя: ровный участок реактивного рёва, шов цикла закрыт кроссфейдом 0,5 с."""
    x = load(fetch('blast_off'))
    seg = x[int(1.0 * SR):int(6.5 * SR)].copy()
    n = int(0.5 * SR)
    fade = np.linspace(0, 1, n)
    loop = np.concatenate([seg[:n] * fade + seg[-n:] * (1 - fade), seg[n:-n]])
    rms = 10 * np.log10(np.mean(kweight(loop).astype(np.float64) ** 2) + 1e-12)
    loop = loop * 10 ** ((ENGINE_RMS - rms) / 20)
    if np.abs(loop).max() > 0.89:
        loop *= 0.89 / np.abs(loop).max()
    write_ogg(loop, os.path.join(out_dir, 'engine.ogg'))
    print('engine         blast_off    loop %.1f s' % (len(loop) / SR))


def main():
    out_dir = sys.argv[sys.argv.index('--out') + 1] if '--out' in sys.argv else AUDIO
    only = sys.argv[sys.argv.index('--only') + 1].split(',') if '--only' in sys.argv else None
    os.makedirs(out_dir, exist_ok=True)
    if only is None or 'engine' in only:
        build_engine(out_dir)
    for event, variants in PLAN.items():
        if only is not None and event not in only:
            continue
        target = REF_PUNCH[event]
        for f in glob.glob(os.path.join(out_dir, event + '.ogg')) + glob.glob(os.path.join(out_dir, event + '_[0-9].ogg')):
            os.remove(f)
        for i, (key, start, dur, fout, pitch) in enumerate(variants, 1):
            x = load(fetch(key))
            if isinstance(start, str):
                start = find_start(x, start)
            y = clip(x, start, dur, fout, pitch)
            y = (y * 10 ** ((target - punch_db(y)) / 20)).astype(np.float32)
            if np.abs(y).max() > 0.89:  # пик выше -1 dBFS: срезаем лимитером, а не убавляем весь звук
                y = limit(y)
            name = event if len(variants) == 1 else '%s_%d' % (event, i)
            write_ogg(y, os.path.join(out_dir, name + '.ogg'))
            print('%-14s %-12s start %.3f  ref %.1f dB  got %.1f dB' % (name, key, start, target, punch_db(y)))


if __name__ == '__main__':
    main()
