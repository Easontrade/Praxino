# RIFE frame interpolation for mpv's vapoursynth filter (Vulkan, any GPU).
#
# mpv injects `video_in` (the decoded clip) and `container_fps`.
# Requires the VapourSynth-RIFE-ncnn-Vulkan plugin (`core.rife`) and a RIFE v4
# model folder (flownet.param / flownet.bin). The model is looked up in
#   1. the PRAXINO_RIFE_MODEL environment variable, else
#   2. <vapoursynth>/plugins/models/rife-v4.6 next to the VapourSynth install.
# Output is 2x the source rate (23.976 -> 47.952, 30 -> 60). Interpolating to
# a fixed 60 fps needs an inference for 4 of every 5 output frames instead of
# 1 of 2; at 1080p that saturated an RTX 5080 (~40 fps) while 2x ran at ~60.
import os

import vapoursynth as vs

core = vs.core

clip = video_in  # noqa: F821 - provided by mpv
src_fps = container_fps if container_fps > 0.1 else 23.976  # noqa: F821

model_dir = os.environ.get("PRAXINO_RIFE_MODEL") or os.path.join(
    os.path.dirname(vs.__file__), "plugins", "models", "rife-v4.6"
)

clip = core.std.AssumeFPS(clip, fpsnum=int(round(src_fps * 1000)), fpsden=1000)

matrix = "709" if clip.height >= 720 else "170m"
rgb = core.resize.Bicubic(clip, format=vs.RGBS, matrix_in_s=matrix)
# sc=True skips interpolation across scene cuts using the plugin's own detector.
rgb = core.rife.RIFE(
    rgb, model_path=model_dir, factor_num=2, factor_den=1, sc=True, gpu_thread=4
)
clip = core.resize.Bicubic(rgb, format=vs.YUV420P8, matrix_s=matrix)

clip.set_output()
