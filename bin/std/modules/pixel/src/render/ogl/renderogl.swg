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

    const PixelShaderYuv     = #include("shaders/yuv.frag")
    const PixelShaderBlur    = #include("shaders/blur.frag")
    const PixelShaderResolve = #include("shaders/resolve.frag")

    const VertexShaderFont    = #include("shaders/font.vert")
    const PixelShaderFont     = #include("shaders/font.frag")
    const PixelShaderFontMsdf = #include("shaders/font_msdf.frag")

    const KhrAdvancedBlendShaderHeader = "#extension GL_KHR_blend_equation_advanced : require\nlayout(blend_support_all_equations) out;\n"

    const AdvancedBlendingNone:        u8 = 0
    const AdvancedBlendingKhrCoherent: u8 = 1
    const AdvancedBlendingNvCoherent:  u8 = 2
    const AdvancedBlendingKhrBarrier:  u8 = 3
    const AdvancedBlendingNvBarrier:   u8 = 4
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

#[Swag.Strict]
alias TextureHandle = u64                                // Opaque renderer texture identifier.
const InvalidTextureHandle: TextureHandle = cast() 0     // Sentinel that identifies no texture.

#[Swag.Strict]
alias RenderTargetHandle = u64                                     // Opaque renderer framebuffer identifier.
const InvalidRenderTargetHandle: RenderTargetHandle = cast() 0     // Sentinel that identifies no framebuffer.

#[Swag.Strict]
alias RenderTargetSurfaceHandle = u64                                            // Opaque renderer depth/stencil-surface identifier.
const InvalidRenderTargetSurfaceHandle: RenderTargetSurfaceHandle = cast() 0     // Sentinel that identifies no surface.

// Executes [[Pixel.Painter]] command streams through OpenGL.
//
// The two chroma planes of a planar texture, held beside the luma handle the caller carries.
//
// Public only because it names the type of a renderer field, which the generated module surface
// spells out; nothing outside this backend has any use for it.
#[Swag.NoDoc]
struct ChromaPlanes
{
    internal
    {
        chromaB: GLuint
        chromaR: GLuint
        factors: YuvConversionFactors
    }
}

// A renderer is non-copyable and owns its shaders, textures, buffers, and queued
// render targets. Create it as an [[Pixel.IRenderer]], create a
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

        // Device pixels the overlap-safe path has cleared as alpha scratch, and what the same
        // batches would have cleared had each been given the whole clipping rectangle.
        //
        // The pair is what makes the bound measurable from a single run: the second is the cost
        // of the unbounded behaviour, on the very geometry the first was measured on. Reset them
        // with [[Pixel.RenderOgl.resetScratchCounters]].
        readonly scratchClearedPixels: u64
        readonly scratchFullPixels:    u64
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
        orthoMatrix:     Matrix4x4               // Current surface projection matrix.
        modelMatrix:     Matrix4x4               // Current model matrix.
        whiteTexture:    GLuint                  // Built-in one-pixel white texture.
        hatchTextures:   [HatchStyle] GLuint     // Built-in hatch texture handles.
        // The two chroma planes of every planar texture, keyed by the luma handle the caller
        // holds. A texture is one handle everywhere else in this module, and a planar picture is
        // three: keeping the other two here is what lets it travel as an ordinary texture.
        chromaPlanes: HashTable'(TextureHandle, ChromaPlanes)

        // The program a planar texture displaced, restored as soon as one stops being drawn.
        planarPrevShader: #null *ShaderBase

        gradientTexture:         GLuint                                       // Dynamically sized gradient-stop table.
        gradientTextureCapacity: u64                                          // Stop slots allocated in `gradientTexture`.
        gradientOffsetUpload:    Array'Vector4                                // Reused first texture row.
        gradientColorUpload:     Array'Vector4                                // Reused second texture row.
        blendingMode:            BlendingMode = .Alpha                        // Active OpenGL blending mode.
        colorMask:               ColorMask    = {true, true, true, false}     // Painter-requested channel mask.
        curRC:                   RenderContext                                // Active drawable and viewport.

        stackReleasedRT:       Array'#null *RenderTarget     // Targets queued for deferred release.
        stackRT:               Array'#null *RenderTarget     // Nested bound render targets.
        curRT:                 #null *RenderTarget           // Active off-screen target, if any.
        curShader:             #null *ShaderBase             // Active shader, or the default shader.
        overlapMode:           bool                          // Whether overlap-safe alpha drawing is active.
        contentScale:          f32 = 1                       // Device pixels per unit of the painter stream being drawn.
        nativeContext:         #null const *void             // Shared native OpenGL context owned by interface-created drawables.
        contextCount:          u32                           // Number of live interface-created drawables.
        advancedBlending:      u8                            // Advanced blend-equation family supplied by the current context.
        advancedBarrierActive: bool                          // Whether this context must keep later framebuffer touches in separate passes.
    }
}

private impl RenderOgl
{
    func oglContext(rc: RenderContext)->*OglContext
    {
        Debug.assert(rc.data != null, "OpenGL render context has no backend state")
        return cast(*OglContext) rc.data!
    }

