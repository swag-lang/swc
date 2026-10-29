#version 330 core
#include base

in vec4 vcolor;
in vec2 vuv0;
out vec4 color;

uniform int mode;
uniform float radius;
uniform float saturation;
uniform vec4 tint;
uniform vec2 sourceSize;

vec3 sampleBackdrop(vec2 uv)
{
    vec2 size = vec2(textureW, textureH);
    vec2 lo = vec2(0.5 / size.x, 1.0 - (sourceSize.y - 0.5) / size.y);
    vec2 hi = vec2((sourceSize.x - 0.5) / size.x, 1.0 - 0.5 / size.y);
    return texture(inTexture0, clamp(uv, lo, hi)).rgb;
}

void main()
{
    vec2 texel = 1.0 / vec2(textureW, textureH);
    vec2 uv = vec2(vuv0.x * sourceSize.x / textureW, 1.0 - (1.0 - vuv0.y) * sourceSize.y / textureH);
    vec3 sum = vec3(0.0);
    if (mode < 2)
    {
        float total = 0.0;
        float sigma = max(radius / 3.0, 0.001);
        int reach = int(ceil(radius));
        for (int i = -reach; i <= reach; ++i)
        {
            float weight = exp(-float(i * i) / (2.0 * sigma * sigma));
            vec2 offset = mode == 0 ? vec2(i, 0) : vec2(0, i);
            sum += sampleBackdrop(uv + offset * texel) * weight;
            total += weight;
        }
        sum /= total;
    }
    else if (mode == 2)
    {
        vec2 d = texel * radius;
        sum = sampleBackdrop(uv) * 4.0;
        sum += sampleBackdrop(uv + d);
        sum += sampleBackdrop(uv - d);
        sum += sampleBackdrop(uv + vec2(d.x, -d.y));
        sum += sampleBackdrop(uv + vec2(-d.x, d.y));
        sum /= 8.0;
    }
    else if (mode == 3)
    {
        vec2 d = texel * radius;
        sum = sampleBackdrop(uv + vec2(-2.0 * d.x, 0));
        sum += sampleBackdrop(uv + vec2(2.0 * d.x, 0));
        sum += sampleBackdrop(uv + vec2(0, -2.0 * d.y));
        sum += sampleBackdrop(uv + vec2(0, 2.0 * d.y));
        sum += sampleBackdrop(uv + d) * 2.0;
        sum += sampleBackdrop(uv - d) * 2.0;
        sum += sampleBackdrop(uv + vec2(d.x, -d.y)) * 2.0;
        sum += sampleBackdrop(uv + vec2(-d.x, d.y)) * 2.0;
        sum /= 12.0;
    }
    else
    {
        sum = sampleBackdrop(uv);
        float luminance = dot(sum, vec3(0.2126, 0.7152, 0.0722));
        sum = mix(vec3(luminance), sum, saturation);
        sum = mix(sum, tint.rgb, tint.a);
    }
    // Alpha in a composited surface can be scratch coverage; it is not source transparency.
    color = vec4(clamp(sum, 0.0, 1.0), 1.0) * vcolor;
    applyBlendingMode(color);
}
