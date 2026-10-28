using Core

// Two four-channel output pixels use four source pixels from each row.
// Sum in 16-bit lanes before shifting, so rounding matches the scalar box filter.
#[Swag.NoInline]
private func halfByteRow4(source0, source1: const [*] u8, destination: [*] u8, width: u64)
{
    var top = source0
    var bottom = source1
    var dst = destination
    var remaining = width
    while remaining >= 2
    {
        let a = Math.Simd.load(top)
        let b = Math.Simd.load(bottom)
        var low = Math.Simd.widenLow(a) + Math.Simd.widenLow(b)
        var high = Math.Simd.widenHigh(a) + Math.Simd.widenHigh(b)
        low += cast #bit(Math.Simd.U16x8, Math.Simd.align(cast #bit(Math.Simd.U8x16, low), cast #bit(Math.Simd.U8x16, low), 8))
        high += cast #bit(Math.Simd.U16x8, Math.Simd.align(cast #bit(Math.Simd.U8x16, high), cast #bit(Math.Simd.U8x16, high), 8))
        let packed = Math.Simd.packUnsigned(cast #bit(Math.Simd.S16x8, (low >> 2)), cast #bit(Math.Simd.S16x8, (high >> 2)))
        let other = Math.Simd.align(packed, packed, 8)
        let result = cast #bit(Math.Simd.U8x16, Math.Simd.interleaveLow(cast #bit(Math.Simd.U32x4, packed), cast #bit(Math.Simd.U32x4, other)))
        Math.Simd.storeLow8(dst, result)
        top += 16
        bottom += 16
        dst += 8
        remaining -= 2
    }
    if remaining
    {
        for channel in 4'u64 do
            dst[channel] = cast(u8, ((top[channel] + #prom top[channel + 4] + #prom bottom[channel] + #prom bottom[channel + 4]) >> 2))
    }
}

impl Image
{
    mtd const doHalfSize(dstImage: *Image)
    {
        let legacy = .pixelFormat == .BGR8 or
                     .pixelFormat == .BGRA8 or
                     .pixelFormat == .RGB8 or
                     .pixelFormat == .RGBA8
        if not legacy
        {
            var context = {src: me, dst: dstImage}
            parallel for |&context| parIndex in cast(u64, dstImage.height)
            {
                let row        = cast(u32, parIndex)
                let src        = cast(const *Image, context.src)
                let dst        = cast(*Image, context.dst)
                let y0         = cast(s32, row) * 2
                let sourceRow0 = src.pixels.storage() + cast(u64, y0) * src.rowStride
                let sourceRow1 = sourceRow0 + src.rowStride
                let targetRow  = dst.pixels.storage() + cast(u64, row) * dst.rowStride
                for x in dst.width
                {
                    let x0      = cast(u64, x) * 2 * src.bytesPerPixel
                    let p0      = readPixelValue(sourceRow0 + x0, src.pixelFormat)
                    let p1      = readPixelValue(sourceRow0 + x0 + src.bytesPerPixel, src.pixelFormat)
                    let p2      = readPixelValue(sourceRow1 + x0, src.pixelFormat)
                    let p3      = readPixelValue(sourceRow1 + x0 + src.bytesPerPixel, src.pixelFormat)
                    let average = PixelValue{
                        (p0.r + p1.r + p2.r + p3.r) * 0.25,
                        (p0.g + p1.g + p2.g + p3.g) * 0.25,
                        (p0.b + p1.b + p2.b + p3.b) * 0.25,
                        (p0.a + p1.a + p2.a + p3.a) * 0.25}
                    writePixelValue(targetRow + cast(u64, x) * dst.bytesPerPixel, dst.pixelFormat, average)
                }
            }

            return
        }

        var context = {src: me, dst: dstImage}
        parallel for |&context| parIndex in cast(u64, dstImage.height)
        {
            let src = cast(const *Image, context.src)
            let dst = cast(*Image, context.dst)
            let bytes = cast(u64, src.bytesPerPixel)
            var row0 = src.pixels.storage() + 2 * parIndex * src.rowStride
            var row1 = row0 + src.rowStride
            var target = dst.pixels.storage() + parIndex * dst.rowStride
            if bytes == 4
            {
                halfByteRow4(row0, row1, target, cast(u64, dst.width))
                continue
            }
            for dst.width
            {
                target[0] = cast(u8, ((row0[0] + #prom row0[bytes] + #prom row1[0] + #prom row1[bytes]) >> 2))
                target[1] = cast(u8, ((row0[1] + #prom row0[bytes + 1] + #prom row1[1] + #prom row1[bytes + 1]) >> 2))
                target[2] = cast(u8, ((row0[2] + #prom row0[bytes + 2] + #prom row1[2] + #prom row1[bytes + 2]) >> 2))
                row0 += 2 * bytes
                row1 += 2 * bytes
                target += bytes
            }
        }

    }

    // Halves both image dimensions with a 2x2 box filter.
    public mtd halve()
    {
        Swag.assert(.width > 1 and .height > 1)
        .allocWorkingBuffer(.width / 2, .height / 2, .pixelFormat)
        .doHalfSize(.safeWorkingBuffer())
        .applyWorkingBuffer()
    }

    // Returns a copy with both dimensions halved by a 2x2 box filter.
    public mtd const halved()->Image
    {
        Swag.assert(.width > 1 and .height > 1)
        var result: #returntype = create(.width / 2, .height / 2, .pixelFormat, alphaMode: me.alphaMode)
        .doHalfSize(&result)
        return result
    }
}
