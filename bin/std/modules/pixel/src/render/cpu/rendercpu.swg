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
    fonts: FontCache

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
        contentScale:   f32        = 1                     // Device pixels per unit of the painter stream being drawn.

        scissorOn:   bool
        scissorRect: Math.Rectangle

        blendingMode: BlendingMode = Alpha
        colorMask:    ColorMask    = {true, true, true, false}

        paintCommand: Command = undefined
        paintOn:      bool
        program:      u8

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
    handle:  TextureHandle
    image:   Image
    stencil: Array'u8
}

private
{
    const CpuProgram_Default: u8 = 0
    const CpuProgram_Simple:  u8 = 1
    const CpuProgram_Font:    u8 = 2
    const CpuProgram_Msdf:    u8 = 3
    const CpuProgram_Blur:    u8 = 4
    const CpuProgram_Resolve: u8 = 5
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
        for texture, [idx] in .textures where texture.handle == handle
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

    func insideEdge(value: f32, topLeft: bool)->bool
    {
        return value > 0 or (value == 0 and topLeft)
    }

    func lerpColor(c0, c1: Color, t: f32)->Color
    {
        let u = Math.saturate(t)
        return Color.fromArgbF32((cast(f32) c0.a + (cast(f32) c1.a - c0.a) * u) / 255.0,
                                 (cast(f32) c0.r + (cast(f32) c1.r - c0.r) * u) / 255.0,
                                 (cast(f32) c0.g + (cast(f32) c1.g - c0.g) * u) / 255.0,
                                 (cast(f32) c0.b + (cast(f32) c1.b - c0.b) * u) / 255.0)
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

    func writePixel(image: *Image, x, y: s32, color: Color)
    {
        let storageY = image.height - y - 1
        let pixel    = image.pixels.buffer! + cast(u64) (storageY * image.rowStride + x * image.bytesPerPixel)

        switch #complete image.pixelFormat
        {
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

    func blendChannel(src, dst, srcAlpha: f32, mode: BlendingMode)->f32
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
        }

        return src
    }

    mtd blendPixel(image: *Image, x, y: s32, src: Color)
    {
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

        let sa  = cast(f32) src.a / 255.0
        var out = Color.fromArgbF32(blendChannel(cast(f32) src.a / 255.0, cast(f32) dst.a / 255.0, sa, .blendingMode),
                                    blendChannel(cast(f32) src.r / 255.0, cast(f32) dst.r / 255.0, sa, .blendingMode),
                                    blendChannel(cast(f32) src.g / 255.0, cast(f32) dst.g / 255.0, sa, .blendingMode),
                                    blendChannel(cast(f32) src.b / 255.0, cast(f32) dst.b / 255.0, sa, .blendingMode))

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

        let c00 = readPixel(image, coord(x0, image.width, repeat), coord(y0, image.height, repeat))
        let c10 = readPixel(image, coord(x0 + 1, image.width, repeat), coord(y0, image.height, repeat))
        let c01 = readPixel(image, coord(x0, image.width, repeat), coord(y0 + 1, image.height, repeat))
        let c11 = readPixel(image, coord(x0 + 1, image.width, repeat), coord(y0 + 1, image.height, repeat))
        return lerpColor(lerpColor(c00, c10, tx), lerpColor(c01, c11, tx), ty)
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

        let c00 = readPixel(image, x0, y0)
        let c10 = readPixel(image, x1, y0)
        let c01 = readPixel(image, x0, y1)
        let c11 = readPixel(image, x1, y1)
        return lerpColor(lerpColor(c00, c10, fx), lerpColor(c01, c11, fx), fy)
    }

    mtd sampleBlur(image: *Image, u, v: f32)->Color
    {
        let radius = Math.max(.blurRadius, 0.0)
        if radius <= 0.000001 do
            return sampleLinear(image, u, v, false)

        let rr     = radius * radius
        let w0     = 0.5135 / Math.pow(radius, 0.96)
        var a, r, g, b: f32
        var offset = -radius
        while offset <= radius
        {
            let su     = .blurAxis == 0 ? u + offset / image.width : u
            let sv     = .blurAxis == 0 ? v : v + offset / image.height
            let sample = sampleLinear(image, su, sv, false)
            let weight = w0 * Math.exp((-offset * offset) / (2.0 * rr))
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

        if t <= p.gradientStops[0].offset do
            return p.gradientStops[0].color
        for var i: u8 = 1; i < p.gradientStopCount; i += 1
        {
            if t > p.gradientStops[i].offset do
                continue
            let lo = p.gradientStops[i - 1].offset
            let hi = p.gradientStops[i].offset
            let u  = hi == lo ? 1.0 : Math.saturate((t - lo) / (hi - lo))
            return lerpColor(p.gradientStops[i - 1].color, p.gradientStops[i].color, u)
        }

        return p.gradientStops[p.gradientStopCount - 1].color
    }

    mtd samplePaint(paintPos: Vector2)->Color
    {
        if !.paintOn do
            return Color.fromArgb(Argb.White)

        let p = &.paintCommand.texture0
        switch p.type
        {
        case .SolidColor:
            return Color.fromArgb(Argb.White)

        case .Texture:
            let storage = .findTexture(p.texture.handle)
            if !storage do
                return Color.fromArgb(Argb.Zero)

            if p.uvMode == .FillSubRect and .program != CpuProgram_Blur and .program != CpuProgram_Resolve do
                return sampleSubRect(&storage.image, paintPos, &.paintCommand, .contentScale)

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
                return .sampleBlur(&storage.image, u, v)
            if .program == CpuProgram_Resolve do
                return .sampleResolve(&storage.image, u, v)

            if p.interpolationMode == .Linear do
                return sampleLinear(&storage.image, u, v, repeat)
            return sampleNearest(&storage.image, u, v, repeat)

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

        let px  = Math.saturate(uv.x) * width - 0.5
        let py  = Math.saturate(uv.y) * height - 0.5
        let x0  = cast(s32) Math.floor(px)
        let y0  = cast(s32) Math.floor(py)
        let x1  = Math.min(x0 + 1, width - 1)
        let y1  = Math.min(y0 + 1, height - 1)
        let tx  = px - Math.floor(px)
        let ty  = py - Math.floor(py)
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

    mtd shadeMsdf(faceColor: Color, uv, uvDx, uvDy: Vector2)->Color
    {
        let atlas = .fontAtlas()
        if !atlas do
            return Color.fromArgb(Argb.Zero)

        let safeAtlas     = atlas!
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
            var alpha = msdfCoverage(safeAtlas, uv + Vector2{-off.x, -off.y}, screenPxRange, 0.5, 1.0)
            alpha += msdfCoverage(safeAtlas, uv + Vector2{off.x, -off.y}, screenPxRange, 0.5, 1.0)
            alpha += msdfCoverage(safeAtlas, uv + Vector2{-off.x, off.y}, screenPxRange, 0.5, 1.0)
            alpha += msdfCoverage(safeAtlas, uv + Vector2{off.x, off.y}, screenPxRange, 0.5, 1.0)
            alpha = Math.pow(alpha * 0.25, FontGamma)
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

    mtd shade(paintPos, fontUv, fontUvDx, fontUvDy: Vector2, vertexColor: Color, coverage: f32)->Color
    {
        var result = Color.multiply(vertexColor, .samplePaint(paintPos))
        if .program == CpuProgram_Font
        {
            let atlas = .fontAtlas()
            if !atlas do
                return Color.fromArgb(Argb.Zero)
            let sample = sampleFontAtlas(atlas!, fontUv, false)
            result.a = cast(u8) Math.clamp(Math.round(cast(f32) result.a * Math.pow(sample.x, FontGamma)), 0.0, 255.0)
        }
        elif .program == CpuProgram_Msdf
        {
            result = .shadeMsdf(result, fontUv, fontUvDx, fontUvDy)
        }
        elif .program == CpuProgram_Default
        {
            result.a = cast(u8) Math.clamp(Math.round(cast(f32) result.a * coverage), 0.0, 255.0)
        }

        return result
    }

    mtd drawTriangle(image: *Image, input0, input1, input2: VertexLayout)
    {
        var transform = .worldTransform
        transform.multiply(.modelTransform)

        // Map the logical painter stream to device pixels last, so positions and
        // translations scale alike (see RenderOgl.buildModelMatrix).
        if .contentScale != 1 do
            transform.multiply(Transform2.createScale(.contentScale, .contentScale, 0, 0))

        var v0 = input0
        var v1 = input1
        var v2 = input2
        var p0 = transform.transformPoint(v0.pos)
        var p1 = transform.transformPoint(v1.pos)
        var p2 = transform.transformPoint(v2.pos)

        var area = edge(p0, p1, p2)
        if area == 0 do
            return
        if area < 0
        {
            swap(&v1, &v2)
            swap(&p1, &p2)
            area = -area
        }

        let minX = Math.clamp(cast(s32) Math.floor(Math.min(p0.x, Math.min(p1.x, p2.x))), 0, image.width - 1)
        let minY = Math.clamp(cast(s32) Math.floor(Math.min(p0.y, Math.min(p1.y, p2.y))), 0, image.height - 1)
        let maxX = Math.clamp(cast(s32) Math.ceil(Math.max(p0.x, Math.max(p1.x, p2.x))) - 1, 0, image.width - 1)
        let maxY = Math.clamp(cast(s32) Math.ceil(Math.max(p0.y, Math.max(p1.y, p2.y))) - 1, 0, image.height - 1)
        if minX > maxX or minY > maxY do
            return

        let edge0TopLeft = isTopLeft(p1, p2)
        let edge1TopLeft = isTopLeft(p2, p0)
        let edge2TopLeft = isTopLeft(p0, p1)
        let invArea      = 1.0 / area

        let dcDx     = (v0.cov * (p1.y - p2.y) + v1.cov * (p2.y - p0.y) + v2.cov * (p0.y - p1.y)) * invArea
        let dcDy     = (v0.cov * (p2.x - p1.x) + v1.cov * (p0.x - p2.x) + v2.cov * (p1.x - p0.x)) * invArea
        let covWidth = Math.max(Math.abs(dcDx) + Math.abs(dcDy), 0.00001)
        let fontUvDx = Vector2{(v0.uv.x * (p1.y - p2.y) + v1.uv.x * (p2.y - p0.y) + v2.uv.x * (p0.y - p1.y)) * invArea,
                               (v0.uv.y * (p1.y - p2.y) + v1.uv.y * (p2.y - p0.y) + v2.uv.y * (p0.y - p1.y)) * invArea}
        let fontUvDy = Vector2{(v0.uv.x * (p2.x - p1.x) + v1.uv.x * (p0.x - p2.x) + v2.uv.x * (p1.x - p0.x)) * invArea,
                               (v0.uv.y * (p2.x - p1.x) + v1.uv.y * (p0.x - p2.x) + v2.uv.y * (p1.x - p0.x)) * invArea}

        let c0 = Color.fromArgb(v0.color)
        let c1 = Color.fromArgb(v1.color)
        let c2 = Color.fromArgb(v2.color)

        let stencil = .currentStencil()
        for var y = minY; y <= maxY; y += 1
        {
            if .scissorOn and (y < .scissorRect.y or y >= .scissorRect.bottom()) do
                continue

            for var x = minX; x <= maxX; x += 1
            {
                if .scissorOn and (x < .scissorRect.x or x >= .scissorRect.right()) do
                    continue

                let sample = Vector2{cast(f32) x + 0.5, cast(f32) y + 0.5}
                let e0     = edge(p1, p2, sample)
                let e1     = edge(p2, p0, sample)
                let e2     = edge(p0, p1, sample)
                if !insideEdge(e0, edge0TopLeft) or !insideEdge(e1, edge1TopLeft) or !insideEdge(e2, edge2TopLeft) do
                    continue

                let stencilIdx = cast(u64) y * cast(u64) image.width + cast(u64) x
                if .stencilOn and !.stencilWrite and (dref stencil)[stencilIdx] != 1 do
                    continue
                if .stencilWrite
                {
                    (dref stencil)[stencilIdx] = .stencilMode == .Set ? 1 : 0
                    continue
                }

                let w0          = e0 * invArea
                let w1          = e1 * invArea
                let w2          = e2 * invArea
                let paintPos    = v0.pos * w0 + v1.pos * w1 + v2.pos * w2
                let fontUv      = v0.uv * w0 + v1.uv * w1 + v2.uv * w2
                let vertexColor = Color.fromArgbF32((c0.a * w0 + c1.a * w1 + c2.a * w2) / 255.0,
                                                    (c0.r * w0 + c1.r * w1 + c2.r * w2) / 255.0,
                                                    (c0.g * w0 + c1.g * w1 + c2.g * w2) / 255.0,
                                                    (c0.b * w0 + c1.b * w1 + c2.b * w2) / 255.0)
                let cov = Math.saturate(((v0.cov * w0 + v1.cov * w1 + v2.cov * w2) - 0.5) / covWidth + 0.5)
                .blendPixel(image, x, y, .shade(paintPos, fontUv, fontUvDx, fontUvDy, vertexColor, cov))
            }
        }
    }

    mtd drawTriangleRange(image: *Image, painter: *Painter, start, count: u32)
    {
        var i   = start
        let end = start + count
        while i + 2 < end
        {
            .drawTriangle(image, painter.vertexBuffer[i], painter.vertexBuffer[i + 1], painter.vertexBuffer[i + 2])
            i += 3
        }
    }

    mtd drawTriangles(painter: *Painter, start, count: u32)
    {
        let image = .currentImage()
        if !image do
            return

        if !.overlapMode or .alphaResolve
        {
            .drawTriangleRange(image, painter, start, count)
            return
        }

        let pixelCount = cast(u64) image.width * cast(u64) image.height
        if .overlapAlpha.count != pixelCount do
            .overlapAlpha.resize(pixelCount)
        if .overlapWritten.count != pixelCount do
            .overlapWritten.resize(pixelCount)
        Memory.clear(.overlapAlpha.buffer!, pixelCount)
        Memory.clear(.overlapWritten.buffer!, pixelCount)

        // Destination alpha is the scratch channel in the OpenGL overlap path.
        .clearAlpha(image)
        .overlapPass = 1
        .drawTriangleRange(image, painter, start, count)
        .overlapPass = 2
        .drawTriangleRange(image, painter, start, count)
        .overlapPass = 0
    }

    mtd clearAlpha(image: *Image)
    {
        let minX = .scissorOn ? Math.clamp(cast(s32) .scissorRect.x, 0, image.width) : 0
        let minY = .scissorOn ? Math.clamp(cast(s32) .scissorRect.y, 0, image.height) : 0
        let maxX = .scissorOn ? Math.clamp(cast(s32) .scissorRect.right(), 0, image.width) : image.width
        let maxY = .scissorOn ? Math.clamp(cast(s32) .scissorRect.bottom(), 0, image.height) : image.height
        for var y = minY; y < maxY; y += 1
        {
            for var x = minX; x < maxX; x += 1
            {
                var pixel = readPixel(image, x, y)
                pixel.a = 0
                writePixel(image, x, y, pixel)
            }
        }
    }

    mtd clearCurrent(color: Color, forceColorMask = false)
    {
        let image = .currentImage()
        if !image do
            return

        let minX    = .scissorOn ? Math.clamp(cast(s32) .scissorRect.x, 0, image.width) : 0
        let minY    = .scissorOn ? Math.clamp(cast(s32) .scissorRect.y, 0, image.height) : 0
        let maxX    = .scissorOn ? Math.clamp(cast(s32) .scissorRect.right(), 0, image.width) : image.width
        let maxY    = .scissorOn ? Math.clamp(cast(s32) .scissorRect.bottom(), 0, image.height) : image.height
        let stencil = .currentStencil()
        for var y = minY; y < maxY; y += 1
        {
            for var x = minX; x < maxX; x += 1
            {
                let idx = cast(u64) y * cast(u64) image.width + cast(u64) x
                (dref stencil)[idx] = 0

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
            .paintCommand = dref cmd
            .paintOn      = true

        case .BindRenderTarget:
            .bindRenderTargetImpl(cmd.renderTgt.tgt)
            let target = .curRT!
            target.paintAlpha    = cmd.renderTgt.paintAlpha
            target.paintAlphaIdx = 0

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
        for &cmd, [idx] in painter.commandBuffer do
            .executeCommand(painter, &cmd, cast(u64) idx)
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
        let source         = storage!
        var result: retval = source.image
        result.crop(x, y, width, height)
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
    internal mtd addImageImpl(image: const *Image)->Texture
    {
        if !image.isValid() do
            return {}

        var result: retval
        result.attach(cast(TextureHandle) .nextHandle, image.pixelFormat, image.width, image.height)
        .nextHandle += 1

        var storage: CpuTexture
        storage.handle = result.handle
        storage.image  = dref image
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

        for rt, [idx] in .stackReleasedRT
        {
            let candidate = rt!
            if candidate.colorBuffer.width >= w2 and candidate.colorBuffer.height >= h2
            {
                .stackReleasedRT.removeAt(idx)
                return candidate
            }
        }

        let result = Memory.new'RenderTarget()
        dref result = .createRenderTargetImpl(cast(s32) w2, cast(s32) h2)
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
