using Core

private const GrayChannel0_32 = [0'u8, 4, 8, 12, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128]
private const GrayChannel1_32 = [1'u8, 5, 9, 13, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128]
private const GrayChannel2_32 = [2'u8, 6, 10, 14, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128]
private const GrayOutput32    = [0'u8, 0, 0, 128, 1, 1, 1, 128, 2, 2, 2, 128, 3, 3, 3, 128]
private const GrayChannel0_24 = [0'u8, 3, 6, 9, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128]
private const GrayChannel1_24 = [1'u8, 4, 7, 10, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128]
private const GrayChannel2_24 = [2'u8, 5, 8, 11, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128]
private const GrayOutput24    = [0'u8, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3, 128, 128, 128, 128]

public impl Image
{
    // Transform image to grayscale, with a given factor
    mtd grayscale(factor: f32 = 1)
    {
        if !.pixelFormat.isPacked() do
            return

        let f = Math.saturate(factor)
        if f == 0 do
            return

        if .pixelFormat.isGrayscale() or .pixelFormat.bitDepth() != 8 or .alphaMode == .Premultiplied
        {
            var context = f
            .transformLogicalPixels(&context)
            {
                let blend = userData![as f32]
                let gray  = value.r * 0.2126 + value.g * 0.7152 + value.b * 0.0722
                value.r = Math.lerp(value.r, gray, blend)
                value.g = Math.lerp(value.g, gray, blend)
                value.b = Math.lerp(value.b, gray, blend)
            }

            return
        }

        if f == 1
        {
            var context = {image: me}
            Jobs.parallelFor(cast(u32) .height, &context) #code(row, data)
            {
                let params    = cast(*#decltype(context)) data!
                let image     = cast(*Image) params.image
                let rowPixels = image.pixels.buffer! + cast(u64) row * image.rowStride
                let blueFirst = image.pixelFormat == .BGR8 or image.pixelFormat == .BGRA8
                let weight0   = blueFirst ? 19'u16 : 54'u16
                let weight2   = blueFirst ? 54'u16 : 19'u16
                let weights0  = Math.Simd.splat(weight0)
                let weights1  = Math.Simd.splat(183'u16)
                let weights2  = Math.Simd.splat(weight2)
                let zeros     = Math.Simd.splat(0's16)
                var x         = 0

                if image.bytesPerPixel == 4
                {
                    let shuffle0  = Math.Simd.load(GrayChannel0_32.buffer)
                    let shuffle1  = Math.Simd.load(GrayChannel1_32.buffer)
                    let shuffle2  = Math.Simd.load(GrayChannel2_32.buffer)
                    let output    = Math.Simd.load(GrayOutput32.buffer)
                    let alphaMask = cast(Math.Simd.U8x16) [0'u8, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255]
                    while image.width - x >= 4
                    {
                        let block    = rowPixels + cast(u64) x * 4
                        let pixels   = Math.Simd.load(block)
                        let channel0 = Math.Simd.widenLow(Math.Simd.shuffle(pixels, shuffle0))
                        let channel1 = Math.Simd.widenLow(Math.Simd.shuffle(pixels, shuffle1))
                        let channel2 = Math.Simd.widenLow(Math.Simd.shuffle(pixels, shuffle2))
                        let weighted = channel0 * weights0 + channel1 * weights1 + channel2 * weights2
                        let gray16   = weighted >> 8
                        let gray8    = Math.Simd.packUnsigned(cast #bit(Math.Simd.S16x8) gray16, zeros)
                        let result   = Math.Simd.shuffle(gray8, output)
                        Math.Simd.store(block, result | (pixels & alphaMask))
                        x += 4
                    }
                }
                else
                {
                    let shuffle0 = Math.Simd.load(GrayChannel0_24.buffer)
                    let shuffle1 = Math.Simd.load(GrayChannel1_24.buffer)
                    let shuffle2 = Math.Simd.load(GrayChannel2_24.buffer)
                    let output   = Math.Simd.load(GrayOutput24.buffer)
                    while image.width - x >= 6
                    {
                        let block    = rowPixels + cast(u64) x * 3
                        let pixels   = Math.Simd.load(block)
                        let channel0 = Math.Simd.widenLow(Math.Simd.shuffle(pixels, shuffle0))
                        let channel1 = Math.Simd.widenLow(Math.Simd.shuffle(pixels, shuffle1))
                        let channel2 = Math.Simd.widenLow(Math.Simd.shuffle(pixels, shuffle2))
                        let weighted = channel0 * weights0 + channel1 * weights1 + channel2 * weights2
                        let gray16   = weighted >> 8
                        let gray8    = Math.Simd.packUnsigned(cast #bit(Math.Simd.S16x8) gray16, zeros)
                        let result   = Math.Simd.shuffle(gray8, output)
                        Image.storeLow12(block, result)
                        x += 4
                    }
                }

                while x < image.width
                {
                    let pixel = rowPixels + cast(u64) x * image.bytesPerPixel
                    let gray  = cast(u8) (((pixel[0] * cast(s32) weight0 + pixel[1] * 183's32 + pixel[2] * cast(s32) weight2) >> 8) & 0xFF)
                    pixel[0] = gray
                    pixel[1] = gray
                    pixel[2] = gray
                    x        += 1
                }
            }

            return
        }

        var context   = f
        let blueFirst = .pixelFormat == .BGR8 or .pixelFormat == .BGRA8
        .visitPixels(&context)
        {
            let blend   = userData![as f32]
            let weight0 = blueFirst ? 19's32 : 54's32
            let weight2 = blueFirst ? 54's32 : 19's32
            let gray    = cast(f32) ((((pix[0] * weight0) + (pix[1] * 183's32) + (pix[2] * weight2)) >> 8) & 0xFF)
            pix[0] = cast(u8) Math.lerp(cast(f32) pix[0], gray, blend)
            pix[1] = cast(u8) Math.lerp(cast(f32) pix[1], gray, blend)
            pix[2] = cast(u8) Math.lerp(cast(f32) pix[2], gray, blend)
        }
    }
}
