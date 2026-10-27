# Motion-compensated frame interpolation for mpv's vapoursynth filter.
#
# mpv injects `video_in` (the decoded clip) and `container_fps`.
# Requires the VapourSynth mvtools plugin. Output is ~60 fps (59.94 for
# NTSC-style sources) so it lines up with common 60 Hz displays.
import vapoursynth as vs

core = vs.core

clip = video_in  # noqa: F821 - provided by mpv
src_fps = container_fps if container_fps > 0.1 else 23.976  # noqa: F821

if clip.format.id != vs.YUV420P8:
    clip = core.resize.Bilinear(clip, format=vs.YUV420P8)

num, den = (60000, 1001) if abs(src_fps - round(src_fps)) > 0.01 else (60, 1)
# Normalise the input timing so FlowFPS gets a constant frame rate.
clip = core.std.AssumeFPS(clip, fpsnum=int(round(src_fps * 1000)), fpsden=1000)

sup = core.mv.Super(clip, pel=2, hpad=16, vpad=16)
backward = core.mv.Analyse(sup, isb=True, blksize=16, overlap=4, truemotion=True)
forward = core.mv.Analyse(sup, isb=False, blksize=16, overlap=4, truemotion=True)
clip = core.mv.FlowFPS(clip, sup, backward, forward, num=num, den=den)

clip.set_output()
