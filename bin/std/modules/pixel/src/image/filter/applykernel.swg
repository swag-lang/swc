using Core

impl Image
{
    // Predefined convolution kernels for [[Pixel.Image.applyKernel]].
    //
    // Each value lists the kernel size, the normalization divisor (zero for none), then the
    // weights row by row, from the top row of the picture.
    #[Swag.Incomplete]
    public enum Kernel: const [..] s32
    {
        GaussianBlur3x3Light  = [3, 8, 0, 1, 0, 1, 4, 1, 0, 1, 0]      // Light 3-by-3 Gaussian blur.
        GaussianBlur3x3Strong = [3, 20, 1, 2, 1, 2, 8, 2, 1, 2, 1]     // Stronger 3-by-3 Gaussian blur.

        // Smooth 5-by-5 Gaussian blur.
        GaussianBlur5x5 = [5, 159,
                           2, 4, 5, 4, 2,
                           4, 9, 12, 9, 4,
                           5, 12, 15, 12, 5,
                           4, 9, 12, 9, 4,
                           2, 4, 5, 4, 2]

        BoxBlur3x3 = [3, 9, 1, 1, 1, 1, 1, 1, 1, 1, 1]     // Uniform 3-by-3 box blur.

        // Uniform 5-by-5 box blur.
        BoxBlur5x5 = [5, 25,
                      1, 1, 1, 1, 1,
                      1, 1, 1, 1, 1,
                      1, 1, 1, 1, 1,
                      1, 1, 1, 1, 1,
                      1, 1, 1, 1, 1]

        Sharpen3x3Strong = [3, 8, -1, -1, -1, -1, 16, -1, -1, -1, -1]     // Strong all-neighbor sharpening.
        Sharpen3x3Cross  = [3, 1, 0, -1, 0, -1, 5, -1, 0, -1, 0]          // Cross-shaped sharpening.
        Soften3x3        = [3, 20, 0, 1, 0, 1, 16, 1, 0, 1, 0]            // Mild cross-shaped softening.

        EmbossLeft3x3Light   = [3, 0, -1, -1, 0, -1, 3, 0, 0, 0, 0]      // Light emboss illuminated from the left.
        EmbossLeft3x3Medium  = [3, 0, -2, -2, 0, -2, 6, 0, 0, 0, 0]      // Medium emboss illuminated from the left.
        EmbossLeft3x3Strong  = [3, 0, -4, -4, 0, -4, 12, 0, 0, 0, 0]     // Strong emboss illuminated from the left.
        EmbossRight3x3Light  = [3, 0, 0, 0, 0, 0, -3, 1, 0, 1, 1]        // Light emboss illuminated from the right.
        EmbossRight3x3Medium = [3, 0, 0, 0, 0, 0, -6, 2, 0, 2, 2]        // Medium emboss illuminated from the right.
        EmbossRight3x3Strong = [3, 0, 0, 0, 0, 0, -12, 4, 0, 4, 4]       // Strong emboss illuminated from the right.

        Laplacian8           = [3, 0, -1, -1, -1, -1, 8, -1, -1, -1, -1]      // Eight-neighbor Laplacian edge detector.
        DiagonalGradient     = [3, 0, -5, 0, 0, 0, 0, 0, 0, 0, 5]             // Diagonal gradient edge detector.
        HorizontalGradient   = [3, 0, -1, -1, -1, 0, 0, 0, 1, 1, 1]           // Horizontal gradient edge detector.
        HorizontalLine       = [3, 0, -1, -1, -1, 2, 2, 2, -1, -1, -1]        // Horizontal line detector.
        Laplacian8Strong     = [3, 0, -5, -5, -5, -5, 40, -5, -5, -5, -5]     // Strong eight-neighbor Laplacian edge detector.
        Laplacian4           = [3, 0, 0, 1, 0, 1, -4, 1, 0, 1, 0]             // Four-neighbor Laplacian edge detector.
        SobelHorizontal3x3   = [3, 0, 1, 2, 1, 0, 0, 0, -1, -2, -1]           // Sobel horizontal-edge detector.
        SobelVertical3x3     = [3, 0, 1, 0, -1, 2, 0, -2, 1, 0, -1]           // Sobel vertical-edge detector.
        PrewittHorizontal3x3 = [3, 0, 1, 1, 1, 0, 0, 0, -1, -1, -1]           // Prewitt horizontal-edge detector.
        PrewittVertical3x3   = [3, 0, 1, 0, -1, 1, 0, -1, 1, 0, -1]           // Prewitt vertical-edge detector.
    }

