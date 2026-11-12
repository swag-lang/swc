#global public

using Swag, Core, Ogl, Core.Math

private
{
    const BaseVertexShader = #include("shaders/base.vert")
    const BasePixelShader  = #include("shaders/base.frag")

    const VertexShaderSimple = #include("shaders/simple.vert")
    const PixelShaderSimple  = #include("shaders/simple.frag")

    const VertexShaderAA = #include("shaders/aa.vert")
    const PixelShaderAA  = #include("shaders/aa.frag")

    const PixelShaderYuv      = #include("shaders/yuv.frag")
    const PixelShaderBlur     = #include("shaders/blur.frag")
    const PixelShaderResolve  = #include("shaders/resolve.frag")
    const PixelShaderBackdrop = #include("shaders/backdrop.frag")

    const VertexShaderFont    = #include("shaders/font.vert")
    const PixelShaderFont     = #include("shaders/font.frag")
    const PixelShaderFontMsdf = #include("shaders/font_msdf.frag")

    const KhrAdvancedBlendShaderHeader = "#extension GL_KHR_blend_equation_advanced : require\nlayout(blend_support_all_equations) out;\n"

    const AdvancedBlendingNone:        u8 = 0
    const AdvancedBlendingKhrCoherent: u8 = 1
    const AdvancedBlendingNvCoherent:  u8 = 2
    const AdvancedBlendingKhrBarrier:  u8 = 3
    const AdvancedBlendingNvBarrier:   u8 = 4

    // How the context answers whether the driver reset the device: not at all, through the core
    // entry point of OpenGL 4.5, or through `GL_ARB_robustness`.
    const ResetQueryNone: u8 = 0
    const ResetQueryCore: u8 = 1
    const ResetQueryArb:  u8 = 2

    // Coverage masks kept alive at once. A mask costs a full render-target plane, and only the
    // surface and the layers open over it are ever sampled together.
    const MaxClipMasks = 4'u64
}

// Sets the glyph-coverage exponent used by the font shaders.
//
// This approximates linear-space text compositing when framebuffer blending uses
// nonlinear sRGB.
// 1.0 = off; ~1.33 (= 1/0.75) is a mild, safe correction for dark-on-light text.
const FontGamma = 1.0'f32 / 0.75

// MSDF distance range in atlas texels mapped to the stored [0,1] range.
//
// The value must remain twice the font atlas spread.
const MsdfRange = 16.0'f32

// Last mip level of a distance-field atlas: a level averages blocks of 2^level texels, and glyphs
// sit on cells of the 8-texel spread (`RefEmSpread`), so level 3 is the last one whose blocks stay
// inside one glyph.
const FontAtlasMaxLevel: GLint = 3

#[Swag.Strict]
alias TextureHandle = u64     // Opaque renderer texture identifier.
const InvalidTextureHandle: TextureHandle = cast(0)     // Sentinel that identifies no texture.

#[Swag.Strict]
alias RenderTargetHandle = u64     // Opaque renderer framebuffer identifier.
const InvalidRenderTargetHandle: RenderTargetHandle = cast(0)     // Sentinel that identifies no framebuffer.

#[Swag.Strict]
alias RenderTargetSurfaceHandle = u64     // Opaque renderer depth/stencil-surface identifier.
const InvalidRenderTargetSurfaceHandle: RenderTargetSurfaceHandle = cast(0)     // Sentinel that identifies no surface.

// Holds the two chroma planes of a planar texture, beside the luma handle the caller carries.
//
// Public only because it names the type of a renderer field, which the generated module surface
// spells out; nothing outside this backend has any use for it.
internal struct ChromaPlanes
{
    internal
    {
        chromaB: GLuint
        chromaR: GLuint
        factors: YuvConversionFactors
    }
}

// A clipping region drawn as coverage: one channel per device pixel of the target it serves.
#[Swag.Opaque]
internal struct ClipMask
{
    framebuffer: GLuint
    texture:     GLuint
    width:       s32
    height:      s32
    lastUse:     u64     // Stamp of the last request that selected this mask, for reuse order.
}

// Executes [[Pixel.Painter]] command streams through OpenGL.
//
// A renderer is non-copyable and owns its shaders, textures, buffers, and queued
// render targets. Borrow it as an [[Pixel.IRenderer]], create a
// [[Pixel.RenderContext]], call `init`, then bracket frames with `begin` and `end`.
// The artistic blend modes use advanced blend equations, with explicit barriers when the
// context does not provide coherent ordering; call
// [[Pixel.RenderOgl.supportsAdvancedBlending]] after `init` before selecting one on
// a context whose driver capabilities are not known.
#[Swag.NoCopy]
struct RenderOgl
{
    public
    {
        // Glyph storage and font views of this renderer. A glyph atlas carries a GPU texture created
        // in this renderer's context, so it must not outlive it: fonts are created through this cache
        // and released with the renderer.
        fonts: FontCache

        // The built-in shaders. Bind one with [[Pixel.Painter.setShader]] and feed its uniforms
        // with [[Pixel.Painter.setShaderParam]] to build a custom pass.
        shaderSimple:   ShaderSimple      // Built-in non-antialiased shader.
        shaderAA:       ShaderAA          // Built-in antialiased shader.
        shaderYuv:      ShaderYuv         // Built-in planar 4:2:0 shader.
        shaderBlur:     ShaderBlur        // Built-in separable-blur shader.
        shaderResolve:  ShaderResolve     // Built-in supersampling-resolve shader.
        shaderFont:     ShaderFont        // Built-in bitmap-font shader.
        shaderFontMsdf: ShaderFont        // Built-in MSDF-font shader.

        // Device pixels the overlap-safe path has cleared as alpha scratch.
        //
        // Compare with [[Pixel.RenderOgl.scratchFullPixels]] to measure the saving on the same
        // batches. Reset both counters with [[Pixel.RenderOgl.resetScratchCounters]].
        readonly scratchClearedPixels: u64

        // Device pixels the same batches would clear using their whole clipping rectangles.
        //
        // This is the reference cost for [[Pixel.RenderOgl.scratchClearedPixels]], accumulated
        // since the last call to [[Pixel.RenderOgl.resetScratchCounters]].
        readonly scratchFullPixels: u64

        // Times [[Pixel.RenderOgl.recoverLostDevice]] rebuilt this renderer after a device reset.
        readonly deviceResets: u32
    }

    // The GPU objects and the state mirror of the context. Everything here belongs to the
    // OpenGL context this renderer owns; reaching in from outside would desynchronize the mirror.

    private
    {
        using native:   NativeRenderOgl     // Platform-specific context operations.
        vertexbuffer:   GLuint              // OpenGL streaming vertex buffer.
        worldTransform: Transform2          // Current painter world transform.

        // The transform the model matrix was last built from, and the scissor currently in force,
        // in device pixels from the top left. Both are what lets a draw narrow the region it
        // touches to the geometry it is about to draw.
        deviceTransform: Transform2
        scissorBox:      Math.Rectangle
        scissorOn:       bool
        orthoMatrix:     Matrix4x4     // Current surface projection matrix.
        modelMatrix:     Matrix4x4     // Current model matrix.
        whiteTexture:    GLuint        // Built-in one-pixel white texture.
        clearTexture:    GLuint        // Built-in one-pixel transparent texture, drawn for a lost texture.
        hatchTextures:   [HatchStyle] GLuint     // Built-in hatch texture handles.
        // The two chroma planes of every planar texture, keyed by the luma handle the caller
        // holds. A texture is one handle everywhere else in this module, and a planar picture is
        // three: keeping the other two here is what lets it travel as an ordinary texture.
        chromaPlanes: HashTable'(TextureHandle, ChromaPlanes)

        // The program a planar texture displaced, restored as soon as one stops being drawn.
        planarPrevShader: *ShaderBase?

        gradientTexture:         GLuint                    // Dynamically sized gradient-stop table.
        gradientTextureCapacity: u64                       // Stop slots allocated in `gradientTexture`.
        gradientOffsetUpload:    Array'Vector4             // Reused first texture row.
        gradientColorUpload:     Array'Vector4             // Reused second texture row.
        blendingMode:            BlendingMode = .Alpha     // Active OpenGL blending mode.
        colorMask:               ColorMask    = {true, true, true, false}     // Painter-requested channel mask.
        curRC:                   RenderContext             // Active drawable and viewport.

        stackReleasedRT: Array'(*RenderTarget?)     // Targets queued for deferred release.
        stackRT:         Array'(*RenderTarget?)     // Nested bound render targets.
        curRT:           *RenderTarget?             // Active off-screen target, if any.
        shaderBackdrop:  ShaderBackdrop
        curShader:       *ShaderBase?     // Active shader, or the default shader.
        overlapMode:     bool             // Whether overlap-safe alpha drawing is active.
        alphaReplay:     bool             // Whether commands are being replayed to rebuild a target's alpha plane.
        contentScale:    f32 = 1          // Device pixels per unit of the painter stream being drawn.

        // The clipping region, rendered as coverage into a texture the size of the target and read
        // by every fragment at its device position. The hardware stencil holds one bit per pixel,
        // and a region cut along a curve needs the fraction of each pixel its edge covers.
        clipMasks:             Array'ClipMask          // One mask per target size a region was drawn for.
        clipMaskClock:         u64                     // Counter stamping each mask request, for reuse order.
        clipMaskIndex:         s32 = -1                // Mask of the region in force, or none yet.
        clipMaskOn:            bool                    // Whether fragments are cut by the region.
        clipMaskWriting:       bool                    // Whether fragments are writing the region.
        stackClipMaskOn:       Array'bool              // Regions suspended by the render targets bound inside them.
        nativeContext:         const *void?            // Shared native OpenGL context owned by interface-created drawables.
        offscreen:             bool                    // Contexts own invisible drawables and never present to the desktop.
        contextCount:          u32                     // Number of live interface-created drawables.
        contexts:              Array'(*OglContext)     // The live interface-created drawables, which share `nativeContext`.
        generation:            TextureGeneration       // Device generation stamped on every texture and target.
        resetQuery:            u8                      // How the context reports a device reset, if it does.
        deviceLost:            bool                    // Whether a reported reset still waits for a replacement context.
        advancedBlending:      u8                      // Advanced blend-equation family supplied by the current context.
        advancedBarrierActive: bool                    // Whether this context must keep later framebuffer touches in separate passes.
    }
}

private impl RenderOgl
{
    func oglContext(rc: RenderContext)->*OglContext
    {
        Swag.assert(rc.data != null, "OpenGL render context has no backend state")
        return cast(*OglContext, rc.data)
    }

    internal func hasExtension(name: string)->bool
    {
        var count: GLint
        glGetIntegerv(GL_NUM_EXTENSIONS, &count)
        for idx in count
        {
            let value = glGetStringi(GL_EXTENSIONS, cast(GLuint, idx))
            if value and cast(string, cast(const cstring, value)) == name do
                return true
        }

        return false
    }

    func advancedBlendEquation(mode: BlendingMode)->GLenum
    {
        switch mode
        {
        case .Multiply:   return GL_MULTIPLY_KHR
        case .Screen:     return GL_SCREEN_KHR
        case .Overlay:    return GL_OVERLAY_KHR
        case .Darken:     return GL_DARKEN_KHR
        case .Lighten:    return GL_LIGHTEN_KHR
        case .ColorDodge: return GL_COLORDODGE_KHR
        case .ColorBurn:  return GL_COLORBURN_KHR
        case .HardLight:  return GL_HARDLIGHT_KHR
        case .SoftLight:  return GL_SOFTLIGHT_KHR
        case .Difference: return GL_DIFFERENCE_KHR
        case .Exclusion:  return GL_EXCLUSION_KHR
        case .Hue:        return GL_HSL_HUE_KHR
        case .Saturation: return GL_HSL_SATURATION_KHR
        case .Color:      return GL_HSL_COLOR_KHR
        case .Luminosity: return GL_HSL_LUMINOSITY_KHR
        default:          return GL_FUNC_ADD
        }
    }

    mtd const usesKhrAdvancedBlending()->bool => .advancedBlending == AdvancedBlendingKhrCoherent or .advancedBlending == AdvancedBlendingKhrBarrier

    mtd const requiresAdvancedBlendBarrier()->bool => .advancedBlending == AdvancedBlendingKhrBarrier or .advancedBlending == AdvancedBlendingNvBarrier

    // Starts a new framebuffer-touching pass on contexts whose advanced equations are not
    // coherent. Once a command stream selects an artistic mode, every later touch is isolated:
    // standard draws and clears also count as touches in the extension contract.
    mtd prepareFramebufferTouch()
    {
        if not .advancedBarrierActive do
            return

        switch .advancedBlending
        {
        case AdvancedBlendingKhrBarrier: glBlendBarrierKHR()
        case AdvancedBlendingNvBarrier:  glBlendBarrierNV()
        }
    }

    mtd finishAdvancedBlendPass()
    {
        // Keep the barrier state latched across draw calls. Swapping or ending a command stream
        // does not end the extension's framebuffer-touch ordering contract; the first clear or
        // draw of the next stream must still start behind a barrier.
        .prepareFramebufferTouch()
    }

    // Returns the text of one shader source, past the byte-order mark it may start with.
    //
    // A shader travels as the bytes of its file, and GLSL accepts nothing at all before
    // `#version`: a mark an editor left at the start of one makes every program built from it
    // fail to compile, which reaches the screen as a picture that simply never draws.
    internal func shaderSource(bytes: const [..] u8)->string
    {
        if bytes.count >= 3 and bytes[0] == 0xEF and bytes[1] == 0xBB and bytes[2] == 0xBF do
            return Swag.makeString(bytes.buffer + 3, bytes.count - 3)
        return Swag.makeString(bytes.buffer, bytes.count)
    }

    // Fails with the driver's log when the shader did not compile.
    //
    // A driver may fill the log after a successful compile too, so only the status decides.
    func checkShaderCompiled(shaderID: GLuint) fail
    {
        var status: GLint
        glGetShaderiv(shaderID, GL_COMPILE_STATUS, &status)
        if status do
            return

        var logLength: GLint
        glGetShaderiv(shaderID, GL_INFO_LOG_LENGTH, &logLength)
        var log: String
        log.reserve(cast(u64, logLength) + 1)
        var written: GLsizei
        glGetShaderInfoLog(shaderID, logLength, &written, log.buffer)
        log.length = cast(u64, written)
        fail Swag.SystemError{Errors.mkString(Format.toString("cannot compile a shader: %", log))}
    }

    // Fails with the driver's log when the program did not link.
    func checkProgramLinked(programID: GLuint) fail
    {
        var status: GLint
        glGetProgramiv(programID, GL_LINK_STATUS, &status)
        if status do
            return

        var logLength: GLint
        glGetProgramiv(programID, GL_INFO_LOG_LENGTH, &logLength)
        var log: String
        log.reserve(cast(u64, logLength) + 1)
        var written: GLsizei
        glGetProgramInfoLog(programID, logLength, &written, log.buffer)
        log.length = cast(u64, written)
        fail Swag.SystemError{Errors.mkString(Format.toString("cannot link a shader program: %", log))}
    }

