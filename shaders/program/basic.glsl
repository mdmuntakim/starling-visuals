// Starling Visuals 2.1: unlit geometry. `gbuffers_basic` draws the block outline, debug lines and
// the game's solid-colour shapes; nothing here samples the block atlas, because these vertices
// have no meaningful texture coordinates and sampling one arbitrary atlas texel is how basic
// geometry turns into a random colour.
//
// The block outline is black at 40% alpha. Blended into the scene before the film curve, 40% of
// a bright sky lifts to grey, so the outline reads white. A black basic vertex is therefore
// written opaque: the outline stays black through the curve, as it should. Anything that is not
// black keeps its own colour and its own alpha.

#ifdef VERTEX_SHADER

out vec4 glcolor;

void main() {
    glcolor = gl_Color;
    gl_Position = ftransform();
}

#endif

#ifdef FRAGMENT_SHADER

in vec4 glcolor;

void main() {
    vec4 color = glcolor;
    if (max(color.r, max(color.g, color.b)) < 0.02) color.a = 1.0;

    /* DRAWBUFFERS:0 */
    gl_FragData[0] = color;
}

#endif
