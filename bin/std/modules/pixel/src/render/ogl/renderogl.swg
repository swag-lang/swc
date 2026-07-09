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

    const PixelShaderBlur = #include("shaders/blur.frag")
    const PixelShaderResolve = #include("shaders/resolve.frag")

    const VertexShaderFont = #include("shaders/font.vert")
    const PixelShaderFont  = #include("shaders/font.frag")
    const PixelShaderFontMsdf = #include("shaders/font_msdf.frag")
}

// Exponent applied to glyph coverage in the font shaders to approximate
// linear-space text compositing (the framebuffer blend is non-linear sRGB).
// 1.0 = off; ~1.33 (= 1/0.75) is a mild, safe correction for dark-on-light text.
const FontGamma = 1.0'f32 / 0.75

// MSDF distance range in atlas texels mapped to the stored [0,1] range.
// Must match the generator: 2 * Font.RefEmSpread (spread = 8).
const MsdfRange = 16.0'f32

#[Swag.Strict]
alias TextureHandle = u64
const InvalidTextureHandle: TextureHandle = cast() 0

#[Swag.Strict]
alias RenderTargetHandle = u64
const InvalidRenderTargetHandle: RenderTargetHandle = cast() 0

#[Swag.Strict]
alias RenderTargetSurfaceHandle = u64
const InvalidRenderTargetSurfaceHandle: RenderTargetSurfaceHandle = cast() 0

struct HeadlessTexture
{
    handle: TextureHandle
    pixels: Array'u8
}

#[Swag.NoCopy]
struct RenderOgl
{
    using native:        NativeRenderOgl
    vertexbuffer:        GLuint
    shaderSimple:        ShaderSimple
    shaderAA:            ShaderAA
    shaderBlur:          ShaderBlur
    shaderResolve:       ShaderResolve
    shaderFont:          ShaderFont
    shaderFontMsdf:      ShaderFont
    worldTransform:      Transform2
    orthoMatrix:         Matrix4x4
    modelMatrix:         Matrix4x4
    whiteTexture:        GLuint
    hatchTextures:       [@countof(HatchStyle)] GLuint
    blendingMode:        BlendingMode = .Alpha
    curRC:               RenderingContext
    stackReleasedRT:     Array'*RenderTarget
    stackRT:             Array'*RenderTarget
    curRT:               *RenderTarget
    curShader:           *ShaderBase
    overlapMode          = false
    headless:            bool
    headlessNextHandle:  u64 = 1
    headlessTextures:    Array'HeadlessTexture
}

private impl RenderOgl
{
    mtd findHeadlessTexture(handle: TextureHandle)->#null *HeadlessTexture
    {
        for &it in .headlessTextures where it.handle == handle do
            return it
        return null
    }