    mtd createShaders()
    {
        // Programs share three vertex stages. Keep those compiled objects for the whole batch
        // instead of compiling the same source again for each fragment stage.
        func compileVertex(source: const [..] u8)->GLuint fail
        {
            var text: String = shaderSource(source)
            text.replace("#include base", shaderSource(BaseVertexShader))
            let shader = glCreateShader(GL_VERTEX_SHADER)
            defer #fail glDeleteShader(shader)
            var pointer = text.buffer
            var length  = cast(GLint, text.length)
            glShaderSource(shader, 1, &pointer, &length)
            glCompileShader(shader)
            try checkShaderCompiled(shader)
            return shader
        }

        let simple = expect compileVertex(VertexShaderSimple)
        defer glDeleteShader(simple)
        let aa = expect compileVertex(VertexShaderAA)
        defer glDeleteShader(aa)
        let font = expect compileVertex(VertexShaderFont)
        defer glDeleteShader(font)

        var baseBuilder: StringBuilder
        if .usesKhrAdvancedBlending() do
            baseBuilder.appendString(KhrAdvancedBlendShaderHeader)
        baseBuilder.appendString(shaderSource(BasePixelShader))
        let baseSource = baseBuilder.moveToString()

        scope
        {
            expect .createShader(&.shaderSimple, simple, PixelShaderSimple, baseSource)
            let text0 = glGetUniformLocation(cast(GLuint, .shaderSimple.handle), ("inTexture0").buffer)
            glUseProgram(cast(GLuint, .shaderSimple.handle))
            glUniform1i(text0, 0)
        }

        scope
        {
            expect .createShader(&.shaderAA, aa, PixelShaderAA, baseSource)
            let text0 = glGetUniformLocation(cast(GLuint, .shaderAA.handle), ("inTexture0").buffer)
            let text1 = glGetUniformLocation(cast(GLuint, .shaderAA.handle), ("inTexture1").buffer)
            glUseProgram(cast(GLuint, .shaderAA.handle))
            glUniform1i(text0, 0)
            glUniform1i(text1, 1)
        }

        scope
        {
            // The picture arrives as three planes on units 0, 3 and 4, and the shader converts
            // while it samples: that is what lets a decoder skip the conversion entirely.
            expect .createShader(&.shaderYuv, simple, PixelShaderYuv, baseSource)
            let text0   = glGetUniformLocation(cast(GLuint, .shaderYuv.handle), ("inTexture0").buffer)
            let chromaB = glGetUniformLocation(cast(GLuint, .shaderYuv.handle), ("inChromaB").buffer)
            let chromaR = glGetUniformLocation(cast(GLuint, .shaderYuv.handle), ("inChromaR").buffer)
            .shaderYuv.lumaRed = cast(ShaderParamHandle, glGetUniformLocation(cast(GLuint, .shaderYuv.handle), ("yuvLumaRed").buffer))
            .shaderYuv.green   = cast(ShaderParamHandle, glGetUniformLocation(cast(GLuint, .shaderYuv.handle), ("yuvGreen").buffer))
            glUseProgram(cast(GLuint, .shaderYuv.handle))
            glUniform1i(text0, 0)
            glUniform1i(chromaB, 3)
            glUniform1i(chromaR, 4)
        }

        scope
        {
            expect .createShader(&.shaderFont, font, PixelShaderFont, baseSource)
            let text0 = glGetUniformLocation(cast(GLuint, .shaderFont.handle), ("inTexture0").buffer)
            let text1 = glGetUniformLocation(cast(GLuint, .shaderFont.handle), ("inTexture1").buffer)
            let gamma = glGetUniformLocation(cast(GLuint, .shaderFont.handle), ("fontGamma").buffer)
            glUseProgram(cast(GLuint, .shaderFont.handle))
            glUniform1i(text0, 0)
            glUniform1i(text1, 1)
            glUniform1f(gamma, FontGamma)
        }

        scope
        {
            expect .createShader(&.shaderFontMsdf, font, PixelShaderFontMsdf, baseSource)
            let text0 = glGetUniformLocation(cast(GLuint, .shaderFontMsdf.handle), ("inTexture0").buffer)
            let text1 = glGetUniformLocation(cast(GLuint, .shaderFontMsdf.handle), ("inTexture1").buffer)
            let gamma = glGetUniformLocation(cast(GLuint, .shaderFontMsdf.handle), ("fontGamma").buffer)
            let range = glGetUniformLocation(cast(GLuint, .shaderFontMsdf.handle), ("msdfRange").buffer)
            glUseProgram(cast(GLuint, .shaderFontMsdf.handle))
            glUniform1i(text0, 0)
            glUniform1i(text1, 1)
            glUniform1f(gamma, FontGamma)
            glUniform1f(range, MsdfRange)

            let h = cast(GLuint, .shaderFontMsdf.handle)
            .shaderFontMsdf.fxEnabled      = cast(glGetUniformLocation(h, ("fxEnabled").buffer))
            .shaderFontMsdf.fxFaceDilate   = cast(glGetUniformLocation(h, ("fxFaceDilate").buffer))
            .shaderFontMsdf.fxFaceSoftness = cast(glGetUniformLocation(h, ("fxFaceSoftness").buffer))
            .shaderFontMsdf.fxOutlineWidth = cast(glGetUniformLocation(h, ("fxOutlineWidth").buffer))
            .shaderFontMsdf.fxOutlineColor = cast(glGetUniformLocation(h, ("fxOutlineColor").buffer))
            .shaderFontMsdf.fxGlowColor    = cast(glGetUniformLocation(h, ("fxGlowColor").buffer))
            .shaderFontMsdf.fxGlowOffset   = cast(glGetUniformLocation(h, ("fxGlowOffset").buffer))
            .shaderFontMsdf.fxGlowInner    = cast(glGetUniformLocation(h, ("fxGlowInner").buffer))
            .shaderFontMsdf.fxGlowOuter    = cast(glGetUniformLocation(h, ("fxGlowOuter").buffer))
            .shaderFontMsdf.fxGlowPower    = cast(glGetUniformLocation(h, ("fxGlowPower").buffer))
            .shaderFontMsdf.fxBevel        = cast(glGetUniformLocation(h, ("fxBevel").buffer))
        }

        scope
        {
            expect .createShader(&.shaderBlur, simple, PixelShaderBlur, baseSource)
            let text0 = glGetUniformLocation(cast(GLuint, .shaderBlur.handle), ("inTexture0").buffer)
            glUseProgram(cast(GLuint, .shaderBlur.handle))
            glUniform1i(text0, 0)
            .shaderBlur.axis   = cast(glGetUniformLocation(cast(GLuint, .shaderBlur.handle), ("axis").buffer))
            .shaderBlur.radius = cast(glGetUniformLocation(cast(GLuint, .shaderBlur.handle), ("radius").buffer))
        }

        scope
        {
            expect .createShader(&.shaderResolve, simple, PixelShaderResolve, baseSource)
            let text0 = glGetUniformLocation(cast(GLuint, .shaderResolve.handle), ("inTexture0").buffer)
            glUseProgram(cast(GLuint, .shaderResolve.handle))
            glUniform1i(text0, 0)
            .shaderResolve.factor = cast(glGetUniformLocation(cast(GLuint, .shaderResolve.handle), ("factor").buffer))
        }

        scope
        {
            expect .createShader(&.shaderBackdrop, simple, PixelShaderBackdrop, baseSource)
            let handle = cast(GLuint, .shaderBackdrop.handle)
            glUseProgram(handle)
            glUniform1i(glGetUniformLocation(handle, ("inTexture0").buffer), 0)
            .shaderBackdrop.mode       = cast(glGetUniformLocation(handle, ("mode").buffer))
            .shaderBackdrop.radius     = cast(glGetUniformLocation(handle, ("radius").buffer))
            .shaderBackdrop.saturation = cast(glGetUniformLocation(handle, ("saturation").buffer))
            .shaderBackdrop.tint       = cast(glGetUniformLocation(handle, ("tint").buffer))
            .shaderBackdrop.sourceSize = cast(glGetUniformLocation(handle, ("sourceSize").buffer))
        }
    }

    func generateTexture(datas: const [..] u8, w, h: s32)->GLuint
    {
        Swag.assert(datas.count <= 8 * 8)
        var previousTexture, previousBuffer, previousAlignment, previousRowLength, previousSkipRows, previousSkipPixels: GLint
        glGetIntegerv(GL_TEXTURE_BINDING_2D, &previousTexture)
        glGetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING, &previousBuffer)
        glGetIntegerv(GL_UNPACK_ALIGNMENT, &previousAlignment)
        glGetIntegerv(GL_UNPACK_ROW_LENGTH, &previousRowLength)
        glGetIntegerv(GL_UNPACK_SKIP_ROWS, &previousSkipRows)
        glGetIntegerv(GL_UNPACK_SKIP_PIXELS, &previousSkipPixels)
        defer
        {
            glBindTexture(GL_TEXTURE_2D, cast(GLuint, previousTexture))
            glBindBuffer(GL_PIXEL_UNPACK_BUFFER, cast(GLuint, previousBuffer))
            glPixelStorei(GL_UNPACK_ALIGNMENT, previousAlignment)
            glPixelStorei(GL_UNPACK_ROW_LENGTH, previousRowLength)
            glPixelStorei(GL_UNPACK_SKIP_ROWS, previousSkipRows)
            glPixelStorei(GL_UNPACK_SKIP_PIXELS, previousSkipPixels)
        }

        var arr: [64] u32
        for p, i in datas do
            arr[i] = p ? 0xFFFFFFFF : 0

        var result: GLuint
        glGenTextures(1, &result)
        let nameError = glGetError()
        if not result or nameError != GL_NO_ERROR do
            Swag.panic("OpenGL cannot allocate a built-in texture", #curlocation)
        glBindTexture(GL_TEXTURE_2D, result)
        glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0)
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
        glPixelStorei(GL_UNPACK_ROW_LENGTH, 0)
        glPixelStorei(GL_UNPACK_SKIP_ROWS, 0)
        glPixelStorei(GL_UNPACK_SKIP_PIXELS, 0)
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, &arr[0])
        if glGetError() != GL_NO_ERROR do
            Swag.panic("OpenGL cannot initialize a built-in texture", #curlocation)
        return result
    }

    func ortho(b, t, l, r, n, f: f32)->Matrix4x4
    {
        var result: #returntype
        result.m[0, 0] = 2 / (r - l)
        result.m[0, 1] = 0
        result.m[0, 2] = 0
        result.m[0, 3] = 0

        result.m[1, 0] = 0
        result.m[1, 1] = 2 / (t - b)
        result.m[1, 2] = 0
        result.m[1, 3] = 0

        result.m[2, 0] = 0
        result.m[2, 1] = 0
        result.m[2, 2] = -2 / (f - n)
        result.m[2, 3] = 0

        result.m[3, 0] = -(r + l) / (r - l)
        result.m[3, 1] = -(t + b) / (t - b)
        result.m[3, 2] = -(f + n) / (f - n)
        result.m[3, 3] = 1
        return result
    }

    mtd buildModelMatrix(modelTransform: Transform2)
    {
        var tr = .worldTransform
        tr.multiply(modelTransform)

        // The painter stream is recorded in logical units; the content scale maps
        // them to device pixels. Applied last, it scales positions and translations
        // alike, so widget code never sees physical coordinates.
        if .contentScale != 1 do
            tr.multiply(Transform2.createScale(.contentScale, .contentScale, 0, 0))

        // Vertices reach the screen through this, so a bound recorded in vertex space becomes a
        // device rectangle through the same transform.
        .deviceTransform = tr

        // Received matrix is in row major order, so transpose it

        // x
        .modelMatrix.m[0, 0] = tr.m11
        .modelMatrix.m[0, 1] = tr.m12

        // y
        .modelMatrix.m[1, 0] = tr.m21
        .modelMatrix.m[1, 1] = tr.m22

        // z
        .modelMatrix.m[2, 2] = 1

        // translation
        .modelMatrix.m[3, 0] = tr.m31
        .modelMatrix.m[3, 1] = tr.m32
    }

    mtd setBlendingMode(bm: BlendingMode)
    {
        .blendingMode = bm
        if bm.usesAdvancedBlending() and .requiresAdvancedBlendBarrier() do
            .advancedBarrierActive = true

        // The fragment shader must know when a zero-alpha fragment is meaningful: its
        // zero-coverage discard is an optimization under alpha compositing and a bug under
        // 'Copy', where a transparent source is the erase operation. The uniform lives per
        // program, so it is refreshed here and on every program switch, never only when a
        // texture brush happens to be bound.
        if .curShader
        {
            glUniform1i(cast(GLint, .curShader.copyMode), cast(GLint, (bm == .Copy)))
            glUniform1i(cast(GLint, .curShader.premultiplyBlendSource), cast(GLint, (.usesKhrAdvancedBlending() and bm.usesAdvancedBlending())))
        }

        switch #complete bm
        {
        case .Copy:
            glDisable(GL_BLEND)

        case .Alpha:

            // The alpha channel composites with its own factors. Running it through the colour
            // rule scales the source alpha by itself, so coverage accumulates as the square of
            // what was asked for and a stack of faint layers reaches almost no opacity at all:
            // a soft gradient built from many rings comes out as nothing. Only the destination
            // is weighted for alpha, which is the "over" operator this mode names.
            glEnable(GL_BLEND)
            glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA)
            glBlendEquation(GL_FUNC_ADD)

        case .Add:
            glEnable(GL_BLEND)
            glBlendFunc(GL_ONE, GL_ONE)
            glBlendEquation(GL_FUNC_ADD)

        case .Sub:
            glEnable(GL_BLEND)
            glBlendFunc(GL_ONE, GL_ONE)
            glBlendEquation(GL_FUNC_SUBTRACT)

        case .SubDst:
            glEnable(GL_BLEND)
            glBlendFunc(GL_ONE, GL_ONE)
            glBlendEquation(GL_FUNC_REVERSE_SUBTRACT)

        case .Min:
            glEnable(GL_BLEND)
            glBlendFunc(GL_ONE, GL_ONE)
            glBlendEquation(GL_MIN)

        case .Max:
            glEnable(GL_BLEND)
            glBlendFunc(GL_ONE, GL_ONE)
            glBlendEquation(GL_MAX)

        case .DstIn:
            glEnable(GL_BLEND)
            glBlendFuncSeparate(GL_ZERO, GL_SRC_ALPHA, GL_ZERO, GL_SRC_ALPHA)
            glBlendEquation(GL_FUNC_ADD)

        case .Multiply, .Screen, .Overlay, .Darken, .Lighten, .ColorDodge, .ColorBurn, .HardLight,
             .SoftLight, .Difference, .Exclusion, .Hue, .Saturation, .Color, .Luminosity:
            Swag.assert(.advancedBlending != AdvancedBlendingNone, "OpenGL renderer does not support advanced blending modes on this context")
            if .advancedBlending == AdvancedBlendingNone
            {
                glEnable(GL_BLEND)
                glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA)
                glBlendEquation(GL_FUNC_ADD)
                return
            }

            glEnable(GL_BLEND)
            glBlendEquation(advancedBlendEquation(bm))
        }
    }

    mtd setColorMask(mask: ColorMask)
    {
        .colorMask = mask
        glColorMask(mask.r ? GL_TRUE : GL_FALSE,
                    mask.g ? GL_TRUE : GL_FALSE,
                    mask.b ? GL_TRUE : GL_FALSE,
                    mask.a ? GL_TRUE : GL_FALSE)
    }
}

