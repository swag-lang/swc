#version 330 core
#include base

in vec4     vcolor;
in vec2     vuv0;
in vec2     vuv1;

uniform sampler2D   inTexture0;
uniform sampler2D   inTexture1;

out vec4 color;

float median(float a, float b, float c)
{
    return max(min(a, b), min(max(a, b), c));
}

void main()
{
    // Reconstruct the true distance as the median of the three channels.
    // This is what preserves sharp corners a single-channel SDF would round off.
    vec3  msd  = texture(inTexture1, vuv1).rgb;
    float sd   = median(msd.r, msd.g, msd.b);
    float dist = sd - 0.5;

    // Screen-space anti-aliasing. fwidth() measures how fast the distance field
    // changes per pixel, so the edge stays one pixel wide at any draw size or zoom.
    float aaf   = fwidth(dist);
    float alpha = smoothstep(-aaf, aaf, dist);

    color    = vcolor * texture(inTexture0, vuv0);
    color.w *= alpha;
}
