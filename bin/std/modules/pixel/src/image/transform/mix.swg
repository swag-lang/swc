using Core

impl Image
{
    // Selects how source pixels are combined with a destination image.
    public enum MixMode
    {
        Copy           // Replace destination pixels with source pixels.
        SourceOver     // Composite straight-alpha source pixels over the destination.
    }

    mtd const doMix(dstImage: *Image, srcImage: Image, x, y: s32, mode = MixMode.Copy)
    {
        Swag.assert(srcImage.pixelFormat.hasAlpha() or mode != .SourceOver)

        Memory.copy(dstImage.pixels.storage(), .pixels.storage(), .byteCount)

        let x64      = cast(s64, x)
        let y64      = cast(s64, y)
        let left64   = Math.max(x64, 0)
        let top64    = Math.max(y64, 0)
        let right64  = Math.min(x64 + cast(s64, srcImage.width), cast(s64, .width))
        let bottom64 = Math.min(y64 + cast(s64, srcImage.height), cast(s64, .height))
        if left64 >= right64 or top64 >= bottom64 do
            return

        let left   = cast(s32, left64)
        let top    = cast(s32, top64)
        let right  = cast(s32, right64)
        let bottom = cast(s32, bottom64)

        var context = {
            dst: dstImage,
            src: &srcImage,
            dstX: left,
            dstY: top,
            srcX: cast(s32, (left64 - x64)),
            srcY: cast(s32, (top64 - y64)),
            width: right - left,
            mode: mode}

        parallel for |&context| parIndex in cast(u64, (bottom - top))
        {
            let row    = cast(u32, parIndex)
            let dst    = cast(*Image, context.dst)
            let src    = cast(const *Image, context.src)
            let dstRow = dst.pixels.storage() + cast(u64, (context.dstY + row)) * dst.rowStride + cast(u64, context.dstX) * dst.bytesPerPixel
            let srcRow = src.pixels.storage() + cast(u64, (context.srcY + row)) * src.rowStride + cast(u64, context.srcX) * src.bytesPerPixel

            if context.mode == .Copy and
               dst.pixelFormat == src.pixelFormat and
               dst.alphaMode == src.alphaMode
            {
                Memory.copy(dstRow, srcRow, cast(u64, context.width) * dst.bytesPerPixel)
            }
            else
            {
                for column in context.width
                {
                    let pixDst = dstRow + cast(u64, column) * dst.bytesPerPixel
                    let pixSrc = srcRow + cast(u64, column) * src.bytesPerPixel
                    let source = readLogicalPixelValue(pixSrc, src.pixelFormat, src.alphaMode)
                    var output = source
                    if context.mode == .SourceOver
                    {
                        let destination = readLogicalPixelValue(pixDst, dst.pixelFormat, dst.alphaMode)
                        output.a = source.a + destination.a * (1.0 - source.a)
                        if output.a == 0.0
                        {
                            output = {0, 0, 0, 0}
                        }
                        else
                        {
                            let destinationFactor = destination.a * (1.0 - source.a)
                            output.r = (source.r * source.a + destination.r * destinationFactor) / output.a
                            output.g = (source.g * source.a + destination.g * destinationFactor) / output.a
                            output.b = (source.b * source.a + destination.b * destinationFactor) / output.a
                        }
                    }

                    writeLogicalPixelValue(pixDst, dst.pixelFormat, dst.alphaMode, output)
                }
            }
        }
    }

    // Draws `srcImage` into the image, in place.
    //
    // `(x, y)` places the bottom-left corner of `srcImage` in buffer coordinates: `x` counts
    // columns from the left and `y` counts rows up from the bottom of the picture. The part of
    // `srcImage` outside the image is ignored. [[Pixel.Image.MixMode.SourceOver]] requires a
    // source format with alpha.
    public mtd mix(srcImage: Image, x, y: s32, mode = MixMode.Copy)
    {
        Swag.assert(.pixelFormat.isPacked() and srcImage.pixelFormat.isPacked(), "mixing planar images is unsupported")
        Swag.assert(.pixels.buffer != null)
        .allocWorkingBuffer()
        .doMix(.safeWorkingBuffer(), srcImage, x, y, mode)
        .applyWorkingBuffer()
    }

    // Returns a copy of the image with `srcImage` drawn at `(x, y)`, placed as by [[Pixel.Image.mix]].
    public mtd const mixed(srcImage: Image, x, y: s32, mode = MixMode.Copy)->Image
    {
        Swag.assert(.pixels.buffer != null)
        Swag.assert(.pixelFormat.isPacked() and srcImage.pixelFormat.isPacked(), "mixing planar images is unsupported")
        var result: #returntype = create(.width, .height, .pixelFormat, alphaMode: me.alphaMode)
        .doMix(&result, srcImage, x, y, mode)
        return result
    }
}
