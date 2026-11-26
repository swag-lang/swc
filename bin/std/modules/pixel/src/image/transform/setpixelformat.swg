using Core

private const DropKeep   = [0'u8, 1, 2, 4, 5, 6, 8, 9, 10, 12, 13, 14, 128, 128, 128, 128]
private const DropSwap   = [2'u8, 1, 0, 6, 5, 4, 10, 9, 8, 14, 13, 12, 128, 128, 128, 128]
private const ExpandKeep = [0'u8, 1, 2, 128, 3, 4, 5, 128, 6, 7, 8, 128, 9, 10, 11, 128]
private const ExpandSwap = [2'u8, 1, 0, 128, 5, 4, 3, 128, 8, 7, 6, 128, 11, 10, 9, 128]

internal func expandRgb8Alpha(source: const [*] u8, target: [*] u8, count: u64, swapColors: bool)
{
    using Math.Simd
    let table = swapColors ? ExpandSwap.buffer : ExpandKeep.buffer
    let channels = load(table)
    const Opaque = splat(0xFF000000'u32)
    let output   = cast([*] u32, target)
    var x: u64
    while count - x >= 6
    {
        let words = cast #bit(U32x4, shuffle(load(source + x * 3), channels))
        store(output + x, words | Opaque)
        x += 4
    }

    let first = swapColors ? 2 : 0
    let last  = 2 - first
    for i in x until count
    {
        let pixel = source + i * 3
        output[i] = 0xFF000000'u32 | cast(u32, pixel[first]) |
                    (cast(u32, pixel[1]) << 8) | (cast(u32, pixel[last]) << 16)
    }
}

internal func(HALF: bool) expandRgb16Alpha(source: const [*] u8, target: [*] u8, count: u64)
{
    using Math.Simd
    const Alpha  = HALF ? 0x3C00'u16 : 0xFFFF'u16
    const Expand = cast(U8x16, [0'u8, 1, 2, 3, 4, 5, 128, 128, 6, 7, 8, 9, 10, 11, 128, 128])
    const Opaque = cast(U16x8, [0'u16, 0, 0, Alpha, 0, 0, 0, Alpha])
    var x = 0'u64
    while count - x >= 3
    {
        var block = cast #bit(U16x8, shuffle(load(source + x * 6), Expand))
        #static if HALF
        {
            // The generic HALF round-trip canonicalizes NaNs and preserves their sign.
            let nan = (block & 0x7FFF'u16) > splat(0x7C00'u16)
            block = select(nan, (block & 0x8000'u16) | 0x7E00'u16, block)
        }

        store(cast([*] u16, target + x * 8), block | Opaque)
        x += 2
    }

    for i in x until count
    {
        let input  = cast(const [*] u16, source + i * 6)
        let output = cast([*] u16, target + i * 8)
        for channel in 3
        {
            var value = input[channel]
            #static if HALF do
                value = (value & 0x7FFF) > 0x7C00 ? ((value & 0x8000) | 0x7E00) : value
            output[channel] = value
        }

        output[3] = Alpha
    }
}

internal func expandRgb32Alpha(source: const [*] u8, target: [*] u8, count: u64)
{
    using Math.Simd
    const Color  = cast(U32x4, [0xFFFF_FFFF'u32, 0xFFFF_FFFF, 0xFFFF_FFFF, 0])
    const Opaque = cast(U32x4, [0'u32, 0, 0, 0x3F80_0000])
    let input  = cast(const [*] u32, source)
    let output = cast([*] u32, target)
    var x      = 0'u64
    while count - x >= 2
    {
        store(output + x * 4, (load(input + x * 3) & Color) | Opaque)
        x += 1
    }

    for i in x until count
    {
        let at  = output + 4 * i
        let rgb = input + 3 * i
        at[0] = rgb[0]
        at[1] = rgb[1]
        at[2] = rgb[2]
        at[3] = 0x3F80_0000
    }
}

impl Image
{
    mtd const doChangePf(dstImage: *Image)
    {
        let format = .pixelFormat
        if (format == .RGB16 and dstImage.pixelFormat == .RGBA16) or
           (format == .RGBF16 and dstImage.pixelFormat == .RGBAF16) or
           (format == .RGBF32 and dstImage.pixelFormat == .RGBAF32)
        {
            let src = me
            let dst = dstImage
            parallel for |src, dst, format| row in cast(u64, .height)
            {
                let input  = src.pixels.storage() + row * src.rowStride
                let output = dst.pixels.storage() + row * dst.rowStride
                let width  = cast(u64, src.width)
                switch format
                {
                case .RGB16:  expandRgb16Alpha'false(input, output, width)
                case .RGBF16: expandRgb16Alpha'true(input, output, width)
                case .RGBF32: expandRgb32Alpha(input, output, width)
                default:      unreachable
                }
            }

            return
        }

        let srcLegacy = .pixelFormat == .BGR8 or
                        .pixelFormat == .BGRA8 or
                        .pixelFormat == .RGB8 or
                        .pixelFormat == .RGBA8
        let dstLegacy = dstImage.pixelFormat == .BGR8 or
                        dstImage.pixelFormat == .BGRA8 or
                        dstImage.pixelFormat == .RGB8 or
                        dstImage.pixelFormat == .RGBA8
        if not srcLegacy or not dstLegacy or .alphaMode != dstImage.alphaMode
        {
            var genericContext = {src: me, dst: dstImage}
            parallel for |&genericContext| parIndex in cast(u64, .height)
            {
                let row    = cast(u32, parIndex)
                let params = &genericContext
                let src    = cast(const *Image, params.src)
                let dst    = cast(*Image, params.dst)
                let srcRow = src.pixels.storage() + cast(u64, row) * src.rowStride
                let dstRow = dst.pixels.storage() + cast(u64, row) * dst.rowStride
                for x in src.width
                {
                    let source = srcRow + cast(u64, x) * src.bytesPerPixel
                    let target = dstRow + cast(u64, x) * dst.bytesPerPixel
                    writeLogicalPixelValue(target, dst.pixelFormat, dst.alphaMode, readLogicalPixelValue(source, src.pixelFormat, src.alphaMode))
                }
            }

            return
        }

        var context = {src: me, dst: dstImage}
        parallel for |&context| parIndex in cast(u64, .height)
        {
            let row          = cast(u32, parIndex)
            let params       = &context
            let src          = cast(const *Image, params.src)
            let dst          = cast(*Image, params.dst)
            let srcRow       = src.pixels.storage() + cast(u64, row) * src.rowStride
            let dstRow       = dst.pixels.storage() + cast(u64, row) * dst.rowStride
            let srcBlueFirst = src.pixelFormat == .BGR8 or src.pixelFormat == .BGRA8
            let dstBlueFirst = dst.pixelFormat == .BGR8 or dst.pixelFormat == .BGRA8
            let swapColors   = srcBlueFirst != dstBlueFirst
            var x            = 0

            if src.bytesPerPixel == 4 and dst.bytesPerPixel == 4
            {
                PackedPixel.swapRedBlue32Row(srcRow, dstRow, src.width)
                x = src.width
            }
            elif src.bytesPerPixel == 4
            {
                let table   = swapColors ? DropSwap.buffer : DropKeep.buffer
                let shuffle = Math.Simd.load(table)
                while src.width - x >= 4
                {
                    let source = srcRow + cast(u64, x) * 4
                    let target = dstRow + cast(u64, x) * 3
                    Image.storeLow12(target, Math.Simd.shuffle(Math.Simd.load(source), shuffle))
                    x += 4
                }
            }
            elif dst.bytesPerPixel == 4
            {
                expandRgb8Alpha(srcRow, dstRow, cast(u64, src.width), swapColors)
                x = src.width
            }
            else
            {
                PackedPixel.swapRedBlue24Row(srcRow, dstRow, src.width)
                x = src.width
            }

            while x < src.width
            {
                let source = srcRow + cast(u64, x) * src.bytesPerPixel
                let target = dstRow + cast(u64, x) * dst.bytesPerPixel
                let red    = srcBlueFirst ? source[2] : source[0]
                let green  = source[1]
                let blue   = srcBlueFirst ? source[0] : source[2]
                if dstBlueFirst
                {
                    target[0] = blue
                    target[1] = green
                    target[2] = red
                }
                else
                {
                    target[0] = red
                    target[1] = green
                    target[2] = blue
                }

                if dst.bytesPerPixel == 4 do
                    target[3] = src.bytesPerPixel == 4 ? source[3] : 255
                x += 1
            }
        }
    }

    // Converts the image in place to another packed pixel representation.
    //
    // Integer destinations clamp and quantize, grayscale destinations use luminance,
    // adding alpha creates opaque samples, and removing alpha discards it. Alpha
    // association is retained whenever both formats store alpha.
    public mtd convertTo(newPf: PixelFormat)
    {
        Swag.assert(.pixels.buffer != null)

        if newPf == .pixelFormat do
            return

        let targetAlphaMode = newPf.hasAlpha() and .pixelFormat.hasAlpha() ? .alphaMode : AlphaMode.Straight
        .allocWorkingBuffer(.width, .height, newPf, targetAlphaMode)
        .doChangePf(.safeWorkingBuffer())
        .applyWorkingBuffer()
    }

    // Returns a copy converted to another packed pixel representation.
    //
    // Conversion semantics match [[Pixel.Image.convertTo]], and opaque image metadata is copied.
    public mtd const convertedTo(newPf: PixelFormat)->Image
    {
        Swag.assert(.pixels.buffer != null)

        if newPf == .pixelFormat do
            return me

        let targetAlphaMode     = newPf.hasAlpha() and .pixelFormat.hasAlpha() ? .alphaMode : AlphaMode.Straight
        var result: #returntype = create(.width, .height, newPf, alphaMode: targetAlphaMode)
        .doChangePf(&result)
        result.metadata = .metadata
        return result
    }
}