impl RenderOgl
{
    // Selects GPU rendering without a visible native window.
    //
    // Call before creating any context. When enabled, [[Pixel.IRenderer.createContext]] accepts
    // a null drawable and owns an invisible platform context host. Frames are read through
    // render targets; `end` does not swap a desktop back buffer. Disabling restores the normal
    // window-backed contract. Context creation still fails when OpenGL is unavailable.
    mtd setOffscreen(enabled = true)
    {
        Swag.assert(.contextCount == 0, "offscreen mode can only change before creating renderer contexts")
        .offscreen = enabled
    }

    // Resets the scratch-clear counters, so a caller measures a frame rather than a session.
    mtd resetScratchCounters()
    {
        .scratchClearedPixels, .scratchFullPixels = 0
    }

    // Reports whether the current context provides advanced blend equations.
    //
    // Call this after [[Pixel.IRenderer.init]]. A `false` result means
    // [[Pixel.RenderCpu]] remains available for the artistic blend modes, while
    // this OpenGL context can use the traditional modes only.
    mtd const supportsAdvancedBlending()->bool => .advancedBlending != AdvancedBlendingNone

    // Rebuilds the renderer after the driver reset its graphics device, and reports whether it had to.
    //
    // A reset — a GPU timeout under heavy load, a driver update, an adapter removal — destroys
    // every resource of the context without making a single call fail: drawing then produces
    // nothing and every readback returns stale bytes, for good. Call this before recording a
    // frame. It answers `false` while the device is healthy, and always on a context that cannot
    // report a reset.
    //
    // After it answers `true`, every [[Pixel.Texture]] and [[Pixel.RenderTarget]] created before
    // reads as invalid. The renderer restores its own shaders, buffers and glyph atlases; owners
    // upload their textures again, and every drawable must be repainted completely. It fails when
    // no replacement context can be created: the renderer then draws nothing, and the next call
    // tries again.
    mtd recoverLostDevice()->bool fail
    {
        if .resetQuery == ResetQueryNone or .contexts.count == 0 do
            return false

        let first = .contexts[0]
        if not .deviceLost
        {
            .native.setCurrentContext(first[])
            if .deviceResetStatus() == GL_NO_ERROR do
                return false

            // Retire everything at once, so nothing of the lost device is drawn or released
            // while the replacement is not there yet.
            .deviceLost = true
            .generation = .generation.next()
            .forgetDeviceResources()
        }

        .nativeContext = try .native.replaceLostContext(.contexts.toSlice(), .nativeContext)
        .deviceLost    = false
        .native.setCurrentContext(first[])
        .initImpl()
        .deviceResets += 1
        return true
    }

    // Returns what the context reports about a device reset, `GL_NO_ERROR` when nothing happened.
    private mtd deviceResetStatus()->GLenum
    {
        switch .resetQuery
        {
        case ResetQueryCore: return glGetGraphicsResetStatus()
        case ResetQueryArb:  return glGetGraphicsResetStatusARB()
        }

        return GL_NO_ERROR
    }

    // Forgets every object of a lost context without handing it back.
    //
    // Their names died with the context, and the replacement may give the same names to new
    // objects: releasing one now would destroy someone else's resource.
    private mtd forgetDeviceResources()
    {
        // Glyph atlases keep their pixels, so each page is uploaded again, whole, on next use.
        for it in .fonts.glyphCaches
        {
            let cache = unwrap it
            for &atlas in cache.atlases
            {
                atlas.texture.clear()
                atlas.markDirty(0, 0, atlas.width / atlas.bytesPerPixel, atlas.height)
            }

            cache.dirty = cache.atlases.count != 0
        }

        // Pooled targets are this renderer's own; bound ones belong to their callers.
        for rt in .stackReleasedRT do
            Memory.delete(rt)
        .stackReleasedRT.clear()
        .stackRT.clear()
        .curRT = null

        .clipMasks.clear()
        .clipMaskIndex   = -1
        .clipMaskOn      = false
        .clipMaskWriting = false
        .stackClipMaskOn.clear()

        .chromaPlanes.clear()
        .gradientTextureCapacity = 0
        .curShader               = null
        .planarPrevShader        = null
        .advancedBarrierActive   = false
    }

    // Releases queued and currently bound render-target descriptors, and the glyph atlases.
    mtd opDrop()
    {
        Swag.assert(.contextCount == 0, "renderer contexts must be deleted before the renderer")
        .releaseFontTextures()

        for rt in .stackReleasedRT do
            Memory.delete(rt)
        for rt in .stackRT do
            Memory.delete(rt)
        Memory.delete(.curRT)
    }

    // Deletes the GPU textures of every glyph atlas of this renderer.
    //
    // The atlases themselves are plain CPU pixels and go away with the cache; only the texture
    // names belong to the graphics context and have to be handed back to it here.
    internal mtd releaseFontTextures()
    {
        for it in .fonts.glyphCaches
        {
            let cache = unwrap it
            for &atlas in cache.atlases where atlas.texture.handle != InvalidTextureHandle
            {
                var id: GLuint = cast(atlas.texture.handle)
                glDeleteTextures(1, &id)
                atlas.texture.clear()
            }
        }
    }

    // Makes `rc` current and starts a frame.
    internal mtd beginImpl(rc: RenderContext)
    {
        .setCurrentContextImpl(rc)
    }

    // Finishes and presents the current frame.
    //
    // Do not force GPU completion here: a swap is ordered after the submitted drawing.
    // The native present can still block on driver backpressure or display synchronization;
    // callers presenting on the UI thread cannot process input during that wait.
    internal mtd endImpl()
    {
        // Keep hot scratch images, but retire those unused by this frame (for example,
        // the full-window backdrop targets after the lens closes).
        for index in reversed(.stackReleasedRT.count)
        {
            let target = unwrap .stackReleasedRT[index]
            if not target.poolUsed
            {
                .stackReleasedRT.removeAt(index)
                .deleteRenderTargetImpl(target)
                Memory.delete(target)
            }
            else
            {
                target.poolUsed = false
            }
        }

        glFlush()
        .native.swapBuffers(oglContext(.curRC)[])
    }

    // Makes `rc` the current rendering context.
    internal mtd setCurrentContextImpl(rc: RenderContext)
    {
        // Selecting a drawable makes it the target everything reports and draws against
        // until something binds another one, and starts it from the identity transform.
        // This is what the CPU backend has always done, and starting a frame is nothing
        // more: a submission recorded before the first frame would otherwise find a
        // zero-sized target and a zero transform, and draw nothing at all.
        .curRC = rc
        .native.setCurrentContext(oglContext(rc)[])
        .resetTransformImpl()
    }

