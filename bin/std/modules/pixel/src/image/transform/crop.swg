using Core

impl Image
{
    mtd const doCrop(dstImage: *Image, x, y, w, h: s32)
    {
        let self: const &Image = me
        var f                  = {x: x, y: .height - y - h, self: self}
        dstImage.visitPixels(&f, stride: w)
        {
            let params = cast(*#decltype(f)) (notnull userData)
            var srcPix = params.self.pixels.buffer + (y + params.y) * params.self.rowStride
            srcPix += cast(u64) (params.x * image.bytesPerPixel)
            Memory.copy(pix, srcPix, cast(u64) image.rowStride)
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

        .allocWorkingBuffer(cw, ch, .pixelFormat)
        .doCrop(.safeWorkingBuffer(), cx, cy, cw, ch)
        .applyWorkingBuffer()
    }

    public mtd crop(cropRect: Math.Rectangle)
    {
        return .crop(cast() cropRect.x, cast() cropRect.y, cast() cropRect.width, cast() cropRect.height)
    }

    // Crop image
    public mtd const cropped(x, y, w, h: s32)->Image
    {
        let cx = Math.clamp(x, 0, .width - 1)
        let cy = Math.clamp(y, 0, .height - 1)
        let cw = Math.min(w, .width - cx)
        let ch = Math.min(h, .height - cy)
        Debug.assert(cw > 0 and ch > 0)

        var result: retval = create(cw, ch, .pixelFormat)
        .doCrop(&result, cx, cy, cw, ch)
        return result
    }

    // Returns a cropped copy described by `cropRect`.
    //
    // Coordinates are clamped to the source image. Width and height must leave at
    // least one source pixel after clamping.
    public mtd const cropped(cropRect: Math.Rectangle)->Image
    {
        return .cropped(cast() cropRect.x, cast() cropRect.y, cast() cropRect.width, cast() cropRect.height)
    }
}
