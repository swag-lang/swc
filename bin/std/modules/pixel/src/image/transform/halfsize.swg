using Core

impl Image
{
    mtd const doHalfSize(dstImage: *Image)
    {
        let legacy = .pixelFormat == .BGR8 or .pixelFormat == .BGRA8 or .pixelFormat == .RGB8 or .pixelFormat == .RGBA8
        if !legacy
        {
            var context = {src: me, dst: dstImage}
            Jobs.parallelFor(cast(u32) dstImage.height, &context) #code(row, data)
            {
                let params     = cast(*#decltype(context)) data!
                let src        = cast(const *Image) params.src
                let dst        = cast(*Image) params.dst
                let y0         = cast(s32) row * 2
                let sourceRow0 = src.pixels.buffer! + cast(u64) y0 * src.rowStride
                let sourceRow1 = sourceRow0 + src.rowStride
                let targetRow  = dst.pixels.buffer! + cast(u64) row * dst.rowStride
                for x in dst.width
                {
                    let x0      = cast(u64) x * 2 * src.bytesPerPixel
                    let p0      = readPixelValue(sourceRow0 + x0, src.pixelFormat)
                    let p1      = readPixelValue(sourceRow0 + x0 + src.bytesPerPixel, src.pixelFormat)
                    let p2      = readPixelValue(sourceRow1 + x0, src.pixelFormat)
                    let p3      = readPixelValue(sourceRow1 + x0 + src.bytesPerPixel, src.pixelFormat)
                    let average = PixelValue{
                        (p0.r + p1.r + p2.r + p3.r) * 0.25,
                        (p0.g + p1.g + p2.g + p3.g) * 0.25,
                        (p0.b + p1.b + p2.b + p3.b) * 0.25,
                        (p0.a + p1.a + p2.a + p3.a) * 0.25}
                    writePixelValue(targetRow + cast(u64) x * dst.bytesPerPixel, dst.pixelFormat, average)
                }
            }

            return
        }

        var f = {img: me}
        dstImage.visitPixels(&f)
        {
            let data       = cast(*#decltype(f)) userData!
            let srcImage   = cast(const *Image) data.img
            let b8         = srcImage.bytesPerPixel
            let w8         = srcImage.width * b8
            let pixSrc     = srcImage.pixels.buffer! + (x * 2 * b8) + (y * 2 * w8)
            let pixSrcb8   = pixSrc + b8
            let pixSrcw8   = pixSrc + w8
            let pixSrcw8b8 = pixSrcw8 + b8
            pix[0] = cast(u8) ((pixSrc[0] + #prom pixSrcb8[0] + #prom pixSrcw8[0] + #prom pixSrcw8b8[0]) >> 2)
            pix[1] = cast(u8) ((pixSrc[1] + #prom pixSrcb8[1] + #prom pixSrcw8[1] + #prom pixSrcw8b8[1]) >> 2)
            pix[2] = cast(u8) ((pixSrc[2] + #prom pixSrcb8[2] + #prom pixSrcw8[2] + #prom pixSrcw8b8[2]) >> 2)
            if image.bitsPerPixel == 32 do
                pix[3] = cast(u8) ((pixSrc[3] + #prom pixSrcb8[3] + #prom pixSrcw8[3] + #prom pixSrcw8b8[3]) >> 2)
        }
    }

    // Halves both image dimensions with a 2x2 box filter.
    public mtd halve()
    {
        Debug.assert(.width > 1 and .height > 1)
        .allocWorkingBuffer(.width / 2, .height / 2, .pixelFormat)
        .doHalfSize(.safeWorkingBuffer())
        .applyWorkingBuffer()
    }

    // Returns a copy with both dimensions halved by a 2x2 box filter.
    public mtd const halved()->Image
    {
        Debug.assert(.width > 1 and .height > 1)
        var result: retval = create(.width / 2, .height / 2, .pixelFormat, alphaMode: me.alphaMode)
        .doHalfSize(&result)
        return result
    }
}
