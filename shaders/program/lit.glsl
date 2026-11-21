// Starling Visuals 3.0: everything drawn with the world's light, in one forward pass. The light
// is worked out per vertex (faces are flat and the lightmap is per vertex anyway); the fragment
// stage samples, looks the sun up in the shadow map, adds the surface's own response, and
// blends. Water adds its waves, reflection and foam. `composite` adds the haze and the sky.
// The stage file defines VERTEX_SHADER or FRAGMENT_SHADER, and what it draws: TERRAIN, WATER,
// ENTITIES, CLOUDS, PARTICLES, WEATHER or nothing (other textured things).
//
// 2.1 moves the Fresnel edge and the sun's highlight to the vertex stage. Every face in this
// world is flat, so both vary slowly across it and interpolate smoothly; the fragment stage
// keeps only the shadow lookup and the texture. That is two pow() calls and a normalize() per
// pixel gone, and it is what makes the highlight stable instead of a crawling per-pixel lobe.

#include "/lib/common.glsl"

#if defined SHADOWS && !defined CLOUDS
    #define SHADOWED
#endif

#ifdef VERTEX_SHADER

out vec2 texcoord;
out vec4 glcolor;
out vec3 fill;
out vec3 key;
out float open;
flat out int material;
out vec3 rel;
out vec3 normal;
out float skyLevel;
out float grazing;
out float spec;
#ifdef SHADOWED
out vec3 shadowClip;
#endif

attribute vec4 mc_Entity;

uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;

// The face shade the game bakes into terrain colours (1 up, 0.5 down, 0.8 north and south,
// 0.6 east and west), which this pack's own sun replaces.
float bakedShade(vec3 n) {
    vec3 a = abs(n);
    return a.x * 0.6 + a.z * 0.8 + (n.y > 0.0 ? a.y : a.y * 0.5);
}

// The wind's own motion, shared by the world and its shadow: leaves and grass lean and come
// back, the top of a tall plant more than its root. It is a function of the world position, so
// a section that is re-meshed keeps the same phase.
vec3 windOffset(vec3 world, int id) {
#ifdef WAVING_PLANTS
    if (id == 10002 || id == 10003) {
        float tall = id == 10003 ? 0.55 : 1.0;
        float phase = world.x * 0.7 + world.z * 0.55;
        float sway = sin(frameTimeCounter * 1.35 + phase) * 0.035
            + sin(frameTimeCounter * 2.1 - phase * 1.7) * 0.012;
        return vec3(sway, 0.0, sway * 0.6) * tall;
    }
#endif
    return vec3(0.0);
}

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    glcolor = gl_Color;
    material = int(mc_Entity.x + 0.5);

    // The world position before the wind moves it: the phase must not chase the vertex.
    vec4 view = gl_ModelViewMatrix * gl_Vertex;
    vec3 at = (gbufferModelViewInverse * view).xyz;
    vec3 sway = windOffset(at + cameraPosition, material);
    vec4 vertex = gl_Vertex;
    vertex.xyz += sway;
    view = gl_ModelViewMatrix * vertex;
    gl_Position = gl_ProjectionMatrix * view;
    at = (gbufferModelViewInverse * view).xyz;

    vec3 n = normalize(mat3(gbufferModelViewInverse) * (gl_NormalMatrix * gl_Normal));
    vec2 levels = lightLevels((gl_TextureMatrix[1] * gl_MultiTexCoord1).xy);
    #ifdef HAND_LIGHT
        // What the player holds that glows (a torch, a lantern, a lava bucket) lights around
        // them as a block of its level would: one level less each block away.
        float held = float(max(heldBlockLightValue, heldBlockLightValue2));
        levels.x = max(levels.x, clamp((held - length(at)) / 15.0, 0.0, 1.0));
    #endif
    float wrap = 0.0;
    float unshade = 1.0;
    #if defined TERRAIN || defined WATER
        if (material == 10002 || material == 10003) {
            wrap = 1.0;
        } else {
            // The game's baked face shade is already in the vertex colour; lift the light by its
            // inverse so the pack's own sun is the only shade. Clamped: a down face's 0.5 would
            // otherwise ask for twice the light of an up face and over-brighten what it can see.
            unshade = clamp(1.0 / max(bakedShade(n), 0.5), 1.0, 1.65);
        }
    #endif
    #ifdef CLOUDS
        levels = vec2(0.0, 1.0);
        wrap = 0.5;
    #endif
    #if defined PARTICLES || defined WEATHER
        wrap = 1.0;
    #endif

    fill = fillLightAt(n, levels) * unshade;
    key = keyLightAt(n, wrap) * unshade;
    #ifdef CLOUDS
        // Their texture is white; the cloud itself sends back about half the light.
        fill *= 0.55;
        key *= 0.55;
    #endif
    open = openSky(levels);
    rel = at;
    normal = n;
    skyLevel = levels.y;

    // The view direction and the surface response, once per vertex instead of once per pixel.
    vec3 v = -at / max(length(at), 1e-4);
    float ndv = clamp(dot(n, v), 0.0, 1.0);
    float plant = (material == 10001 || material == 10002 || material == 10003) ? 1.0 : 0.0;
    grazing = pow(1.0 - ndv, 3.0) * 0.16 * (1.0 - plant * 0.7);
    spec = 0.0;
    #ifdef SPECULAR
        // A polished face (ice, packed ice, glass, snow, metal) gets a tighter lobe than stone.
        // Plants and water are excluded: their normals are arbitrary and water has its own.
        if (plant < 0.5 && material != 10004 && material != 10005 && material != 10006) {
            float power = material == 10007 ? 140.0 : 48.0;
            float wet = clamp(wetness * 1.3 + rainStrength * 0.35, 0.0, 1.0);
            spec = specular(n, v, keyLightDir(), power) * fresnel(n, v) * (0.06 + wet * 0.34);
        }
    #endif

    #ifdef SHADOWED
        // Off the surface a little, along its normal (toward the light for plants, whose normals
        // point anywhere), so that it doesn't shadow itself; further with distance, where the
        // map's texels are bigger.
        vec3 off = mix(n, keyLightDir(), wrap) * (0.03 + length(at) * 0.004);
        shadowClip = (shadowProjection * (shadowModelView * vec4(at + off, 1.0))).xyz;
    #endif
}

