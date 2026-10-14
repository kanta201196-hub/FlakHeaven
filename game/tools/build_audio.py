import subprocess, os, shutil, glob
EX='ex'; K=EX+'/kenney_sci-fi-sounds/Audio/'; I=EX+'/kenney_impact-sounds/Audio/'; D=EX+'/kenney_digital-audio/Audio/'
U=EX+'/kenney_interface-sounds/Audio/'; J=EX+'/kenney_music-jingles/Audio/'; G=EX+'/impacts/Impacts/'; C=EX+'/chip/'
DL='/mnt/user-data/uploads/Downloads/'
OUT='out'
os.makedirs(OUT, exist_ok=True)
for f in glob.glob(OUT+'/*'): os.remove(f)

def make(name, src, start=0.0, dur=None, fin=0.0, fout=0.0, pitch=1.0, gain_db=0.0, layer=None, layer_db=-6.0, stereo=False):
    inputs=['-i', src] + (['-i', layer] if layer else [])
    chain=f"[0:a]atrim=start={start}" + (f":duration={dur}" if dur else "") + ",asetpts=PTS-STARTPTS"
    if pitch!=1.0:
        chain+=f",aresample=44100,asetrate={int(44100*pitch)},aresample=44100"
    if fin>0: chain+=f",afade=t=in:d={fin}"
    if fout>0 and dur: chain+=f",afade=t=out:st={max(0,dur/pitch-fout)}:d={fout}"
    chain+="[a0]"
    if layer:
        chain+=f";[1:a]volume={layer_db}dB[a1];[a0][a1]amix=inputs=2:duration=first:normalize=0[a2]"
        last='[a2]'
    else:
        last='[a0]'
    # нормализация пика к -3 dBFS + доп. усиление
    tmp=OUT+'/_tmp.wav'
    subprocess.run(['ffmpeg','-v','error','-y',*inputs,'-filter_complex',chain,'-map',last,'-ac','2' if stereo else '1','-ar','44100',tmp],check=True)
    r=subprocess.run(['ffmpeg','-i',tmp,'-af','volumedetect','-f','null','-'],capture_output=True,text=True).stderr
    peak=float([l for l in r.split('\n') if 'max_volume' in l][0].split(':')[1].split()[0])
    g=-3.0-peak+gain_db
    subprocess.run(['ffmpeg','-v','error','-y','-i',tmp,'-af',f'volume={g}dB','-c:a','libvorbis','-q:a','5',f'{OUT}/{name}.ogg'],check=True)
    os.remove(tmp)

# --- Курсовое и пушки (записанные выстрелы, CC0 Eldritch Grim), обрезаны до короткого «удара»
# начало выстрела в исходниках — через 0,07–0,19 с тишины, режем от атаки
for i,(n,st) in enumerate([(2,0.147),(6,0.187),(15,0.136)],1):
    make(f'gun_fire_{i}', G+f'Gunshot {n}.wav', start=st, dur=0.16, fout=0.08)
for i,(n,st) in enumerate([(14,0.187),(10,0.158)],1):
    make(f'gunpod_fire_{i}', G+f'Gunshot {n}.wav', start=st, dur=0.13, fout=0.07, pitch=1.15)
for i,(n,st) in enumerate([(1,0.114),(2,0.066),(3,0.097)],1):
    make(f'turret_fire_{i}', G+f'Pistol {n}.wav', start=st, dur=0.11, fout=0.06, pitch=1.2)