    func hasExtension(name: string)->bool
    {
        var count: GLint
        glGetIntegerv(GL_NUM_EXTENSIONS, &count)
        for idx in count
        {
            let value = glGetStringi(GL_EXTENSIONS, cast(GLuint) idx)
            if value and cast(string) (cast(const cstring) value!) == name do
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

    mtd const usesKhrAdvancedBlending()->bool
    {
        return .advancedBlending == AdvancedBlendingKhrCoherent or .advancedBlending == AdvancedBlendingKhrBarrier
    }

    mtd const requiresAdvancedBlendBarrier()->bool
    {
        return .advancedBlending == AdvancedBlendingKhrBarrier or .advancedBlending == AdvancedBlendingNvBarrier
    }

    // Starts a new framebuffer-touching pass on contexts whose advanced equations are not
    // coherent. Once a command stream selects an artistic mode, every later touch is isolated:
    // standard draws and clears also count as touches in the extension contract.
    mtd prepareFramebufferTouch()
    {
        if !.advancedBarrierActive do
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

    func setShaderCompileError(shaderID: GLuint) fail
    {
        var result:        GLint
        var infoLogLength: s32
        var infoLog:       String

        glGetShaderiv(shaderID, GL_COMPILE_STATUS, &result)
        glGetShaderiv(shaderID, GL_INFO_LOG_LENGTH, &infoLogLength)
        infoLog.reserve(cast(u64) infoLogLength + 1)
        glGetShaderInfoLog(shaderID, infoLogLength, null, infoLog.buffer)
        if infoLogLength
        {
            infoLog.length = infoLogLength
            Console.print(infoLog)
            fail Swag.SystemError{"shader error"}
        }
    }

    mtd createShaders()
    {
        {
            expect .createShader(&.shaderSimple, VertexShaderSimple, PixelShaderSimple)
            let text0 = glGetUniformLocation(cast(GLuint) .shaderSimple.handle, ("inTexture0").buffer)
            glUseProgram(cast(GLuint) .shaderSimple.handle)
            glUniform1i(text0, 0)
        }

        {
            expect .createShader(&.shaderAA, VertexShaderAA, PixelShaderAA)
            let text0 = glGetUniformLocation(cast(GLuint) .shaderAA.handle, ("inTexture0").buffer)
            let text1 = glGetUniformLocation(cast(GLuint) .shaderAA.handle, ("inTexture1").buffer)
            glUseProgram(cast(GLuint) .shaderAA.handle)
            glUniform1i(text0, 0)
            glUniform1i(text1, 1)
        }

        {
            // The picture arrives as three planes on units 0, 3 and 4, and the shader converts
            // while it samples: that is what lets a decoder skip the conversion entirely.
            expect .createShader(&.shaderYuv, VertexShaderSimple, PixelShaderYuv)
            let text0   = glGetUniformLocation(cast(GLuint) .shaderYuv.handle, ("inTexture0").buffer)
            let chromaB = glGetUniformLocation(cast(GLuint) .shaderYuv.handle, ("inChromaB").buffer)
            let chromaR = glGetUniformLocation(cast(GLuint) .shaderYuv.handle, ("inChromaR").buffer)
            .shaderYuv.lumaRed = cast(ShaderParamHandle) glGetUniformLocation(cast(GLuint) .shaderYuv.handle, ("yuvLumaRed").buffer)
            .shaderYuv.green   = cast(ShaderParamHandle) glGetUniformLocation(cast(GLuint) .shaderYuv.handle, ("yuvGreen").buffer)
            glUseProgram(cast(GLuint) .shaderYuv.handle)
            glUniform1i(text0, 0)
            glUniform1i(chromaB, 3)
            glUniform1i(chromaR, 4)
        }

        {
            expect .createShader(&.shaderFont, VertexShaderFont, PixelShaderFont)
            let text0 = glGetUniformLocation(cast(GLuint) .shaderFont.handle, ("inTexture0").buffer)
            let text1 = glGetUniformLocation(cast(GLuint) .shaderFont.handle, ("inTexture1").buffer)
            let gamma = glGetUniformLocation(cast(GLuint) .shaderFont.handle, ("fontGamma").buffer)
            glUseProgram(cast(GLuint) .shaderFont.handle)
            glUniform1i(text0, 0)
            glUniform1i(text1, 1)
            glUniform1f(gamma, FontGamma)
        }

        {
            expect .createShader(&.shaderFontMsdf, VertexShaderFont, PixelShaderFontMsdf)
            let text0 = glGetUniformLocation(cast(GLuint) .shaderFontMsdf.handle, ("inTexture0").buffer)
            let text1 = glGetUniformLocation(cast(GLuint) .shaderFontMsdf.handle, ("inTexture1").buffer)
            let gamma = glGetUniformLocation(cast(GLuint) .shaderFontMsdf.handle, ("fontGamma").buffer)
            let range = glGetUniformLocation(cast(GLuint) .shaderFontMsdf.handle, ("msdfRange").buffer)
            glUseProgram(cast(GLuint) .shaderFontMsdf.handle)
            glUniform1i(text0, 0)
            glUniform1i(text1, 1)
            glUniform1f(gamma, FontGamma)
            glUniform1f(range, MsdfRange)

            let h = cast(GLuint) .shaderFontMsdf.handle
            .shaderFontMsdf.fxEnabled      = cast() glGetUniformLocation(h, ("fxEnabled").buffer)
            .shaderFontMsdf.fxFaceDilate   = cast() glGetUniformLocation(h, ("fxFaceDilate").buffer)
            .shaderFontMsdf.fxFaceSoftness = cast() glGetUniformLocation(h, ("fxFaceSoftness").buffer)
            .shaderFontMsdf.fxOutlineWidth = cast() glGetUniformLocation(h, ("fxOutlineWidth").buffer)
            .shaderFontMsdf.fxOutlineColor = cast() glGetUniformLocation(h, ("fxOutlineColor").buffer)
            .shaderFontMsdf.fxGlowColor    = cast() glGetUniformLocation(h, ("fxGlowColor").buffer)
            .shaderFontMsdf.fxGlowOffset   = cast() glGetUniformLocation(h, ("fxGlowOffset").buffer)
            .shaderFontMsdf.fxGlowInner    = cast() glGetUniformLocation(h, ("fxGlowInner").buffer)
            .shaderFontMsdf.fxGlowOuter    = cast() glGetUniformLocation(h, ("fxGlowOuter").buffer)
            .shaderFontMsdf.fxGlowPower    = cast() glGetUniformLocation(h, ("fxGlowPower").buffer)
            .shaderFontMsdf.fxBevel        = cast() glGetUniformLocation(h, ("fxBevel").buffer)
        }

        {
            expect .createShader(&.shaderBlur, VertexShaderSimple, PixelShaderBlur)
            let text0 = glGetUniformLocation(cast(GLuint) .shaderBlur.handle, ("inTexture0").buffer)
            glUseProgram(cast(GLuint) .shaderBlur.handle)
            glUniform1i(text0, 0)
            .shaderBlur.axis   = cast() glGetUniformLocation(cast(GLuint) .shaderBlur.handle, ("axis").buffer)
            .shaderBlur.radius = cast() glGetUniformLocation(cast(GLuint) .shaderBlur.handle, ("radius").buffer)
        }

        {
            expect .createShader(&.shaderResolve, VertexShaderSimple, PixelShaderResolve)
            let text0 = glGetUniformLocation(cast(GLuint) .shaderResolve.handle, ("inTexture0").buffer)
            glUseProgram(cast(GLuint) .shaderResolve.handle)
            glUniform1i(text0, 0)
            .shaderResolve.factor = cast() glGetUniformLocation(cast(GLuint) .shaderResolve.handle, ("factor").buffer)
        }
    }

    func generateTexture(datas: const [..] u8, w, h: s32)->GLuint
    {
        Debug.assert(datas.count <= 8 * 8)

        var arr: [64] u32
        for p, i in datas do
            arr[i] = p ? 0xFFFFFFFF : 0

        var result: GLuint
        glGenTextures(1, &result)
        glBindTexture(GL_TEXTURE_2D, result)
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, &arr[0])
        return result
    }

    func ortho(b, t, l, r, n, f: f32)->Matrix4x4
    {
        var result: retval
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
            glUniform1i(cast(GLint) .curShader.copyMode, cast(GLint) (bm == .Copy))
            glUniform1i(cast(GLint) .curShader.premultiplyBlendSource, cast(GLint) (.usesKhrAdvancedBlending() and bm.usesAdvancedBlending()))
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

        case .Multiply, .Screen, .Overlay, .Darken, .Lighten, .ColorDodge, .ColorBurn, .HardLight, .SoftLight, .Difference, .Exclusion, .Hue, .Saturation, .Color, .Luminosity:
            Debug.assert(.advancedBlending != AdvancedBlendingNone, "OpenGL renderer does not support advanced blending modes on this context")
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

    // Releases queued and currently bound render-target descriptors, and the glyph atlases.
    mtd opDrop()
    {
        Debug.assert(.contextCount == 0, "renderer contexts must be deleted before the renderer")
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
            let cache = it!
            for &atlas in cache.atlases where atlas.texture.handle != InvalidTextureHandle
            {
                var id: GLuint = cast() atlas.texture.handle
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
    // Presenting does not wait for the picture to be drawn. A swap is ordered after everything
    // submitted before it, so what reaches the screen is always the frame that was just recorded;
    // waiting for the processor to see it finish only stops this thread for the whole of the
    // drawing. On a shared-memory adapter that is tens of milliseconds a frame, and a caller that
    // presents on a clock — a video player above all — loses exactly that much of every period.
    internal mtd endImpl()
    {
        glFlush()
        .native.swapBuffers(oglContext(.curRC)[])
    }

    // Set the current rendering context
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

    // Clear current render buffers
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
            return {.curRT.colorBuffer.width, .curRT.colorBuffer.height}
        return {.curRC.width, .curRC.height}
    }

    // Force the scissor
    internal mtd setScissorRectImpl(rect: Math.Rectangle)
    {
        .applyScissor(rect)
    }

    // Reset the scissor
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
        .scissorBox = rect
        .scissorOn  = true
        let {?, h} = .targetSizeImpl()
        glEnable(GL_SCISSOR_TEST)
        glScissor(cast(GLint) rect.x, cast(GLint) (cast(f32) h - rect.y - rect.height), cast(GLint) rect.width, cast(GLint) rect.height)
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
        let {w, h} = .targetSizeImpl()
        return {0, 0, cast(f32) w, cast(f32) h}
    }

    // Adds one overlap-safe batch to the scratch-clear counters.
    private mtd countScratchClear(bounded: Math.Rectangle, unbounded: Math.Rectangle)
    {
        .scratchClearedPixels += cast(u64) Math.max(bounded.width * bounded.height, 0.0'f32)
        .scratchFullPixels    += cast(u64) Math.max(unbounded.width * unbounded.height, 0.0'f32)
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

        var box = .deviceTransform.transformBounds({bbMin.x, bbMin.y, bbMax.x - bbMin.x, bbMax.y - bbMin.y})

        // Grow to whole pixels, which is a superset of the pixels the batch can shade: a fragment
        // is lit from its centre, and every centre inside the bound falls in this range. It is the
        // rounding [[Pixel.RenderCpu.triangleRangeBounds]] uses, so both backends narrow to the
        // same region and leave the same alpha behind.
        let x0 = Math.floor(box.x)
        let y0 = Math.floor(box.y)
        let x1 = Math.ceil(box.right())
        let y1 = Math.ceil(box.bottom())

        let {w, h} = .targetSizeImpl()
        var clip   = Math.Rectangle{0, 0, cast(f32) w, cast(f32) h}
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

        .applyScissor({nx0, ny0, nx1 - nx0, ny1 - ny0})
        return true
    }

    internal func GLDebugMessageCallback(Source: GLenum, Type: GLenum, Id: GLuint, Severity: GLenum, Length: GLsizei, Message: const *GLchar, UserParam: const *void)
    {
    // Swag.print(cast(cstring) (Message));
    }

    // Initializes OpenGL extensions, built-in shaders, buffers, and hatch textures.
    //
    // Call this once after a native context is current.
    internal mtd initImpl()
    {
        glInitExtensions()

        if hasExtension("GL_KHR_blend_equation_advanced_coherent")
        {
            .advancedBlending = AdvancedBlendingKhrCoherent
        }
        elif hasExtension("GL_NV_blend_equation_advanced_coherent")
        {
            .advancedBlending = AdvancedBlendingNvCoherent
            glBlendParameteriNV(GL_BLEND_PREMULTIPLIED_SRC_NV, cast(GLint) GL_FALSE)
        }
        elif hasExtension("GL_KHR_blend_equation_advanced")
        {
            .advancedBlending = AdvancedBlendingKhrBarrier
        }
        elif hasExtension("GL_NV_blend_equation_advanced")
        {
            .advancedBlending = AdvancedBlendingNvBarrier
            glBlendParameteriNV(GL_BLEND_PREMULTIPLIED_SRC_NV, cast(GLint) GL_FALSE)
        }

        .createShaders()

        // glEnable(GL_DEBUG_OUTPUT);
        // glEnable(GL_DEBUG_OUTPUT_SYNCHRONOUS);
        // glDebugMessageCallback(&GLDebugMessageCallback, null);

        glGenBuffers(1, &.vertexbuffer)
        glBindBuffer(GL_ARRAY_BUFFER, .vertexbuffer)

        // Vertex buffer layout
        var offset: #null const [*] u8 = null
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
        glGenTextures(1, &.gradientTexture)
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

    // Set the current render target
    internal mtd bindRenderTargetImpl(rt: *RenderTarget, vp: #null *Math.Rectangle = null)
    {
        Debug.assert(rt != null)
        if !rt.colorBuffer.isValid() do
            return
        if .curRT do
            .stackRT.add(.curRT)
        .curRT            = rt
        .curRT.paintAlpha = false

        glBindFramebuffer(GL_FRAMEBUFFER, cast(GLuint) .curRT.handle)
        if vp do
            glViewport(cast() vp.x, cast() vp.y, cast() vp.width, cast() vp.height)
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
        var result: retval = Image.create(w, h, .BGRA8)
        glBindFramebuffer(GL_FRAMEBUFFER, cast(GLuint) rt.handle)
        glReadBuffer(GL_COLOR_ATTACHMENT0)
        glReadPixels(x, rt.colorBuffer.height - h - y, w, h, GL_BGRA, GL_UNSIGNED_BYTE, cast([*] u8) result.pixels.buffer!)
        glBindFramebuffer(GL_FRAMEBUFFER, 0)
        return result
    }

    // Get current render target pixels
    internal mtd unbindRenderTargetToImageImpl(x, y, w, h: s32)->Image
    {
        let curRT = .curRT!

        var result: retval = Image.create(w, h, .BGRA8)
        glReadBuffer(GL_COLOR_ATTACHMENT0)
        glReadPixels(x, curRT.colorBuffer.height - h - y, w, h, GL_BGRA, GL_UNSIGNED_BYTE, cast([*] u8) result.pixels.buffer!)
        .unbindRenderTargetImpl()
        return result
    }

    // Go back to the previous render target, or frame buffer
    internal mtd unbindRenderTargetImpl()
    {
        if .stackRT.count
        {
            .curRT = .stackRT.popBack()
            let curRT = .curRT!
            glBindFramebuffer(GL_FRAMEBUFFER, cast(GLuint) curRT.handle)
            glViewport(0, 0, curRT.colorBuffer.width, curRT.colorBuffer.height)
        }
        else
        {
            .curRT = null
            glBindFramebuffer(GL_FRAMEBUFFER, 0)
            glViewport(0, 0, .curRC.width, .curRC.height)
        }
    }

    // Create a render target
    internal mtd createRenderTargetImpl(w, h: s32)->RenderTarget
    {
        Debug.assert(w > 0 and h > 0)
        var colorID: GLuint
        glGenTextures(1, &colorID)
        glBindTexture(GL_TEXTURE_2D, colorID)
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, null)

        var fbo: GLuint
        glGenFramebuffers(1, &fbo)
        glBindFramebuffer(GL_FRAMEBUFFER, fbo)
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, colorID, 0)

        var rbo: GLuint
        glGenRenderbuffers(1, &rbo)
        glBindRenderbuffer(GL_RENDERBUFFER, rbo)
        glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, w, h)
        glBindRenderbuffer(GL_RENDERBUFFER, 0)
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, rbo)

        glBindFramebuffer(GL_FRAMEBUFFER, 0)

        var result: retval
        result.attach(cast(RenderTargetHandle) fbo, cast(TextureHandle) colorID, .RGBA8, w, h, cast(RenderTargetSurfaceHandle) rbo)
        return result
    }

    // Delete a render target
    internal mtd deleteRenderTargetImpl(rt: *RenderTarget)
    {
        if rt.handle == InvalidRenderTargetHandle or !rt.colorBuffer.isValid() do
            return

        var cb: GLuint = cast() rt.colorBuffer.handle
        glDeleteTextures(1, &cb)

        var ds: GLuint = cast() rt.depthStencil
        glDeleteRenderbuffers(1, &ds)

        var fb: GLuint = cast() rt.handle
        glDeleteFramebuffers(1, &fb)

        rt.clear()
    }

    // Creates one single-channel plane of a planar picture.
    private mtd createPlaneTexture(width, height: s32)->GLuint
    {
        var textureID: GLuint
        glGenTextures(1, &textureID)
        glBindTexture(GL_TEXTURE_2D, textureID)
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
        glTexImage2D(GL_TEXTURE_2D, 0, GL_R8, cast(GLsizei) width, cast(GLsizei) height, 0, GL_RED, GL_UNSIGNED_BYTE, null)
        return textureID
    }

    // Uploads one plane, letting the driver skip whatever padding the source rows carry.
    private mtd uploadPlane(handle: GLuint, pixels: const [*] u8, stride: u64, width, height: s32)
    {
        glBindTexture(GL_TEXTURE_2D, handle)
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
        glPixelStorei(GL_UNPACK_ROW_LENGTH, cast(GLint) stride)
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, cast(GLsizei) width, cast(GLsizei) height, GL_RED, GL_UNSIGNED_BYTE, pixels)
        glPixelStorei(GL_UNPACK_ROW_LENGTH, 0)
    }

    // Registers a planar picture as three single-channel planes the shader converts.
    internal mtd addImageImpl(view: const *Yuv420View)->Texture
    {
        if view.width <= 0 or view.height <= 0
        {
            return {}
        }

        let chromaWidth  = (view.width + 1) / 2
        let chromaHeight = (view.height + 1) / 2
        let luma         = .createPlaneTexture(view.width, view.height)

        var planes: ChromaPlanes
        planes.chromaB = .createPlaneTexture(chromaWidth, chromaHeight)
        planes.chromaR = .createPlaneTexture(chromaWidth, chromaHeight)

        var result: retval
        result.attach(cast(TextureHandle) luma, .Yuv420, view.width, view.height)
        .chromaPlanes.add(result.handle, planes)
        .updatePlanarImpl(result, view)
        return result
    }

    // Replaces the planar picture held by a texture, converting nothing.
    internal mtd updatePlanarImpl(texture: Texture, view: const *Yuv420View)
    {
        if !texture.isValid() or texture.pixelFormat != .Yuv420 do
            return
        let planes = .chromaPlanes.tryFind(texture.handle)
        if !planes do
            return

        let chromaWidth  = (texture.width + 1) / 2
        let chromaHeight = (texture.height + 1) / 2
        .uploadPlane(cast(GLuint) texture.handle, view.luma, view.lumaStride, texture.width, texture.height)
        .uploadPlane(planes!.value.chromaB, view.chromaB, view.chromaStride, chromaWidth, chromaHeight)
        .uploadPlane(planes!.value.chromaR, view.chromaR, view.chromaStride, chromaWidth, chromaHeight)
        planes!.value.factors = view.conversionFactors()
    }

    // Load and register an image for rendering
    internal mtd addImageImpl(fullName: string)->Texture fail
    {
        let image = Image.load(fullName)
        return .addImageImpl(&image)
    }

    // Register an image for rendering
    internal mtd addImageImpl(image: const *Image)->Texture
    {
        if !image.isValid()
        {
            return {}
        }

        // A planar picture has no single upload format; it goes through the plane path.
        if image.pixelFormat == .Yuv420
        {
            Debug.assert(false, "a planar picture is added through its view")
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

        var textureID: GLuint
        glGenTextures(1, &textureID)
        glBindTexture(GL_TEXTURE_2D, textureID)
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
        glTexImage2D(GL_TEXTURE_2D, 0, tinternal, cast(s32) source.width, cast(s32) source.height, 0, fmt, dataType, cast([*] u8) source.pixels.buffer!)

        var result: retval
        result.attach(cast(TextureHandle) textureID, source.pixelFormat, source.width, source.height)
        return result
    }

    // Maps a Pixel byte layout to its OpenGL upload/readback format.
    internal func pixelFormatToNative(pixelFormat: PixelFormat)->GLenum
    {
        switch #complete pixelFormat
        {
        case .Yuv420:
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

        return GL_RGBA
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

    // Update content of texture
    internal mtd updateTextureImpl(texture: Texture, pixels: const *u8)
    {
        let fmt       = pixelFormatToNative(texture.pixelFormat)
        let textureID = cast(GLuint) texture.handle
        glBindTexture(GL_TEXTURE_2D, textureID)
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, cast(s32) texture.width, cast(s32) texture.height, fmt, pixelFormatToNativeType(texture.pixelFormat), pixels)
    }

    // Reads a texture into owned CPU memory in `pixelFormat`.
    internal mtd readTexturePixelsImpl(texture: Texture, pixelFormat: PixelFormat)->Array'u8
    {
        var result: retval
        glEnable(GL_TEXTURE_2D)
        glBindTexture(GL_TEXTURE_2D, cast() texture.handle)
        Debug.assert(pixelFormat.isPacked(), "texture readback requires a packed format")
        result.resize(cast(u64) texture.width * cast(u64) texture.height * pixelFormat.bitsPerPixel() / 8)
        let fmt = pixelFormatToNative(pixelFormat)
        glPixelStorei(GL_PACK_ALIGNMENT, 1)
        glGetTexImage(GL_TEXTURE_2D, 0, fmt, pixelFormatToNativeType(pixelFormat), result.buffer)
        glDisable(GL_TEXTURE_2D)
        return result
    }

    // Unregister a texture created with 'addImage'
    internal mtd removeTextureImpl(texture: *Texture)
    {
        if !texture.isValid() do
            return

        let planes = .chromaPlanes.tryFind(texture.handle)
        if planes
        {
            var chromaB = planes!.value.chromaB
            var chromaR = planes!.value.chromaR
            glDeleteTextures(1, &chromaB)
            glDeleteTextures(1, &chromaR)
            .chromaPlanes.remove(texture.handle)
        }

        var id: GLuint = cast() texture.handle
        glDeleteTextures(1, &id)
        texture.clear()
    }

    // Translate the world transform
    internal mtd translateTransformImpl(x, y: f32)
    {
        let tr = Transform2.createTranslation(x, y)
        .worldTransform.multiply(tr)
    }

    // Rotate the world transform
    internal mtd rotateTransformImpl(angle: Math.Angle)
    {
        let tr = Transform2.createRotation(angle.radians, 0, 0)
        .worldTransform.multiply(tr)
    }

    // Rotate the world transform
    internal mtd rotateTransformImpl(angle: Math.Angle, centerX, centerY: f32)
    {
        let tr = Transform2.createRotation(angle.radians, centerX, centerY)
        .worldTransform.multiply(tr)
    }

    // Scale the world transform
    internal mtd scaleTransformImpl(x, y: f32)
    {
        let tr = Transform2.createScale(x, y, 0, 0)
        .worldTransform.multiply(tr)
    }

    // Scale the world transform
    internal mtd scaleTransformImpl(x: f32)
    {
        let tr = Transform2.createScale(x, x, 0, 0)
        .worldTransform.multiply(tr)
    }

    // Reset the world transform
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
        .orthoMatrix = ortho(cast(f32) height, 0, 0, cast(f32) width, 0, 1.0)
        glUniformMatrix4fv(cast(GLint) mvp, 1, GL_FALSE, &.orthoMatrix.m[0, 0])
        glViewport(0, 0, width, height)

        // Draw matrix
        .buildModelMatrix(Transform2.Identity)
        glUniformMatrix4fv(cast(GLint) mdl, 1, GL_FALSE, &.modelMatrix.m[0, 0])
    }

    private mtd executeCommand(dc: *Painter, cmd: Pixel.Command, cmdIdx: u64)
    {
        switch cmd.id
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
            let curShader = .curShader!
            glUniformMatrix4fv(cast(GLint) curShader.mdl, 1, GL_FALSE, &.modelMatrix.m[0, 0])

        case .StartClippingRegion:
            glEnable(GL_STENCIL_TEST)
            glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE)
            glStencilFunc(GL_ALWAYS, 1, 0xFF)
            fallthrough

        case .SetClippingRegionMode:
            let params = &cmd.clippingRegion
            let mode   = params.mode == .Set ? GL_REPLACE : cast(GLenum) GL_ZERO
            glStencilOp(mode, mode, mode)

        case .EndClippingRegion:
            .setColorMask(.colorMask)
            glStencilFunc(GL_EQUAL, 1, 0xFF)
            glStencilOp(GL_KEEP, GL_KEEP, GL_KEEP)

        case .ResetClippingRegion:
            glDisable(GL_STENCIL_TEST)

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
            .applyScissor({x0, y0, x1 - x0, y1 - y0})

        case .ResetClippingRect:
            .clearScissor()

        case .StartNoOverlap:
            .overlapMode = true

        case .StopNoOverlap:
            .overlapMode = false
            .setBlendingMode(.blendingMode)

        case .DrawTriangles:
            let params = &cmd.drawTriangles
            if !.overlapMode
            {
                if .advancedBarrierActive
                {
                    // A non-coherent pass may touch each sample only once, including through
                    // standard blending. Painter batches can contain overlapping geometry, so
                    // isolate every primitive rather than only every recorded draw command.
                    for var start = params.start; start < params.start + params.count; start += 3
                    {
                        .prepareFramebufferTouch()
                        glDrawArrays(GL_TRIANGLES, cast(GLint) start, 3)
                    }
                }
                else
                {
                    .prepareFramebufferTouch()
                    glDrawArrays(GL_TRIANGLES, cast(GLint) params.start, cast(GLsizei) params.count)
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
                glDrawArrays(GL_TRIANGLES, cast(GLint) params.start, cast(GLsizei) params.count)

                // Then we use the stored alpha as the blend factor.
                // When a pixel is drawn once, the alpha value will be reset to 0, so this means that
                // the second overlapping pixel (if there's one) will not be written.
                glBlendFuncSeparate(GL_DST_ALPHA, GL_ONE_MINUS_DST_ALPHA, GL_ZERO, GL_ZERO)
                glBlendEquation(GL_FUNC_ADD)
                glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE)
                glDrawArrays(GL_TRIANGLES, cast(GLint) params.start, cast(GLsizei) params.count)
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
            .setShader(&.shaderFont)

        case .StartMsdfFont:
            .setShader(&.shaderFontMsdf)

        case .EndFont:
            .setShader(&.shaderAA)

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
            glBindTexture(GL_TEXTURE_2D, cast(GLuint) texture)
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
            cache.dirty = false
            glActiveTexture(GL_TEXTURE1)
            let bpp = cache.renderMode.bytesPerPixel()
            let fmt = bpp == 1 ? GL_RED : (bpp == 4 ? GL_RGBA : GL_RGB)
            for &atlas in cache.atlases
            {
                if !atlas.dirty do
                    continue
                atlas.dirty = false

                let isNew = atlas.texture.handle == InvalidTextureHandle

                var textureID: GLuint
                if isNew do
                    glGenTextures(1, &textureID)
                else do
                    textureID = cast() atlas.texture.handle

                atlas.texture.attach(cast(TextureHandle) textureID, atlas.bytesPerPixel == 3 ? .RGB8 : .RGBA8, atlas.width / atlas.bytesPerPixel, atlas.height)

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
                    glTexImage2D(GL_TEXTURE_2D, 0, fmt, cast(GLsizei) atlas.texture.width, cast(GLsizei) atlas.texture.height, 0, fmt, GL_UNSIGNED_BYTE, atlas.data.buffer)
                }
                else do
                    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, cast(GLsizei) atlas.texture.width, cast(GLsizei) atlas.texture.height, fmt, GL_UNSIGNED_BYTE, atlas.data.buffer)

                // Build the mip chain for distance-field atlases. Each glyph keeps a
                // 'spread'-texel margin, so low mips do not bleed neighbouring glyphs.
                if isDF do
                    glGenerateMipmap(GL_TEXTURE_2D)
            }

        case .ResetTexture0:
            if .planarPrevShader
            {
                .setShader(.planarPrevShader)
                .planarPrevShader = null
            }

            let curShader = .curShader!
            glUniform1f(cast(GLint) curShader.paintType, cast(GLfloat) cast(u32) BrushType.SolidColor)
            glUniform1f(cast(GLint) curShader.uvMode, cast(GLfloat) cast(u32) UVMode.Fill)
            glUniform1f(cast(GLint) curShader.interpolationMode, cast(GLfloat) cast(u32) InterpolationMode.Pixel)
            glUniform1i(cast(GLint) curShader.gradientCount, 0)
            glActiveTexture(GL_TEXTURE0)
            glBindTexture(GL_TEXTURE_2D, .whiteTexture)

        case .BindTexture0:
            let params = &cmd.texture0

            // A planar picture is three textures and its own program. Selecting it here, from the
            // format the texture carries, is what lets it travel through the ordinary texture
            // path: nothing above this line knows the difference.
            let planarPlanes = params.type == .Texture and params.texture.pixelFormat == .Yuv420 ? .chromaPlanes.tryFind(params.texture.handle) : null
            if planarPlanes
            {
                if !.planarPrevShader do
                    .planarPrevShader = .curShader
                glActiveTexture(GL_TEXTURE3)
                glBindTexture(GL_TEXTURE_2D, planarPlanes!.value.chromaB)
                glActiveTexture(GL_TEXTURE4)
                glBindTexture(GL_TEXTURE_2D, planarPlanes!.value.chromaR)
                .setShader(&.shaderYuv)
                let factors = &planarPlanes!.value.factors
                glUniform4f(cast(GLint) .shaderYuv.lumaRed,
                            cast(GLfloat) factors.lumaOffset,
                            cast(GLfloat) factors.lumaScale,
                            cast(GLfloat) factors.redCr,
                            cast(GLfloat) factors.blueCb)
                glUniform2f(cast(GLint) .shaderYuv.green,
                            cast(GLfloat) factors.greenCb,
                            cast(GLfloat) factors.greenCr)
            }
            elif .planarPrevShader
            {
                .setShader(.planarPrevShader)
                .planarPrevShader = null
            }

            let curShader = .curShader!
            glUniform4fv(cast(GLint) curShader.boundRect, 1, &params.boundRect.x)
            glUniform4fv(cast(GLint) curShader.textureRect, 1, &params.textureRect.x)
            glUniform1f(cast(GLint) curShader.uvMode, cast(GLfloat) params.uvMode)

            // At a fractional content scale, pixel sampling switches to the sharp
            // bilinear shader path (uniform value 2): texel edges keep one device
            // pixel of smoothing instead of dropping texels or smearing borders.
            var interpol = cast(GLfloat) params.interpolationMode
            if params.interpolationMode == .Pixel and .contentScale != 1 do
                interpol = 2.0
            glUniform1f(cast(GLint) curShader.interpolationMode, interpol)
            glUniform1f(cast(GLint) curShader.paintType, cast(GLfloat) cast(u32) params.type)
            glActiveTexture(GL_TEXTURE0)

            switch #complete params.type
            {
            case .SolidColor:
                glBindTexture(GL_TEXTURE_2D, .whiteTexture)
                glUniform1i(cast(GLint) curShader.gradientCount, 0)

            case .Texture:
                glBindTexture(GL_TEXTURE_2D, cast(GLuint) params.texture.handle)
                glUniform1f(cast(GLint) curShader.textureW, cast(GLfloat) params.texture.width)
                glUniform1f(cast(GLint) curShader.textureH, cast(GLfloat) params.texture.height)
                glUniform1i(cast(GLint) curShader.gradientCount, 0)

            case .Hatch:
                glBindTexture(GL_TEXTURE_2D, .hatchTextures[params.hatch])
                glUniform1i(cast(GLint) curShader.gradientCount, 0)

            case .LinearGradient, .RadialGradient, .SweepGradient:
                glBindTexture(GL_TEXTURE_2D, .whiteTexture)
                glUniform1f(cast(GLint) curShader.gradientSpread, cast(GLfloat) cast(u32) params.gradientSpread)
                glUniform2f(cast(GLint) curShader.gradientStart, cast(GLfloat) params.gradientStart.x, cast(GLfloat) params.gradientStart.y)
                glUniform2f(cast(GLint) curShader.gradientEnd, cast(GLfloat) params.gradientEnd.x, cast(GLfloat) params.gradientEnd.y)
                glUniform2f(cast(GLint) curShader.gradientRadius, cast(GLfloat) params.gradientRadius0, cast(GLfloat) params.gradientRadius1)
                glUniform2f(cast(GLint) curShader.gradientAngles, cast(GLfloat) params.gradientAngle0, cast(GLfloat) params.gradientAngle1)
                glUniform1i(cast(GLint) curShader.gradientCount, cast(GLint) params.gradientStopCount)

                let stops = Swag.makeSlice(dc.gradientStops.buffer + params.gradientStopStart, params.gradientStopCount)
                if params.gradientStopCount <= 8
                {
                    glUniform1i(cast(GLint) curShader.gradientTextureEnabled, 0)
                    var offsets: [8] f32
                    var colors:  [8] Vector4
                    for i in params.gradientStopCount
                    {
                        offsets[i] = stops[i].offset
                        colors[i]  = stops[i].color.toVector4()
                    }

                    if params.gradientStopCount
                    {
                        glUniform1fv(cast(GLint) curShader.gradientOffsets, cast(GLsizei) params.gradientStopCount, &offsets[0])
                        glUniform4fv(cast(GLint) curShader.gradientColors, cast(GLsizei) params.gradientStopCount, &colors[0].x)
                    }
                }
                else
                {
                    glUniform1i(cast(GLint) curShader.gradientTextureEnabled, 1)
                    glUniform1i(cast(GLint) curShader.gradientTexture, 2)

                    if .gradientTextureCapacity < params.gradientStopCount
                    {
                        .gradientTextureCapacity = Math.max(.gradientTextureCapacity * 2, params.gradientStopCount)
                        glActiveTexture(GL_TEXTURE2)
                        glBindTexture(GL_TEXTURE_2D, .gradientTexture)
                        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA32F, cast(GLsizei) .gradientTextureCapacity, 2, 0, GL_RGBA, GL_FLOAT, null)
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
                        .gradientOffsetUpload[i] = {stops[i].offset, 0, 0, 0}
                        .gradientColorUpload[i]  = stops[i].color.toVector4()
                    }

                    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, cast(GLsizei) params.gradientStopCount, 1, GL_RGBA, GL_FLOAT, .gradientOffsetUpload.buffer)
                    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 1, cast(GLsizei) params.gradientStopCount, 1, GL_RGBA, GL_FLOAT, .gradientColorUpload.buffer)
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
            .bindRenderTargetImpl(cmd.renderTgt.tgt)
            let curRT = .curRT!
            curRT.paintAlpha    = cmd.renderTgt.paintAlpha
            curRT.paintAlphaIdx = cmdIdx
            let curShader = .curShader!
            .computeMatrices(curShader.mvp, curShader.mdl)

        case .UnbindRenderTarget:
            Debug.assert(.curRT != null)

            let curRT = .curRT!
            if curRT.paintAlpha
            {
                glEnable(GL_BLEND)
                glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_TRUE)
                glClearColor(0, 0, 0, 0)
                .prepareFramebufferTouch()
                glClear(GL_COLOR_BUFFER_BIT)
                glBlendFunc(GL_SRC_ALPHA, GL_ZERO)
                glBlendEquation(GL_MAX)

                for var i = curRT.paintAlphaIdx; i < cmdIdx; i += 1
                {
                    let cmd1 = dc.commandBuffer[i]
                    switch cmd1.id
                    {
                    case .Transform, .StartFont, .StartMsdfFont, .EndFont, .ResetTexture0, .BindTexture0, .ResetTextureFont, .BindTextureFont, .SetFontEffect, .DrawTriangles: .executeCommand(dc, cmd1, cast(u64) i)
                    }
                }

                .setColorMask(.colorMask)
            }