    // Clears the current render buffers.
    internal mtd clearImpl()
    {
        glClearStencil(0)
        glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE)
        glClearColor(0, 0, 0, 0)
        glClear(GL_COLOR_BUFFER_BIT | GL_STENCIL_BUFFER_BIT)
    }

    // Returns the active render-target size in pixels.
    internal mtd targetSizeImpl()->{ width, height: s32 }
    {
        if .curRT do
            return {width: .curRT.colorBuffer.width, height: .curRT.colorBuffer.height}
        return {width: .curRC.width, height: .curRC.height}
    }

    // Restricts following writes to a surface-space rectangle.
    internal mtd setScissorRectImpl(rect: Math.Rectangle)
    {
        .applyScissor(rect)
    }

    // Disables the surface-space scissor rectangle.
    internal mtd resetScissorRectImpl()
    {
        .clearScissor()
    }

    // Restricts drawing to `rect`, in device pixels from the top left of the bound target.
    //
    // Every scissor change goes through here so the mirror the overlap-safe path narrows from
    // says what OpenGL is actually clipping to.
    private mtd applyScissor(rect: Math.Rectangle)
    {
        // Empty rectangles clip every pixel. OpenGL rejects negative extents instead of treating
        // them as empty, leaving an error for an unrelated operation in the next submission.
        let scissor = rect.width <= 0 or rect.height <= 0 ? Math.Rectangle{} : rect
        .scissorBox = scissor
        .scissorOn  = true
        let {width: _, height: h} = .targetSizeImpl()
        glEnable(GL_SCISSOR_TEST)
        glScissor(cast(GLint, scissor.x),
                  cast(GLint, (cast(f32, h) - scissor.y - scissor.height)),
                  cast(GLint, scissor.width),
                  cast(GLint, scissor.height))
    }

    // Lets drawing reach the whole bound target again.
    private mtd clearScissor()
    {
        .scissorOn = false
        glDisable(GL_SCISSOR_TEST)
    }

    // Returns the whole bound target, in device pixels from its top left.
    private mtd targetRect()->Math.Rectangle
    {
        let {width: w, height: h} = .targetSizeImpl()
        return Math.Rectangle{0, 0, cast(f32, w), cast(f32, h)}
    }

    // Sets the destination alpha to one where a batch bounded by `bbMin`/`bbMax` can reach.
    //
    // The clear is confined to the batch the way the overlap-safe scratch clear is, so a page of
    // blended marks costs their own area rather than the whole clip once per mark.
    private mtd makeBackdropOpaque(bbMin, bbMax: Math.Vector2)
    {
        let savedOn  = .scissorOn
        let savedBox = .scissorBox
        let narrowed = .narrowScissorToBatch(bbMin, bbMax)

        .prepareFramebufferTouch()
        glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_TRUE)
        glClearColor(0, 0, 0, 1)
        glClear(GL_COLOR_BUFFER_BIT)
        .setColorMask(.colorMask)

        if narrowed
        {
            if savedOn do
                .applyScissor(savedBox)
            else do
                .clearScissor()
        }
    }

    // Adds one overlap-safe batch to the scratch-clear counters.
    private mtd countScratchClear(bounded: Math.Rectangle, unbounded: Math.Rectangle)
    {
        .scratchClearedPixels += cast(u64, Math.max(bounded.width * bounded.height, 0.0'f32))
        .scratchFullPixels    += cast(u64, Math.max(unbounded.width * unbounded.height, 0.0'f32))
    }

    // Narrows the scissor to what a batch bounded by `bbMin`/`bbMax` in vertex space can reach.
    //
    // Reports whether it changed anything, so a caller that has to put the previous scissor back
    // knows whether it must. A batch whose bounds are empty — one that recorded no vertex — or
    // that reaches outside the target on every side is left alone: there is nothing to gain, and
    // an inverted rectangle would clip away geometry that must still be drawn.
    private mtd narrowScissorToBatch(bbMin, bbMax: Math.Vector2)->bool
    {
        if bbMin.x > bbMax.x or bbMin.y > bbMax.y do
            return false

        var box = .deviceTransform.transformBounds(Math.Rectangle{bbMin.x, bbMin.y, bbMax.x - bbMin.x, bbMax.y - bbMin.y})

        // Grow to whole pixels, which is a superset of the pixels the batch can shade: a fragment
        // is lit from its centre, and every centre inside the bound falls in this range. It is the
        // rounding [[Pixel.RenderCpu.triangleRangeBounds]] uses, so both backends narrow to the
        // same region and leave the same alpha behind.
        let x0 = Math.floor(box.x)
        let y0 = Math.floor(box.y)
        let x1 = Math.ceil(box.right())
        let y1 = Math.ceil(box.bottom())

        let {width: w, height: h} = .targetSizeImpl()
        var clip = Math.Rectangle{0, 0, cast(f32, w), cast(f32, h)}
        if .scissorOn do
            clip = .scissorBox

        let nx0 = Math.max(x0, clip.x)
        let ny0 = Math.max(y0, clip.y)
        let nx1 = Math.min(x1, clip.right())
        let ny1 = Math.min(y1, clip.bottom())

        // Nothing of the batch survives the clip: keep the scissor as it is and let the two draw
        // passes produce no fragment, rather than installing an empty rectangle the clear would
        // read as the whole target on a backend that normalizes it.
        if nx1 <= nx0 or ny1 <= ny0 do
            return false

        // Already at least as tight as what the bounds give: changing it would only cost two
        // calls per batch.
        if nx0 <= clip.x and ny0 <= clip.y and nx1 >= clip.right() and ny1 >= clip.bottom() do
            return false

        .applyScissor(Math.Rectangle{nx0, ny0, nx1 - nx0, ny1 - ny0})
        return true
    }

    // Initializes OpenGL extensions, built-in shaders, buffers, and hatch textures.
    //
    // Call this once after a native context is current.
    internal mtd initImpl()
    {
        glInitExtensions()
        .applyPresentPolicy()

        // Only a context created to report resets is asked about them, and only through an entry
        // point it publishes: the extension wrappers end the process on a missing one.
        .resetQuery = ResetQueryNone
        if .native.notifiesReset
        {
            var major, minor: GLint
            glGetIntegerv(GL_MAJOR_VERSION, &major)
            glGetIntegerv(GL_MINOR_VERSION, &minor)
            if major > 4 or (major == 4 and minor >= 5) do
                .resetQuery = ResetQueryCore
            elif hasExtension("GL_ARB_robustness") do
                .resetQuery = ResetQueryArb
        }

        if hasExtension("GL_KHR_blend_equation_advanced_coherent")
        {
            .advancedBlending = AdvancedBlendingKhrCoherent
        }
        elif hasExtension("GL_NV_blend_equation_advanced_coherent")
        {
            .advancedBlending = AdvancedBlendingNvCoherent
            glBlendParameteriNV(GL_BLEND_PREMULTIPLIED_SRC_NV, cast(GLint, GL_FALSE))
        }
        elif hasExtension("GL_KHR_blend_equation_advanced")
        {
            .advancedBlending = AdvancedBlendingKhrBarrier
        }
        elif hasExtension("GL_NV_blend_equation_advanced")
        {
            .advancedBlending = AdvancedBlendingNvBarrier
            glBlendParameteriNV(GL_BLEND_PREMULTIPLIED_SRC_NV, cast(GLint, GL_FALSE))
        }

        .createShaders()

        glGenBuffers(1, &.vertexbuffer)
        let vertexBufferError = glGetError()
        if not .vertexbuffer or vertexBufferError != GL_NO_ERROR do
            Swag.panic("OpenGL cannot allocate the vertex buffer", #curlocation)
        glBindBuffer(GL_ARRAY_BUFFER, .vertexbuffer)

        // Vertex buffer layout
        var offset: const [*] u8? = null
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, #sizeof(VertexLayout), offset)
        offset += #sizeof(Vector2)
        glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, #sizeof(VertexLayout), offset)
        offset += #sizeof(Vector2)
        glVertexAttribPointer(2, 4, GL_UNSIGNED_BYTE, GL_TRUE, #sizeof(VertexLayout), offset)
        offset += #sizeof(u32)

        // antialiasing coverage
        glVertexAttribPointer(3, 1, GL_FLOAT, GL_FALSE, #sizeof(VertexLayout), offset)

        // Generate predefined textures
        .whiteTexture = generateTexture([1], 1, 1)
        .clearTexture = generateTexture([0], 1, 1)
        glGenTextures(1, &.gradientTexture)
        let gradientNameError = glGetError()
        if not .gradientTexture or gradientNameError != GL_NO_ERROR do
            Swag.panic("OpenGL cannot allocate the gradient texture", #curlocation)
        glActiveTexture(GL_TEXTURE2)
        glBindTexture(GL_TEXTURE_2D, .gradientTexture)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
        glActiveTexture(GL_TEXTURE0)
        using HatchStyle
        .hatchTextures[Dot]                   = generateTexture(Hatch.Dot, 8, 8)
        .hatchTextures[Horizontal]            = generateTexture(Hatch.Horizontal, 8, 8)
        .hatchTextures[HorizontalLight]       = generateTexture(Hatch.HorizontalLight, 8, 8)
        .hatchTextures[HorizontalNarrow]      = generateTexture(Hatch.HorizontalNarrow, 8, 8)
        .hatchTextures[Vertical]              = generateTexture(Hatch.Vertical, 8, 8)
        .hatchTextures[VerticalLight]         = generateTexture(Hatch.VerticalLight, 8, 8)
        .hatchTextures[VerticalNarrow]        = generateTexture(Hatch.VerticalNarrow, 8, 8)
        .hatchTextures[SolidDiamond]          = generateTexture(Hatch.SolidDiamond, 8, 8)
        .hatchTextures[OutlinedDiamond]       = generateTexture(Hatch.OutlinedDiamond, 8, 8)
        .hatchTextures[HorizontalDark]        = generateTexture(Hatch.HorizontalDark, 8, 8)
        .hatchTextures[VerticalDark]          = generateTexture(Hatch.VerticalDark, 8, 8)
        .hatchTextures[Grid]                  = generateTexture(Hatch.Grid, 8, 8)
        .hatchTextures[GridLarge]             = generateTexture(Hatch.GridLarge, 8, 8)
        .hatchTextures[GridDotted]            = generateTexture(Hatch.GridDotted, 8, 8)
        .hatchTextures[Cross]                 = generateTexture(Hatch.Cross, 8, 8)
        .hatchTextures[CrossLarge]            = generateTexture(Hatch.CrossLarge, 8, 8)
        .hatchTextures[Percent5]              = generateTexture(Hatch.Percent5, 8, 8)
        .hatchTextures[Percent10]             = generateTexture(Hatch.Percent10, 8, 8)
        .hatchTextures[Percent20]             = generateTexture(Hatch.Percent20, 8, 8)
        .hatchTextures[Percent25]             = generateTexture(Hatch.Percent25, 8, 8)
        .hatchTextures[Percent30]             = generateTexture(Hatch.Percent30, 8, 8)
        .hatchTextures[Percent40]             = generateTexture(Hatch.Percent40, 8, 8)
        .hatchTextures[Percent50]             = generateTexture(Hatch.Percent50, 8, 8)
        .hatchTextures[Percent60]             = generateTexture(Hatch.Percent60, 8, 8)
        .hatchTextures[Percent70]             = generateTexture(Hatch.Percent70, 8, 8)
        .hatchTextures[Percent75]             = generateTexture(Hatch.Percent75, 8, 8)
        .hatchTextures[Percent80]             = generateTexture(Hatch.Percent80, 8, 8)
        .hatchTextures[Percent90]             = generateTexture(Hatch.Percent90, 8, 8)
        .hatchTextures[CheckBoard]            = generateTexture(Hatch.CheckBoard, 8, 8)
        .hatchTextures[CheckBoardLarge]       = generateTexture(Hatch.CheckBoardLarge, 8, 8)
        .hatchTextures[Weave]                 = generateTexture(Hatch.Weave, 8, 8)
        .hatchTextures[DiagonalForward]       = generateTexture(Hatch.DiagonalForward, 8, 8)
        .hatchTextures[DiagonalForwardLight]  = generateTexture(Hatch.DiagonalForwardLight, 8, 8)
        .hatchTextures[DiagonalBackward]      = generateTexture(Hatch.DiagonalBackward, 8, 8)
        .hatchTextures[DiagonalBackwardLight] = generateTexture(Hatch.DiagonalBackwardLight, 8, 8)
        .hatchTextures[DiagonalCross]         = generateTexture(Hatch.DiagonalCross, 8, 8)
    }

    // Binds an off-screen target for following direct operations or painter submission.
    internal mtd bindRenderTargetImpl(rt: *RenderTarget, vp: *Math.Rectangle? = null)
    {
        Swag.assert(rt != null)
        if not rt.colorBuffer.isValid() do
            return
        if .curRT do
            .stackRT.add(.curRT)
        .curRT = rt
        .curRT.paintAlpha = false

        glBindFramebuffer(GL_FRAMEBUFFER, cast(GLuint, .curRT.handle))
        if vp do
            glViewport(cast(vp.x), cast(vp.y), cast(vp.width), cast(vp.height))
        else do
            glViewport(0, 0, .curRT.colorBuffer.width, .curRT.colorBuffer.height)
    }

    // Reads a rectangle of any render target back as an image.
    //
    // Unlike [[RenderOgl.unbindRenderTargetToImage]] this does not touch the target stack, so a
    // target filled by a painter command stream, which binds and unbinds it as it runs, can
    // still be read afterwards.
    internal mtd readRenderTargetImpl(rt: const *RenderTarget, x, y, w, h: s32)->Image
    {
        if not rt.colorBuffer.isValid() do
            return {}
        var previousRead: GLint
        glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &previousRead)
        defer glBindFramebuffer(GL_READ_FRAMEBUFFER, cast(GLuint, previousRead))

        glBindFramebuffer(GL_READ_FRAMEBUFFER, cast(GLuint, rt.handle))
        glReadBuffer(GL_COLOR_ATTACHMENT0)
        return .readBoundTargetToImage(rt, x, y, w, h)
    }

    // Reads the active target into a new image, then restores the previous target.
    internal mtd unbindRenderTargetToImageImpl(x, y, w, h: s32)->Image
    {
        let curRT = unwrap .curRT

        // Name the framebuffer to read from rather than trusting whatever the command stream
        // left bound. A painter binds and unbinds targets as it runs, and reading the ambient
        // binding takes the DEFAULT framebuffer instead - a blank buffer, or a foreign window -
        // which is the whole-image mismatch the parity tests were retrying around.
        glBindFramebuffer(GL_READ_FRAMEBUFFER, cast(GLuint, curRT.handle))
        glReadBuffer(GL_COLOR_ATTACHMENT0)
        let result = .readBoundTargetToImage(curRT, x, y, w, h)
        .unbindRenderTargetImpl()
        return result
    }

    // Reads the selected framebuffer with a CPU destination regardless of ambient pack state.
    private mtd readBoundTargetToImage(rt: const *RenderTarget, x, y, w, h: s32)->Image
    {
        var result: #returntype = Image.create(w, h, .BGRA8)
        var buffer, alignment, rowLength, skipRows, skipPixels: GLint
        glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &buffer)
        glGetIntegerv(GL_PACK_ALIGNMENT, &alignment)
        glGetIntegerv(GL_PACK_ROW_LENGTH, &rowLength)
        glGetIntegerv(GL_PACK_SKIP_ROWS, &skipRows)
        glGetIntegerv(GL_PACK_SKIP_PIXELS, &skipPixels)
        defer
        {
            glBindBuffer(GL_PIXEL_PACK_BUFFER, cast(GLuint, buffer))
            glPixelStorei(GL_PACK_ALIGNMENT, alignment)
            glPixelStorei(GL_PACK_ROW_LENGTH, rowLength)
            glPixelStorei(GL_PACK_SKIP_ROWS, skipRows)
            glPixelStorei(GL_PACK_SKIP_PIXELS, skipPixels)
        }

        glBindBuffer(GL_PIXEL_PACK_BUFFER, 0)
        glPixelStorei(GL_PACK_ALIGNMENT, 4)
        glPixelStorei(GL_PACK_ROW_LENGTH, 0)
        glPixelStorei(GL_PACK_SKIP_ROWS, 0)
        glPixelStorei(GL_PACK_SKIP_PIXELS, 0)
        glReadPixels(x, rt.colorBuffer.height - h - y, w, h, GL_BGRA, GL_UNSIGNED_BYTE, cast([*] u8, result.pixels.storage()))
        if glGetError() != GL_NO_ERROR do
            return {}
        return result
    }

    // Restores the previous render target, or the frame buffer.
    internal mtd unbindRenderTargetImpl()
    {
        if .stackRT.count
        {
            .curRT = .stackRT.popBack()
            let curRT = unwrap .curRT
            glBindFramebuffer(GL_FRAMEBUFFER, cast(GLuint, curRT.handle))
            glViewport(0, 0, curRT.colorBuffer.width, curRT.colorBuffer.height)
        }
        else
        {
            .curRT = null
            glBindFramebuffer(GL_FRAMEBUFFER, 0)
            glViewport(0, 0, .curRC.width, .curRC.height)
        }
    }

    // Creates an off-screen target owned by this renderer.
    internal mtd createRenderTargetImpl(w, h: s32)->RenderTarget
    {
        Swag.assert(w > 0 and h > 0)
        var previousRead, previousDraw: GLint
        var previousTexture, previousUnpackBuffer: GLint
        glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &previousRead)
        glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &previousDraw)
        glGetIntegerv(GL_TEXTURE_BINDING_2D, &previousTexture)
        glGetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING, &previousUnpackBuffer)
        defer
        {
            glBindFramebuffer(GL_READ_FRAMEBUFFER, cast(GLuint, previousRead))
            glBindFramebuffer(GL_DRAW_FRAMEBUFFER, cast(GLuint, previousDraw))
            glBindTexture(GL_TEXTURE_2D, cast(GLuint, previousTexture))
            glBindBuffer(GL_PIXEL_UNPACK_BUFFER, cast(GLuint, previousUnpackBuffer))
        }

        var colorID: GLuint
        glGenTextures(1, &colorID)
        let textureNameError = glGetError()
        if not colorID or textureNameError != GL_NO_ERROR
        {
            if colorID do
                glDeleteTextures(1, &colorID)
            return {}
        }

        glBindTexture(GL_TEXTURE_2D, colorID)
        glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0)
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, null)
        if glGetError() != GL_NO_ERROR
        {
            glDeleteTextures(1, &colorID)
            return {}
        }

        var fbo: GLuint
        glGenFramebuffers(1, &fbo)
        let framebufferNameError = glGetError()
        if not fbo or framebufferNameError != GL_NO_ERROR
        {
            if fbo do
                glDeleteFramebuffers(1, &fbo)
            glDeleteTextures(1, &colorID)
            return {}
        }

        glBindFramebuffer(GL_FRAMEBUFFER, fbo)
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, colorID, 0)
        let status = glCheckFramebufferStatus(GL_FRAMEBUFFER)
        let attachmentError = glGetError()
        if status != GL_FRAMEBUFFER_COMPLETE or attachmentError != GL_NO_ERROR
        {
            glDeleteFramebuffers(1, &fbo)
            glDeleteTextures(1, &colorID)
            return {}
        }

        // Clipping uses coverage textures; no draw enables hardware depth or stencil tests.
        var result: #returntype
        result.attach(cast(RenderTargetHandle, fbo), cast(TextureHandle, colorID), .RGBA8, w, h, .generation)
        return result
    }

    // Releases an off-screen target and invalidates its descriptor.
    internal mtd deleteRenderTargetImpl(rt: *RenderTarget)
    {
        if rt.handle == InvalidRenderTargetHandle do
            return

        // A target of a lost device went with it; its names may already belong to new resources.
        if not rt.colorBuffer.isValid()
        {
            rt.clear()
            return
        }

        var cb: GLuint = cast(rt.colorBuffer.handle)
        glDeleteTextures(1, &cb)

        var ds: GLuint = cast(rt.depthStencil)
        glDeleteRenderbuffers(1, &ds)

        var fb: GLuint = cast(rt.handle)
        glDeleteFramebuffers(1, &fb)

        rt.clear()
    }

    // Creates one single-channel plane of a planar picture.
    private mtd createPlaneTexture(width, height: s32)->GLuint
    {
        var previousTexture, previousUnpackBuffer, previousAlignment: GLint
        glGetIntegerv(GL_TEXTURE_BINDING_2D, &previousTexture)
        glGetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING, &previousUnpackBuffer)
        glGetIntegerv(GL_UNPACK_ALIGNMENT, &previousAlignment)
        defer
        {
            glBindTexture(GL_TEXTURE_2D, cast(GLuint, previousTexture))
            glBindBuffer(GL_PIXEL_UNPACK_BUFFER, cast(GLuint, previousUnpackBuffer))
            glPixelStorei(GL_UNPACK_ALIGNMENT, previousAlignment)
        }

        var textureID: GLuint
        glGenTextures(1, &textureID)
        let nameError = glGetError()
        if not textureID or nameError != GL_NO_ERROR
        {
            if textureID do
                glDeleteTextures(1, &textureID)
            return 0
        }

        glBindTexture(GL_TEXTURE_2D, textureID)
        glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0)
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
        glTexImage2D(GL_TEXTURE_2D, 0, GL_R8, cast(GLsizei, width), cast(GLsizei, height), 0, GL_RED, GL_UNSIGNED_BYTE, null)
        if glGetError() != GL_NO_ERROR
        {
            glDeleteTextures(1, &textureID)
            return 0
        }

        return textureID
    }

    // Uploads one plane, letting the driver skip whatever padding the source rows carry.
    private mtd uploadPlane(handle: GLuint, pixels: const [*] u8, stride: u64, width, height: s32)->bool
    {
        var previousTexture, previousBuffer, previousAlignment, previousRowLength, previousSkipRows, previousSkipPixels: GLint
        glGetIntegerv(GL_TEXTURE_BINDING_2D, &previousTexture)
        glGetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING, &previousBuffer)
        glGetIntegerv(GL_UNPACK_ALIGNMENT, &previousAlignment)
        glGetIntegerv(GL_UNPACK_ROW_LENGTH, &previousRowLength)
        glGetIntegerv(GL_UNPACK_SKIP_ROWS, &previousSkipRows)
        glGetIntegerv(GL_UNPACK_SKIP_PIXELS, &previousSkipPixels)
        defer
        {
            glBindTexture(GL_TEXTURE_2D, cast(GLuint, previousTexture))
            glBindBuffer(GL_PIXEL_UNPACK_BUFFER, cast(GLuint, previousBuffer))
            glPixelStorei(GL_UNPACK_ALIGNMENT, previousAlignment)
            glPixelStorei(GL_UNPACK_ROW_LENGTH, previousRowLength)
            glPixelStorei(GL_UNPACK_SKIP_ROWS, previousSkipRows)
            glPixelStorei(GL_UNPACK_SKIP_PIXELS, previousSkipPixels)
        }

        glBindTexture(GL_TEXTURE_2D, handle)
        glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0)
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
        glPixelStorei(GL_UNPACK_ROW_LENGTH, cast(GLint, stride))
        glPixelStorei(GL_UNPACK_SKIP_ROWS, 0)
        glPixelStorei(GL_UNPACK_SKIP_PIXELS, 0)
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, cast(GLsizei, width), cast(GLsizei, height), GL_RED, GL_UNSIGNED_BYTE, pixels)
        return glGetError() == GL_NO_ERROR
    }

    // Registers a planar picture as three single-channel planes the shader converts.
    internal mtd addImageImpl(view: const *YuvPlanarView)->Texture
    {
        if view.width <= 0 or view.height <= 0
        {
            return {}
        }

        let luma = .createPlaneTexture(view.width, view.height)
        if not luma do
            return {}

        var planes: ChromaPlanes
        planes.chromaB = .createPlaneTexture(view.chromaWidth(), view.chromaHeight())
        planes.chromaR = .createPlaneTexture(view.chromaWidth(), view.chromaHeight())
        if not planes.chromaB or not planes.chromaR
        {
            var lumaID = luma
            glDeleteTextures(1, &lumaID)
            if planes.chromaB do
                glDeleteTextures(1, &planes.chromaB)
            if planes.chromaR do
                glDeleteTextures(1, &planes.chromaR)
            return {}
        }

        var result: #returntype
        result.attach(cast(TextureHandle, luma), view.chromaShift == 0 ? .Yuv444 : .Yuv420, view.width, view.height, .generation)
        .chromaPlanes.add(result.handle, planes)
        if not .updatePlanarImpl(result, view)
        {
            .removeTextureImpl(&result)
            return {}
        }

        return result
    }

    // Replaces the planar picture held by a texture, converting nothing.
    internal mtd updatePlanarImpl(texture: Texture, view: const *YuvPlanarView)->bool
    {
        if not texture.isValid() or view.width != texture.width or view.height != texture.height do
            return false
        if (texture.pixelFormat == .Yuv420 and view.chromaShift != 1) or
           (texture.pixelFormat == .Yuv444 and view.chromaShift != 0) or
           (texture.pixelFormat != .Yuv420 and texture.pixelFormat != .Yuv444) do
            return false
        let planes = .chromaPlanes.tryFind(texture.handle)
        if not planes do
            return false

        if not .uploadPlane(cast(GLuint, texture.handle), view.luma, view.lumaStride, texture.width, texture.height) or
           not .uploadPlane(planes.value.chromaB, view.chromaB, view.chromaStride, view.chromaWidth(), view.chromaHeight()) or
           not .uploadPlane(planes.value.chromaR, view.chromaR, view.chromaStride, view.chromaWidth(), view.chromaHeight()) do
            return false
        planes.value.factors = view.conversionFactors()
        return true
    }

    // Loads an image file into a texture owned by this renderer.
    internal mtd addImageImpl(fullName: string)->Texture fail
    {
        let image = try Image.load(fullName)
        return .addImageImpl(&image)
    }

    // Copies an image into a texture owned by this renderer.
    internal mtd addImageImpl(image: const *Image)->Texture
    {
        if not image.isValid()
        {
            return {}
        }

        // A planar picture has no single upload format; it goes through the plane path.
        if image.pixelFormat == .Yuv420 or image.pixelFormat == .Yuv444
        {
            Swag.assert(false, "a planar picture is added through its view")
            return {}
        }

        var straight: Image
        var source = image
        if image.alphaMode == .Premultiplied
        {
            straight = image.convertedAlphaTo(.Straight)
            source   = &straight
        }

        let fmt       = pixelFormatToNative(source.pixelFormat)
        let tinternal = pixelFormatToInternal(source.pixelFormat)
        let dataType  = pixelFormatToNativeType(source.pixelFormat)
        var previousTexture, previousBuffer, previousAlignment, previousRowLength, previousSkipRows, previousSkipPixels: GLint
        glGetIntegerv(GL_TEXTURE_BINDING_2D, &previousTexture)
        glGetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING, &previousBuffer)
        glGetIntegerv(GL_UNPACK_ALIGNMENT, &previousAlignment)
        glGetIntegerv(GL_UNPACK_ROW_LENGTH, &previousRowLength)
        glGetIntegerv(GL_UNPACK_SKIP_ROWS, &previousSkipRows)
        glGetIntegerv(GL_UNPACK_SKIP_PIXELS, &previousSkipPixels)
        defer
        {
            glBindTexture(GL_TEXTURE_2D, cast(GLuint, previousTexture))
            glBindBuffer(GL_PIXEL_UNPACK_BUFFER, cast(GLuint, previousBuffer))
            glPixelStorei(GL_UNPACK_ALIGNMENT, previousAlignment)
            glPixelStorei(GL_UNPACK_ROW_LENGTH, previousRowLength)
            glPixelStorei(GL_UNPACK_SKIP_ROWS, previousSkipRows)
            glPixelStorei(GL_UNPACK_SKIP_PIXELS, previousSkipPixels)
        }

        var textureID: GLuint
        glGenTextures(1, &textureID)
        let nameError = glGetError()
        if not textureID or nameError != GL_NO_ERROR
        {
            if textureID do
                glDeleteTextures(1, &textureID)
            return {}
        }

        glBindTexture(GL_TEXTURE_2D, textureID)
        glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0)
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
        glPixelStorei(GL_UNPACK_ROW_LENGTH, 0)
        glPixelStorei(GL_UNPACK_SKIP_ROWS, 0)
        glPixelStorei(GL_UNPACK_SKIP_PIXELS, 0)
        glTexImage2D(GL_TEXTURE_2D, 0, tinternal, cast(s32, source.width), cast(s32, source.height), 0, fmt, dataType, cast([*] u8, source.pixels.storage()))
        if glGetError() != GL_NO_ERROR
        {
            glDeleteTextures(1, &textureID)
            return {}
        }

        var result: #returntype
        result.attach(cast(TextureHandle, textureID), source.pixelFormat, source.width, source.height, .generation)
        return result
    }

    // Maps a Pixel byte layout to its OpenGL upload/readback format.
    internal func pixelFormatToNative(pixelFormat: PixelFormat)->GLenum
    {
        switch #complete pixelFormat
        {
        case .Yuv420, .Yuv444:
            return GL_RED     // One plane at a time.

        case .Gray8, .Gray16, .GrayF16, .GrayF32:
            return GL_LUMINANCE

        case .GrayAlpha8, .GrayAlpha16, .GrayAlphaF16, .GrayAlphaF32:
            return GL_LUMINANCE_ALPHA

        case .BGR8:
            return GL_BGR

        case .BGRA8:
            return GL_BGRA

        case .RGB8, .RGB16, .RGBF16, .RGBF32:
            return GL_RGB

        case .RGBA8, .RGBA16, .RGBAF16, .RGBAF32:
            return GL_RGBA
        }
    }

    // Maps a Pixel sample representation to its OpenGL transfer type.
    internal func pixelFormatToNativeType(pixelFormat: PixelFormat)->GLenum
    {
        switch pixelFormat
        {
        case .Gray16, .GrayAlpha16, .RGB16, .RGBA16:     return GL_UNSIGNED_SHORT
        case .GrayF16, .GrayAlphaF16, .RGBF16, .RGBAF16: return GL_HALF_FLOAT
        case .GrayF32, .GrayAlphaF32, .RGBF32, .RGBAF32: return GL_FLOAT
        default: return GL_UNSIGNED_BYTE
        }
    }

    // Selects texture storage that retains the source sample precision.
    internal func pixelFormatToInternal(pixelFormat: PixelFormat)->GLenum
    {
        switch pixelFormat
        {
        case .Gray8:         return GL_LUMINANCE8
        case .GrayAlpha8:    return GL_LUMINANCE8_ALPHA8
        case .Gray16:        return GL_LUMINANCE16
        case .GrayAlpha16:   return GL_LUMINANCE16_ALPHA16
        case .GrayF16:       return GL_LUMINANCE16F_EXT
        case .GrayAlphaF16:  return GL_LUMINANCE_ALPHA16F_EXT
        case .GrayF32:       return GL_LUMINANCE32F_EXT
        case .GrayAlphaF32:  return GL_LUMINANCE_ALPHA32F_EXT
        case .RGB16:         return GL_RGB16
        case .RGBA16:        return GL_RGBA16
        case .RGBF16:        return GL_RGB16F
        case .RGBAF16:       return GL_RGBA16F
        case .RGBF32:        return GL_RGB32F
        case .RGBAF32:       return GL_RGBA32F
        case .BGRA8, .RGBA8: return GL_RGBA8
        default:             return GL_RGB8
        }
    }

    // Replaces all bytes of a texture owned by this renderer.
    internal mtd updateTextureImpl(texture: Texture, pixels: const *u8)->bool
    {
        if not texture.isValid() do
            return false
        let fmt       = pixelFormatToNative(texture.pixelFormat)
        let textureID = cast(GLuint, texture.handle)
        var previousTexture, previousBuffer, previousAlignment, previousRowLength, previousSkipRows, previousSkipPixels: GLint
        glGetIntegerv(GL_TEXTURE_BINDING_2D, &previousTexture)
        glGetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING, &previousBuffer)
        glGetIntegerv(GL_UNPACK_ALIGNMENT, &previousAlignment)
        glGetIntegerv(GL_UNPACK_ROW_LENGTH, &previousRowLength)
        glGetIntegerv(GL_UNPACK_SKIP_ROWS, &previousSkipRows)
        glGetIntegerv(GL_UNPACK_SKIP_PIXELS, &previousSkipPixels)
        defer
        {
            glBindTexture(GL_TEXTURE_2D, cast(GLuint, previousTexture))
            glBindBuffer(GL_PIXEL_UNPACK_BUFFER, cast(GLuint, previousBuffer))
            glPixelStorei(GL_UNPACK_ALIGNMENT, previousAlignment)
            glPixelStorei(GL_UNPACK_ROW_LENGTH, previousRowLength)
            glPixelStorei(GL_UNPACK_SKIP_ROWS, previousSkipRows)
            glPixelStorei(GL_UNPACK_SKIP_PIXELS, previousSkipPixels)
        }

        glBindTexture(GL_TEXTURE_2D, textureID)
        glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0)
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
        glPixelStorei(GL_UNPACK_ROW_LENGTH, 0)
        glPixelStorei(GL_UNPACK_SKIP_ROWS, 0)
        glPixelStorei(GL_UNPACK_SKIP_PIXELS, 0)
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, cast(s32, texture.width), cast(s32, texture.height), fmt, pixelFormatToNativeType(texture.pixelFormat), pixels)
        return glGetError() == GL_NO_ERROR
    }

    // Reads a texture into owned CPU memory in `pixelFormat`.
    internal mtd readTexturePixelsImpl(texture: Texture, pixelFormat: PixelFormat)->Array'u8
    {
        var result: #returntype
        if not texture.isValid() do
            return result
        Swag.assert(pixelFormat.isPacked(), "texture readback requires a packed format")
        var previousTexture, previousBuffer, alignment, rowLength, skipRows, skipPixels: GLint
        glGetIntegerv(GL_TEXTURE_BINDING_2D, &previousTexture)
        glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &previousBuffer)
        glGetIntegerv(GL_PACK_ALIGNMENT, &alignment)
        glGetIntegerv(GL_PACK_ROW_LENGTH, &rowLength)
        glGetIntegerv(GL_PACK_SKIP_ROWS, &skipRows)
        glGetIntegerv(GL_PACK_SKIP_PIXELS, &skipPixels)
        defer
        {
            glBindTexture(GL_TEXTURE_2D, cast(GLuint, previousTexture))
            glBindBuffer(GL_PIXEL_PACK_BUFFER, cast(GLuint, previousBuffer))
            glPixelStorei(GL_PACK_ALIGNMENT, alignment)
            glPixelStorei(GL_PACK_ROW_LENGTH, rowLength)
            glPixelStorei(GL_PACK_SKIP_ROWS, skipRows)
            glPixelStorei(GL_PACK_SKIP_PIXELS, skipPixels)
        }

        glBindTexture(GL_TEXTURE_2D, cast(texture.handle))
        glBindBuffer(GL_PIXEL_PACK_BUFFER, 0)
        glPixelStorei(GL_PACK_ALIGNMENT, 1)
        glPixelStorei(GL_PACK_ROW_LENGTH, 0)
        glPixelStorei(GL_PACK_SKIP_ROWS, 0)
        glPixelStorei(GL_PACK_SKIP_PIXELS, 0)
        result.resize(cast(u64, texture.width) * cast(u64, texture.height) * pixelFormat.bitsPerPixel() / 8)
        let fmt = pixelFormatToNative(pixelFormat)
        glGetTexImage(GL_TEXTURE_2D, 0, fmt, pixelFormatToNativeType(pixelFormat), result.buffer)
        if glGetError() != GL_NO_ERROR do
            result.clear()
        return result
    }

    // Releases a texture created by `addImage` and invalidates its descriptor.
    internal mtd removeTextureImpl(texture: *Texture)
    {
        if not texture.isValid() do
            return

        let planes = .chromaPlanes.tryFind(texture.handle)
        if planes
        {
            var chromaB = planes.value.chromaB
            var chromaR = planes.value.chromaR
            glDeleteTextures(1, &chromaB)
            glDeleteTextures(1, &chromaR)
            .chromaPlanes.remove(texture.handle)
        }

        var id: GLuint = cast(texture.handle)
        glDeleteTextures(1, &id)
        texture.clear()
    }

    // Translates following painter submissions in surface pixels.
    internal mtd translateTransformImpl(x, y: f32)
    {
        let tr = Transform2.createTranslation(x, y)
        .worldTransform.multiply(tr)
    }

    // Rotates following painter submissions around the surface origin.
    internal mtd rotateTransformImpl(angle: Math.Angle)
    {
        let tr = Transform2.createRotation(angle.radians, 0, 0)
        .worldTransform.multiply(tr)
    }

    // Rotates following painter submissions around a surface-space center.
    internal mtd rotateTransformImpl(angle: Math.Angle, centerX, centerY: f32)
    {
        let tr = Transform2.createRotation(angle.radians, centerX, centerY)
        .worldTransform.multiply(tr)
    }

    // Scales following painter submissions independently on both axes.
    internal mtd scaleTransformImpl(x, y: f32)
    {
        let tr = Transform2.createScale(x, y, 0, 0)
        .worldTransform.multiply(tr)
    }

    // Scales following painter submissions uniformly.
    internal mtd scaleTransformImpl(x: f32)
    {
        let tr = Transform2.createScale(x, x, 0, 0)
        .worldTransform.multiply(tr)
    }

    // Restores the identity world transform.
    internal mtd resetTransformImpl()
    {
        .worldTransform.setIdentity()
        .modelMatrix.setIdentity()
    }

    // Uploads projection and model matrices for the current target.
    //
    // `mvp` and `mdl` are uniform locations in the active shader.
    internal mtd computeMatrices(mvp, mdl: ShaderParamHandle)
    {
        let {width, height} = .targetSizeImpl()

        // View, ortho projection
        .orthoMatrix = ortho(cast(f32, height), 0, 0, cast(f32, width), 0, 1.0)
        glUniformMatrix4fv(cast(GLint, mvp), 1, GL_FALSE, &.orthoMatrix.m[0, 0])
        glViewport(0, 0, width, height)

        // Draw matrix
        .buildModelMatrix(Transform2.Identity)
        glUniformMatrix4fv(cast(GLint, mdl), 1, GL_FALSE, &.modelMatrix.m[0, 0])
    }

    private mtd executeCommand(dc: *Painter, cmd: Pixel.Command, cmdIdx: u64) fail
    {
        switch cmd.op
        {
        case .SetBlendingMode:
            let params = &cmd.blendingMode
            .setBlendingMode(params.mode)

        case .Clear:
            let params       = &cmd.clear
            let {a, r, g, b} = params.color.toArgbF32()
            .prepareFramebufferTouch()
            glClearColor(r, g, b, a)
            glClear(GL_COLOR_BUFFER_BIT | GL_STENCIL_BUFFER_BIT)

        case .ColorMask:
            .setColorMask(cmd.colorMask)

        case .Transform:
            let params = &cmd.transform
            .buildModelMatrix(params.tr)
            let curShader = unwrap .curShader
            glUniformMatrix4fv(cast(GLint, curShader.mdl), 1, GL_FALSE, &.modelMatrix.m[0, 0])

        case .StartClippingRegion:

            // A region is coverage, so it is drawn into a mask the size of the target rather than
            // into the one-bit stencil, and it starts empty: what the previous start/end pair
            // wrote must not leak into it. The mask shares the target's projection and scissor,
            // so a fragment lands on the same device pixel in both; the scissor is lifted for the
            // reset alone, because the old region can extend past the clip in force now.
            let {width, height} = .targetSizeImpl()
            .clipMaskIndex   = try .clipMaskFor(width, height)
            .clipMaskWriting = true
            .clipMaskOn      = false
            let mask = .clipMasks[cast(u64, .clipMaskIndex)]

            // The shader still declares the mask sampler while writing coverage. Leaving the
            // destination bound there creates a texture feedback loop, even when a uniform
            // branch skips the lookup. Only EndClippingRegion exposes the finished mask again.
            glActiveTexture(GL_TEXTURE5)
            glBindTexture(GL_TEXTURE_2D, .whiteTexture)
            glActiveTexture(GL_TEXTURE0)
            glBindFramebuffer(GL_FRAMEBUFFER, mask.framebuffer)
            glViewport(0, 0, width, height)
            glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE)
            if .scissorOn do
                glDisable(GL_SCISSOR_TEST)
            glClearColor(0, 0, 0, 0)
            glClear(GL_COLOR_BUFFER_BIT)
            if .scissorOn do
                glEnable(GL_SCISSOR_TEST)
            .applyClipMaskMode(cmd.clippingRegion.mode)
            .uploadClipMaskState()

        case .SetClippingRegionMode:
            .applyClipMaskMode(cmd.clippingRegion.mode)

        case .EndClippingRegion:
            .clipMaskWriting = false
            .clipMaskOn      = true
            .rebindCurrentTarget()
            .setColorMask(.colorMask)
            .setBlendingMode(.blendingMode)
            let mask = .clipMasks[cast(u64, .clipMaskIndex)]
            glActiveTexture(GL_TEXTURE5)
            glBindTexture(GL_TEXTURE_2D, mask.texture)
            glActiveTexture(GL_TEXTURE0)
            .uploadClipMaskState()

        case .ResetClippingRegion:
            .clipMaskOn = false
            .uploadClipMaskState()

        case .SetClippingRect:
            let params = &cmd.clippingRect

            // Painter clip rectangles are logical; the scissor works in framebuffer
            // pixels. Round the scaled edges so neighbouring clips stay watertight.
            //
            // The vertical flip reads the height of the target bound right now, not the one the
            // submission started on: a stream that binds a layer part-way through keeps clipping,
            // and a layer is almost always shorter than the surface, so a stale height puts the
            // scissor entirely outside the framebuffer and drops every fragment of the layer.
            let k  = .contentScale
            let x0 = Math.round(params.rect.x * k)
            let y0 = Math.round(params.rect.y * k)
            let x1 = Math.round(params.rect.right() * k)
            let y1 = Math.round(params.rect.bottom() * k)
            .applyScissor(Math.Rectangle{x0, y0, x1 - x0, y1 - y0})

        case .ResetClippingRect:
            .clearScissor()

        case .StartNoOverlap:
            .overlapMode = true

        case .StopNoOverlap:
            .overlapMode = false
            .setBlendingMode(.blendingMode)

        case .DrawTriangles:
            let params = &cmd.drawTriangles
            if not .overlapMode
            {
                // An advanced equation weighs the backdrop by the destination alpha. When the
                // painter is not writing alpha, that plane is scratch — the window's is never
                // written at all — and a backdrop read as transparent lets the source replace it:
                // a black shadow multiplied onto a page came out as an opaque black block. The
                // stored colour is the backdrop, opaque by definition, so its alpha is set to one
                // where this batch can reach before the equation reads it.
                if .blendingMode.usesAdvancedBlending() and not .colorMask.a and not .alphaReplay do
                    .makeBackdropOpaque(params.bbMin, params.bbMax)

                if .advancedBarrierActive
                {
                    // A non-coherent pass may touch each sample only once, including through
                    // standard blending. Painter batches can contain overlapping geometry, so
                    // isolate every primitive rather than only every recorded draw command.
                    for var start = params.start; start < params.start + params.count; start += 3
                    {
                        .prepareFramebufferTouch()
                        glDrawArrays(GL_TRIANGLES, cast(GLint, start), 3)
                    }
                }
                else
                {
                    .prepareFramebufferTouch()
                    glDrawArrays(GL_TRIANGLES, cast(GLint, params.start), cast(GLsizei, params.count))
                }
            }
            else
            {
                .prepareFramebufferTouch()

                // The scratch channel only has to start from zero where this batch can write, so
                // the clear is confined to the geometry rather than to the whole clipping
                // rectangle. Unbounded it costs the area of the clip once per batch: a full-screen
                // window painting a document of strokes clears several megapixels per stroke, and
                // that, not the strokes, is what the adapter spends the frame on.
                let savedOn   = .scissorOn
                let savedBox  = .scissorBox
                let unbounded = savedOn ? savedBox : .targetRect()
                let narrowed  = .narrowScissorToBatch(params.bbMin, params.bbMax)
                .countScratchClear(.scissorOn ? .scissorBox : .targetRect(), unbounded)

                // Fresh start on alpha. Clear all
                glDisable(GL_BLEND)
                glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_TRUE)
                glClearColor(0, 0, 0, 0)
                glClear(GL_COLOR_BUFFER_BIT)

                // First we mark the alpha buffer with the 'maximum' alpha to paint.
                // If a pixel is drawn twice because of overlapping, we will have the 'most opaque'.
                // The source factor is one: weighting the source alpha by itself would store the
                // coverage squared, and the draw pass below would then light every antialiased
                // fringe and every translucent stroke by its own opacity a second time.
                glEnable(GL_BLEND)
                glBlendFunc(GL_ONE, GL_ZERO)
                glBlendEquation(GL_MAX)
                glDrawArrays(GL_TRIANGLES, cast(GLint, params.start), cast(GLsizei, params.count))

                // Then we use the stored alpha as the blend factor.
                // When a pixel is drawn once, the alpha value will be reset to 0, so this means that
                // the second overlapping pixel (if there's one) will not be written.
                glBlendFuncSeparate(GL_DST_ALPHA, GL_ONE_MINUS_DST_ALPHA, GL_ZERO, GL_ZERO)
                glBlendEquation(GL_FUNC_ADD)
                glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE)
                glDrawArrays(GL_TRIANGLES, cast(GLint, params.start), cast(GLsizei, params.count))
                .setColorMask(.colorMask)

                if narrowed
                {
                    if savedOn do
                        .applyScissor(savedBox)
                    else do
                        .clearScissor()
                }
            }

        case .StartFont:
            .selectProgram(&.shaderFont)

        case .StartMsdfFont:
            .selectProgram(&.shaderFontMsdf)

        case .EndFont:
            .selectProgram(&.shaderAA)

        case .BindTextureFont:
            let params = &cmd.textureFont
            let cache  = params.font.cache

            // Distance-field atlases are mipmapped: trilinear minification fixes the
            // undersampling that wrecks a minified MSDF at arbitrary scale ratios.
            let isDF = cache.renderMode.isDistanceField()
            let magF = isDF ? GL_LINEAR : GL_NEAREST
            let minF = isDF ? GL_LINEAR_MIPMAP_LINEAR : GL_NEAREST
            glActiveTexture(GL_TEXTURE1)
            let texture = cache.atlases[params.atlasIndex].texture.handle
            glBindTexture(GL_TEXTURE_2D, cast(GLuint, texture))
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, magF)
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, minF)

        case .ResetTextureFont:
            glActiveTexture(GL_TEXTURE1)
            glBindTexture(GL_TEXTURE_2D, .whiteTexture)

        case .UpdateFont:
            let cache = cmd.font.fontRef.cache

            // Mipmapped trilinear minification for distance-field atlases (see BindTextureFont).
            let isDF = cache.renderMode.isDistanceField()
            let magF = isDF ? GL_LINEAR : GL_NEAREST
            let minF = isDF ? GL_LINEAR_MIPMAP_LINEAR : GL_NEAREST
            glActiveTexture(GL_TEXTURE1)
            let bpp = cache.renderMode.bytesPerPixel()
            let fmt = bpp == 1 ? GL_RED : (bpp == 4 ? GL_RGBA : GL_RGB)
            for &atlas in cache.atlases
            {
                if not atlas.dirty do
                    continue
                defer #fail .removeTextureImpl(&atlas.texture)

                let isNew = atlas.texture.handle == InvalidTextureHandle

                var textureID: GLuint
                if isNew do
                    glGenTextures(1, &textureID)
                else do
                    textureID = cast(atlas.texture.handle)
                let textureNameError = glGetError()
                if not textureID or textureNameError != GL_NO_ERROR do
                    fail RenderResourceError{"OpenGL cannot allocate a glyph atlas"}

                atlas.texture.attach(cast(TextureHandle, textureID), atlas.bytesPerPixel == 3 ? .RGB8 : .RGBA8, atlas.width / atlas.bytesPerPixel, atlas.height, .generation)

                // An atlas keeps fixed dimensions for its whole life, so allocate the
                // texture storage once and stream new glyphs in with glTexSubImage2D.
                // Re-uploading with glTexImage2D every time a glyph is appended forces
                // the driver to reallocate and synchronize, which stalls the frame and
                // is felt as a series of hitches while a font warms up its glyphs.
                glBindTexture(GL_TEXTURE_2D, textureID)
                glPixelStorei(GL_UNPACK_ALIGNMENT, 1)

                if isNew
                {
                    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
                    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
                    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, magF)
                    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, minF)
                    if isDF do
                        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAX_LEVEL, FontAtlasMaxLevel)
                    glTexImage2D(GL_TEXTURE_2D, 0, fmt, cast(GLsizei, atlas.texture.width), cast(GLsizei, atlas.texture.height), 0, fmt, GL_UNSIGNED_BYTE, atlas.data.buffer)
                    if glGetError() != GL_NO_ERROR do
                        fail RenderResourceError{"OpenGL cannot initialize a glyph atlas"}
                }
                else
                {
                    // New glyphs occupy only a small part of an existing page. Keep the atlas
                    // row stride while uploading its changed rectangle, then restore unpack
                    // state so ordinary image uploads still read tightly packed rows.
                    let pixels = atlas.data.buffer + cast(u64, atlas.dirtyMinY) * atlas.width + atlas.dirtyMinX * bpp
                    glPixelStorei(GL_UNPACK_ROW_LENGTH, cast(GLint, atlas.texture.width))
                    glTexSubImage2D(GL_TEXTURE_2D, 0, cast(GLint, atlas.dirtyMinX), cast(GLint, atlas.dirtyMinY), cast(GLsizei, (atlas.dirtyMaxX - atlas.dirtyMinX)), cast(GLsizei, (atlas.dirtyMaxY - atlas.dirtyMinY)), fmt, GL_UNSIGNED_BYTE, pixels)
                    if glGetError() != GL_NO_ERROR do
                        fail RenderResourceError{"OpenGL cannot update a glyph atlas"}
                    glPixelStorei(GL_UNPACK_ROW_LENGTH, 0)
                }

                // Build the mip chain for distance-field atlases. Each glyph keeps a
                // 'spread'-texel margin and starts on a 'spread'-texel cell, and the chain stops
                // at that size, so no level blends a neighbouring glyph into this one.
                if isDF do
                    glGenerateMipmap(GL_TEXTURE_2D)
                if glGetError() != GL_NO_ERROR do
                    fail RenderResourceError{"OpenGL cannot build glyph atlas mipmaps"}
                atlas.dirty = false
            }

            cache.dirty = false

        case .ResetTexture0:
            if .planarPrevShader
            {
                .setShader(.planarPrevShader)
                .planarPrevShader = null
            }

            let curShader = unwrap .curShader
            glUniform1f(cast(GLint, curShader.paintType), cast(GLfloat, cast(u32, BrushType.SolidColor)))
            glUniform1f(cast(GLint, curShader.uvMode), cast(GLfloat, cast(u32, UVMode.Fill)))
            glUniform1f(cast(GLint, curShader.interpolationMode), cast(GLfloat, cast(u32, InterpolationMode.Pixel)))
            glUniform1i(cast(GLint, curShader.gradientCount), 0)
            glActiveTexture(GL_TEXTURE0)
            glBindTexture(GL_TEXTURE_2D, .whiteTexture)

        case .BindTexture0:
            let params = &cmd.texture0

            // A planar picture is three textures and its own program. Selecting it here, from the
            // format the texture carries, is what lets it travel through the ordinary texture
            // path: nothing above this line knows the difference.
            let planarPlanes = params.type == .Texture and not params.texture.pixelFormat.isPacked() ? .chromaPlanes.tryFind(params.texture.handle) : null
            if planarPlanes
            {
                if not .planarPrevShader do
                    .planarPrevShader = .curShader
                glActiveTexture(GL_TEXTURE3)
                glBindTexture(GL_TEXTURE_2D, planarPlanes.value.chromaB)
                glActiveTexture(GL_TEXTURE4)
                glBindTexture(GL_TEXTURE_2D, planarPlanes.value.chromaR)
                .setShader(&.shaderYuv)
                let factors = &planarPlanes.value.factors
                glUniform4f(cast(GLint, .shaderYuv.lumaRed),
                            cast(GLfloat, factors.lumaOffset),
                            cast(GLfloat, factors.lumaScale),
                            cast(GLfloat, factors.redCr),
                            cast(GLfloat, factors.blueCb))
                glUniform2f(cast(GLint, .shaderYuv.green),
                            cast(GLfloat, factors.greenCb),
                            cast(GLfloat, factors.greenCr))
            }
            elif .planarPrevShader
            {
                .setShader(.planarPrevShader)
                .planarPrevShader = null
            }

            let curShader = unwrap .curShader
            glUniform4fv(cast(GLint, curShader.boundRect), 1, &params.boundRect.x)
            glUniform4fv(cast(GLint, curShader.textureRect), 1, &params.textureRect.x)
            glUniform4fv(cast(GLint, curShader.texturePixelBounds), 1, &params.texturePixelBounds.x)
            glUniform1f(cast(GLint, curShader.uvMode), cast(GLfloat, params.uvMode))

            // At a fractional content scale, pixel sampling switches to the sharp
            // bilinear shader path (uniform value 2): texel edges keep one device
            // pixel of smoothing instead of dropping texels or smearing borders.
            var interpol = cast(GLfloat, params.interpolationMode)
            if params.interpolationMode == .Pixel and .contentScale != 1 do
                interpol = 2.0
            glUniform1f(cast(GLint, curShader.interpolationMode), interpol)
            glUniform1f(cast(GLint, curShader.paintType), cast(GLfloat, cast(u32, params.type)))
            glActiveTexture(GL_TEXTURE0)

            switch #complete params.type
            {
            case .SolidColor:
                glBindTexture(GL_TEXTURE_2D, .whiteTexture)
                glUniform1i(cast(GLint, curShader.gradientCount), 0)

            case .Texture:

                // A texture of a lost device names nothing in this context, or someone else's
                // storage once the name is reused: draw nothing rather than the wrong picture.
                let lost = params.texture.handle != InvalidTextureHandle and not params.texture.isValid()
                glBindTexture(GL_TEXTURE_2D, lost ? .clearTexture : cast(GLuint, params.texture.handle))
                glUniform1f(cast(GLint, curShader.textureW), cast(GLfloat, params.texture.width))
                glUniform1f(cast(GLint, curShader.textureH), cast(GLfloat, params.texture.height))
                glUniform1i(cast(GLint, curShader.gradientCount), 0)

            case .Hatch:
                glBindTexture(GL_TEXTURE_2D, .hatchTextures[params.hatch])
                glUniform1i(cast(GLint, curShader.gradientCount), 0)

            case .LinearGradient, .RadialGradient, .SweepGradient:
                glBindTexture(GL_TEXTURE_2D, .whiteTexture)
                glUniform1f(cast(GLint, curShader.gradientSpread), cast(GLfloat, cast(u32, params.gradientSpread)))
                glUniform2f(cast(GLint, curShader.gradientStart), cast(GLfloat, params.gradientStart.x), cast(GLfloat, params.gradientStart.y))
                glUniform2f(cast(GLint, curShader.gradientEnd), cast(GLfloat, params.gradientEnd.x), cast(GLfloat, params.gradientEnd.y))
                glUniform2f(cast(GLint, curShader.gradientRadius), cast(GLfloat, params.gradientRadius0), cast(GLfloat, params.gradientRadius1))
                glUniform2f(cast(GLint, curShader.gradientAngles), cast(GLfloat, params.gradientAngle0), cast(GLfloat, params.gradientAngle1))
                glUniform1i(cast(GLint, curShader.gradientCount), cast(GLint, params.gradientStopCount))

                let stops = Swag.makeSlice(dc.gradientStops.buffer + params.gradientStopStart, params.gradientStopCount)
                if params.gradientStopCount <= 8
                {
                    glUniform1i(cast(GLint, curShader.gradientTextureEnabled), 0)
                    var offsets: [8] f32
                    var colors:  [8] Vector4
                    for i in params.gradientStopCount
                    {
                        offsets[i] = stops[i].offset
                        colors[i]  = stops[i].color.toVector4()
                    }

                    if params.gradientStopCount
                    {
                        glUniform1fv(cast(GLint, curShader.gradientOffsets), cast(GLsizei, params.gradientStopCount), &offsets[0])
                        glUniform4fv(cast(GLint, curShader.gradientColors), cast(GLsizei, params.gradientStopCount), &colors[0].x)
                    }
                }
                else
                {
                    glUniform1i(cast(GLint, curShader.gradientTextureEnabled), 1)
                    glUniform1i(cast(GLint, curShader.gradientTexture), 2)

                    if .gradientTextureCapacity < params.gradientStopCount
                    {
                        let newCapacity = Math.max(.gradientTextureCapacity * 2, params.gradientStopCount)
                        glActiveTexture(GL_TEXTURE2)
                        glBindTexture(GL_TEXTURE_2D, .gradientTexture)
                        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA32F, cast(GLsizei, newCapacity), 2, 0, GL_RGBA, GL_FLOAT, null)
                        if glGetError() != GL_NO_ERROR do
                            fail RenderResourceError{"OpenGL cannot allocate gradient stops"}
                        .gradientTextureCapacity = newCapacity
                    }
                    else
                    {
                        glActiveTexture(GL_TEXTURE2)
                        glBindTexture(GL_TEXTURE_2D, .gradientTexture)
                    }

                    .gradientOffsetUpload.resize(params.gradientStopCount)
                    .gradientColorUpload.resize(params.gradientStopCount)
                    for i in params.gradientStopCount
                    {
                        .gradientOffsetUpload[i] = Vector4{stops[i].offset, 0, 0, 0}
                        .gradientColorUpload[i]  = stops[i].color.toVector4()
                    }

                    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, cast(GLsizei, params.gradientStopCount), 1, GL_RGBA, GL_FLOAT, .gradientOffsetUpload.buffer)
                    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 1, cast(GLsizei, params.gradientStopCount), 1, GL_RGBA, GL_FLOAT, .gradientColorUpload.buffer)
                    if glGetError() != GL_NO_ERROR do
                        fail RenderResourceError{"OpenGL cannot upload gradient stops"}
                    glActiveTexture(GL_TEXTURE0)
                }
            }

            switch #complete params.uvMode
            {
            case .Fill, .FillSubRect:
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)

            case .Tile:
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT)
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT)
            }

            switch #complete params.interpolationMode
            {
            case .Pixel:
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST)
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST)

            case .Linear:
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
            }

        case .ReleaseTexture:
            var texture = cmd.texture0.texture
            me.removeTextureImpl(&texture)

        case .BindRenderTarget:
            if not cmd.renderTgt.tgt.colorBuffer.isValid() do
                fail RenderResourceError{"OpenGL cannot allocate a painter render target"}
            .bindRenderTargetImpl(cmd.renderTgt.tgt)
            let curRT = unwrap .curRT
            curRT.paintAlpha    = cmd.renderTgt.paintAlpha
            curRT.paintAlphaIdx = cmdIdx
            let curShader = unwrap .curShader
            .computeMatrices(curShader.mvp, curShader.mdl)

            // A layer has a space of its own: the region in force around it cuts the layer when
            // it is drawn, not the marks inside it.
            .stackClipMaskOn.add(.clipMaskOn)
            .clipMaskOn = false
            .uploadClipMaskState()

        case .UnbindRenderTarget:
            Swag.assert(.curRT != null)

            let curRT = .curRT
            if curRT.paintAlpha
            {
                glEnable(GL_BLEND)
                glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_TRUE)
                glClearColor(0, 0, 0, 0)
                .prepareFramebufferTouch()
                glClear(GL_COLOR_BUFFER_BIT)
                glBlendFunc(GL_SRC_ALPHA, GL_ZERO)
                glBlendEquation(GL_MAX)

                .alphaReplay = true
                for var i = curRT.paintAlphaIdx; i < cmdIdx; i += 1
                {
                    let cmd1 = dc.commandBuffer[i]
                    switch cmd1.op
                    {
                    case .Transform, .StartFont, .StartMsdfFont, .EndFont,
                         .ResetTexture0, .BindTexture0, .ResetTextureFont,
                         .BindTextureFont, .SetFontEffect, .DrawTriangles:
                        try .executeCommand(dc, cmd1, cast(u64, i))
                    }
                }

                .alphaReplay = false
                .setColorMask(.colorMask)
            }

            .unbindRenderTargetImpl()
            let curShader = unwrap .curShader
            .computeMatrices(curShader.mvp, curShader.mdl)
            if .stackClipMaskOn.count
            {
                .clipMaskOn = .stackClipMaskOn.popBack()
                .uploadClipMaskState()
            }

        case .ReleaseRenderTarget:
            .releaseRenderTargetImpl(cmd.renderTgt.tgt)

        case .CaptureBackdrop:
            let capture = &cmd.backdropCapture
            if not capture.tgt.colorBuffer.isValid() do
                fail RenderResourceError{"OpenGL cannot allocate a backdrop render target"}
            let size = .targetSizeImpl()
            let rect = capture.rect
            .prepareFramebufferTouch()
            glDisable(GL_SCISSOR_TEST)
            glBindFramebuffer(GL_DRAW_FRAMEBUFFER, cast(GLuint, capture.tgt.handle))
            glBlitFramebuffer(cast(GLint, rect.x), cast(GLint, (size.height - rect.bottom())), cast(GLint, rect.right()), cast(GLint, (size.height - rect.y)), 0, capture.tgt.colorBuffer.height - cast(GLint, rect.height), cast(GLint, rect.width), capture.tgt.colorBuffer.height, GL_COLOR_BUFFER_BIT, GL_NEAREST)
            .rebindCurrentTarget()
            if .scissorOn
            {
                var scissor = .scissorBox
                .applyScissor(scissor)
            }

        case .SetBackdropShader:
            let params = &cmd.backdropPass
            .selectProgram(&.shaderBackdrop)
            glUniform1i(cast(GLint, .shaderBackdrop.mode), params.mode)
            glUniform1f(cast(GLint, .shaderBackdrop.radius), params.radius)
            glUniform1f(cast(GLint, .shaderBackdrop.saturation), params.saturation)
            glUniform2f(cast(GLint, .shaderBackdrop.sourceSize), params.width, params.height)
            let tint = params.tint.toVector4()
            glUniform4f(cast(GLint, .shaderBackdrop.tint), tint.x, tint.y, tint.z, tint.w)

        case .SetDefaultShader:
            let params = &cmd.defaultShader
            switch #complete params.id
            {
            case .Default:
                .selectProgram(&.shaderAA)

            case .Simple:
                .selectProgram(&.shaderSimple)

            case .Blur:
                .selectProgram(&.shaderBlur)
                glUniform1i(cast(GLint, .shaderBlur.axis), params.axis)

                // The blur samples target texels; a logical radius must cover the
                // same on-screen extent whatever the content scale.
                glUniform1f(cast(GLint, .shaderBlur.radius), params.radius * .contentScale)

            case .Resolve:
                .selectProgram(&.shaderResolve)
                glUniform1i(cast(GLint, .shaderResolve.factor), params.factor)
            }

        case .SetShader:
            let params = &cmd.shader
            .selectProgram(params.shader)

        case .SetShaderParam:
            let params = &cmd.shaderParam
            switch params.type
            {
            case s32: glUniform1i(cast(GLint, params.param), params._s32)
            case f32: glUniform1f(cast(GLint, params.param), params._f32)
            default:  Swag.assert(false)
            }

        case .SetFontEffect:

            // Always emitted right after StartMsdfFont, so the MSDF font program is
            // the active one and these uniforms land on it.
            let p  = &cmd.fontEffect
            let s  = &.shaderFontMsdf
            let oc = p.outlineColor.toVector4()
            let gc = p.glowColor.toVector4()
            glUniform1f(cast(GLint, s.fxEnabled), p.enabled)
            glUniform1f(cast(GLint, s.fxFaceDilate), p.faceDilate)
            glUniform1f(cast(GLint, s.fxFaceSoftness), p.faceSoftness)
            glUniform1f(cast(GLint, s.fxOutlineWidth), p.outlineWidth)
            glUniform4fv(cast(GLint, s.fxOutlineColor), 1, &oc.x)
            glUniform4fv(cast(GLint, s.fxGlowColor), 1, &gc.x)
            glUniform1f(cast(GLint, s.fxGlowOffset), p.glowOffset)
            glUniform1f(cast(GLint, s.fxGlowInner), p.glowInner)
            glUniform1f(cast(GLint, s.fxGlowOuter), p.glowOuter)
            glUniform1f(cast(GLint, s.fxGlowPower), p.glowPower)
            glUniform1f(cast(GLint, s.fxBevel), p.bevel)
        }
    }

    // Executes a completed painter command stream.
    internal mtd drawImpl(dc: *Painter) fail
    {
        let previousTarget = .curRT
        let targetDepth    = .stackRT.count
        var nextCommand: u64
        defer #fail
        {
            // A failed stream still owns releases after the command that failed. Restore the
            // caller's target even when a nested layer or coverage-mask pass was interrupted.
            for cmd in dc.commandBuffer.toSlice()[nextCommand until dc.commandBuffer.count]
            {
                if Swag.kindOf(cmd.op) == .ReleaseRenderTarget
                {
                    .releaseRenderTargetImpl(cmd.renderTgt.tgt)
                }
                elif Swag.kindOf(cmd.op) == .ReleaseTexture
                {
                    var texture = cmd.texture0.texture
                    .removeTextureImpl(&texture)
                }
            }

            .stackRT.resize(targetDepth)
            .curRT           = previousTarget
            .clipMaskOn      = false
            .clipMaskWriting = false
            .alphaReplay     = false
            .overlapMode     = false
            .stackClipMaskOn.clear()
            .rebindCurrentTarget()
            .clearScissor()
            while glGetError() != GL_NO_ERROR {}
        }

        // Attribute an earlier native error to the submission boundary, never to the next
        // allocation. It is reported to the caller, who must repaint before presenting.
        if glGetError() != GL_NO_ERROR do
            fail RenderResourceError{"OpenGL has an error before painter submission"}
        if .curRT and not .curRT.colorBuffer.isValid() do
            fail RenderResourceError{"OpenGL cannot allocate the submission render target"}

        var unpackBuffer, alignment, rowLength, skipRows, skipPixels: GLint
        glGetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING, &unpackBuffer)
        glGetIntegerv(GL_UNPACK_ALIGNMENT, &alignment)
        glGetIntegerv(GL_UNPACK_ROW_LENGTH, &rowLength)
        glGetIntegerv(GL_UNPACK_SKIP_ROWS, &skipRows)
        glGetIntegerv(GL_UNPACK_SKIP_PIXELS, &skipPixels)
        defer
        {
            glBindBuffer(GL_PIXEL_UNPACK_BUFFER, cast(GLuint, unpackBuffer))
            glPixelStorei(GL_UNPACK_ALIGNMENT, alignment)
            glPixelStorei(GL_UNPACK_ROW_LENGTH, rowLength)
            glPixelStorei(GL_UNPACK_SKIP_ROWS, skipRows)
            glPixelStorei(GL_UNPACK_SKIP_PIXELS, skipPixels)
            for i in 4 do
                glDisableVertexAttribArray(cast(GLuint, i))
        }

        glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0)
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
        glPixelStorei(GL_UNPACK_ROW_LENGTH, 0)
        glPixelStorei(GL_UNPACK_SKIP_ROWS, 0)
        glPixelStorei(GL_UNPACK_SKIP_PIXELS, 0)
        let {width, height} = .targetSizeImpl()
        if width <= 0 or height <= 0 do
            return

        // The stream's logical-to-device factor drives the model matrix, the
        // scissor, and blur radii for the whole submission.
        .contentScale = dc.contentScale()

        glBindBuffer(GL_ARRAY_BUFFER, .vertexbuffer)

        // The vertex stream is rebuilt for every frame. Allocate and upload it in one call;
        // GL_STREAM_DRAW describes its one-upload, one-draw lifetime.
        let byteSize = dc.vertexBuffer.count * #sizeof(VertexLayout)
        glBufferData(GL_ARRAY_BUFFER, byteSize, dc.vertexBuffer.buffer, GL_STREAM_DRAW)
        if glGetError() != GL_NO_ERROR do
            fail RenderResourceError{"OpenGL cannot upload the vertex stream"}

        // Default shader; a planar picture drawn last in the previous submission no longer
        // holds a program to restore.
        .selectProgram(&.shaderAA)
        let curShader = unwrap .curShader
        .computeMatrices(curShader.mvp, curShader.mdl)

        // Default state
        .clearScissor()
        .clipMaskOn      = false
        .clipMaskWriting = false
        .stackClipMaskOn.clear()
        .uploadClipMaskState()
        glDisable(GL_STENCIL_TEST)
        glDisable(GL_DEPTH_TEST)
        glClearStencil(0)
        glStencilMask(0xFF)
        glDepthMask(GL_FALSE)

        glActiveTexture(GL_TEXTURE0)
        glBindTexture(GL_TEXTURE_2D, .whiteTexture)
        glActiveTexture(GL_TEXTURE1)
        glBindTexture(GL_TEXTURE_2D, .whiteTexture)
        .setBlendingMode(BlendingMode.Alpha)
        .setColorMask({true, true, true, false})

        for i in 4 do
            glEnableVertexAttribArray(cast(GLuint, i))
        for cmd, cmdIdx in dc.commandBuffer
        {
            try .executeCommand(dc, cmd, cmdIdx)
            nextCommand = cmdIdx + 1
        }

        if glGetError() != GL_NO_ERROR do
            fail RenderResourceError{"OpenGL cannot complete the painter commands"}
        .finishAdvancedBlendPass()
    }

    // Makes `shader` the program of the commands that follow, as a painter command asks.
    //
    // A planar texture swaps in its own program and restores the displaced one when the next
    // texture is bound; a program chosen after it supersedes that restore. Otherwise the reset
    // that follows a font program's start would bring back the program the picture displaced,
    // and the glyphs would be drawn by it: text right after a video frame came out as raw,
    // blurred distance fields.
    mtd selectProgram(shader: *ShaderBase?)
    {
        .planarPrevShader = null
        .setShader(shader)
    }

    // Makes `shader` the current OpenGL program, or the built-in antialiased program when `null`.
    //
    // The matrices, blending, and clipping uniforms of the program are refreshed.
    mtd setShader(shader: *ShaderBase? = null)
    {
        .curShader = shader orelse &.shaderAA
        glUseProgram(cast(GLuint, .curShader.handle))
        glUniformMatrix4fv(cast(GLint, .curShader.mvp), 1, GL_FALSE, &.orthoMatrix.m[0, 0])
        glUniformMatrix4fv(cast(GLint, .curShader.mdl), 1, GL_FALSE, &.modelMatrix.m[0, 0])

        // Uniforms are per program: the incoming program's copyMode may be stale from an
        // earlier frame, so realign it with the current blending mode; see setBlendingMode.
        glUniform1i(cast(GLint, .curShader.copyMode), cast(GLint, (.blendingMode == .Copy)))
        glUniform1i(cast(GLint, .curShader.premultiplyBlendSource), cast(GLint, (.usesKhrAdvancedBlending() and .blendingMode.usesAdvancedBlending())))
        .uploadClipMaskState()
    }

    // Returns the clipping mask matching a target size, creating it the first time.
    //
    // A mask is one coverage channel per device pixel, drawn under the target's own projection,
    // so it has to be exactly the target's size; a window and the layers inside it each get one.
    // Only a handful are alive at once — the surface and the layers open over it — while a border
    // drag walks a whole path of target sizes, so the cache is bounded and gives its least
    // recently used entry back rather than keeping a full-target texture for every size the
    // window ever passed through. The mask in force is never the one reused: the region being
    // drawn still samples it.
    private mtd clipMaskFor(width, height: s32)->s32 fail
    {
        .clipMaskClock += 1

        for &mask, index in .clipMasks where mask.width == width and mask.height == height
        {
            mask.lastUse = .clipMaskClock
            return cast(s32, index)
        }

        var reuse = -1's32
        if .clipMasks.count >= MaxClipMasks
        {
            var oldest = Swag.U64.Max
            for mask, index in .clipMasks where cast(s32, index) != .clipMaskIndex and mask.lastUse < oldest
            {
                oldest = mask.lastUse
                reuse  = cast(s32, index)
            }
        }

        // The texture is created on the mask's own unit, so the paint texture bound on unit zero
        // stays what the next batch expects to sample.
        var mask: ClipMask
        mask.width   = width
        mask.height  = height
        mask.lastUse = .clipMaskClock
        glActiveTexture(GL_TEXTURE5)
        mask.texture = .createPlaneTexture(width, height)
        glActiveTexture(GL_TEXTURE0)
        if not mask.texture do
            fail RenderResourceError{"OpenGL cannot allocate a clipping mask"}
        glGenFramebuffers(1, &mask.framebuffer)
        let framebufferNameError = glGetError()
        if not mask.framebuffer or framebufferNameError != GL_NO_ERROR
        {
            .releaseClipMask(&mask)
            fail RenderResourceError{"OpenGL cannot allocate a clipping framebuffer"}
        }

        glBindFramebuffer(GL_FRAMEBUFFER, mask.framebuffer)
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, mask.texture, 0)
        let status = glCheckFramebufferStatus(GL_FRAMEBUFFER)
        let attachmentError = glGetError()
        if status != GL_FRAMEBUFFER_COMPLETE or attachmentError != GL_NO_ERROR
        {
            .releaseClipMask(&mask)
            fail RenderResourceError{"OpenGL cannot complete a clipping framebuffer"}
        }

        if reuse >= 0
        {
            .releaseClipMask(&.clipMasks[cast(u64, reuse)])
            .clipMasks[cast(u64, reuse)] = mask
            return reuse
        }

        .clipMasks.add(mask)
        return cast(s32, (.clipMasks.count - 1))
    }

    // Hands every coverage mask back to the graphics context.
    //
    // Their framebuffers are named by an extension entry point, so this belongs where the context
    // is still current — beside the glyph atlases, on the way out of the last context — and not in
    // the drop of a renderer that no longer has one.
    internal mtd releaseClipMasks()
    {
        for &mask in .clipMasks do
            .releaseClipMask(mask)
        .clipMasks.clear()
        .clipMaskIndex = -1
    }

    // Hands one mask's framebuffer and texture back to the graphics context.
    private mtd releaseClipMask(mask: *ClipMask)
    {
        if mask.framebuffer do
            glDeleteFramebuffers(1, &mask.framebuffer)
        if mask.texture do
            glDeleteTextures(1, &mask.texture)
        mask[] = {}
    }

    // Binds the framebuffer of the target in force again, after a detour through a mask.
    private mtd rebindCurrentTarget()
    {
        if .curRT
        {
            let curRT = .curRT
            glBindFramebuffer(GL_FRAMEBUFFER, cast(GLuint, curRT.handle))
            glViewport(0, 0, curRT.colorBuffer.width, curRT.colorBuffer.height)
            return
        }

        glBindFramebuffer(GL_FRAMEBUFFER, 0)
        glViewport(0, 0, .curRC.width, .curRC.height)
    }

    // Sets the blend that folds newly drawn coverage into the mask under `mode`.
    //
    // The fragment program writes its coverage in every channel while a region is being written,
    // so adding keeps the most covered of overlapping shapes and clearing keeps what they leave.
    private mtd applyClipMaskMode(mode: ClippingMode)
    {
        glEnable(GL_BLEND)
        switch #complete mode
        {
        case .Set:
            glBlendFunc(GL_ONE, GL_ONE)
            glBlendEquation(GL_MAX)

        case .Clear:
            glBlendFunc(GL_ZERO, GL_ONE_MINUS_SRC_COLOR)
            glBlendEquation(GL_FUNC_ADD)
        }
    }

    // Uploads the region state to the active program, which holds it per program.
    private mtd uploadClipMaskState()
    {
        if not .curShader do
            return
        let curShader = .curShader

        var mode = 0
        if .clipMaskWriting do
            mode = 2
        elif .clipMaskOn do
            mode = 1
        glUniform1i(cast(GLint, curShader.clipMaskMode), cast(GLint, mode))
        if .clipMaskIndex >= 0
        {
            let mask = .clipMasks[cast(u64, .clipMaskIndex)]
            glUniform2f(cast(GLint, curShader.clipMaskSize), cast(GLfloat, mask.width), cast(GLfloat, mask.height))
        }
    }

    // Acquires a pooled render target at least as large as the requested size.
    //
    // Return it with [[Pixel.RenderOgl.releaseRenderTarget]].
    internal mtd acquireRenderTargetImpl(width, height: s32)->*RenderTarget
    {
        Swag.assert(width > 0 and height > 0)

        // Small buckets absorb resize jitter without doubling each full-window dimension.
        let bucketWidth  = RenderTarget.pooledExtent(width)
        let bucketHeight = RenderTarget.pooledExtent(height)
        if not bucketWidth or not bucketHeight
        {
            let result = Memory.new'RenderTarget()
            result.clear()
            return result
        }

        for rt, i in .stackReleasedRT
        {
            let r = unwrap rt
            if r.colorBuffer.width == bucketWidth and r.colorBuffer.height == bucketHeight
            {
                .stackReleasedRT.removeAt(i)
                return r
            }
        }

        var rt = Memory.new'RenderTarget()
        rt[] = .createRenderTargetImpl(cast(s32, bucketWidth), cast(s32, bucketHeight))
        return rt
    }

    // Returns a pooled target to this renderer; `null` is ignored.
    internal mtd releaseRenderTargetImpl(tgt: *RenderTarget?)
    {
        if not tgt do
            return
        if not tgt.colorBuffer.isValid()
        {
            Memory.delete(tgt)
            return
        }

        tgt.poolUsed = true
        .stackReleasedRT.add(tgt)
    }

    // Compiles a fragment stage and links it with the shared vertex stage into `base`.
    internal mtd createShader(base: *ShaderBase, vertexShaderID: GLuint, pixel: const [..] u8, baseSource: string) fail
    {
        var buf: String = shaderSource(pixel)
        buf.replace("#include base", baseSource)

        let fragmentShaderID = glCreateShader(GL_FRAGMENT_SHADER)
        defer glDeleteShader(fragmentShaderID)
        var pixelSourcePointer = buf.buffer
        var pixelSourceLength  = cast(GLint, buf.length)
        glShaderSource(fragmentShaderID, 1, &pixelSourcePointer, &pixelSourceLength)
        glCompileShader(fragmentShaderID)
        try checkShaderCompiled(fragmentShaderID)

        let progID = glCreateProgram()
        defer #fail glDeleteProgram(progID)
        glAttachShader(progID, vertexShaderID)
        glAttachShader(progID, fragmentShaderID)
        glLinkProgram(progID)
        glDetachShader(progID, vertexShaderID)
        glDetachShader(progID, fragmentShaderID)
        try checkProgramLinked(progID)

        base.handle = cast(ShaderHandle, progID)

        base.mvp                    = cast(glGetUniformLocation(progID, ("mvp").buffer))
        base.mdl                    = cast(glGetUniformLocation(progID, ("mdl").buffer))
        base.boundRect              = cast(glGetUniformLocation(progID, ("boundRect").buffer))
        base.textureRect            = cast(glGetUniformLocation(progID, ("textureRect").buffer))
        base.texturePixelBounds     = cast(glGetUniformLocation(progID, ("texturePixelBounds").buffer))
        base.uvMode                 = cast(glGetUniformLocation(progID, ("uvMode").buffer))
        base.interpolationMode      = cast(glGetUniformLocation(progID, ("interpolationMode").buffer))
        base.copyMode               = cast(glGetUniformLocation(progID, ("copyMode").buffer))
        base.textureW               = cast(glGetUniformLocation(progID, ("textureW").buffer))
        base.textureH               = cast(glGetUniformLocation(progID, ("textureH").buffer))
        base.paintType              = cast(glGetUniformLocation(progID, ("paintType").buffer))
        base.gradientSpread         = cast(glGetUniformLocation(progID, ("gradientSpread").buffer))
        base.gradientStart          = cast(glGetUniformLocation(progID, ("gradientStart").buffer))
        base.gradientEnd            = cast(glGetUniformLocation(progID, ("gradientEnd").buffer))
        base.gradientRadius         = cast(glGetUniformLocation(progID, ("gradientRadius").buffer))
        base.gradientAngles         = cast(glGetUniformLocation(progID, ("gradientAngles").buffer))
        base.gradientCount          = cast(glGetUniformLocation(progID, ("gradientCount").buffer))
        base.gradientOffsets        = cast(glGetUniformLocation(progID, ("gradientOffsets[0]").buffer))
        base.gradientColors         = cast(glGetUniformLocation(progID, ("gradientColors[0]").buffer))
        base.gradientTexture        = cast(glGetUniformLocation(progID, ("gradientTexture").buffer))
        base.gradientTextureEnabled = cast(glGetUniformLocation(progID, ("gradientTextureEnabled").buffer))
        base.premultiplyBlendSource = cast(glGetUniformLocation(progID, ("premultiplyBlendSource").buffer))
        base.clipMaskMode           = cast(glGetUniformLocation(progID, ("clipMaskMode").buffer))
        base.clipMaskSize           = cast(glGetUniformLocation(progID, ("clipMaskSize").buffer))

        // The clipping mask has a texture unit of its own, above the paint, font, gradient and
        // chroma units, so binding it never displaces what a program is sampling.
        let clipMask = glGetUniformLocation(progID, ("clipMask").buffer)
        glUseProgram(progID)
        glUniform1i(clipMask, 5)
    }
}
