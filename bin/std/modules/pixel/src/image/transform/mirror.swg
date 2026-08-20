using Core

impl Image
{
    mtd const doMirror(dstImage: *Image)
    {
        if .bitsPerPixel == 32
        {
            var context = {src: me, dst: dstImage}
            Jobs.parallelFor(cast(u32) .height, &context) #code(row, data)
            {
                let params        = cast(*#decltype(context)) data!
                let src           = cast(const *Image) params.src
                let dst           = cast(*Image) params.dst
                let srcRow        = src.pixels.buffer! + cast(u64) row * src.rowStride
                let dstRow        = dst.pixels.buffer! + cast(u64) row * dst.rowStride
                let reversePixels = cast(Math.Simd.U8x16) [12'u8, 13, 14, 15, 8, 9, 10, 11, 4, 5, 6, 7, 0, 1, 2, 3]
                var x             = 0
                while src.width - x >= 4
                {
                    let srcBlock = srcRow + cast(u64) (src.width - x - 4) * 4
                    Math.Simd.store(dstRow + cast(u64) x * 4, Math.Simd.shuffle(Math.Simd.load(srcBlock), reversePixels))
                    x += 4
                }

                while x < src.width
                {
                    (cast([*] u32) dstRow)[x] = (cast(const [*] u32) srcRow)[src.width - x - 1]
                    x += 1
                }
            }

            return
        }

        if .bitsPerPixel == 24
        {
            var context = {src: me, dst: dstImage}
            Jobs.parallelFor(cast(u32) .height, &context) #code(row, data)
            {
                let params        = cast(*#decltype(context)) data!
                let src           = cast(const *Image) params.src
                let dst           = cast(*Image) params.dst
                let srcRow        = src.pixels.buffer! + cast(u64) row * src.rowStride
                let dstRow        = dst.pixels.buffer! + cast(u64) row * dst.rowStride
                let reversePixels = cast(Math.Simd.U8x16) [13'u8, 14, 15, 10, 11, 12, 7, 8, 9, 4, 5, 6, 128, 128, 128, 128]
                var x             = 0
                while src.width - x >= 6
                {
                    let srcBlock = srcRow + cast(u64) (src.width - x - 4) * 3
                    let pixels   = Math.Simd.load(srcBlock - 4)
                    Image.storeLow12(dstRow + cast(u64) x * 3, Math.Simd.shuffle(pixels, reversePixels))
                    x += 4
                }

                while x < src.width
                {
                    let source = srcRow + cast(u64) (src.width - x - 1) * 3
                    let target = dstRow + cast(u64) x * 3
                    Image.copyPixelDirect'24(target, source)
                    x += 1
                }
            }

            return
        }

        Debug.assert(false)
    }

    // Flip image horizontally
    public mtd mirror()
    {
        Debug.assert(.pixels.buffer != null)
        .allocWorkingBuffer()
        .doMirror(.safeWorkingBuffer())
        .applyWorkingBuffer()
    }

    // Flip image horizontally
    public mtd const mirrored()->Image
    {
        Debug.assert(.pixels.buffer != null)
        var result: retval = create(.width, .height, .pixelFormat)
        .doMirror(&result)
        return result
    }
}
