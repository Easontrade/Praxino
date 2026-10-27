// Praxino light denoise shader (original code, MIT).
//
// The libmpv bundled with media_kit is built without most FFmpeg filters,
// including hqdn3d, so denoising runs in the GPU shader chain instead of a
// lavfi filter. A small weighted 3x3 blur is enough for the "light denoise"
// toggle and keeps hardware decoding (no copy-back) possible.

//!DESC Praxino-light-denoise
//!HOOK MAIN
//!BIND HOOKED
//!SAVE MAIN
//!WIDTH HOOKED.w
//!HEIGHT HOOKED.h
//!COMPONENTS 4

vec4 hook() {
    vec2 p = HOOKED_pt;
    vec4 sum = HOOKED_tex(HOOKED_pos) * 0.4;
    sum += HOOKED_tex(HOOKED_pos + vec2(-p.x, -p.y)) * 0.075;
    sum += HOOKED_tex(HOOKED_pos + vec2(0.0, -p.y)) * 0.075;
    sum += HOOKED_tex(HOOKED_pos + vec2(p.x, -p.y)) * 0.075;
    sum += HOOKED_tex(HOOKED_pos + vec2(-p.x, 0.0)) * 0.075;
    sum += HOOKED_tex(HOOKED_pos + vec2(p.x, 0.0)) * 0.075;
    sum += HOOKED_tex(HOOKED_pos + vec2(-p.x, p.y)) * 0.075;
    sum += HOOKED_tex(HOOKED_pos + vec2(0.0, p.y)) * 0.075;
    sum += HOOKED_tex(HOOKED_pos + vec2(p.x, p.y)) * 0.075;
    return sum;
}