#endif

#ifdef FRAGMENT_SHADER

in vec2 texcoord;
in vec4 glcolor;
in vec3 fill;
in vec3 key;
in float open;
flat in int material;
in vec3 rel;
in vec3 normal;
in float skyLevel;
in float grazing;
in float spec;
#ifdef SHADOWED
in vec3 shadowClip;
#endif

uniform sampler2D gtexture;
uniform vec4 entityColor;
#ifdef SHADOWED
uniform sampler2DShadow shadowtex0;
#endif
#ifdef WATER
uniform sampler2D depthtex1;

// The open water's normal at world point `p` (x, z) and time `t`: four travelling waves, each
// leaning the surface along its direction by its slope, and a fine chop for rain.
vec3 waveNormal(vec2 p, float t) {
    vec2 a = vec2(0.80, 0.60);
    vec2 b = vec2(-0.50, 0.87);
    vec2 c = vec2(0.20, -0.98);
    vec2 d = vec2(0.95, -0.31);
    vec2 slope = a * cos(dot(a, p) * 1.3 + t * 1.1) * 0.026
        + b * cos(dot(b, p) * 2.1 + t * 1.7) * 0.025
        + c * cos(dot(c, p) * 3.7 + t * 2.3) * 0.026
        + d * cos(dot(d, p) * 6.1 + t * 3.1) * 0.010;
    if (rainStrength > 0.01) {
        vec2 r = p * 9.0;
        slope += vec2(cos(r.x * 1.7 + t * 8.0), sin(r.y * 1.9 - t * 7.0)) * 0.012 * rainStrength;
    }
    return normalize(vec3(-slope.x, 1.0, -slope.y));
}
#endif