    mtd addHeadlessTexture(texture: Texture, pixels: const [..] u8)
    {
        var storage: HeadlessTexture
        storage.handle = texture.handle
        storage.pixels.resize(cast(u64) texture.getByteSize())
        if pixels do
            Memory.copy(storage.pixels.buffer, @dataof(pixels), Math.min(@countof(pixels), storage.pixels.count))
        .headlessTextures.add(#move storage)
    }

    mtd clearHeadlessTexture(texture: Texture, color: Color)
    {
        let storage = .findHeadlessTexture(texture.handle)
        if !storage do
            return

        var img = Image.create(texture.width, texture.height, texture.pf)
        img.fill(color)
        Memory.copy(storage.pixels.buffer, img.pixels.buffer, Math.min(storage.pixels.count, img.pixels.count))
    }

    mtd removeHeadlessTexture(handle: TextureHandle)
    {
        for it, idx in .headlessTextures where it.handle == handle
        {
            .headlessTextures.removeAt(idx)
            return
        }
    }

    func setShaderCompileError(shaderID: GLuint) throw
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
            throw Swag.SystemError{"shader error"}
        }
    }

    mtd createShaders()
    {
        {
            assume createShader(&.shaderSimple, VertexShaderSimple, PixelShaderSimple)
            let text0 = glGetUniformLocation(cast(GLuint) .shaderSimple.handle, @dataof("inTexture0"))
            glUseProgram(cast(GLuint) .shaderSimple.handle)
            glUniform1i(text0, 0)
        }

        {
            assume createShader(&.shaderAA, VertexShaderAA, PixelShaderAA)
            let text0 = glGetUniformLocation(cast(GLuint) .shaderAA.handle, @dataof("inTexture0"))
            let text1 = glGetUniformLocation(cast(GLuint) .shaderAA.handle, @dataof("inTexture1"))
            glUseProgram(cast(GLuint) .shaderAA.handle)
            glUniform1i(text0, 0)
            glUniform1i(text1, 1)
        }

        {
            assume createShader(&.shaderFont, VertexShaderFont, PixelShaderFont)
            let text0 = glGetUniformLocation(cast(GLuint) .shaderFont.handle, @dataof("inTexture0"))
            let text1 = glGetUniformLocation(cast(GLuint) .shaderFont.handle, @dataof("inTexture1"))
            let gamma = glGetUniformLocation(cast(GLuint) .shaderFont.handle, @dataof("fontGamma"))
            glUseProgram(cast(GLuint) .shaderFont.handle)
            glUniform1i(text0, 0)
            glUniform1i(text1, 1)
            glUniform1f(gamma, FontGamma)
        }

        {
            assume createShader(&.shaderFontMsdf, VertexShaderFont, PixelShaderFontMsdf)
            let text0 = glGetUniformLocation(cast(GLuint) .shaderFontMsdf.handle, @dataof("inTexture0"))
            let text1 = glGetUniformLocation(cast(GLuint) .shaderFontMsdf.handle, @dataof("inTexture1"))
            let gamma = glGetUniformLocation(cast(GLuint) .shaderFontMsdf.handle, @dataof("fontGamma"))
            let range = glGetUniformLocation(cast(GLuint) .shaderFontMsdf.handle, @dataof("msdfRange"))
            glUseProgram(cast(GLuint) .shaderFontMsdf.handle)
            glUniform1i(text0, 0)
            glUniform1i(text1, 1)
            glUniform1f(gamma, FontGamma)
            glUniform1f(range, MsdfRange)

            let h = cast(GLuint) .shaderFontMsdf.handle
            .shaderFontMsdf.fxEnabled      = cast() glGetUniformLocation(h, @dataof("fxEnabled"))
            .shaderFontMsdf.fxFaceDilate   = cast() glGetUniformLocation(h, @dataof("fxFaceDilate"))
            .shaderFontMsdf.fxFaceSoftness = cast() glGetUniformLocation(h, @dataof("fxFaceSoftness"))
            .shaderFontMsdf.fxOutlineWidth = cast() glGetUniformLocation(h, @dataof("fxOutlineWidth"))
            .shaderFontMsdf.fxOutlineColor = cast() glGetUniformLocation(h, @dataof("fxOutlineColor"))
            .shaderFontMsdf.fxGlowColor    = cast() glGetUniformLocation(h, @dataof("fxGlowColor"))
            .shaderFontMsdf.fxGlowOffset   = cast() glGetUniformLocation(h, @dataof("fxGlowOffset"))
            .shaderFontMsdf.fxGlowInner    = cast() glGetUniformLocation(h, @dataof("fxGlowInner"))
            .shaderFontMsdf.fxGlowOuter    = cast() glGetUniformLocation(h, @dataof("fxGlowOuter"))
            .shaderFontMsdf.fxGlowPower    = cast() glGetUniformLocation(h, @dataof("fxGlowPower"))
            .shaderFontMsdf.fxBevel        = cast() glGetUniformLocation(h, @dataof("fxBevel"))
        }

        {
            assume createShader(&.shaderBlur, VertexShaderSimple, PixelShaderBlur)
            let text0 = glGetUniformLocation(cast(GLuint) .shaderBlur.handle, @dataof("inTexture0"))
            glUseProgram(cast(GLuint) .shaderBlur.handle)
            glUniform1i(text0, 0)
            .shaderBlur.axis   = cast() glGetUniformLocation(cast(GLuint) .shaderBlur.handle, @dataof("axis"))
            .shaderBlur.radius = cast() glGetUniformLocation(cast(GLuint) .shaderBlur.handle, @dataof("radius"))
        }

        {
            assume createShader(&.shaderResolve, VertexShaderSimple, PixelShaderResolve)
            let text0 = glGetUniformLocation(cast(GLuint) .shaderResolve.handle, @dataof("inTexture0"))
            glUseProgram(cast(GLuint) .shaderResolve.handle)
            glUniform1i(text0, 0)
            .shaderResolve.factor = cast() glGetUniformLocation(cast(GLuint) .shaderResolve.handle, @dataof("factor"))
        }
    }

    func generateTexture(datas: const [..] u8, w, h: s32)->GLuint
    {
        Debug.assert(@countof(datas) <= 8 * 8)

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

        #[Swag.Complete]
        switch bm
        {
        case Copy:
            glDisable(GL_BLEND)
        case Alpha:
            glEnable(GL_BLEND)
            glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
            glBlendEquation(GL_FUNC_ADD)
        case Add:
            glEnable(GL_BLEND)
            glBlendFunc(GL_ONE, GL_ONE)
            glBlendEquation(GL_FUNC_ADD)
        case Sub:
            glEnable(GL_BLEND)
            glBlendFunc(GL_ONE, GL_ONE)
            glBlendEquation(GL_FUNC_SUBTRACT)
        case SubDst:
            glEnable(GL_BLEND)
            glBlendFunc(GL_ONE, GL_ONE)
            glBlendEquation(GL_FUNC_REVERSE_SUBTRACT)
        case Min:
            glEnable(GL_BLEND)
            glBlendFunc(GL_ONE, GL_ONE)
            glBlendEquation(GL_MIN)
        case Max:
            glEnable(GL_BLEND)
            glBlendFunc(GL_ONE, GL_ONE)
            glBlendEquation(GL_MAX)
        }
    }
}

impl RenderOgl
{
    mtd opDrop()
    {
        for rt in .stackReleasedRT do
            Memory.delete(rt)
        for rt in .stackRT do
            Memory.delete(rt)
        Memory.delete(.curRT)
    }

    mtd setupHeadless()
    {
        for rt in .stackReleasedRT do
            Memory.delete(rt)
        for rt in .stackRT do
            Memory.delete(rt)
        Memory.delete(.curRT)

        .stackReleasedRT.clear()
        .stackRT.clear()
        .curRT = null
        .headlessTextures.clear()
        .headless = true
        .headlessNextHandle = 1
    }

    // To be called before rendering
    mtd begin(rc: RenderingContext)
    {
        .curRC = rc
        if .headless
        {
            .resetTransform()
            return
        }
        .native.setCurrentContext(.curRC)
        .resetTransform()
    }

