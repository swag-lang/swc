using Core

public impl Image
{
    // Invert colors
    mtd invert()
    {
        if .pixelFormat.channels() < 3 or .pixelFormat.bitDepth() != 8 do
            return

        let keepAlpha = .pixelFormat.hasAlpha()
        if keepAlpha
        {
            .visitVectorBytes() #code(block, data)
            {
                discard data
                let invertMask = cast(Math.Simd.U8x16) [255'u8, 255, 255, 0, 255, 255, 255, 0, 255, 255, 255, 0, 255, 255, 255, 0]
                Math.Simd.store(block, Math.Simd.load(block) ^ invertMask)
            }
        }
        else
        {
            .visitVectorBytes() #code(block, data)
            {
                discard data
                Math.Simd.store(block, Math.Simd.load(block) ^ Math.Simd.splat(255'u8))
            }
        }

        let pixels = .pixels.buffer!
        var offset = .byteCount & ~15'u64
        while offset < .byteCount
        {
            if !keepAlpha or offset & 3 != 3 do
                pixels[offset] = 255 - pixels[offset]
            offset += 1
        }
    }
}
