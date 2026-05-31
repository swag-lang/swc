#version 330 core
#include base

in vec4     vcolor;
in vec2     vuv0;
in vec2     vuv1;

uniform sampler2D   inTexture0;
uniform sampler2D   inTexture1;

out vec4 color;

void main()
{
    float distanceValue = texture(inTexture1, vuv1).r;
    float smoothing = max(fwidth(distanceValue), 1.0 / 255.0);
    float alpha = smoothstep(0.5 - smoothing, 0.5 + smoothing, distanceValue);

    color = vcolor * texture(inTexture0, vuv0);
    color.w *= alpha;
}
