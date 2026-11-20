using Core

public impl Image
{
    // Selects how [[Pixel.Image.smartCropRect]] positions a cover crop.
    enum SmartCropMode
    {
        Attention     // Centers the crop over the most visually salient region.
        Entropy       // Trims the edges whose luminance histograms carry less information.
        Center        // Centers the crop on the source.
        None          // Keeps the entire source.
    }

    // Returns the largest crop with the supplied width-to-height ratio, in source pixel coordinates.
    //
    // `aspect` must be finite and positive. The source must be valid. The result can have
    // fractional edges, for use when sampling a texture. With `.None`, the result is the source
    // bounds. The analysis uses a reduced working copy and leaves the source pixels unchanged.
    mtd const smartCropRect(aspect: f32, mode = SmartCropMode.Attention)->Math.Rectangle
    {
        Swag.assert(.isValid() and Math.isFinite(aspect) and aspect > 0)
        let width  = cast(f32, .width)
        let height = cast(f32, .height)
        if mode == .None do
            return {0, 0, width, height}

        let cropWidth  = Math.min(width, height * aspect)
        let cropHeight = Math.min(height, width / aspect)
        if cropWidth == width and cropHeight == height do
            return {0, 0, width, height}

        var center = Math.Point{width * 0.5, height * 0.5}
        switch #complete mode
        {
        case .Attention:     center = .attentionCropCenter(cropWidth / width, cropHeight / height)
        case .Entropy:       center = .entropyCropCenter(cropWidth / width, cropHeight / height)
        case .Center, .None: break
        }

        return {Math.clamp(center.x - cropWidth * 0.5, 0, width - cropWidth),
                Math.clamp(center.y - cropHeight * 0.5, 0, height - cropHeight),
                cropWidth, cropHeight}
    }
}

private impl Image
{
    const AttentionSide = 32

    // As in libvips attention cropping, smooth an edge and color map at the scale of the
    // crop and center the window on the peak. Compute salience before choosing the placement.
    mtd const attentionCropCenter(widthFraction, heightFraction: f32)->Math.Point
    {
        let sample = .resized(AttentionSide, AttentionSide, .Bilinear)
        var luminance, chroma: [AttentionSide, AttentionSide] f32
        for y in AttentionSide
        {
            for x in AttentionSide
            {
                let color   = sample.pixelColor(x, y)
                let opacity = cast(f32, color.a) / 255
                luminance[y, x] = color.relativeLuminance() * opacity
                chroma[y, x]    = cast(f32,
                                       Math.max(color.r, color.g, color.b) -
                                       Math.min(color.r, color.g, color.b)) * opacity / 255
            }
        }

        var energy: [AttentionSide, AttentionSide] f32
        for y in AttentionSide
        {
            let above = Math.max(0, y - 1)
            let below = Math.min(AttentionSide - 1, y + 1)
            for x in AttentionSide
            {
                let left  = Math.max(0, x - 1)
                let right = Math.min(AttentionSide - 1, x + 1)
                let edge  = 4 * luminance[y, x] - luminance[y, left] - luminance[y, right] -
                            luminance[above, x] - luminance[below, x]
                energy[y, x] = Math.abs(edge) + chroma[y, x] * 0.2
            }
        }

        let sigma  = Math.sqrt(widthFraction * widthFraction + heightFraction * heightFraction) * AttentionSide / 10
        let radius = cast(s32, Math.ceil(3 * sigma))
        var kernel: [AttentionSide] f32
        for offset in 0 to radius do
            kernel[offset] = Math.exp(-cast(f32, offset * offset) / (2 * sigma * sigma))

        var horizontal: [AttentionSide, AttentionSide] f32

        // Zero padding keeps the blur from repeating scan borders outside the image.
        for y in AttentionSide
        {
            for x in AttentionSide
            {
                var value: f32
                for offset in Math.max(-radius, -x) to Math.min(radius, AttentionSide - 1 - x) do
                    value += energy[y, x + offset] * kernel[Math.abs(offset)]
                horizontal[y, x] = value
            }
        }

        let middle       = cast(f32, AttentionSide - 1) * 0.5
        var score: f32
        var bestDistance = Swag.F32.Max
        var best         = Math.Point{middle, middle}
        for y in AttentionSide
        {
            for x in AttentionSide
            {
                var value: f32
                for offset in Math.max(-radius, -y) to Math.min(radius, AttentionSide - 1 - y) do
                    value += horizontal[y + offset, x] * kernel[Math.abs(offset)]
                let dx       = x - middle
                let dy       = y - middle
                let distance = dx * dx + dy * dy
                let tied     = Math.abs(value - score) <= Math.ConstF32.Epsilon
                if value > score + Math.ConstF32.Epsilon or (tied and distance < bestDistance)
                {
                    score        = value
                    bestDistance = distance
                    best         = {x, y}
                }
            }
        }

        if score <= Math.ConstF32.Epsilon do
            best = {x: middle, y: middle}
        return {(best.x + 0.5) * .width / AttentionSide, (best.y + 0.5) * .height / AttentionSide}
    }

    // Greedy entropy cropping compares equal-sized strips at the two ends of the trim axis.
    mtd const entropyCropCenter(widthFraction, heightFraction: f32)->Math.Point
    {
        func stripEntropy(sample: const *Image, start, length: s32, across: bool)->f32
        {
            var histogram: [256] u32
            let breadth = across ? sample.height : sample.width
            for line in start until start + length
            {
                for at in breadth
                {
                    let color = across ? sample.pixelColor(line, at) : sample.pixelColor(at, line)
                    let luma  = (77'u32 * color.r + 150'u32 * color.g + 29'u32 * color.b) / 256
                    let bin   = luma * color.a / 255
                    histogram[bin] += 1
                }
            }

            let count = cast(f32, length * breadth)
            var score: f32
            for frequency in histogram where frequency != 0
            {
                let p = cast(f32, frequency) / count
                score -= p * Math.log2(p)
            }

            return score
        }

        const MaxSide = 160
        let scale  = Math.min(1.0'f32, cast(f32, MaxSide) / Math.max(.width, .height))
        let sample = .resized(Math.max(1, Math.roundS32(.width * scale)),
                              Math.max(1, Math.roundS32(.height * scale)),
                              .Bilinear)
        let across = widthFraction < heightFraction
        let length = across ? sample.width : sample.height
        let keep   = Math.max(1, Math.roundS32(length * Math.min(widthFraction, heightFraction)))
        let step   = (length - keep + 7) / 8
        var start  = 0
        var end    = length
        while end - start > keep
        {
            let strip = Math.min(step, end - start - keep)
            let first = stripEntropy(&sample, start, strip, across)
            let last  = stripEntropy(&sample, end - strip, strip, across)
            if first < last or (first == last and start < length - end) do
                start += strip
            else do
                end -= strip
        }

        let position = cast(f32, start + end) * 0.5 / length
        return {across ? position * .width : cast(f32, .width) * 0.5,
                across ? cast(f32, .height) * 0.5 : position * .height}
    }
}
