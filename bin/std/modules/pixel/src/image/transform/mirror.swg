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
                let params = cast(*#decltype(context)) data!
                let src    = cast(const *Image) params.src
                let dst    = cast(*Image) params.dst
                let srcRow = src.pixels.buffer! + cast(u64) row * src.rowStride
                let dstRow = dst.pixels.buffer! + cast(u64) row * dst.rowStride
                PackedPixel.reverseBgra32Row(srcRow, dstRow, src.width)
            }

            return
        }

        if .bitsPerPixel == 24
        {
            var context = {src: me, dst: dstImage}
            Jobs.parallelFor(cast(u32) .height, &context) #code(row, data)
            {
                let params = cast(*#decltype(context)) data!
                let src    = cast(const *Image) params.src
                let dst    = cast(*Image) params.dst
                let srcRow = src.pixels.buffer! + cast(u64) row * src.rowStride
                let dstRow = dst.pixels.buffer! + cast(u64) row * dst.rowStride
                PackedPixel.reverseBgr24Row(srcRow, dstRow, src.width)
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
