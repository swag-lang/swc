using Core

private const DropKeep   = [0'u8, 1, 2, 4, 5, 6, 8, 9, 10, 12, 13, 14, 128, 128, 128, 128]
private const DropSwap   = [2'u8, 1, 0, 6, 5, 4, 10, 9, 8, 14, 13, 12, 128, 128, 128, 128]
private const ExpandKeep = [0'u8, 1, 2, 128, 3, 4, 5, 128, 6, 7, 8, 128, 9, 10, 11, 128]
private const ExpandSwap = [2'u8, 1, 0, 128, 5, 4, 3, 128, 8, 7, 6, 128, 11, 10, 9, 128]

impl Image
{
    mtd const doChangePf(dstImage: *Image)
    {
        let srcLegacy = .pixelFormat == .BGR8 or .pixelFormat == .BGRA8 or .pixelFormat == .RGB8 or .pixelFormat == .RGBA8
        let dstLegacy = dstImage.pixelFormat == .BGR8 or dstImage.pixelFormat == .BGRA8 or dstImage.pixelFormat == .RGB8 or dstImage.pixelFormat == .RGBA8
        if !srcLegacy or !dstLegacy or .alphaMode != dstImage.alphaMode
        {
            var genericContext = {src: me, dst: dstImage}
            Jobs.parallelFor(cast(u32) .height, &genericContext) #code(row, data)
            {
                let params = cast(*#decltype(genericContext)) data!
                let src    = cast(const *Image) params.src
                let dst    = cast(*Image) params.dst
                let srcRow = src.pixels.buffer! + cast(u64) row * src.rowStride
                let dstRow = dst.pixels.buffer! + cast(u64) row * dst.rowStride
                for x in src.width
                {
                    let source = srcRow + cast(u64) x * src.bytesPerPixel
                    let target = dstRow + cast(u64) x * dst.bytesPerPixel
                    writeLogicalPixelValue(target, dst.pixelFormat, dst.alphaMode, readLogicalPixelValue(source, src.pixelFormat, src.alphaMode))
                }
            }

            return
        }

        var context = {src: me, dst: dstImage}
        Jobs.parallelFor(cast(u32) .height, &context) #code(row, data)
        {
            let params       = cast(*#decltype(context)) data!
            let src          = cast(const *Image) params.src
            let dst          = cast(*Image) params.dst
            let srcRow       = src.pixels.buffer! + cast(u64) row * src.rowStride
            let dstRow       = dst.pixels.buffer! + cast(u64) row * dst.rowStride
            let srcBlueFirst = src.pixelFormat == .BGR8 or src.pixelFormat == .BGRA8
            let dstBlueFirst = dst.pixelFormat == .BGR8 or dst.pixelFormat == .BGRA8
            let swapColors   = srcBlueFirst != dstBlueFirst
            var x            = 0

            if src.bytesPerPixel == 4 and dst.bytesPerPixel == 4
            {
                PackedPixel.swapRedBlue32Row(srcRow, dstRow, src.width)
                x = src.width
            }
            elif src.bytesPerPixel == 4
            {
                let table   = swapColors ? DropSwap.buffer : DropKeep.buffer
                let shuffle = Math.Simd.load(table)
                while src.width - x >= 4
                {
                    let source = srcRow + cast(u64) x * 4
                    let target = dstRow + cast(u64) x * 3
                    Image.storeLow12(target, Math.Simd.shuffle(Math.Simd.load(source), shuffle))
                    x += 4
                }
            }
            elif dst.bytesPerPixel == 4
            {
                let table     = swapColors ? ExpandSwap.buffer : ExpandKeep.buffer
                let shuffle   = Math.Simd.load(table)
                let alphaMask = cast(Math.Simd.U8x16) [0'u8, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255]
                while src.width - x >= 6
                {
                    let source = srcRow + cast(u64) x * 3
                    let target = dstRow + cast(u64) x * 4
                    Math.Simd.store(target, Math.Simd.shuffle(Math.Simd.load(source), shuffle) | alphaMask)
                    x += 4
                }
            }
            else
            {
                PackedPixel.swapRedBlue24Row(srcRow, dstRow, src.width)
                x = src.width
            }

            while x < src.width
            {
                let source = srcRow + cast(u64) x * src.bytesPerPixel
                let target = dstRow + cast(u64) x * dst.bytesPerPixel
                let red    = srcBlueFirst ? source[2] : source[0]
                let green  = source[1]
                let blue   = srcBlueFirst ? source[0] : source[2]
                if dstBlueFirst
                {
                    target[0] = blue
                    target[1] = green
                    target[2] = red
                }
                else
                {
                    target[0] = red
                    target[1] = green
                    target[2] = blue
                }

                if dst.bytesPerPixel == 4 do
                    target[3] = src.bytesPerPixel == 4 ? source[3] : 255
                x += 1
            }
        }
    }

    // Converts the image in place to another packed pixel representation.
    //
    // Integer destinations clamp and quantize, grayscale destinations use luminance,
    // adding alpha creates opaque samples, and removing alpha discards it. Alpha
    // association is retained whenever both formats store alpha.
    public mtd convertTo(newPf: PixelFormat)
    {
        Debug.assert(.pixels.buffer != null)

        if newPf == .pixelFormat do
            return

        let targetAlphaMode = newPf.hasAlpha() and .pixelFormat.hasAlpha() ? .alphaMode : AlphaMode.Straight
        .allocWorkingBuffer(.width, .height, newPf, targetAlphaMode)
        .doChangePf(.safeWorkingBuffer())
        .applyWorkingBuffer()
    }

    // Returns a copy converted to another packed pixel representation.
    //
    // Conversion semantics match [[Image.convertTo]].
    public mtd const convertedTo(newPf: PixelFormat)->Image
    {
        Debug.assert(.pixels.buffer != null)

        if newPf == .pixelFormat do
            return me

        let targetAlphaMode = newPf.hasAlpha() and .pixelFormat.hasAlpha() ? .alphaMode : AlphaMode.Straight
        var result: retval  = create(.width, .height, newPf, alphaMode: targetAlphaMode)
        .doChangePf(&result)
        return result
    }
}
