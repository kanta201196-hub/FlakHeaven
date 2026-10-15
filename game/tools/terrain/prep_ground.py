# B-25: CC0-текстуры земли с Poly Haven -> game/art/ground/pbr/
#   <слот>_albedo.jpg — цвет; <слот>_nh.jpg — R,G нормаль (OpenGL), B высота.
# Запуск из корня репозитория: python3 game/tools/terrain/prep_ground.py [слот ...]
import io, json, os, sys, urllib.request
from PIL import Image

RES = "2k"
SLOTS = {  # слот шейдера -> набор Poly Haven (CC0)
    "sand": "gravelly_sand",
    "clay": "mud_cracked_dry_riverbed_002",
    "gravel": "dry_ground_rocks",
    "river": "river_small_rocks",
    "rock": "cliff_side",          # B-26: склоны и обрывы (проекция с трёх сторон)
}
OUT = "game/art/ground/pbr"


def get(url):
    # без своего User-Agent API Poly Haven отвечает 403
    req = urllib.request.Request(url, headers={"User-Agent": "FlakHeaven-prep/1.0"})
    return urllib.request.urlopen(req, timeout=120).read()


os.makedirs(OUT, exist_ok=True)
lic = []
for slot, asset in SLOTS.items():
    if len(sys.argv) > 1 and slot not in sys.argv[1:]:
        continue
    files = json.loads(get("https://api.polyhaven.com/files/" + asset))
    info = json.loads(get("https://api.polyhaven.com/info/" + asset))
    img = lambda key, fmt="jpg": Image.open(io.BytesIO(get(files[key][RES][fmt]["url"])))
    alb = img("Diffuse").convert("RGB")
    alb.save(f"{OUT}/{slot}_albedo.jpg", quality=92)
    nor = img("nor_gl").convert("RGB").resize(alb.size)
    disp = img("Displacement", "png").convert("L").resize(alb.size)
    r, g, _ = nor.split()
    Image.merge("RGB", (r, g, disp)).save(f"{OUT}/{slot}_nh.jpg", quality=95)
    lic.append(f"| `pbr/{slot}_*` | {info['name']} (`{asset}`) | {', '.join(info.get('authors', {}))} | https://polyhaven.com/a/{asset} |")
    print(slot, asset, alb.size)
print("\n".join(lic))
