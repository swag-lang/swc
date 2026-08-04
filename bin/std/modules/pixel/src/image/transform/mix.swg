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

        let mec = cast #unconst (*Image) me
        var f   = {dstImage: dstImage, srcImage: &srcImage, x: x, y: y, mode: mode}

        #[Swag.Mixin]
        func(BPP: u8) doIt()
        {
            mec.visitPixels(&f)
            {
                let params   = cast(*#decltype(f)) userData!
                let dstImage = cast(*Image) params.dstImage
                let srcImage = cast(const *Image) params.srcImage

                var pixDst = dstImage.pixels.buffer! + x * image.bytesPerPixel
                pixDst += cast(u64) (y * (image.width * image.bytesPerPixel))

                // fast path: outside blit rect, keep pixel as-is
                if x < params.x or y < params.y or x >= params.x + srcImage.width or y >= params.y + srcImage.height
                {
                    copyPixelDirect'BPP(cast([*] u8) pixDst!, cast([*] u8) pix)     // copy current dst pixel back (no change)
                }
                else
                {
                    let x1     = x - params.x
                    let y1     = y - params.y
                    var pixSrc = srcImage.pixels.buffer! + x1 * srcImage.bytesPerPixel
                    pixSrc += cast(u64) (y1 * (srcImage.width * srcImage.bytesPerPixel))

                    switch #complete params.mode
                    {
                    case .Copy:
                        copyPixelDirect'BPP(pixDst!, pixSrc!)

                    case .SourceOver:
                        if BPP != 32 do
                            copyPixelDirect'BPP(pixDst!, pixSrc!)
                        else
                        {
                            let sourceAlpha      = pixSrc[3] / 255.0
                            let destinationAlpha = pix[3] / 255.0
                            let outputAlpha      = sourceAlpha + destinationAlpha * (1.0 - sourceAlpha)
                            if Math.isZeroEpsilon(outputAlpha)
                            {
                                dref cast(*u32) pixDst = 0
                            }
                            else
                            {
                                let destinationFactor = destinationAlpha * (1.0 - sourceAlpha)
                                for [channel] in 3
                                {
                                    let value = (pixSrc[channel] * sourceAlpha + pix[channel] * destinationFactor) / outputAlpha
                                    pixDst[channel] = cast(u8) Math.round(value)
                                }

                                pixDst[3] = cast(u8) Math.round(outputAlpha * 255.0)
                            }
                        }
                    }
                }
            }
        }

        switch .bitsPerPixel
        {
        case 24: doIt'24()
        case 32: doIt'32()
        default: Debug.assert(false)
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
