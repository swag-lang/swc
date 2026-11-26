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

    internal backdropCache: [2] CpuBackdropCache

    private
    {
        nextHandle: u64 = 1
        generation: TextureGeneration
        textures:   Array'CpuTexture

        surface:     Image
        scanScratch:   ScanScratch
        scanClip:      ScanIntersection

        stackReleasedRT: Array'(*RenderTarget?)
        stackRT:         Array'(*RenderTarget?)
        curRT:           *RenderTarget?

        worldTransform: Transform2 = Transform2.Identity
        modelTransform: Transform2 = Transform2.Identity
        contentScale:   f32        = 1     // Device pixels per unit of the painter stream being drawn.

        scissorOn:   bool
        scissorRect: Math.Rectangle

        blendingMode: BlendingMode = Alpha
        colorMask:    ColorMask    = {true, true, true, false}

        paint:         BrushBinding
        gradientStops: const [..] GradientStop?
        paintOn:       bool
        program:       u8

        // The clipping region is a coverage plane, one byte per device pixel of the target: a
        // region cut along a curve keeps the fraction of each pixel its edge covers, so what is
        // painted through it keeps a smooth edge.
        surfaceStencil: CpuStencil
        stencilOn:      bool
        stencilWrite:   bool
        stencilMode:    ClippingMode = Set
        stackStencilOn: Array'bool     // Regions suspended by the render targets bound inside them.

        font:           *Font?
        fontAtlasIndex: s32 = -1
        fontEffect:     FontEffectParams
        overlapMode:    bool
        overlapPass:    u8
        overlapAlpha:   Array'u8
        overlapWritten: Array'u8
        overlapRows:    Array'OverlapRow
        alphaResolve:   bool
        whiteMatte:     [*] u8?

        blurAxis:      s32
        blurRadius:    f32 = 4
        resolveFactor: s32 = 1
        backdropPass:  BackdropPass
    }
}

// Two source/result pairs fit a full 4K backdrop without retaining pooled texture padding.
internal struct CpuBackdropCache
{
    source: Image
    result: Image
    key:    CpuBackdropCacheKey
    valid:  bool
    used:   bool
    hits:   u64
}

internal struct CpuBackdropCacheKey
{
    radius, scale: f32
    sourceWidth, sourceHeight, targetWidth, targetHeight: s32
    textureRect, boundRect: Vector4
    transform:     Transform2
}

internal impl CpuBackdropCache
{
    // Each of the two passes owns at most 64 MiB, counting both retained images.
    const MaxBytes = 64'u64 * 1024 * 1024

    func acceptsSize(width, height: s32)->bool => width > 0 and height > 0 and cast(u64, width) <= MaxBytes / 8 / cast(u64, height)

    mtd const retainedBytes()->u64 => .source.pixels.count + .result.pixels.count
}

// A texture of [[Pixel.RenderCpu]], held in system memory.
#[Swag.Opaque]
internal struct CpuTexture
{
    public
    {
        handle:  TextureHandle
        image:   Image
        stencil: CpuStencil
        planar:  CpuPlanarTexture
    }
}

// CPU-owned copies of the source planes, sampled before RGB conversion like the GPU shader.
private struct CpuPlanarTexture
{
    luma, chromaB, chromaR: Array'u8
    width, height, chromaWidth, chromaHeight: s32 = 0
    matrix:      YuvMatrix = .Bt601
    studioRange: bool      = false
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
    const Empty = PixelBounds{0, 0, -1, -1}

    // Reports whether the rectangle covers no pixel at all.
    mtd const isEmpty()->bool => .minX > .maxX or .minY > .maxY

    // Returns the number of pixel rows the rectangle spans.
    mtd const rows()->s32 => .maxY - .minY + 1

    // Returns the number of pixels the rectangle spans.
    mtd const area()->u64 => cast(u64, (.maxX - .minX + 1)) * cast(u64, .rows())
}

private struct CpuStencil
{
    pixels: Array'u8
    width:  s32
    dirty:  PixelBounds = PixelBounds.Empty
}

private struct OverlapRow
{
    first: s32 = Swag.S32.Max
    last:  s32 = -1
}

