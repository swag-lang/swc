using Core

impl Image
{
    mtd const getWH(l, t, r, b: s32)->{ w, h: s32 }
    {
        let cw = .width + l + r
        let ch = .height + t + b
        Swag.assert(cw > 0 and ch > 0)
        return {cw, ch}
    }

    mtd const doExpand(dstImage: *Image, l, t, r, b: s32, color: Color)
    {
        dstImage.fill(color)

        // Rows are stored bottom-up, so the first buffer rows are the bottom of the picture: the
        // vertical offset comes from the bottom margin.
        let dstX = l < 0 ? 0 : l
        let dstY = b < 0 ? 0 : b
        let srcX = l < 0 ? -l : 0
        let srcY = b < 0 ? -b : 0

        let retainedWidth  = .width + Math.min(l, 0) + Math.min(r, 0)
        let retainedHeight = .height + Math.min(t, 0) + Math.min(b, 0)
        if retainedWidth <= 0 or retainedHeight <= 0 do
            return

        let srcW = retainedWidth * .bytesPerPixel
        let srcH = retainedHeight

        var dstPix = dstImage.pixels.buffer + dstY * dstImage.rowStride
        dstPix += dstX * .bytesPerPixel

        for cy in srcH
        {
            var srcPix = .pixels.buffer + (srcY + cy) * .rowStride
            srcPix += cast(u64) (srcX * .bytesPerPixel)
            Memory.copy(dstPix, srcPix, srcW)
            dstPix += dstImage.rowStride
        }
    }

    // Grows the image by a margin on each side, filled with `color`.
    //
    // `l`, `t`, `r` and `b` are the left, top, right and bottom margins in pixels, in picture
    // coordinates like [[Pixel.Image.crop]]. A negative margin removes that many pixels from its
    // side instead. The resulting size must
    // stay positive.
    public mtd expand(l, t, r, b: s32, color: Color = Color.fromArgb(Argb.White))
    {
        let {cw, ch} = .getWH(l, t, r, b)
        .allocWorkingBuffer(cw, ch, .pixelFormat)
        .doExpand(.safeWorkingBuffer(), l, t, r, b, color)
        .applyWorkingBuffer()
    }

    // Returns a copy grown by a margin on each side, filled with `color`.
    public mtd const expanded(l, t, r, b: s32, color: Color = Color.fromArgb(Argb.White))->Image
    {
        let {cw, ch}       = .getWH(l, t, r, b)
        var result: retval = create(cw, ch, .pixelFormat, alphaMode: me.alphaMode)
        .doExpand(&result, l, t, r, b, color)
        return result
    }
}
