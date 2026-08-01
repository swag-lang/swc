using Core

impl Image
{
    mtd const doHalfSize(dstImage: *Image)
    {
        var f = {img: me}
        dstImage.visitPixels(&f)
        {
            let data       = cast(*#decltype(f)) (notnull userData)
            let srcImage   = cast(const *Image) data.img
            let b8         = srcImage.bytesPerPixel
            let w8         = srcImage.width * b8
            let pixSrc     = (notnull srcImage.pixels.buffer) + (x * 2 * b8) + (y * 2 * w8)
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
        var result: retval = create(.width / 2, .height / 2, .pixelFormat)
        .doHalfSize(&result)
        return result
    }
}