    #[Swag.Safety(.All, false)]
    mtd doKernel(dstImage: *Image, kernel: Kernel)
    {
        if not .pixelFormat.isPacked() do
            return

        if not .hasStraightByteColors()
        {
            var context = {kernel: cast(const [..] s32, kernel), dstImage: dstImage}
            .visitPixels(&context)
            {
                let params       = cast(const *#decltype(context), userData!)[]
                let radius       = params.kernel[0] / 2
                var coefficients = params.kernel.buffer + 2
                var sum          = PixelValue{0, 0, 0, 0}

                // The buffer is bottom-up, so the top kernel row reads the highest buffer row.
                for var dy = -radius; dy <= radius; dy += 1
                {
                    let sourceY   = Math.clamp(y - dy, 0, image.height - 1)
                    let sourceRow = image.pixels.storage() + cast(u64, sourceY) * image.rowStride
                    for var dx = -radius; dx <= radius; dx += 1
                    {
                        let sourceX     = Math.clamp(x + dx, 0, image.width - 1)
                        let source      = sourceRow + cast(u64, sourceX) * image.bytesPerPixel
                        let sample      = readLogicalPixelValue(source, image.pixelFormat, image.alphaMode)
                        let coefficient = cast(f32, coefficients[])
                        sum.r        += sample.r * coefficient
                        sum.g        += sample.g * coefficient
                        sum.b        += sample.b * coefficient
                        coefficients += 1
                    }
                }

                let divisor = params.kernel[1]
                if divisor > 1
                {
                    let scale = cast(f32, divisor)
                    sum.r /= scale
                    sum.g /= scale
                    sum.b /= scale
                }

                let current = readLogicalPixelValue(pix, image.pixelFormat, image.alphaMode)
                sum.a = current.a
                let destination = params.dstImage.pixels.storage() +
                                  cast(u64, y) * params.dstImage.rowStride +
                                  cast(u64, x) * params.dstImage.bytesPerPixel
                writeLogicalPixelValue(destination, params.dstImage.pixelFormat, params.dstImage.alphaMode, sum)
            }

            return
        }

        var context = {kernel: cast(const [..] s32, kernel), dstImage: dstImage}
        .visitPixels(&context)
        {
            let params        = cast(*#decltype(context), userData!)
            let radius        = params.kernel[0] / 2
            let bytesPerPixel = image.bytesPerPixel
            let rowStride     = image.rowStride
            let width         = image.width
            let height        = image.height
            let pixels        = cast([*] u8, image.pixels.storage())
            var coefficients  = params.kernel.buffer + 2

            var channel0Sum, channel1Sum, channel2Sum: s32

            // Interior pixels use contiguous rows without clamping each sample.
            if x >= radius and x <= width - radius - 1 and y >= radius and y <= height - radius - 1
            {
                var source      = pixels + ((x - radius) * bytesPerPixel) + ((y + radius) * rowStride)
                let kernelWidth = (radius * 2) + 1
                let rowStep     = cast(u64, (rowStride + (kernelWidth * bytesPerPixel)))
                for kernelWidth
                {
                    for kernelWidth
                    {
                        let coefficient = coefficients[]
                        channel0Sum  += cast(s32, source[0]) * coefficient
                        channel1Sum  += cast(s32, source[1]) * coefficient
                        channel2Sum  += cast(s32, source[2]) * coefficient
                        coefficients += 1
                        source       += bytesPerPixel
                    }

                    source -= rowStep     // Move to the row below after walking the kernel width.
                }
            }
            // Border pixels repeat the nearest edge sample.
            else
            {
                for var dy = -radius; dy <= radius; dy += 1
                {
                    let sourceY = Math.clamp(y - dy, 0, height - 1)
                    for var dx = -radius; dx <= radius; dx += 1
                    {
                        let sourceX     = Math.clamp(x + dx, 0, width - 1)
                        let source      = pixels + (sourceX * bytesPerPixel) + (sourceY * rowStride)
                        let coefficient = coefficients[]
                        channel0Sum  += cast(s32, source[0]) * coefficient
                        channel1Sum  += cast(s32, source[1]) * coefficient
                        channel2Sum  += cast(s32, source[2]) * coefficient
                        coefficients += 1
                    }
                }
            }

            let divisor = params.kernel[1]
            if divisor > 1 do
                channel0Sum, channel1Sum, channel2Sum /= divisor

            var destination = params.dstImage.pixels.storage() + (x * bytesPerPixel) + (y * rowStride)
            destination[0] = cast(u8, Math.clamp(channel0Sum, 0, 255))
            destination[1] = cast(u8, Math.clamp(channel1Sum, 0, 255))
            destination[2] = cast(u8, Math.clamp(channel2Sum, 0, 255))
            if image.bitsPerPixel == 32 do
                destination[3] = pix[3]
        }
    }

    // Convolves the image with a predefined kernel, in place.
    public mtd applyKernel(kernel: Kernel)
    {
        Swag.assert(.pixels.buffer != null)
        .allocWorkingBuffer()
        .doKernel(.safeWorkingBuffer(), kernel)
        .applyWorkingBuffer()
    }

    // Returns a copy of the image convolved with a predefined kernel.
    public mtd withKernelApplied(kernel: Kernel)->Image
    {
        Swag.assert(.pixels.buffer != null)
        var result: retval = create(.width, .height, .pixelFormat, alphaMode: me.alphaMode)
        .doKernel(&result, kernel)
        return result
    }
}
