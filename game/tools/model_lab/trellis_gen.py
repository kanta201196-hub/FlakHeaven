# «Оса» через TRELLIS.2 (microsoft-trellis-2.hf.space, MIT). Нужен HF_TOKEN в окружении (квота ZeroGPU).
# python3 trellis_gen.py <in.png> <seed> <out.glb>
import os, sys, shutil, time
from gradio_client import Client, handle_file
src, seed, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
c = Client("https://microsoft-trellis-2.hf.space/", token=os.environ.get("HF_TOKEN"))
t = time.time()
c.predict(api_name="/start_session")
img = c.predict(handle_file(src), api_name="/preprocess_image")
c.predict(handle_file(img), seed, "1024", 7.5, 0.7, 12, 5.0, 7.5, 0.5, 12, 3.0, 1.0, 0.0, 12, 3.0, api_name="/image_to_3d")
g = c.predict(100000, 1024, api_name="/extract_glb")
shutil.copy(g[0] if isinstance(g, (list, tuple)) else g, out)
print("GLB:", out, round(time.time() - t), "с")
