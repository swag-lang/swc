#version 330 core
#include base

in vec4 vcolor;
in vec2 vuv0;
in vec2 vpaintPos;

uniform int factor;

out vec4 color;

void main()
{
    int f = clamp(factor, 1, 8);

    vec2 texSize = vec2(textureSize(inTexture0, 0));
    // Anchor blocks at the content's top-left, independently of bottom padding in the texture.
    vec2 sourcePx = clamp(vec2(vuv0.x, 1.0 - vuv0.y), vec2(0.0), vec2(0.999999)) * texSize;
    vec2 basePx = floor(sourcePx / float(f)) * float(f);

    vec4 acc = vec4(0.0);
    for(int y = 0; y < 8; ++y)
    {
        if(y >= f)
            break;

        for(int x = 0; x < 8; ++x)
        {
            if(x >= f)
                break;

            vec2 uv = (basePx + vec2(x, y) + vec2(0.5)) / texSize;
            uv.y = 1.0 - uv.y;
            vec4 s  = texture(inTexture0, uv);

            // The source comes from a paintAlpha render target: RGB has already been
            // blended over transparent black while alpha is rebuilt separately. Average
            // premultiplied RGB/coverage, then return straight-alpha color for the
            // normal Pixel texture path.
            acc.rgb += s.rgb;
            acc.a   += s.a;
        }
    }

    float count = float(f * f);
    float a     = acc.a / count;
    vec3 rgb    = acc.a > 0.00001 ? acc.rgb / acc.a : vec3(0.0);
    color       = vcolor * vec4(rgb, a);
    applyBlendingMode(color);
}
