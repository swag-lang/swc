using Core

impl Image
{
    mtd const getWH(l, t, r, b: s32)->{ w, h: s32 }
    {
        let cw = .width + l + r
        let ch = .height + t + b
        Debug.assert(cw > 0 and ch > 0)
        return {cw, ch}
    }

    mtd const doExpand(dstImage: *Image, l, t, r, b: s32, color: Color)
    {
        dstImage.fill(color)

        let dstX = l < 0 ? 0 : l
        let dstY = t < 0 ? 0 : t
        let srcX = l < 0 ? -l : 0
        let srcY = t < 0 ? -t : 0

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

    // Crop image
    public mtd expand(l, t, r, b: s32, color: Color = Color.fromArgb(Argb.White))
    {
        let {cw, ch} = .getWH(l, t, r, b)
        .allocWorkingBuffer(cw, ch, .pixelFormat)
        .doExpand(.safeWorkingBuffer(), l, t, r, b, color)
        .applyWorkingBuffer()
    }

    // Crop image
    public mtd const expanded(l, t, r, b: s32, color: Color = Color.fromArgb(Argb.White))->Image
    {
        let {cw, ch}       = .getWH(l, t, r, b)
        var result: retval = create(cw, ch, .pixelFormat, alphaMode: me.alphaMode)
        .doExpand(&result, l, t, r, b, color)
        return result
    }
}