private
{
    // Pixel area below which splitting a batch into bands costs more than the rasterization saves.
    const CpuBandPixelThreshold: u64 = 64 * 1024

    // Rows per raster block, amortizing triangle setup without tying blocks to worker count.
    const CpuBandRows: s32 = 16

    const CpuProgram_Default:  u8 = 0
    const CpuProgram_Simple:   u8 = 1
    const CpuProgram_Font:     u8 = 2
    const CpuProgram_Msdf:     u8 = 3
    const CpuProgram_Blur:     u8 = 4
    const CpuProgram_Resolve:  u8 = 5
    const CpuProgram_Backdrop: u8 = 6

    // Four BGRA pixels share these byte masks in the packed span kernels.
    const CpuBgraRgbMask   = cast(Math.Simd.U8x16, [255'u8, 255, 255, 0, 255, 255, 255, 0, 255, 255, 255, 0, 255, 255, 255, 0])
    const CpuBgraAlphaMask = cast(Math.Simd.U8x16, [0'u8, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255])

    // Alpha factor of the bitmap font shader per atlas byte: pow(byte / 255, FontGamma).
    //
    // Filled on first use with the exact expression the per-pixel path evaluated, so a lookup
    // returns bit-identical factors. The mutex protects concurrent renderer initialization.
    var g_FontGammaLut:      [256] f32
    var g_FontGammaOpaque:   [256] u8
    var g_FontGammaLutReady: bool
    var g_FontGammaLutMutex: Swag.Mutex
}

private func ensureFontGammaLut()
{
    g_FontGammaLutMutex.lock()
    defer g_FontGammaLutMutex.unlock()

    if g_FontGammaLutReady do
        return
    for i in 256
    {
        let gamma = Math.pow(cast(f32, i) / 255.0, FontGamma)
        g_FontGammaLut[i]    = gamma
        g_FontGammaOpaque[i] = cast(u8, Math.clamp(Math.round(255.0 * gamma), 0.0, 255.0))
    }

    g_FontGammaLutReady = true
}

// Everything a triangle range resolves once, so the pixel loops read plain locals instead of
// re-deriving transforms, clips, formats, paint textures, and font atlases per pixel.
private struct RasterBatch
{
    image:     *Image?
    painter:   *Painter?
    start:     u32
    count:     u32
    transform: Transform2

    late pixels: [*] u8     // Target pixel base; rows are stored bottom-up.
    rowStride:   s32
    width:       s32
    height:      s32

    // Device clip, target bounds and scissor folded into one inclusive pixel rectangle.
    clipMinX: s32
    clipMinY: s32
    clipMaxX: s32
    clipMaxY: s32

    late stencil: [*] u8     // Stencil plane of the target, one byte per pixel, top-down rows.
    overlapRows:  [*] OverlapRow?

    solidPaint:  bool                   // The paint multiplies by opaque white, which is the identity.
    paintImage:  *Image?                // Storage of a bound texture paint, resolved once.
    paintPlanar: *CpuPlanarTexture?     // Source planes for video textures.
    atlas:       const *GlyphAtlas?     // Glyph atlas of the bound font, resolved once.
    subRect:     SubRectSampler
    atlasMaxX:   s32
    atlasMaxY:   s32

    blurTaps:        const [*] BlurTap?     // Texture blur taps owned by the active draw call.
    blurTapCount:    u64
    blurWeights:     const [*] f32?     // Backdrop weights owned by the active draw call.
    blurWeightCount: u64
    backdropPixels:  const [*] Math.Simd.F32x4?     // Logical top-down samples prepared once for a Gaussian pass.
}

private struct SubRectSampler
{
    origin, size, span, sharpWidth: Vector2
    minX, minY, maxX, maxY:         s32
    nearest, sharp:                 bool
}

private struct BlurTap
{
    offset: f32
    weight: f32
}

private struct FontLinearAxis
{
    first, second: s32
    fraction:      f32
}

// A position in a glyph atlas, kept as a whole texel and an offset from it in texels.
//
// Where a glyph lands in its atlas depends on the text its font drew before. A normalized
// coordinate rounds at the magnitude of that placement, so the same glyph would shade an
// antialiased pixel a step lighter or darker depending on draw order. The offset from a whole
// texel near the glyph keeps the precision of every sample independent of where the glyph lies.
private struct AtlasPoint
{
    baseX, baseY: s32
    offset:       Vector2
}

private impl AtlasPoint
{
    mtd const moved(delta: Vector2)->AtlasPoint => {.baseX, .baseY, .offset + delta}
}

// How one triangle maps target pixels onto the glyph atlas, in texels from its first vertex.
//
// The vertices of a glyph quad sit on whole texels of its cell, so the differences between
// them, and every interpolated offset, are computed alike wherever the cell lies in the page.
private struct FontFrame
{
    baseX, baseY: s32
    origin:       Vector2     // First vertex, as an offset from the base texel.
    edge1:        Vector2     // Second vertex minus the first, in texels.
    edge2:        Vector2     // Third vertex minus the first, in texels.
    dx:           Vector2     // Texel step of one target pixel to the right.
    dy:           Vector2     // Texel step of one target pixel down.

    tapOffset:   Vector2
    screenRange: f32
}

private impl FontFrame
{
    func from(atlas: const *GlyphAtlas, uv0, uv1, uv2, p0, p1, p2: Vector2, invArea: f32)->FontFrame
    {
        let size  = Vector2{cast(f32, (atlas.width / atlas.bytesPerPixel)), cast(f32, atlas.height)}
        let first = uv0 * size
        var result: FontFrame
        result.baseX  = cast(s32, Math.floor(first.x))
        result.baseY  = cast(s32, Math.floor(first.y))
        result.origin = first - Vector2{cast(f32, result.baseX), cast(f32, result.baseY)}
        result.edge1  = (uv1 - uv0) * size
        result.edge2  = (uv2 - uv0) * size
        result.dx     = (result.edge1 * (p2.y - p0.y) + result.edge2 * (p0.y - p1.y)) * invArea
        result.dy     = (result.edge1 * (p0.x - p2.x) + result.edge2 * (p1.x - p0.x)) * invArea
        return result
    }

    // The texel steps are constant over the entire triangle.
    mtd prepareMsdf()
    {
        let fwX     = Math.abs(.dx.x) + Math.abs(.dy.x)
        let fwY     = Math.abs(.dx.y) + Math.abs(.dy.y)
        let screenX = fwX > 0.000001 ? MsdfRange / fwX : 0.0
        let screenY = fwY > 0.000001 ? MsdfRange / fwY : 0.0
        .screenRange = Math.max(0.5 * (screenX + screenY), 1.0)
        .tapOffset   = {fwX * 0.25, fwY * 0.25}
    }

    // Returns the atlas position of the fragment with barycentric weights `w1` and `w2`.
    #[Swag.Inline]
    mtd const at(w1, w2: f32)->AtlasPoint => {.baseX, .baseY, .origin + .edge1 * w1 + .edge2 * w2}
}

private impl RenderCpu
{
    mtd ensureGeneration()->bool
    {
        if .generation.tag do
            return true

        var generation: TextureGeneration
        var outcome:    Swag.Error
        catch { generation = try TextureGeneration.claim() } as outcome
        if outcome.value() != null do
            return false
        .generation = generation
        return true
    }

    mtd findTexture(handle: TextureHandle)->*CpuTexture?
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

    mtd currentImage()->*Image?
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

    mtd currentStencil()->*CpuStencil
    {
        if .curRT
        {
            let texture = unwrap .findTexture(.curRT.colorBuffer.handle)
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
        .surfaceStencil = {}
    }

    mtd ensureStencil(width, height: s32)
    {
        let count   = cast(u64, width) * cast(u64, height)
        let stencil = .currentStencil()
        if stencil.width == width and stencil.pixels.count == count do
            return
        stencil.pixels.resize(count)
        Memory.clear(stencil.pixels.storage(), count)
        stencil.width = width
        stencil.dirty = PixelBounds.Empty
    }

    mtd clearStencil()
    {
        let stencil = .currentStencil()
        if stencil.dirty.isEmpty() do
            return
        clearScratchRows(stencil.pixels.storage(), stencil.width, stencil.dirty)
        stencil.dirty = PixelBounds.Empty
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
    // Rounding matches drawTriangleBatch. The result bounds scratch resets and band splits.
    mtd triangleRangeBounds(image: *Image, painter: *Painter, triangles: const *TriangleBatch, transform: Transform2)->PixelBounds
    {
        var lowest  = Vector2.Max
        var highest = Vector2.Min

        // Each output axis depends on one input axis, so transforming the recorded
        // extrema gives exactly the same bounds as transforming every vertex.
        let axisAligned = (transform.m12 == 0 and transform.m21 == 0) or
                          (transform.m11 == 0 and transform.m22 == 0)
        if axisAligned
        {
            let first = transform.transformPoint(triangles.bbMin)
            let last  = transform.transformPoint(triangles.bbMax)
            lowest  = {Math.min(first.x, last.x), Math.min(first.y, last.y)}
            highest = {Math.max(first.x, last.x), Math.max(first.y, last.y)}
        }
        else
        {
            let start = triangles.start
            let end   = start + triangles.count
            for var i = start; i < end; i += 1
            {
                let p = transform.transformPoint(painter.vertexBuffer[i].pos)
                lowest.x  = Math.min(lowest.x, p.x)
                lowest.y  = Math.min(lowest.y, p.y)
                highest.x = Math.max(highest.x, p.x)
                highest.y = Math.max(highest.y, p.y)
            }
        }

        var result: #returntype
        result.minX = Math.clamp(cast(s32, Math.floor(lowest.x)), 0, image.width - 1)
        result.minY = Math.clamp(cast(s32, Math.floor(lowest.y)), 0, image.height - 1)
        result.maxX = Math.clamp(cast(s32, Math.ceil(highest.x)) - 1, 0, image.width - 1)
        result.maxY = Math.clamp(cast(s32, Math.ceil(highest.y)) - 1, 0, image.height - 1)

        if .scissorOn
        {
            result.minX = Math.max(result.minX, cast(s32, .scissorRect.x))
            result.minY = Math.max(result.minY, cast(s32, .scissorRect.y))
            result.maxX = Math.min(result.maxX, cast(s32, .scissorRect.right()) - 1)
            result.maxY = Math.min(result.maxY, cast(s32, .scissorRect.bottom()) - 1)
        }

        return result
    }

    // Returns an interpolated coverage attribute as a signed distance from the contour.
    //
    // A band carries its ramp in zero to one, and subtracting the contour signs it. A measured
    // stroke carries a signed distance around [[Pixel.StrokeCoverageBias]] instead, because one
    // quad has to describe both of its sides; the two travel in the same batch and are told apart
    // by range. This is the OpenGL fragment program's rule, and the two have to agree to the
    // pixel — see `render.parity.swg`.
    #[Swag.Inline]
    func signedCoverage(raw: f32)->f32
    {
        if raw > StrokeCoverageBias * 0.5 do
            return 0.5 - Math.abs(raw - StrokeCoverageBias)
        return raw - 0.5
    }

    // Zeroes `bounds` inside a per-pixel scratch plane stored as `width` bytes per row.
    func clearScratchRows(plane: [*] u8, width: s32, bounds: PixelBounds)
    {
        let runWidth = cast(u64, (bounds.maxX - bounds.minX + 1))
        for var y = bounds.minY; y <= bounds.maxY; y += 1 do
            Memory.clear(plane + cast(u64, y) * cast(u64, width) + cast(u64, bounds.minX), runWidth)
    }

    func edge(a, b, p: Vector2)->f32 => Math.mulAdd(-(b.y - a.y), p.x - a.x, (b.x - a.x) * (p.y - a.y))

    // Says whether the edge from `a` to `b` owns the pixel centres lying exactly on it.
    //
    // A left edge does, and of the two horizontal edges the lower one does. That is the fill rule
    // of a GPU seen from this top-down surface: OpenGL applies its top-left rule in a window
    // whose rows run upward, so the edge it calls the top one is the lower one here. A one-pixel
    // rule drawn on a whole coordinate therefore lands on the same row on both renderers.
    func isTopLeft(a, b: Vector2)->bool
    {
        let dx = b.x - a.x
        let dy = b.y - a.y
        return dy < 0 or (dy == 0 and dx < 0)
    }

    // Classify the rounded edge bits so the shared-edge tie survives inlining.
    #[Swag.Inline]
    func insideEdge(value: f32, topLeft: bool)->bool
    {
        let bits      = cast #bit(u32, value)
        let magnitude = bits & 0x7FFF_FFFF
        if not magnitude do
            return topLeft
        return bits <= 0x7F80_0000
    }

    // A rounded edge test is monotonic along a row. Once its outside columns are
    // trimmed, every interior pixel can use the same coverage without rechecking it.
    #[Swag.Inline]
    func trimEdgeSpan(x0, x1: *s32, a, c, origin: f32, topLeft: bool)
    {
        if a == 0
        {
            if not insideEdge(c, topLeft) do
                x1[] = x0[] - 1
        }
        elif a > 0
        {
            while x0[] <= x1[] and not insideEdge(Math.mulAdd(a, cast(f32, x0[]) + 0.5 - origin, c), topLeft) do
                x0[] += 1
        }
        else
        {
            while x0[] <= x1[] and not insideEdge(Math.mulAdd(a, cast(f32, x1[]) + 0.5 - origin, c), topLeft) do
                x1[] -= 1
        }
    }

    // Narrows the columns `x0` to `x1` of one row to those that can pass one edge test.
    //
    // The edge value at pixel centre `sx` is `a * (sx - originX) + c`. A long thin triangle — a
    // stroke band on a diagonal, a spoke of a fan — covers a sliver of its bounding box, and a walk
    // over the box tests mostly pixels outside it. Where `a` is not zero the edge crosses the row
    // once, and every centre on its outer side tests outside, so the row starts or ends there. The
    // bound is moved past that crossing by more than the rounding of the per-pixel test: the
    // narrowed walk skips only pixels the test rejects, and paints the image the box walk paints.
    func narrowEdgeSpan(x0, x1: *s32, a, c, originX: f32)
    {
        // The value is the same across the row, so one negative value rejects all of it.
        if a == 0
        {
            if c < 0 do
                x1[] = x0[] - 1
            return
        }

        let root = originX - c / a
        if not Math.isFinite(root) do
            return
        let margin = 1 + 0.000001 * (Math.abs(root - originX) + Math.abs(cast(f32, x0[]) - originX) + Math.abs(cast(f32, x1[]) - originX))
        if a > 0
        {
            let first = root - 0.5 - margin
            if first > cast(f32, x1[]) do
                x0[] = x1[] + 1
            elif first > cast(f32, x0[]) do
                x0[] = cast(s32, first)
        }
        else
        {
            let last = root - 0.5 + margin
            if last < cast(f32, x0[]) do
                x1[] = x0[] - 1
            elif last < cast(f32, x1[]) do
                x1[] = cast(s32, last) + 1
        }
    }

    func lerpColor(c0, c1: Color, t: f32)->Color
    {
        let u = Math.saturate(t)
        return Color.fromArgbF32((cast(f32, c0.a) + (cast(f32, c1.a) - c0.a) * u) / 255.0,
                                 (cast(f32, c0.r) + (cast(f32, c1.r) - c0.r) * u) / 255.0,
                                 (cast(f32, c0.g) + (cast(f32, c1.g) - c0.g) * u) / 255.0,
                                 (cast(f32, c0.b) + (cast(f32, c1.b) - c0.b) * u) / 255.0)
    }

    // Bilinear texture filtering keeps the two byte-quantizing lerps of the former float path,
    // but evaluates their weights as 16.16 integers instead of converting twelve intermediate
    // colors through normalized floats for every sampled pixel.
    func lerpByte(c0, c1: u8, weight: u32)->u8
    {
        const One = 65536'u32
        return cast(u8, ((cast(u32, c0) * (One - weight) + cast(u32, c1) * weight) >> 16))
    }

    func bilinearColor(c00, c10, c01, c11: Color, tx, ty: f32)->Color
    {
        let wx = bilinearWeight(tx)
        let wy = bilinearWeight(ty)

        var top, bottom, result: Color
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

    #[Swag.Inline]
    func lerpBgra8(c0, c1, weight: u32)->u32
    {
        const Lanes = 0x000000FF000000FF'u64
        const Pair  = 0x00FF00FF'u64
        let a       = cast(u64, c0)
        let b       = cast(u64, c1)
        let inverse = 65536 - cast(u64, weight)

        // Keep the two 16.16 products in separate 32-bit lanes so neither carries into the other.
        let blueRed0    = (a | (a << 16)) & Lanes
        let blueRed1    = (b | (b << 16)) & Lanes
        let greenAlpha0 = ((a >> 8) | (a << 8)) & Lanes
        let greenAlpha1 = ((b >> 8) | (b << 8)) & Lanes
        let blueRed     = ((blueRed0 * inverse + blueRed1 * weight) >> 16) & Lanes
        let greenAlpha  = ((greenAlpha0 * inverse + greenAlpha1 * weight) >> 16) & Lanes
        return cast(u32,
                    ((blueRed | (blueRed >> 16)) & Pair) |
                    (((greenAlpha | (greenAlpha >> 16)) & Pair) << 8))
    }

    // The sign bit of the unsigned weight contributes one whole source difference
    // after the multiply-high. Select that source as the starting value before adding
    // the signed product, including the exact weight of 65536 at the upper endpoint.
    #[Swag.Inline]
    func lerpChannels8(a, b: Math.Simd.U16x8, weight: Math.Simd.S16x8, upper: bool)->Math.Simd.S16x8
    {
        let delta = cast #bit(Math.Simd.S16x8, b - a)
        let start = cast #bit(Math.Simd.S16x8, upper ? b : a)
        return start + Math.Simd.mulHigh(delta, weight)
    }

    #[Swag.Inline]
    internal func lerpBgra8x4(a, b: Math.Simd.U8x16, weight: Math.Simd.S16x8, upper: bool)->Math.Simd.U8x16
    {
        let low  = lerpChannels8(Math.Simd.widenLow(a), Math.Simd.widenLow(b), weight, upper)
        let high = lerpChannels8(Math.Simd.widenHigh(a), Math.Simd.widenHigh(b), weight, upper)
        return Math.Simd.packUnsigned(low, high)
    }

    #[Swag.Inline]
    func bilinearWeight(fraction: f32)->u32 => cast(u32, (Math.saturate(fraction) * 65536.0))

    #[Swag.Inline]
    func loadBgra8(row: const [*] u8, x: s32)->u32
    {
        let pixel = cast(const [*] u32, row)[x]
        #static if Core.BIG_ENDIAN do
            return Swag.byteSwap(pixel)
        else do
            return pixel
    }

    #[Swag.Inline]
    func(const Format: PixelFormat) loadColor8(row: const [*] u8, x: s32)->u32
    {
        #static if Format == .BGRA8 do
            return loadBgra8(row, x)
        elif Format == .RGB16 or Format == .RGBA16
        {
            #[Swag.Inline]
            func normalizedWord(value: u16)->u8 => cast(u8, (cast(u32, value) + 128) / 257)

            const Components = Format == .RGBA16 ? 4 : 3
            let samples = cast(const [*] u16, row) + cast(u64, x) * Components
            let alpha = Format == .RGBA16 ? normalizedWord(samples[3]) : 255'u8
            return Color.fromArgb(alpha, normalizedWord(samples[0]), normalizedWord(samples[1]), normalizedWord(samples[2])).argb
        }

        else
        {
            // Three-byte pixels cannot be read with a four-byte load at the end of a row.
            const Bytes = Format == .RGBA8 ? 4 : 3
            let texel = row + cast(u64, x) * Bytes
            #static if Format == .BGR8 do
                return Color.fromArgb(255'u8, texel[2], texel[1], texel[0]).argb
            elif Format == .RGB8 do
                return Color.fromArgb(255'u8, texel[0], texel[1], texel[2]).argb
            else do
                return Color.fromArgb(texel[3], texel[0], texel[1], texel[2]).argb
        }
    }

    #[Swag.Inline]
    func(const Format: PixelFormat) sampleColor8Bilinear(image: *Image, x0, x1, y0, y1: s32, wx, wy: u32)->Color
    {
        let pixels = image.pixels.storage()
        let stride = cast(u64, image.rowStride)
        let top    = pixels + cast(u64, (image.height - y0 - 1)) * stride
        let c0     = lerpBgra8(loadColor8'Format(top, x0), loadColor8'Format(top, x1), wx)
        if wy == 0 or y0 == y1 do
            return Color.fromArgb(c0)
        let bottom = pixels + cast(u64, (image.height - y1 - 1)) * stride
        let c1     = lerpBgra8(loadColor8'Format(bottom, x0), loadColor8'Format(bottom, x1), wx)
        return Color.fromArgb(lerpBgra8(c0, c1, wy))
    }

    // The caller has clamped the coordinates. Straight integer colors use the same
    // two quantized lerps as the generic sampler after converting texels to bytes.
    #[Swag.Inline]
    func bilinearTexels(image: *Image, x0, x1, y0, y1: s32, tx, ty: f32)->Color
    {
        let wx = bilinearWeight(tx)
        let wy = bilinearWeight(ty)
        if image.alphaMode == .Straight
        {
            switch image.pixelFormat
            {
            case .BGRA8: return sampleColor8Bilinear'(.BGRA8)(image, x0, x1, y0, y1, wx, wy)
            case .RGBA8: return sampleColor8Bilinear'(.RGBA8)(image, x0, x1, y0, y1, wx, wy)
            case .BGR8:  return sampleColor8Bilinear'(.BGR8)(image, x0, x1, y0, y1, wx, wy)
            case .RGB8:  return sampleColor8Bilinear'(.RGB8)(image, x0, x1, y0, y1, wx, wy)
            case .RGB16: return sampleColor8Bilinear'(.RGB16)(image, x0, x1, y0, y1, wx, wy)
            case .RGBA16: return sampleColor8Bilinear'(.RGBA16)(image, x0, x1, y0, y1, wx, wy)
            default:     break
            }
        }

        let c00 = readPixel(image, x0, y0)
        let c10 = readPixel(image, x1, y0)
        let c01 = readPixel(image, x0, y1)
        let c11 = readPixel(image, x1, y1)
        return bilinearColor(c00, c10, c01, c11, tx, ty)
    }

    func modFloor(value, divisor: s32)->s32
    {
        var result = value % divisor
        if result < 0 do
            result += divisor
        return result
    }

    func readPixel(image: *Image, x, y: s32)->Color => image.pixelColor(x, y)

    // Reads one clamped BGRA8 pixel: the exact bytes [[readPixel]] returns for that format,
    // without the per-pixel format dispatch. The sampling helpers call this on every fetch of
    // a texture paint, which is most of what a themed frame rasterizes.
    #[Swag.Inline]
    func fetchBgra8(image: *Image, x, y: s32)->Color
    {
        let cx  = Math.clamp(x, 0, image.width - 1)
        let cy  = image.height - Math.clamp(y, 0, image.height - 1) - 1
        let pix = image.pixels.storage() + cast(u64, (cx * 4)) + cast(u64, cy) * cast(u64, image.width) * 4

        var result: Color
        result.b = pix[0]
        result.g = pix[1]
        result.r = pix[2]
        result.a = pix[3]
        return result
    }

    func writePixel(image: *Image, x, y: s32, color: Color)
    {
        let storageY = image.height - y - 1
        let pixel    = image.pixels.storage() + cast(u64, (storageY * image.rowStride + x * image.bytesPerPixel))

        switch #complete image.pixelFormat
        {
        case .Yuv420, .Yuv444:

            // A surface is always packed: this backend converts a planar picture on upload.
            Swag.assert(false, "cannot write one pixel of a planar picture")

        case .Gray8, .GrayAlpha8, .Gray16, .GrayAlpha16, .GrayF16, .GrayAlphaF16, .GrayF32,
             .GrayAlphaF32, .RGB16, .RGBA16, .RGBF16, .RGBAF16, .RGBF32, .RGBAF32:
            writeLogicalPixelValue(pixel, image.pixelFormat, image.alphaMode, PixelValue{cast(f32, color.r) / 255.0, cast(f32, color.g) / 255.0, cast(f32, color.b) / 255.0, cast(f32, color.a) / 255.0})

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

    func blendSaturation(color: Math.Vector3)->f32 => Math.max(color.x, color.y, color.z) - Math.min(color.x, color.y, color.z)

    func clipBlendColor(color: Math.Vector3)->Math.Vector3
    {
        let luminosity = blendLuminosity(color)
        let minValue   = Math.min(color.x, color.y, color.z)
        let maxValue   = Math.max(color.x, color.y, color.z)
        var result     = color

        if minValue < 0 do
            result = luminosity + (result - luminosity) * luminosity / (luminosity - minValue)
        if maxValue > 1 do
            result = luminosity + (result - luminosity) * (1.0 - luminosity) / (maxValue - luminosity)
        return result
    }

    func setBlendLuminosity(color: Math.Vector3, luminosity: f32)->Math.Vector3 => clipBlendColor(color + luminosity - blendLuminosity(color))

    func setBlendSaturation(color: Math.Vector3, saturation: f32)->Math.Vector3
    {
        let currentSaturation = blendSaturation(color)
        if currentSaturation == 0 do
            return Math.Vector3.Zero

        let minValue = Math.min(color.x, color.y, color.z)
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

    func blendChannel(src, dst, srcAlpha, _: f32, mode: BlendingMode)->f32
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

        case .Multiply, .Screen, .Overlay, .Darken, .Lighten, .ColorDodge, .ColorBurn, .HardLight,
             .SoftLight, .Difference, .Exclusion, .Hue, .Saturation, .Color, .Luminosity:
            return src
        }
    }

    // Applies byte alpha with one exact division, truncating the final channel toward zero.
    //
    // Both weights sum to 255, so the numerator fits in 16 bits and equal colors stay equal.
    // Keeping the weights integral makes quantization independent of floating-point contraction.
    #[Swag.Inline]
    func blendAlphaByte(src, dst, alpha: u8)->u8 => cast(u8, ((cast(u32, src) * alpha + cast(u32, dst) * (255'u32 - alpha)) / 255))

    // Alpha-blends one BGRA8 pixel under the default color mask, preserving its alpha byte.
    #[Swag.Inline]
    func blendAlphaBgra8(pixel: [*] u8, src: Color)
    {
        if src.a == 255
        {
            pixel[0] = src.b
            pixel[1] = src.g
            pixel[2] = src.r
            return
        }

        pixel[0] = blendAlphaByte(src.b, pixel[0], src.a)
        pixel[1] = blendAlphaByte(src.g, pixel[1], src.a)
        pixel[2] = blendAlphaByte(src.r, pixel[2], src.a)
    }

    // Composites four BGRA pixels, preserving the destination alpha bytes.
    #[Swag.Inline]
    func blendAlphaBgra8x4(src, dst, alpha: Math.Simd.U8x16)->Math.Simd.U8x16
    {
        #[Swag.Inline]
        func blendChannels(src, dst, alpha: Math.Simd.U16x8)->Math.Simd.S16x8
        {
            // The numerator is at most 255 * 255. This is the exact floor of n / 255.
            let n = src * alpha + dst * (255'u16 - alpha) + 1'u16
            return cast #bit(Math.Simd.S16x8, (n + (n >> 8)) >> 8)
        }

        let low  = blendChannels(Math.Simd.widenLow(src), Math.Simd.widenLow(dst), Math.Simd.widenLow(alpha))
        let high = blendChannels(Math.Simd.widenHigh(src), Math.Simd.widenHigh(dst), Math.Simd.widenHigh(alpha))
        return Math.Simd.select(CpuBgraRgbMask, Math.Simd.packUnsigned(low, high), dst)
    }

    #[Swag.Inline]
    func coverageAlpha(alpha: u8, coverage: f32)->u8 => cast(u8, Math.clamp(Math.round(cast(f32, alpha) * coverage), 0.0, 255.0))

    mtd blendPixel(image: *Image, x, y: s32, src: Color)
    {
        // A zero-alpha source is coverage, not ink: the OpenGL shader discards it under
        // every mode except 'Copy', where a transparent write is the erase operation.
        if src.a == 0 and .blendingMode != .Copy do
            return

        // GL_MAX ignores blend factors: alpha replay keeps the greatest source coverage.
        if .alphaResolve
        {
            var out = readPixel(image, x, y)
            out.a = Math.max(out.a, src.a)
            writePixel(image, x, y, out)
            return
        }

        let pixelIdx = cast(u64, y) * cast(u64, image.width) + cast(u64, x)

        // The mark pass keeps the coverage a pixel is most covered by, so the draw pass can
        // composite it once. It is the alpha itself, not the alpha weighted by itself: squaring
        // it here made every antialiased fringe and every translucent stroke light by its own
        // opacity a second time, so a stroke at 50% covered a quarter of what it should.
        if .overlapPass == 1
        {
            .overlapAlpha[pixelIdx] = Math.max(.overlapAlpha[pixelIdx], src.a)
            return
        }

        if .overlapPass == 2
        {
            if .overlapWritten[pixelIdx] != 0 do
                return
            .overlapWritten[pixelIdx] = 1

            // The first fragment consumes the maximum alpha accumulated by the mark pass;
            // subsequent overlapping fragments see zero destination alpha and contribute nothing.
            let alpha = .overlapAlpha[pixelIdx]
            if image.pixelFormat == .BGRA8 and image.alphaMode == .Straight
            {
                let offset = cast(u64, image.height - y - 1) * image.rowStride + cast(u64, x) * 4
                let pixel  = image.pixels.storage() + offset
                let color  = Color.fromArgb(alpha, src.r, src.g, src.b)
                blendAlphaBgra8(pixel, color)
                if let matte = .whiteMatte do
                    blendAlphaBgra8(matte + offset, color)
                pixel[3] = 0
                return
            }

            let dst = readPixel(image, x, y)
            let out = Color.fromArgb(0'u8,
                                     blendAlphaByte(src.r, dst.r, alpha),
                                     blendAlphaByte(src.g, dst.g, alpha),
                                     blendAlphaByte(src.b, dst.b, alpha))
            writePixel(image, x, y, out)
            return
        }

        let dst = readPixel(image, x, y)
        if .blendingMode == .Alpha
        {
            var out = dst
            if .colorMask.r do
                out.r = blendAlphaByte(src.r, dst.r, src.a)
            if .colorMask.g do
                out.g = blendAlphaByte(src.g, dst.g, src.a)
            if .colorMask.b do
                out.b = blendAlphaByte(src.b, dst.b, src.a)
            if .colorMask.a do
                out.a = blendAlphaByte(255, dst.a, src.a)
            writePixel(image, x, y, out)
            return
        }

        let sa = cast(f32, src.a) / 255.0
        let da = cast(f32, dst.a) / 255.0

        // The alpha channel composites with a source factor of one, not with the source alpha the
        // colour channels use: weighting it by itself accumulates coverage as a square, so a stack
        // of faint layers reaches almost no opacity at all. This matches the separate blend
        // function the OpenGL renderer sets, so a CPU render and a GPU render cover the same.
        var outA = blendChannel(sa, da, sa, da, .blendingMode)
        if .blendingMode.usesAdvancedBlending() do
            outA = sa + da * (1.0 - sa)

        let srcColor = Math.Vector3{cast(f32, src.r) / 255.0, cast(f32, src.g) / 255.0, cast(f32, src.b) / 255.0}
        let dstColor = Math.Vector3{cast(f32, dst.r) / 255.0, cast(f32, dst.g) / 255.0, cast(f32, dst.b) / 255.0}
        var outColor = Math.Vector3{blendChannel(srcColor.x, dstColor.x, sa, da, .blendingMode),
                                    blendChannel(srcColor.y, dstColor.y, sa, da, .blendingMode),
                                    blendChannel(srcColor.z, dstColor.z, sa, da, .blendingMode)}

        // An advanced equation weighs the backdrop by the destination alpha. When alpha is not
        // being written, that plane is scratch — the window's is never written at all — and a
        // backdrop read as transparent would lose the effect: the stored colour is the backdrop,
        // and it is opaque by definition.
        if .blendingMode.usesAdvancedBlending() do
            outColor = blendAdvanced(srcColor, dstColor, sa, .colorMask.a ? da : 1.0, .blendingMode)

        var out = Color.fromArgbF32(outA, outColor.x, outColor.y, outColor.z)

        if not .colorMask.r do
            out.r = dst.r
        if not .colorMask.g do
            out.g = dst.g
        if not .colorMask.b do
            out.b = dst.b
        if not .colorMask.a do
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

        let x = Math.clamp(nearestTexel(uu * image.width), 0, image.width - 1)
        let y = Math.clamp(nearestTexel((1.0 - vv) * image.height), 0, image.height - 1)
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

        let fx     = uu * image.width - 0.5
        let fy     = (1.0 - vv) * image.height - 0.5
        let floorX = Math.floor(fx)
        let floorY = Math.floor(fy)
        let tx     = fx - floorX
        let ty     = fy - floorY

        func coord(value, size: s32, wrap: bool)->s32
        {
            if wrap do
                return modFloor(value, size)
            return Math.clamp(value, 0, size - 1)
        }

        let baseX = cast(s32, floorX)
        let baseY = cast(s32, floorY)
        let x0    = coord(baseX, image.width, repeat)
        let x1    = coord(baseX + 1, image.width, repeat)
        let y0    = coord(baseY, image.height, repeat)
        let y1    = coord(baseY + 1, image.height, repeat)
        return bilinearTexels(image, x0, x1, y0, y1, tx, ty)
    }

    // Returns the texel a nearest sampler picks for `coordinate`, in texels.
    //
    // The coordinate is first snapped to the 1/256 grid a GPU carries it on. A pixel centre that
    // maps exactly onto a texel boundary then falls on the same side on every row; left to the
    // rounding of the interpolation, each pixel would pick its own side and tear the edge.
    #[Swag.Inline]
    func nearestTexel(coordinate: f32)->s32
    {
        return cast(s32, Math.floor(Math.round(coordinate * 256.0) / 256.0))
    }

    // Reads the texel of a top-down byte plane nearest to the normalized coordinates.
    func fetchPlanarPlane(plane: const *Array'u8, width, height: s32, u, v: f32, repeat: bool)->f32
    {
        var x = nearestTexel(u * width)
        var y = nearestTexel((1.0 - v) * height)
        if repeat
        {
            x = modFloor(x, width)
            y = modFloor(y, height)
        }
        else
        {
            x = Math.clamp(x, 0, width - 1)
            y = Math.clamp(y, 0, height - 1)
        }

        return cast(f32, plane.storage()[cast(u64, (y * width + x))])
    }

    // Samples a top-down byte plane at the normalized coordinates used by a GPU texture.
    func samplePlanarPlane(plane: const *Array'u8, width, height: s32, u, v: f32, repeat: bool)->f32
    {
        var x = u * width - 0.5
        var y = (1.0 - v) * height - 0.5
        if not repeat
        {
            x = Math.clamp(x, 0.0, cast(f32, width - 1))
            y = Math.clamp(y, 0.0, cast(f32, height - 1))
        }

        let x0 = cast(s32, Math.floor(x))
        let y0 = cast(s32, Math.floor(y))
        var x1 = x0 + 1
        var y1 = y0 + 1
        if repeat
        {
            x1 = modFloor(x1, width)
            y1 = modFloor(y1, height)
        }
        else
        {
            x1 = Math.min(x1, width - 1)
            y1 = Math.min(y1, height - 1)
        }

        let readX0 = repeat ? modFloor(x0, width) : x0
        let readY0 = repeat ? modFloor(y0, height) : y0
        let tx     = x - x0
        let ty     = y - y0
        let pixels = plane.storage()
        let c00    = cast(f32, pixels[cast(u64, (readY0 * width + readX0))])
        let c10    = cast(f32, pixels[cast(u64, (readY0 * width + x1))])
        let c01    = cast(f32, pixels[cast(u64, (y1 * width + readX0))])
        let c11    = cast(f32, pixels[cast(u64, (y1 * width + x1))])
        let top    = c00 + (c10 - c00) * tx
        let bot    = c01 + (c11 - c01) * tx
        return top + (bot - top) * ty
    }

    // Samples all source planes at the draw coordinate and applies the color matrix afterward.
    //
    // Pixel mode reads the nearest luma sample and still filters the two chroma planes: the
    // sampling mode of a brush governs its own texture, which is the luma plane, while the chroma
    // planes are half-size companions that are always interpolated up to it.
    func samplePlanar(texture: const *CpuPlanarTexture, u, v: f32, mode: InterpolationMode, repeat: bool)->Color
    {
        var y = 0.0'f32
        if mode == .Pixel do
            y = RenderCpu.fetchPlanarPlane(&texture.luma, texture.width, texture.height, u, v, repeat)
        else do
            y = RenderCpu.samplePlanarPlane(&texture.luma, texture.width, texture.height, u, v, repeat)

        let d       = RenderCpu.samplePlanarPlane(&texture.chromaB, texture.chromaWidth, texture.chromaHeight, u, v, repeat) - 128.0
        let e       = RenderCpu.samplePlanarPlane(&texture.chromaR, texture.chromaWidth, texture.chromaHeight, u, v, repeat) - 128.0
        let factors = yuvConversionFactors(texture.matrix, texture.studioRange)
        let c       = Math.max(y - cast(f32, factors.lumaOffset), 0.0) * cast(f32, factors.lumaScale)
        let r       = (c + cast(f32, factors.redCr) * e + 128.0) / 256.0
        let g       = (c + cast(f32, factors.greenCb) * d + cast(f32, factors.greenCr) * e + 128.0) / 256.0
        let b       = (c + cast(f32, factors.blueCb) * d + 128.0) / 256.0
        return Color{a: 255,
                     r: cast(u8, Math.round(Math.clamp(r, 0.0, 255.0))),
                     g: cast(u8, Math.round(Math.clamp(g, 0.0, 255.0))),
                     b: cast(u8, Math.round(Math.clamp(b, 0.0, 255.0)))}
    }

    func sampleSubRect(image: *Image, paintPos: Vector2, sampler: const *SubRectSampler)->Color
    {
        let tx = Math.saturate((paintPos.x - sampler.origin.x) / sampler.size.x)
        let ty = Math.saturate((paintPos.y - sampler.origin.y) / sampler.size.y)
        var px = cast(f32, sampler.minX) + tx * sampler.span.x - 0.5
        var py = cast(f32, sampler.minY) + ty * sampler.span.y - 0.5

        if sampler.nearest
        {
            let x = Math.clamp(nearestTexel(px + 0.5), sampler.minX, sampler.maxX)
            let y = Math.clamp(nearestTexel(py + 0.5), sampler.minY, sampler.maxY)

            // The presentation blit runs through here for every surface pixel.
            if image.pixelFormat == .BGRA8 do
                return fetchBgra8(image, x, y)
            return readPixel(image, x, y)
        }

        px = Math.clamp(px, cast(f32, sampler.minX), cast(f32, sampler.maxX))
        py = Math.clamp(py, cast(f32, sampler.minY), cast(f32, sampler.maxY))
        let floorX = Math.floor(px)
        let floorY = Math.floor(py)
        let x0     = cast(s32, floorX)
        let y0     = cast(s32, floorY)
        let x1     = Math.min(x0 + 1, sampler.maxX)
        let y1     = Math.min(y0 + 1, sampler.maxY)
        var fx     = px - floorX
        var fy     = py - floorY

        // Sharp bilinear (see the OpenGL base shader): pixel mode at a fractional
        // content scale keeps one device pixel of smoothing at each texel boundary
        // instead of dropping texels or smearing one-texel tile borders.
        if sampler.sharp
        {
            fx = Math.saturate((fx - 0.5) / sampler.sharpWidth.x + 0.5)
            fy = Math.saturate((fy - 0.5) / sampler.sharpWidth.y + 0.5)
        }

        return bilinearTexels(image,
                              Math.clamp(x0, 0, image.width - 1),
                              Math.clamp(x1, 0, image.width - 1),
                              Math.clamp(y0, 0, image.height - 1),
                              Math.clamp(y1, 0, image.height - 1),
                              fx,
                              fy)
    }

    // Inline the sampler and byte reads into the convolution: a captured callback here
    // otherwise adds an indirect call for every tap of every blurred pixel.
    #[Swag.Inline]
    func normalizedChannels(color: Color)->Math.Simd.F32x4
    {
        return cast(Math.Simd.F32x4, [cast(f32, color.r), cast(f32, color.g), cast(f32, color.b), cast(f32, color.a)]) / 255.0
    }

    #[Swag.Inline]
    func backdropTexel(image: *Image, params: const *BackdropPass, pixels: const [*] Math.Simd.F32x4?, x, y: s32)->Math.Simd.F32x4
    {
        if pixels do
            return pixels[cast(u64, y) * cast(u64, params.width) + cast(u64, x)]
        return normalizedChannels(fetchBgra8(image, x, y))
    }

    #[Swag.Inline]
    func sampleBackdropLinear(image: *Image, params: const *BackdropPass, pixels: const [*] Math.Simd.F32x4?, su, sv: f32)->Math.Simd.F32x4
    {
        // Keep interpolation in float until the pass is complete. Quantizing each of the
        // two bilinear lerps loses brightness repeatedly on the reconstruction pyramid.
        let x   = Math.clamp(su * image.width - 0.5, 0.0, cast(f32, params.width - 1))
        let y   = Math.clamp((1 - sv) * image.height - 0.5, 0.0, cast(f32, params.height - 1))
        let x0  = cast(s32, Math.floor(x))
        let y0  = cast(s32, Math.floor(y))
        let x1  = Math.min(x0 + 1, params.width - 1)
        let y1  = Math.min(y0 + 1, params.height - 1)
        let c00 = backdropTexel(image, params, pixels, x0, y0)

        // Aligned texel centers need no interpolation. Keep fractional coordinates on
        // the same bilinear path, without an epsilon that could change edge pixels.
        if x == x0 and y == y0 do
            return c00
        let c10    = backdropTexel(image, params, pixels, x1, y0)
        let c01    = backdropTexel(image, params, pixels, x0, y1)
        let c11    = backdropTexel(image, params, pixels, x1, y1)
        let top    = c00 + (c10 - c00) * (x - x0)
        let bottom = c01 + (c11 - c01) * (x - x0)
        return top + (bottom - top) * (y - y0)
    }

    mtd sampleBackdrop(batch: *RasterBatch, image: *Image, u, v: f32)->Color
    {
        let params  = &.backdropPass
        let sourceU = u * params.width / image.width
        let sourceV = 1 - (1 - v) * params.height / image.height

        var sum: Math.Simd.F32x4
        if params.mode < 2
        {
            let reach = Math.ceil(params.radius)
            for i in batch.blurWeightCount
            {
                let offset = cast(f32, i) - reach
                let su     = params.mode == 0 ? sourceU + offset / image.width : sourceU
                let sv     = params.mode == 1 ? sourceV + offset / image.height : sourceV
                sum += sampleBackdropLinear(image, params, batch.backdropPixels, su, sv) * batch.blurWeights![i]
            }
        }
        elif params.mode < 4
        {
            let dx       = params.radius / image.width
            let dy       = params.radius / image.height
            let diagonal = sampleBackdropLinear(image, params, batch.backdropPixels, sourceU + dx, sourceV + dy) +
                           sampleBackdropLinear(image, params, batch.backdropPixels, sourceU - dx, sourceV - dy) +
                           sampleBackdropLinear(image, params, batch.backdropPixels, sourceU + dx, sourceV - dy) +
                           sampleBackdropLinear(image, params, batch.backdropPixels, sourceU - dx, sourceV + dy)
            if params.mode == 2
            {
                sum = (sampleBackdropLinear(image, params, batch.backdropPixels, sourceU, sourceV) * 4 + diagonal) / 8
            }
            else
            {
                sum = sampleBackdropLinear(image, params, batch.backdropPixels, sourceU - 2 * dx, sourceV) +
                      sampleBackdropLinear(image, params, batch.backdropPixels, sourceU + 2 * dx, sourceV) +
                      sampleBackdropLinear(image, params, batch.backdropPixels, sourceU, sourceV - 2 * dy) +
                      sampleBackdropLinear(image, params, batch.backdropPixels, sourceU, sourceV + 2 * dy)
                sum = (sum + diagonal * 2) / 12
            }
        }
        else
        {
            sum = sampleBackdropLinear(image, params, batch.backdropPixels, sourceU, sourceV)
            let luminance = sum[0] * 0.2126 + sum[1] * 0.7152 + sum[2] * 0.0722
            let gray      = cast(Math.Simd.F32x4, [luminance, luminance, luminance, 1.0])
            sum = gray + (sum - gray) * params.saturation
            let tint = normalizedChannels(params.tint)
            sum = sum * (1 - tint[3]) + tint * tint[3]
        }

        return Color.fromArgb(255'u8,
                              cast(u8, Math.round(Math.saturate(sum[0]) * 255)),
                              cast(u8, Math.round(Math.saturate(sum[1]) * 255)),
                              cast(u8, Math.round(Math.saturate(sum[2]) * 255)))
    }

    mtd sampleBlur(batch: *RasterBatch, image: *Image, u, v: f32)->Color
    {
        if batch.blurTapCount == 0 do
            return sampleLinear(image, u, v, false)

        var sum: Math.Simd.F32x4
        let horizontal = .blurAxis == 0
        for i in batch.blurTapCount
        {
            let tap = batch.blurTaps![i]
            let su  = horizontal ? u + tap.offset : u
            let sv  = horizontal ? v : v + tap.offset
            sum += normalizedChannels(sampleLinear(image, su, sv, false)) * tap.weight
        }

        return Color.fromArgbF32(sum[3], sum[0], sum[1], sum[2])
    }

    mtd sampleResolve(image: *Image, u, v: f32)->Color
    {
        let factor = Math.clamp(.resolveFactor, 1, 8)

        // Resolve blocks follow source texels, not a truncated quotient of the padded allocation.
        let sourceX = Math.clamp(u, 0.0, 0.999999) * image.width
        let sourceY = Math.clamp(1.0 - v, 0.0, 0.999999) * image.height
        let baseX   = cast(s32, Math.floor(sourceX / factor)) * factor
        let baseY   = cast(s32, Math.floor(sourceY / factor)) * factor

        var sumA, sumR, sumG, sumB: f32
        for var y: s32; y < factor; y += 1
        {
            for var x: s32; x < factor; x += 1
            {
                let sample = readPixel(image, Math.clamp(baseX + x, 0, image.width - 1), Math.clamp(baseY + y, 0, image.height - 1))
                sumA += cast(f32, sample.a) / 255.0
                sumR += cast(f32, sample.r) / 255.0
                sumG += cast(f32, sample.g) / 255.0
                sumB += cast(f32, sample.b) / 255.0
            }
        }

        let count = cast(f32, (factor * factor))
        let alpha = sumA / count
        if sumA <= 0.00001 do
            return Color.fromArgbF32(alpha, 0, 0, 0)
        return Color.fromArgbF32(alpha, sumR / sumA, sumG / sumA, sumB / sumA)
    }

    mtd sampleGradient(p: const *BrushBinding, paintPos: Vector2)->Color
    {
        if p.gradientStopCount == 0 do
            return Color.fromArgb(Argb.White)
        let stops = unwrap .gradientStops

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
        let p = &.paint
        switch #complete p.type
        {
        case .SolidColor:
            return Color.fromArgb(Argb.White)

        case .Texture:
            let image = batch.paintImage
            if not image do
                return Color.fromArgb(Argb.Zero)

            if p.uvMode == .FillSubRect and
               .program != CpuProgram_Blur and
               .program != CpuProgram_Resolve and
               .program != CpuProgram_Backdrop
            {
                if batch.paintPlanar
                {
                    let dstW = Math.max(p.boundRect.z - p.boundRect.x, 0.000001)
                    let dstH = Math.max(p.boundRect.w - p.boundRect.y, 0.000001)
                    let tx   = (paintPos.x - p.boundRect.x) / dstW
                    let ty   = (paintPos.y - p.boundRect.y) / dstH
                    let u    = p.textureRect.x + tx * (p.textureRect.z - p.textureRect.x)
                    let v    = 1.0 - (p.textureRect.y + ty * (p.textureRect.w - p.textureRect.y))
                    return RenderCpu.samplePlanar(batch.paintPlanar, u, v, p.interpolationMode, false)
                }

                return sampleSubRect(image, paintPos, &batch.subRect)
            }

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

            if batch.paintPlanar do
                return RenderCpu.samplePlanar(batch.paintPlanar, u, v, p.interpolationMode, repeat)

            if .program == CpuProgram_Blur do
                return .sampleBlur(batch, image, u, v)
            if .program == CpuProgram_Resolve do
                return .sampleResolve(image, u, v)
            if .program == CpuProgram_Backdrop do
                return .sampleBackdrop(batch, image, u, v)

            if p.interpolationMode == .Linear do
                return sampleLinear(image, u, v, repeat)
            return sampleNearest(image, u, v, repeat)

        case .Hatch:
            let x = modFloor(cast(s32, Math.floor(paintPos.x - p.boundRect.x)), 8)
            let y = modFloor(cast(s32, Math.floor(paintPos.y - p.boundRect.y)), 8)
            return hatchPixel(p.hatch, x, y) ? Color.fromArgb(Argb.White) : Color.fromArgb(Argb.Zero)

        case .LinearGradient, .RadialGradient, .SweepGradient:
            return .sampleGradient(&.paint, paintPos)
        }
    }

    func hatchPixel(style: HatchStyle, x, y: s32)->bool
    {
        let idx = cast(u64, (y * 8 + x))
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
    }

    func smoothStep(edge0, edge1, value: f32)->f32
    {
        if edge1 <= edge0 do
            return value < edge0 ? 0.0 : 1.0
        let t = Math.saturate((value - edge0) / (edge1 - edge0))
        return t * t * (3.0 - 2.0 * t)
    }

    func median(a, b, c: f32)->f32 => Math.max(Math.min(a, b), Math.min(Math.max(a, b), c))

    mtd fontAtlas()->*GlyphAtlas?
    {
        if not .font or .fontAtlasIndex < 0 do
            return null

        let cache = .font.cache
        if cast(u64, .fontAtlasIndex) >= cache.atlases.count do
            return null
        return &cache.atlases[cast(u64, .fontAtlasIndex)]
    }

    func readFontAtlas(atlas: const *GlyphAtlas, x, y: s32)->Vector4
    {
        let pixelWidth = cast(s32, (atlas.width / atlas.bytesPerPixel))
        let xx         = Math.clamp(x, 0, pixelWidth - 1)
        let yy         = Math.clamp(y, 0, cast(s32, atlas.height) - 1)
        let row        = cast(s32, atlas.height) - yy - 1
        let ptr        = atlas.data.storage() + cast(u64, row) * atlas.width + cast(u64, xx) * atlas.bytesPerPixel

        if atlas.bytesPerPixel == 1
        {
            let value = cast(f32, ptr[0]) / 255.0
            return Vector4{value, value, value, value}
        }

        return Vector4{cast(f32, ptr[0]) / 255.0,
                       cast(f32, ptr[1]) / 255.0,
                       cast(f32, ptr[2]) / 255.0,
                       cast(f32, ptr[3]) / 255.0}
    }

    // Keep the interpolation rounded before quantizing font coverage and effect colors.
    func lerpFontSample(src, dst: Vector4, factor: f32)->Vector4
    {
        return Vector4{Math.mulAdd(factor, dst.x - src.x, src.x),
                       Math.mulAdd(factor, dst.y - src.y, src.y),
                       Math.mulAdd(factor, dst.z - src.z, src.z),
                       Math.mulAdd(factor, dst.w - src.w, src.w)}
    }

    // Samples the atlas bilinearly; a texel outside the page reads as the nearest edge texel.
    func sampleFontAtlas(atlas: const *GlyphAtlas, pos: AtlasPoint)->Vector4
    {
        let width  = cast(s32, (atlas.width / atlas.bytesPerPixel))
        let height = cast(s32, atlas.height)
        let px     = pos.offset.x - 0.5
        let py     = pos.offset.y - 0.5
        let x0     = pos.baseX + cast(s32, Math.floor(px))
        let y0     = pos.baseY + cast(s32, Math.floor(py))
        let x1     = Math.min(x0 + 1, width - 1)
        let y1     = Math.min(y0 + 1, height - 1)
        let tx     = px - Math.floor(px)
        let ty     = py - Math.floor(py)

        // The MSDF shader takes four of these per shaded pixel; branching on the atlas layout
        // once, the four fetches then read the exact values [[readFontAtlas]] returns.
        if atlas.bytesPerPixel == 4
        {
            func fetch(atlas: const *GlyphAtlas, width, height, x, y: s32)->Vector4
            {
                let xx  = Math.clamp(x, 0, width - 1)
                let yy  = Math.clamp(y, 0, height - 1)
                let row = height - yy - 1
                let ptr = atlas.data.storage() + cast(u64, row) * atlas.width + cast(u64, xx) * atlas.bytesPerPixel
                return Vector4{cast(f32, ptr[0]) / 255.0,
                               cast(f32, ptr[1]) / 255.0,
                               cast(f32, ptr[2]) / 255.0,
                               cast(f32, ptr[3]) / 255.0}
            }

            let f00 = fetch(atlas, width, height, x0, y0)
            let f10 = fetch(atlas, width, height, x1, y0)
            let f01 = fetch(atlas, width, height, x0, y1)
            let f11 = fetch(atlas, width, height, x1, y1)
            return lerpFontSample(lerpFontSample(f00, f10, tx), lerpFontSample(f01, f11, tx), ty)
        }

        let c00 = readFontAtlas(atlas, x0, y0)
        let c10 = readFontAtlas(atlas, x1, y0)
        let c01 = readFontAtlas(atlas, x0, y1)
        let c11 = readFontAtlas(atlas, x1, y1)
        return lerpFontSample(lerpFontSample(c00, c10, tx), lerpFontSample(c01, c11, tx), ty)
    }

    func msdfCoverage(atlas: const *GlyphAtlas, pos: AtlasPoint, screenPxRange, edge, aa: f32)->f32
    {
        let sample = sampleFontAtlas(atlas, pos)
        let sd     = median(sample.x, sample.y, sample.z)
        return Math.saturate((sd - edge) * screenPxRange / aa + 0.5)
    }

    #[Swag.Inline]
    func fontLinearAxis(base, size: s32, position, floor: f32)->FontLinearAxis
    {
        let first = base + cast(s32, floor)
        return {Math.clamp(first, 0, size - 1), Math.clamp(first + 1, 0, size - 1), position - floor}
    }

    #[Swag.Inline]
    func msdfTexel(row: const [*] u8, x: s32)->Math.Simd.F32x4
    {
        #static if Core.BIG_ENDIAN
        {
            let pixel = row + cast(u64, x) * 4
            return cast(Math.Simd.F32x4, [cast(f32, pixel[0]), cast(f32, pixel[1]), cast(f32, pixel[2]), cast(f32, pixel[3])]) / 255.0
        }
        else
        {
            // Each widened byte fits in the mantissa of 2^23. Subtracting 2^23
            // converts all four lanes exactly, including the last texel of a row.
            let pixel = cast #bit(Math.Simd.U8x16, Math.Simd.splat(loadBgra8(row, x)))
            let lanes = Math.Simd.widenLow(Math.Simd.widenLow(pixel)) | 0x4B00_0000'u32
            return (cast #bit(Math.Simd.F32x4, lanes) - 8388608.0) / 255.0
        }
    }

    #[Swag.Inline]
    func lerpMsdf(first, second: Math.Simd.F32x4, fraction: f32)->Math.Simd.F32x4
    {
        return Math.mulAdd(Math.Simd.splat(fraction), second - first, first)
    }

    // Both taps on this row interpolate the same texel when their footprints meet.
    #[Swag.Inline]
    func msdfRow(atlas: const *GlyphAtlas, y: s32, left, right: FontLinearAxis)->{left, right: Math.Simd.F32x4}
    {
        let row   = atlas.data.storage() + (atlas.height - 1 - cast(u64, y)) * atlas.width
        let first = msdfTexel(row, left.first)
        let next  = left.first == left.second ? first : msdfTexel(row, left.second)
        let other = right.first == left.second ? next : msdfTexel(row, right.first)
        let last  = right.first == right.second ? other : msdfTexel(row, right.second)
        return {lerpMsdf(first, next, left.fraction), lerpMsdf(other, last, right.fraction)}
    }

    #[Swag.Inline]
    func msdfTap(top, bottom: Math.Simd.F32x4, fraction, screenPxRange: f32)->f32
    {
        let value = lerpMsdf(top, bottom, fraction)
        let sd    = median(value[0], value[1], value[2])
        return Math.saturate((sd - 0.5) * screenPxRange + 0.5)
    }

    // The four quarter-pixel taps form a rectangle. Resolve each axis once and reuse
    // horizontally interpolated rows when the two vertical footprints overlap.
    func msdfCoverage4(atlas: const *GlyphAtlas, pos: AtlasPoint, offset: Vector2, screenPxRange: f32)->f32
    {
        if atlas.bytesPerPixel != 4
        {
            var fallback = msdfCoverage(atlas, pos.moved({-offset.x, -offset.y}), screenPxRange, 0.5, 1.0)
            fallback += msdfCoverage(atlas, pos.moved({offset.x, -offset.y}), screenPxRange, 0.5, 1.0)
            fallback += msdfCoverage(atlas, pos.moved({-offset.x, offset.y}), screenPxRange, 0.5, 1.0)
            return fallback + msdfCoverage(atlas, pos.moved(offset), screenPxRange, 0.5, 1.0)
        }

        let width    = cast(s32, (atlas.width / 4))
        let height   = cast(s32, atlas.height)
        let position = cast(Math.Simd.F32x4, [pos.offset.x - offset.x, pos.offset.x + offset.x,
                                              pos.offset.y - offset.y, pos.offset.y + offset.y]) - 0.5
        let floors = Math.floor(position)
        let left   = fontLinearAxis(pos.baseX, width, position[0], floors[0])
        let right  = fontLinearAxis(pos.baseX, width, position[1], floors[1])
        let top    = fontLinearAxis(pos.baseY, height, position[2], floors[2])
        let bottom = fontLinearAxis(pos.baseY, height, position[3], floors[3])

        let first = msdfRow(atlas, top.first, left, right)
        let next  = top.first == top.second ? first : msdfRow(atlas, top.second, left, right)
        let other = bottom.first == top.second ? next : msdfRow(atlas, bottom.first, left, right)
        let last  = bottom.first == bottom.second ? other : msdfRow(atlas, bottom.second, left, right)

        var result = msdfTap(first.left, next.left, top.fraction, screenPxRange)
        result += msdfTap(first.right, next.right, top.fraction, screenPxRange)
        result += msdfTap(other.left, last.left, bottom.fraction, screenPxRange)
        result += msdfTap(other.right, last.right, bottom.fraction, screenPxRange)
        return result
    }

    mtd shadeMsdf(faceColor: Color, pos: AtlasPoint, frame: const *FontFrame, safeAtlas: const *GlyphAtlas)->Color
    {
        let screenPxRange = frame.screenRange
        if .fontEffect.enabled < 0.5
        {
            let coverage = msdfCoverage4(safeAtlas, pos, frame.tapOffset, screenPxRange) * 0.25
            let alpha    = coverage == 0 or coverage == 1 ? coverage : Math.pow(coverage, FontGamma)
            return faceColor.withAlphaF32(cast(f32, faceColor.a) / 255.0 * alpha)
        }

        let p           = &.fontEffect
        let aa          = Math.max(1.0, p.faceSoftness * screenPxRange)
        let sample      = sampleFontAtlas(safeAtlas, pos)
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
            let gradX     = sampleFontAtlas(safeAtlas, pos.moved(frame.dx)).w - sdTrue
            let gradY     = sampleFontAtlas(safeAtlas, pos.moved(frame.dy)).w - sdTrue
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

        // A fragment containing only glow keeps its authored straight-alpha color.
        if shapeAlpha == 0 and glowAlpha > 0 do
            return p.glowColor.withAlphaF32(glowAlpha)

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
    mtd shadeBatch(batch: *RasterBatch, paintPos: Vector2, fontPos: AtlasPoint, fontFrame: const *FontFrame, vertexColor: Color, coverage: f32)->Color
    {
        var result = vertexColor
        if not batch.solidPaint
        {
            let paintColor = .samplePaintBatch(batch, paintPos)
            result = vertexColor.argb == Color.fromArgb(Argb.White).argb ? paintColor : Color.multiply(vertexColor, paintColor)
        }

        if .program == CpuProgram_Font
        {
            // With no atlas bound the font program covers the whole primitive, the way a white
            // texture does: a text decoration is drawn between two glyph runs in that state.
            let atlas = batch.atlas
            if not atlas do
                return result

            // Nearest atlas fetch, inlined: the sample value only feeds the gamma power, so the
            // lookup table replaces the per-pixel pow with the factor it would have computed.
            let x     = Math.clamp(fontPos.baseX + cast(s32, Math.floor(fontPos.offset.x)), 0, batch.atlasMaxX)
            let y     = Math.clamp(fontPos.baseY + cast(s32, Math.floor(fontPos.offset.y)), 0, batch.atlasMaxY)
            let row   = batch.atlasMaxY - y
            let value = atlas.data.storage()[cast(u64, row) * atlas.width + cast(u64, x) * atlas.bytesPerPixel]
            result.a = result.a == 255 ? g_FontGammaOpaque[value] :
                       cast(u8, Math.clamp(Math.round(cast(f32, result.a) * g_FontGammaLut[value]), 0.0, 255.0))
        }
        elif .program == CpuProgram_Msdf
        {
            let atlas = batch.atlas
            if not atlas do
                return result
            result = .shadeMsdf(result, fontPos, fontFrame, atlas)
        }
        elif .program == CpuProgram_Default
        {
            result.a = coverageAlpha(result.a, coverage)
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

        let minX = Math.max(Math.clamp(cast(s32, Math.floor(Math.min(p0.x, p1.x, p2.x))), 0, batch.width - 1), batch.clipMinX)
        let minY = Math.max(Math.clamp(cast(s32, Math.floor(Math.min(p0.y, p1.y, p2.y))), 0, batch.height - 1), bandMinY, batch.clipMinY)
        let maxX = Math.min(Math.clamp(cast(s32, Math.ceil(Math.max(p0.x, p1.x, p2.x))) - 1, 0, batch.width - 1), batch.clipMaxX)
        let maxY = Math.min(Math.clamp(cast(s32, Math.ceil(Math.max(p0.y, p1.y, p2.y))) - 1, 0, batch.height - 1), bandMaxY, batch.clipMaxY)
        if minX > maxX or minY > maxY do
            return

        let edge0TopLeft = isTopLeft(p1, p2)
        let edge1TopLeft = isTopLeft(p2, p0)
        let edge2TopLeft = isTopLeft(p0, p1)
        let edge0Origin  = edge0TopLeft ? p1 : p2
        let edge1Origin  = edge1TopLeft ? p2 : p0
        let edge2Origin  = edge2TopLeft ? p0 : p1
        let invArea      = 1.0 / area

        // Opposite orientations of a shared edge use one endpoint as their common origin.
        // The same rounded equation in scalar and packed paths makes the two edge values
        // exact opposites, even when one triangle ends with a scalar tail.
        let dx0 = p2.x - p1.x
        let dy0 = p2.y - p1.y
        let dx1 = p0.x - p2.x
        let dy1 = p0.y - p2.y
        let dx2 = p1.x - p0.x
        let dy2 = p1.y - p0.y

        // Narrowing costs three divisions a row, which a triangle a few pixels wide never repays.
        let narrowRows = maxX - minX >= 8

        let dcDx     = (v0.cov * (p1.y - p2.y) + v1.cov * (p2.y - p0.y) + v2.cov * (p0.y - p1.y)) * invArea
        let dcDy     = (v0.cov * (p2.x - p1.x) + v1.cov * (p0.x - p2.x) + v2.cov * (p1.x - p0.x)) * invArea
        let covWidth = Math.max(Math.abs(dcDx) + Math.abs(dcDy), 0.00001)

        if let rows = batch.overlapRows
        {
            var bounds = PixelBounds{minX: minX, minY: minY, maxX: maxX, maxY: maxY}

            // The sides of an axis-aligned stroke triangle can reject whole columns and
            // rows. Subpixel dashes often have no pixel centre between those sides.
            // Boundary samples still go through the normal edge tie rule.
            if (maxX - minX < 2 or maxY - minY < 2) and
               (p0.x == p1.x or p0.x == p2.x or p1.x == p2.x) and
               (p0.y == p1.y or p0.y == p2.y or p1.y == p2.y)
            {
                if cast(f32, minX) + 0.5 < Math.min(p0.x, p1.x, p2.x) do
                    bounds.minX += 1
                if cast(f32, maxX) + 0.5 > Math.max(p0.x, p1.x, p2.x) do
                    bounds.maxX -= 1
                if cast(f32, minY) + 0.5 < Math.min(p0.y, p1.y, p2.y) do
                    bounds.minY += 1
                if cast(f32, maxY) + 0.5 > Math.max(p0.y, p1.y, p2.y) do
                    bounds.maxY -= 1
                if bounds.isEmpty() do
                    return
            }

            let triangle = TriangleSpan{
                bounds: bounds,
                origin: [edge0Origin, edge1Origin, edge2Origin],
                dx: [dx0, dx1, dx2], dy: [dy0, dy1, dy2],
                topLeft: [edge0TopLeft, edge1TopLeft, edge2TopLeft], invArea: invArea}
            .accumulateSolidStroke(batch, rows, &triangle, Color.fromArgb(v0.color).a, [v0.cov, v1.cov, v2.cov], covWidth)
            return
        }

        // Font fragments are located in texels from the first vertex, never in normalized atlas
        // coordinates, so a glyph shades alike wherever earlier text placed it; see AtlasPoint.
        let needFontPos = (.program == CpuProgram_Font or .program == CpuProgram_Msdf) and batch.atlas != null
        var fontFrame   = needFontPos ? FontFrame.from(unwrap batch.atlas, v0.uv, v1.uv, v2.uv, p0, p1, p2, invArea) : {}
        if needFontPos and .program == CpuProgram_Msdf do
            fontFrame.prepareMsdf()

        let c0 = Color.fromArgb(v0.color)
        let c1 = Color.fromArgb(v1.color)
        let c2 = Color.fromArgb(v2.color)
        let constantColor = c0 == c1 and c1 == c2

        let image       = unwrap batch.image
        let stencilTest = .stencilOn
        let maskColor   = .colorMask.r and .colorMask.g and .colorMask.b and not .colorMask.a
        let maskFull    = .colorMask.r and .colorMask.g and .colorMask.b and .colorMask.a
        let maskAlpha   = not .colorMask.r and not .colorMask.g and not .colorMask.b and .colorMask.a
        let plainBgra8  = not .alphaResolve and .overlapPass == 0 and image.pixelFormat == .BGRA8
        let fastAlpha   = plainBgra8 and .blendingMode == .Alpha and maskColor
        let fastCopy    = plainBgra8 and .blendingMode == .Copy and (maskColor or maskFull)
        let whiteMatte  = .whiteMatte

        // A triangle whose vertices agree on color and coverage shades one constant fragment
        // under a solid paint, and the frequent blend states then collapse per pixel.
        var constShade = constantColor and
                         batch.solidPaint and
                         (.program == CpuProgram_Simple or .program == CpuProgram_Default)
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
            else
            {
                constShade = false
            }
        }

        // Writing a region shades nothing and takes the general loop below, which is the one that
        // computes the coverage each pixel contributes to it.
        if constShade and plainBgra8 and not .stencilWrite
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
                let fill    = cast(Math.Simd.U8x16, [constColor.b, constColor.g, constColor.r, constColor.a,
                                                     constColor.b, constColor.g, constColor.r, constColor.a,
                                                     constColor.b, constColor.g, constColor.r, constColor.a,
                                                     constColor.b, constColor.g, constColor.r, constColor.a])
                let alpha = Math.Simd.splat(constColor.a)
                for var y = minY; y <= maxY; y += 1
                {
                    let sy         = cast(f32, y) + 0.5
                    let rowDy0     = sy - edge0Origin.y
                    let rowDy1     = sy - edge1Origin.y
                    let rowDy2     = sy - edge2Origin.y
                    let rowOffset  = cast(u64, batch.height - y - 1) * batch.rowStride
                    let rowPixels  = batch.pixels + rowOffset
                    let rowStencil = batch.stencil + cast(u64, y) * cast(u64, batch.width)
                    var x0         = minX
                    var x1         = maxX
                    let rowEdge0   = dx0 * rowDy0
                    let rowEdge1   = dx1 * rowDy1
                    let rowEdge2   = dx2 * rowDy2
                    if narrowRows
                    {
                        narrowEdgeSpan(&x0, &x1, -dy0, rowEdge0, edge0Origin.x)
                        narrowEdgeSpan(&x0, &x1, -dy1, rowEdge1, edge1Origin.x)
                        narrowEdgeSpan(&x0, &x1, -dy2, rowEdge2, edge2Origin.x)
                    }

                    trimEdgeSpan(&x0, &x1, -dy0, rowEdge0, edge0Origin.x, edge0TopLeft)
                    trimEdgeSpan(&x0, &x1, -dy1, rowEdge1, edge1Origin.x, edge1TopLeft)
                    trimEdgeSpan(&x0, &x1, -dy2, rowEdge2, edge2Origin.x, edge2TopLeft)

                    var x = x0
                    if not stencilTest
                    {
                        while x1 - x >= 3
                        {
                            let pixel = rowPixels + cast(u64, x) * 4
                            if copyAll do
                                Math.Simd.store(pixel, fill)
                            elif alphaMaskStore do
                                Math.Simd.store(pixel, Math.Simd.select(CpuBgraAlphaMask, fill, Math.Simd.load(pixel)))
                            elif fastAlpha and constColor.a != 255 do
                                Math.Simd.store(pixel, blendAlphaBgra8x4(fill, Math.Simd.load(pixel), alpha))
                            else do
                                Math.Simd.store(pixel, Math.Simd.select(CpuBgraRgbMask, fill, Math.Simd.load(pixel)))
                            // Alpha restoration and copy operations affect only the current target.
                            if fastAlpha and whiteMatte
                            {
                                let target = whiteMatte + rowOffset + cast(u64, x) * 4
                                Math.Simd.store(target, blendAlphaBgra8x4(fill, Math.Simd.load(target), alpha))
                            }

                            x += 4
                        }
                    }

                    for pixelX in x until x1 + 1
                    {
                        // The region cuts the coverage. A copy has no coverage to cut, so the
                        // region decides alone whether the pixel is written.
                        var laneColor = constColor
                        if stencilTest
                        {
                            let clip = rowStencil[pixelX]
                            if clip == 0 do
                                continue
                            if clip != 255
                            {
                                if .blendingMode == .Copy
                                {
                                    if clip < 128 do
                                        continue
                                }
                                else
                                {
                                    laneColor.a = cast(u8, ((cast(u32, laneColor.a) * clip) / 255))
                                    if laneColor.a == 0 do
                                        continue
                                }
                            }
                        }

                        let lanePixel = rowPixels + cast(u64, pixelX) * 4
                        if fastAlpha
                        {
                            blendAlphaBgra8(lanePixel, laneColor)
                            if let matte = whiteMatte do
                                blendAlphaBgra8(matte + rowOffset + cast(u64, pixelX) * 4, laneColor)
                        }
                        elif alphaMaskStore
                        {
                            // A cut alpha no longer stores as it is: it composites.
                            if laneColor.a == constColor.a do
                                lanePixel[3] = laneColor.a
                            else do
                                .blendPixel(image, pixelX, y, laneColor)
                        }
                        else
                        {
                            lanePixel[0] = laneColor.b
                            lanePixel[1] = laneColor.g
                            lanePixel[2] = laneColor.r
                            if copyAll do
                                lanePixel[3] = laneColor.a
                        }
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
        let paint = &.paint
        let white = Color.fromArgb(Argb.White).argb
        if fastAlpha and
           whiteMatte == null and
           not batch.solidPaint and
           not stencilTest and
           batch.paintImage != null and
           v0.color == white and
           v1.color == white and
           v2.color == white and
           paint.type == .Texture and
           paint.uvMode == .FillSubRect and
           paint.interpolationMode == .Pixel and
           .contentScale == 1 and
           (.program == CpuProgram_Simple or (.program == CpuProgram_Default and v0.cov == v1.cov and v1.cov == v2.cov and v0.cov > 0.51))
        {
            let source       = batch.paintImage
            let directFormat = source.pixelFormat == .BGR8 or
                               source.pixelFormat == .BGRA8 or
                               source.pixelFormat == .RGB8 or
                               source.pixelFormat == .RGBA8
            if directFormat and source.alphaMode == .Straight
            {
                // Everything the sampler recomputes per pixel from the paint command is
                // constant over the triangle.
                let texMinX = cast(s32, paint.texturePixelBounds.x)
                let texMinY = cast(s32, paint.texturePixelBounds.y)
                let texMaxX = cast(s32, paint.texturePixelBounds.z)
                let texMaxY = cast(s32, paint.texturePixelBounds.w)
                let spanX   = cast(f32, (texMaxX - texMinX + 1))
                let spanY   = cast(f32, (texMaxY - texMinY + 1))
                let dstW    = Math.max(paint.boundRect.z - paint.boundRect.x, 0.000001)
                let dstH    = Math.max(paint.boundRect.w - paint.boundRect.y, 0.000001)
                let originX = paint.boundRect.x
                let originY = paint.boundRect.y

                let hasAlpha    = source.pixelFormat == .RGBA8 or source.pixelFormat == .BGRA8
                let swapRedBlue = source.pixelFormat == .RGBA8 or source.pixelFormat == .RGB8
                let texelBytes  = cast(u64, (hasAlpha ? 4 : 3))
                let texelRow    = texelBytes * cast(u64, source.width)
                let texels      = source.pixels.storage()
                let lastTexelX  = source.width - 1
                let lastTexelY  = source.height - 1

                for var y = minY; y <= maxY; y += 1
                {
                    let sy        = cast(f32, y) + 0.5
                    let rowDy0    = sy - edge0Origin.y
                    let rowDy1    = sy - edge1Origin.y
                    let rowDy2    = sy - edge2Origin.y
                    let rowPixels = batch.pixels + cast(u64, (batch.height - y - 1)) * cast(u64, batch.rowStride)
                    var x0        = minX
                    var x1        = maxX
                    if narrowRows
                    {
                        narrowEdgeSpan(&x0, &x1, -dy0, dx0 * rowDy0, edge0Origin.x)
                        narrowEdgeSpan(&x0, &x1, -dy1, dx1 * rowDy1, edge1Origin.x)
                        narrowEdgeSpan(&x0, &x1, -dy2, dx2 * rowDy2, edge2Origin.x)
                    }

                    for var x = x0; x <= x1; x += 1
                    {
                        let sx = cast(f32, x) + 0.5
                        let e0 = Math.mulAdd(-dy0, sx - edge0Origin.x, dx0 * rowDy0)
                        let e1 = Math.mulAdd(-dy1, sx - edge1Origin.x, dx1 * rowDy1)
                        let e2 = Math.mulAdd(-dy2, sx - edge2Origin.x, dx2 * rowDy2)
                        if not insideEdge(e0, edge0TopLeft) or
                           not insideEdge(e1, edge1TopLeft) or
                           not insideEdge(e2, edge2TopLeft) do
                            continue

                        let w0 = e0 * invArea
                        let w1 = e1 * invArea
                        let w2 = e2 * invArea
                        let tx = Math.saturate((v0.pos.x * w0 + v1.pos.x * w1 + v2.pos.x * w2 - originX) / dstW)
                        let ty = Math.saturate((v0.pos.y * w0 + v1.pos.y * w1 + v2.pos.y * w2 - originY) / dstH)
                        let px = cast(f32, texMinX) + tx * spanX - 0.5
                        let py = cast(f32, texMinY) + ty * spanY - 0.5

                        let texelX = Math.clamp(Math.clamp(nearestTexel(px + 0.5), texMinX, texMaxX), 0, lastTexelX)
                        let texelY = Math.clamp(Math.clamp(nearestTexel(py + 0.5), texMinY, texMaxY), 0, lastTexelY)
                        let texel  = texels + cast(u64, texelX) * texelBytes + cast(u64, (lastTexelY - texelY)) * texelRow

                        let pixel = rowPixels + cast(u64, x) * 4
                        if hasAlpha
                        {
                            var src: Color
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

        // The opaque interior of a textured triangle needs only bilinear sampling and
        // compositing. Keep the general fragment path for coverage fringes and other paint.
        if fastAlpha and
           narrowRows and
           not stencilTest and
           not .stencilWrite and
           not batch.solidPaint and
           not batch.paintPlanar and
           paint.type == .Texture and
           paint.uvMode == .Fill and
           paint.interpolationMode == .Linear and
           v0.color == white and
           v1.color == white and
           v2.color == white and
           (.program == CpuProgram_Simple or (.program == CpuProgram_Default and v0.cov == 1 and v1.cov == 1 and v2.cov == 1))
        {
            if let source = batch.paintImage where source.alphaMode == .Straight
            {
                let triangle = TriangleSpan{
                    bounds: {minX: minX, minY: minY, maxX: maxX, maxY: maxY},
                    origin: [edge0Origin, edge1Origin, edge2Origin],
                    dx: [dx0, dx1, dx2], dy: [dy0, dy1, dy2],
                    topLeft: [edge0TopLeft, edge1TopLeft, edge2TopLeft],
                    pos: [v0.pos, v1.pos, v2.pos], invArea: invArea}
                switch source.pixelFormat
                {
                case .BGRA8:
                    drawLinearTextureTriangle'(.BGRA8)(batch, source, &triangle, paint.boundRect, whiteMatte)
                    return

                case .RGBA8:
                    drawLinearTextureTriangle'(.RGBA8)(batch, source, &triangle, paint.boundRect, whiteMatte)
                    return

                case .BGR8:
                    drawLinearTextureTriangle'(.BGR8)(batch, source, &triangle, paint.boundRect, whiteMatte)
                    return

                case .RGB8:
                    drawLinearTextureTriangle'(.RGB8)(batch, source, &triangle, paint.boundRect, whiteMatte)
                    return

                case .RGB16:
                    drawLinearTextureTriangle'(.RGB16)(batch, source, &triangle, paint.boundRect, whiteMatte)
                    return

                case .RGBA16:
                    drawLinearTextureTriangle'(.RGBA16)(batch, source, &triangle, paint.boundRect, whiteMatte)
                    return

                default:
                    break
                }
            }
        }

        let needPaintPos = not batch.solidPaint
        let needCoverage = .program == CpuProgram_Default
        let copyAll      = fastCopy and maskFull

        for var y = minY; y <= maxY; y += 1
        {
            let sy         = cast(f32, y) + 0.5
            let rowDy0     = sy - edge0Origin.y
            let rowDy1     = sy - edge1Origin.y
            let rowDy2     = sy - edge2Origin.y
            let rowOffset  = cast(u64, batch.height - y - 1) * batch.rowStride
            let rowPixels  = batch.pixels + rowOffset
            let rowStencil = batch.stencil + cast(u64, y) * cast(u64, batch.width)
            var x0         = minX
            var x1         = maxX
            if narrowRows
            {
                narrowEdgeSpan(&x0, &x1, -dy0, dx0 * rowDy0, edge0Origin.x)
                narrowEdgeSpan(&x0, &x1, -dy1, dx1 * rowDy1, edge1Origin.x)
                narrowEdgeSpan(&x0, &x1, -dy2, dx2 * rowDy2, edge2Origin.x)
            }

            for var x = x0; x <= x1; x += 1
            {
                let sx = cast(f32, x) + 0.5
                let e0 = Math.mulAdd(-dy0, sx - edge0Origin.x, dx0 * rowDy0)
                let e1 = Math.mulAdd(-dy1, sx - edge1Origin.x, dx1 * rowDy1)
                let e2 = Math.mulAdd(-dy2, sx - edge2Origin.x, dx2 * rowDy2)
                if not insideEdge(e0, edge0TopLeft) or
                   not insideEdge(e1, edge1TopLeft) or
                   not insideEdge(e2, edge2TopLeft) do
                    continue

                var clip = 255'u8
                if stencilTest
                {
                    clip = rowStencil[x]
                    if clip == 0 and not .stencilWrite do
                        continue
                }

                let w0          = e0 * invArea
                let w1          = e1 * invArea
                let w2          = e2 * invArea
                let cov         = needCoverage ? Math.saturate(signedCoverage(v0.cov * w0 + v1.cov * w1 + v2.cov * w2) / covWidth + 0.5) : 0.0
                let paintPos    = needPaintPos ? v0.pos * w0 + v1.pos * w1 + v2.pos * w2 : {}
                let fontPos     = needFontPos ? fontFrame.at(w1, w2) : {}
                let vertexColor = constantColor ? c0 : Color.fromArgbF32((c0.a * w0 + c1.a * w1 + c2.a * w2) / 255.0,
                                                                         (c0.r * w0 + c1.r * w1 + c2.r * w2) / 255.0,
                                                                         (c0.g * w0 + c1.g * w1 + c2.g * w2) / 255.0,
                                                                         (c0.b * w0 + c1.b * w1 + c2.b * w2) / 255.0)
                var src = .shadeBatch(batch, paintPos, fontPos, &fontFrame, vertexColor, cov)

                // Writing the region: the fragment's coverage — its antialiased edge, the alpha of
                // its texture, the transparency of its colour — joins the mask and shades nothing.
                if .stencilWrite
                {
                    if .stencilMode == .Set do
                        rowStencil[x] = Math.max(rowStencil[x], src.a)
                    else do
                        rowStencil[x] = cast(u8, ((cast(u32, rowStencil[x]) * (255 - cast(u32, src.a))) / 255))
                    continue
                }

                // Painting through one: the region cuts the coverage. A copy has no coverage to
                // cut, so the region decides alone whether the pixel is written.
                if clip != 255
                {
                    if .blendingMode == .Copy
                    {
                        if clip < 128 do
                            continue
                    }
                    else
                    {
                        src.a = cast(u8, ((cast(u32, src.a) * clip) / 255))
                    }
                }

                if fastAlpha
                {
                    // The zero-alpha skip mirrors the general blend's coverage early-out.
                    if src.a == 0 do
                        continue
                    blendAlphaBgra8(rowPixels + cast(u64, x) * 4, src)
                    if let matte = whiteMatte do
                        blendAlphaBgra8(matte + rowOffset + cast(u64, x) * 4, src)
                }
                elif fastCopy
                {
                    // 'Copy' writes transparent sources too, which is the erase operation.
                    let pixel = rowPixels + cast(u64, x) * 4
                    pixel[0] = src.b
                    pixel[1] = src.g
                    pixel[2] = src.r
                    if copyAll do
                        pixel[3] = src.a
                    continue
                }
                else
                {
                    .blendPixel(image, x, y, src)
                }
            }
        }
    }

    // A solid batch with identical vertex colors needs only the greatest coverage.
    // Paint that varies across a batch still needs the first contributing fragment.
    mtd solidOverlapColor(batch: *RasterBatch)->{valid: bool, color: Color}
    {
        let image = unwrap batch.image
        if not batch.solidPaint or
           .stencilWrite or
           .blendingMode != .Alpha or
           image.pixelFormat != .BGRA8 or
           image.alphaMode != .Straight or
           (.program != CpuProgram_Default and .program != CpuProgram_Simple) do
            return {false, {}}

        let vertices = batch.painter!.vertexBuffer.storage() + batch.start
        let color    = vertices[0].color
        for i in batch.count where vertices[i].color != color do
            return {false, {}}
        return {true, Color.fromArgb(color)}
    }

    mtd compositeSolidOverlap(batch: *RasterBatch, bounds: PixelBounds, color: Color)
    {
        let white = .whiteMatte
        let alpha = .overlapAlpha.storage()
        let rows  = .overlapRows.storage()
        for y in bounds.minY until bounds.maxY + 1
        {
            let span = rows[y]
            if span.first > span.last do
                continue
            let rowOffset = cast(u64, batch.height - y - 1) * batch.rowStride
            let maskRow   = alpha + cast(u64, y) * batch.width
            for x in span.first until span.last + 1
            {
                let coverage = maskRow[x]
                if not coverage do
                    continue
                let offset = rowOffset + cast(u64, x) * 4
                let ink    = Color.fromArgb(coverage, color.r, color.g, color.b)
                blendAlphaBgra8(batch.pixels + offset, ink)
                if let matte = white do
                    blendAlphaBgra8(matte + offset, ink)
            }
        }
    }

    struct TriangleSpan
    {
        bounds:  PixelBounds
        origin:  [3] Vector2
        dx, dy:  [3] f32
        topLeft: [3] bool
        pos:     [3] Vector2
        invArea: f32
    }

    // The overlap mark pass stores only the greatest coverage of a solid stroke.
    // It has no color, texture, destination or font work to do.
    mtd accumulateSolidStroke(batch: *RasterBatch, rows: [*] OverlapRow, triangle: const *TriangleSpan, alpha: u8, coverage: [3] f32, covWidth: f32)
    {
        let bounds       = triangle.bounds
        let origin       = triangle.origin
        let dx           = triangle.dx
        let dy           = triangle.dy
        let topLeft      = triangle.topLeft
        let invArea      = triangle.invArea
        let mask         = .overlapAlpha.storage()
        let stencil      = .stencilOn
        let needCoverage = .program == CpuProgram_Default
        let trim         = bounds.maxX - bounds.minX >= 4
        for y in bounds.minY until bounds.maxY + 1
        {
            let sy = cast(f32, y) + 0.5
            let c0 = dx[0] * (sy - origin[0].y)
            let c1 = dx[1] * (sy - origin[1].y)
            let c2 = dx[2] * (sy - origin[2].y)
            var x0 = bounds.minX
            var x1 = bounds.maxX
            if x1 - x0 >= 8
            {
                narrowEdgeSpan(&x0, &x1, -dy[0], c0, origin[0].x)
                narrowEdgeSpan(&x0, &x1, -dy[1], c1, origin[1].x)
                narrowEdgeSpan(&x0, &x1, -dy[2], c2, origin[2].x)
            }

            if trim
            {
                trimEdgeSpan(&x0, &x1, -dy[0], c0, origin[0].x, topLeft[0])
                trimEdgeSpan(&x0, &x1, -dy[1], c1, origin[1].x, topLeft[1])
                trimEdgeSpan(&x0, &x1, -dy[2], c2, origin[2].x, topLeft[2])
            }

            if x0 > x1 do
                continue

            rows[y].first = Math.min(rows[y].first, x0)
            rows[y].last  = Math.max(rows[y].last, x1)

            let offset  = cast(u64, y) * batch.width
            let row     = mask + offset
            let clipRow = batch.stencil + offset
            for x in x0 until x1 + 1
            {
                let clip = stencil ? clipRow[x] : 255'u8
                if clip == 0 or row[x] >= alpha do
                    continue

                var ink = alpha
                if needCoverage or not trim
                {
                    let sx = cast(f32, x) + 0.5
                    let e0 = Math.mulAdd(-dy[0], sx - origin[0].x, c0)
                    let e1 = Math.mulAdd(-dy[1], sx - origin[1].x, c1)
                    let e2 = Math.mulAdd(-dy[2], sx - origin[2].x, c2)
                    if not trim and
                       (not insideEdge(e0, topLeft[0]) or
                        not insideEdge(e1, topLeft[1]) or
                        not insideEdge(e2, topLeft[2])) do
                        continue

                    if needCoverage
                    {
                        let w0  = e0 * invArea
                        let w1  = e1 * invArea
                        let w2  = e2 * invArea
                        let cov = Math.saturate(signedCoverage(coverage[0] * w0 + coverage[1] * w1 + coverage[2] * w2) / covWidth + 0.5)
                        ink = coverageAlpha(alpha, cov)
                    }
                }

                let clipped = cast(u8, (cast(u32, ink) * clip / 255))
                row[x] = Math.max(row[x], clipped)
            }
        }
    }

    struct LinearSample
    {
        low, high: s32
        weight:    u32
    }

    #[Swag.Inline]
    func linearSample(coordinate: f32, size: s32)->LinearSample
    {
        let whole = Math.floor(coordinate)
        let low   = cast(s32, whole)
        return {Math.clamp(low, 0, size - 1), Math.clamp(low + 1, 0, size - 1), bilinearWeight(coordinate - whole)}
    }

    #[Swag.Inline]
    func(const Format: PixelFormat) writeLinearTexturePixel(pixel: [*] u8, ink: Color)
    {
        #static if Format == .BGR8 or Format == .RGB8 or Format == .RGB16
        {
            pixel[0] = ink.b
            pixel[1] = ink.g
            pixel[2] = ink.r
        }
        else do
            blendAlphaBgra8(pixel, ink)
    }

    struct FilteredTextureRow
    {
        sourceY: s32 = -1
        colors:  Array'u32
    }

    func(const Format: PixelFormat) filterTextureRow(cached: *FilteredTextureRow, pixels: const [*] u8, samples: const [..] LinearSample, sourceY: s32)
    {
        if sourceY == cached.sourceY do
            return
        cached.sourceY = sourceY
        cached.colors.resize(samples.count)
        for sample, index in samples do
            cached.colors[index] = lerpBgra8(loadColor8'Format(pixels, sample.low), loadColor8'Format(pixels, sample.high), sample.weight)
    }

    func(const Format: PixelFormat) drawLinearTextureTriangle(batch: *RasterBatch, source: *Image, triangle: const *TriangleSpan, paintRect: Vector4, matte: [*] u8?)
    {
        let paintWidth  = Math.max(paintRect.z - paintRect.x, 0.000001)
        let paintHeight = Math.max(paintRect.w - paintRect.y, 0.000001)
        let origin      = triangle.origin
        let dx          = triangle.dx
        let dy          = triangle.dy
        let topLeft     = triangle.topLeft
        let p0          = triangle.pos[0]
        let p1          = triangle.pos[1]
        let p2          = triangle.pos[2]
        let invArea     = triangle.invArea
        // A transformed rectangle has a separable mapping when its axes are preserved.
        // Its samples can share column weights even when the triangle's covered span moves.
        let t        = batch.transform
        let paintMin = t.transformPoint({paintRect.x, paintRect.y})
        let deviceW  = t.m11 * paintWidth
        let deviceH  = t.m22 * paintHeight
        var columns: Array'LinearSample
        if batch.painter!.useScanlineFills and t.m12 == 0 and t.m21 == 0 and paintMin.isFinite() and
           Math.isFinite(deviceW) and Math.isFinite(deviceH) and deviceW != 0 and deviceH != 0 and
           cast(u64, triangle.bounds.maxX - triangle.bounds.minX + 1) *
           cast(u64, triangle.bounds.maxY - triangle.bounds.minY + 1) >= 4096
        {
            columns.resize(cast(u64, triangle.bounds.maxX - triangle.bounds.minX + 1))
            for index in columns.count
            {
                let center = cast(f32, triangle.bounds.minX + cast(s32, index)) + 0.5
                let u      = Math.saturate((center - paintMin.x) / deviceW)
                columns[index] = linearSample(u * source.width - 0.5, source.width)
            }
        }

        let cacheRows = columns.count and Math.abs(deviceH) >= 1.25 * source.height
        var filteredTop, filteredBottom: FilteredTextureRow
        for y in triangle.bounds.minY until triangle.bounds.maxY + 1
        {
            let sy = cast(f32, y) + 0.5
            let c0 = dx[0] * (sy - origin[0].y)
            let c1 = dx[1] * (sy - origin[1].y)
            let c2 = dx[2] * (sy - origin[2].y)
            var x0 = triangle.bounds.minX
            var x1 = triangle.bounds.maxX
            narrowEdgeSpan(&x0, &x1, -dy[0], c0, origin[0].x)
            narrowEdgeSpan(&x0, &x1, -dy[1], c1, origin[1].x)
            narrowEdgeSpan(&x0, &x1, -dy[2], c2, origin[2].x)
            trimEdgeSpan(&x0, &x1, -dy[0], c0, origin[0].x, topLeft[0])
            trimEdgeSpan(&x0, &x1, -dy[1], c1, origin[1].x, topLeft[1])
            trimEdgeSpan(&x0, &x1, -dy[2], c2, origin[2].x, topLeft[2])

            let rowOffset = cast(u64, batch.height - y - 1) * batch.rowStride
            let row = batch.pixels + rowOffset
            let white = matte ? matte + rowOffset : null
            if columns.count
            {
                let v       = 1.0 - (sy - paintMin.y) / deviceH
                let sampleY = linearSample((1.0 - Math.saturate(v)) * source.height - 0.5, source.height)
                let pixels  = source.pixels.storage()
                let top     = pixels + cast(u64, source.height - 1 - sampleY.low) * source.rowStride
                let bottom  = pixels + cast(u64, source.height - 1 - sampleY.high) * source.rowStride
                let twoRows = sampleY.weight and top != bottom
                if cacheRows and x0 <= x1
                {
                    // Upscaling revisits the same horizontal samples on consecutive rows.
                    if sampleY.low == filteredBottom.sourceY or (twoRows and sampleY.high == filteredTop.sourceY) do
                        swap(&filteredTop, &filteredBottom)
                    filterTextureRow'Format(&filteredTop, top, columns.toSlice(), sampleY.low)
                    if twoRows do
                        filterTextureRow'Format(&filteredBottom, bottom, columns.toSlice(), sampleY.high)

                    let first  = cast(u64, x0 - triangle.bounds.minX)
                    let savedA = cast(const [*] u8, filteredTop.colors.storage() + first)
                    let savedB = twoRows ? cast(const [*] u8, filteredBottom.colors.storage() + first) : savedA
                    let weight = Math.Simd.splat(cast #bit(s16, cast(u16, sampleY.weight)))
                    let upper  = sampleY.weight >= 32768
                    var x      = x0
                    while x1 - x >= 3
                    {
                        let offset = (x - x0) * 4
                        let a      = Math.Simd.load(savedA + offset)
                        let ink    = twoRows ? lerpBgra8x4(a, Math.Simd.load(savedB + offset), weight, upper) : a
                        let target = row + cast(u64, x) * 4
                        let old    = Math.Simd.load(target)
                        #static if Format == .BGR8 or Format == .RGB8 or Format == .RGB16
                        {
                            Math.Simd.store(target, Math.Simd.select(CpuBgraRgbMask, ink, old))
                            if white
                            {
                                let other = white + cast(u64, x) * 4
                                Math.Simd.store(other, Math.Simd.select(CpuBgraRgbMask, ink, Math.Simd.load(other)))
                            }
                        }
                        else
                        {
                            let alpha = (cast #bit(Math.Simd.U32x4, ink) >> 24) * 0x0101_0101'u32
                            let weights = cast #bit(Math.Simd.U8x16, alpha)
                            Math.Simd.store(target, blendAlphaBgra8x4(ink, old, weights))
                            if white
                            {
                                let other = white + cast(u64, x) * 4
                                Math.Simd.store(other, blendAlphaBgra8x4(ink, Math.Simd.load(other), weights))
                            }
                        }

                        x += 4
                    }

                    for x in x until x1 + 1
                    {
                        let index = cast(u64, x - triangle.bounds.minX)
                        let a     = filteredTop.colors[index]
                        let value = twoRows ? lerpBgra8(a, filteredBottom.colors[index], sampleY.weight) : a
                        writeLinearTexturePixel'Format(row + cast(u64, x) * 4, Color.fromArgb(value))
                        if white do
                            writeLinearTexturePixel'Format(white + cast(u64, x) * 4, Color.fromArgb(value))
                    }

                    continue
                }

                for x in x0 until x1 + 1
                {
                    let sampleX = columns[cast(u64, x - triangle.bounds.minX)]
                    let a = lerpBgra8(loadColor8'Format(top, sampleX.low), loadColor8'Format(top, sampleX.high), sampleX.weight)
                    var value = a
                    if twoRows
                    {
                        let b = lerpBgra8(loadColor8'Format(bottom, sampleX.low), loadColor8'Format(bottom, sampleX.high), sampleX.weight)
                        value = lerpBgra8(a, b, sampleY.weight)
                    }

                    writeLinearTexturePixel'Format(row + cast(u64, x) * 4, Color.fromArgb(value))
                    if white do
                        writeLinearTexturePixel'Format(white + cast(u64, x) * 4, Color.fromArgb(value))
                }

                continue
            }

            for x in x0 until x1 + 1
            {
                let sx = cast(f32, x) + 0.5
                let w0 = Math.mulAdd(-dy[0], sx - origin[0].x, c0) * invArea
                let w1 = Math.mulAdd(-dy[1], sx - origin[1].x, c1) * invArea
                let w2 = Math.mulAdd(-dy[2], sx - origin[2].x, c2) * invArea

                // Keep the general sampler's barycentric and normalized coordinates, including
                // their rounding. The only difference is resolving paint and format once.
                let pos = p0 * w0 + p1 * w1 + p2 * w2
                let u   = (pos.x - paintRect.x) / paintWidth
                let v   = 1.0 - (pos.y - paintRect.y) / paintHeight
                let fx  = Math.saturate(u) * source.width - 0.5
                let fy  = (1.0 - Math.saturate(v)) * source.height - 0.5
                let ix  = Math.floor(fx)
                let iy  = Math.floor(fy)
                let col = cast(s32, ix)
                let src = cast(s32, iy)
                let xLo = Math.clamp(col, 0, source.width - 1)
                let xHi = Math.clamp(col + 1, 0, source.width - 1)
                let yLo = Math.clamp(src, 0, source.height - 1)
                let yHi = Math.clamp(src + 1, 0, source.height - 1)
                let ink = sampleColor8Bilinear'Format(source, xLo, xHi, yLo, yHi, bilinearWeight(fx - ix), bilinearWeight(fy - iy))
                writeLinearTexturePixel'Format(row + cast(u64, x) * 4, ink)
                if white do
                    writeLinearTexturePixel'Format(white + cast(u64, x) * 4, ink)
            }
        }
    }

    // A bitmap glyph at its raster size has one atlas byte per destination pixel. Its triangles
    // are only a transport for the quad, so composite the mask as rows without interpolating.
    mtd tryDrawBitmapGlyph(batch: *RasterBatch, vertices: const [*] VertexLayout, bandMinY, bandMaxY: s32)->bool
    {
        let first   = vertices[0]
        let last    = vertices[5]
        let right   = Vector2{last.pos.x, first.pos.y}
        let lower   = Vector2{first.pos.x, last.pos.y}
        let uvRight = Vector2{last.uv.x, first.uv.y}
        let uvLower = Vector2{first.uv.x, last.uv.y}
        if vertices[1].pos != right or
           vertices[2].pos != lower or
           vertices[3].pos != lower or
           vertices[4].pos != right or
           vertices[1].uv != uvRight or
           vertices[2].uv != uvLower or
           vertices[3].uv != uvLower or
           vertices[4].uv != uvRight do
            return false

        for vertex in Swag.makeSlice(vertices, 6) where vertex.color != first.color do
            return false

        // Limit the input range of both mappings so interpolation error stays within a texel.
        func bounded(value: f32)->bool => Math.abs(value) <= 16384
        func aligned(value, rounded: f32)->bool => bounded(rounded) and Math.abs(value - rounded) <= 0.001

        let p0 = batch.transform.transformPoint(first.pos)
        let p1 = batch.transform.transformPoint(last.pos)
        if not bounded(p0.x) or not bounded(p0.y) or not bounded(p1.x) or not bounded(p1.y) do
            return false

        let size = Vector2{cast(f32, batch.atlasMaxX + 1), cast(f32, batch.atlasMaxY + 1)}
        let uv0  = first.uv * size
        let uv1  = last.uv * size
        let u0   = Math.round(uv0.x)
        let v0   = Math.round(uv0.y)
        let u1   = Math.round(uv1.x)
        let v1   = Math.round(uv1.y)
        if u0 < 0 or
           v0 < 0 or
           u1 > size.x or
           v1 > size.y or
           u1 <= u0 or
           v1 <= v0 or
           Math.abs((u1 - u0) - (p1.x - p0.x)) > 0.002 or
           Math.abs((v1 - v0) - (p1.y - p0.y)) > 0.002 or
           not aligned(uv0.x, u0) or
           not aligned(uv0.y, v0) or
           not aligned(uv1.x, u1) or
           not aligned(uv1.y, v1) do
            return false

        let x0 = Math.ceil(p0.x - 0.5)
        let y0 = Math.ceil(p0.y - 0.5)
        let x1 = x0 + u1 - u0
        let y1 = y0 + v1 - v0

        // If the pixel centers approach either edge of a texel, keep the original
        // triangle coverage and sampling. Otherwise the fractional phase is irrelevant.
        let phaseX = x0 + 0.5 - p0.x
        let phaseY = y0 + 0.5 - p0.y
        if phaseX < 0.01 or phaseX > 0.99 or phaseY < 0.01 or phaseY > 0.99 do
            return false

        var ink = Color.fromArgb(first.color)
        if ink.a == 0 do
            return true
        let left   = Math.max(cast(s32, x0), batch.clipMinX)
        let rightX = Math.min(cast(s32, x1), batch.clipMaxX + 1)
        let top    = Math.max(cast(s32, y0), batch.clipMinY, bandMinY)
        let bottom = Math.min(cast(s32, y1), batch.clipMaxY + 1, bandMaxY + 1)
        if left >= rightX or top >= bottom do
            return true

        let atlas  = unwrap batch.atlas
        let srcX   = cast(s32, u0) + left - cast(s32, x0)
        let srcY   = cast(s32, v0) + top - cast(s32, y0)
        let width  = rightX - left
        let alpha  = ink.a
        let fill   = cast #bit(Math.Simd.U8x16, Math.Simd.splat(first.color))
        let pixels = atlas.data.storage()
        for y in top until bottom
        {
            let row    = batch.atlasMaxY - (srcY + y - top)
            let mask   = pixels + cast(u64, row) * atlas.width + cast(u64, srcX)
            let target = batch.pixels + cast(u64, batch.height - y - 1) * batch.rowStride + cast(u64, left) * 4
            var x      = 0's32
            if alpha == 255 and not .stencilOn
            {
                while width - x >= 4
                {
                    let weight = cast(Math.Simd.U32x4, [cast(u32, g_FontGammaOpaque[mask[x]]), cast(u32, g_FontGammaOpaque[mask[x + 1]]),
                                                        cast(u32, g_FontGammaOpaque[mask[x + 2]]), cast(u32, g_FontGammaOpaque[mask[x + 3]])])
                    let weights = cast #bit(Math.Simd.U8x16, weight * 0x0101_0101'u32)
                    let dst     = target + x * 4
                    Math.Simd.store(dst, blendAlphaBgra8x4(fill, Math.Simd.load(dst), weights))
                    x += 4
                }
            }

            for column in x until width
            {
                let value = mask[column]
                ink.a = alpha == 255 ? g_FontGammaOpaque[value] :
                        cast(u8, Math.clamp(Math.round(cast(f32, alpha) * g_FontGammaLut[value]), 0.0, 255.0))
                if .stencilOn
                {
                    let clip = batch.stencil[cast(u64, y) * batch.width + cast(u64, left + column)]
                    ink.a = cast(u8, (cast(u32, ink.a) * clip) / 255)
                }

                blendAlphaBgra8(target + column * 4, ink)
            }
        }

        return true
    }

    mtd drawTriangleRange(batch: *RasterBatch, bandMinY, bandMaxY: s32)
    {
        let vertices = batch.painter!.vertexBuffer.storage()
        var i        = batch.start
        let end      = batch.start + batch.count
        let bitmap   = .program == CpuProgram_Font and
                       batch.solidPaint and
                       batch.atlas and
                       batch.atlas.bytesPerPixel == 1 and
                       batch.image!.pixelFormat == .BGRA8 and
                       .blendingMode == .Alpha and
                       .colorMask.r and
                       .colorMask.g and
                       .colorMask.b and
                       not .colorMask.a and
                       not .stencilWrite and
                       .overlapPass == 0 and
                       not .alphaResolve and
                       not .whiteMatte and
                       batch.transform.m12 == 0 and
                       batch.transform.m21 == 0 and
                       batch.transform.m11 > 0 and
                       batch.transform.m22 > 0

        while i + 2 < end
        {
            if bitmap and i + 5 < end and .tryDrawBitmapGlyph(batch, vertices + i, bandMinY, bandMaxY)
            {
                i += 6
                continue
            }

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
        func binTriangles(batch: *RasterBatch, bounds: PixelBounds, bandCount: s32)->Array'Array'u32
        {
            var bins: #returntype
            bins.resize(cast(u64, bandCount))
            let vertices      = batch.painter!.vertexBuffer.storage() + batch.start
            let triangleCount = batch.count / 3
            var references    = 0'u64
            for triangle in triangleCount
            {
                let index = triangle * 3
                let y0    = batch.transform.transformPoint(vertices[index].pos).y
                let y1    = batch.transform.transformPoint(vertices[index + 1].pos).y
                let y2    = batch.transform.transformPoint(vertices[index + 2].pos).y
                let low   = Math.min(y0, y1, y2)
                let high  = Math.max(y0, y1, y2)
                if not Math.isFinite(y0) or
                   not Math.isFinite(y1) or
                   not Math.isFinite(y2) or
                   low < -2_000_000_000.0 or
                   high > 2_000_000_000.0 do
                    return {}

                // Use the same rounded, target-clamped range as drawTriangleBatch.
                let firstY = Math.max(bounds.minY, Math.clamp(cast(s32, Math.floor(low)), 0, batch.height - 1))
                let lastY  = Math.min(bounds.maxY, Math.clamp(cast(s32, Math.ceil(high)) - 1, 0, batch.height - 1))
                if firstY > lastY do
                    continue
                let first = (firstY - bounds.minY) / CpuBandRows
                let last  = (lastY - bounds.minY) / CpuBandRows
                references += cast(u64, last - first + 1)
                if references > cast(u64, triangleCount) * 8 do
                    return {}

                for band in first until last + 1 do
                    bins[band].add(cast(u32, index))
            }

            return bins
        }

        if bounds.area() < CpuBandPixelThreshold or
           bounds.rows() <= CpuBandRows or
           Swag.workerCount() <= 1
        {
            .drawTriangleRange(batch, bounds.minY, bounds.maxY)
            return
        }

        // More blocks than workers let the runtime balance localized overdraw. Whole blocks
        // keep triangle order and exclusive row ownership; the final block may be shorter.
        let bandCount = (bounds.rows() - 1) / CpuBandRows + 1
        let bins      = bandCount >= 4 and batch.count >= 384 ? binTriangles(batch, bounds, bandCount) : {}
        let indexed   = bins.toSlice()
        let renderer  = me
        parallel for |renderer, batch, bounds, indexed| index in cast(u64, bandCount)
        {
            let bandY = bounds.minY + cast(s32, index) * CpuBandRows
            let lastY = bandY + Math.min(CpuBandRows - 1, bounds.maxY - bandY)
            if indexed.count
            {
                let vertices = batch.painter!.vertexBuffer.storage() + batch.start
                for triangle in indexed[index] do
                    renderer.drawTriangleBatch(batch, vertices + triangle, bandY, lastY)
            }
            else
            {
                renderer.drawTriangleRange(batch, bandY, lastY)
            }
        }
    }

    // Resolves everything a triangle range needs exactly once: transform, clip, target bytes,
    // stencil plane, paint texture, and font atlas. Command state cannot change inside a range,
    // so per-pixel work then reads plain locals.
    mtd setupBatch(batch: *RasterBatch, image: *Image, painter: *Painter, triangles: const *TriangleBatch, transform: Transform2)
    {
        batch.image     = image
        batch.painter   = painter
        batch.start     = triangles.start
        batch.count     = triangles.count
        batch.transform = transform
        batch.pixels    = image.pixels.storage()
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
            batch.clipMinX = Math.max(batch.clipMinX, cast(s32, Math.ceil(.scissorRect.x)))
            batch.clipMinY = Math.max(batch.clipMinY, cast(s32, Math.ceil(.scissorRect.y)))
            batch.clipMaxX = Math.min(batch.clipMaxX, cast(s32, Math.ceil(.scissorRect.right())) - 1)
            batch.clipMaxY = Math.min(batch.clipMaxY, cast(s32, Math.ceil(.scissorRect.bottom())) - 1)
        }

        batch.stencil = .currentStencil().pixels.storage()

        batch.solidPaint      = not .paintOn or .paint.type == .SolidColor
        batch.paintImage      = null
        batch.paintPlanar     = null
        batch.blurTaps        = null
        batch.blurTapCount    = 0
        batch.blurWeights     = null
        batch.blurWeightCount = 0
        if .paintOn and .paint.type == .Texture and .paint.texture.isValid()
        {
            let storage = .findTexture(.paint.texture.handle)
            if storage
            {
                batch.paintImage = &storage.image
                if storage.planar.width > 0 do
                    batch.paintPlanar = &storage.planar
            }
        }

        if batch.paintImage and
           not batch.paintPlanar and
           .paint.uvMode == .FillSubRect and
           .program != CpuProgram_Blur and
           .program != CpuProgram_Resolve and
           .program != CpuProgram_Backdrop
        {
            let p       = &.paint
            let sampler = &batch.subRect
            sampler.origin  = {p.boundRect.x, p.boundRect.y}
            sampler.size    = {Math.max(p.boundRect.z - p.boundRect.x, 0.000001), Math.max(p.boundRect.w - p.boundRect.y, 0.000001)}
            sampler.minX    = cast(s32, p.texturePixelBounds.x)
            sampler.minY    = cast(s32, p.texturePixelBounds.y)
            sampler.maxX    = cast(s32, p.texturePixelBounds.z)
            sampler.maxY    = cast(s32, p.texturePixelBounds.w)
            sampler.span    = {cast(f32, (sampler.maxX - sampler.minX + 1)), cast(f32, (sampler.maxY - sampler.minY + 1))}
            sampler.nearest = p.interpolationMode == .Pixel and .contentScale == 1
            sampler.sharp   = p.interpolationMode == .Pixel and not sampler.nearest
            if sampler.sharp
            {
                sampler.sharpWidth.x = Math.clamp((sampler.span.x / sampler.size.x) / .contentScale, 0.0001, 1.0)
                sampler.sharpWidth.y = Math.clamp((sampler.span.y / sampler.size.y) / .contentScale, 0.0001, 1.0)
            }
        }

        batch.atlas = .fontAtlas()
        if .program == CpuProgram_Font and batch.atlas
        {
            batch.atlasMaxX = cast(s32, batch.atlas.width / batch.atlas.bytesPerPixel) - 1
            batch.atlasMaxY = cast(s32, batch.atlas.height) - 1
            ensureFontGammaLut()
        }
    }

    // Copies or blends a rectangle with one source texel per destination pixel.
    // SVG coverage tiles and window presentation both use this mapping.
    mtd tryDrawTextureRect(batch: *RasterBatch)->bool
    {
        if batch.count != 6 or .program != CpuProgram_Default and .program != CpuProgram_Simple do
            return false
        if .contentScale != 1 or not batch.transform.isTranslationOnly() do
            return false
        if not .colorMask.r or
           not .colorMask.g or
           not .colorMask.b do
            return false
        let copy  = .blendingMode == .Copy and .colorMask.a and not .scissorOn
        let blend = .blendingMode == .Alpha and not .colorMask.a and batch.transform.isIdentity()
        if (not copy and not blend) or .stencilOn or .stencilWrite or .overlapMode or .alphaResolve do
            return false

        let source = batch.paintImage
        let target = batch.image
        if not source or
           not target or
           source == target or
           target.pixelFormat != .BGRA8 do
            return false
        let rgba = source.pixelFormat == .RGBA8
        if source.pixelFormat != .BGRA8 and not (blend and rgba) do
            return false
        if blend and source.alphaMode != .Straight do
            return false

        let params = &.paint
        if params.type != .Texture or
           params.interpolationMode != .Pixel or
           params.uvMode != (blend ? .Fill : .FillSubRect) do
            return false

        let vertices    = batch.painter!.vertexBuffer.storage() + batch.start
        let topLeft     = Vector2{params.boundRect.x, params.boundRect.y}
        let topRight    = Vector2{params.boundRect.z, params.boundRect.y}
        let bottomRight = Vector2{params.boundRect.z, params.boundRect.w}
        let bottomLeft  = Vector2{params.boundRect.x, params.boundRect.w}
        if vertices[0].pos != topLeft or
           vertices[1].pos != topRight or
           vertices[2].pos != bottomRight or
           vertices[3].pos != topLeft or
           vertices[4].pos != bottomRight or
           vertices[5].pos != bottomLeft
        {
            return false
        }

        let white = Color.fromArgb(Argb.White).argb
        for vertex in Swag.makeSlice(vertices, 6)
        {
            if vertex.color != white or vertex.cov != 1 do
                return false
        }

        let deviceTopLeft     = batch.transform.transformPoint(topLeft)
        let deviceBottomRight = batch.transform.transformPoint(bottomRight)
        let dstX              = cast(s32, deviceTopLeft.x)
        let dstY              = cast(s32, deviceTopLeft.y)
        let dstRight          = cast(s32, deviceBottomRight.x)
        let dstBottom         = cast(s32, deviceBottomRight.y)
        if cast(f32, dstX) != deviceTopLeft.x or
           cast(f32, dstY) != deviceTopLeft.y or
           cast(f32, dstRight) != deviceBottomRight.x or
           cast(f32, dstBottom) != deviceBottomRight.y do
            return false

        let srcX      = blend ? 0 : cast(s32, params.texturePixelBounds.x)
        let srcY      = blend ? 0 : cast(s32, params.texturePixelBounds.y)
        let srcRight  = blend ? source.width : cast(s32, params.texturePixelBounds.z) + 1
        let srcBottom = blend ? source.height : cast(s32, params.texturePixelBounds.w) + 1
        let width     = dstRight - dstX
        let height    = dstBottom - dstY
        if width <= 0 or height <= 0 or srcRight - srcX != width or srcBottom - srcY != height do
            return false
        if dstX < 0 or dstY < 0 or dstRight > target.width or dstBottom > target.height do
            return false
        if srcX < 0 or srcY < 0 or srcRight > source.width or srcBottom > source.height do
            return false

        // Keep the aligned blend within the range where interpolated f32 pixel centers
        // also select the same texel, including near the diagonal shared by the triangles.
        if blend and (dstRight > 16384 or dstBottom > 16384) do
            return false

        let left   = Math.max(dstX, batch.clipMinX)
        let right  = Math.min(dstRight, batch.clipMaxX + 1)
        let top    = Math.max(dstY, batch.clipMinY)
        let bottom = Math.min(dstBottom, batch.clipMaxY + 1)
        if left >= right or top >= bottom do
            return true

        let rowBytes = cast(u64, right - left) * 4
        for y in top until bottom
        {
            let sourceY   = srcY + y - dstY
            let sourceX   = srcX + left - dstX
            let sourceRow = source.pixels.storage() + cast(u64, (source.height - sourceY - 1)) * source.rowStride + cast(u64, sourceX) * 4
            let dstOffset = cast(u64, target.height - y - 1) * target.rowStride + cast(u64, left) * 4
            let targetRow = target.pixels.storage() + dstOffset
            if copy
            {
                Memory.copy(targetRow, sourceRow, rowBytes)
                continue
            }

            let sourceBlue = rgba ? 2 : 0
            let sourceRed  = rgba ? 0 : 2
            var x          = 0's32
            while right - left - x >= 4
            {
                let src     = cast #bit(Math.Simd.U32x4, Math.Simd.load(sourceRow + x * 4))
                let alpha   = src >> 24
                let weights = cast #bit(Math.Simd.U8x16, alpha * 0x0101_0101'u32)
                let bgra    = rgba ? ((src & 0x00FF_0000'u32) >> 16) | (src & 0xFF00_FF00'u32) | ((src & 0xFF'u32) << 16) : src
                let pixel   = targetRow + x * 4
                Math.Simd.store(pixel, blendAlphaBgra8x4(cast #bit(Math.Simd.U8x16, bgra), Math.Simd.load(pixel), weights))
                if let matte = .whiteMatte
                {
                    let dst = matte + dstOffset + x * 4
                    Math.Simd.store(dst, blendAlphaBgra8x4(cast #bit(Math.Simd.U8x16, bgra), Math.Simd.load(dst), weights))
                }

                x += 4
            }

            for column in x until right - left
            {
                let texel = sourceRow + column * 4
                let alpha = texel[3]
                if alpha
                {
                    let color = Color.fromArgb(alpha, texel[sourceRed], texel[1], texel[sourceBlue])
                    blendAlphaBgra8(targetRow + column * 4, color)
                    if let matte = .whiteMatte do
                        blendAlphaBgra8(matte + dstOffset + column * 4, color)
                }
            }
        }

        return true
    }

    // An aligned full-target resolve has one source block per destination pixel. Skip the
    // triangle coverage, interpolated paint coordinates and format dispatch for this case.
    // Other mappings and render states keep the general shader path.
    mtd tryResolveTextureRect(batch: *RasterBatch)->bool
    {
        if batch.count != 6 or .program != CpuProgram_Resolve or not batch.transform.isIdentity() do
            return false
        if .blendingMode != .Copy or
           not .colorMask.r or
           not .colorMask.g or
           not .colorMask.b or
           not .colorMask.a or
           .stencilOn or
           .stencilWrite or
           .scissorOn or
           .overlapMode or
           .alphaResolve do
            return false

        let source = batch.paintImage
        let target = batch.image
        if not source or
           not target or
           source == target or
           source.pixelFormat != .BGRA8 or
           target.pixelFormat != .BGRA8 do
            return false

        let factor = Math.clamp(.resolveFactor, 1, 8)
        if source.width != target.width * factor or source.height != target.height * factor do
            return false
        let params = &.paint
        let insetX = 0.5'f32 / source.width
        let insetY = 0.5'f32 / source.height
        if params.type != .Texture or
           params.uvMode != .FillSubRect or
           params.boundRect != Vector4{0, 0, cast(f32, target.width), cast(f32, target.height)} or
           params.textureRect != Vector4{insetX, insetY, 1 - insetX, 1 - insetY} do
            return false

        let vertices = batch.painter!.vertexBuffer.storage() + batch.start
        let corners  = [Vector2{0, 0}, Vector2{target.width, 0}, Vector2{target.width, target.height},
                        Vector2{0, 0}, Vector2{target.width, target.height}, Vector2{0, target.height}]
        for i in 6 where vertices[i].pos != corners[i] or vertices[i].color != Argb.White do
            return false

        resolveTexture(source, target, factor)
        return true
    }

    func resolveTexture(source: const *Image, target: *Image, factor: s32)
    {
        func resolveRows(source: const *Image, target: *Image, factor, firstRow, endRow: s32)
        {
            var previousTop, previousBottom: u64
            var previousColor: u32
            var hasPrevious:   bool

            // Keep the shader's normalized additions in the same top-to-bottom sample order.
            // Integer averaging changes truncation at byte boundaries, even for opaque mattes.
            for y in firstRow until endRow
            {
                let destination = target.pixels.storage() + cast(u64, y) * cast(u64, target.rowStride)
                for x in target.width
                {
                    let pixel = destination + cast(u64, x) * 4
                    if factor == 2
                    {
                        // SVG mattes and UI grounds repeat many identical 2x2 blocks. Reuse
                        // their exact resolved bytes, including float rounding and straight-alpha
                        // conversion, instead of normalizing the same four samples again.
                        let sourceOffset = cast(u64, y * 2) * cast(u64, source.rowStride) + cast(u64, x) * 8
                        let bottom       = cast(const [*] u64, source.pixels.storage() + sourceOffset)[0]
                        let top          = cast(const [*] u64, source.pixels.storage() + sourceOffset + cast(u64, source.rowStride))[0]
                        if hasPrevious and top == previousTop and bottom == previousBottom
                        {
                            cast([*] u32, pixel)[0] = previousColor
                            continue
                        }

                        previousTop    = top
                        previousBottom = bottom
                        hasPrevious    = true
                    }

                    var sum: Math.Simd.F32x4
                    for row in factor
                    {
                        let sourceRow = y * factor + factor - row - 1
                        let pixels    = source.pixels.storage() + cast(u64, sourceRow) * cast(u64, source.rowStride) + cast(u64, x * factor) * 4
                        for column in factor
                        {
                            let pixel = pixels + cast(u64, column) * 4
                            sum += cast(Math.Simd.F32x4, [cast(f32, pixel[0]), cast(f32, pixel[1]), cast(f32, pixel[2]), cast(f32, pixel[3])]) / 255.0
                        }
                    }

                    let alpha = sum[3] / cast(f32, factor * factor)
                    let color = sum[3] <= 0.00001 ? Color.fromArgbF32(alpha, 0, 0, 0) : Color.fromArgbF32(alpha, sum[2] / sum[3], sum[1] / sum[3], sum[0] / sum[3])
                    pixel[0]      = color.b
                    pixel[1]      = color.g
                    pixel[2]      = color.r
                    pixel[3]      = color.a
                    previousColor = cast(const [*] u32, pixel)[0]
                }
            }
        }

        // Work scales with source samples, not destination pixels. Bands own disjoint rows;
        // the synchronous join keeps both texture buffers alive until every store completes.
        let sampleCount = cast(u64, source.width) * cast(u64, source.height)
        if sampleCount < CpuBandPixelThreshold or
           target.height <= CpuBandRows or
           Swag.workerCount() <= 1
        {
            resolveRows(source, target, factor, 0, target.height)
        }
        else
        {
            let bandCount = (target.height - 1) / CpuBandRows + 1
            parallel for |source, target, factor| index in cast(u64, bandCount)
            {
                let firstRow = cast(s32, index) * CpuBandRows
                resolveRows(source, target, factor, firstRow, Math.min(firstRow + CpuBandRows, target.height))
            }
        }
    }

    // A solid, device-aligned rectangle shades one color across its full span. Avoid
    // testing both triangles against their shared diagonal before writing that span.
    mtd tryDrawSolidRect(batch: *RasterBatch, bounds: PixelBounds)->bool
    {
        if batch.count != 6 or
           not batch.solidPaint or
           (.program != CpuProgram_Default and .program != CpuProgram_Simple) or
           .stencilOn or
           .stencilWrite or
           .overlapMode or
           .alphaResolve or
           .whiteMatte != null do
            return false
        if batch.image!.pixelFormat != .BGRA8 do
            return false

        let transform = &batch.transform
        if transform.m12 or transform.m21 or transform.m11 <= 0 or transform.m22 <= 0 do
            return false

        let vertices = batch.painter!.vertexBuffer.storage() + batch.start
        let color    = Color.fromArgb(vertices[0].color)
        if .blendingMode != .Copy and
           (.blendingMode != .Alpha or color.a != 255 or .colorMask.a) do
            return false

        for vertex in Swag.makeSlice(vertices, 6) where vertex.color != color.argb or vertex.cov != 1 do
            return false

        let first = vertices[0].pos
        let last  = vertices[2].pos
        if vertices[1].pos != Vector2{last.x, first.y} or
           vertices[3].pos != first or
           vertices[4].pos != last or
           vertices[5].pos != Vector2{first.x, last.y} do
            return false

        // A near-integral edge stays on the same side of every pixel center.
        func aligned(value: f32, rounded: f32)->bool => Math.abs(rounded) <= 16384 and Math.abs(value - rounded) <= 0.001

        let topLeft     = transform.transformPoint(first)
        let bottomRight = transform.transformPoint(last)
        let left        = Math.round(topLeft.x)
        let top         = Math.round(topLeft.y)
        let right       = Math.round(bottomRight.x)
        let bottom      = Math.round(bottomRight.y)
        if left >= right or
           top >= bottom or
           not aligned(topLeft.x, left) or
           not aligned(topLeft.y, top) or
           not aligned(bottomRight.x, right) or
           not aligned(bottomRight.y, bottom) do
            return false

        let minX = Math.max(cast(s32, left), batch.clipMinX)
        let minY = Math.max(cast(s32, top), batch.clipMinY, bounds.minY)
        let maxX = Math.min(cast(s32, right), batch.clipMaxX + 1)
        let maxY = Math.min(cast(s32, bottom), batch.clipMaxY + 1, bounds.maxY + 1)
        if minX >= maxX or minY >= maxY do
            return true

        let blue  = .colorMask.b ? 255'u8 : 0'u8
        let green = .colorMask.g ? 255'u8 : 0'u8
        let red   = .colorMask.r ? 255'u8 : 0'u8
        let alpha = .colorMask.a ? 255'u8 : 0'u8
        let mask  = cast(Math.Simd.U8x16, [blue, green, red, alpha, blue, green, red, alpha,
                                           blue, green, red, alpha, blue, green, red, alpha])
        let fill = cast(Math.Simd.U8x16, [color.b, color.g, color.r, color.a, color.b, color.g, color.r, color.a,
                                          color.b, color.g, color.r, color.a, color.b, color.g, color.r, color.a])
        let width = maxX - minX
        for y in minY until maxY
        {
            var pixel = batch.pixels + cast(u64, batch.height - y - 1) * cast(u64, batch.rowStride) + cast(u64, minX) * 4
            for width / 4
            {
                Math.Simd.store(pixel, Math.Simd.select(mask, fill, Math.Simd.load(pixel)))
                pixel += 16
            }

            for width % 4
            {
                if blue do
                    pixel[0] = color.b
                if green do
                    pixel[1] = color.g
                if red do
                    pixel[2] = color.r
                if alpha do
                    pixel[3] = color.a
                pixel += 4
            }
        }

        return true
    }

    mtd markStencilDirty(bounds: PixelBounds)
    {
        let stencil = .currentStencil()
        if stencil.dirty.isEmpty()
        {
            stencil.dirty = bounds
        }
        else
        {
            stencil.dirty.minX = Math.min(stencil.dirty.minX, bounds.minX)
            stencil.dirty.minY = Math.min(stencil.dirty.minY, bounds.minY)
            stencil.dirty.maxX = Math.max(stencil.dirty.maxX, bounds.maxX)
            stencil.dirty.maxY = Math.max(stencil.dirty.maxY, bounds.maxY)
        }
    }

    mtd scanBounds(image: *Image, fill: const *ScanFillBatch, transform: const *Transform2)->Rectangle
    {
        let local = Rectangle{fill.low.x, fill.low.y, fill.high.x - fill.low.x, fill.high.y - fill.low.y}
        var area  = transform.transformBounds(local)
        if not Math.isFinite(area.x) or not Math.isFinite(area.y) or
           not Math.isFinite(area.right()) or not Math.isFinite(area.bottom()) do
            return {}

        area.intersect({0, 0, cast(f32, image.width), cast(f32, image.height)})
        if .scissorOn do
            area.intersect(.scissorRect)
        return area
    }

    func firstScanPoint(painter: const *Painter, fill: const *ScanFillBatch)->u64
    {
        return fill.first == 0 ? 0'u64 : painter.scanContourEnds[fill.first - 1]
    }

    // Limit live crossing storage even for dense paths spanning the entire surface.
    func scanBandHeight(pointCount: u64)->s32
    {
        return cast(s32, Math.clamp(1_048_576'u64 / (pointCount * VerticalSamples), 1, 256))
    }

    // Device-space points and row bounds shared by the bands of a compound fill.
    struct ScanContourBounds
    {
        low, high: f32
        finite:    bool
    }

    struct ProjectedContours
    {
        points: Array'Vector2
        bounds: Array'ScanContourBounds
    }

    func projectContours(projected: *ProjectedContours, painter: const *Painter, fill: const *ScanFillBatch, transform: const *Transform2, first, pointCount: u64)
    {
        let points = painter.scanPoints.toSlice()
        let ends   = painter.scanContourEnds.toSlice()[fill.first until fill.end]
        let mapped = projected.points.emplaceAddress(cast(u32, pointCount))
        projected.bounds.reserve(ends.count)
        var point = first
        for end in ends
        {
            var bounds = ScanContourBounds{Swag.F32.Max, -Swag.F32.Max, true}
            for index in point until end
            {
                let value = transform.transformPoint(points[index])
                bounds.finite         = bounds.finite and value.isFinite()
                bounds.low            = Math.min(bounds.low, value.y)
                bounds.high           = Math.max(bounds.high, value.y)
                mapped[index - first] = value
            }

            projected.bounds.add(bounds)
            point = end
        }
    }

    mtd gatherProjectedRows(painter: const *Painter, fill: const *ScanFillBatch, projected: const *ProjectedContours, origin: Vector2, width, height: s32)->[..] ScanSample
    {
        let crossings = .scanScratch.startRows(height)
        let points    = projected.points.toSlice()
        let ends      = painter.scanContourEnds.toSlice()[fill.first until fill.end]
        let first     = firstScanPoint(painter, fill)
        let identity  = Transform2.Identity
        var point     = 0'u64
        for terminal, index in ends
        {
            let end    = terminal - first
            let bounds = &projected.bounds[index]

            // Use the same tile-local coordinates the edge collector will subtract.
            if not bounds.finite or (bounds.high - origin.y >= 0 and bounds.low - origin.y <= cast(f32, height)) do
                addScanContour(crossings, points[point until end], &identity, 1, origin, true, cast(f32, width))
            point = end
        }

        return crossings
    }

    mtd gatherScanRows(painter: const *Painter, fill: const *ScanFillBatch, transform: const *Transform2, origin: Vector2, width, height: s32)->[..] ScanSample
    {
        let crossings = .scanScratch.startRows(height)
        let points    = painter.scanPoints.toSlice()
        let ends      = painter.scanContourEnds.toSlice()
        var point     = firstScanPoint(painter, fill)
        for end in ends[fill.first until fill.end]
        {
            addScanContour(crossings, points[point until end], transform, 1, origin, false, cast(f32, width))
            point = end
        }

        return crossings
    }

    #[Swag.Inline]
    func scanAlpha4(values: const [*] f32, scale: Math.Simd.F32x4)->Math.Simd.U32x4
    {
        let scaled = Math.Simd.load(values) * scale
        let whole  = Math.floor(scaled)
        // Keep the scalar rounding at values just below a half-integer.
        let roundUp = (scaled - whole >= Math.Simd.splat(0.5'f32)) & 1'u32
        // Integers this small map directly to the low mantissa bits at 2^23.
        let biased = cast #bit(Math.Simd.U32x4, whole + Math.Simd.splat(8_388_608.0'f32))
        return biased - 0x4B00_0000'u32 + roundUp
    }

    mtd drawScanFill(painter: *Painter, fill: const *ScanFillBatch)
    {
        let image = .currentImage()
        if not image do
            return

        let transform = .deviceTransform()
        let area      = .scanBounds(image, fill, &transform)
        if area.isEmpty() do
            return

        let left       = cast(s32, Math.floor(area.x))
        let top        = cast(s32, Math.floor(area.y))
        let right      = cast(s32, Math.ceil(area.right()))
        let bottom     = cast(s32, Math.ceil(area.bottom()))
        let width      = right - left
        let firstPoint = firstScanPoint(painter, fill)
        let pointCount = painter.scanContourEnds[fill.end - 1] - firstPoint
        let bandHeight = scanBandHeight(pointCount)
        let color      = fill.color
        let tint       = cast #bit(Math.Simd.U8x16, Math.Simd.splat(color.argb))
        let alphaScale = Math.Simd.splat(cast(f32, color.a) / VerticalSamples)
        let evenOdd    = fill.rule == .EvenOdd
        let stencil    = .stencilOn ? .currentStencil().pixels.storage() : null
        if .stencilWrite and .stencilMode == .Set do
            .markStencilDirty({left, top, right - 1, bottom - 1})

        var projected: ProjectedContours

        // Keep the device-point cache within the same order as a band's crossing storage.
        if fill.end - fill.first >= 128 and pointCount <= 1_048_576 and bottom - top > bandHeight * 2 do
            projectContours(&projected, painter, fill, &transform, firstPoint, pointCount)

        for var y = top; y < bottom; y += bandHeight
        {
            let height    = Math.min(bandHeight, bottom - y)
            let origin    = Vector2{cast(f32, left), cast(f32, y)}
            let crossings = projected.bounds.count ? .gatherProjectedRows(painter, fill, &projected, origin, width, height) :
                            .gatherScanRows(painter, fill, &transform, origin, width, height)

            for row in height
            {
                let deviceY  = y + cast(s32, row)
                let {values: coverage, first: firstX, end: endX} = .scanScratch.resolveRow(crossings, cast(s32, row), width, evenOdd, false)
                let maskRow  = stencil ? stencil + cast(u64, deviceY) * image.width + left : null
                if .stencilWrite
                {
                    let stencilPixels = unwrap maskRow
                    for x in firstX until endX where coverage[x] > 0
                    {
                        let alpha = coverageAlpha(color.a, coverage[x] / VerticalSamples)
                        if .stencilMode == .Set do
                            stencilPixels[x] = Math.max(stencilPixels[x], alpha)
                        else do
                            stencilPixels[x] = cast(u8, (cast(u32, stencilPixels[x]) * (255 - cast(u32, alpha))) / 255)
                    }

                    continue
                }

                let dstOffset = cast(u64, image.height - deviceY - 1) * image.rowStride + cast(u64, left) * 4
                let dst = image.pixels.storage() + dstOffset
                var x   = firstX
                while endX - x >= 4
                {
                    var weight = scanAlpha4(coverage + x, alphaScale)
                    if maskRow
                    {
                        let clip = cast(Math.Simd.U32x4, [cast(u32, maskRow[x]), cast(u32, maskRow[x + 1]),
                                                         cast(u32, maskRow[x + 2]), cast(u32, maskRow[x + 3])])
                        let product = weight * clip + 1'u32
                        weight = (product + (product >> 8)) >> 8
                    }

                    let weights = cast #bit(Math.Simd.U8x16, weight * 0x0101_0101'u32)
                    let target  = dst + x * 4
                    Math.Simd.store(target, blendAlphaBgra8x4(tint, Math.Simd.load(target), weights))
                    if let matte = .whiteMatte
                    {
                        let white = matte + dstOffset + x * 4
                        Math.Simd.store(white, blendAlphaBgra8x4(tint, Math.Simd.load(white), weights))
                    }

                    x += 4
                }

                for column in x until endX where coverage[column] > 0
                {
                    var ink = color
                    ink.a   = coverageAlpha(color.a, coverage[column] / VerticalSamples)
                    if maskRow do
                        ink.a = cast(u8, (cast(u32, ink.a) * maskRow[column]) / 255)
                    if not ink.a do
                        continue

                    blendAlphaBgra8(dst + column * 4, ink)
                    if let matte = .whiteMatte do
                        blendAlphaBgra8(matte + dstOffset + column * 4, ink)
                }
            }
        }
    }

    mtd drawScanClip(painter: *Painter, first, end: u64)
    {
        let image = .currentImage()
        if not image do
            return

        let shapes    = painter.scanClipShapes.toSlice()[first until end]
        let transform = .deviceTransform()
        var area      = .scanBounds(image, &shapes[0], &transform)
        for &shape, index in shapes
        {
            if shape.first == shape.end do
                return
            if index do
                area.intersect(.scanBounds(image, shape, &transform))
            if area.isEmpty() do
                return
        }

        let left   = cast(s32, Math.floor(area.x))
        let top    = cast(s32, Math.floor(area.y))
        let right  = cast(s32, Math.ceil(area.right()))
        let bottom = cast(s32, Math.ceil(area.bottom()))
        let width  = right - left
        let points = painter.scanContourEnds[shapes[shapes.count - 1].end - 1] - firstScanPoint(painter, &shapes[0])
        let bandHeight = scanBandHeight(points)
        let stencil    = .currentStencil().pixels.storage()
        let alphaScale = Math.Simd.splat(255.0'f32 / VerticalSamples)
        const Pack = cast(Math.Simd.U8x16, [0'u8, 4, 8, 12, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80])
        .markStencilDirty({left, top, right - 1, bottom - 1})

        // Intersect subrow intervals before resolving fractional coverage. Two shapes can
        // touch the same pixel without sharing any part of it.
        for var y = top; y < bottom; y += bandHeight
        {
            let height      = Math.min(bandHeight, bottom - y)
            let origin      = Vector2{cast(f32, left), cast(f32, y)}
            let sampleCount = cast(u64, height) * VerticalSamples
            .scanClip.startBand(sampleCount)
            var covered = true
            for &shape, index in shapes
            {
                let crossings = .gatherScanRows(painter, shape, &transform, origin, width, height)
                covered = .scanClip.intersect(&.scanScratch, crossings, shape.rule == .EvenOdd, index == 0)
                if not covered do
                    break
            }

            if not covered do
                continue

            let rows = .scanClip.rows.toSlice()[0 until sampleCount]
            for row in height
            {
                let {values, first: startX, end: endX} = .scanScratch.resolveRow(rows, cast(s32, row), width, false, false, sortedRows: true)
                let dst = stencil + (cast(u64, y) + row) * image.width + left
                var x = startX
                while endX - x >= 4
                {
                    let alpha = cast #bit(Math.Simd.U8x16, scanAlpha4(values + x, alphaScale))
                    Math.Simd.storeLow4(dst + x, Math.Simd.shuffle(alpha, Pack))
                    x += 4
                }

                for column in x until endX do
                    dst[column] = coverageAlpha(255, values[column] / VerticalSamples)
            }
        }
    }

    mtd drawTriangles(painter: *Painter, triangles: const *TriangleBatch)
    {
        let image = .currentImage()
        if not image or triangles.count < 3 do
            return

        // A direct serial draw clips each triangle anyway. A range-wide walk is only needed
        // for scissored ranges, parallel bands, or passes that act on the range as a whole.
        let needsRange = .scissorOn or
                         .stencilWrite or
                         .overlapMode or
                         .program == CpuProgram_Backdrop or
                         Swag.workerCount() > 1
        let transform = .deviceTransform()
        let bounds    = needsRange ? .triangleRangeBounds(image, painter, triangles, transform) :
                        PixelBounds{minX: 0, minY: 0, maxX: image.width - 1, maxY: image.height - 1}
        if bounds.isEmpty() do
            return

        if .stencilWrite and .stencilMode == .Set do
            .markStencilDirty(bounds)

        var batch: RasterBatch
        .setupBatch(&batch, image, painter, triangles, transform)
        if .tryDrawSolidRect(&batch, bounds) or
           .tryDrawTextureRect(&batch) or
           .tryResolveTextureRect(&batch) do
            return

        // Both the Gaussian weights and the normalized tap offsets are constant over the draw.
        var blurTaps:    Array'BlurTap
        var blurWeights: Array'f32
        if .program == CpuProgram_Blur and batch.paintImage
        {
            let radius = Math.max(.blurRadius, 0.0)
            if radius > 0.000001
            {
                let rr       = radius * radius
                let w0       = 0.5135 / Math.pow(radius, 0.96)
                let axisSize = .blurAxis == 0 ? batch.paintImage.width : batch.paintImage.height
                var offset   = -radius
                while offset <= radius
                {
                    blurTaps.add({offset / axisSize, w0 * Math.exp((-offset * offset) / (2.0 * rr))})
                    offset += 1.0
                }

                batch.blurTaps     = blurTaps.storage()
                batch.blurTapCount = blurTaps.count
            }
        }

        if .program == CpuProgram_Backdrop and .backdropPass.mode < 2
        {
            let radius = .backdropPass.radius
            let reach  = cast(s32, Math.ceil(radius))
            let sigma  = Math.max(radius / 3, 0.001)
            var total  = 0.0'f32
            for var offset = -reach; offset <= reach; offset += 1
            {
                let weight = Math.exp(-cast(f32, offset * offset) / (2 * sigma * sigma))
                blurWeights.add(weight)
                total += weight
            }

            for &weight in blurWeights do
                weight[] /= total
            batch.blurWeights     = blurWeights.storage()
            batch.blurWeightCount = blurWeights.count
        }

        if not .overlapMode or .alphaResolve
        {
            if not .rasterizeCachedBackdrop(&batch, bounds) do
                .rasterizeRange(&batch, bounds)
            return
        }

        // Both overlap passes only ever reach the pixels the range covers, so the scratch
        // planes are reset over those bounds instead of over the whole target.
        let pixelCount = cast(u64, image.width) * cast(u64, image.height)
        if .overlapAlpha.count != pixelCount do
            .overlapAlpha.resize(pixelCount)
        clearScratchRows(.overlapAlpha.storage(), image.width, bounds)
        let solid = .solidOverlapColor(&batch)
        if solid.valid
        {
            .overlapRows.resize(cast(u64, image.height))
            for y in bounds.minY until bounds.maxY + 1 do
                .overlapRows[y] = {}
            batch.overlapRows = .overlapRows.storage()
        }

        // Destination alpha is the scratch channel in the OpenGL overlap path.
        .clearAlpha(image, bounds)
        .overlapPass = 1
        .rasterizeRange(&batch, bounds)
        if solid.valid
        {
            .compositeSolidOverlap(&batch, bounds, solid.color)
        }
        else
        {
            if .overlapWritten.count != pixelCount do
                .overlapWritten.resize(pixelCount)
            clearScratchRows(.overlapWritten.storage(), image.width, bounds)
            .overlapPass = 2
            .rasterizeRange(&batch, bounds)
        }

        .overlapPass = 0
    }

    // Gaussian intermediates overwrite a complete rectangle. Compare their useful source
    // texels exactly: redraws of an unchanged scene can reuse the convolution, while even a
    // one-byte edit invalidates it. Other drawing states keep the general raster path.
    mtd rasterizeCachedBackdrop(batch: *RasterBatch, bounds: PixelBounds)->bool
    {
        if .program != CpuProgram_Backdrop or .backdropPass.mode >= 2 or batch.count != 6 do
            return false
        if .blendingMode != .Copy or
           not .colorMask.r or
           not .colorMask.g or
           not .colorMask.b or
           not .colorMask.a do
            return false
        if .stencilOn or .stencilWrite or .scissorOn or .overlapMode or .alphaResolve do
            return false

        let source = batch.paintImage
        let target = batch.image
        let width  = .backdropPass.width
        let height = .backdropPass.height
        if not source or
           not target or
           source == target or
           source.pixelFormat != .BGRA8 or
           target.pixelFormat != .BGRA8 or
           not CpuBackdropCache.acceptsSize(width, height) do
            return false
        if source.width < width or
           source.height < height or
           target.width < width or
           target.height < height do
            return false
        if .paint.type != .Texture or .paint.uvMode != .Fill do
            return false

        let topLeft     = Vector2{.paint.boundRect.x, .paint.boundRect.y}
        let topRight    = Vector2{.paint.boundRect.z, .paint.boundRect.y}
        let bottomRight = Vector2{.paint.boundRect.z, .paint.boundRect.w}
        let bottomLeft  = Vector2{.paint.boundRect.x, .paint.boundRect.w}
        let transform   = &batch.transform
        if transform.m12 != 0 or
           transform.m21 != 0 or
           transform.m11 <= 0 or
           transform.m22 <= 0 or
           transform.transformPoint(topLeft) != Vector2.Zero or
           transform.transformPoint(bottomRight) != Vector2{width, height} do
            return false
        let vertices = batch.painter!.vertexBuffer.storage() + batch.start
        if vertices[0].pos != topLeft or
           vertices[1].pos != topRight or
           vertices[2].pos != bottomRight or
           vertices[3].pos != topLeft or
           vertices[4].pos != bottomRight or
           vertices[5].pos != bottomLeft do
            return false
        for vertex in Swag.makeSlice(vertices, 6)
        {
            if vertex.color != Argb.White or vertex.cov != 1 do
                return false
        }

        // The sampler clamps to the declared useful extent. Mapping and physical texture
        // dimensions also belong in the key because they affect floating-point coordinates.
        let cache = &.backdropCache[.backdropPass.mode]
        cache.used = true
        let key = CpuBackdropCacheKey{.backdropPass.radius, .contentScale, source.width, source.height,
                                      target.width, target.height, .paint.textureRect, .paint.boundRect, batch.transform}
        let rowBytes = cast(u64, width) * 4
        var same     = cache.valid and
                       cache.source.width == width and
                       cache.source.height == height and
                       Memory.compare(&cache.key, &key, #sizeof(CpuBackdropCacheKey)) == 0
        if same
        {
            for y in height
            {
                let input    = source.pixels.storage() + cast(u64, source.height - y - 1) * cast(u64, source.rowStride)
                let previous = cache.source.pixels.storage() + cast(u64, height - y - 1) * rowBytes
                if Memory.compare(input, previous, rowBytes) != 0
                {
                    same = false
                    break
                }
            }
        }

        if same
        {
            for y in height
            {
                let input  = cache.result.pixels.storage() + cast(u64, height - y - 1) * rowBytes
                let output = target.pixels.storage() + cast(u64, target.height - y - 1) * cast(u64, target.rowStride)
                Memory.copy(output, input, rowBytes)
            }

            cache.hits += 1
            return true
        }

        cache.valid = false
        if cache.source.width != width or cache.source.height != height
        {
            cache.source = Image.create(width, height, .BGRA8)
            cache.result = Image.create(width, height, .BGRA8)
        }

        for y in height
        {
            let input  = source.pixels.storage() + cast(u64, source.height - y - 1) * cast(u64, source.rowStride)
            let output = cache.source.pixels.storage() + cast(u64, height - y - 1) * rowBytes
            Memory.copy(output, input, rowBytes)
        }

        // A Gaussian repeatedly fetches the same texels across neighbouring output pixels.
        // Convert each source texel once, with the exact division used by the general sampler.
        // Keep tiny draws allocation-free and bound transient storage independently of the cache.
        var samples: Array'Math.Simd.F32x4
        var prepared   = batch[]
        let pixelCount = cast(u64, width) * cast(u64, height)
        if pixelCount >= 4096 and pixelCount <= CpuBackdropCache.MaxBytes / #sizeof(Math.Simd.F32x4)
        {
            samples.resize(pixelCount)
            for y in height
            {
                let row = samples.storage() + cast(u64, y) * cast(u64, width)
                for x in width do
                    row[x] = normalizedChannels(fetchBgra8(source, x, y))
            }

            prepared.backdropPixels = samples.storage()
        }

        .rasterizeRange(&prepared, bounds)
        for y in height
        {
            let input  = target.pixels.storage() + cast(u64, target.height - y - 1) * cast(u64, target.rowStride)
            let output = cache.result.pixels.storage() + cast(u64, height - y - 1) * rowBytes
            Memory.copy(output, input, rowBytes)
        }

        cache.key   = key
        cache.valid = true
        return true
    }

    // Returns the region the scissor allows, as the bounds an unrestricted pass covers.
    mtd clipBounds(image: *Image)->PixelBounds
    {
        if not .scissorOn do
            return PixelBounds{0, 0, image.width - 1, image.height - 1}

        var result: #returntype
        result.minX = Math.clamp(cast(s32, .scissorRect.x), 0, image.width - 1)
        result.minY = Math.clamp(cast(s32, .scissorRect.y), 0, image.height - 1)
        result.maxX = Math.clamp(cast(s32, .scissorRect.right()) - 1, 0, image.width - 1)
        result.maxY = Math.clamp(cast(s32, .scissorRect.bottom()) - 1, 0, image.height - 1)
        return result
    }

    // Zeroes the destination alpha over `bounds`, the scratch channel of the overlap resolve.
    //
    // OpenGL does this with an alpha-masked `glClear` bounded by the scissor, which it narrows to
    // the same range for the same reason: the scratch only has to start from zero where the batch
    // can write, and zeroing the whole clipping rectangle instead costs its area once per batch
    // and destroys alpha the batch never touches. The two backends narrow identically, so the
    // alpha they leave behind stays comparable.
    //
    // The alpha byte is written in place: routing a single-channel reset through a `Color` round
    // trip made this the dominant cost of rasterizing a vector atlas.
    mtd clearAlpha(image: *Image, bounds: PixelBounds)
    {
        if not image.pixelFormat.hasAlpha() do
            return

        let minX = Math.clamp(bounds.minX, 0, image.width)
        let minY = Math.clamp(bounds.minY, 0, image.height)
        let maxX = Math.clamp(bounds.maxX + 1, 0, image.width)
        let maxY = Math.clamp(bounds.maxY + 1, 0, image.height)

        // Every format carrying alpha stores it in the fourth byte, and rows are stored bottom-up.
        let pixels = image.pixels.storage()
        let stride = cast(u64, image.bytesPerPixel)
        let zero   = Math.Simd.splat(0'u8)
        for var y = minY; y < maxY; y += 1
        {
            let row    = pixels + cast(u64, ((image.height - y - 1) * image.rowStride + minX * image.bytesPerPixel))
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
        if not image do
            return

        let minX = .scissorOn ? Math.clamp(cast(s32, .scissorRect.x), 0, image.width) : 0
        let minY = .scissorOn ? Math.clamp(cast(s32, .scissorRect.y), 0, image.height) : 0
        let maxX = .scissorOn ? Math.clamp(cast(s32, .scissorRect.right()), 0, image.width) : image.width
        let maxY = .scissorOn ? Math.clamp(cast(s32, .scissorRect.bottom()), 0, image.height) : image.height
        if minX >= maxX or minY >= maxY do
            return

        let runWidth = cast(u64, (maxX - minX))
        if minX == 0 and minY == 0 and maxX == image.width and maxY == image.height
        {
            .clearStencil()
        }
        else
        {
            // A scissored clear can leave part of the dirty rectangle intact.
            let stencil = .currentStencil()
            let cleared = PixelBounds{Math.max(minX, stencil.dirty.minX), Math.max(minY, stencil.dirty.minY),
                                      Math.min(maxX - 1, stencil.dirty.maxX), Math.min(maxY - 1, stencil.dirty.maxY)}
            if not cleared.isEmpty() do
                clearScratchRows(stencil.pixels.storage(), image.width, cleared)
        }

        // The masked general write reduces to raw byte stores for the BGRA8 targets every frame
        // clears: all channels under a forced or full mask, or the three color bytes under the
        // default mask, whose disabled alpha simply keeps the fourth byte in place.
        let writeAll = forceColorMask or (.colorMask.r and .colorMask.g and .colorMask.b and .colorMask.a)
        let writeRgb = not writeAll and .colorMask.r and .colorMask.g and .colorMask.b and not .colorMask.a
        if image.pixelFormat == .BGRA8 and (writeAll or writeRgb)
        {
            let pixels = image.pixels.storage()

            // Transparent target clears are the common layer setup. Clear each contiguous
            // BGRA row in one operation instead of issuing four stores per pixel.
            if writeAll and not color.a and not color.r and not color.g and not color.b
            {
                let byteCount = runWidth * 4
                for var y = minY; y < maxY; y += 1
                {
                    let row = pixels + cast(u64, ((image.height - y - 1) * image.rowStride + minX * 4))
                    Memory.clear(row, byteCount)
                }

                return
            }

            let fill = cast(Math.Simd.U8x16, [color.b, color.g, color.r, color.a,
                                              color.b, color.g, color.r, color.a,
                                              color.b, color.g, color.r, color.a,
                                              color.b, color.g, color.r, color.a])
            for var y = minY; y < maxY; y += 1
            {
                let row       = pixels + cast(u64, ((image.height - y - 1) * image.rowStride + minX * 4))
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
                if not .colorMask.r do
                    out.r = old.r
                if not .colorMask.g do
                    out.g = old.g
                if not .colorMask.b do
                    out.b = old.b
                if not .colorMask.a do
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
        .stackStencilOn.clear()
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
        if not image do
            return

        // The replay rebuilds the whole alpha plane rather than one batch's scratch, so it starts
        // from the whole clipped region and not from any batch's bounds.
        .clearAlpha(image, .clipBounds(image))

        // The clipping region is replayed with the geometry, so the alpha plane is carved by the
        // same clips the color plane was. That only reproduces the color pass from a region the
        // recording started with: the target was cleared right after it was bound, and a clear
        // empties the stencil, so the replay starts from an empty one too.
        .clearStencil()
        .stencilOn    = false
        .stencilWrite = false
        .stencilMode  = .Set

        .alphaResolve = true
        for var i = first; i < last; i += 1
        {
            let replay = &painter.commandBuffer[i]
            switch replay.op
            {
            case .Transform, .StartFont, .StartMsdfFont, .EndFont, .ResetTexture0, .BindTexture0,
                 .ResetTextureFont, .BindTextureFont, .SetFontEffect, .StartClippingRegion,
                 .SetClippingRegionMode, .EndClippingRegion, .ResetClippingRegion, .DrawTriangles:
                .executeCommand(painter, replay, i)

            default: break
            }
        }

        .alphaResolve = false
    }

    mtd executeCommand(painter: *Painter, cmd: const *Command, cmdIdx: u64)
    {
        switch cmd.op
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

            // The previous mask can extend past the current scissor.
            .clearStencil()
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
            .drawTriangles(painter, &cmd.drawTriangles)

        case .DrawScanFill:
            .drawScanFill(painter, &cmd.scanFill)

        case .DrawScanClip:
            .drawScanClip(painter, cmd.scanClip.first, cmd.scanClip.end)

        case .StartFont:
            .program = CpuProgram_Font

        case .StartMsdfFont:
            .program = CpuProgram_Msdf

        case .EndFont:
            .program = CpuProgram_Default

        case .BindTextureFont:
            .font = cmd.textureFont.font
            .fontAtlasIndex = cmd.textureFont.atlasIndex

        case .ResetTextureFont:
            .font = null
            .fontAtlasIndex = -1

        case .UpdateFont:

            // Glyph pixels already live in CPU memory; no upload is required.
            break

        case .ResetTexture0:
            .paintOn = false

        case .BindTexture0:
            .paint = cmd.texture0
            if cmd.texture0.gradientStopCount do
                .gradientStops = Swag.makeSlice(painter.gradientStops.buffer + cmd.texture0.gradientStopStart, cmd.texture0.gradientStopCount)
            else do
                .gradientStops = null
            .paintOn = true

        case .ReleaseTexture:
            var texture = cmd.texture0.texture
            me.removeTextureImpl(&texture)

        case .BindRenderTarget:
            .bindRenderTargetImpl(cmd.renderTgt.tgt)
            let target = unwrap .curRT
            target.paintAlpha    = cmd.renderTgt.paintAlpha
            target.paintAlphaIdx = cmdIdx

            // A layer has a space of its own: the region in force around it cuts the layer when
            // it is drawn, not the marks inside it.
            .stackStencilOn.add(.stencilOn)
            .stencilOn    = false
            .stencilWrite = false

        case .UnbindRenderTarget:
            let target = unwrap .curRT
            if target.paintAlpha do
                .replayTargetAlpha(painter, target.paintAlphaIdx, cmdIdx)
            .unbindRenderTargetImpl()
            if .stackStencilOn.count do
                .stencilOn = .stackStencilOn.popBack()

        case .ReleaseRenderTarget:
            .releaseRenderTargetImpl(cmd.renderTgt.tgt)

        case .CaptureBackdrop:
            let source = unwrap .currentImage()
            let target = unwrap .findTexture(cmd.backdropCapture.tgt.colorBuffer.handle)
            let rect   = cmd.backdropCapture.rect
            for y in cast(s32, rect.height)
            {
                for x in cast(s32, rect.width) do
                    writePixel(&target.image, x, y, readPixel(source, x + cast(s32, rect.x), y + cast(s32, rect.y)))
            }

        case .SetBackdropShader:
            .program      = CpuProgram_Backdrop
            .backdropPass = cmd.backdropPass

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
            if not shader do
                .program = CpuProgram_Default
            else do
                Swag.assert(false, "RenderCpu does not support custom shaders")

        case .SetShaderParam:
            Swag.assert(false, "RenderCpu does not support custom shader parameters")

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
        .generation.release()
        for rt in .stackReleasedRT do
            Memory.delete(rt)
    }

    // Resets all renderer-owned resources and returns to an empty deterministic state.
    //
    // Every outstanding texture and render-target handle from this renderer becomes invalid.
    mtd reset()
    {
        Swag.drop(me, 1)
        Swag.init(me, 1)
    }

    // Starts a CPU frame with the requested positive BGRA surface dimensions.
    //
    // Reusing the same dimensions preserves the surface pixels until they are cleared or drawn
    // over. No native context is created.
    mtd begin(width, height: s32)
    {
        Swag.assert(width > 0 and height > 0, "RenderCpu.begin needs positive width and height")
        .ensureSurface(width, height)
        .resetTransformImpl()
    }

    // Finishes a CPU frame.
    //
    // CPU rendering is synchronous, so this operation does not present or wait for work.
    internal mtd endImpl()
    {
        for &cache in .backdropCache
        {
            if cache.used
            {
                cache.used = false
            }
            else
            {
                Swag.drop(cache, 1)
                Swag.init(cache, 1)
            }
        }

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
    }

    // Returns an owned copy of the current surface pixels.
    mtd surfaceImage()->Image
    {
        Swag.assert(.surface.isValid(), "surfaceImage needs an active CPU surface")
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
            return {width: image.width, height: image.height}
        return {width: 0, height: 0}
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
    // The painter must have been ended and must remain unchanged until this call returns. A
    // stream that refers to a retired render target fails before changing renderer state.
    internal mtd drawImpl(painter: *Painter) fail
    {
        var nextCommand: u64
        defer #fail
        {
            for cmd in painter.commandBuffer.toSlice()[nextCommand until painter.commandBuffer.count]
            {
                switch cmd.op
                {
                case .ReleaseRenderTarget:
                    .releaseRenderTargetImpl(cmd.renderTgt.tgt)

                case .ReleaseTexture:
                    var texture = cmd.texture0.texture
                    .removeTextureImpl(&texture)

                default:
                    break
                }
            }

            painter.markSubmitted()
        }

        for cmd in painter.commandBuffer
        {
            switch cmd.op
            {
            case .BindRenderTarget:
                if not cmd.renderTgt.tgt.colorBuffer.isValid() do
                    fail RenderResourceError{"CPU renderer cannot bind a render target from an earlier resource generation"}

            case .CaptureBackdrop:
                if not cmd.backdropCapture.tgt.colorBuffer.isValid() do
                    fail RenderResourceError{"CPU renderer cannot capture into a target from an earlier resource generation"}

            default:
                break
            }
        }

        .resetDrawState()
        .contentScale = painter.contentScale()
        for &cmd, idx in painter.commandBuffer
        {
            .executeCommand(painter, cmd, cast(u64, idx))
            nextCommand = cast(u64, idx) + 1
        }
    }

    // Shares geometry and coverage with a second matte during an SVG tile submission.
    // The paired targets are distinct BGRA buffers of identical dimensions.
    internal mtd beginSvgMattes(white: Texture)
    {
        let image = &.findTexture(white.handle)!.image
        let bytes = image.pixels.storage()
        Memory.set(bytes, 255, image.byteCount)
        .whiteMatte = bytes
    }

    internal mtd endSvgMattes()
    {
        .whiteMatte = null
    }

    // Binds an off-screen target for following direct operations or painter submission.
    //
    // The target is borrowed until [[Pixel.RenderCpu.unbindRenderTarget]] restores its parent.
    internal mtd bindRenderTargetImpl(rt: *RenderTarget)
    {
        Swag.assert(rt != null, "bindRenderTarget needs a target")
        if not rt.colorBuffer.isValid() do
            return
        if .curRT do
            .stackRT.add(.curRT)
        .curRT = rt
        .curRT.paintAlpha = false
        .ensureStencil(rt.colorBuffer.width, rt.colorBuffer.height)
    }

    // Borrows the CPU target image until the next change to texture storage.
    internal mtd renderTargetImage(rt: const *RenderTarget)->const *Image?
    {
        let texture = .findTexture(rt.colorBuffer.handle)
        return texture ? &texture.image : null
    }

    // Resolves the whole CPU matte with the same sample order as the painter resolve.
    internal mtd resolveSvgTarget(source, target: const *RenderTarget, factor: s32)
    {
        let sourceTexture = unwrap .findTexture(source.colorBuffer.handle)
        let targetTexture = unwrap .findTexture(target.colorBuffer.handle)
        resolveTexture(&sourceTexture.image, &targetTexture.image, factor)
    }

    // Reads a rectangle of an off-screen target into a new image.
    //
    // The rectangle is clamped to the target and must retain at least one pixel.
    internal mtd readRenderTargetImpl(rt: const *RenderTarget, x, y, width, height: s32)->Image
    {
        Swag.assert(rt != null and width > 0 and height > 0, "readRenderTarget needs a target and positive dimensions")
        if not rt.colorBuffer.isValid() do
            return {}
        let storage = .findTexture(rt.colorBuffer.handle)
        Swag.assert(storage != null, "render target is not owned by this renderer")
        let source = storage

        // Cropping a copy allocates and walks the whole target a second time, and the read that
        // matters — a page, a thumbnail, a captured frame — asks for the whole of it.
        if x == 0 and y == 0 and width == source.image.width and height == source.image.height
        {
            var whole: #returntype = source.image
            return whole
        }

        var result: #returntype = source.image.cropped(x, y, width, height)
        return result
    }

    // Reads the active target into a new image, then restores the previous target.
    internal mtd unbindRenderTargetToImageImpl(x, y, width, height: s32)->Image
    {
        let rt     = unwrap .curRT
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
        Swag.assert(width > 0 and height > 0, "createRenderTarget needs positive width and height")
        if not .ensureGeneration() do
            return {}

        let targetHandle = cast(RenderTargetHandle, .nextHandle)
        .nextHandle += 1
        let textureHandle = cast(TextureHandle, .nextHandle)
        .nextHandle += 1

        var result: #returntype
        result.attach(targetHandle, textureHandle, .BGRA8, width, height, .generation)

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
        if rt.handle == InvalidRenderTargetHandle do
            return
        if not rt.colorBuffer.isValid()
        {
            rt.clear()
            return
        }

        .removeTextureStorage(rt.colorBuffer.handle)
        rt.clear()
    }

    // Loads an image file and registers an owned CPU texture.
    internal mtd addImageImpl(fullName: string)->Texture fail
    {
        let image = try Image.load(fullName)
        return .addImageImpl(&image)
    }

    // Registers a planar picture.
    //
    // This backend has no shaders, so it converts once here rather than once per sample and holds
    // an ordinary packed surface. The descriptor still says the picture is planar, which is what
    // the caller handed over.
    internal mtd addImageImpl(view: const *YuvPlanarView)->Texture
    {
        if not view.isValidLayout() or not .ensureGeneration() do
            return {}

        var image = Image.create(view.width, view.height, .RGB8)
        view.convertToRgb(&image)

        var result: #returntype
        result.attach(cast(TextureHandle, .nextHandle), view.chromaShift == 0 ? .Yuv444 : .Yuv420, view.width, view.height, .generation)
        .nextHandle += 1

        var storage: CpuTexture
        storage.handle = result.handle
        storage.image  = #move image
        .copyPlanar(view, &storage.planar)
        .textures.add(#move storage)
        return result
    }

    // Converts a planar picture into the surface that holds it.
    internal mtd updatePlanarImpl(texture: Texture, view: const *YuvPlanarView)->bool
    {
        if not view.isValidLayout() or
           not texture.isValid() or
           view.width != texture.width or
           view.height != texture.height do
            return false
        if (texture.pixelFormat == .Yuv420 and view.chromaShift != 1) or
           (texture.pixelFormat == .Yuv444 and view.chromaShift != 0) or
           (texture.pixelFormat != .Yuv420 and texture.pixelFormat != .Yuv444) do
            return false
        let storage = .findTexture(texture.handle)
        Swag.assert(storage != null, "texture is not owned by this renderer")
        view.convertToRgb(&storage.image)
        .copyPlanar(view, &storage.planar)
        return true
    }

    // Reuses the renderer-owned plane buffers as decoded video frames replace each other.
    private mtd copyPlanar(view: const *YuvPlanarView, target: *CpuPlanarTexture)
    {
        target.width        = view.width
        target.height       = view.height
        target.chromaWidth  = view.chromaWidth()
        target.chromaHeight = view.chromaHeight()
        target.matrix       = view.matrix
        target.studioRange  = view.studioRange
        target.luma.resize(cast(u64, target.width * target.height))
        target.chromaB.resize(cast(u64, target.chromaWidth * target.chromaHeight))
        target.chromaR.resize(cast(u64, target.chromaWidth * target.chromaHeight))
        for y in target.height
        {
            Memory.copy(target.luma.storage() + cast(u64, (y * target.width)),
                        view.luma + cast(u64, y) * view.lumaStride,
                        cast(u64, target.width))
        }

        for y in target.chromaHeight
        {
            Memory.copy(target.chromaB.storage() + cast(u64, (y * target.chromaWidth)),
                        view.chromaB + cast(u64, y) * view.chromaStride,
                        cast(u64, target.chromaWidth))
            Memory.copy(target.chromaR.storage() + cast(u64, (y * target.chromaWidth)),
                        view.chromaR + cast(u64, y) * view.chromaStride,
                        cast(u64, target.chromaWidth))
        }
    }

    // Copies an image into a renderer-owned CPU texture.
    internal mtd addImageImpl(image: const *Image)->Texture
    {
        if not image.isValid() or not .ensureGeneration() do
            return {}

        var result: #returntype
        result.attach(cast(TextureHandle, .nextHandle), image.pixelFormat, image.width, image.height, .generation)
        .nextHandle += 1

        var storage: CpuTexture
        storage.handle = result.handle
        if image.alphaMode == .Premultiplied do
            storage.image = image.convertedAlphaTo(.Straight)
        else do
            storage.image = image[]
        .textures.add(#move storage)
        return result
    }

    // Replaces all bytes of a renderer-owned texture.
    //
    // `pixels` must address at least [[Pixel.Texture.byteCount]] readable bytes.
    internal mtd updateTextureImpl(texture: Texture, pixels: const *u8)->bool
    {
        if not texture.isValid() do
            return false
        let storage = .findTexture(texture.handle)
        Swag.assert(storage != null, "texture is not owned by this renderer")
        let target = storage

        if texture.pixelFormat == .Yuv420 or texture.pixelFormat == .Yuv444
        {
            let shift        = texture.pixelFormat == .Yuv420 ? 1 : 0
            let divisor      = 1's32 << shift
            let chromaWidth  = texture.width / divisor + (texture.width % divisor != 0 ? 1 : 0)
            let chromaHeight = texture.height / divisor + (texture.height % divisor != 0 ? 1 : 0)
            let lumaSize     = cast(u64, texture.width) * cast(u64, texture.height)
            let chromaSize   = cast(u64, chromaWidth) * cast(u64, chromaHeight)
            let source       = cast(const [*] u8, pixels)
            let planar       = &target.planar
            let view         = YuvPlanarView{
                luma: source,
                chromaB: source + lumaSize,
                chromaR: source + lumaSize + chromaSize,
                lumaStride: cast(u64, texture.width),
                chromaStride: cast(u64, chromaWidth),
                width: texture.width,
                height: texture.height,
                chromaShift: shift,
                matrix: planar.matrix,
                studioRange: planar.studioRange}
            view.convertToRgb(&target.image)
            .copyPlanar(&view, &target.planar)
            return true
        }

        Memory.copy(target.image.pixels.storage(), pixels, target.image.byteCount)
        return true
    }

    // Reads a renderer-owned texture into the requested tightly packed format.
    internal mtd readTexturePixelsImpl(texture: Texture, pixelFormat: PixelFormat)->Array'u8
    {
        var result: #returntype
        if not texture.isValid() do
            return result
        let storage = .findTexture(texture.handle)
        Swag.assert(storage != null, "texture is not owned by this renderer")
        let source = storage
        let image  = source.image.convertedTo(pixelFormat)
        result = image.pixels
        return result
    }

    // Releases a renderer-owned texture and invalidates its descriptor.
    internal mtd removeTextureImpl(texture: *Texture)
    {
        if not texture.isValid()
        {
            texture.clear()
            return
        }

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
        Swag.assert(width > 0 and height > 0, "acquireRenderTarget needs positive width and height")
        let bucketWidth  = RenderTarget.pooledExtent(width)
        let bucketHeight = RenderTarget.pooledExtent(height)
        if not bucketWidth or not bucketHeight
        {
            let result = Memory.new'RenderTarget()
            result.clear()
            return result
        }

        // Match RenderOgl's small buckets and let larger, unused targets expire.
        for rt, idx in .stackReleasedRT
        {
            let candidate = unwrap rt
            if candidate.colorBuffer.width == bucketWidth and candidate.colorBuffer.height == bucketHeight
            {
                .stackReleasedRT.removeAt(idx)
                return candidate
            }
        }

        let result = Memory.new'RenderTarget()
        result[] = .createRenderTargetImpl(cast(s32, bucketWidth), cast(s32, bucketHeight))
        return result
    }

    // Returns a pooled target to this renderer; `null` is ignored.
    //
    // `target` must be a currently unbound pointer returned by
    // [[Pixel.RenderCpu.acquireRenderTarget]]. Ownership transfers back to the renderer.
    internal mtd releaseRenderTargetImpl(target: *RenderTarget?)
    {
        if not target do
            return
        if not target.colorBuffer.isValid()
        {
            target.clear()
            Memory.delete(target)
            return
        }

        target.poolUsed = true
        .stackReleasedRT.add(target)
    }
}
