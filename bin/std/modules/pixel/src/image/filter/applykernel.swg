using Core

impl Image
{
    // Kernel format is : kernelSize, kernelNormalizeValue, kernelValues...
    #[Swag.Incomplete]
    public enum Kernel: const [..] s32
    {
        GaussianBlur3x3Light  = [3, 8, 0, 1, 0, 1, 4, 1, 0, 1, 0]                                                            // Light 3-by-3 Gaussian blur.
        GaussianBlur3x3Strong = [3, 20, 1, 2, 1, 2, 8, 2, 1, 2, 1]                                                           // Stronger 3-by-3 Gaussian blur.
        GaussianBlur5x5       = [5, 159, 2, 4, 5, 4, 2, 4, 9, 12, 9, 4, 5, 12, 15, 12, 5, 4, 9, 12, 9, 4, 2, 4, 5, 4, 2]     // Smooth 5-by-5 Gaussian blur.
        BoxBlur3x3            = [3, 9, 1, 1, 1, 1, 1, 1, 1, 1, 1]                                                            // Uniform 3-by-3 box blur.
        BoxBlur5x5            = [5, 25, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]           // Uniform 5-by-5 box blur.
        Sharpen3x3Strong      = [3, 8, -1, -1, -1, -1, 16, -1, -1, -1, -1]                                                   // Strong all-neighbor sharpening.
        Sharpen3x3Cross       = [3, 1, 0, -1, 0, -1, 5, -1, 0, -1, 0]                                                        // Cross-shaped sharpening.
        Soften3x3             = [3, 20, 0, 1, 0, 1, 16, 1, 0, 1, 0]                                                          // Mild cross-shaped softening.
        EmbossLeft3x3Light    = [3, 0, -1, -1, 0, -1, 3, 0, 0, 0, 0]                                                         // Light emboss illuminated from the left.
        EmbossLeft3x3Medium   = [3, 0, -2, -2, 0, -2, 6, 0, 0, 0, 0]                                                         // Medium emboss illuminated from the left.
        EmbossLeft3x3Strong   = [3, 0, -4, -4, 0, -4, 12, 0, 0, 0, 0]                                                        // Strong emboss illuminated from the left.
        EmbossRight3x3Light   = [3, 0, 0, 0, 0, 0, -3, 1, 0, 1, 1]                                                           // Light emboss illuminated from the right.
        EmbossRight3x3Medium  = [3, 0, 0, 0, 0, 0, -6, 2, 0, 2, 2]                                                           // Medium emboss illuminated from the right.
        EmbossRight3x3Strong  = [3, 0, 0, 0, 0, 0, -12, 4, 0, 4, 4]                                                          // Strong emboss illuminated from the right.
        Laplacian8            = [3, 0, -1, -1, -1, -1, 8, -1, -1, -1, -1]                                                    // Eight-neighbor Laplacian edge detector.
        DiagonalGradient      = [3, 0, -5, 0, 0, 0, 0, 0, 0, 0, 5]                                                           // Diagonal gradient edge detector.
        HorizontalGradient    = [3, 0, -1, -1, -1, 0, 0, 0, 1, 1, 1]                                                         // Horizontal gradient edge detector.
        HorizontalLine        = [3, 0, -1, -1, -1, 2, 2, 2, -1, -1, -1]                                                      // Horizontal line detector.
        Laplacian8Strong      = [3, 0, -5, -5, -5, -5, 40, -5, -5, -5, -5]                                                   // Strong eight-neighbor Laplacian edge detector.
        Laplacian4            = [3, 0, 0, 1, 0, 1, -4, 1, 0, 1, 0]                                                           // Four-neighbor Laplacian edge detector.
        SobelHorizontal3x3    = [3, 0, 1, 2, 1, 0, 0, 0, -1, -2, -1]                                                         // Sobel horizontal-edge detector.
        SobelVertical3x3      = [3, 0, 1, 0, -1, 2, 0, -2, 1, 0, -1]                                                         // Sobel vertical-edge detector.
        PrewittHorizontal3x3  = [3, 0, 1, 1, 1, 0, 0, 0, -1, -1, -1]                                                         // Prewitt horizontal-edge detector.
        PrewittVertical3x3    = [3, 0, 1, 0, -1, 1, 0, -1, 1, 0, -1]                                                         // Prewitt vertical-edge detector.
    }

    #[Swag.Safety(.All, false)]
    mtd doKernel(dstImage: *Image, kernel: Kernel)
    {
        // unsupported pixel format
        if .pixelFormat.channels() < 3 or .pixelFormat.bitDepth() != 8 do
            return

        var f = {kernel: cast(const [..] s32) kernel, dstImage: dstImage}
        .visitPixels(&f)
        {
            let params     = cast(*#decltype(f)) userData!
            let kernelSize = params.kernel[0] / 2
            let b8         = image.bytesPerPixel
            let w8         = image.rowStride
            let w          = image.width
            let h          = image.height
            let px         = cast([*] u8) image.pixels.buffer!
            var ks         = @dataof(params.kernel) + 2

            var bs, gs, rs: s32

            // Fast case when we are not around borders
            if x >= kernelSize and x <= w - kernelSize - 1 and y >= kernelSize and y <= h - kernelSize - 1
            {
                var p     = px + ((x - kernelSize) * b8) + ((y - kernelSize) * w8)
                let kfull = (kernelSize * 2) + 1
                let koff  = cast(u64) (w8 - (kfull * b8))
                for kfull
                {
                    for kfull
                    {
                        let ks0 = ks[]
                        bs += cast(s32) p[0] * ks0
                        gs += cast(s32) p[1] * ks0
                        rs += cast(s32) p[2] * ks0
                        ks += 1
                        p  += b8
                    }

                    p += koff     // Go to next line
                }
            }

            // Slowest case, near the borders
            else
            {
                for var dy = -kernelSize; dy <= kernelSize; dy += 1
                {
                    let ny     = Math.clamp(y + dy, 0, h - 1)
                    for var dx = -kernelSize; dx <= kernelSize; dx += 1
                    {
                        let nx  = Math.clamp(x + dx, 0, w - 1)
                        let p   = px + (nx * b8) + (ny * w8)
                        let ks0 = ks[]
                        bs += cast(s32) p[0] * ks0
                        gs += cast(s32) p[1] * ks0
                        rs += cast(s32) p[2] * ks0
                        ks += 1
                    }
                }
            }

            let ksum = params.kernel[1]
            if ksum > 1 do
                bs, gs, rs /= ksum

            var dpix = params.dstImage.pixels.buffer! + (x * b8) + (y * w8)
            dpix[0] = cast(u8) Math.clamp(bs, 0, 255)
            dpix[1] = cast(u8) Math.clamp(gs, 0, 255)
            dpix[2] = cast(u8) Math.clamp(rs, 0, 255)
            if image.bitsPerPixel == 32 do
                dpix[3] = pix[3]
        }
    }

    // Apply a kernel to the image
    public mtd applyKernel(kernel: Kernel)
    {
        Debug.assert(.pixels.buffer != null)
        .allocWorkingBuffer()
        .doKernel(.safeWorkingBuffer(), kernel)
        .applyWorkingBuffer()
    }

    // Apply a kernel to the image
    public mtd withKernelApplied(kernel: Kernel)->Image
    {
        Debug.assert(.pixels.buffer != null)
        var result: retval = create(.width, .height, .pixelFormat)
        .doKernel(&result, kernel)
        return result
    }
}
