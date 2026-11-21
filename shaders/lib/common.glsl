// Starling Visuals 3.0: the uniforms every program reads, and the light, sky and lens model.
// Colours are linear and in the scene's own units: the sun gives about SUN_STRENGTH, the open
// sky a fraction of it, and the final pass is the only place display gamma is applied.
//
// The model is split in two so a phone pays for what it can see: `skyAmbient` is the cheap,
// direction-free sky that vertex lighting and the haze read, and `skyRadiance` is the full
// directional sky that only the pixels actually looking at the sky (and water) evaluate.

#include "/lib/settings.glsl"

uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform vec3 sunPosition;
uniform vec3 shadowLightPosition;
uniform vec3 cameraPosition;
uniform float rainStrength;
uniform float wetness;
uniform float thunderStrength;
uniform float far;
uniform float nightVision;
uniform float blindness;
uniform float darknessFactor;
uniform float screenBrightness;
uniform float frameTimeCounter;
uniform float viewWidth;
uniform float viewHeight;
uniform int isEyeInWater;
uniform int worldTime;
uniform int moonPhase;

// A gamma-space scene (Minecraft's textures and vertex colours) to linear light, and back.
vec3 toLinear(vec3 c) {
    return pow(max(c, 0.0), vec3(2.2));
}

vec3 toDisplay(vec3 c) {
    return pow(max(c, 0.0), vec3(1.0 / 2.2));
}

float luma(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}

