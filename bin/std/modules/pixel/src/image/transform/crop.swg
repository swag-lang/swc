using Core

impl Image
{
    mtd const doCrop(dstImage: *Image, x, y, w, h: s32)
    {
        let self: const *Image = me
        var f = {x: x, y: .height - y - h, self: self}
        dstImage.visitPixels(&f, stride: w)
        {
            let params = cast(*#decltype(f)) userData!
            var srcPix = params.self.pixels.buffer + (y + params.y) * params.self.rowStride
            srcPix += cast(u64) (params.x * image.bytesPerPixel)
            Memory.copy(pix, srcPix, cast(u64) image.rowStride)
        }
    }

    // Crops the image in place to a rectangle given in top-left pixel coordinates.
    //
    // Coordinates are clamped to the image, and the clamped rectangle must keep at least one
    // pixel.
    public mtd crop(x, y, w, h: s32)
    {
        let cx = Math.clamp(x, 0, .width - 1)
        let cy = Math.clamp(y, 0, .height - 1)
        let cw = Math.min(w, .width - cx)
        let ch = Math.min(h, .height - cy)
        Swag.assert(cw > 0 and ch > 0)

        .allocWorkingBuffer(cw, ch, .pixelFormat)
        .doCrop(.safeWorkingBuffer(), cx, cy, cw, ch)
        .applyWorkingBuffer()
    }

    // Crops the image in place to `cropRect`, clamped as by the pixel-coordinate overload.
    public mtd crop(cropRect: Math.Rectangle)
    {
        .crop(cast() cropRect.x, cast() cropRect.y, cast() cropRect.width, cast() cropRect.height)
    }

    // Returns a copy cropped to a rectangle given in top-left pixel coordinates.
    //
    // Coordinates are clamped as by [[Pixel.Image.crop]].
    public mtd const cropped(x, y, w, h: s32)->Image
    {
        let cx = Math.clamp(x, 0, .width - 1)
        let cy = Math.clamp(y, 0, .height - 1)
        let cw = Math.min(w, .width - cx)
        let ch = Math.min(h, .height - cy)
        Swag.assert(cw > 0 and ch > 0)

        var result: retval = create(cw, ch, .pixelFormat, alphaMode: me.alphaMode)
        .doCrop(&result, cx, cy, cw, ch)
        return result
    }

    public mtd const cropped(cropRect: Math.Rectangle)->Image => .cropped(cast() cropRect.x, cast() cropRect.y, cast() cropRect.width, cast() cropRect.height)
}
