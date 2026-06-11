uniform sampler2D inTexture0;

uniform float textureW; // texture resolution
uniform float textureH; // texture resolution
uniform vec4  textureRect;
uniform float uvMode;

uniform float paintType;
uniform float gradientSpread;
uniform vec2  gradientStart;
uniform vec2  gradientEnd;
uniform vec2  gradientRadius;
uniform vec2  gradientAngles;
uniform int   gradientCount;
uniform float gradientOffsets[8];
uniform vec4  gradientColors[8];

float applyGradientSpread(float t)
{
    if(gradientSpread < 0.5)
        return clamp(t, 0.0, 1.0);

    if(gradientSpread < 1.5)
        return fract(t);

    float u = fract(t * 0.5) * 2.0;
    return u <= 1.0 ? u : 2.0 - u;
}

vec4 sampleGradientStops(float t)
{
    if(gradientCount <= 0)
        return vec4(1.0);

    t = applyGradientSpread(t);

    if(t <= gradientOffsets[0])
        return gradientColors[0];

    for(int i = 1; i < 8; ++i)
    {
        if(i >= gradientCount)
            break;

        if(t <= gradientOffsets[i])
        {
            float lo = gradientOffsets[i - 1];
            float hi = gradientOffsets[i];
            float u  = hi == lo ? 1.0 : clamp((t - lo) / (hi - lo), 0.0, 1.0);
            return mix(gradientColors[i - 1], gradientColors[i], u);
        }
    }

    return gradientColors[gradientCount - 1];
}

vec4 samplePaint(vec2 paintPos, vec2 uv)
{
    if(paintType < 2.5)
    {
        if(uvMode > 0.5 && uvMode < 1.5)
        {
            vec2 uvMin = vec2(textureRect.x, 1.0 - textureRect.w);
            vec2 uvMax = vec2(textureRect.z, 1.0 - textureRect.y);
            uv = clamp(uv, uvMin, uvMax);
        }

        return texture(inTexture0, uv);
    }

    if(paintType < 3.5)
    {
        vec2  axis = gradientEnd - gradientStart;
        float len2 = dot(axis, axis);
        float t    = len2 <= 0.000001 ? 0.0 : dot(paintPos - gradientStart, axis) / len2;
        return sampleGradientStops(t);
    }

    if(paintType < 4.5)
    {
        float radius = max(gradientRadius.y - gradientRadius.x, 0.000001);
        float t      = (length(paintPos - gradientStart) - gradientRadius.x) / radius;
        return sampleGradientStops(t);
    }

    float span  = gradientAngles.y - gradientAngles.x;
    span        = abs(span) <= 0.000001 ? 6.28318530718 : span;
    float angle = atan(paintPos.y - gradientStart.y, paintPos.x - gradientStart.x);
    float t     = (angle - gradientAngles.x) / span;
    return sampleGradientStops(t);
}
