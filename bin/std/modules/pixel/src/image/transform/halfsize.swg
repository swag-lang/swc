using Core

const HalfRgbLeft = cast(Math.Simd.U8x16, [0'u8, 1, 2, 6, 7, 8, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80])
const HalfRgbRight = cast(Math.Simd.U8x16, [3'u8, 4, 5, 9, 10, 11, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80])

// The wide reads stay inside the row by leaving the final one or two output
// pixels to the scalar tail. Only six bytes are written per vector step.
#[Swag.NoInline]
private func halfByteRow3(source0, source1: const [*] u8, destination: [*] u8, width: u64)
{
    var top = source0
    var bottom = source1
    var dst = destination
    var remaining = width
    while remaining >= 3
    {
        let a = Math.Simd.load(top)
        let b = Math.Simd.load(bottom)
        let a0 = Math.Simd.widenLow(Math.Simd.shuffle(a, HalfRgbLeft))
        let a1 = Math.Simd.widenLow(Math.Simd.shuffle(a, HalfRgbRight))
        let b0 = Math.Simd.widenLow(Math.Simd.shuffle(b, HalfRgbLeft))
        let b1 = Math.Simd.widenLow(Math.Simd.shuffle(b, HalfRgbRight))
        let sums = (a0 + a1 + b0 + b1) >> 2
        let packed = Math.Simd.packUnsigned(cast #bit(Math.Simd.S16x8, sums), Math.Simd.splat(0's16))
        cast([*] u32, dst)[0] = cast #bit(Math.Simd.U32x4, packed)[0]
        cast([*] u16, (dst + 4))[0] = cast #bit(Math.Simd.U16x8, packed)[2]
        top += 12
        bottom += 12
        dst += 6
        remaining -= 2
    }
    while remaining
    {
        for channel in 3'u64 do
            dst[channel] = cast(u8, ((top[channel] + #prom top[channel + 3] + #prom bottom[channel] + #prom bottom[channel + 3]) >> 2))
        top += 6
        bottom += 6
        dst += 3
        remaining -= 1
    }
}

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
            let row0 = src.pixels.storage() + 2 * parIndex * src.rowStride
            let row1 = row0 + src.rowStride
            let target = dst.pixels.storage() + parIndex * dst.rowStride
            if bytes == 4 do
                halfByteRow4(row0, row1, target, cast(u64, dst.width))
            else do
                halfByteRow3(row0, row1, target, cast(u64, dst.width))
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
