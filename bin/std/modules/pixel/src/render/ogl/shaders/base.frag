uniform sampler2D inTexture0;

uniform vec4  boundRect;
uniform float textureW; // texture resolution
uniform float textureH; // texture resolution
uniform vec4  textureRect;
uniform float uvMode;
uniform float interpolationMode;

uniform float paintType;
uniform float gradientSpread;
uniform vec2  gradientStart;
uniform vec2  gradientEnd;
uniform vec2  gradientRadius;
uniform vec2  gradientAngles;
uniform int   gradientCount;
uniform float gradientOffsets[8];
uniform vec4  gradientColors[8];
uniform sampler2D gradientTexture;
uniform bool gradientTextureEnabled;
uniform bool  premultiplyBlendSource;

float gradientOffsetAt(int index)
{
    if(gradientTextureEnabled)
        return texelFetch(gradientTexture, ivec2(index, 0), 0).r;
    return gradientOffsets[index];
}

vec4 gradientColorAt(int index)
{
    if(gradientTextureEnabled)
        return texelFetch(gradientTexture, ivec2(index, 1), 0);
    return gradientColors[index];
}

void applyBlendingMode(inout vec4 value)
{
    if(premultiplyBlendSource)
        value.rgb *= value.a;
}

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

    float firstOffset = gradientOffsetAt(0);
    vec4 firstColor = gradientColorAt(0);
    if(t <= firstOffset)
        return firstColor;

    for(int i = 1; i < gradientCount; ++i)
    {
        float offset = gradientOffsetAt(i);

        if(t <= offset)
        {
            float lo = gradientOffsetAt(i - 1);
            float hi = offset;
            vec4 color0 = gradientColorAt(i - 1);
            vec4 color1 = gradientColorAt(i);
            float u  = hi == lo ? 1.0 : clamp((t - lo) / (hi - lo), 0.0, 1.0);
            return mix(color0, color1, u);
        }
    }

    return gradientColorAt(gradientCount - 1);
}

vec2 subRectPixelMin()
{
    return floor(vec2(textureRect.x * textureW, textureRect.y * textureH));
}

vec2 subRectPixelMax()
{
    return floor(vec2(textureRect.z * textureW, textureRect.w * textureH));
}

vec2 subRectUVFromPixel(vec2 p)
{
    return vec2((p.x + 0.5) / textureW, 1.0 - (p.y + 0.5) / textureH);
}

vec2 subRectPixelFromPaint(vec2 paintPos)
{
    vec2 minP = subRectPixelMin();
    vec2 maxP = subRectPixelMax();
    vec2 size = max(maxP - minP + 1.0, vec2(1.0));
    vec2 dst  = max(boundRect.zw - boundRect.xy, vec2(0.000001));
    vec2 t    = clamp((paintPos - boundRect.xy) / dst, vec2(0.0), vec2(1.0));
    return minP + t * size - 0.5;
}

vec4 sampleSubRectNearest(vec2 paintPos)
{
    vec2 minP = subRectPixelMin();
    vec2 maxP = subRectPixelMax();
    vec2 p    = subRectPixelFromPaint(paintPos);
    p = clamp(floor(p + 0.5), minP, maxP);
    return texture(inTexture0, subRectUVFromPixel(p));
}

vec4 sampleSubRectLinear(vec2 paintPos)
{
    vec2 minP = subRectPixelMin();
    vec2 maxP = subRectPixelMax();
    vec2 p    = subRectPixelFromPaint(paintPos);
    p = clamp(p, minP, maxP);

    vec2 p0 = clamp(floor(p), minP, maxP);
    vec2 p1 = clamp(p0 + 1.0, minP, maxP);
    vec2 f  = p - p0;

    vec4 c00 = texture(inTexture0, subRectUVFromPixel(p0));
    vec4 c10 = texture(inTexture0, subRectUVFromPixel(vec2(p1.x, p0.y)));
    vec4 c01 = texture(inTexture0, subRectUVFromPixel(vec2(p0.x, p1.y)));
    vec4 c11 = texture(inTexture0, subRectUVFromPixel(p1));

    return mix(mix(c00, c10, f.x), mix(c01, c11, f.x), f.y);
}

// Sharp bilinear: nearest sampling with exactly one device pixel of smoothing at
// each texel boundary. At a fractional content scale, true bilinear spreads a
// one-texel tile border across several device pixels and washes it out, while pure
// nearest drops or doubles texels; this keeps texel edges crisp at any scale and
// degrades to bilinear where the mapping minifies.
vec4 sampleSubRectSharp(vec2 paintPos)
{
    vec2 minP = subRectPixelMin();
    vec2 maxP = subRectPixelMax();
    vec2 p    = subRectPixelFromPaint(paintPos);
    p = clamp(p, minP, maxP);

    vec2 p0 = clamp(floor(p), minP, maxP);
    vec2 p1 = clamp(p0 + 1.0, minP, maxP);

    vec2 w = clamp(fwidth(p), vec2(0.0001), vec2(1.0));
    vec2 f = clamp((p - p0 - 0.5) / w + 0.5, vec2(0.0), vec2(1.0));

    vec4 c00 = texture(inTexture0, subRectUVFromPixel(p0));
    vec4 c10 = texture(inTexture0, subRectUVFromPixel(vec2(p1.x, p0.y)));
    vec4 c01 = texture(inTexture0, subRectUVFromPixel(vec2(p0.x, p1.y)));
    vec4 c11 = texture(inTexture0, subRectUVFromPixel(p1));

    return mix(mix(c00, c10, f.x), mix(c01, c11, f.x), f.y);
}

vec4 sampleTexture(vec2 paintPos, vec2 uv)
{
    if(uvMode > 0.5 && uvMode < 1.5)
    {
        if(interpolationMode < 0.5)
            return sampleSubRectNearest(paintPos);

        if(interpolationMode < 1.5)
            return sampleSubRectLinear(paintPos);

        return sampleSubRectSharp(paintPos);
    }

    return texture(inTexture0, uv);
}

vec4 samplePaint(vec2 paintPos, vec2 uv)
{
    if(paintType < 2.5)
        return sampleTexture(paintPos, uv);

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
