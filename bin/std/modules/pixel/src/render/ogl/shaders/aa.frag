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

    // Extruded-fringe antialiasing: coverage is interpolated across the fringe band.
    color.w *= clamp(vcov, 0.0, 1.0);

    color.w *= texture(inTexture1, vuv1).r;
    if(color.w == 0 && !copyMode)
        discard;
}
