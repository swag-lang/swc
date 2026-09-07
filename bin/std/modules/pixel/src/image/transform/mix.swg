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
        Debug.assert(srcImage.pixelFormat.hasAlpha() or mode != .SourceOver)

        Memory.copy(dstImage.pixels.buffer, .pixels.buffer, .byteCount)

        let left   = Math.max(x, 0)
        let top    = Math.max(y, 0)
        let right  = Math.min(x + srcImage.width, .width)
        let bottom = Math.min(y + srcImage.height, .height)
        if left >= right or top >= bottom do
            return

        var context = {
            dst: dstImage,
            src: &srcImage,
            dstX: left,
            dstY: top,
            srcX: left - x,
            srcY: top - y,
            width: right - left,
            mode: mode}

        parallel for |&context| parIndex in cast(u64) (bottom - top)
        {
            let row    = cast(u32) parIndex
            let dst    = cast(*Image) context.dst
            let src    = cast(const *Image) context.src
            let dstRow = dst.pixels.buffer! + cast(u64) (context.dstY + row) * dst.rowStride + cast(u64) context.dstX * dst.bytesPerPixel
            let srcRow = src.pixels.buffer! + cast(u64) (context.srcY + row) * src.rowStride + cast(u64) context.srcX * src.bytesPerPixel

            if context.mode == .Copy and dst.pixelFormat == src.pixelFormat and dst.alphaMode == src.alphaMode
            {
                Memory.copy(dstRow, srcRow, cast(u64) context.width * dst.bytesPerPixel)
            }
            else
            {
                for column in context.width
                {
                    let pixDst = dstRow + cast(u64) column * dst.bytesPerPixel
                    let pixSrc = srcRow + cast(u64) column * src.bytesPerPixel
                    let source = readLogicalPixelValue(pixSrc, src.pixelFormat, src.alphaMode)
                    var output = source
                    if context.mode == .SourceOver
                    {
                        let destination = readLogicalPixelValue(pixDst, dst.pixelFormat, dst.alphaMode)
                        output.a = source.a + destination.a * (1.0 - source.a)
                        if Math.isZeroEpsilon(output.a)
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

    // Mix with another image
    public mtd mix(srcImage: Image, x, y: s32, mode = MixMode.Copy)
    {
        Debug.assert(.pixelFormat.isPacked() and srcImage.pixelFormat.isPacked(), "mixing planar images is unsupported")
        Debug.assert(.pixels.buffer != null)
        .allocWorkingBuffer()
        .doMix(.safeWorkingBuffer(), srcImage, x, y, mode)
        .applyWorkingBuffer()
    }

    // Mix with another image
    public mtd const mixed(srcImage: Image, x, y: s32, mode = MixMode.Copy)->Image
    {
        Debug.assert(.pixels.buffer != null)
        Debug.assert(.pixelFormat.isPacked() and srcImage.pixelFormat.isPacked(), "mixing planar images is unsupported")
        var result: retval = create(.width, .height, .pixelFormat, alphaMode: me.alphaMode)
        .doMix(&result, srcImage, x, y, mode)
        return result
    }
}
