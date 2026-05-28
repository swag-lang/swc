using Core

impl Image
{
    mtd const doCrop(dstImage: *Image, x, y, w, h: s32)
    {
        let srcImage = me
        let cropX    = x
        let cropY    = .height - y - h
        dstImage.visitPixels(stride: w)
        {
            var srcPix = srcImage.pixels.buffer + (y + cropY) * srcImage.width8
            srcPix += cast(u64) (cropX * image.bpp8)
            Memory.copy(pix, srcPix, cast(u64) image.width8)
        }
    }

    // Crop image
    public mtd crop(x, y, w, h: s32)
    {
        let cx = Math.clamp(x, 0, .width - 1)
        let cy = Math.clamp(y, 0, .height - 1)
        let cw = Math.min(w, .width - cx)
        let ch = Math.min(h, .height - cy)
        Debug.assert(cw > 0 and ch > 0)

        .allocWorkingBuffer(cw, ch, .pf)
        .doCrop(.workingBuffer, cx, cy, cw, ch)
        .applyWorkingBuffer()
    }

    public mtd crop(cropRect: Math.Rectangle)
    {
        return .crop(cast() cropRect.x, cast() cropRect.y, cast() cropRect.width, cast() cropRect.height)
    }

    // Crop image
    public mtd const toCrop(x, y, w, h: s32)->Image
    {
        let cx = Math.clamp(x, 0, .width - 1)
        let cy = Math.clamp(y, 0, .height - 1)
        let cw = Math.min(w, .width - cx)
        let ch = Math.min(h, .height - cy)
        Debug.assert(cw > 0 and ch > 0)

        var result: retval = create(cw, ch, .pf)
        .doCrop(&result, cx, cy, cw, ch)
        return result
    }

    public mtd const toCrop(cropRect: Math.Rectangle)->Image
    {
        return .toCrop(cast() cropRect.x, cast() cropRect.y, cast() cropRect.width, cast() cropRect.height)
    }
}
