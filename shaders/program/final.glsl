// Starling Visuals 2.1: the lens. Bloom from colortex0's mipmaps (the scene at ever smaller
// sizes, which the game makes before this pass), the sun's rays from where the sky shows on the
// way to it (their alpha, at a small size: soft without many samples), a light edge smooth, a
// fine sharpen, then the film curve, the grade, the vignette and the grain. Every stage is a
// switch, so a phone can turn the expensive ones off without a second version of the pack.
//
// The bloom used to read four taps at each of five mip levels (twenty fetches). 2.1 reads four
// taps at the near level and one at each far level: the far levels are already so blurred that
// their extra taps only cost bandwidth. The rays now test two points toward the sun first and
// skip the whole loop where the sky cannot show, which is most of the screen.

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

// One bloom tap with a soft knee: a pixel just under BLOOM_THRESHOLD contributes a little, so
// the glow does not have a hard edge where a texture crosses the threshold.
vec3 bloomTap(vec3 c) {
    float br = max(c.r, max(c.g, c.b));
    float knee = 0.45;
    float soft = clamp(br - BLOOM_THRESHOLD + knee, 0.0, 2.0 * knee);
    soft = soft * soft / (4.0 * knee + 1e-4);
    float contribution = max(soft, br - BLOOM_THRESHOLD) / max(br, 1e-4);
    return c * contribution;
}

// The scene blurred over four sizes: a four-tap tent at the near level for a clean small glow,
// then one tap at each of three far levels for the wide halo. Eight fetches instead of twenty.
vec3 bloomAt(vec2 uv) {
    vec3 sum = vec3(0.0);
    float lod = screenLod(1.0);
    vec2 texel = exp2(lod) / vec2(viewWidth, viewHeight);
    sum += bloomTap(textureLod(colortex0, uv + texel * vec2(0.6, 0.6), lod).rgb);
    sum += bloomTap(textureLod(colortex0, uv + texel * vec2(-0.6, 0.6), lod).rgb);
    sum += bloomTap(textureLod(colortex0, uv + texel * vec2(0.6, -0.6), lod).rgb);
    sum += bloomTap(textureLod(colortex0, uv + texel * vec2(-0.6, -0.6), lod).rgb);
    sum *= 0.25;
    float weight = 0.55;
    for (int i = 2; i <= 5; i++) {
        float l = screenLod(float(i));
        sum += bloomTap(textureLod(colortex0, uv, l).rgb) * weight;
        weight *= 0.55;
    }
    return sum / 1.95;
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
    // Two probes on the way to the light. If neither has any sky, the whole shaft is hidden and
    // the sample loop is skipped; that is most of the terrain on screen.
    float probe = max(
        textureLod(colortex0, mix(uv, light, 0.35), lod).a,
        textureLod(colortex0, mix(uv, light, 0.70), lod).a);
    if (probe < 0.01) return vec3(0.0);

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

// A light edge-aware smooth, in linear light, before the film curve: the stair-step edge of a
// distant block or a leaf becomes a soft line without a full FXAA pass. Only a strong local
// contrast is touched, so textures keep their detail.
vec3 smoothEdges(vec3 color, vec2 uv) {
    vec2 texel = 1.0 / vec2(viewWidth, viewHeight);
    vec3 l = texture2D(colortex0, uv - vec2(texel.x, 0.0)).rgb;
    vec3 r = texture2D(colortex0, uv + vec2(texel.x, 0.0)).rgb;
    vec3 d = texture2D(colortex0, uv - vec2(0.0, texel.y)).rgb;
    vec3 u = texture2D(colortex0, uv + vec2(0.0, texel.y)).rgb;
    float lo = min(luma(color), min(min(luma(l), luma(r)), min(luma(d), luma(u))));
    float hi = max(luma(color), max(max(luma(l), luma(r)), max(luma(d), luma(u))));
    float edge = smoothstep(0.08, 0.65, hi - lo);
    vec3 blur = (l + r + d + u) * 0.25;
    return mix(color, blur, edge * 0.45);
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
    return max(color + (color - blur) * SHARPEN_STRENGTH, 0.0);
}

// A restrained teal-and-amber grade: cool shade, warm light, and a little contrast around middle
// grey. It is what makes the sun and the water read as one photograph instead of two. The last
// step desaturates the top of the range, so a sunlit white block rolls into a warm white instead
// of a flat sheet of pure white.
vec3 grade(vec3 c) {
    c = clamp(c, 0.0, 1.0);
    c = (c - 0.5) * CONTRAST + 0.5;
    float l = luma(c);
    vec3 warm = mix(vec3(1.0), vec3(1.045, 1.0, 0.945), max(WARMTH, 0.0));
    vec3 cool = mix(vec3(1.0), vec3(0.955, 1.0, 1.055), max(0.0 - WARMTH, 0.0));
    c *= mix(warm, cool, step(WARMTH, 0.0));
    c += vec3(-0.010, 0.002, 0.016) * (1.0 - l);
    c += vec3(0.016, 0.006, -0.010) * l;
    float peak = smoothstep(0.74, 1.0, luma(c));
    c = mix(c, vec3(luma(c)), peak * 0.22);
    return clamp(c, 0.0, 1.0);
}

void main() {
    vec3 color = texture2D(colortex0, texcoord).rgb;
    #ifdef GODRAYS
        if (isEyeInWater == 0) color += raysAt(texcoord);
    #endif
    #ifdef BLOOM
        // A touch of warmth in the glow, the way a film's halation picks up the emulsion's dye.
        color = mix(color, bloomAt(texcoord) * vec3(1.03, 0.99, 0.95), BLOOM_STRENGTH);
    #endif
    #ifdef SMOOTH_EDGES
        color = smoothEdges(color, texcoord);
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
