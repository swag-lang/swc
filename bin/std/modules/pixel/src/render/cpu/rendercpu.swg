#global public

using Swag, Core, Core.Math

// Executes [[Pixel.Painter]] command streams into deterministic CPU-owned pixel buffers.
//
// A CPU renderer owns every texture and render target it creates. It needs no native window,
// graphics context, or GPU driver. Call [[Pixel.RenderCpu.begin]], record and submit a painter,
// then read the surface or an off-screen target back as an [[Pixel.Image]].
//
// Every renderer-independent painter operation, including MSDF font effects, blur, and
// supersampling resolve, is interpreted directly. Custom OpenGL shaders remain specific to
// [[Pixel.RenderOgl]] and are a programmer error when submitted to this backend.
#[Swag.NoCopy]
struct RenderCpu
{
    // Glyph storage and font views owned by this renderer.
    public fonts: FontCache

    private
    {
        nextHandle: u64 = 1
        textures:   Array'CpuTexture

        surface: Image

        stackReleasedRT: Array'#null *RenderTarget
        stackRT:         Array'#null *RenderTarget
        curRT:           #null *RenderTarget

        worldTransform: Transform2 = Transform2.Identity
        modelTransform: Transform2 = Transform2.Identity
        contentScale:   f32        = 1     // Device pixels per unit of the painter stream being drawn.

        scissorOn:   bool
        scissorRect: Math.Rectangle

        blendingMode: BlendingMode = Alpha
        colorMask:    ColorMask    = {true, true, true, false}

        paintCommand:  Command = undefined
        gradientStops: #null const [..] GradientStop
        paintOn:       bool
        program:       u8

        surfaceStencil: Array'u8
        stencilOn:      bool
        stencilWrite:   bool
        stencilMode:    ClippingMode = Set

        font:           #null *Font
        fontAtlasIndex: s32 = -1
        fontEffect:     FontEffectParams
        overlapMode:    bool
        overlapPass:    u8
        overlapAlpha:   Array'u8
        overlapWritten: Array'u8
        alphaResolve:   bool

        blurAxis:      s32
        blurRadius:    f32 = 4
        resolveFactor: s32 = 1
    }
}

// Dependency-visible backing type required by the concrete [[Pixel.RenderCpu]] layout.
#[Swag.Opaque, Swag.NoDoc]
struct CpuTexture
{
    public
    {
        handle:  TextureHandle
        image:   Image
        stencil: Array'u8
    }
}

// Inclusive device-pixel rectangle a draw batch can touch inside its target.
private struct PixelBounds
{
    minX: s32
    minY: s32
    maxX: s32
    maxY: s32
}

private impl PixelBounds
{
    // Reports whether the rectangle covers no pixel at all.
    mtd const isEmpty()->bool => .minX > .maxX or .minY > .maxY

    // Returns the number of pixel rows the rectangle spans.
    mtd const rows()->s32 => .maxY - .minY + 1

    // Returns the number of pixels the rectangle spans.
    mtd const area()->u64 => cast(u64) (.maxX - .minX + 1) * cast(u64) .rows()
}

