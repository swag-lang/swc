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

// TextMeshPro-style face/outline/glow/bevel effects. All default to 0, which the
// 'fxEnabled' gate turns into the original plain-fill path (kept pixel-identical
// for the common UI-text case). Effects are bounded by the atlas spread, exactly
// like the SDF padding limits TMP's outline/glow extent.
uniform float       fxEnabled;        // 0 = plain fill, 1 = effects path
uniform float       fxFaceDilate;     // SDF units; grows (+) / shrinks (-) the glyph
uniform float       fxFaceSoftness;   // edge softness, in SDF units (0 = crisp)
uniform float       fxOutlineWidth;   // SDF units; 0 = no outline
uniform vec4        fxOutlineColor;
uniform vec4        fxGlowColor;      // a = 0 => no glow
uniform float       fxGlowOffset;     // shifts the glow band outward (SDF units)
uniform float       fxGlowInner;
uniform float       fxGlowOuter;
uniform float       fxGlowPower;
uniform float       fxBevel;          // 0..1 emboss amount

out vec4 color;

float median(float a, float b, float c)
{
    return max(min(a, b), min(max(a, b), c));
}

// Coverage at one sample for a given edge threshold. 'aa' (>=1) is the transition
// width in screen pixels; aa = 1 keeps the analytic ~1px crisp edge.
float coverageAt(vec2 uv, float screenPxRange, float edge, float aa)
{
    vec3  msd = texture(inTexture1, uv).rgb;
    float sd  = median(msd.r, msd.g, msd.b);
    return clamp((sd - edge) * screenPxRange / aa + 0.5, 0.0, 1.0);
}

void main()
{
    // Screen pixels spanned by the distance range (clamped to a 1px floor so the
    // edge never washes out under heavy minification).
    vec2  texSize       = vec2(textureSize(inTexture1, 0));
    vec2  unitRange     = vec2(msdfRange) / texSize;
    vec2  screenTexSize = vec2(1.0) / fwidth(vuv1);
    float screenPxRange = max(0.5 * (unitRange.x * screenTexSize.x + unitRange.y * screenTexSize.y), 1.0);

    vec4 paint = samplePaint(vpaintPos, vuv0);
    vec4 face  = vcolor * paint;

    if (fxEnabled < 0.5)
    {
        // 2x2 supersample across the pixel footprint. A minified MSDF otherwise samples
        // only 4 of the many texels a screen pixel covers, which breaks the median and
        // produces the muddy/uneven look at small sizes.
        vec2  off = fwidth(vuv1) * 0.25;
        float a   = coverageAt(vuv1 + vec2(-off.x, -off.y), screenPxRange, 0.5, 1.0)
                  + coverageAt(vuv1 + vec2( off.x, -off.y), screenPxRange, 0.5, 1.0)
                  + coverageAt(vuv1 + vec2(-off.x,  off.y), screenPxRange, 0.5, 1.0)
                  + coverageAt(vuv1 + vec2( off.x,  off.y), screenPxRange, 0.5, 1.0);
        a *= 0.25;

        color    = face;
        color.w *= pow(a, fontGamma);
        return;
    }

    // --- Effects path ---------------------------------------------------------
    // Transition width in screen pixels (softness widens it for soft edges/shadow).
    float aa = max(1.0, fxFaceSoftness * screenPxRange);

    // MTSDF: the RGB median keeps the face corners sharp, but its sub-edge field has
    // corner-ray artifacts. The alpha channel is a true single-channel SDF: smooth and
    // ray-free, so the outer effects (outline outer edge, glow, soft shadow) use it.
    vec4  msd = texture(inTexture1, vuv1);
    float sdM = median(msd.r, msd.g, msd.b);
    float sdT = msd.a;

    float faceEdge    = 0.5 - fxFaceDilate;
    float outlineEdge = faceEdge - fxOutlineWidth;

    // A soft face (shadow / large softness) uses the smooth true SDF too, so its
    // feathered edge has no rays; a crisp face stays on the sharp-cornered median.
    float sdFace   = mix(sdM, sdT, clamp(fxFaceSoftness * screenPxRange - 1.0, 0.0, 1.0));
    float faceCov  = clamp((sdFace - faceEdge)  * screenPxRange / aa + 0.5, 0.0, 1.0);
    float outerCov = clamp((sdT - outlineEdge)  * screenPxRange / aa + 0.5, 0.0, 1.0);

    // Bevel: emboss only the sloped rim near the edge, lit from the upper-left. The
    // true SDF (smooth, ray-free) gives the surface gradient; its magnitude fades to
    // zero across the flat interior, so the body keeps the base face color while only
    // the bevel band is shaded. 'ref' is the in-ramp gradient magnitude (~1/range),
    // which makes the band size-independent.
    vec3 faceRgb = face.rgb;
    if (fxBevel > 0.0)
    {
        vec2  grad     = vec2(dFdx(sdT), dFdy(sdT));
        float gmag     = length(grad);
        float ref      = 1.0 / screenPxRange;
        float strength = smoothstep(0.0, 0.6 * ref, gmag);
        vec2  n        = gmag > 1e-6 ? grad / gmag : vec2(0.0);
        float lit      = dot(n, normalize(vec2(-1.0, -1.0)));
        faceRgb       *= clamp(1.0 + fxBevel * lit * strength, 0.25, 1.75);
    }

    // Face over outline (straight-alpha compositing). With no outline this reduces
    // to the plain coverage, so the effects path degrades cleanly.
    float faceLA = faceCov  * face.a;
    float outlLA = outerCov * fxOutlineColor.a;
    float shapeA = faceLA + outlLA * (1.0 - faceLA);
    vec3  shapeRgb = faceRgb;
    if (shapeA > 0.0001)
        shapeRgb = (faceRgb * faceLA + fxOutlineColor.rgb * outlLA * (1.0 - faceLA)) / shapeA;

    // Glow: a soft halo from the distance to the (offset) edge, sitting under the shape.
    float glowA = 0.0;
    if (fxGlowColor.a > 0.0)
    {
        float gd = abs(sdT - (0.5 - fxGlowOffset));
        float g  = 1.0 - smoothstep(fxGlowInner, fxGlowOuter, gd);
        glowA    = pow(clamp(g, 0.0, 1.0), max(fxGlowPower, 0.0001)) * fxGlowColor.a;
    }

    // Shape over glow.
    float outA   = shapeA + glowA * (1.0 - shapeA);
    vec3  outRgb = shapeRgb;
    if (outA > 0.0001)
        outRgb = (shapeRgb * shapeA + fxGlowColor.rgb * glowA * (1.0 - shapeA)) / outA;

    color = vec4(outRgb, outA);
}