// A smooth two-dimensional value noise: four hashes, for the milky way's dust and the aurora's
// folds. The old 3D version cost eight hashes per tap and was only ever read on the sky.
float valueNoise2(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash12(i);
    float b = hash12(i + vec2(1.0, 0.0));
    float c = hash12(i + vec2(0.0, 1.0));
    float d = hash12(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// World-space directions of the sun and of the light that casts shadows (the moon at night).
vec3 sunDir() {
    return normalize(mat3(gbufferModelViewInverse) * sunPosition);
}

vec3 keyLightDir() {
    return normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
}

// 0 at night, 1 by day, crossing over while the sun is near the horizon.
float daylight(vec3 s) {
    return smoothstep(-0.12, 0.10, s.y);
}

// Sunlight once it has crossed the air: the lower the sun, the longer the path and the redder.
vec3 sunlight(vec3 s) {
    float air = 1.0 / (max(s.y, 0.0) + 0.07);
    vec3 transmitted = exp(-vec3(0.045, 0.11, 0.26) * air);
    return transmitted * smoothstep(-0.04, 0.06, s.y) * SUN_STRENGTH * (1.0 - rainStrength * 0.8);
}

vec3 moonlight(vec3 s) {
    return vec3(0.035, 0.05, 0.09) * smoothstep(0.0, -0.10, s.y) * (1.0 - rainStrength * 0.6);
}

// The sky's radiance along a world-space direction `d`, the sun at `s`. This is the full,
// directional sky: a Rayleigh zenith, a warm horizon, two Mie lobes around the sun and the
// moon's own cool halo. It is evaluated for sky pixels, water and the sun disk, not for every
// lit vertex (see `skyAmbient`).
vec3 skyRadiance(vec3 d, vec3 s) {
    float day = daylight(s);
    float lowSun = 1.0 - smoothstep(0.0, 0.4, abs(s.y));
    float up = clamp(d.y, 0.0, 1.0);
    float horizon = pow(1.0 - up, 5.0);

    vec3 zenith = mix(vec3(0.0016, 0.0038, 0.011), vec3(0.042, 0.118, 0.45), day);
    vec3 rim = mix(vec3(0.0045, 0.0065, 0.014), vec3(0.31, 0.47, 0.80) * (1.0 - 0.40 * lowSun), day);
    vec3 color = mix(zenith, rim, horizon);

    // The sun warms the horizon around it; a broad Mie haze surrounds it all day, a tight
    // aureole sits inside it, and at night the moon has its own much cooler halo.
    float toward = max(dot(d, s), 0.0);
    color += vec3(1.00, 0.42, 0.14) * lowSun * day * pow(toward, 4.0) * horizon * 2.6;
    color += vec3(1.00, 0.55, 0.28) * lowSun * day * pow(toward, 2.0) * horizon * 0.9;
    color += sunlight(s) * (0.55 / SUN_STRENGTH) * (pow(toward, 256.0) * 0.9 + pow(toward, 24.0) + 0.40 * pow(toward, 5.0));
    color += vec3(0.10, 0.16, 0.32) * (1.0 - day) * pow(max(dot(d, keyLightDir()), 0.0), 20.0) * 0.35;
    color += vec3(0.05, 0.09, 0.20) * (1.0 - day) * pow(max(dot(d, keyLightDir()), 0.0), 6.0) * 0.18;

    // Under the horizon, hazy land as far as the horizon's colour, darker looking further down.
    color *= mix(1.0, 0.5, smoothstep(0.1, 0.7, -d.y));
    color = mix(color, vec3(luma(color) * 0.85), rainStrength * 0.85);
    color = mix(color, vec3(luma(color)), (1.0 - day) * 0.25);
    return color * SKY_BRIGHTNESS * SKY_SATURATION;
}

// The cheap sky: one average of the zenith and the horizon, no direction-dependent lobes. This
// is what fills the world's shadowed side and colours the haze, so it runs per vertex and per
// terrain pixel; the full `skyRadiance` above is kept for the pixels that actually see sky.
vec3 skyAmbient(vec3 s) {
    float day = daylight(s);
    float lowSun = 1.0 - smoothstep(0.0, 0.4, abs(s.y));
    vec3 zenith = mix(vec3(0.0016, 0.0038, 0.011), vec3(0.042, 0.118, 0.45), day);
    vec3 rim = mix(vec3(0.0045, 0.0065, 0.014), vec3(0.31, 0.47, 0.80), day);
    vec3 color = zenith * 0.62 + rim * 0.38;
    // The warm band a low sun puts along the horizon, averaged into the fill.
    color += vec3(1.00, 0.42, 0.16) * lowSun * day * 0.055;
    color = mix(color, vec3(luma(color) * 0.88), rainStrength * 0.85);
    color = mix(color, vec3(luma(color)), (1.0 - day) * 0.25);
    return color * SKY_BRIGHTNESS * SKY_SATURATION;
}

// The night sky's own detail: two layers of stars on a cell grid, a faint milky way, and an
// aurora low over the horizon. `t` is seconds; a star's twinkle is deterministic.
vec3 nightSky(vec3 d, vec3 s, float t) {
    float night = 1.0 - daylight(s);
    if (night <= 0.001 || d.y < -0.08) return vec3(0.0);
    night *= 1.0 - rainStrength;
    if (night <= 0.001) return vec3(0.0);
    vec3 color = vec3(0.0);

    // The milky way: a broad band tilted across the sky, broken by cheap 2D dust.
    vec3 bandNormal = normalize(vec3(0.25, 0.32, 0.91));
    float band = pow(1.0 - abs(dot(d, bandNormal)), 9.0);
    vec2 q = d.xz / max(d.y + 0.35, 0.15);
    float dust = 0.55 + 0.45 * valueNoise2(q * 3.2 + vec2(13.0, 4.0));
    color += vec3(0.030, 0.034, 0.060) * band * dust * night * smoothstep(-0.05, 0.25, d.y);

    // Three star layers now: a dim field, a bright field and a few very bright ones, so the
    // sky has depth instead of a single sprinkle of points.
    for (int layer = 0; layer < 3; layer++) {
        float scale = layer == 0 ? 110.0 : (layer == 1 ? 230.0 : 410.0);
        vec3 p = d * scale + float(layer) * 17.0;
        vec3 cell = floor(p);
        vec3 f = fract(p) - 0.5;
        float h = hash13(cell);
        float threshold = layer == 0 ? 0.978 : (layer == 1 ? 0.988 : 0.996);
        float star = smoothstep(0.12, 0.0, length(f)) * smoothstep(threshold, 1.0, h);
        float twinkle = 0.60 + 0.40 * sin(t * (1.1 + h * 2.9) + h * 61.0);
        vec3 tint = mix(vec3(0.72, 0.82, 1.0), vec3(1.0, 0.88, 0.72), hash13(cell + 7.0));
        color += tint * star * twinkle * night * (layer == 0 ? 0.45 : (layer == 1 ? 0.8 : 1.25));
    }

    // A faint nebula: a coloured cloud across the upper sky, so the night is not pure black.
    {
        vec2 q = d.xz / max(d.y + 0.25, 0.12);
        float n1 = valueNoise2(q * 2.4 + vec2(3.0, 7.0));
        float n2 = valueNoise2(q * 5.1 - vec2(11.0, 2.0));
        float neb = pow(n1, 2.0) * (0.5 + 0.5 * n2);
        neb *= smoothstep(0.05, 0.45, d.y) * night;
        color += mix(vec3(0.18, 0.08, 0.32), vec3(0.06, 0.22, 0.38), n2) * neb * 0.18;
    }

#ifdef AURORA
    // A curtain of green and violet light: two overlapping sheets, strongest low in the north.
    // Only the north half of the sky can show one, so the rest skips the noise entirely.
    if (d.z > 0.02 && d.y > 0.0) {
        float north = smoothstep(0.02, 0.6, d.z) * smoothstep(0.0, 0.18, d.y);
        vec2 p = d.xz / max(d.y + 0.18, 0.04);
        float sheet = 0.5 + 0.5 * sin(p.y * 2.2 + t * 0.11 + valueNoise2(p * 1.7 + vec2(t * 0.05)) * 5.2);
        float curtain = pow(sheet, 3.0) * exp(-abs(p.x) * 0.55);
        float folds = 0.6 + 0.4 * valueNoise2(p * 4.0 + vec2(t * 0.08));
        color += mix(vec3(0.06, 0.55, 0.32), vec3(0.42, 0.12, 0.75), 0.35)
            * curtain * folds * north * night * AURORA_STRENGTH;
    }
#endif

    return color;
}

// The game's lightmap coordinates (block, sky) as 0..1 light levels.
vec2 lightLevels(vec2 lm) {
    return clamp((lm - 1.0 / 32.0) * (16.0 / 15.0), 0.0, 1.0);
}

// The sun's or moon's light on a surface facing `n` (world space), before shadows. `wrap` lights
// both sides of thin plants.
vec3 keyLightAt(vec3 n, float wrap) {
    vec3 s = sunDir();
    float facing = dot(n, keyLightDir());
    float lit = mix(clamp(facing, 0.0, 1.0), abs(facing) * 0.6 + 0.4, wrap);
    return (sunlight(s) + moonlight(s)) * lit;
}

// Everything else reaching it with light levels `levels`: the sky around, the warm light the
// sunlit ground sends back, torches, and a floor that keeps caves readable. One cheap sky
// sample, not two full directional ones: the fill is an average by nature.
vec3 fillLightAt(vec3 n, vec2 levels) {
    vec3 s = sunDir();
    vec3 sky = skyAmbient(s);
    vec3 ambient = mix(vec3(luma(sky)), sky, 0.5) * 1.35 * (0.72 + 0.28 * n.y);
    // The ground bounces a little of the sun back onto down-facing faces, warm and weak.
    vec3 bounce = sunlight(s) * max(s.y, 0.0) * 0.18 * (0.5 - 0.5 * n.y) * vec3(1.0, 0.92, 0.82);
    float sky2 = levels.y * levels.y;
    float block = levels.x;
    vec3 torch = vec3(1.0, 0.56, 0.26) * (pow(block, 4.0) * 1.8 + block * 0.08) * BLOCKLIGHT_STRENGTH;
    vec3 floorLight = vec3(0.012, 0.013, 0.016) + nightVision * 0.3;
    floorLight *= mix(1.0, 0.35, clamp(darknessFactor + blindness, 0.0, 1.0));
    return (ambient + bounce) * sky2 + torch + floorLight;
}

// Without the shadow map (past its reach, or shadows off): where the sky can't see, the sun
// doesn't either.
float openSky(vec2 levels) {
    return smoothstep(0.7, 0.97, levels.y);
}

// The shadow map's own distortion: points near the player get more of its texels.
vec2 distortShadow(vec2 p) {
    return p / (length(p) * SHADOW_DISTORTION + (1.0 - SHADOW_DISTORTION));
}

// A normalized Blinn-Phong lobe. The old code returned the peak of the lobe itself (about four
// for a polished surface) and multiplied it by a full sun's irradiance, so a flat top face at
// noon had its whole surface in the highlight and clipped to white. The caller now also gives a
// Fresnel weight, so the lobe only becomes strong at the grazing angles where a real surface
// reflects: a wet or icy face, not every block's roof.
float specular(vec3 n, vec3 v, vec3 l, float power) {
    vec3 h = normalize(l + v);
    float d = max(dot(n, h), 0.0);
    float nl = max(dot(n, l), 0.0);
    return pow(d, power) * nl * (power + 8.0) / 25.1327;
}

// Schlick's Fresnel: 4% head-on, nearly all of it at a grazing look. This is what keeps the
// sun's image on a wet street and off a dry roof.
float fresnel(vec3 n, vec3 v) {
    return 0.04 + 0.96 * pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 5.0);
}

// ACES: the RRT + ODT shoulder fitted by Stephen Hill, with the standard sRGB/AP0 conversion on
// each side. Compared with the old compact fit it keeps the hue of a sunset and the colour of
// lava while it rolls off, and it never reaches a flat 1.0: the top of the range stays a colour.
vec3 tonemapACES(vec3 color) {
    // GLSL's mat3 constructor takes columns, so each matrix is written column by column; every
    // row sums to one, which keeps a neutral grey neutral.
    const mat3 inputMatrix = mat3(
        0.6131, 0.0702, 0.0206,
        0.3395, 0.9164, 0.1096,
        0.0474, 0.0134, 0.8698);
    const mat3 outputMatrix = mat3(
         1.7050, -0.1302, -0.0240,
        -0.6217,  1.1408, -0.1289,
        -0.0833, -0.0106,  1.1529);
    color = inputMatrix * color;
    vec3 a = color * (color + 0.0245786) - 0.000090537;
    vec3 b = color * (0.983729 * color + 0.4329510) + 0.238081;
    return clamp(outputMatrix * (a / b), 0.0, 1.0);
}

// A soft filmic shoulder (the Uncharted 2 curve) with a true black. It keeps more of the
// midtone lift than ACES and is the gentler option for a small, bright phone screen.
vec3 tonemapFilmic(vec3 x) {
    vec3 a = max(x - 0.004, 0.0);
    a = (a * (6.2 * a + 0.5)) / (a * (6.2 * a + 1.7) + 0.06);
    return clamp(a, 0.0, 1.0);
}

vec3 tonemapReinhard(vec3 x) {
    const float white = 4.0;
    return clamp(x * (1.0 + x / (white * white)) / (1.0 + x), 0.0, 1.0);
}

vec3 tonemap(vec3 x) {
    x *= EXPOSURE;
#if TONEMAP == 0
    x = tonemapACES(x);
#elif TONEMAP == 1
    x = tonemapFilmic(x);
#else
    x = tonemapReinhard(x);
#endif
    // Saturation after the curve, where it reads the way a photograph's does, then a film-like
    // desaturation of the very brightest values so nothing ends as a flat sheet of white.
    x = mix(vec3(luma(x)), x, SATURATION);
    float peak = smoothstep(0.78, 1.0, max(x.r, max(x.g, x.b)));
    x = mix(x, vec3(luma(x)), peak * 0.28);
    return clamp(x, 0.0, 1.0);
}
