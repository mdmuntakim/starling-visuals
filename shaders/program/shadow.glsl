// Starling Visuals 2: the world seen from the sun (or moon) into the shadow map, distorted as the
// lookups in lit.glsl undo. Water casts none: the sun goes on lighting what is under it. Leaves
// and grass move with the same wind as the world, so their shadows move too.

#include "/lib/common.glsl"

#ifdef VERTEX_SHADER

out vec2 texcoord;
flat out int material;

attribute vec4 mc_Entity;

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
    material = int(mc_Entity.x + 0.5);
    vec4 vertex = gl_Vertex;
    vertex.xyz += windOffset(gl_Vertex.xyz + cameraPosition, material);
    gl_Position = gl_ModelViewProjectionMatrix * vertex;
    gl_Position.xy = distortShadow(gl_Position.xy);
}

#endif

#ifdef FRAGMENT_SHADER

in vec2 texcoord;
flat in int material;

uniform sampler2D gtexture;

void main() {
    if (material == 10001 || texture2D(gtexture, texcoord).a < 0.1) discard;

    /* DRAWBUFFERS:0 */
    gl_FragData[0] = vec4(1.0);
}

#endif
