#version 330 core
#include base

in vec4     vcolor;
in vec2     vuv0;
in vec2     vuv1;

uniform sampler2D   inTexture0;
uniform sampler2D   inTexture1;

// Gamma applied to glyph coverage to approximate linear-space compositing
// (the framebuffer blend is non-linear sRGB). Counters over-heavy text edges.
uniform float       fontGamma;

out vec4 color;

void main()
{
    float cov = texture(inTexture1, vuv1).r;
    color = vcolor * texture(inTexture0, vuv0);
    color.w *= pow(cov, fontGamma);
}