    // To be called after rendering
    mtd end()
    {
        if .headless do
            return

        // The surface renders into a persistent FBO and then samples it to blit
        // onscreen, so the frame must be fully resolved and presented before we
        // return. With on-demand rendering (paint only when dirty) SwapBuffers
        // alone does not guarantee the last submitted frame is presented before
        // the next one is built, which makes hot-tracking visuals (menu/listctrl
        // highlight) lag one update behind. Flush + finish keeps the swap chain
        // in lockstep with what was just drawn.
        glFlush()
        glFinish()
        .native.swapBuffers(.curRC)
    }

    // Set the current rendering context
    mtd setCurrentContext(rc: RenderingContext)
    {
        if .headless
        {
            .curRC = rc
            return
        }
        .native.setCurrentContext(rc)
    }

    // Clear current render buffers
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd clear()
    {
        if .headless
        {
            if .curRT do
                .clearHeadlessTexture(.curRT.colorBuffer, Argb.Zero)
            return
        }

        glClearStencil(0)
        glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE)
        glClearColor(0, 0, 0, 0)
        glClear(GL_COLOR_BUFFER_BIT | GL_STENCIL_BUFFER_BIT)
    }

    // Get the actual render target size
    mtd getTargetSize()->{ width, height: s32 }
    {
        if .curRT do
            return {.curRT.colorBuffer.width, .curRT.colorBuffer.height}
        return {.curRC.width, .curRC.height}
    }

    // Force the scissor
    mtd setScissorRect(rect: Math.Rectangle)
    {
        if .headless do
            return

        glEnable(GL_SCISSOR_TEST)
        let (?, h) = .getTargetSize()
        glScissor(cast(GLint) rect.x, cast(GLint) (h - rect.y - rect.height), cast(GLint) rect.width, cast(GLint) rect.height)
    }

    // Reset the scissor
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd resetScissorRect()
    {
        if .headless do
            return

        glDisable(GL_SCISSOR_TEST)
    }

    #[Warning("Wrn0006", WarningLevel.Disable)]
    internal func GLDebugMessageCallback(Source: GLenum, Type: GLenum, Id: GLuint, Severity: GLenum, Length: GLsizei, Message: const *GLchar, UserParam: const *void)
    {
        //@print(cast(cstring) (Message));
    }

    // First init
    mtd init()
    {
        if .headless
        {
            return
        }

        Font.clearCaches()

        glInitExtensions()
        .createShaders()

        //glEnable(GL_DEBUG_OUTPUT);
        //glEnable(GL_DEBUG_OUTPUT_SYNCHRONOUS);
        //glDebugMessageCallback(&GLDebugMessageCallback, null);

        glGenBuffers(1, &.vertexbuffer)
        glBindBuffer(GL_ARRAY_BUFFER, .vertexbuffer)

        // Vertex buffer layout
        var offset: const [*] u8 = null
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
    mtd bindRenderTarget(rt: *RenderTarget, vp: *Math.Rectangle = null)
    {
        Debug.assert(rt != null)
        if !rt.colorBuffer.valid do
            return
        if .curRT do
            .stackRT.add(.curRT)
        .curRT            = rt
        .curRT.paintAlpha = false

        if .headless do
            return

        glBindFramebuffer(GL_FRAMEBUFFER, cast(GLuint) .curRT.handle)
        if vp do
            glViewport(cast() vp.x, cast() vp.y, cast() vp.width, cast() vp.height)
        else do
            glViewport(0, 0, .curRT.colorBuffer.width, .curRT.colorBuffer.height)
    }

    // Get current render target pixels
    mtd unbindRenderTargetToImage(x, y, w, h: s32)->Image
    {
        if .headless
        {
            var result: retval = Image.create(.curRT.colorBuffer.width, .curRT.colorBuffer.height, .curRT.colorBuffer.pf, .getTexturePixels(.curRT.colorBuffer, .curRT.colorBuffer.pf).toSlice())
            result.crop(x, y, w, h)
            .unbindRenderTarget()
            return result
        }

        var result: retval = Image.create(w, h, .BGRA8)
        glReadBuffer(GL_COLOR_ATTACHMENT0)
        glReadPixels(x, .curRT.colorBuffer.height - h - y, w, h, GL_BGRA, GL_UNSIGNED_BYTE, result.pixels.buffer)
        .unbindRenderTarget()
        return result
    }

    // Go back to the previous render target, or frame buffer
    mtd unbindRenderTarget()
    {
        if .stackRT.count
        {
            .curRT = .stackRT.popBack()
            if .headless do
                return
            glBindFramebuffer(GL_FRAMEBUFFER, cast(GLuint) .curRT.handle)
            glViewport(0, 0, .curRT.colorBuffer.width, .curRT.colorBuffer.height)
        }
        else
        {
            .curRT = null
            if .headless do
                return
            glBindFramebuffer(GL_FRAMEBUFFER, 0)
            glViewport(0, 0, .curRC.width, .curRC.height)
        }
    }

    // Create a render target
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd createRenderTarget(w, h: s32)->RenderTarget
    {
        if .headless
        {
            var result: retval
            result.handle             = cast(RenderTargetHandle) .headlessNextHandle
            .headlessNextHandle += 1
            result.colorBuffer.handle = cast(TextureHandle) .headlessNextHandle
            .headlessNextHandle += 1
            result.colorBuffer.width  = w
            result.colorBuffer.height = h
            result.colorBuffer.valid  = true
            result.colorBuffer.pf     = .BGRA8
            .addHeadlessTexture(result.colorBuffer, null)
            return result
        }

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
        result.handle             = cast(RenderTargetHandle) fbo
        result.colorBuffer.handle = cast(TextureHandle) colorID
        result.colorBuffer.width  = w
        result.colorBuffer.height = h
        result.colorBuffer.valid  = true
        result.colorBuffer.pf     = .RGBA8
        result.depthStencil       = cast() rbo
        return result
    }

    // Delete a render target
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd deleteRenderTarget(rt: *RenderTarget)
    {
        if rt.handle == InvalidRenderTargetHandle or !rt.colorBuffer.valid do
            return

        if .headless
        {
            .removeHeadlessTexture(rt.colorBuffer.handle)
            rt.handle            = InvalidRenderTargetHandle
            rt.depthStencil      = InvalidRenderTargetSurfaceHandle
            rt.colorBuffer.valid = false
            return
        }

        var cb: GLuint = cast() rt.colorBuffer.handle
        glDeleteTextures(1, &cb)

        var ds: GLuint = cast() rt.depthStencil
        glDeleteRenderbuffers(1, &ds)

        var fb: GLuint = cast() rt.handle
        glDeleteFramebuffers(1, &fb)

        rt.handle            = InvalidRenderTargetHandle
        rt.depthStencil      = InvalidRenderTargetSurfaceHandle
        rt.colorBuffer.valid = false
    }

    // Load and register an image for rendering
    mtd addImage(fullName: string)->Texture throw
    {
        return .addImage(Image.load(fullName))
    }

    // Register an image for rendering
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd addImage(image: Image)->Texture
    {
        if !image.isValid()
        {
            var result: Texture
            result.handle = InvalidTextureHandle
            result.pf     = .RGBA8
            result.width  = 0
            result.height = 0
            result.valid  = false
            return result
        }

        if .headless
        {
            var result: retval
            result.handle = cast(TextureHandle) .headlessNextHandle
            .headlessNextHandle += 1
            result.width  = image.width
            result.height = image.height
            result.pf     = image.pf
            result.valid  = true
            .addHeadlessTexture(result, image.pixels.toSlice())
            return result
        }

        var fmt:      GLenum = 0
        var tinternal = GL_RGB

        #[Swag.Complete]
        switch image.pf
        {
        case BGR8:
            fmt = GL_BGR
        case BGRA8:
            fmt       = GL_BGRA
            tinternal = GL_RGBA
        case RGB8:
            fmt = GL_RGB
        case RGBA8:
            fmt       = GL_RGBA
            tinternal = GL_RGBA
        }

        var textureID: GLuint
        glGenTextures(1, &textureID)
        glBindTexture(GL_TEXTURE_2D, textureID)
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
        glTexImage2D(GL_TEXTURE_2D, 0, tinternal, cast(s32) image.width, cast(s32) image.height, 0, fmt, GL_UNSIGNED_BYTE, image.pixels.buffer)

        var result: retval
        result.handle = cast(TextureHandle) textureID
        result.width  = image.width
        result.height = image.height
        result.pf     = image.pf
        result.valid  = true
        return result
    }

    func pixelFormatToNative(pf: PixelFormat)->GLenum
    {
        #[Swag.Complete]
        switch pf
        {
        case BGR8:
            return GL_BGR
        case BGRA8:
            return GL_BGRA
        case RGB8:
            return GL_RGB
        case RGBA8:
            return GL_RGBA
        }

        return GL_RGBA
    }

    // Update content of texture
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd updateTexture(texture: Texture, pixels: const *u8)
    {
        if .headless
        {
            let storage = .findHeadlessTexture(texture.handle)
            if !storage do
                return
            Memory.copy(storage.pixels.buffer, pixels, Math.min(storage.pixels.count, cast(u64) texture.getByteSize()))
            return
        }

        let fmt       = pixelFormatToNative(texture.pf)
        let textureID = cast(GLuint) texture.handle
        glBindTexture(GL_TEXTURE_2D, textureID)
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, cast(s32) texture.width, cast(s32) texture.height, fmt, GL_UNSIGNED_BYTE, pixels)
    }

    // Returns the pixels associated to a texture
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd getTexturePixels(texture: Texture, pf: PixelFormat)->Array'u8
    {
        var result: retval
        if .headless
        {
            if !texture.valid do
                return result

            result.resize(cast(u64) texture.getByteSize())
            let storage = .findHeadlessTexture(texture.handle)
            if storage do
                Memory.copy(result.buffer, storage.pixels.buffer, Math.min(result.count, storage.pixels.count))
            return result
        }

        glEnable(GL_TEXTURE_2D)
        glBindTexture(GL_TEXTURE_2D, cast() texture.handle)
        result.resize(cast(u64) texture.getByteSize())
        let fmt = pixelFormatToNative(pf)
        glGetTexImage(GL_TEXTURE_2D, 0, fmt, GL_UNSIGNED_BYTE, result.buffer)
        glDisable(GL_TEXTURE_2D)
        return result
    }

    // Unregister a texture created with 'addImage'
    #[Warning("Wrn0006", WarningLevel.Disable)]
    mtd removeTexture(texture: *Texture)
    {
        if !texture.valid do
            return
        if .headless
        {
            .removeHeadlessTexture(texture.handle)
            texture.valid = false
            return
        }
        glDeleteTextures(1, cast(*GLuint) &texture.handle)
        texture.valid = false
    }

    // Translate the world transform
    mtd translateTransform(x, y: f32)
    {
        let tr = Transform2.createTranslation(x, y)
        .worldTransform.multiply(tr)
    }

    // Rotate the world transform
    mtd rotateTransform(angle: Math.Angle)
    {
        let tr = Transform2.createRotation(angle.rad, 0, 0)
        .worldTransform.multiply(tr)
    }

    // Rotate the world transform
    mtd rotateTransform(angle: Math.Angle, centerX, centerY: f32)
    {
        let tr = Transform2.createRotation(angle.rad, centerX, centerY)
        .worldTransform.multiply(tr)
    }

    // Scale the world transform
    mtd scaleTransform(x, y: f32)
    {
        let tr = Transform2.createScale(x, y, 0, 0)
        .worldTransform.multiply(tr)
    }

    // Scale the world transform
    mtd scaleTransform(x: f32)
    {
        let tr = Transform2.createScale(x, x, 0, 0)
        .worldTransform.multiply(tr)
    }

    // Reset the world transform
    mtd resetTransform()
    {
        .worldTransform.setIdentity()
        .modelMatrix.setIdentity()
    }

    mtd computeMatrices(mvp, mdl: ShaderParamHandle)
    {
        let (width, height) = .getTargetSize()

        // View, ortho projection
        .orthoMatrix = ortho(cast(f32) height, 0, 0, cast(f32) width, 0, 1.0)
        glUniformMatrix4fv(cast(GLint) mvp, 1, GL_FALSE, &.orthoMatrix.m[0, 0])
        glViewport(0, 0, width, height)

        // Draw matrix
        .buildModelMatrix(Transform2.Identity)
        glUniformMatrix4fv(cast(GLint) mdl, 1, GL_FALSE, &.modelMatrix.m[0, 0])
    }

    private mtd executeCommand(dc: *Painter, cmd: Pixel.Command, cmdIdx: u64, width, height: s32)
    {
        switch cmd.id
        {
        case SetBlendingMode:
            let params = &cmd.blendingMode
            .setBlendingMode(params.mode)

        case Clear:
            let params = &cmd.clear
            let (a, r, g, b) = params.color.toArgbf()
            glClearColor(r, g, b, a)
            glClear(GL_COLOR_BUFFER_BIT | GL_STENCIL_BUFFER_BIT)

        case ColorMask:
            let params = &cmd.colorMask
            glColorMask(params.r ? GL_TRUE : GL_FALSE, params.g ? GL_TRUE : GL_FALSE, params.b ? GL_TRUE : GL_FALSE, params.a ? GL_TRUE : GL_FALSE)

        case Transform:
            let params = &cmd.transform
            .buildModelMatrix(params.tr)
            glUniformMatrix4fv(cast(GLint) .curShader.mdl, 1, GL_FALSE, &.modelMatrix.m[0, 0])

        case StartClippingRegion:
            glEnable(GL_STENCIL_TEST)
            glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE)
            glStencilFunc(GL_ALWAYS, 1, 0xFF)
            fallthrough

        case SetClippingRegionMode:
            let params = &cmd.clippingRegion
            let mode   = params.mode == .Set ? GL_REPLACE : cast(GLenum) GL_ZERO
            glStencilOp(mode, mode, mode)

        case EndClippingRegion:
            glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_FALSE)
            glStencilFunc(GL_EQUAL, 1, 0xFF)
            glStencilOp(GL_KEEP, GL_KEEP, GL_KEEP)

        case ResetClippingRegion:
            glDisable(GL_STENCIL_TEST)

        case SetClippingRect:
            let params = &cmd.clippingRect
            glEnable(GL_SCISSOR_TEST)
            glScissor(cast(GLint) params.rect.x, cast(GLint) (height - params.rect.y - params.rect.height), cast(GLint) params.rect.width, cast(GLint) params.rect.height)

        case ResetClippingRect:
            glDisable(GL_SCISSOR_TEST)

        case StartNoOverlap:
            .overlapMode = true

        case StopNoOverlap:
            .overlapMode = false
            .setBlendingMode(.blendingMode)

        case DrawTriangles:
            let params = &cmd.drawTriangles
            if !.overlapMode
            {
                glDrawArrays(GL_TRIANGLES, cast(GLint) params.start, cast(GLsizei) params.count)
            }
            else
            {
                // Fresh start on alpha. Clear all
                glDisable(GL_BLEND)
                glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_TRUE)
                glClearColor(0, 0, 0, 0)
                glClear(GL_COLOR_BUFFER_BIT)

                // First we mark the alpha buffer with the 'maximum' alpha to paint.
                // If a pixel is drawn twice because of overlapping, we will have the 'most opaque'
                glEnable(GL_BLEND)
                glBlendFunc(GL_SRC_ALPHA, GL_ZERO)
                glBlendEquation(GL_MAX)
                glDrawArrays(GL_TRIANGLES, cast(GLint) params.start, cast(GLsizei) params.count)

                // Then we use the stored alpha as the blend factor.
                // When a pixel is drawn once, the alpha value will be reset to 0, so this means that
                // the second overlapping pixel (if there's one) will not be written.
                glBlendFuncSeparate(GL_DST_ALPHA, GL_ONE_MINUS_DST_ALPHA, GL_ZERO, GL_ZERO)
                glBlendEquation(GL_FUNC_ADD)
                glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE)
                glDrawArrays(GL_TRIANGLES, cast(GLint) params.start, cast(GLsizei) params.count)
                glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_FALSE)
            }

        case StartFont:
            .setShader(&.shaderFont)
        case StartMsdfFont:
            .setShader(&.shaderFontMsdf)
        case EndFont:
            .setShader(&.shaderAA)

        case BindTextureFont:
            let params = &cmd.textureFont
            let cache  = params.font.cache
            // Distance-field atlases are mipmapped: trilinear minification fixes the
            // undersampling that wrecks a minified MSDF at arbitrary scale ratios.
            let isDF   = cache.renderMode.isDistanceField()
            let magF   = isDF ? GL_LINEAR : GL_NEAREST
            let minF   = isDF ? GL_LINEAR_MIPMAP_LINEAR : GL_NEAREST
            glActiveTexture(GL_TEXTURE1)
            let texture = cache.atlases[params.atlasIndex].texture.handle
            glBindTexture(GL_TEXTURE_2D, cast(GLuint) texture)
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, magF)
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, minF)

        case ResetTextureFont:
            glActiveTexture(GL_TEXTURE1)
            glBindTexture(GL_TEXTURE_2D, .whiteTexture)

        case UpdateFont:
            let cache = cmd.font.fontRef.cache
            // Mipmapped trilinear minification for distance-field atlases (see BindTextureFont).
            let isDF  = cache.renderMode.isDistanceField()
            let magF  = isDF ? GL_LINEAR : GL_NEAREST
            let minF  = isDF ? GL_LINEAR_MIPMAP_LINEAR : GL_NEAREST
            cache.dirty = false
            glActiveTexture(GL_TEXTURE1)
            let bpp = cache.renderMode.bytesPerPixel()
            let fmt = bpp == 1 ? GL_RED : (bpp == 4 ? GL_RGBA : GL_RGB)
            for &atlas in cache.atlases
            {
                if !atlas.dirty do
                    continue
                atlas.dirty = false

                atlas.texture.width  = atlas.width / atlas.bpp
                atlas.texture.height = atlas.height
                atlas.texture.pf     = atlas.bpp == 3 ? .RGB8 : .RGBA8

                // An atlas keeps fixed dimensions for its whole life, so allocate the
                // texture storage once and stream new glyphs in with glTexSubImage2D.
                // Re-uploading with glTexImage2D every time a glyph is appended forces
                // the driver to reallocate and synchronize, which stalls the frame and
                // is felt as a series of hitches while a font warms up its glyphs.
                let isNew = atlas.texture.handle == InvalidTextureHandle
                if isNew do
                    glGenTextures(1, cast(*GLuint) &atlas.texture.handle)
                glBindTexture(GL_TEXTURE_2D, cast(GLuint) atlas.texture.handle)
                glPixelStorei(GL_UNPACK_ALIGNMENT, 1)

                if isNew
                {
                    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
                    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
                    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, magF)
                    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, minF)
                    glTexImage2D(GL_TEXTURE_2D, 0, fmt, cast(GLsizei) atlas.texture.width, cast(GLsizei) atlas.texture.height, 0, fmt, GL_UNSIGNED_BYTE, atlas.datas.buffer)
                }
                else do
                    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, cast(GLsizei) atlas.texture.width, cast(GLsizei) atlas.texture.height, fmt, GL_UNSIGNED_BYTE, atlas.datas.buffer)

                // Build the mip chain for distance-field atlases. Each glyph keeps a
                // 'spread'-texel margin, so low mips do not bleed neighbouring glyphs.
                if isDF do
                    glGenerateMipmap(GL_TEXTURE_2D)
            }

        case ResetTexture0:
            glUniform1f(cast(GLint) .curShader.paintType, cast(GLfloat) cast(u32) BrushType.SolidColor)
            glUniform1f(cast(GLint) .curShader.uvMode, cast(GLfloat) cast(u32) UVMode.Fill)
            glUniform1f(cast(GLint) .curShader.interpolationMode, cast(GLfloat) cast(u32) InterpolationMode.Pixel)
            glUniform1i(cast(GLint) .curShader.gradientCount, 0)
            glActiveTexture(GL_TEXTURE0)
            glBindTexture(GL_TEXTURE_2D, .whiteTexture)

        case BindTexture0:
            let params = &cmd.texture0
            glUniform4fv(cast(GLint) .curShader.boundRect, 1, &params.boundRect.x)
            glUniform4fv(cast(GLint) .curShader.textureRect, 1, &params.textureRect.x)
            glUniform1f(cast(GLint) .curShader.uvMode, cast(GLfloat) params.uvMode)
            glUniform1f(cast(GLint) .curShader.interpolationMode, cast(GLfloat) params.interpolationMode)
            glUniform1i(cast(GLint) .curShader.copyMode, cast(GLint) (.blendingMode == .Copy))
            glUniform1f(cast(GLint) .curShader.paintType, cast(GLfloat) cast(u32) params.type)
            glActiveTexture(GL_TEXTURE0)

            #[Swag.Complete]
            switch params.type
            {
            case SolidColor:
                glBindTexture(GL_TEXTURE_2D, .whiteTexture)
                glUniform1i(cast(GLint) .curShader.gradientCount, 0)
            case Texture:
                glBindTexture(GL_TEXTURE_2D, cast(GLuint) params.texture.handle)
                glUniform1f(cast(GLint) .curShader.textureW, cast(GLfloat) params.texture.width)
                glUniform1f(cast(GLint) .curShader.textureH, cast(GLfloat) params.texture.height)
                glUniform1i(cast(GLint) .curShader.gradientCount, 0)
            case Hatch:
                glBindTexture(GL_TEXTURE_2D, .hatchTextures[params.hatch])
                glUniform1i(cast(GLint) .curShader.gradientCount, 0)
            case LinearGradient, RadialGradient, SweepGradient:
                glBindTexture(GL_TEXTURE_2D, .whiteTexture)
                glUniform1f(cast(GLint) .curShader.gradientSpread, cast(GLfloat) cast(u32) params.gradientSpread)
                glUniform2f(cast(GLint) .curShader.gradientStart, cast(GLfloat) params.gradientStart.x, cast(GLfloat) params.gradientStart.y)
                glUniform2f(cast(GLint) .curShader.gradientEnd, cast(GLfloat) params.gradientEnd.x, cast(GLfloat) params.gradientEnd.y)
                glUniform2f(cast(GLint) .curShader.gradientRadius, cast(GLfloat) params.gradientRadius0, cast(GLfloat) params.gradientRadius1)
                glUniform2f(cast(GLint) .curShader.gradientAngles, cast(GLfloat) params.gradientAngle0, cast(GLfloat) params.gradientAngle1)
                glUniform1i(cast(GLint) .curShader.gradientCount, cast(GLint) params.gradientStopCount)

                var offsets: [MaxGradientStops] f32
                var colors:  [MaxGradientStops] Vector4
                for i in params.gradientStopCount
                {
                    offsets[i] = params.gradientStops[i].offset
                    colors[i]  = params.gradientStops[i].color.toVector4()
                }

                glUniform1fv(cast(GLint) .curShader.gradientOffsets, cast(GLsizei) params.gradientStopCount, &offsets[0])
                glUniform4fv(cast(GLint) .curShader.gradientColors, cast(GLsizei) params.gradientStopCount, &colors[0].x)
            }

            #[Swag.Complete]
            switch params.uvMode
            {
            case Fill, FillSubRect:
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
            case Tile:
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT)
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT)
            }

            #[Swag.Complete]
            switch params.interpolationMode
            {
            case Pixel:
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST)
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
            case Linear:
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
            }

        case BindRenderTarget:
            .bindRenderTarget(cmd.renderTgt.tgt)
            .curRT.paintAlpha    = cmd.renderTgt.paintAlpha
            .curRT.paintAlphaIdx = cmdIdx
            .computeMatrices(.curShader.mvp, .curShader.mdl)

        case UnbindRenderTarget:
            Debug.assert(.curRT != null)

            if .curRT.paintAlpha
            {
                glEnable(GL_BLEND)
                glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_TRUE)
                glClearColor(0, 0, 0, 0)
                glClear(GL_COLOR_BUFFER_BIT)
                glBlendFunc(GL_SRC_ALPHA, GL_ZERO)
                glBlendEquation(GL_MAX)

                for var i = .curRT.paintAlphaIdx; i < cmdIdx; i += 1
                {
                    let cmd1 = dc.commandBuffer[i]
                    switch cmd1.id
                    {
                    case Transform, StartFont, StartMsdfFont, EndFont, ResetTexture0, BindTexture0, ResetTextureFont, BindTextureFont, SetFontEffect, DrawTriangles:
                        .executeCommand(dc, cmd1, cast(u64) i, width, height)
                    }
                }
            }

            .unbindRenderTarget()
            .computeMatrices(.curShader.mvp, .curShader.mdl)

        case ReleaseRenderTarget:
            .releaseRenderTarget(cmd.renderTgt.tgt)

        case SetShader:
            let params = &cmd.shader
            .setShader(params.shader)

        case SetShaderParam:
            let params = &cmd.shaderParam
            switch params.type
            {
            case s32:
                glUniform1i(cast(GLint) params.param, params._s32)
            case f32:
                glUniform1f(cast(GLint) params.param, params._f32)
            default:
                Debug.assert(false)
            }

        case SetFontEffect:
            // Always emitted right after StartMsdfFont, so the MSDF font program is
            // the active one and these uniforms land on it.
            let p = &cmd.fontEffect
            let s = &.shaderFontMsdf
            let oc = p.outlineColor.toVector4()
            let gc = p.glowColor.toVector4()
            glUniform1f(cast(GLint) s.fxEnabled,      p.enabled)
            glUniform1f(cast(GLint) s.fxFaceDilate,   p.faceDilate)
            glUniform1f(cast(GLint) s.fxFaceSoftness, p.faceSoftness)
            glUniform1f(cast(GLint) s.fxOutlineWidth, p.outlineWidth)
            glUniform4fv(cast(GLint) s.fxOutlineColor, 1, &oc.x)
            glUniform4fv(cast(GLint) s.fxGlowColor, 1, &gc.x)
            glUniform1f(cast(GLint) s.fxGlowOffset,   p.glowOffset)
            glUniform1f(cast(GLint) s.fxGlowInner,    p.glowInner)
            glUniform1f(cast(GLint) s.fxGlowOuter,    p.glowOuter)
            glUniform1f(cast(GLint) s.fxGlowPower,    p.glowPower)
            glUniform1f(cast(GLint) s.fxBevel,        p.bevel)
        }
    }

    // Draw the given painter
    mtd draw(dc: *Painter)
    {
        if .headless
        {
            for cmd in dc.commandBuffer
            {
                switch cmd.id
                {
                case Clear:
                    if .curRT do
                        .clearHeadlessTexture(.curRT.colorBuffer, cmd.clear.color)
                case BindRenderTarget:
                    .bindRenderTarget(cmd.renderTgt.tgt)
                    if .curRT
                    {
                        .curRT.paintAlpha    = cmd.renderTgt.paintAlpha
                        .curRT.paintAlphaIdx = 0
                    }
                case UnbindRenderTarget:
                    if .curRT do
                        .unbindRenderTarget()
                case ReleaseRenderTarget:
                    .releaseRenderTarget(cmd.renderTgt.tgt)
                default:
                    continue
                }
            }
            return
        }

        let (width, height) = .getTargetSize()
        if width <= 0 or height <= 0 do
            return

        glBindBuffer(GL_ARRAY_BUFFER, .vertexbuffer)
        // The vertex buffer is fully rebuilt and re-uploaded every frame, so hint
        // GL_STREAM_DRAW (write once, draw once) instead of GL_STATIC_DRAW. Orphan
        // the previous storage first so the driver can hand back fresh memory rather
        // than blocking until the in-flight draw releases the old buffer.
        let byteSize = dc.vertexBuffer.count * #sizeof(VertexLayout)
        glBufferData(GL_ARRAY_BUFFER, byteSize, null, GL_STREAM_DRAW)
        glBufferData(GL_ARRAY_BUFFER, byteSize, dc.vertexBuffer.buffer, GL_STREAM_DRAW)

        // Default shader
        .setShader(&.shaderAA)
        .computeMatrices(.curShader.mvp, .curShader.mdl)

        // Default state
        glDisable(GL_SCISSOR_TEST)
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
        glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_FALSE)

        for i in 4 do
            glEnableVertexAttribArray(cast(GLuint) i)
        for cmd, cmdIdx in dc.commandBuffer do
            .executeCommand(dc, cmd, cmdIdx, width, height)
        for i in 4 do
            glDisableVertexAttribArray(cast(GLuint) i)
    }

    // Set the current shader
    mtd setShader(shader: *ShaderBase = null)
    {
        if .headless
        {
            .curShader = shader orelse &.shaderAA
            return
        }

        .curShader = shader orelse &.shaderAA
        glUseProgram(cast(GLuint) .curShader.handle)
        glUniformMatrix4fv(cast(GLint) .curShader.mvp, 1, GL_FALSE, &.orthoMatrix.m[0, 0])
        glUniformMatrix4fv(cast(GLint) .curShader.mdl, 1, GL_FALSE, &.modelMatrix.m[0, 0])
    }

    // Get a render target of the given size
    // releaseRenderTarget must be called to release it
    mtd getRenderTarget(w, h: s32)->*RenderTarget
    {
        let w2 = Math.roundUpToPowerOf2(cast(u32) w)
        let h2 = Math.roundUpToPowerOf2(cast(u32) h)

        for rt, i in .stackReleasedRT
        {
            if rt.colorBuffer.width == w2 and rt.colorBuffer.height == h2
            {
                .stackReleasedRT.removeAt(i)
                return rt
            }
        }

        for rt, i in .stackReleasedRT
        {
            if rt.colorBuffer.width >= w2 and rt.colorBuffer.height >= h2
            {
                .stackReleasedRT.removeAt(i)
                return rt
            }
        }

        var rt = Memory.new'RenderTarget()
        dref rt = .createRenderTarget(cast(s32) w2, cast(s32) h2)
        return rt
    }

    // Release the given render target
    mtd releaseRenderTarget(tgt: *RenderTarget)
    {
        .stackReleasedRT.add(tgt)
    }

    // Create the given shader
    func createShader(base: *ShaderBase, vertex, pixel: const [..] u8) throw
    {
        var buf: String = @mkstring(@dataof(vertex), @countof(vertex))
        buf.replace("#include base", @mkstring(@dataof(BaseVertexShader), @countof(BaseVertexShader)))

        let vertexShaderID      = glCreateShader(GL_VERTEX_SHADER)
        var vertexSourcePointer = buf.buffer
        var vertexSourceLength  = cast(GLint) buf.length
        glShaderSource(vertexShaderID, 1, &vertexSourcePointer, &vertexSourceLength)
        glCompileShader(vertexShaderID)
        try setShaderCompileError(vertexShaderID)

        buf = @mkstring(@dataof(pixel), @countof(pixel))
        buf.replace("#include base", @mkstring(@dataof(BasePixelShader), @countof(BasePixelShader)))

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

        base.mvp         = cast() glGetUniformLocation(progID, @dataof("mvp"))
        base.mdl         = cast() glGetUniformLocation(progID, @dataof("mdl"))
        base.boundRect         = cast() glGetUniformLocation(progID, @dataof("boundRect"))
        base.textureRect       = cast() glGetUniformLocation(progID, @dataof("textureRect"))
        base.uvMode            = cast() glGetUniformLocation(progID, @dataof("uvMode"))
        base.interpolationMode = cast() glGetUniformLocation(progID, @dataof("interpolationMode"))
        base.copyMode          = cast() glGetUniformLocation(progID, @dataof("copyMode"))
        base.textureW          = cast() glGetUniformLocation(progID, @dataof("textureW"))
        base.textureH          = cast() glGetUniformLocation(progID, @dataof("textureH"))
        base.paintType       = cast() glGetUniformLocation(progID, @dataof("paintType"))
        base.gradientSpread  = cast() glGetUniformLocation(progID, @dataof("gradientSpread"))
        base.gradientStart   = cast() glGetUniformLocation(progID, @dataof("gradientStart"))
        base.gradientEnd     = cast() glGetUniformLocation(progID, @dataof("gradientEnd"))
        base.gradientRadius  = cast() glGetUniformLocation(progID, @dataof("gradientRadius"))
        base.gradientAngles  = cast() glGetUniformLocation(progID, @dataof("gradientAngles"))
        base.gradientCount   = cast() glGetUniformLocation(progID, @dataof("gradientCount"))
        base.gradientOffsets = cast() glGetUniformLocation(progID, @dataof("gradientOffsets[0]"))
        base.gradientColors  = cast() glGetUniformLocation(progID, @dataof("gradientColors[0]"))
    }
}
