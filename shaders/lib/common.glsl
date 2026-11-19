// Starling Visuals 2: the uniforms every program reads, and the light, sky and lens model.
// Colours are linear and in the scene's own units: the sun gives about SUN_STRENGTH, the open
// sky a fraction of it, and the final pass is the only place display gamma is applied.

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

vec3 toLinear(vec3 c) {
    return pow(c, vec3(2.2));
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

// A smooth three-dimensional value noise, for the rare places a little structure helps (the
// milky way, the aurora, the wet sheen on stone). It is not used per pixel unless a switch asks.
float valueNoise3(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float n000 = hash13(i + vec3(0.0, 0.0, 0.0));
    float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
    float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
    float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
    float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
    float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
    float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
    float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
    return mix(
        mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
        mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
        f.z);
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

// The sky's radiance along a world-space direction `d`, the sun at `s`. It is the base sky, not
// the stars or the aurora: the vertex lighting reads this too, and a star is not fill light.
vec3 skyRadiance(vec3 d, vec3 s) {
    float day = daylight(s);
    float lowSun = 1.0 - smoothstep(0.0, 0.4, abs(s.y));
    float up = clamp(d.y, 0.0, 1.0);
    float horizon = pow(1.0 - up, 5.0);

    vec3 zenith = mix(vec3(0.0015, 0.0035, 0.010), vec3(0.040, 0.115, 0.44), day);
    vec3 rim = mix(vec3(0.004, 0.006, 0.013), vec3(0.30, 0.46, 0.78) * (1.0 - 0.42 * lowSun), day);
    vec3 color = mix(zenith, rim, horizon);

    // The sun warms the horizon around it; a broad halo surrounds it all day, and at night the
    // moon has its own much cooler one.
    float toward = max(dot(d, s), 0.0);
    color += vec3(1.0, 0.38, 0.10) * lowSun * day * pow(toward, 4.0) * horizon * 2.4;
    color += sunlight(s) * (0.55 / SUN_STRENGTH) * pow(toward, 32.0);
    color += vec3(0.10, 0.16, 0.32) * (1.0 - day) * pow(max(dot(d, keyLightDir()), 0.0), 24.0) * 0.35;

    // Under the horizon, hazy land as far as the horizon's colour, darker looking further down.
    color *= mix(1.0, 0.5, smoothstep(0.1, 0.7, -d.y));
    color = mix(color, vec3(luma(color) * 0.8), rainStrength * 0.85);
    color = mix(color, vec3(luma(color)), (1.0 - day) * 0.25);
    return color * SKY_BRIGHTNESS * SKY_SATURATION;
}

// The night sky's own detail: two layers of stars on a cell grid, a faint milky way, and an
// aurora low over the horizon. `t` is seconds; a star's twinkle is deterministic.
vec3 nightSky(vec3 d, vec3 s, float t) {
    float night = 1.0 - daylight(s);
    if (night <= 0.001 || d.y < -0.08) return vec3(0.0);
    night *= 1.0 - rainStrength;
    vec3 color = vec3(0.0);

    // The milky way: a broad band tilted across the sky, broken by noise.
    vec3 bandNormal = normalize(vec3(0.25, 0.32, 0.91));
    float band = pow(1.0 - abs(dot(d, bandNormal)), 9.0);
    float dust = 0.55 + 0.45 * valueNoise3(d * 7.0 + vec3(13.0, 4.0, 27.0));
    color += vec3(0.030, 0.034, 0.060) * band * dust * night * smoothstep(-0.05, 0.25, d.y);

    // Two star layers. A cell holds at most one star; the threshold leaves most cells empty.
    for (int layer = 0; layer < 2; layer++) {
        float scale = layer == 0 ? 130.0 : 260.0;
        vec3 p = d * scale + float(layer) * 17.0;
        vec3 cell = floor(p);
        vec3 f = fract(p) - 0.5;
        float h = hash13(cell);
        float threshold = layer == 0 ? 0.982 : 0.991;
        float star = smoothstep(0.10, 0.0, length(f)) * smoothstep(threshold, 1.0, h);
        float twinkle = 0.65 + 0.35 * sin(t * (1.3 + h * 2.7) + h * 61.0);
        vec3 tint = mix(vec3(0.72, 0.82, 1.0), vec3(1.0, 0.88, 0.72), hash13(cell + 7.0));
        color += tint * star * twinkle * night * (layer == 0 ? 0.55 : 0.9);
    }

#ifdef AURORA
    // A curtain of green and violet light: two overlapping sheets, strongest low in the north.
    float north = smoothstep(0.02, 0.6, d.z) * smoothstep(0.0, 0.18, d.y);
    vec2 p = d.xz / max(d.y + 0.18, 0.04);
    float sheet = 0.5 + 0.5 * sin(p.y * 2.2 + t * 0.11 + valueNoise3(vec3(p * 1.7, t * 0.05)) * 5.2);
    float curtain = pow(sheet, 3.0) * exp(-abs(p.x) * 0.55);
    float folds = 0.6 + 0.4 * valueNoise3(vec3(p * 4.0, t * 0.08));
    color += mix(vec3(0.06, 0.55, 0.32), vec3(0.42, 0.12, 0.75), 0.35)
        * curtain * folds * north * night * AURORA_STRENGTH;
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

// Everything else reaching it with light levels `levels`: the sky around (half its colour, the
// rest grey), the warm light the sunlit ground sends back, torches, and a floor that keeps caves
// readable.
vec3 fillLightAt(vec3 n, vec2 levels) {
    vec3 s = sunDir();
    // The sky's light is about the average of the zenith and a horizon away from the sun, and
    // nearer white than either.
    vec3 sky = 0.5 * (skyRadiance(vec3(0.0, 1.0, 0.0), s) + skyRadiance(normalize(vec3(-s.x, 0.1, -s.z)), s));
    vec3 ambient = mix(vec3(luma(sky)), sky, 0.4) * 1.6 * (0.75 + 0.25 * n.y);
    vec3 bounce = sunlight(s) * max(s.y, 0.0) * 0.2 * (0.5 - 0.5 * n.y);
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

// A cheap GGX-shaped highlight: `n` and `v` are unit vectors, `power` the surface's gloss. It
// is not a full BRDF; it is the sun's image on a wet or polished face, which is most of what a
// player reads as "surface" in a block game.
float specular(vec3 n, vec3 v, vec3 l, float power) {
    vec3 h = normalize(l + v);
    float d = max(dot(n, h), 0.0);
    return pow(d, power) * (power + 8.0) / 25.1327;
}

// The ACES film curve (Narkowicz's fit), a soft log shoulder, and a plain Reinhard fallback.
vec3 tonemapACES(vec3 x) {
    x = clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);
    return x;
}

vec3 tonemapAgX(vec3 x) {
    // A compact, hue-preserving approximation of AgX's log shoulder: the scene is compressed
    // around middle grey before the display curve, which keeps sunsets and lava from clipping
    // to one flat colour.
    const float middleGrey = 0.18;
    vec3 a = log2(max(x / middleGrey, 1e-6) + 1.0);
    a = a / (a + 1.35);
    return clamp(a, 0.0, 1.0);
}

vec3 tonemapReinhard(vec3 x) {
    return clamp(x / (1.0 + x), 0.0, 1.0);
}

vec3 tonemap(vec3 x) {
    x *= EXPOSURE;
#if TONEMAP == 0
    x = tonemapACES(x);
#elif TONEMAP == 1
    x = tonemapAgX(x);
#else
    x = tonemapReinhard(x);
#endif
    // Saturation after the curve, where it reads the way a photograph's does.
    return clamp(mix(vec3(luma(x)), x, SATURATION), 0.0, 1.0);
}