            .unbindRenderTargetImpl()
            let curShader = .curShader!
            .computeMatrices(curShader.mvp, curShader.mdl)

        case .ReleaseRenderTarget:
            .releaseRenderTargetImpl(cmd.renderTgt.tgt)

        case .SetDefaultShader:
            let params = &cmd.defaultShader
            switch #complete params.id
            {
            case .Default:
                .setShader(&.shaderAA)

            case .Simple:
                .setShader(&.shaderSimple)

            case .Blur:
                .setShader(&.shaderBlur)
                glUniform1i(cast(GLint) .shaderBlur.axis, params.axis)

                // The blur samples target texels; a logical radius must cover the
                // same on-screen extent whatever the content scale.
                glUniform1f(cast(GLint) .shaderBlur.radius, params.radius * .contentScale)

            case .Resolve:
                .setShader(&.shaderResolve)
                glUniform1i(cast(GLint) .shaderResolve.factor, params.factor)
            }

        case .SetShader:
            let params = &cmd.shader
            .setShader(params.shader)

        case .SetShaderParam:
            let params = &cmd.shaderParam
            switch params.type
            {
            case s32: glUniform1i(cast(GLint) params.param, params._s32)
            case f32: glUniform1f(cast(GLint) params.param, params._f32)
            default:  Debug.assert(false)
            }

