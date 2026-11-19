// Starling Visuals 2: the sky, the air and the fine contact shadows. Pixels at the far plane
// get the sky, the sun and the other bodies (colortex2: stars and moon over black); the others
// the haze they are seen through, thicker low down, and past most of the render distance the sky
// itself. The alpha is how much of the sky shows there, which `final` follows to the sun for its
// rays.

#include "/lib/common.glsl"

/*
const int colortex0Format = RGBA16F;
const int colortex2Format = RGBA16F;
const bool colortex2Clear = true;
*/

#ifdef VERTEX_SHADER

noperspective out vec2 texcoord;

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    gl_Position = ftransform();
}

#endif

#ifdef FRAGMENT_SHADER

noperspective in vec2 texcoord;

uniform sampler2D colortex0;
uniform sampler2D colortex2;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform ivec2 eyeBrightnessSmooth;

// The haze is FOG_DENSITY thick at sea level and thins by e every FOG_HEIGHT blocks above it.
const float FOG_FLOOR = 63.0;

// How much haze a ray `rel` long, from the eye at height `y0`, crosses: thicker at dawn and dusk
// and in rain, and no more than twice sea level's deep underground.
float hazeDepth(vec3 rel, float y0, vec3 s) {
    float lowSun = 1.0 - smoothstep(0.0, 0.35, abs(s.y));
    float density = FOG_DENSITY * 0.003 * (1.0 + 0.5 * lowSun + 4.0 * rainStrength);
    float e0 = exp(-(y0 - FOG_FLOOR) / FOG_HEIGHT);
    float k = -rel.y / FOG_HEIGHT;
    // The mean of exp(-(y - FOG_FLOOR) / FOG_HEIGHT) along the ray.
    float mean = abs(k) > 1e-3 ? e0 * (exp(k) - 1.0) / k : e0;
    return density * min(mean, 2.0) * length(rel);
}

// The light the haze along `d` sends to the eye: the sky's near the horizon (looking down at a
// valley, the sunlit air is as bright as the horizon), dark where the eye has no sky above, and
// brighter toward the sun.
vec3 hazeLight(vec3 d, vec3 s) {
    vec3 level = normalize(vec3(d.x, max(d.y, 0.0) + 0.001, d.z));
    float eyeSky = float(eyeBrightnessSmooth.y) / 240.0;
    vec3 color = skyRadiance(level, s) * mix(0.05, 1.0, eyeSky * eyeSky);
    float toward = pow(max(dot(d, s), 0.0), 8.0);
    color += sunlight(s) * toward * 0.22 * (1.0 - rainStrength);
    return color;
}

// A view-space position from a depth buffer sample.
vec3 viewPosition(vec2 uv, float depth) {
    vec4 view = gbufferProjectionInverse * vec4(vec3(uv, depth) * 2.0 - 1.0, 1.0);
    return view.xyz / view.w;
}

#ifdef SSAO
// A few depth taps around the pixel, each an occluder when it stands above the surface plane.
// It is deliberately narrow (a hand's width) and soft: the shadow map already does the large
// scale, this only seats objects on the ground and darkens the inside of a corner.
float ambientOcclusion(vec2 uv, float depth) {
    vec3 p = viewPosition(uv, depth);
    vec3 n = normalize(cross(dFdx(p), dFdy(p)));
    float jitter = hash12(gl_FragCoord.xy) * 6.2831853;
    float spread = 6.0 / min(viewWidth, viewHeight);
    float worldRadius = 0.75 + 0.035 * length(p);
    float occ = 0.0;
    for (int i = 0; i < SSAO_SAMPLES; i++) {
        float a = float(i) * 2.3999632 + jitter;
        float r = spread * sqrt((float(i) + 1.0) / float(SSAO_SAMPLES));
        vec2 at = uv + vec2(cos(a), sin(a)) * r;
        float d = texture2D(depthtex0, at).r;
        if (d >= 1.0) continue;
        vec3 q = viewPosition(at, d);
        vec3 delta = q - p;
        float dist = length(delta);
        float facing = max(0.0, dot(n, delta / max(dist, 1e-4)));
        occ += facing * (1.0 - smoothstep(0.0, worldRadius, dist));
    }
    return clamp(1.0 - SSAO_STRENGTH * occ / float(SSAO_SAMPLES), 0.35, 1.0);
}
#endif