// How much of the sun reaches this point: the shadow map within its reach, the open sky past it.
// One `shadow2D` is already four texels of hardware filtering; SHADOW_FILTER 2 adds a second
// tap on the opposite diagonal, which is half the cost of the old four-tap grid and just as
// smooth on a phone's screen.
float sunReaches() {
    #ifdef SHADOWED
        float reach = max(abs(shadowClip.x), abs(shadowClip.y));
        if (reach < 1.0) {
            vec3 at = vec3(distortShadow(shadowClip.xy), shadowClip.z) * 0.5 + 0.5;
            at.z -= 0.0002;
            float radius = SHADOW_SOFTNESS / float(shadowMapResolution);
            #if SHADOW_FILTER == 4
                float lit = 0.25 * (
                    shadow2D(shadowtex0, at + vec3(vec2(0.95, 0.32) * radius, 0.0)).r
                    + shadow2D(shadowtex0, at + vec3(vec2(-0.32, 0.95) * radius, 0.0)).r
                    + shadow2D(shadowtex0, at + vec3(vec2(-0.95, -0.32) * radius, 0.0)).r
                    + shadow2D(shadowtex0, at + vec3(vec2(0.32, -0.95) * radius, 0.0)).r);
            #elif SHADOW_FILTER == 2
                float lit = 0.5 * (
                    shadow2D(shadowtex0, at + vec3(vec2(0.7, 0.7) * radius, 0.0)).r
                    + shadow2D(shadowtex0, at + vec3(vec2(-0.7, -0.7) * radius, 0.0)).r);
            #else
                float lit = shadow2D(shadowtex0, at).r;
            #endif
            return mix(lit, open, smoothstep(0.85, 1.0, reach));
        }
    #endif
    return open;
}

