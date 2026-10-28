using Core

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
            for dst.width
            {
                target[0] = cast(u8, ((row0[0] + #prom row0[bytes] + #prom row1[0] + #prom row1[bytes]) >> 2))
                target[1] = cast(u8, ((row0[1] + #prom row0[bytes + 1] + #prom row1[1] + #prom row1[bytes + 1]) >> 2))
                target[2] = cast(u8, ((row0[2] + #prom row0[bytes + 2] + #prom row1[2] + #prom row1[bytes + 2]) >> 2))
                if bytes == 4 do
                    target[3] = cast(u8, ((row0[3] + #prom row0[bytes + 3] + #prom row1[3] + #prom row1[bytes + 3]) >> 2))
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