private
{
    // Pixel area below which splitting a batch into bands costs more than the rasterization saves.
    const CpuBandPixelThreshold: u64 = 64 * 1024

    // Rows a band must carry for scheduling it to be worth a job.
    const CpuBandMinRows: s32 = 16

    const CpuProgram_Default: u8 = 0
    const CpuProgram_Simple:  u8 = 1
    const CpuProgram_Font:    u8 = 2
    const CpuProgram_Msdf:    u8 = 3
    const CpuProgram_Blur:    u8 = 4
    const CpuProgram_Resolve: u8 = 5

    // Four BGRA pixels share these byte masks in the packed span kernels.
    const CpuBgraRgbMask   = cast(Math.Simd.U8x16) [255'u8, 255, 255, 0, 255, 255, 255, 0, 255, 255, 255, 0, 255, 255, 255, 0]
    const CpuBgraAlphaMask = cast(Math.Simd.U8x16) [0'u8, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255]
    const CpuPixelLanes    = cast(Math.Simd.F32x4) [0.0'f32, 1.0, 2.0, 3.0]

    // Alpha factor of the bitmap font shader per atlas byte: pow(byte / 255, FontGamma).
    //
    // Filled at run time with the exact expression the per-pixel path evaluated, so a lookup
    // returns bit-identical factors. Initialization happens on the serial command path; two
    // renderers on two threads can only race to store the same values.
    var g_FontGammaLut:      [256] f32
    var g_FontGammaLutReady: bool
}

private func ensureFontGammaLut()
{
    if g_FontGammaLutReady do
        return
    for i in 256 do
        g_FontGammaLut[i] = Math.pow(cast(f32) i / 255.0, FontGamma)
    g_FontGammaLutReady = true
}

// Everything a triangle range resolves once, so the pixel loops read plain locals instead of
// re-deriving transforms, clips, formats, paint textures, and font atlases per pixel.
private struct RasterBatch
{
    image:     #null *Image
    painter:   #null *Painter
    start:     u32
    count:     u32
    transform: Transform2

    pixels:    [*] u8     // Target pixel base; rows are stored bottom-up.
    rowStride: s32
    width:     s32
    height:    s32

    // Device clip, target bounds and scissor folded into one inclusive pixel rectangle.
    clipMinX: s32
    clipMinY: s32
    clipMaxX: s32
    clipMaxY: s32

    stencil: [*] u8     // Stencil plane of the target, one byte per pixel, top-down rows.

    solidPaint: bool                        // The paint multiplies by opaque white, which is the identity.
    paintImage: #null *Image                // Storage of a bound texture paint, resolved once.
    atlas:      #null const *GlyphAtlas     // Glyph atlas of the bound font, resolved once.

    blurWeights:     #null const [*] f32     // Gaussian tap weights owned by the active draw call.
    blurWeightCount: u64
}

private struct FontLinearSample
{
    x0, y0, x1, y1: s32
    tx, ty:         f32
}

private impl RenderCpu
{
    mtd findTexture(handle: TextureHandle)->#null *CpuTexture
    {
        for &texture in .textures where texture.handle == handle do
            return texture
        return null
    }

    mtd removeTextureStorage(handle: TextureHandle)
    {
        for texture, idx in .textures where texture.handle == handle
        {
            .textures.removeAt(idx)
            return
        }
    }

    mtd currentImage()->#null *Image
    {
        if .curRT
        {
            let texture = .findTexture(.curRT.colorBuffer.handle)
            if texture do
                return &texture.image
            return null
        }

        if .surface.isValid() do
            return &.surface
        return null
    }

    mtd currentStencil()->*Array'u8
    {
        if .curRT
        {
            let texture = .findTexture(.curRT.colorBuffer.handle)!
            return &texture.stencil
        }

        return &.surfaceStencil
    }

    mtd ensureSurface(width, height: s32)
    {
        if width <= 0 or height <= 0 do
            return
        if .surface.isValid() and .surface.width == width and .surface.height == height do
            return

        .surface = Image.create(width, height, .BGRA8)
        .surface.clear()
    }

    mtd ensureStencil(width, height: s32)
    {
        let count   = cast(u64) width * cast(u64) height
        let stencil = .currentStencil()
        if stencil.count == count do
            return
        stencil.resize(count)
        Memory.clear(stencil.buffer!, count)
    }

    // Returns the transform mapping painter-stream positions to device pixels.
    //
    // The content scale is applied last, so positions and translations scale alike
    // (see RenderOgl.buildModelMatrix).
    mtd deviceTransform()->Transform2
    {
        var result = .worldTransform
        result.multiply(.modelTransform)
        if .contentScale != 1 do
            result.multiply(Transform2.createScale(.contentScale, .contentScale, 0, 0))
        return result
    }

    // Returns the pixels a triangle range can touch, clipped to the target and the scissor.
    //
    // Rounding matches [[Pixel.RenderCpu.drawTriangle]] exactly, so the result is a superset of
    // the pixels the range actually shades. It bounds the scratch resets of the overlap passes
    // and the band split of the parallel rasterizer.
    mtd triangleRangeBounds(image: *Image, painter: *Painter, start, count: u32)->PixelBounds
    {
        let transform = .deviceTransform()

        var lowest  = Vector2.Max
        var highest = Vector2.NegMax
        for var i = start; i < start + count; i += 1
        {
            let p = transform.transformPoint(painter.vertexBuffer[i].pos)
            lowest.x  = Math.min(lowest.x, p.x)
            lowest.y  = Math.min(lowest.y, p.y)
            highest.x = Math.max(highest.x, p.x)
            highest.y = Math.max(highest.y, p.y)
        }

        var result: retval
        result.minX = Math.clamp(cast(s32) Math.floor(lowest.x), 0, image.width - 1)
        result.minY = Math.clamp(cast(s32) Math.floor(lowest.y), 0, image.height - 1)
        result.maxX = Math.clamp(cast(s32) Math.ceil(highest.x) - 1, 0, image.width - 1)
        result.maxY = Math.clamp(cast(s32) Math.ceil(highest.y) - 1, 0, image.height - 1)

        if .scissorOn
        {
            result.minX = Math.max(result.minX, cast(s32) .scissorRect.x)
            result.minY = Math.max(result.minY, cast(s32) .scissorRect.y)
            result.maxX = Math.min(result.maxX, cast(s32) .scissorRect.right() - 1)
            result.maxY = Math.min(result.maxY, cast(s32) .scissorRect.bottom() - 1)
        }

        return result
    }

    // Zeroes `bounds` inside a per-pixel scratch plane stored as `width` bytes per row.
    func clearScratchRows(plane: [*] u8, width: s32, bounds: PixelBounds)
    {
        let runWidth = cast(u64) (bounds.maxX - bounds.minX + 1)
        for var y = bounds.minY; y <= bounds.maxY; y += 1 do
            Memory.clear(plane + cast(u64) y * cast(u64) width + cast(u64) bounds.minX, runWidth)
    }

    func edge(a, b, p: Vector2)->f32
    {
        return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
    }

    func isTopLeft(a, b: Vector2)->bool
    {
        let dx = b.x - a.x
        let dy = b.y - a.y
        return dy < 0 or (dy == 0 and dx > 0)
    }

    // Preserve the rounded f32 edge value at the classification boundary. Auto-inlining this
    // predicate into the raster loop changes exact-zero decisions in release mode.
    #[Swag.NoInline]
    func insideEdge(value: f32, topLeft: bool)->bool
    {
        return value > 0 or (value == 0 and topLeft)
    }

    // Returns one coverage bit per horizontal pixel while preserving the scalar top-left rule.
    func insideEdges4(edge0, edge1, edge2: Math.Simd.F32x4, edge0TopLeft, edge1TopLeft, edge2TopLeft: bool)->u32
    {
        let zero  = Math.Simd.splat(0.0'f32)
        var mask0 = edge0 > zero
        var mask1 = edge1 > zero
        var mask2 = edge2 > zero
        if edge0TopLeft do
            mask0 |= edge0 == zero
        if edge1TopLeft do
            mask1 |= edge1 == zero
        if edge2TopLeft do
            mask2 |= edge2 == zero
        return Math.Simd.bitmask(mask0 & mask1 & mask2)
    }

    func lerpColor(c0, c1: Color, t: f32)->Color
    {
        let u = Math.saturate(t)
        return Color.fromArgbF32((cast(f32) c0.a + (cast(f32) c1.a - c0.a) * u) / 255.0,
                                 (cast(f32) c0.r + (cast(f32) c1.r - c0.r) * u) / 255.0,
                                 (cast(f32) c0.g + (cast(f32) c1.g - c0.g) * u) / 255.0,
                                 (cast(f32) c0.b + (cast(f32) c1.b - c0.b) * u) / 255.0)
    }

    // Bilinear texture filtering keeps the two byte-quantizing lerps of the former float path,
    // but evaluates their weights as 16.16 integers instead of converting twelve intermediate
    // colors through normalized floats for every sampled pixel.
    func lerpByte(c0, c1: u8, weight: u32)->u8
    {
        const One = 65536'u32
        return cast(u8) ((cast(u32) c0 * (One - weight) + cast(u32) c1 * weight) >> 16)
    }

    func bilinearColor(c00, c10, c01, c11: Color, tx, ty: f32)->Color
    {
        const One = 65536.0'f32
        let wx = cast(u32) (Math.saturate(tx) * One)
        let wy = cast(u32) (Math.saturate(ty) * One)

        var top, bottom, result: Color = undefined
        top.a    = lerpByte(c00.a, c10.a, wx)
        top.r    = lerpByte(c00.r, c10.r, wx)
        top.g    = lerpByte(c00.g, c10.g, wx)
        top.b    = lerpByte(c00.b, c10.b, wx)
        bottom.a = lerpByte(c01.a, c11.a, wx)
        bottom.r = lerpByte(c01.r, c11.r, wx)
        bottom.g = lerpByte(c01.g, c11.g, wx)
        bottom.b = lerpByte(c01.b, c11.b, wx)
        result.a = lerpByte(top.a, bottom.a, wy)
        result.r = lerpByte(top.r, bottom.r, wy)
        result.g = lerpByte(top.g, bottom.g, wy)
        result.b = lerpByte(top.b, bottom.b, wy)
        return result
    }

    func modFloor(value, divisor: s32)->s32
    {
        var result = value % divisor
        if result < 0 do
            result += divisor
        return result
    }

    func readPixel(image: *Image, x, y: s32)->Color
    {
        return image.pixelColor(x, y)
    }

    // Reads one clamped BGRA8 pixel: the exact bytes [[readPixel]] returns for that format,
    // without the per-pixel format dispatch. The sampling helpers call this on every fetch of
    // a texture paint, which is most of what a themed frame rasterizes.
    func fetchBgra8(image: *Image, x, y: s32)->Color
    {
        let cx  = Math.clamp(x, 0, image.width - 1)
        let cy  = image.height - Math.clamp(y, 0, image.height - 1) - 1
        let pix = image.pixels.buffer! + cast(u64) (cx * 4) + cast(u64) cy * cast(u64) image.width * 4

        var result: Color = undefined
        result.b = pix[0]
        result.g = pix[1]
        result.r = pix[2]
        result.a = pix[3]
        return result
    }

    func writePixel(image: *Image, x, y: s32, color: Color)
    {
        let storageY = image.height - y - 1
        let pixel    = image.pixels.buffer! + cast(u64) (storageY * image.rowStride + x * image.bytesPerPixel)

        switch #complete image.pixelFormat
        {
        case .Yuv420:

            // A surface is always packed: this backend converts a planar picture on upload.
            Debug.assert(false, "cannot write one pixel of a planar picture")

        case .BGRA8:
            pixel[0] = color.b
            pixel[1] = color.g
            pixel[2] = color.r
            pixel[3] = color.a

        case .RGBA8:
            pixel[0] = color.r
            pixel[1] = color.g
            pixel[2] = color.b
            pixel[3] = color.a

        case .BGR8:
            pixel[0] = color.b
            pixel[1] = color.g
            pixel[2] = color.r

        case .RGB8:
            pixel[0] = color.r
            pixel[1] = color.g
            pixel[2] = color.b
        }
    }

    func blendSeparable(src, dst: f32, mode: BlendingMode)->f32
    {
        switch mode
        {
        case .Multiply:
            return src * dst

        case .Screen:
            return src + dst - src * dst

        case .Overlay:
            return dst <= 0.5 ? 2.0 * src * dst : 1.0 - 2.0 * (1.0 - src) * (1.0 - dst)

        case .Darken:
            return Math.min(src, dst)

        case .Lighten:
            return Math.max(src, dst)

        case .ColorDodge:
            return dst == 0 ? 0 : (src == 1 ? 1 : Math.min(1.0, dst / (1.0 - src)))

        case .ColorBurn:
            return dst == 1 ? 1 : (src == 0 ? 0 : 1.0 - Math.min(1.0, (1.0 - dst) / src))

        case .HardLight:
            return src <= 0.5 ? 2.0 * src * dst : 1.0 - 2.0 * (1.0 - src) * (1.0 - dst)

        case .SoftLight:
            if src <= 0.5 do
                return dst - (1.0 - 2.0 * src) * dst * (1.0 - dst)
            let d = dst <= 0.25 ? ((16.0 * dst - 12.0) * dst + 4.0) * dst : Math.sqrt(dst)
            return dst + (2.0 * src - 1.0) * (d - dst)

        case .Difference:
            return Math.abs(dst - src)

        case .Exclusion:
            return dst + src - 2.0 * dst * src

        default:
            return src
        }
    }

    func blendLuminosity(color: Math.Vector3)->f32 => 0.3 * color.x + 0.59 * color.y + 0.11 * color.z

    func blendSaturation(color: Math.Vector3)->f32 => Math.max(color.x, Math.max(color.y, color.z)) - Math.min(color.x, Math.min(color.y, color.z))

    func clipBlendColor(color: Math.Vector3)->Math.Vector3
    {
        let luminosity = blendLuminosity(color)
        let minValue   = Math.min(color.x, Math.min(color.y, color.z))
        let maxValue   = Math.max(color.x, Math.max(color.y, color.z))
        var result     = color

        if minValue < 0 do
            result = luminosity + (result - luminosity) * luminosity / (luminosity - minValue)
        if maxValue > 1 do
            result = luminosity + (result - luminosity) * (1.0 - luminosity) / (maxValue - luminosity)
        return result
    }

    func setBlendLuminosity(color: Math.Vector3, luminosity: f32)->Math.Vector3
    {
        return clipBlendColor(color + luminosity - blendLuminosity(color))
    }

    func setBlendSaturation(color: Math.Vector3, saturation: f32)->Math.Vector3
    {
        let currentSaturation = blendSaturation(color)
        if currentSaturation == 0 do
            return Math.Vector3.Zero

        let minValue = Math.min(color.x, Math.min(color.y, color.z))
        return (color - minValue) * saturation / currentSaturation
    }

    func blendNonSeparable(src, dst: Math.Vector3, mode: BlendingMode)->Math.Vector3
    {
        switch mode
        {
        case .Hue:        return setBlendLuminosity(setBlendSaturation(src, blendSaturation(dst)), blendLuminosity(dst))
        case .Saturation: return setBlendLuminosity(setBlendSaturation(dst, blendSaturation(src)), blendLuminosity(dst))
        case .Color:      return setBlendLuminosity(src, blendLuminosity(dst))
        case .Luminosity: return setBlendLuminosity(dst, blendLuminosity(src))
        default:          return src
        }
    }

    func blendAdvanced(src, dst: Math.Vector3, srcAlpha, dstAlpha: f32, mode: BlendingMode)->Math.Vector3
    {
        // Render targets accumulate premultiplied color under source-over blending. Recover the
        // backdrop color for the blend function, then combine the overlap, source-only, and
        // backdrop-only coverage exactly as the advanced OpenGL equations do.
        let backdrop = dstAlpha > 0 ? Math.Vector3{Math.clamp(dst.x / dstAlpha, 0.0, 1.0),
                                                   Math.clamp(dst.y / dstAlpha, 0.0, 1.0),
                                                   Math.clamp(dst.z / dstAlpha, 0.0, 1.0)} : Math.Vector3.Zero
        var blended = blendNonSeparable(src, backdrop, mode)
        if mode.isSeparable()
        {
            blended.x = blendSeparable(src.x, backdrop.x, mode)
            blended.y = blendSeparable(src.y, backdrop.y, mode)
            blended.z = blendSeparable(src.z, backdrop.z, mode)
        }

        return blended * srcAlpha * dstAlpha + src * srcAlpha * (1.0 - dstAlpha) + dst * (1.0 - srcAlpha)
    }

    func blendChannel(src, dst, srcAlpha, dstAlpha: f32, mode: BlendingMode)->f32
    {
        switch #complete mode
        {
        case .Copy:   return src
        case .Alpha:  return src * srcAlpha + dst * (1.0 - srcAlpha)
        case .Add:    return Math.min(src + dst, 1.0)
        case .Sub:    return Math.max(src - dst, 0.0)
        case .SubDst: return Math.max(dst - src, 0.0)
        case .Min:    return Math.min(src, dst)
        case .Max:    return Math.max(src, dst)
        case .DstIn:  return dst * srcAlpha
        case .Multiply, .Screen, .Overlay, .Darken, .Lighten, .ColorDodge, .ColorBurn, .HardLight, .SoftLight, .Difference, .Exclusion, .Hue, .Saturation, .Color, .Luminosity: return src
        }

        return src
    }

    // Alpha-blends one BGRA8 pixel under the default color mask.
    //
    // The arithmetic mirrors [[Pixel.RenderCpu.blendPixel]] for the 'Alpha' mode operation by
    // operation, so the stored bytes are identical; only the format dispatch, the mode switch,
    // and the mask branches are resolved away. The alpha byte stays in place, which is exactly
    // what the disabled alpha mask means, and an opaque source stores its own bytes because the
    // u8 to f32 round trip of the general path is exact.
    func blendAlphaBgra8(pixel: [*] u8, src: Color)
    {
        if src.a == 255
        {
            pixel[0] = src.b
            pixel[1] = src.g
            pixel[2] = src.r
            return
        }

        let sa   = cast(f32) src.a / 255.0
        let outR = Math.saturate((cast(f32) src.r / 255.0) * sa + (cast(f32) pixel[2] / 255.0) * (1.0 - sa))
        let outG = Math.saturate((cast(f32) src.g / 255.0) * sa + (cast(f32) pixel[1] / 255.0) * (1.0 - sa))
        let outB = Math.saturate((cast(f32) src.b / 255.0) * sa + (cast(f32) pixel[0] / 255.0) * (1.0 - sa))
        pixel[0] = cast(u8) (outB * 255)
        pixel[1] = cast(u8) (outG * 255)
        pixel[2] = cast(u8) (outR * 255)
    }

    mtd blendPixel(image: *Image, x, y: s32, src: Color)
    {
        // A zero-alpha source is coverage, not ink: the OpenGL shader discards it under
        // every mode except 'Copy', where a transparent write is the erase operation.
        if src.a == 0 and .blendingMode != .Copy do
            return

        let dst = readPixel(image, x, y)

        // OpenGL rebuilds paintAlpha targets with GL_MAX and a source-alpha blend factor.
        // Preserve that slightly unusual alpha-squared behavior so CPU and GPU resolves agree.
        if .alphaResolve
        {
            var out = dst
            let a   = cast(u8) Math.clamp(Math.round(cast(f32) src.a * cast(f32) src.a / 255.0), 0.0, 255.0)
            out.a = Math.max(out.a, a)
            writePixel(image, x, y, out)
            return
        }

        let pixelIdx = cast(u64) y * cast(u64) image.width + cast(u64) x
        if .overlapPass == 1
        {
            let a = cast(u8) Math.clamp(Math.round(cast(f32) src.a * cast(f32) src.a / 255.0), 0.0, 255.0)
            .overlapAlpha[pixelIdx] = Math.max(.overlapAlpha[pixelIdx], a)
            return
        }

        if .overlapPass == 2
        {
            if .overlapWritten[pixelIdx] != 0 do
                return
            .overlapWritten[pixelIdx] = 1

            // The first fragment consumes the maximum alpha accumulated by the mark pass;
            // subsequent overlapping fragments see zero destination alpha and contribute nothing.
            let factor = cast(f32) .overlapAlpha[pixelIdx] / 255.0
            var out    = Color.fromArgbF32(0,
                                           cast(f32) src.r / 255.0 * factor + cast(f32) dst.r / 255.0 * (1.0 - factor),
                                           cast(f32) src.g / 255.0 * factor + cast(f32) dst.g / 255.0 * (1.0 - factor),
                                           cast(f32) src.b / 255.0 * factor + cast(f32) dst.b / 255.0 * (1.0 - factor))
            writePixel(image, x, y, out)
            return
        }

        let sa = cast(f32) src.a / 255.0
        let da = cast(f32) dst.a / 255.0

        // The alpha channel composites with a source factor of one, not with the source alpha the
        // colour channels use: weighting it by itself accumulates coverage as a square, so a stack
        // of faint layers reaches almost no opacity at all. This matches the separate blend
        // function the OpenGL renderer sets, so a CPU render and a GPU render cover the same.
        var outA = blendChannel(sa, da, sa, da, .blendingMode)
        if .blendingMode == .Alpha or .blendingMode.usesAdvancedBlending() do
            outA = sa + da * (1.0 - sa)

        let srcColor = Math.Vector3{cast(f32) src.r / 255.0, cast(f32) src.g / 255.0, cast(f32) src.b / 255.0}
        let dstColor = Math.Vector3{cast(f32) dst.r / 255.0, cast(f32) dst.g / 255.0, cast(f32) dst.b / 255.0}
        var outColor = Math.Vector3{blendChannel(srcColor.x, dstColor.x, sa, da, .blendingMode),
                                    blendChannel(srcColor.y, dstColor.y, sa, da, .blendingMode),
                                    blendChannel(srcColor.z, dstColor.z, sa, da, .blendingMode)}
        if .blendingMode.usesAdvancedBlending() do
            outColor = blendAdvanced(srcColor, dstColor, sa, da, .blendingMode)

        var out = Color.fromArgbF32(outA, outColor.x, outColor.y, outColor.z)

        if !.colorMask.r do
            out.r = dst.r
        if !.colorMask.g do
            out.g = dst.g
        if !.colorMask.b do
            out.b = dst.b
        if !.colorMask.a do
            out.a = dst.a
        writePixel(image, x, y, out)
    }

    func sampleNearest(image: *Image, u, v: f32, repeat: bool)->Color
    {
        var uu = u
        var vv = v
        if repeat
        {
            uu = Math.fract(uu)
            vv = Math.fract(vv)
            if uu < 0 do
                uu += 1
            if vv < 0 do
                vv += 1
        }
        else
        {
            uu = Math.saturate(uu)
            vv = Math.saturate(vv)
        }

        let x = Math.clamp(cast(s32) Math.floor(uu * image.width), 0, image.width - 1)
        let y = Math.clamp(cast(s32) Math.floor((1.0 - vv) * image.height), 0, image.height - 1)
        if image.pixelFormat == .BGRA8 do
            return fetchBgra8(image, x, y)
        return readPixel(image, x, y)
    }

    func sampleLinear(image: *Image, u, v: f32, repeat: bool)->Color
    {
        var uu = u
        var vv = v
        if repeat
        {
            uu = Math.fract(uu)
            vv = Math.fract(vv)
            if uu < 0 do
                uu += 1
            if vv < 0 do
                vv += 1
        }
        else
        {
            uu = Math.saturate(uu)
            vv = Math.saturate(vv)
        }

        let fx = uu * image.width - 0.5
        let fy = (1.0 - vv) * image.height - 0.5
        let x0 = cast(s32) Math.floor(fx)
        let y0 = cast(s32) Math.floor(fy)
        let tx = fx - Math.floor(fx)
        let ty = fy - Math.floor(fy)

        func coord(value, size: s32, wrap: bool)->s32
        {
            if wrap do
                return modFloor(value, size)
            return Math.clamp(value, 0, size - 1)
        }

        if image.pixelFormat == .BGRA8
        {
            let f00 = fetchBgra8(image, coord(x0, image.width, repeat), coord(y0, image.height, repeat))
            let f10 = fetchBgra8(image, coord(x0 + 1, image.width, repeat), coord(y0, image.height, repeat))
            let f01 = fetchBgra8(image, coord(x0, image.width, repeat), coord(y0 + 1, image.height, repeat))
            let f11 = fetchBgra8(image, coord(x0 + 1, image.width, repeat), coord(y0 + 1, image.height, repeat))
            return bilinearColor(f00, f10, f01, f11, tx, ty)
        }

        let c00 = readPixel(image, coord(x0, image.width, repeat), coord(y0, image.height, repeat))
        let c10 = readPixel(image, coord(x0 + 1, image.width, repeat), coord(y0, image.height, repeat))
        let c01 = readPixel(image, coord(x0, image.width, repeat), coord(y0 + 1, image.height, repeat))
        let c11 = readPixel(image, coord(x0 + 1, image.width, repeat), coord(y0 + 1, image.height, repeat))
        return bilinearColor(c00, c10, c01, c11, tx, ty)
    }

    func sampleSubRect(image: *Image, paintPos: Vector2, params: const *Command, contentScale: f32)->Color
    {
        let p    = &params.texture0
        let minX = cast(s32) Math.floor(p.textureRect.x * image.width)
        let minY = cast(s32) Math.floor(p.textureRect.y * image.height)
        let maxX = cast(s32) Math.floor(p.textureRect.z * image.width)
        let maxY = cast(s32) Math.floor(p.textureRect.w * image.height)
        let dstW = Math.max(p.boundRect.z - p.boundRect.x, 0.000001)
        let dstH = Math.max(p.boundRect.w - p.boundRect.y, 0.000001)
        let tx   = Math.saturate((paintPos.x - p.boundRect.x) / dstW)
        let ty   = Math.saturate((paintPos.y - p.boundRect.y) / dstH)
        var px   = cast(f32) minX + tx * cast(f32) (maxX - minX + 1) - 0.5
        var py   = cast(f32) minY + ty * cast(f32) (maxY - minY + 1) - 0.5

        if p.interpolationMode == .Pixel and contentScale == 1
        {
            let x = Math.clamp(cast(s32) Math.floor(px + 0.5), minX, maxX)
            let y = Math.clamp(cast(s32) Math.floor(py + 0.5), minY, maxY)

            // The presentation blit runs through here for every surface pixel.
            if image.pixelFormat == .BGRA8 do
                return fetchBgra8(image, x, y)
            return readPixel(image, x, y)
        }

        px = Math.clamp(px, cast(f32) minX, cast(f32) maxX)
        py = Math.clamp(py, cast(f32) minY, cast(f32) maxY)
        let x0 = cast(s32) Math.floor(px)
        let y0 = cast(s32) Math.floor(py)
        let x1 = Math.min(x0 + 1, maxX)
        let y1 = Math.min(y0 + 1, maxY)
        var fx = px - Math.floor(px)
        var fy = py - Math.floor(py)

        // Sharp bilinear (see the OpenGL base shader): pixel mode at a fractional
        // content scale keeps one device pixel of smoothing at each texel boundary
        // instead of dropping texels or smearing one-texel tile borders.
        if p.interpolationMode == .Pixel
        {
            let texelsPerUnitX = cast(f32) (maxX - minX + 1) / dstW
            let texelsPerUnitY = cast(f32) (maxY - minY + 1) / dstH
            let wx             = Math.clamp(texelsPerUnitX / contentScale, 0.0001, 1.0)
            let wy             = Math.clamp(texelsPerUnitY / contentScale, 0.0001, 1.0)
            fx = Math.saturate((fx - 0.5) / wx + 0.5)
            fy = Math.saturate((fy - 0.5) / wy + 0.5)
        }

        if image.pixelFormat == .BGRA8
        {
            let f00 = fetchBgra8(image, x0, y0)
            let f10 = fetchBgra8(image, x1, y0)
            let f01 = fetchBgra8(image, x0, y1)
            let f11 = fetchBgra8(image, x1, y1)
            return bilinearColor(f00, f10, f01, f11, fx, fy)
        }

        let c00 = readPixel(image, x0, y0)
        let c10 = readPixel(image, x1, y0)
        let c01 = readPixel(image, x0, y1)
        let c11 = readPixel(image, x1, y1)
        return bilinearColor(c00, c10, c01, c11, fx, fy)
    }

    mtd sampleBlur(batch: *RasterBatch, image: *Image, u, v: f32)->Color
    {
        let radius = Math.max(.blurRadius, 0.0)
        if radius <= 0.000001 do
            return sampleLinear(image, u, v, false)

        var a, r, g, b: f32
        var offset = -radius
        for i in batch.blurWeightCount
        {
            let su     = .blurAxis == 0 ? u + offset / image.width : u
            let sv     = .blurAxis == 0 ? v : v + offset / image.height
            let sample = sampleLinear(image, su, sv, false)
            let weight = batch.blurWeights![i]
            a      += cast(f32) sample.a / 255.0 * weight
            r      += cast(f32) sample.r / 255.0 * weight
            g      += cast(f32) sample.g / 255.0 * weight
            b      += cast(f32) sample.b / 255.0 * weight
            offset += 1.0
        }

        return Color.fromArgbF32(a, r, g, b)
    }

    mtd sampleResolve(image: *Image, u, v: f32)->Color
    {
        let factor    = Math.clamp(.resolveFactor, 1, 8)
        let dstWidth  = Math.max(image.width / factor, 1)
        let dstHeight = Math.max(image.height / factor, 1)
        let baseX     = cast(s32) Math.floor(Math.clamp(u, 0.0, 0.999999) * dstWidth) * factor
        let baseY     = cast(s32) Math.floor(Math.clamp(1.0 - v, 0.0, 0.999999) * dstHeight) * factor

        var sumA, sumR, sumG, sumB: f32
        for var y: s32; y < factor; y += 1
        {
            for var x: s32; x < factor; x += 1
            {
                let sample = readPixel(image, Math.clamp(baseX + x, 0, image.width - 1), Math.clamp(baseY + y, 0, image.height - 1))
                sumA += cast(f32) sample.a / 255.0
                sumR += cast(f32) sample.r / 255.0
                sumG += cast(f32) sample.g / 255.0
                sumB += cast(f32) sample.b / 255.0
            }
        }

        let count = cast(f32) (factor * factor)
        let alpha = sumA / count
        if sumA <= 0.00001 do
            return Color.fromArgbF32(alpha, 0, 0, 0)
        return Color.fromArgbF32(alpha, sumR / sumA, sumG / sumA, sumB / sumA)
    }

    mtd sampleGradient(params: const *Command, paintPos: Vector2)->Color
    {
        let p = &params.texture0
        if p.gradientStopCount == 0 do
            return Color.fromArgb(Argb.White)
        let stops = .gradientStops!

        var t: f32
        switch p.type
        {
        case .LinearGradient:
            let dx   = p.gradientEnd.x - p.gradientStart.x
            let dy   = p.gradientEnd.y - p.gradientStart.y
            let len2 = dx * dx + dy * dy
            if len2 <= 0.000001 do
                t = 0
            else do
                t = ((paintPos.x - p.gradientStart.x) * dx + (paintPos.y - p.gradientStart.y) * dy) / len2

        case .RadialGradient:
            let dx     = paintPos.x - p.gradientStart.x
            let dy     = paintPos.y - p.gradientStart.y
            let radius = Math.max(p.gradientRadius1 - p.gradientRadius0, 0.000001)
            t = (Math.sqrt(dx * dx + dy * dy) - p.gradientRadius0) / radius

        case .SweepGradient:
            var span = p.gradientAngle1 - p.gradientAngle0
            if Math.abs(span) <= 0.000001 do
                span = ConstF32.TwoPi
            let angle = Math.atan2(paintPos.y - p.gradientStart.y, paintPos.x - p.gradientStart.x)
            t = (angle - p.gradientAngle0) / span

        default:
            return Color.fromArgb(Argb.White)
        }

        switch #complete p.gradientSpread
        {
        case .Clamp:
            t = Math.saturate(t)

        case .Repeat:
            t = Math.fract(t)
            if t < 0 do
                t += 1

        case .Mirror:
            var u = Math.fract(t * 0.5) * 2.0
            if u < 0 do
                u += 2
            t = u <= 1.0 ? u : 2.0 - u
        }

        if t <= stops[0].offset do
            return stops[0].color
        for var i = 1'u64; i < p.gradientStopCount; i += 1
        {
            if t > stops[i].offset do
                continue
            let lo = stops[i - 1].offset
            let hi = stops[i].offset
            let u  = hi == lo ? 1.0 : Math.saturate((t - lo) / (hi - lo))
            return lerpColor(stops[i - 1].color, stops[i].color, u)
        }

        return stops[p.gradientStopCount - 1].color
    }

    // Samples the bound paint like the general path did, with the texture storage resolved once
    // per batch instead of once per pixel. Solid paints never reach this: the shader short-circuits
    // them through [[RasterBatch.solidPaint]], because multiplying by opaque white is the identity.
    mtd samplePaintBatch(batch: *RasterBatch, paintPos: Vector2)->Color
    {
        let p = &.paintCommand.texture0
        switch p.type
        {
        case .SolidColor:
            return Color.fromArgb(Argb.White)

        case .Texture:
            let image = batch.paintImage
            if !image do
                return Color.fromArgb(Argb.Zero)

            if p.uvMode == .FillSubRect and .program != CpuProgram_Blur and .program != CpuProgram_Resolve do
                return sampleSubRect(image, paintPos, &.paintCommand, .contentScale)

            let w      = Math.max(p.boundRect.z - p.boundRect.x, 0.000001)
            let h      = Math.max(p.boundRect.w - p.boundRect.y, 0.000001)
            var u      = (paintPos.x - p.boundRect.x) / w
            var v      = 1.0 - (paintPos.y - p.boundRect.y) / h
            let repeat = p.uvMode == .Tile

            if p.uvMode == .FillSubRect
            {
                u = p.textureRect.x + u * (p.textureRect.z - p.textureRect.x)
                v = 1.0 - (p.textureRect.y + (1.0 - v) * (p.textureRect.w - p.textureRect.y))
            }
            elif p.uvMode == .Tile
            {
                u = (paintPos.x - p.boundRect.x) / Math.max(p.textureRect.z, 0.000001)
                v = 1.0 - (paintPos.y - p.boundRect.y) / Math.max(p.textureRect.w, 0.000001)
            }

            if .program == CpuProgram_Blur do
                return .sampleBlur(batch, image, u, v)
            if .program == CpuProgram_Resolve do
                return .sampleResolve(image, u, v)

            if p.interpolationMode == .Linear do
                return sampleLinear(image, u, v, repeat)
            return sampleNearest(image, u, v, repeat)

        case .Hatch:
            let x = modFloor(cast(s32) Math.floor(paintPos.x - p.boundRect.x), 8)
            let y = modFloor(cast(s32) Math.floor(paintPos.y - p.boundRect.y), 8)
            return hatchPixel(p.hatch, x, y) ? Color.fromArgb(Argb.White) : Color.fromArgb(Argb.Zero)

        case .LinearGradient, .RadialGradient, .SweepGradient:
            return .sampleGradient(&.paintCommand, paintPos)
        }
    }

    func hatchPixel(style: HatchStyle, x, y: s32)->bool
    {
        let idx = cast(u64) (y * 8 + x)
        switch #complete style
        {
        case .Dot:                   return Hatch.Dot[idx] != 0
        case .Horizontal:            return Hatch.Horizontal[idx] != 0
        case .HorizontalLight:       return Hatch.HorizontalLight[idx] != 0
        case .HorizontalNarrow:      return Hatch.HorizontalNarrow[idx] != 0
        case .Vertical:              return Hatch.Vertical[idx] != 0
        case .VerticalLight:         return Hatch.VerticalLight[idx] != 0
        case .VerticalNarrow:        return Hatch.VerticalNarrow[idx] != 0
        case .SolidDiamond:          return Hatch.SolidDiamond[idx] != 0
        case .OutlinedDiamond:       return Hatch.OutlinedDiamond[idx] != 0
        case .HorizontalDark:        return Hatch.HorizontalDark[idx] != 0
        case .VerticalDark:          return Hatch.VerticalDark[idx] != 0
        case .Grid:                  return Hatch.Grid[idx] != 0
        case .GridLarge:             return Hatch.GridLarge[idx] != 0
        case .GridDotted:            return Hatch.GridDotted[idx] != 0
        case .Cross:                 return Hatch.Cross[idx] != 0
        case .CrossLarge:            return Hatch.CrossLarge[idx] != 0
        case .Percent5:              return Hatch.Percent5[idx] != 0
        case .Percent10:             return Hatch.Percent10[idx] != 0
        case .Percent20:             return Hatch.Percent20[idx] != 0
        case .Percent25:             return Hatch.Percent25[idx] != 0
        case .Percent30:             return Hatch.Percent30[idx] != 0
        case .Percent40:             return Hatch.Percent40[idx] != 0
        case .Percent50:             return Hatch.Percent50[idx] != 0
        case .Percent60:             return Hatch.Percent60[idx] != 0
        case .Percent70:             return Hatch.Percent70[idx] != 0
        case .Percent75:             return Hatch.Percent75[idx] != 0
        case .Percent80:             return Hatch.Percent80[idx] != 0
        case .Percent90:             return Hatch.Percent90[idx] != 0
        case .CheckBoard:            return Hatch.CheckBoard[idx] != 0
        case .CheckBoardLarge:       return Hatch.CheckBoardLarge[idx] != 0
        case .Weave:                 return Hatch.Weave[idx] != 0
        case .DiagonalForward:       return Hatch.DiagonalForward[idx] != 0
        case .DiagonalForwardLight:  return Hatch.DiagonalForwardLight[idx] != 0
        case .DiagonalBackward:      return Hatch.DiagonalBackward[idx] != 0
        case .DiagonalBackwardLight: return Hatch.DiagonalBackwardLight[idx] != 0
        case .DiagonalCross:         return Hatch.DiagonalCross[idx] != 0
        }

        return false
    }

    func smoothStep(edge0, edge1, value: f32)->f32
    {
        if edge1 <= edge0 do
            return value < edge0 ? 0.0 : 1.0
        let t = Math.saturate((value - edge0) / (edge1 - edge0))
        return t * t * (3.0 - 2.0 * t)
    }

    func median(a, b, c: f32)->f32
    {
        return Math.max(Math.min(a, b), Math.min(Math.max(a, b), c))
    }

    mtd fontAtlas()->#null *GlyphAtlas
    {
        if !.font or .fontAtlasIndex < 0 do
            return null

        let cache = .font.cache
        if cast(u64) .fontAtlasIndex >= cache.atlases.count do
            return null
        return &cache.atlases[cast(u64) .fontAtlasIndex]
    }

    func readFontAtlas(atlas: const *GlyphAtlas, x, y: s32)->Vector4
    {
        let pixelWidth = cast(s32) (atlas.width / atlas.bytesPerPixel)
        let xx         = Math.clamp(x, 0, pixelWidth - 1)
        let yy         = Math.clamp(y, 0, cast(s32) atlas.height - 1)
        let row        = cast(s32) atlas.height - yy - 1
        let ptr        = atlas.data.buffer! + cast(u64) row * atlas.width + cast(u64) xx * atlas.bytesPerPixel

        if atlas.bytesPerPixel == 1
        {
            let value = cast(f32) ptr[0] / 255.0
            return {value, value, value, value}
        }

        return {cast(f32) ptr[0] / 255.0,
                cast(f32) ptr[1] / 255.0,
                cast(f32) ptr[2] / 255.0,
                cast(f32) ptr[3] / 255.0}
    }

    func sampleFontAtlas(atlas: const *GlyphAtlas, uv: Vector2, linear: bool)->Vector4
    {
        let width  = cast(s32) (atlas.width / atlas.bytesPerPixel)
        let height = cast(s32) atlas.height
        if !linear
        {
            let x = Math.clamp(cast(s32) Math.floor(uv.x * width), 0, width - 1)
            let y = Math.clamp(cast(s32) Math.floor(uv.y * height), 0, height - 1)
            return readFontAtlas(atlas, x, y)
        }

        let px = Math.saturate(uv.x) * width - 0.5
        let py = Math.saturate(uv.y) * height - 0.5
        let x0 = cast(s32) Math.floor(px)
        let y0 = cast(s32) Math.floor(py)
        let x1 = Math.min(x0 + 1, width - 1)
        let y1 = Math.min(y0 + 1, height - 1)
        let tx = px - Math.floor(px)
        let ty = py - Math.floor(py)

        // The MSDF shader takes four of these per shaded pixel; branching on the atlas layout
        // once, the four fetches then read the exact values [[readFontAtlas]] returns.
        if atlas.bytesPerPixel == 4
        {
            func fetch(atlas: const *GlyphAtlas, width, height, x, y: s32)->Vector4
            {
                let xx  = Math.clamp(x, 0, width - 1)
                let yy  = Math.clamp(y, 0, height - 1)
                let row = height - yy - 1
                let ptr = atlas.data.buffer! + cast(u64) row * atlas.width + cast(u64) xx * atlas.bytesPerPixel
                return {cast(f32) ptr[0] / 255.0,
                        cast(f32) ptr[1] / 255.0,
                        cast(f32) ptr[2] / 255.0,
                        cast(f32) ptr[3] / 255.0}
            }

            let f00 = fetch(atlas, width, height, x0, y0)
            let f10 = fetch(atlas, width, height, x1, y0)
            let f01 = fetch(atlas, width, height, x0, y1)
            let f11 = fetch(atlas, width, height, x1, y1)
            return Vector4.lerp(Vector4.lerp(f00, f10, tx), Vector4.lerp(f01, f11, tx), ty)
        }

        let c00 = readFontAtlas(atlas, x0, y0)
        let c10 = readFontAtlas(atlas, x1, y0)
        let c01 = readFontAtlas(atlas, x0, y1)
        let c11 = readFontAtlas(atlas, x1, y1)
        return Vector4.lerp(Vector4.lerp(c00, c10, tx), Vector4.lerp(c01, c11, tx), ty)
    }

    func msdfCoverage(atlas: const *GlyphAtlas, uv: Vector2, screenPxRange, edge, aa: f32)->f32
    {
        let sample = sampleFontAtlas(atlas, uv, true)
        let sd     = median(sample.x, sample.y, sample.z)
        return Math.saturate((sd - edge) * screenPxRange / aa + 0.5)
    }

    // Evaluates the four quarter-pixel MSDF taps from their shared texel neighborhood. At normal
    // text scales the four bilinear footprints cover at most nine texels instead of fetching
    // sixteen; unusual minification falls back to the independent sampler without changing it.
    func msdfCoverage4(atlas: const *GlyphAtlas, uv, offset: Vector2, screenPxRange: f32)->f32
    {
        let points: [4] Vector2 = [uv + Vector2{-offset.x, -offset.y},
                                   uv + Vector2{offset.x, -offset.y},
                                   uv + Vector2{-offset.x, offset.y},
                                   uv + Vector2{offset.x, offset.y}]
        if atlas.bytesPerPixel != 4
        {
            var fallback = 0'f32
            for point in points do
                fallback += msdfCoverage(atlas, point, screenPxRange, 0.5, 1.0)
            return fallback
        }

        let width  = cast(s32) (atlas.width / atlas.bytesPerPixel)
        let height = cast(s32) atlas.height
        var samples: [4] FontLinearSample
        var minX   = Swag.S32.Max
        var minY   = Swag.S32.Max
        var maxX   = Swag.S32.Min
        var maxY   = Swag.S32.Min
        for point, index in points
        {
            let px     = Math.saturate(point.x) * width - 0.5
            let py     = Math.saturate(point.y) * height - 0.5
            let sample = &samples[index]
            sample.x0 = cast(s32) Math.floor(px)
            sample.y0 = cast(s32) Math.floor(py)
            sample.x1 = Math.min(sample.x0 + 1, width - 1)
            sample.y1 = Math.min(sample.y0 + 1, height - 1)
            sample.tx = px - Math.floor(px)
            sample.ty = py - Math.floor(py)
            minX      = Math.min(minX, sample.x0)
            minY      = Math.min(minY, sample.y0)
            maxX      = Math.max(maxX, sample.x1)
            maxY      = Math.max(maxY, sample.y1)
        }

        let cacheWidth  = maxX - minX + 1
        let cacheHeight = maxY - minY + 1
        if cacheWidth > 3 or cacheHeight > 3
        {
            var fallback = 0'f32
            for point in points do
                fallback += msdfCoverage(atlas, point, screenPxRange, 0.5, 1.0)
            return fallback
        }

        var cache: [9] Vector4
        for y in cacheHeight
        {
            for x in cacheWidth do
                cache[cast(u64) (y * cacheWidth + x)] = readFontAtlas(atlas, minX + x, minY + y)
        }

        var result = 0'f32
        for sample in samples
        {
            let row0  = (sample.y0 - minY) * cacheWidth
            let row1  = (sample.y1 - minY) * cacheWidth
            let f00   = cache[cast(u64) (row0 + sample.x0 - minX)]
            let f10   = cache[cast(u64) (row0 + sample.x1 - minX)]
            let f01   = cache[cast(u64) (row1 + sample.x0 - minX)]
            let f11   = cache[cast(u64) (row1 + sample.x1 - minX)]
            let value = Vector4.lerp(Vector4.lerp(f00, f10, sample.tx), Vector4.lerp(f01, f11, sample.tx), sample.ty)
            let sd    = median(value.x, value.y, value.z)
            result += Math.saturate((sd - 0.5) * screenPxRange + 0.5)
        }

        return result
    }

    mtd shadeMsdf(faceColor: Color, uv, uvDx, uvDy: Vector2, safeAtlas: const *GlyphAtlas)->Color
    {
        let width         = cast(f32) (safeAtlas.width / safeAtlas.bytesPerPixel)
        let height        = cast(f32) safeAtlas.height
        let fwX           = Math.abs(uvDx.x) + Math.abs(uvDy.x)
        let fwY           = Math.abs(uvDx.y) + Math.abs(uvDy.y)
        let screenX       = fwX > 0.000001 ? 1.0 / fwX : 1.0
        let screenY       = fwY > 0.000001 ? 1.0 / fwY : 1.0
        let screenPxRange = Math.max(0.5 * (MsdfRange / width * screenX + MsdfRange / height * screenY), 1.0)

        if .fontEffect.enabled < 0.5
        {
            let off   = Vector2{fwX * 0.25, fwY * 0.25}
            let alpha = Math.pow(msdfCoverage4(safeAtlas, uv, off, screenPxRange) * 0.25, FontGamma)
            return faceColor.withAlphaF32(cast(f32) faceColor.a / 255.0 * alpha)
        }

        let p           = &.fontEffect
        let aa          = Math.max(1.0, p.faceSoftness * screenPxRange)
        let sample      = sampleFontAtlas(safeAtlas, uv, true)
        let sdMedian    = median(sample.x, sample.y, sample.z)
        let sdTrue      = sample.w
        let faceEdge    = 0.5 - p.faceDilate
        let outlineEdge = faceEdge - p.outlineWidth
        let useTrue     = Math.saturate(p.faceSoftness * screenPxRange - 1.0)
        let sdFace      = sdMedian + (sdTrue - sdMedian) * useTrue
        let faceCov     = Math.saturate((sdFace - faceEdge) * screenPxRange / aa + 0.5)
        let outerCov    = Math.saturate((sdTrue - outlineEdge) * screenPxRange / aa + 0.5)

        let face  = faceColor.toVector4()
        var faceR = face.x
        var faceG = face.y
        var faceB = face.z
        if p.bevel > 0
        {
            let gradX     = sampleFontAtlas(safeAtlas, uv + uvDx, true).w - sdTrue
            let gradY     = sampleFontAtlas(safeAtlas, uv + uvDy, true).w - sdTrue
            let magnitude = Math.sqrt(gradX * gradX + gradY * gradY)
            let reference = 1.0 / screenPxRange
            let strength  = smoothStep(0.0, 0.6 * reference, magnitude)
            var lit: f32
            if magnitude > 0.000001 do
                lit = (-gradX - gradY) / (magnitude * ConstF32.Sqrt2)
            let light = Math.clamp(1.0 + p.bevel * lit * strength, 0.25, 1.75)
            faceR, faceG, faceB *= light
        }

        let outline      = p.outlineColor.toVector4()
        let faceAlpha    = faceCov * face.w
        let outlineAlpha = outerCov * outline.w
        let shapeAlpha   = faceAlpha + outlineAlpha * (1.0 - faceAlpha)
        var shapeR       = faceR
        var shapeG       = faceG
        var shapeB       = faceB
        if shapeAlpha > 0.0001
        {
            shapeR = (faceR * faceAlpha + outline.x * outlineAlpha * (1.0 - faceAlpha)) / shapeAlpha
            shapeG = (faceG * faceAlpha + outline.y * outlineAlpha * (1.0 - faceAlpha)) / shapeAlpha
            shapeB = (faceB * faceAlpha + outline.z * outlineAlpha * (1.0 - faceAlpha)) / shapeAlpha
        }

        let glow = p.glowColor.toVector4()
        var glowAlpha: f32
        if glow.w > 0
        {
            let distance  = Math.abs(sdTrue - (0.5 - p.glowOffset))
            let intensity = 1.0 - smoothStep(p.glowInner, p.glowOuter, distance)
            glowAlpha = Math.pow(Math.saturate(intensity), Math.max(p.glowPower, 0.0001)) * glow.w
        }

        let resultAlpha = shapeAlpha + glowAlpha * (1.0 - shapeAlpha)
        var resultR     = shapeR
        var resultG     = shapeG
        var resultB     = shapeB
        if resultAlpha > 0.0001
        {
            resultR = (shapeR * shapeAlpha + glow.x * glowAlpha * (1.0 - shapeAlpha)) / resultAlpha
            resultG = (shapeG * shapeAlpha + glow.y * glowAlpha * (1.0 - shapeAlpha)) / resultAlpha
            resultB = (shapeB * shapeAlpha + glow.z * glowAlpha * (1.0 - shapeAlpha)) / resultAlpha
        }

        return Color.fromArgbF32(resultAlpha, resultR, resultG, resultB)
    }

    // Shades one fragment like the general path did, with the paint, the atlas, and the font
    // gamma resolved per batch. Every arithmetic step keeps the general path's exact expression,
    // so the shaded color is bit-identical.
    mtd shadeBatch(batch: *RasterBatch, paintPos, fontUv, fontUvDx, fontUvDy: Vector2, vertexColor: Color, coverage: f32)->Color
    {
        var result = batch.solidPaint ? vertexColor : Color.multiply(vertexColor, .samplePaintBatch(batch, paintPos))
        if .program == CpuProgram_Font
        {
            let atlas = batch.atlas
            if !atlas do
                return Color.fromArgb(Argb.Zero)

            // Nearest atlas fetch, inlined: the sample value only feeds the gamma power, so the
            // lookup table replaces the per-pixel pow with the factor it would have computed.
            let width  = cast(s32) (atlas.width / atlas.bytesPerPixel)
            let height = cast(s32) atlas.height
            let x      = Math.clamp(cast(s32) Math.floor(fontUv.x * width), 0, width - 1)
            let y      = Math.clamp(cast(s32) Math.floor(fontUv.y * height), 0, height - 1)
            let row    = cast(s32) atlas.height - y - 1
            let value  = atlas.data.buffer![cast(u64) row * atlas.width + cast(u64) x * atlas.bytesPerPixel]
            result.a = cast(u8) Math.clamp(Math.round(cast(f32) result.a * g_FontGammaLut[value]), 0.0, 255.0)
        }
        elif .program == CpuProgram_Msdf
        {
            let atlas = batch.atlas
            if !atlas do
                return Color.fromArgb(Argb.Zero)
            result = .shadeMsdf(result, fontUv, fontUvDx, fontUvDy, atlas)
        }
        elif .program == CpuProgram_Default
        {
            result.a = cast(u8) Math.clamp(Math.round(cast(f32) result.a * coverage), 0.0, 255.0)
        }

        return result
    }

    // Rasterizes one triangle, restricted to the rows of `[bandMinY, bandMaxY]`.
    //
    // A band is a row range of the target, never a clip: it selects which worker owns the
    // pixel, so a band-restricted sweep of the whole range produces exactly the pixels the
    // unrestricted sweep would. The scissor is folded into the loop bounds, and the loops pick
    // the cheapest body that still stores the exact bytes the general path stored.
    mtd drawTriangleBatch(batch: *RasterBatch, vertices: const [*] VertexLayout, bandMinY, bandMaxY: s32)
    {
        var v0 = vertices[0]
        var v1 = vertices[1]
        var v2 = vertices[2]
        var p0 = batch.transform.transformPoint(v0.pos)
        var p1 = batch.transform.transformPoint(v1.pos)
        var p2 = batch.transform.transformPoint(v2.pos)

        var area = edge(p0, p1, p2)
        if area == 0 do
            return
        if area < 0
        {
            swap(&v1, &v2)
            swap(&p1, &p2)
            area = -area
        }

        let minX = Math.max(Math.clamp(cast(s32) Math.floor(Math.min(p0.x, Math.min(p1.x, p2.x))), 0, batch.width - 1), batch.clipMinX)
        let minY = Math.max(Math.max(Math.clamp(cast(s32) Math.floor(Math.min(p0.y, Math.min(p1.y, p2.y))), 0, batch.height - 1), bandMinY), batch.clipMinY)
        let maxX = Math.min(Math.clamp(cast(s32) Math.ceil(Math.max(p0.x, Math.max(p1.x, p2.x))) - 1, 0, batch.width - 1), batch.clipMaxX)
        let maxY = Math.min(Math.min(Math.clamp(cast(s32) Math.ceil(Math.max(p0.y, Math.max(p1.y, p2.y))) - 1, 0, batch.height - 1), bandMaxY), batch.clipMaxY)
        if minX > maxX or minY > maxY do
            return

        let edge0TopLeft = isTopLeft(p1, p2)
        let edge1TopLeft = isTopLeft(p2, p0)
        let edge2TopLeft = isTopLeft(p0, p1)
        let invArea      = 1.0 / area

        // Per-pixel edge deltas, hoisted: each edge function stays the exact expression of
        // [[edge]], with its row term computed once per row.
        let dx0 = p2.x - p1.x
        let dy0 = p2.y - p1.y
        let dx1 = p0.x - p2.x
        let dy1 = p0.y - p2.y
        let dx2 = p1.x - p0.x
        let dy2 = p1.y - p0.y

        // A stencil write shades nothing: the loop only stamps the mask over the covered pixels.
        if .stencilWrite
        {
            let stencilValue: u8 = .stencilMode == .Set ? 1 : 0
            for var y = minY; y <= maxY; y += 1
            {
                let sy         = cast(f32) y + 0.5
                let rowDy0     = sy - p1.y
                let rowDy1     = sy - p2.y
                let rowDy2     = sy - p0.y
                let rowStencil = batch.stencil + cast(u64) y * cast(u64) batch.width
                for var x = minX; x <= maxX; x += 1
                {
                    let sx = cast(f32) x + 0.5
                    let e0 = dx0 * rowDy0 - dy0 * (sx - p1.x)
                    let e1 = dx1 * rowDy1 - dy1 * (sx - p2.x)
                    let e2 = dx2 * rowDy2 - dy2 * (sx - p0.x)
                    if !insideEdge(e0, edge0TopLeft) or !insideEdge(e1, edge1TopLeft) or !insideEdge(e2, edge2TopLeft) do
                        continue
                    rowStencil[x] = stencilValue
                }
            }

            return
        }

        let dcDx     = (v0.cov * (p1.y - p2.y) + v1.cov * (p2.y - p0.y) + v2.cov * (p0.y - p1.y)) * invArea
        let dcDy     = (v0.cov * (p2.x - p1.x) + v1.cov * (p0.x - p2.x) + v2.cov * (p1.x - p0.x)) * invArea
        let covWidth = Math.max(Math.abs(dcDx) + Math.abs(dcDy), 0.00001)
        let fontUvDx = Vector2{(v0.uv.x * (p1.y - p2.y) + v1.uv.x * (p2.y - p0.y) + v2.uv.x * (p0.y - p1.y)) * invArea,
                               (v0.uv.y * (p1.y - p2.y) + v1.uv.y * (p2.y - p0.y) + v2.uv.y * (p0.y - p1.y)) * invArea}
        let fontUvDy = Vector2{(v0.uv.x * (p2.x - p1.x) + v1.uv.x * (p0.x - p2.x) + v2.uv.x * (p1.x - p0.x)) * invArea,
                               (v0.uv.y * (p2.x - p1.x) + v1.uv.y * (p0.x - p2.x) + v2.uv.y * (p1.x - p0.x)) * invArea}

        let c0            = Color.fromArgb(v0.color)
        let c1            = Color.fromArgb(v1.color)
        let c2            = Color.fromArgb(v2.color)
        let constantColor = c0 == c1 and c1 == c2

        let image       = batch.image!
        let stencilTest = .stencilOn
        let maskColor   = .colorMask.r and .colorMask.g and .colorMask.b and !.colorMask.a
        let maskFull    = .colorMask.r and .colorMask.g and .colorMask.b and .colorMask.a
        let maskAlpha   = !.colorMask.r and !.colorMask.g and !.colorMask.b and .colorMask.a
        let plainBgra8  = !.alphaResolve and .overlapPass == 0 and image.pixelFormat == .BGRA8
        let fastAlpha   = plainBgra8 and .blendingMode == .Alpha and maskColor
        let fastCopy    = plainBgra8 and .blendingMode == .Copy and (maskColor or maskFull)

        // A triangle whose vertices agree on color and coverage shades one constant fragment
        // under a solid paint, and the frequent blend states then collapse per pixel.
        var constShade = constantColor and batch.solidPaint and (.program == CpuProgram_Simple or .program == CpuProgram_Default)
        var constColor = c0
        if constShade and .program == CpuProgram_Default
        {
            // Away from the 0.5 threshold a uniform coverage saturates to exactly zero or one
            // for every pixel, whatever noise the barycentric interpolation adds; near it, the
            // general loop below keeps the per-pixel decision.
            if v0.cov == v1.cov and v1.cov == v2.cov and (v0.cov < 0.49 or v0.cov > 0.51)
            {
                if v0.cov < 0.5 do
                    constColor.a = 0
            }
            else do
                constShade = false
        }

        if constShade and plainBgra8
        {
            // Multiplying the destination by an opaque coverage returns every channel's own
            // byte, masked or not, so the whole triangle leaves the target untouched.
            if .blendingMode == .DstIn and constColor.a == 255 do
                return

            // 'Alpha' blending never writes a transparent source.
            if .blendingMode == .Alpha and (maskColor or maskAlpha) and constColor.a == 0 do
                return

            // Writing only the alpha channel is the same store under both blend modes that
            // reach it: 'Copy' replaces the byte, and 'Alpha' with an opaque source replaces
            // it too. Restoring an opaque ground after antialiased content is a whole-target
            // rectangle, so leaving that to the general shading loop costs a paint evaluation
            // and a Color round trip per pixel to write one byte.
            let alphaMaskStore = maskAlpha and (.blendingMode == .Copy or (.blendingMode == .Alpha and constColor.a == 255))
            if fastAlpha or fastCopy or alphaMaskStore
            {
                let copyAll = fastCopy and maskFull
                let fill    = cast(Math.Simd.U8x16) [constColor.b, constColor.g, constColor.r, constColor.a,
                                                     constColor.b, constColor.g, constColor.r, constColor.a,
                                                     constColor.b, constColor.g, constColor.r, constColor.a,
                                                     constColor.b, constColor.g, constColor.r, constColor.a]
                for var y = minY; y <= maxY; y += 1
                {
                    let sy         = cast(f32) y + 0.5
                    let rowDy0     = sy - p1.y
                    let rowDy1     = sy - p2.y
                    let rowDy2     = sy - p0.y
                    let rowPixels  = batch.pixels + cast(u64) (batch.height - y - 1) * cast(u64) batch.rowStride
                    let rowStencil = batch.stencil + cast(u64) y * cast(u64) batch.width
                    var x          = minX
                    while x <= maxX
                    {
                        var coverage: u32
                        var laneCount = 1
                        if maxX - x >= 3
                        {
                            let sx = Math.Simd.splat(cast(f32) x + 0.5) + CpuPixelLanes
                            let e0 = dx0 * rowDy0 - dy0 * (sx - p1.x)
                            let e1 = dx1 * rowDy1 - dy1 * (sx - p2.x)
                            let e2 = dx2 * rowDy2 - dy2 * (sx - p0.x)
                            coverage  = insideEdges4(e0, e1, e2, edge0TopLeft, edge1TopLeft, edge2TopLeft)
                            laneCount = 4
                        }
                        else
                        {
                            let sx = cast(f32) x + 0.5
                            let e0 = dx0 * rowDy0 - dy0 * (sx - p1.x)
                            let e1 = dx1 * rowDy1 - dy1 * (sx - p2.x)
                            let e2 = dx2 * rowDy2 - dy2 * (sx - p0.x)
                            if insideEdge(e0, edge0TopLeft) and insideEdge(e1, edge1TopLeft) and insideEdge(e2, edge2TopLeft) do
                                coverage = 1
                        }

                        let pixel = rowPixels + cast(u64) x * 4

                        // Translucent alpha keeps the scalar float blend so every byte rounds as
                        // before; the other full spans collapse to one packed load/store pair.
                        if laneCount == 4 and coverage == 0xF and !stencilTest and (!fastAlpha or constColor.a == 255)
                        {
                            if copyAll do
                                Math.Simd.store(pixel, fill)
                            elif alphaMaskStore do
                                Math.Simd.store(pixel, Math.Simd.select(CpuBgraAlphaMask, fill, Math.Simd.load(pixel)))
                            else do
                                Math.Simd.store(pixel, Math.Simd.select(CpuBgraRgbMask, fill, Math.Simd.load(pixel)))
                            x += 4
                            continue
                        }

                        for lane in laneCount
                        {
                            if !(coverage & (1'u32 << lane)) do
                                continue
                            let pixelX = x + cast(s32) lane
                            if stencilTest and rowStencil[pixelX] != 1 do
                                continue

                            let lanePixel = rowPixels + cast(u64) pixelX * 4
                            if fastAlpha
                            {
                                blendAlphaBgra8(lanePixel, constColor)
                            }
                            elif alphaMaskStore
                            {
                                lanePixel[3] = constColor.a
                            }
                            else
                            {
                                lanePixel[0] = constColor.b
                                lanePixel[1] = constColor.g
                                lanePixel[2] = constColor.r
                                if copyAll do
                                    lanePixel[3] = constColor.a
                            }
                        }

                        x += laneCount
                    }
                }

                return
            }
        }

        // A texture read one texel per device pixel, blended over an opaque destination, is
        // the whole of what drawing a page image, a photograph, or a presented surface costs.
        // Reaching it through the loop below spends a call into the sampler, a switch on the
        // paint kind, a switch on the pixel format, a multiply by opaque white and a Color
        // round trip on every pixel, to move three bytes. The address arithmetic is the same
        // expression the sampler evaluates, so the bytes stored are the same bytes.
        let paint = &.paintCommand.texture0
        let white = Color.fromArgb(Argb.White).argb
        if fastAlpha and !batch.solidPaint and !stencilTest and batch.paintImage != null and
           v0.color == white and v1.color == white and v2.color == white and
           paint.type == .Texture and paint.uvMode == .FillSubRect and paint.interpolationMode == .Pixel and .contentScale == 1 and
           (.program == CpuProgram_Simple or (.program == CpuProgram_Default and v0.cov == v1.cov and v1.cov == v2.cov and v0.cov > 0.51))
        {
            let source = batch.paintImage!
            if source.pixelFormat != .Yuv420
            {
                // Everything the sampler recomputes per pixel from the paint command is
                // constant over the triangle.
                let texMinX = cast(s32) Math.floor(paint.textureRect.x * source.width)
                let texMinY = cast(s32) Math.floor(paint.textureRect.y * source.height)
                let texMaxX = cast(s32) Math.floor(paint.textureRect.z * source.width)
                let texMaxY = cast(s32) Math.floor(paint.textureRect.w * source.height)
                let spanX   = cast(f32) (texMaxX - texMinX + 1)
                let spanY   = cast(f32) (texMaxY - texMinY + 1)
                let dstW    = Math.max(paint.boundRect.z - paint.boundRect.x, 0.000001)
                let dstH    = Math.max(paint.boundRect.w - paint.boundRect.y, 0.000001)
                let originX = paint.boundRect.x
                let originY = paint.boundRect.y

                let hasAlpha    = source.pixelFormat == .RGBA8 or source.pixelFormat == .BGRA8
                let swapRedBlue = source.pixelFormat == .RGBA8 or source.pixelFormat == .RGB8
                let texelBytes  = cast(u64) (hasAlpha ? 4 : 3)
                let texelRow    = texelBytes * cast(u64) source.width
                let texels      = source.pixels.buffer!
                let lastTexelX  = source.width - 1
                let lastTexelY  = source.height - 1

                for var y = minY; y <= maxY; y += 1
                {
                    let sy        = cast(f32) y + 0.5
                    let rowDy0    = sy - p1.y
                    let rowDy1    = sy - p2.y
                    let rowDy2    = sy - p0.y
                    let rowPixels = batch.pixels + cast(u64) (batch.height - y - 1) * cast(u64) batch.rowStride
                    for var x = minX; x <= maxX; x += 1
                    {
                        let sx = cast(f32) x + 0.5
                        let e0 = dx0 * rowDy0 - dy0 * (sx - p1.x)
                        let e1 = dx1 * rowDy1 - dy1 * (sx - p2.x)
                        let e2 = dx2 * rowDy2 - dy2 * (sx - p0.x)
                        if !insideEdge(e0, edge0TopLeft) or !insideEdge(e1, edge1TopLeft) or !insideEdge(e2, edge2TopLeft) do
                            continue

                        let w0 = e0 * invArea
                        let w1 = e1 * invArea
                        let w2 = e2 * invArea
                        let tx = Math.saturate((v0.pos.x * w0 + v1.pos.x * w1 + v2.pos.x * w2 - originX) / dstW)
                        let ty = Math.saturate((v0.pos.y * w0 + v1.pos.y * w1 + v2.pos.y * w2 - originY) / dstH)
                        let px = cast(f32) texMinX + tx * spanX - 0.5
                        let py = cast(f32) texMinY + ty * spanY - 0.5

                        let texelX = Math.clamp(Math.clamp(cast(s32) Math.floor(px + 0.5), texMinX, texMaxX), 0, lastTexelX)
                        let texelY = Math.clamp(Math.clamp(cast(s32) Math.floor(py + 0.5), texMinY, texMaxY), 0, lastTexelY)
                        let texel  = texels + cast(u64) texelX * texelBytes + cast(u64) (lastTexelY - texelY) * texelRow

                        let pixel = rowPixels + cast(u64) x * 4
                        if hasAlpha
                        {
                            var src: Color = undefined
                            src.b = texel[swapRedBlue ? 2 : 0]
                            src.g = texel[1]
                            src.r = texel[swapRedBlue ? 0 : 2]
                            src.a = texel[3]

                            // A transparent texel is coverage, not ink; the general loop skips it
                            // before it can round the destination down by one.
                            if src.a == 0 do
                                continue
                            blendAlphaBgra8(pixel, src)
                            continue
                        }

                        pixel[0] = texel[swapRedBlue ? 2 : 0]
                        pixel[1] = texel[1]
                        pixel[2] = texel[swapRedBlue ? 0 : 2]
                    }
                }

                return
            }
        }

        let needPaintPos = !batch.solidPaint
        let needFontUv   = .program == CpuProgram_Font or .program == CpuProgram_Msdf
        let needCoverage = .program == CpuProgram_Default
        let copyAll      = fastCopy and maskFull

        for var y = minY; y <= maxY; y += 1
        {
            let sy         = cast(f32) y + 0.5
            let rowDy0     = sy - p1.y
            let rowDy1     = sy - p2.y
            let rowDy2     = sy - p0.y
            let rowPixels  = batch.pixels + cast(u64) (batch.height - y - 1) * cast(u64) batch.rowStride
            let rowStencil = batch.stencil + cast(u64) y * cast(u64) batch.width
            for var x = minX; x <= maxX; x += 1
            {
                let sx = cast(f32) x + 0.5
                let e0 = dx0 * rowDy0 - dy0 * (sx - p1.x)
                let e1 = dx1 * rowDy1 - dy1 * (sx - p2.x)
                let e2 = dx2 * rowDy2 - dy2 * (sx - p0.x)
                if !insideEdge(e0, edge0TopLeft) or !insideEdge(e1, edge1TopLeft) or !insideEdge(e2, edge2TopLeft) do
                    continue
                if stencilTest and rowStencil[x] != 1 do
                    continue

                let w0          = e0 * invArea
                let w1          = e1 * invArea
                let w2          = e2 * invArea
                let paintPos    = needPaintPos ? v0.pos * w0 + v1.pos * w1 + v2.pos * w2 : Vector2{}
                let fontUv      = needFontUv ? v0.uv * w0 + v1.uv * w1 + v2.uv * w2 : Vector2{}
                let vertexColor = constantColor ? c0 : Color.fromArgbF32((c0.a * w0 + c1.a * w1 + c2.a * w2) / 255.0,
                                                                         (c0.r * w0 + c1.r * w1 + c2.r * w2) / 255.0,
                                                                         (c0.g * w0 + c1.g * w1 + c2.g * w2) / 255.0,
                                                                         (c0.b * w0 + c1.b * w1 + c2.b * w2) / 255.0)
                let cov = needCoverage ? Math.saturate(((v0.cov * w0 + v1.cov * w1 + v2.cov * w2) - 0.5) / covWidth + 0.5) : 0.0
                let src = .shadeBatch(batch, paintPos, fontUv, fontUvDx, fontUvDy, vertexColor, cov)
                if fastAlpha
                {
                    // The zero-alpha skip mirrors the general blend's coverage early-out.
                    if src.a == 0 do
                        continue
                    blendAlphaBgra8(rowPixels + cast(u64) x * 4, src)
                }
                elif fastCopy
                {
                    // 'Copy' writes transparent sources too, which is the erase operation.
                    let pixel = rowPixels + cast(u64) x * 4
                    pixel[0] = src.b
                    pixel[1] = src.g
                    pixel[2] = src.r
                    if copyAll do
                        pixel[3] = src.a
                    continue
                }
                else do
                    .blendPixel(image, x, y, src)
            }
        }
    }

    mtd drawTriangleRange(batch: *RasterBatch, bandMinY, bandMaxY: s32)
    {
        let vertices = batch.painter!.vertexBuffer.buffer!
        var i        = batch.start
        let end      = batch.start + batch.count
        while i + 2 < end
        {
            .drawTriangleBatch(batch, vertices + i, bandMinY, bandMaxY)
            i += 3
        }
    }

    // Rasterizes a triangle range over `bounds`, across the job pool when it is large enough.
    //
    // Bands partition the rows, so each pixel — color, stencil, and overlap scratch alike — is
    // owned by exactly one worker and the triangles of a pixel keep their submission order. The
    // rasterized image is therefore identical to the serial one, band split or not.
    mtd rasterizeRange(batch: *RasterBatch, bounds: PixelBounds)
    {
        let bandCount = Math.min(cast(s32) Jobs.workerCount(), bounds.rows() / CpuBandMinRows)
        if bounds.area() < CpuBandPixelThreshold or bandCount <= 1
        {
            .drawTriangleRange(batch, bounds.minY, bounds.maxY)
            return
        }

        let bandRows = (bounds.rows() + bandCount - 1) / bandCount
        var f        = {renderer: me, batch: batch, minY: bounds.minY, maxY: bounds.maxY, bandRows: bandRows}
        Jobs.parallelFor(cast(u32) bandCount, &f)
        {
            if !data do
                return
            let params = cast(*#decltype(f)) (data)
            let bandY  = params.minY + cast(s32) index * params.bandRows
            params.renderer.drawTriangleRange(params.batch, bandY, Math.min(bandY + params.bandRows - 1, params.maxY))
        }
    }

    // Resolves everything a triangle range needs exactly once: transform, clip, target bytes,
    // stencil plane, paint texture, and font atlas. Command state cannot change inside a range,
    // so per-pixel work then reads plain locals.
    mtd setupBatch(batch: *RasterBatch, image: *Image, painter: *Painter, start, count: u32)
    {
        batch.image     = image
        batch.painter   = painter
        batch.start     = start
        batch.count     = count
        batch.transform = .deviceTransform()
        batch.pixels    = image.pixels.buffer!
        batch.rowStride = image.rowStride
        batch.width     = image.width
        batch.height    = image.height

        // The general path skipped a pixel whose integer coordinate fell outside the float
        // scissor; folding the scissor with a ceiling keeps exactly that pixel set.
        batch.clipMinX = 0
        batch.clipMinY = 0
        batch.clipMaxX = image.width - 1
        batch.clipMaxY = image.height - 1
        if .scissorOn
        {
            batch.clipMinX = Math.max(batch.clipMinX, cast(s32) Math.ceil(.scissorRect.x))
            batch.clipMinY = Math.max(batch.clipMinY, cast(s32) Math.ceil(.scissorRect.y))
            batch.clipMaxX = Math.min(batch.clipMaxX, cast(s32) Math.ceil(.scissorRect.right()) - 1)
            batch.clipMaxY = Math.min(batch.clipMaxY, cast(s32) Math.ceil(.scissorRect.bottom()) - 1)
        }

        batch.stencil = .currentStencil().buffer!

        batch.solidPaint      = !.paintOn or .paintCommand.texture0.type == .SolidColor
        batch.paintImage      = null
        batch.blurWeights     = null
        batch.blurWeightCount = 0
        if .paintOn and .paintCommand.texture0.type == .Texture
        {
            let storage = .findTexture(.paintCommand.texture0.texture.handle)
            if storage do
                batch.paintImage = &storage.image
        }

        batch.atlas = .fontAtlas()
        if .program == CpuProgram_Font do
            ensureFontGammaLut()
    }

    // Copies the window-presentation rectangle row by row when its texture mapping is exactly the
    // identity. This is a complete rectangle with no shader, blend, mask, clip, or transform work
    // left to perform, so walking two triangles and resampling each texel would only recover the
    // bytes already present in the source.
    mtd tryCopyTextureRect(batch: *RasterBatch)->bool
    {
        if batch.count != 6 or .program != CpuProgram_Default and .program != CpuProgram_Simple do
            return false
        if .contentScale != 1 or !batch.transform.isTranslationOnly() do
            return false
        if .blendingMode != .Copy or !.colorMask.r or !.colorMask.g or !.colorMask.b or !.colorMask.a do
            return false
        if .stencilOn or .stencilWrite or .scissorOn or .overlapMode or .alphaResolve do
            return false

        let source = batch.paintImage
        let target = batch.image
        if !source or !target or source == target or source.pixelFormat != .BGRA8 or target.pixelFormat != .BGRA8 do
            return false

        let params = &.paintCommand.texture0
        if params.type != .Texture or params.uvMode != .FillSubRect or params.interpolationMode != .Pixel do
            return false

        let vertices    = batch.painter!.vertexBuffer.buffer! + batch.start
        let topLeft     = Vector2{params.boundRect.x, params.boundRect.y}
        let topRight    = Vector2{params.boundRect.z, params.boundRect.y}
        let bottomRight = Vector2{params.boundRect.z, params.boundRect.w}
        let bottomLeft  = Vector2{params.boundRect.x, params.boundRect.w}
        if vertices[0].pos != topLeft or vertices[1].pos != topRight or vertices[2].pos != bottomRight or vertices[3].pos != topLeft or vertices[4].pos != bottomRight or vertices[5].pos != bottomLeft
        {
            return false
        }

        let white = Color.fromArgb(Argb.White).argb
        for vertex in @mkslice(vertices, 6)
        {
            if vertex.color != white or vertex.cov != 1 do
                return false
        }

        let deviceTopLeft     = batch.transform.transformPoint(topLeft)
        let deviceBottomRight = batch.transform.transformPoint(bottomRight)
        let dstX              = cast(s32) deviceTopLeft.x
        let dstY              = cast(s32) deviceTopLeft.y
        let dstRight          = cast(s32) deviceBottomRight.x
        let dstBottom         = cast(s32) deviceBottomRight.y
        if cast(f32) dstX != deviceTopLeft.x or cast(f32) dstY != deviceTopLeft.y or cast(f32) dstRight != deviceBottomRight.x or cast(f32) dstBottom != deviceBottomRight.y do
            return false

        let srcX      = cast(s32) Math.floor(params.textureRect.x * source.width)
        let srcY      = cast(s32) Math.floor(params.textureRect.y * source.height)
        let srcRight  = cast(s32) Math.floor(params.textureRect.z * source.width) + 1
        let srcBottom = cast(s32) Math.floor(params.textureRect.w * source.height) + 1
        let width     = dstRight - dstX
        let height    = dstBottom - dstY
        if width <= 0 or height <= 0 or srcRight - srcX != width or srcBottom - srcY != height do
            return false
        if dstX < 0 or dstY < 0 or dstRight > target.width or dstBottom > target.height do
            return false
        if srcX < 0 or srcY < 0 or srcRight > source.width or srcBottom > source.height do
            return false

        let rowBytes = cast(u64) width * 4
        for row in height
        {
            let sourceRow = source.pixels.buffer! + cast(u64) (source.height - srcY - row - 1) * cast(u64) source.rowStride + cast(u64) srcX * 4
            let targetRow = target.pixels.buffer! + cast(u64) (target.height - dstY - row - 1) * cast(u64) target.rowStride + cast(u64) dstX * 4
            Memory.copy(targetRow, sourceRow, rowBytes)
        }

        return true
    }

    mtd drawTriangles(painter: *Painter, start, count: u32)
    {
        let image = .currentImage()
        if !image or count < 3 do
            return

        let bounds = .triangleRangeBounds(image, painter, start, count)
        if bounds.isEmpty() do
            return

        var batch: RasterBatch = undefined
        .setupBatch(&batch, image, painter, start, count)
        if .tryCopyTextureRect(&batch) do
            return

        // The blur kernel depends only on the active shader radius. Building it once here
        // removes pow/exp from every tap of every pixel while preserving the exact tap order.
        var blurWeights: Array'f32
        if .program == CpuProgram_Blur
        {
            let radius = Math.max(.blurRadius, 0.0)
            if radius > 0.000001
            {
                let rr     = radius * radius
                let w0     = 0.5135 / Math.pow(radius, 0.96)
                var offset = -radius
                while offset <= radius
                {
                    blurWeights.add(w0 * Math.exp((-offset * offset) / (2.0 * rr)))
                    offset += 1.0
                }

                batch.blurWeights     = blurWeights.buffer!
                batch.blurWeightCount = blurWeights.count
            }
        }

        if !.overlapMode or .alphaResolve
        {
            .rasterizeRange(&batch, bounds)
            return
        }

        // Both overlap passes only ever reach the pixels the range covers, so the scratch
        // planes are reset over those bounds instead of over the whole target.
        let pixelCount = cast(u64) image.width * cast(u64) image.height
        if .overlapAlpha.count != pixelCount do
            .overlapAlpha.resize(pixelCount)
        if .overlapWritten.count != pixelCount do
            .overlapWritten.resize(pixelCount)
        clearScratchRows(.overlapAlpha.buffer!, image.width, bounds)
        clearScratchRows(.overlapWritten.buffer!, image.width, bounds)

        // Destination alpha is the scratch channel in the OpenGL overlap path.
        .clearAlpha(image)
        .overlapPass = 1
        .rasterizeRange(&batch, bounds)
        .overlapPass = 2
        .rasterizeRange(&batch, bounds)
        .overlapPass = 0
    }

    // Zeroes the destination alpha of the scissor region, the scratch channel of the overlap resolve.
    //
    // OpenGL does this with an alpha-masked `glClear`, which the scissor bounds; the region
    // mirrors that exactly. The alpha byte is written in place: routing a single-channel reset
    // through a `Color` round trip made this the dominant cost of rasterizing a vector atlas.
    mtd clearAlpha(image: *Image)
    {
        if !image.pixelFormat.hasAlpha() do
            return

        let minX = .scissorOn ? Math.clamp(cast(s32) .scissorRect.x, 0, image.width) : 0
        let minY = .scissorOn ? Math.clamp(cast(s32) .scissorRect.y, 0, image.height) : 0
        let maxX = .scissorOn ? Math.clamp(cast(s32) .scissorRect.right(), 0, image.width) : image.width
        let maxY = .scissorOn ? Math.clamp(cast(s32) .scissorRect.bottom(), 0, image.height) : image.height

        // Every format carrying alpha stores it in the fourth byte, and rows are stored bottom-up.
        let pixels = image.pixels.buffer!
        let stride = cast(u64) image.bytesPerPixel
        let zero   = Math.Simd.splat(0'u8)
        for var y = minY; y < maxY; y += 1
        {
            let row    = pixels + cast(u64) ((image.height - y - 1) * image.rowStride + minX * image.bytesPerPixel)
            var offset = 3'u64
            var x      = minX
            while maxX - x >= 4
            {
                let block = row + offset - 3
                Math.Simd.store(block, Math.Simd.select(CpuBgraAlphaMask, zero, Math.Simd.load(block)))
                offset += 4 * stride
                x      += 4
            }

            while x < maxX
            {
                row[offset] = 0
                offset      += stride
                x           += 1
            }
        }
    }

    mtd clearCurrent(color: Color, forceColorMask = false)
    {
        let image = .currentImage()
        if !image do
            return

        let minX = .scissorOn ? Math.clamp(cast(s32) .scissorRect.x, 0, image.width) : 0
        let minY = .scissorOn ? Math.clamp(cast(s32) .scissorRect.y, 0, image.height) : 0
        let maxX = .scissorOn ? Math.clamp(cast(s32) .scissorRect.right(), 0, image.width) : image.width
        let maxY = .scissorOn ? Math.clamp(cast(s32) .scissorRect.bottom(), 0, image.height) : image.height
        if minX >= maxX or minY >= maxY do
            return

        // The stencil plane is row-contiguous, so the reset runs per row instead of per pixel.
        let stencil    = .currentStencil()
        let stencilBuf = stencil.buffer!
        let runWidth   = cast(u64) (maxX - minX)
        for var y = minY; y < maxY; y += 1 do
            Memory.clear(stencilBuf + cast(u64) y * cast(u64) image.width + cast(u64) minX, runWidth)

        // The masked general write reduces to raw byte stores for the BGRA8 targets every frame
        // clears: all channels under a forced or full mask, or the three color bytes under the
        // default mask, whose disabled alpha simply keeps the fourth byte in place.
        let writeAll = forceColorMask or (.colorMask.r and .colorMask.g and .colorMask.b and .colorMask.a)
        let writeRgb = !writeAll and .colorMask.r and .colorMask.g and .colorMask.b and !.colorMask.a
        if image.pixelFormat == .BGRA8 and (writeAll or writeRgb)
        {
            let pixels = image.pixels.buffer!

            // Transparent target clears are the common layer setup. Clear each contiguous
            // BGRA row in one operation instead of issuing four stores per pixel.
            if writeAll and !color.a and !color.r and !color.g and !color.b
            {
                let byteCount = runWidth * 4
                for var y = minY; y < maxY; y += 1
                {
                    let row = pixels + cast(u64) ((image.height - y - 1) * image.rowStride + minX * 4)
                    Memory.clear(row, byteCount)
                }

                return
            }

            let fill = cast(Math.Simd.U8x16) [color.b, color.g, color.r, color.a,
                                              color.b, color.g, color.r, color.a,
                                              color.b, color.g, color.r, color.a,
                                              color.b, color.g, color.r, color.a]
            for var y = minY; y < maxY; y += 1
            {
                let row       = pixels + cast(u64) ((image.height - y - 1) * image.rowStride + minX * 4)
                var offset    = 0'u64
                let byteCount = runWidth * 4
                while byteCount - offset >= #sizeof(Math.Simd.U8x16)
                {
                    if writeAll do
                        Math.Simd.store(row + offset, fill)
                    else do
                        Math.Simd.store(row + offset, Math.Simd.select(CpuBgraRgbMask, fill, Math.Simd.load(row + offset)))
                    offset += #sizeof(Math.Simd.U8x16)
                }

                while offset < byteCount
                {
                    row[offset]     = color.b
                    row[offset + 1] = color.g
                    row[offset + 2] = color.r
                    if writeAll do
                        row[offset + 3] = color.a
                    offset += 4
                }
            }

            return
        }

        for var y = minY; y < maxY; y += 1
        {
            for var x = minX; x < maxX; x += 1
            {
                if forceColorMask
                {
                    writePixel(image, x, y, color)
                    continue
                }

                let old = readPixel(image, x, y)
                var out = color
                if !.colorMask.r do
                    out.r = old.r
                if !.colorMask.g do
                    out.g = old.g
                if !.colorMask.b do
                    out.b = old.b
                if !.colorMask.a do
                    out.a = old.a
                writePixel(image, x, y, out)
            }
        }
    }

    mtd resetDrawState()
    {
        .modelTransform = Transform2.Identity
        .scissorOn      = false
        .blendingMode   = .Alpha
        .colorMask      = {true, true, true, false}
        .paintOn        = false
        .program        = CpuProgram_Default
        .stencilOn      = false
        .stencilWrite   = false
        .stencilMode    = .Set
        .font           = null
        .fontAtlasIndex = -1
        .fontEffect     = {}
        .overlapMode    = false
        .overlapPass    = 0
        .alphaResolve   = false
        let image = .currentImage()
        if image do
            .ensureStencil(image.width, image.height)
    }

    mtd replayTargetAlpha(painter: *Painter, first, last: u64)
    {
        let image = .currentImage()
        if !image do
            return

        .clearAlpha(image)
        .alphaResolve = true
        for var i = first; i < last; i += 1
        {
            let replay = &painter.commandBuffer[i]
            switch replay.id
            {
            case .Transform, .StartFont, .StartMsdfFont, .EndFont, .ResetTexture0,
                 .BindTexture0, .ResetTextureFont, .BindTextureFont, .SetFontEffect,
                 .DrawTriangles: .executeCommand(painter, replay, i)
            }
        }

        .alphaResolve = false
    }

    mtd executeCommand(painter: *Painter, cmd: const *Command, cmdIdx: u64)
    {
        switch cmd.id
        {
        case .SetBlendingMode:
            .blendingMode = cmd.blendingMode.mode

        case .Clear:
            .clearCurrent(cmd.clear.color)

        case .ColorMask:
            .colorMask = cmd.colorMask

        case .Transform:
            .modelTransform = cmd.transform.tr

        case .StartClippingRegion:
            .stencilOn    = true
            .stencilWrite = true
            .stencilMode  = cmd.clippingRegion.mode

        case .SetClippingRegionMode:
            .stencilMode = cmd.clippingRegion.mode

        case .EndClippingRegion:
            .stencilWrite = false

        case .ResetClippingRegion:
            .stencilOn    = false
            .stencilWrite = false

        case .SetClippingRect:

            // Painter clip rectangles are logical; the scissor tests device pixels.
            .scissorOn          = true
            .scissorRect.x      = Math.round(cmd.clippingRect.rect.x * .contentScale)
            .scissorRect.y      = Math.round(cmd.clippingRect.rect.y * .contentScale)
            .scissorRect.width  = Math.round(cmd.clippingRect.rect.right() * .contentScale) - .scissorRect.x
            .scissorRect.height = Math.round(cmd.clippingRect.rect.bottom() * .contentScale) - .scissorRect.y

        case .ResetClippingRect:
            .scissorOn = false

        case .StartNoOverlap:
            .overlapMode = true

        case .StopNoOverlap:
            .overlapMode = false

        case .DrawTriangles:
            .drawTriangles(painter, cmd.drawTriangles.start, cmd.drawTriangles.count)

        case .StartFont:
            .program = CpuProgram_Font

        case .StartMsdfFont:
            .program = CpuProgram_Msdf

        case .EndFont:
            .program = CpuProgram_Default

        case .BindTextureFont:
            .font           = cmd.textureFont.font
            .fontAtlasIndex = cmd.textureFont.atlasIndex

        case .ResetTextureFont:
            .font           = null
            .fontAtlasIndex = -1

        case .UpdateFont:

            // Glyph pixels already live in CPU memory; no upload is required.
            break

        case .ResetTexture0:
            .paintOn = false

        case .BindTexture0:
            .paintCommand = cmd[]
            if cmd.texture0.gradientStopCount do
                .gradientStops = @mkslice(painter.gradientStops.buffer + cmd.texture0.gradientStopStart, cmd.texture0.gradientStopCount)
            else do
                .gradientStops = null
            .paintOn = true

        case .ReleaseTexture:
            var texture = cmd.texture0.texture
            me.removeTextureImpl(&texture)

        case .BindRenderTarget:
            .bindRenderTargetImpl(cmd.renderTgt.tgt)
            let target = .curRT!
            target.paintAlpha    = cmd.renderTgt.paintAlpha
            target.paintAlphaIdx = cmdIdx

        case .UnbindRenderTarget:
            let target = .curRT!
            if target.paintAlpha do
                .replayTargetAlpha(painter, target.paintAlphaIdx, cmdIdx)
            .unbindRenderTargetImpl()

        case .ReleaseRenderTarget:
            .releaseRenderTargetImpl(cmd.renderTgt.tgt)

        case .SetDefaultShader:
            switch #complete cmd.defaultShader.id
            {
            case .Default:
                .program = CpuProgram_Default

            case .Simple:
                .program = CpuProgram_Simple

            case .Blur:

                // The blur samples target texels; a logical radius must cover the
                // same on-screen extent whatever the content scale.
                .program    = CpuProgram_Blur
                .blurAxis   = cmd.defaultShader.axis
                .blurRadius = cmd.defaultShader.radius * .contentScale

            case .Resolve:
                .program       = CpuProgram_Resolve
                .resolveFactor = cmd.defaultShader.factor
            }

        case .SetShader:
            let shader = cmd.shader.shader
            if !shader do
                .program = CpuProgram_Default
            else do
                Debug.assert(false, "RenderCpu does not support custom shaders")

        case .SetShaderParam:
            Debug.assert(false, "RenderCpu does not support custom shader parameters")

        case .SetFontEffect:
            .fontEffect = cmd.fontEffect
        }
    }
}

impl RenderCpu
{
    // Releases pooled render-target descriptors owned by the renderer.
    mtd opDrop()
    {
        for rt in .stackReleasedRT do
            Memory.delete(rt)
    }

    // Resets all renderer-owned resources and returns to an empty deterministic state.
    //
    // Every outstanding texture and render-target handle from this renderer becomes invalid.
    mtd reset()
    {
        @drop(me, 1)
        @init(me, 1)
    }

    // Starts a CPU frame with the requested positive BGRA surface dimensions.
    //
    // Reusing the same dimensions preserves the surface pixels until they are cleared or drawn
    // over. No native context is created.
    mtd begin(width, height: s32)
    {
        Debug.assert(width > 0 and height > 0, "RenderCpu.begin needs positive width and height")
        .ensureSurface(width, height)
        .resetTransformImpl()
    }

    // Finishes a CPU frame.
    //
    // CPU rendering is synchronous, so this operation does not present or wait for work.
    internal mtd endImpl() {}

    // Returns an owned copy of the current surface pixels.
    mtd surfaceImage()->Image
    {
        Debug.assert(.surface.isValid(), "surfaceImage needs an active CPU surface")
        return .surface
    }

    // Clears the active target, or the frame surface, to transparent black.
    //
    // All color channels are written; an active direct scissor rectangle still limits the clear.
    internal mtd clearImpl()
    {
        .clearCurrent(Color.fromArgb(Argb.Zero), true)
    }

    // Returns the active target size in pixels.
    internal mtd targetSizeImpl()->{ width, height: s32 }
    {
        let image = .currentImage()
        if image do
            return {image.width, image.height}
        return {0, 0}
    }

    // Restricts following writes to a surface-space rectangle.
    internal mtd setScissorRectImpl(rect: Math.Rectangle)
    {
        .scissorOn   = true
        .scissorRect = rect
    }

    // Disables the surface-space scissor rectangle.
    internal mtd resetScissorRectImpl()
    {
        .scissorOn = false
    }

    // Executes a completed painter command stream synchronously.
    //
    // The painter must have been ended and must remain unchanged until this call returns.
    internal mtd drawImpl(painter: *Painter)
    {
        .resetDrawState()
        .contentScale = painter.contentScale()
        for &cmd, idx in painter.commandBuffer do
            .executeCommand(painter, cmd, cast(u64) idx)
    }

    // Binds an off-screen target for following direct operations or painter submission.
    //
    // The target is borrowed until [[Pixel.RenderCpu.unbindRenderTarget]] restores its parent.
    internal mtd bindRenderTargetImpl(rt: *RenderTarget)
    {
        Debug.assert(rt != null, "bindRenderTarget needs a target")
        if !rt.colorBuffer.isValid() do
            return
        if .curRT do
            .stackRT.add(.curRT)
        .curRT            = rt
        .curRT.paintAlpha = false
        .ensureStencil(rt.colorBuffer.width, rt.colorBuffer.height)
    }

    // Reads a rectangle of an off-screen target into a new image.
    //
    // The rectangle is clamped to the target and must retain at least one pixel.
    internal mtd readRenderTargetImpl(rt: const *RenderTarget, x, y, width, height: s32)->Image
    {
        Debug.assert(rt != null and width > 0 and height > 0, "readRenderTarget needs a target and positive dimensions")
        let storage = .findTexture(rt.colorBuffer.handle)
        Debug.assert(storage != null, "render target is not owned by this renderer")
        let source = storage!

        // Cropping a copy allocates and walks the whole target a second time, and the read that
        // matters — a page, a thumbnail, a captured frame — asks for the whole of it.
        if x == 0 and y == 0 and width == source.image.width and height == source.image.height
        {
            var whole: retval = source.image
            return whole
        }

        var result: retval = source.image.cropped(x, y, width, height)
        return result
    }

    // Reads the active target into a new image, then restores the previous target.
    internal mtd unbindRenderTargetToImageImpl(x, y, width, height: s32)->Image
    {
        let rt     = .curRT!
        var result = .readRenderTargetImpl(rt, x, y, width, height)
        .unbindRenderTargetImpl()
        return result
    }

    // Restores the previous render target, or the frame surface.
    internal mtd unbindRenderTargetImpl()
    {
        if .stackRT.count do
            .curRT = .stackRT.popBack()
        else do
            .curRT = null
    }

    // Creates a transparent off-screen BGRA target with positive dimensions.
    internal mtd createRenderTargetImpl(width, height: s32)->RenderTarget
    {
        Debug.assert(width > 0 and height > 0, "createRenderTarget needs positive width and height")

        let targetHandle = cast(RenderTargetHandle) .nextHandle
        .nextHandle += 1
        let textureHandle = cast(TextureHandle) .nextHandle
        .nextHandle += 1

        var result: retval
        result.attach(targetHandle, textureHandle, .BGRA8, width, height)

        var storage: CpuTexture
        storage.handle = textureHandle
        storage.image  = Image.create(width, height, .BGRA8)
        storage.image.clear()
        .textures.add(#move storage)
        return result
    }

    // Releases an off-screen target and invalidates its descriptor.
    internal mtd deleteRenderTargetImpl(rt: *RenderTarget)
    {
        if rt.handle == InvalidRenderTargetHandle or !rt.colorBuffer.isValid() do
            return
        .removeTextureStorage(rt.colorBuffer.handle)
        rt.clear()
    }

    // Loads an image file and registers an owned CPU texture.
    internal mtd addImageImpl(fullName: string)->Texture fail
    {
        let image = Image.load(fullName)
        return .addImageImpl(&image)
    }

    // Copies an image into a renderer-owned CPU texture.
    // Registers a planar picture.
    //
    // This backend has no shaders, so it converts once here rather than once per sample and holds
    // an ordinary packed surface. The descriptor still says the picture is planar, which is what
    // the caller handed over.
    internal mtd addImageImpl(view: const *Yuv420View)->Texture
    {
        if view.width <= 0 or view.height <= 0 do
            return {}

        var image = Image.create(view.width, view.height, .RGB8)
        view.convertToRgb(&image)

        var result: retval
        result.attach(cast(TextureHandle) .nextHandle, .Yuv420, view.width, view.height)
        .nextHandle += 1

        var storage: CpuTexture
        storage.handle = result.handle
        storage.image  = #move image
        .textures.add(#move storage)
        return result
    }

    // Converts a planar picture into the surface that holds it.
    internal mtd updatePlanarImpl(texture: Texture, view: const *Yuv420View)
    {
        if !texture.isValid() do
            return
        let storage = .findTexture(texture.handle)
        Debug.assert(storage != null, "texture is not owned by this renderer")
        view.convertToRgb(&storage!.image)
    }

    internal mtd addImageImpl(image: const *Image)->Texture
    {
        if !image.isValid() do
            return {}

        var result: retval
        result.attach(cast(TextureHandle) .nextHandle, image.pixelFormat, image.width, image.height)
        .nextHandle += 1

        var storage: CpuTexture
        storage.handle = result.handle
        storage.image  = image[]
        .textures.add(#move storage)
        return result
    }

    // Replaces all bytes of a renderer-owned texture.
    //
    // `pixels` must address at least [[Pixel.Texture.byteCount]] readable bytes.
    internal mtd updateTextureImpl(texture: Texture, pixels: const *u8)
    {
        let storage = .findTexture(texture.handle)
        Debug.assert(storage != null, "texture is not owned by this renderer")
        let target = storage!
        Memory.copy(target.image.pixels.buffer, pixels, target.image.byteCount)
    }

    // Reads a renderer-owned texture into the requested tightly packed format.
    internal mtd readTexturePixelsImpl(texture: Texture, pixelFormat: PixelFormat)->Array'u8
    {
        var result: retval
        if !texture.isValid() do
            return result
        let storage = .findTexture(texture.handle)
        Debug.assert(storage != null, "texture is not owned by this renderer")
        let source = storage!
        let image  = source.image.convertedTo(pixelFormat)
        result = image.pixels
        return result
    }

    // Releases a renderer-owned texture and invalidates its descriptor.
    internal mtd removeTextureImpl(texture: *Texture)
    {
        if !texture.isValid() do
            return
        .removeTextureStorage(texture.handle)
        texture.clear()
    }

    // Translates following painter submissions in surface pixels.
    internal mtd translateTransformImpl(x, y: f32)
    {
        .worldTransform.multiply(Transform2.createTranslation(x, y))
    }

    // Rotates following painter submissions around the surface origin.
    internal mtd rotateTransformImpl(angle: Math.Angle)
    {
        .worldTransform.multiply(Transform2.createRotation(angle.radians, 0, 0))
    }

    // Rotates following painter submissions around a surface-space center.
    internal mtd rotateTransformImpl(angle: Math.Angle, centerX, centerY: f32)
    {
        .worldTransform.multiply(Transform2.createRotation(angle.radians, centerX, centerY))
    }

    // Scales following painter submissions independently on both axes.
    internal mtd scaleTransformImpl(x, y: f32)
    {
        .worldTransform.multiply(Transform2.createScale(x, y, 0, 0))
    }

    // Scales following painter submissions uniformly.
    internal mtd scaleTransformImpl(scale: f32)
    {
        .scaleTransformImpl(scale, scale)
    }

    // Restores the identity world transform.
    internal mtd resetTransformImpl()
    {
        .worldTransform = Transform2.Identity
    }

    // Acquires a pooled off-screen target at least as large as the requested size.
    //
    // The renderer owns the returned descriptor. Return it with
    // [[Pixel.RenderCpu.releaseRenderTarget]] after unbinding it.
    internal mtd acquireRenderTargetImpl(width, height: s32)->*RenderTarget
    {
        Debug.assert(width > 0 and height > 0, "acquireRenderTarget needs positive width and height")
        let w2 = Math.roundUpToPowerOf2(cast(u32) width)
        let h2 = Math.roundUpToPowerOf2(cast(u32) height)

        // Prefer the same-size bucket before consuming a larger target. Besides retaining
        // the expensive large allocations for draws that need them, this mirrors RenderOgl
        // and keeps the sampled texture extent aligned with the requested layer whenever possible.
        for rt, idx in .stackReleasedRT
        {
            let candidate = rt!
            if candidate.colorBuffer.width == w2 and candidate.colorBuffer.height == h2
            {
                .stackReleasedRT.removeAt(idx)
                return candidate
            }
        }

        for rt, idx in .stackReleasedRT
        {
            let candidate = rt!
            if candidate.colorBuffer.width >= w2 and candidate.colorBuffer.height >= h2
            {
                .stackReleasedRT.removeAt(idx)
                return candidate
            }
        }

        let result = Memory.new'RenderTarget()
        result[] = .createRenderTargetImpl(cast(s32) w2, cast(s32) h2)
        return result
    }

    // Returns a pooled target to this renderer; `null` is ignored.
    //
    // `target` must be a currently unbound pointer returned by
    // [[Pixel.RenderCpu.acquireRenderTarget]]. Ownership transfers back to the renderer.
    internal mtd releaseRenderTargetImpl(target: #null *RenderTarget)
    {
        if target do
            .stackReleasedRT.add(target)
    }
}