// A soft caustic pattern for the eye under water, in world space so it stays put as the camera
// moves. Two crossing wave sets make a net of bright lines.
float caustics(vec3 world, float t) {
    vec2 p = world.xz * 0.65 + world.y * 0.22;
    float a = sin(p.x * 2.1 + t * 0.8) * sin(p.y * 2.4 - t * 0.7);
    float b = sin((p.x + p.y) * 3.3 - t * 1.1);
    return pow(max(0.0, a * 0.6 + b * 0.4), 3.0);
}

void main() {
    vec3 color = texture2D(colortex0, texcoord).rgb;
    float depth = texture2D(depthtex0, texcoord).r;
    vec3 s = sunDir();
    float sky = 1.0;
    if (depth >= 1.0) {
        // The near plane: the far one is at infinity, where w is 0.
        vec4 view = gbufferProjectionInverse * vec4(texcoord * 2.0 - 1.0, -1.0, 1.0);
        vec3 dir = normalize(mat3(gbufferModelViewInverse) * (view.xyz / view.w));
        // A round sun, soft at its rim (the bloom makes its glow), the moon and the stars.
        float mu = dot(dir, s);
        float disk = smoothstep(0.9988, 0.9997, mu) * (1.0 - rainStrength);
        float limb = sqrt(max(1.0 - (1.0 - mu) * 480.0, 0.0));
        color = skyRadiance(dir, s) + sunlight(s) * disk * (5.5 + 2.5 * limb);
        color += texture2D(colortex2, texcoord).rgb;
        #ifdef STARS
            color += nightSky(dir, s, frameTimeCounter);
        #endif
        if (isEyeInWater == 1) {
            color = vec3(0.018, 0.085, 0.115) * (0.15 + 0.85 * daylight(s));
            color += caustics(cameraPosition + dir * 8.0, frameTimeCounter) * vec3(0.02, 0.07, 0.08) * 0.35;
        }
    } else {
        vec4 view = gbufferProjectionInverse * vec4(vec3(texcoord, depth) * 2.0 - 1.0, 1.0);
        vec3 rel = (gbufferModelViewInverse * vec4(view.xyz / view.w, 1.0)).xyz;
        float dist = length(rel);
        vec3 dir = rel / max(dist, 1e-4);
        #ifdef SSAO
            color *= ambientOcclusion(texcoord, depth);
        #endif
        if (isEyeInWater == 1) {
            vec3 world = rel + cameraPosition;
            float c = caustics(world, frameTimeCounter);
            #ifdef UNDERWATER_CAUSTICS
                color += vec3(0.06, 0.22, 0.24) * c * (1.0 - smoothstep(0.0, 28.0, dist)) * 1.6;
            #endif
            vec3 water = vec3(0.018, 0.085, 0.115) * (0.15 + 0.85 * daylight(s));
            color = mix(color, water, 1.0 - exp(-dist * 0.075));
        } else if (isEyeInWater == 2) {
            color = mix(color, vec3(0.9, 0.25, 0.02), 1.0 - exp(-dist * 0.8));
        } else if (isEyeInWater == 3) {
            color = mix(color, vec3(0.55, 0.62, 0.70), 1.0 - exp(-dist * 0.6));
        } else {
            float haze = 1.0 - exp(-hazeDepth(rel, cameraPosition.y, s));
            color = mix(color, hazeLight(dir, s), haze);
            // The world's edge fades into the sky behind it.
            float edge = smoothstep(far * 0.7, far, length(rel.xz));
            color = mix(color, skyRadiance(dir, s), edge);
            sky = edge * edge;
        }
    }

    /* DRAWBUFFERS:0 */
    gl_FragData[0] = vec4(color, isEyeInWater == 0 ? sky : 0.0);
}

#endif
