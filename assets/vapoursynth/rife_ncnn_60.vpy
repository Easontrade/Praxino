# RIFE fixed-60fps variant for mpv's vapoursynth filter.
# Same runtime requirements as rife_ncnn.vpy; the factor is chosen so the
# output lands near 60 fps for 23.976 / 24 / 25 / 30 fps sources.
import os

import vapoursynth as vs

core = vs.core

clip = video_in  # noqa: F821 - provided by mpv
src_fps = container_fps if container_fps > 0.1 else 23.976  # noqa: F821

model_dir = os.environ.get("PRAXINO_RIFE_MODEL") or os.path.join(
    os.path.dirname(vs.__file__), "plugins", "models", "rife-v4.6"
)

target = 60.0
factor_num = max(1, int(round(target / src_fps * 1000)))
factor_den = 1000

clip = core.std.AssumeFPS(clip, fpsnum=int(round(src_fps * 1000)), fpsden=1000)

matrix = "709" if clip.height >= 720 else "170m"
rgb = core.resize.Bicubic(clip, format=vs.RGBS, matrix_in_s=matrix)
rgb = core.rife.RIFE(
    rgb,
    model_path=model_dir,
    factor_num=factor_num,
    factor_den=factor_den,
    sc=True,
    gpu_thread=4,
)
clip = core.resize.Bicubic(rgb, format=vs.YUV420P8, matrix_s=matrix)

clip.set_output()
