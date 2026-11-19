// Starling Visuals 2: the lens. Bloom from colortex0's mipmaps (the scene at ever smaller sizes,
// which the game makes before this pass), the sun's rays from where the sky shows on the way to
// it (their alpha, at a small size: soft without many samples), a fine sharpen, then the film
// curve, the grade, the vignette and the grain. Every stage is a switch, so a phone can turn the
// expensive ones off without a second version of the pack.

#include "/lib/common.glsl"

#ifdef VERTEX_SHADER

noperspective out vec2 texcoord;

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    gl_Position = ftransform();
}

#endif

#ifdef FRAGMENT_SHADER

#if defined BLOOM || defined GODRAYS
const bool colortex0MipmapEnabled = true;
#endif

noperspective in vec2 texcoord;

uniform sampler2D colortex0;
uniform sampler2D noisetex;

// The mip level that blurs as much as level `level` would on a screen 540 pixels high, so that
// the glow keeps its size whatever the resolution.
float screenLod(float level) {
    return max(level + log2(viewHeight / 540.0), 0.0);
}

// The scene blurred over a few sizes, each read from its mip level four times around the pixel
// (a tent, without the blocks of a single read). Only what is brighter than BLOOM_THRESHOLD
// feeds it, so a white cloud does not turn the whole screen into a lamp.
vec3 bloomAt(vec2 uv) {
    vec3 sum = vec3(0.0);
    for (int i = 1; i <= 5; i++) {
        float lod = screenLod(float(i));
        vec2 texel = exp2(lod) / vec2(viewWidth, viewHeight);
        vec3 a = textureLod(colortex0, uv + texel * vec2(0.7, 0.7), lod).rgb;
        vec3 b = textureLod(colortex0, uv + texel * vec2(-0.7, 0.7), lod).rgb;
        vec3 c = textureLod(colortex0, uv + texel * vec2(0.7, -0.7), lod).rgb;
        vec3 d = textureLod(colortex0, uv + texel * vec2(-0.7, -0.7), lod).rgb;
        sum += max(a - BLOOM_THRESHOLD, 0.0) + max(b - BLOOM_THRESHOLD, 0.0)
            + max(c - BLOOM_THRESHOLD, 0.0) + max(d - BLOOM_THRESHOLD, 0.0);
    }
    return sum / 20.0;
}

// The light scattered toward the eye along this pixel's ray by the air between it and the sun or
// moon: how much sky shows on the way to it on screen, in the light's colour, strongest looking
// toward it and when it is low.
vec3 raysAt(vec2 uv) {
    vec4 clip = gbufferProjection * vec4(shadowLightPosition, 1.0);
    if (clip.w <= 0.0) return vec3(0.0);
    vec2 light = clip.xy / clip.w * 0.5 + 0.5;
    vec4 view = gbufferProjectionInverse * vec4(uv * 2.0 - 1.0, -1.0, 1.0);
    float toward = max(dot(normalize(view.xyz), normalize(shadowLightPosition)), 0.0);
    float forward = pow(toward, 8.0);
    if (forward < 0.002) return vec3(0.0);

    float lod = screenLod(2.0);
    vec2 step = (light - uv) / float(GODRAYS_SAMPLES);
    // A different start for neighbouring pixels: the samples' bands become a fine grain.
    float dither = texture2D(noisetex, gl_FragCoord.xy / 256.0).r;
    vec2 p = uv + step * dither;
    // Nearer the pixel counts more: a gap's light fades on its way out from it.
    float open = 0.0;
    float weight = 1.0;
    float total = 0.0;
    for (int i = 0; i < GODRAYS_SAMPLES; i++) {
        open += textureLod(colortex0, clamp(p, 0.0, 1.0), lod).a * weight;
        total += weight;
        weight *= 0.88;
        p += step;
    }
    open /= total;

    vec3 s = sunDir();
    float lowSun = 1.0 - smoothstep(0.0, 0.35, abs(s.y));
    float air = 0.25 + 0.75 * lowSun + rainStrength;
    return (sunlight(s) + moonlight(s) * 3.0) * open * forward * air * GODRAYS_STRENGTH * 0.6;
}

// A four-tap unsharp mask, in linear light, before the film curve: the edges of leaves, glass and
// distant blocks stay readable on a phone's small screen without the halo of a strong sharpen.
vec3 sharpen(vec3 color, vec2 uv) {
    vec2 texel = 1.0 / vec2(viewWidth, viewHeight);
    vec3 blur = 0.25 * (
        texture2D(colortex0, uv + vec2(texel.x, 0.0)).rgb
        + texture2D(colortex0, uv - vec2(texel.x, 0.0)).rgb
        + texture2D(colortex0, uv + vec2(0.0, texel.y)).rgb
        + texture2D(colortex0, uv - vec2(0.0, texel.y)).rgb);
    return color + (color - blur) * SHARPEN_STRENGTH;
}

// A restrained teal-and-amber grade: cool shade, warm light, and a little contrast around middle
// grey. It is what makes the sun and the water read as one photograph instead of two.
vec3 grade(vec3 c) {
    c = clamp(c, 0.0, 1.0);
    c = (c - 0.5) * CONTRAST + 0.5;
    vec3 warm = mix(vec3(1.0), vec3(1.045, 1.0, 0.945), max(WARMTH, 0.0));
    vec3 cool = mix(vec3(1.0), vec3(0.955, 1.0, 1.055), max(0.0 - WARMTH, 0.0));
    c *= mix(warm, cool, step(WARMTH, 0.0));
    float l = luma(c);
    c += vec3(-0.010, 0.002, 0.016) * (1.0 - l);
    c += vec3(0.016, 0.006, -0.010) * l;
    return clamp(c, 0.0, 1.0);
}

void main() {
    vec3 color = texture2D(colortex0, texcoord).rgb;
    #ifdef GODRAYS
        if (isEyeInWater == 0) color += raysAt(texcoord);
    #endif
    #ifdef BLOOM
        color = mix(color, bloomAt(texcoord), BLOOM_STRENGTH);
    #endif
    #ifdef SHARPEN
        color = sharpen(color, texcoord);
    #endif
    color = toDisplay(tonemap(color));
    #ifdef COLOR_GRADE
        color = grade(color);
    #endif
    #ifdef VIGNETTE
        vec2 q = texcoord - 0.5;
        color *= clamp(1.0 - dot(q, q) * VIGNETTE_STRENGTH * 2.2, 0.0, 1.0);
    #endif
    #ifdef FILM_GRAIN
        float grain = texture2D(noisetex, gl_FragCoord.xy / 256.0 + vec2(frameTimeCounter * 0.37, 0.0)).r - 0.5;
        color += grain * GRAIN_STRENGTH;
    #endif
    // A last half-texel of noise: 8-bit output bands the night sky without it.
    color += (texture2D(noisetex, gl_FragCoord.xy / 256.0).r - 0.5) / 255.0;

    /* DRAWBUFFERS:0 */
    gl_FragData[0] = vec4(clamp(color, 0.0, 1.0), 1.0);
}

#endif
