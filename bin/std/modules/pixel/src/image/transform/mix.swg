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

        Jobs.parallelFor(cast(u32) (bottom - top), &context) #code(row, data)
        {
            let params = cast(*#decltype(context)) data!
            let dst    = cast(*Image) params.dst
            let src    = cast(const *Image) params.src
            let dstRow = dst.pixels.buffer! + cast(u64) (params.dstY + row) * dst.rowStride + cast(u64) params.dstX * dst.bytesPerPixel
            let srcRow = src.pixels.buffer! + cast(u64) (params.srcY + row) * src.rowStride + cast(u64) params.srcX * src.bytesPerPixel

            if params.mode == .Copy
            {
                Memory.copy(dstRow, srcRow, cast(u64) params.width * dst.bytesPerPixel)
            }
            else
            {
                for column in params.width
                {
                    let pixDst           = dstRow + cast(u64) column * 4
                    let pixSrc           = srcRow + cast(u64) column * 4
                    let sourceAlpha      = pixSrc[3] / 255.0
                    let destinationAlpha = pixDst[3] / 255.0
                    let outputAlpha      = sourceAlpha + destinationAlpha * (1.0 - sourceAlpha)
                    if Math.isZeroEpsilon(outputAlpha)
                    {
                        pixDst[as u32] = 0
                    }
                    else
                    {
                        let destinationFactor = destinationAlpha * (1.0 - sourceAlpha)
                        for channel in 3
                        {
                            let value = (pixSrc[channel] * sourceAlpha + pixDst[channel] * destinationFactor) / outputAlpha
                            pixDst[channel] = cast(u8) Math.round(value)
                        }

                        pixDst[3] = cast(u8) Math.round(outputAlpha * 255.0)
                    }
                }
            }
        }
    }

    // Mix with another image
    public mtd mix(srcImage: Image, x, y: s32, mode = MixMode.Copy)
    {
        Debug.assert(.pixelFormat == srcImage.pixelFormat, "mismatched pixel format")
        Debug.assert(.pixels.buffer != null)
        .allocWorkingBuffer()
        .doMix(.safeWorkingBuffer(), srcImage, x, y, mode)
        .applyWorkingBuffer()
    }

    // Mix with another image
    public mtd const mixed(srcImage: Image, x, y: s32, mode = MixMode.Copy)->Image
    {
        Debug.assert(.pixels.buffer != null)
        Debug.assert(.pixelFormat == srcImage.pixelFormat, "mismatched pixel format")
        var result: retval = create(.width, .height, .pixelFormat)
        .doMix(&result, srcImage, x, y, mode)
        return result
    }
}
