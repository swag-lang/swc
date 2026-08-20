using Core

public impl Image
{
    // Change the lightness. 'factor' is [-1, 1]
    mtd lightness(factor: f32 = 0.5)
    {
        if .pixelFormat.channels() < 3 or .pixelFormat.bitDepth() != 8 do
            return

        let level     = cast(s32) (Math.clamp(factor, -1.0, 1.0) * 255.0)
        let keepAlpha = .pixelFormat.hasAlpha()
        var context   = {adjustment: cast(u8) Math.abs(level), keepAlpha: keepAlpha}
        if level >= 0
        {
            .visitVectorBytes(&context) #code(block, data)
            {
                let params     = cast(*#decltype(context)) data!
                let adjustment = Math.Simd.splat(params.adjustment)
                let alphaMask  = cast(Math.Simd.U8x16) [0'u8, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255]
                let values     = Math.Simd.load(block)
                let adjusted   = Math.Simd.addSaturating(values, adjustment)
                if params.keepAlpha do
                    Math.Simd.store(block, (values & alphaMask) | (adjusted & ~alphaMask))
                else do
                    Math.Simd.store(block, adjusted)
            }
        }
        else
        {
            .visitVectorBytes(&context) #code(block, data)
            {
                let params     = cast(*#decltype(context)) data!
                let adjustment = Math.Simd.splat(params.adjustment)
                let alphaMask  = cast(Math.Simd.U8x16) [0'u8, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255]
                let values     = Math.Simd.load(block)
                let adjusted   = Math.Simd.subSaturating(values, adjustment)
                if params.keepAlpha do
                    Math.Simd.store(block, (values & alphaMask) | (adjusted & ~alphaMask))
                else do
                    Math.Simd.store(block, adjusted)
            }
        }

        let pixels = .pixels.buffer!
        var offset = .byteCount & ~15'u64
        while offset < .byteCount
        {
            if !.pixelFormat.hasAlpha() or offset & 3 != 3 do
                pixels[offset] = cast(u8) Math.clamp(cast(s32) pixels[offset] + level, 0, 255)
            offset += 1
        }
    }
}