void main() {
    vec4 albedo = texture2D(gtexture, texcoord) * glcolor;
    if (albedo.a < 0.1) discard;
    #ifdef ENTITIES
        albedo.rgb = mix(albedo.rgb, entityColor.rgb, entityColor.a);
    #endif

    // Rain darkens the upward faces a little: wet stone and wet grass read darker and glossier.
    float wet = clamp(wetness * 1.3 + rainStrength * 0.35, 0.0, 1.0);
    if (material != 10001 && material != 10002 && material != 10003 && material != 10004
        && material != 10005 && material != 10006) {
        albedo.rgb *= mix(1.0, 0.86, wet * smoothstep(0.15, 0.9, normal.y));
    }

    float sun = dot(key, vec3(1.0)) > 0.0 ? sunReaches() : 0.0;
    vec3 albedoLinear = toLinear(albedo.rgb);
    vec3 lit = albedoLinear * (fill + key * sun);
    float alpha = albedo.a;

    // The sun's and moon's colours once per pixel: the highlight, the light through a leaf and
    // the water all used to normalize the light direction and run the atmosphere again.
    vec3 s = sunDir();
    vec3 keyDir = keyLightDir();
    vec3 sunColor = sunlight(s);
    vec3 moonColor = moonlight(s);

    // A grazing-angle fill: the world's cubes come out of Minecraft with hard edges, and a hard
    // edge reads as a square corner. Lifting the surface toward the sky's own light as the eye
    // looks at it nearly edge-on rounds that corner softly. It is computed per vertex above.
    vec3 color = mix(lit, albedoLinear * fill, grazing);
    // No face is ever allowed to leave the lens as a flat sheet of white: the sun's highlight
    // is Fresnel-weighted in the vertex stage, and this clamp is the last line of defence.
    color = min(color, vec3(6.0));

    #ifdef SPECULAR
        // The sun's or moon's image on the surface. `spec` is the vertex's Fresnel-weighted
        // lobe; the shadow lookup and the light's colour are the only per-pixel parts.
        color += (sunColor + moonColor * 2.0) * spec * sun;
    #endif

    #ifdef EMISSIVE_BLOCKS
        // The blocks whose light is their texture: warm fire, a cool sea lantern, redstone's own
        // red. The emission follows the texture, so a dark crack in lava stays dark, and it is
        // small enough that the film curve rolls it off instead of clipping the block to white.
        //
        // `glow` is the texture's own brightness, and it is the last line of defence against a
        // block turning pale: a dark texel (obsidian, the shell of a pumpkin) emits nothing at
        // all, while a genuinely bright one (glowstone, a flame, lava) emits its colour. Some
        // clients give an emissive id to a sprite shared with a plain block, so the id alone is
        // not trusted.
        if (material >= 10004 && material <= 10006) {
            float own = luma(albedoLinear);
            // Emission only from a texel that is itself bright: a dark texel (obsidian, the
            // shell of a pumpkin) emits nothing, and there is no flat constant lifting it.
            // Cold light and fire need a bright texture; redstone keeps a small constant so a
            // circuit still reads at night.
            if (material == 10004) {
                float glow = smoothstep(0.10, 0.28, own);
                color += vec3(1.00, 0.90, 0.72) * (0.55 * own) * glow;
            } else if (material == 10005) {
                float glow = smoothstep(0.08, 0.24, own);
                color += vec3(1.00, 0.52, 0.18) * (0.50 * own) * glow;
            } else {
                float glow = smoothstep(0.03, 0.16, own);
                color += vec3(0.95, 0.18, 0.06) * (0.24 * own + 0.05) * glow;
            }
        }
    #endif

    #ifdef CLOUDS
        // A silver lining where the cloud's edge meets the sky.
        color += skyAmbient(s) * grazing * 1.6;
    #endif

    // A little light through the thin parts of grass and leaves: the sun shows on the far side
    // of a blade, the way it does through real foliage, without a second material pass.
    if (material == 10002 || material == 10003) {
        float back = max(dot(-normal, keyDir), 0.0);
        color += albedoLinear * (sunColor + moonColor) * back * 0.16 * sun;
    }

    #ifdef WATER
        if (material == 10001) {
            vec3 n = normalize(normal);
            vec3 view = rel / max(length(rel), 1e-4);
            // Its open surface moves with waves; the sides of falling water stay flat.
            #ifdef WATER_WAVES
                if (n.y > 0.9) n = waveNormal(rel.xz + cameraPosition.xz, frameTimeCounter);
            #endif
            vec3 mirrored = reflect(view, n);
            mirrored.y = abs(mirrored.y);
            float ndv = clamp(dot(-view, n), 0.0, 1.0);
            float fres = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
            // The sky's average is enough for a reflection at this scale, and it is one cheap
            // sample instead of a full directional sky per water pixel.
            vec3 reflected = skyAmbient(s) * (0.40 + 0.60 * skyLevel);
            // The moon's or sun's path: a tight lobe plus a broad sheen, both shadowed.
            float mu = max(dot(mirrored, keyDir), 0.0);
            reflected += (sunColor + moonColor * 2.5)
                * (pow(mu, 320.0) * 1.4 + pow(mu, 36.0) * 0.16 + pow(mu, 8.0) * 0.04) * sun;
            // How much water the eye looks through to the bottom (the depth without water): clear
            // where shallow, its own colour where deep.
            float bottom = texture2D(depthtex1, gl_FragCoord.xy / vec2(viewWidth, viewHeight)).r;
            vec4 under = gbufferProjectionInverse * vec4(vec3(gl_FragCoord.xy / vec2(viewWidth, viewHeight), bottom) * 2.0 - 1.0, 1.0);
            float through = bottom >= 1.0 ? 64.0 : max(length(under.xyz / under.w) - length(rel), 0.0);
            float body = clamp(1.0 - exp(-through * 0.32), 0.10, 0.94);
            // A thin bright edge where the water meets the shore, with a little chop.
            float foam = (1.0 - smoothstep(0.0, 0.60, through)) * (0.50 + 0.15 * sin(rel.x * 3.0 + frameTimeCounter * 2.0));
            foam = clamp(foam, 0.0, 0.75);
            vec3 water = mix(color * 0.42, reflected, fres);
            water = mix(water, vec3(0.78, 0.88, 0.92) * (0.40 + 0.60 * skyLevel), foam);
            color = water;
            alpha = mix(body, 1.0, fres);
            alpha = max(alpha, foam);
        }
    #endif
    #ifdef WEATHER
        alpha *= 0.6;
    #endif

    /* DRAWBUFFERS:0 */
    gl_FragData[0] = vec4(color, alpha);
}

#endif
