#version 330 core
#include base

in vec4     vcolor;
in vec2     vuv0;
in vec2     vuv1;
in vec2     vpaintPos;

uniform sampler2D   inTexture1;

// Gamma applied to glyph coverage to approximate linear-space compositing
// (the framebuffer blend is non-linear sRGB). Counters over-heavy text edges.
uniform float       fontGamma;

// Distance-field range, in atlas texels, that maps to the stored [0,1] range
// (= 2 * spread). Needed to convert the field gradient into screen pixels.
uniform float       msdfRange;

out vec4 color;

float median(float a, float b, float c)
{
    return max(min(a, b), min(max(a, b), c));
}

// Coverage at one sample, using an analytic screen-pixel distance so the edge stays
// ~1px crisp at any zoom. The median of the three channels reconstructs the true
// distance, preserving sharp corners a single-channel SDF would round off.
float coverageAt(vec2 uv, float screenPxRange)
{
    vec3  msd = texture(inTexture1, uv).rgb;
    float sd  = median(msd.r, msd.g, msd.b);
    return clamp((sd - 0.5) * screenPxRange + 0.5, 0.0, 1.0);
}

void main()
{
    // Screen pixels spanned by the distance range (clamped to a 1px floor so the
    // edge never washes out under heavy minification).
    vec2  texSize       = vec2(textureSize(inTexture1, 0));
    vec2  unitRange     = vec2(msdfRange) / texSize;
    vec2  screenTexSize = vec2(1.0) / fwidth(vuv1);
    float screenPxRange = max(0.5 * (unitRange.x * screenTexSize.x + unitRange.y * screenTexSize.y), 1.0);

    // 2x2 supersample across the pixel footprint. A minified MSDF otherwise samples
    // only 4 of the many texels a screen pixel covers, which breaks the median and
    // produces the muddy/uneven look at small sizes.
    vec2  off = fwidth(vuv1) * 0.25;
    float a   = coverageAt(vuv1 + vec2(-off.x, -off.y), screenPxRange)
              + coverageAt(vuv1 + vec2( off.x, -off.y), screenPxRange)
              + coverageAt(vuv1 + vec2(-off.x,  off.y), screenPxRange)
              + coverageAt(vuv1 + vec2( off.x,  off.y), screenPxRange);
    a *= 0.25;

    color    = vcolor * samplePaint(vpaintPos, vuv0);
    color.w *= pow(a, fontGamma);
}
