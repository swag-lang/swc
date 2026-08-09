#global public

using Core, Ogl, Core.Math

#[Swag.Strict]
alias ShaderHandle = u64                               // Opaque OpenGL program handle owned by [[Pixel.RenderOgl]].
const InvalidShaderHandle: ShaderHandle = cast() 0     // Sentinel that identifies no shader program.

#[Swag.Strict]
alias ShaderParamHandle = s64                                     // Opaque shader-uniform location.
const InvalidShaderParamHandle: ShaderParamHandle = cast() -1     // Sentinel for an unavailable uniform.

// Stores a shader program and the uniform locations shared by Pixel shaders.
//
// Handles are initialized by [[Pixel.IRenderer.init]] and remain owned by that renderer.
struct ShaderBase
{
    handle:            ShaderHandle          // OpenGL program handle.
    mvp:               ShaderParamHandle     // Model-view-projection matrix uniform.
    mdl:               ShaderParamHandle     // Model matrix uniform.
    boundRect:         ShaderParamHandle     // Destination bounds uniform.
    textureRect:       ShaderParamHandle     // Source texture rectangle uniform.
    uvMode:            ShaderParamHandle     // Texture-coordinate mode uniform.
    interpolationMode: ShaderParamHandle     // Texture interpolation uniform.
    copyMode:          ShaderParamHandle     // Direct-copy mode uniform.
    textureW:          ShaderParamHandle     // Texture width uniform.
    textureH:          ShaderParamHandle     // Texture height uniform.
    paintType:         ShaderParamHandle     // Brush type uniform.
    gradientSpread:    ShaderParamHandle     // Gradient spread uniform.
    gradientStart:     ShaderParamHandle     // Gradient start/center uniform.
    gradientEnd:       ShaderParamHandle     // Gradient end/secondary-center uniform.
    gradientRadius:    ShaderParamHandle     // Radial radii uniform.
    gradientAngles:    ShaderParamHandle     // Sweep angle interval uniform.
    gradientCount:     ShaderParamHandle     // Active gradient-stop count uniform.
    gradientOffsets:   ShaderParamHandle     // Gradient-stop offsets uniform.
    gradientColors:    ShaderParamHandle     // Gradient-stop colors uniform.
    internal
    premultiplyBlendSource: ShaderParamHandle = InvalidShaderParamHandle
}

// Uses the standard shader without antialiasing coverage.
struct ShaderSimple
{
    using base: ShaderBase     // Shared program and uniform handles.
}

// Uses the standard shader with per-vertex antialiasing coverage.
struct ShaderAA
{
    using base: ShaderBase     // Shared program and uniform handles.
}

// Extends the standard shader with bitmap/MSDF text-effect uniforms.
struct ShaderFont
{
    using base: ShaderBase     // Shared program and uniform handles.

    fxEnabled:      ShaderParamHandle     // Effect-enable uniform.
    fxFaceDilate:   ShaderParamHandle     // Face dilation uniform.
    fxFaceSoftness: ShaderParamHandle     // Face softness uniform.
    fxOutlineWidth: ShaderParamHandle     // Outline width uniform.
    fxOutlineColor: ShaderParamHandle     // Outline color uniform.
    fxGlowColor:    ShaderParamHandle     // Glow color uniform.
    fxGlowOffset:   ShaderParamHandle     // Glow offset uniform.
    fxGlowInner:    ShaderParamHandle     // Inner glow boundary uniform.
    fxGlowOuter:    ShaderParamHandle     // Outer glow boundary uniform.
    fxGlowPower:    ShaderParamHandle     // Glow falloff uniform.
    fxBevel:        ShaderParamHandle     // Bevel intensity uniform.
}

// Extends the simple shader with separable-blur controls.
struct ShaderBlur
{
    using base: ShaderBase            // Shared program and uniform handles.
    radius:     ShaderParamHandle     // Blur radius uniform.
    axis:       ShaderParamHandle     // Blur axis uniform: `0` horizontal, `1` vertical.
}

// Extends the simple shader with supersampling resolve controls.
struct ShaderResolve
{
    using base: ShaderBase            // Shared program and uniform handles.
    factor:     ShaderParamHandle     // Integer supersampling factor uniform.
}
