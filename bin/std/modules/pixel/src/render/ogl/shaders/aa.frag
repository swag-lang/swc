#version 330 core
#include base

in vec4     vcolor;
in vec2     vuv0;
in vec2     vuv1;
in vec2     vpaintPos;
in float    vcov;

uniform sampler2D   inTexture1;
uniform bool        copyMode;

out vec4 color;

void main()
{
    color = vcolor * samplePaint(vpaintPos, vuv0);

    // Screen-space-adaptive extruded-fringe antialiasing. The fringe band carries
    // vcov linearly (1 inside, 0.5 on the true contour, 0 on the outer edge), so
    // (vcov-0.5) is a signed coverage that is zero exactly on the contour. fwidth()
    // gives its rate of change per screen pixel, so dividing yields a signed screen-
    // pixel distance and the coverage ramps over ~1px centred on the contour. The
    // edge therefore stays crisp at any zoom, instead of widening (blurring) with
    // the transform the way a raw path-space band does. At scale ~1 this matches the
    // old linear ramp, but it is orientation-correct and scale-invariant.   
    float d = vcov - 0.5;
    color.w *= clamp(d / max(fwidth(d), 1e-5) + 0.5, 0.0, 1.0);

    color.w *= texture(inTexture1, vuv1).r;
    if(color.w == 0 && !copyMode)
        discard;
}
