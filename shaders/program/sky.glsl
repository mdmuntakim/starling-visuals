// Starling Visuals 2: the vanilla sky's geometry. The sky's colour itself is drawn by
// `composite` (one evaluation per sky pixel); here only the stars stay, in colortex2 with the
// moon, given a cooler tint and a slow twinkle so the procedural stars above sit with them.

#include "/lib/common.glsl"

#ifdef VERTEX_SHADER

out vec4 glcolor;

void main() {
    glcolor = gl_Color;
    gl_Position = ftransform();
}

#endif

#ifdef FRAGMENT_SHADER

in vec4 glcolor;

uniform int renderStage;

void main() {
    if (renderStage != MC_RENDER_STAGE_STARS) discard;
#ifdef STARS
    float night = 1.0 - daylight(sunDir());
    vec3 tint = mix(vec3(0.82, 0.90, 1.0), vec3(1.0, 0.94, 0.86), hash12(gl_FragCoord.xy));
    float twinkle = 0.78 + 0.22 * sin(frameTimeCounter * 1.7 + hash12(gl_FragCoord.yx) * 6.2831);

    /* DRAWBUFFERS:2 */
    gl_FragData[0] = vec4(toLinear(glcolor.rgb) * tint * 2.0 * night * twinkle * (1.0 - rainStrength), glcolor.a);
#else
    discard;
#endif
}

#endif
