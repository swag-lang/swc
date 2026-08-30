using Core

public impl Image
{
    // Invert colors
    mtd invert()
    {
        if !.pixelFormat.isPacked() do
            return

        if .pixelFormat.isGrayscale() or .pixelFormat.bitDepth() != 8 or .alphaMode == .Premultiplied
        {
            .transformLogicalPixels()
            {
                value.r = 1.0 - value.r
                value.g = 1.0 - value.g
                value.b = 1.0 - value.b
            }

            return
        }

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