        case .SetFontEffect:

            // Always emitted right after StartMsdfFont, so the MSDF font program is
            // the active one and these uniforms land on it.
            let p  = &cmd.fontEffect
            let s  = &.shaderFontMsdf
            let oc = p.outlineColor.toVector4()
            let gc = p.glowColor.toVector4()
            glUniform1f(cast(GLint) s.fxEnabled, p.enabled)
            glUniform1f(cast(GLint) s.fxFaceDilate, p.faceDilate)
            glUniform1f(cast(GLint) s.fxFaceSoftness, p.faceSoftness)
            glUniform1f(cast(GLint) s.fxOutlineWidth, p.outlineWidth)
            glUniform4fv(cast(GLint) s.fxOutlineColor, 1, &oc.x)
            glUniform4fv(cast(GLint) s.fxGlowColor, 1, &gc.x)
            glUniform1f(cast(GLint) s.fxGlowOffset, p.glowOffset)
            glUniform1f(cast(GLint) s.fxGlowInner, p.glowInner)
            glUniform1f(cast(GLint) s.fxGlowOuter, p.glowOuter)
            glUniform1f(cast(GLint) s.fxGlowPower, p.glowPower)
            glUniform1f(cast(GLint) s.fxBevel, p.bevel)
        }
    }

    // Draw the given painter
    internal mtd drawImpl(dc: *Painter)
    {
        let {width, height} = .targetSizeImpl()
        if width <= 0 or height <= 0 do
            return

        // The stream's logical-to-device factor drives the model matrix, the
        // scissor, and blur radii for the whole submission.
        .contentScale = dc.contentScale()

        glBindBuffer(GL_ARRAY_BUFFER, .vertexbuffer)

        // The vertex buffer is fully rebuilt and re-uploaded every frame, so hint
        // GL_STREAM_DRAW (write once, draw once) instead of GL_STATIC_DRAW. Orphan
        // the previous storage first so the driver can hand back fresh memory rather
        // than blocking until the in-flight draw releases the old buffer.
        //
        // The orphan is what the null does; the fill is a sub-data write into the storage it
        // just handed back. Filling with a second 'glBufferData' would allocate the whole
        // buffer a second time instead, which on a document of strokes is tens of megabytes
        // of driver allocation per frame for nothing.
        let byteSize = dc.vertexBuffer.count * #sizeof(VertexLayout)
        glBufferData(GL_ARRAY_BUFFER, byteSize, null, GL_STREAM_DRAW)
        glBufferSubData(GL_ARRAY_BUFFER, 0, byteSize, dc.vertexBuffer.buffer)

        // Default shader
        .setShader(&.shaderAA)
        let curShader = .curShader!
        .computeMatrices(curShader.mvp, curShader.mdl)

        // Default state
        .clearScissor()
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
            glEnableVertexAttribArray(cast(GLuint) i)
        for cmd, cmdIdx in dc.commandBuffer do
            .executeCommand(dc, cmd, cmdIdx)
        for i in 4 do
            glDisableVertexAttribArray(cast(GLuint) i)
        .finishAdvancedBlendPass()
    }

    // Set the current shader
    mtd setShader(shader: #null *ShaderBase = null)
    {
        .curShader = shader orelse &.shaderAA
        glUseProgram(cast(GLuint) .curShader.handle)
        glUniformMatrix4fv(cast(GLint) .curShader.mvp, 1, GL_FALSE, &.orthoMatrix.m[0, 0])
        glUniformMatrix4fv(cast(GLint) .curShader.mdl, 1, GL_FALSE, &.modelMatrix.m[0, 0])

        // Uniforms are per program: the incoming program's copyMode may be stale from an
        // earlier frame, so realign it with the current blending mode; see setBlendingMode.
        glUniform1i(cast(GLint) .curShader.copyMode, cast(GLint) (.blendingMode == .Copy))
        glUniform1i(cast(GLint) .curShader.premultiplyBlendSource, cast(GLint) (.usesKhrAdvancedBlending() and .blendingMode.usesAdvancedBlending()))
    }

    // Acquires a pooled render target at least as large as the requested size.
    //
    // Return it with [[Pixel.RenderOgl.releaseRenderTarget]].
    internal mtd acquireRenderTargetImpl(width, height: s32)->*RenderTarget
    {
        Debug.assert(width > 0 and height > 0)
        let w2 = Math.roundUpToPowerOf2(cast(u32) width)
        let h2 = Math.roundUpToPowerOf2(cast(u32) height)

        for rt, i in .stackReleasedRT
        {
            let r = rt!
            if r.colorBuffer.width == w2 and r.colorBuffer.height == h2
            {
                .stackReleasedRT.removeAt(i)
                return r
            }
        }

        for rt, i in .stackReleasedRT
        {
            let r = rt!
            if r.colorBuffer.width >= w2 and r.colorBuffer.height >= h2
            {
                .stackReleasedRT.removeAt(i)
                return r
            }
        }

        var rt = Memory.new'RenderTarget()
        rt[] = .createRenderTargetImpl(cast(s32) w2, cast(s32) h2)
        return rt
    }

    // Release the given render target
    internal mtd releaseRenderTargetImpl(tgt: #null *RenderTarget)
    {
        if !tgt do
            return
        .stackReleasedRT.add(tgt)
    }

    // Create the given shader
    internal mtd createShader(base: *ShaderBase, vertex, pixel: const [..] u8) fail
    {
        var buf: String = Swag.makeString(vertex.buffer, vertex.count)
        buf.replace("#include base", Swag.makeString(BaseVertexShader.buffer, BaseVertexShader.count))

        let vertexShaderID      = glCreateShader(GL_VERTEX_SHADER)
        var vertexSourcePointer = buf.buffer
        var vertexSourceLength  = cast(GLint) buf.length
        glShaderSource(vertexShaderID, 1, &vertexSourcePointer, &vertexSourceLength)
        glCompileShader(vertexShaderID)
        try setShaderCompileError(vertexShaderID)

        buf = Swag.makeString(pixel.buffer, pixel.count)
        var baseBuilder: StringBuilder
        if .usesKhrAdvancedBlending() do
            baseBuilder.appendString(KhrAdvancedBlendShaderHeader)
        baseBuilder.appendString(Swag.makeString(BasePixelShader.buffer, BasePixelShader.count))
        let baseSource = baseBuilder.moveToString()
        buf.replace("#include base", baseSource)

        let fragmentShaderID   = glCreateShader(GL_FRAGMENT_SHADER)
        var pixelSourcePointer = buf.buffer
        var pixelSourceLength  = cast(GLint) buf.length
        glShaderSource(fragmentShaderID, 1, &pixelSourcePointer, &pixelSourceLength)
        glCompileShader(fragmentShaderID)
        try setShaderCompileError(fragmentShaderID)

        let progID = glCreateProgram()
        glAttachShader(progID, vertexShaderID)
        glAttachShader(progID, fragmentShaderID)
        glLinkProgram(progID)

        glDetachShader(progID, vertexShaderID)
        glDetachShader(progID, fragmentShaderID)
        glDeleteShader(vertexShaderID)
        glDeleteShader(fragmentShaderID)

        base.handle = cast(ShaderHandle) progID

        base.mvp                    = cast() glGetUniformLocation(progID, ("mvp").buffer)
        base.mdl                    = cast() glGetUniformLocation(progID, ("mdl").buffer)
        base.boundRect              = cast() glGetUniformLocation(progID, ("boundRect").buffer)
        base.textureRect            = cast() glGetUniformLocation(progID, ("textureRect").buffer)
        base.uvMode                 = cast() glGetUniformLocation(progID, ("uvMode").buffer)
        base.interpolationMode      = cast() glGetUniformLocation(progID, ("interpolationMode").buffer)
        base.copyMode               = cast() glGetUniformLocation(progID, ("copyMode").buffer)
        base.textureW               = cast() glGetUniformLocation(progID, ("textureW").buffer)
        base.textureH               = cast() glGetUniformLocation(progID, ("textureH").buffer)
        base.paintType              = cast() glGetUniformLocation(progID, ("paintType").buffer)
        base.gradientSpread         = cast() glGetUniformLocation(progID, ("gradientSpread").buffer)
        base.gradientStart          = cast() glGetUniformLocation(progID, ("gradientStart").buffer)
        base.gradientEnd            = cast() glGetUniformLocation(progID, ("gradientEnd").buffer)
        base.gradientRadius         = cast() glGetUniformLocation(progID, ("gradientRadius").buffer)
        base.gradientAngles         = cast() glGetUniformLocation(progID, ("gradientAngles").buffer)
        base.gradientCount          = cast() glGetUniformLocation(progID, ("gradientCount").buffer)
        base.gradientOffsets        = cast() glGetUniformLocation(progID, ("gradientOffsets[0]").buffer)
        base.gradientColors         = cast() glGetUniformLocation(progID, ("gradientColors[0]").buffer)
        base.gradientTexture        = cast() glGetUniformLocation(progID, ("gradientTexture").buffer)
        base.gradientTextureEnabled = cast() glGetUniformLocation(progID, ("gradientTextureEnabled").buffer)
        base.premultiplyBlendSource = cast() glGetUniformLocation(progID, ("premultiplyBlendSource").buffer)
    }
}