# --- Враги: яркие «бластеры» — на слух отличаются от наших выстрелов (читаемость)
make('enemy_fire_1', K+'laserRetro_002.ogg', dur=0.2, fout=0.08)
make('enemy_fire_2', K+'laserRetro_004.ogg', dur=0.2, fout=0.08)
make('flare', D+'phaseJump4.ogg', dur=0.3, fout=0.1)
# --- Ракеты
make('aam_launch_1', K+'thrusterFire_001.ogg', start=0.1, dur=0.75, fin=0.02, fout=0.45, pitch=1.25)
make('aam_launch_2', K+'thrusterFire_003.ogg', start=0.1, dur=0.75, fin=0.02, fout=0.45, pitch=1.2)
make('rocket_launch', K+'thrusterFire_004.ogg', start=0.05, dur=0.4, fin=0.01, fout=0.25, pitch=1.5)
make('missile_enemy', K+'thrusterFire_000.ogg', start=0.3, dur=0.9, fin=0.05, fout=0.5, pitch=0.9)
make('bomb_drop', D+'highDown.ogg')
# --- Взрывы
make('bomb', K+'lowFrequency_explosion_001.ogg', layer=K+'explosionCrunch_000.ogg', layer_db=-4)
make('explode_1', K+'explosionCrunch_000.ogg', dur=0.6, fout=0.3)
make('explode_2', K+'explosionCrunch_002.ogg', dur=0.6, fout=0.3)
make('explode_big_1', K+'explosionCrunch_001.ogg', layer=K+'lowFrequency_explosion_001.ogg', layer_db=-3)
make('explode_big_2', K+'explosionCrunch_003.ogg', layer=K+'lowFrequency_explosion_001.ogg', layer_db=-3)
make('player_explode', K+'explosionCrunch_004.ogg', layer=K+'lowFrequency_explosion_000.ogg', layer_db=0)
# --- Попадания
for i in range(3):
    make(f'hit_{i+1}', I+f'impactMetal_light_00{i}.ogg', dur=0.2, fout=0.1)
    make(f'pass_hit_{i+1}', I+f'impactPunch_heavy_00{i}.ogg')
    make(f'player_hit_{i+1}', I+f'impactPlate_heavy_00{i}.ogg')
make('shield_break', I+'impactGlass_heavy_001.ogg')
# --- Сигналы, навыки
make('lock', D+'twoTone1.ogg', dur=0.4, fout=0.1)
make('radio', D+'twoTone2.ogg', dur=0.22, fout=0.08, pitch=1.5)
make('roll', K+'thrusterFire_002.ogg', start=0.35, dur=0.4, fin=0.08, fout=0.25, pitch=1.3)
make('near_miss', D+'phaserDown2.ogg', pitch=1.4)
make('combat_turn', K+'thrusterFire_001.ogg', start=0.2, dur=0.6, fin=0.05, fout=0.35, pitch=0.85)
make('shield', K+'forceField_000.ogg')
make('afterburner', K+'thrusterFire_003.ogg', start=0.0, dur=1.5, fin=0.05, fout=0.7)
# --- Интерфейс и награды
make('pickup_1', U+'select_001.ogg')
make('pickup_2', U+'select_002.ogg')
make('repair', D+'powerUp2.ogg')
make('levelup', J+'8-Bit jingles/jingles_NES05.ogg')
make('card', U+'click_001.ogg')
make('ui_ban', U+'error_001.ogg')
make('boss', J+'Hit jingles/jingles_HIT11.ogg')
make('evac', J+'8-Bit jingles/jingles_NES13.ogg')
make('gate', J+'8-Bit jingles/jingles_NES09.ogg')

# --- Двигатель: зацикленный гул (CC0 theMinesAreShakin), шов закрыт кроссфейдом 0,5 с
import numpy as np
raw=subprocess.run(['ffmpeg','-v','quiet','-i',DL+'rocket_engine.001.wav','-ac','1','-ar','44100','-f','s16le','-'],capture_output=True).stdout
x=np.frombuffer(raw,dtype=np.int16).astype(np.float32); sr=44100
seg=x[int(0.3*sr):int(5.8*sr)].copy(); n=int(0.5*sr); fade=np.linspace(0,1,n)
loop=np.concatenate([seg[:n]*fade+seg[-n:]*(1-fade), seg[n:-n]]); loop=loop/np.abs(loop).max()*0.7*32767
subprocess.run(['ffmpeg','-v','error','-y','-f','s16le','-ar','44100','-ac','1','-i','-','-c:a','libvorbis','-q:a','5',OUT+'/engine.ogg'],input=loop.astype(np.int16).tobytes(),check=True)

# --- Музыка (CC0 Juhani Junkala, чиптюн)
def music(name, src):
    subprocess.run(['ffmpeg','-v','error','-y','-i',src,'-af','loudnorm=I=-16:TP=-1.5','-ar','44100','-c:a','libvorbis','-q:a','5',f'{OUT}/{name}.ogg'],check=True)
music('music_menu', C+'Juhani Junkala [Retro Game Music Pack] Title Screen.wav')
music('music_battle_1', C+'Juhani Junkala [Retro Game Music Pack] Level 1.wav')
music('music_battle_2', C+'Juhani Junkala [Retro Game Music Pack] Level 2.wav')
music('music_boss', C+'Juhani Junkala [Retro Game Music Pack] Level 3.wav')
music('music_result', C+'Juhani Junkala [Retro Game Music Pack] Ending.wav')
print(len(os.listdir(OUT)), 'files')
