#global private

struct InterlacedSamples
{
    bytes: [36] u8
    count: u64
}

impl InterlacedSamples
{
    mtd add(value: u8)
    {
        .bytes[.count] = value
        .count         += 1
    }
}

// The slice stays live across the nested loops and each row reads a coordinate
// from an indexed array. Both values must survive the following copy.
func collectInterlacedSamples(width, height: s32, samples: const [..] u16)->InterlacedSamples
{
    let startX: [7] s32 = [0, 4, 0, 2, 0, 1, 0]
    let startY: [7] s32 = [0, 0, 4, 0, 2, 0, 1]
    let stepX:  [7] s32 = [8, 8, 4, 4, 2, 2, 1]
    let stepY:  [7] s32 = [8, 8, 8, 4, 4, 2, 2]
    var raw:    InterlacedSamples

    for pass in 7
    {
        if startX[pass] >= width or startY[pass] >= height do continue
        for var y = startY[pass]; y < height; y += stepY[pass]
        {
            raw.add(0)
            for var x = startX[pass]; x < width; x += stepX[pass]
            {
                let pixel = cast(u64) (y * width + x) * 3
                raw.add(cast(u8) (samples[pixel] / 257))
            }
        }
    }
    return raw
}

#test
{
    const Width  = 5
    const Height = 5
    var samples: [75] u16
    for y in Height
    {
        for x in Width
        {
            let pixel = (y * Width + x) * 3
            samples[pixel]     = cast(u16) (10 + x + y * Width) * 257
            samples[pixel + 1] = cast(u16) (50 + x * 2 + y) * 257
            samples[pixel + 2] = cast(u16) (100 + x + y * 3) * 257
        }
    }

    let raw = collectInterlacedSamples(Width, Height, samples)
    Swag.assert(raw.count == 36)
    Swag.assert(raw.bytes[1] == 10)
    Swag.assert(raw.bytes[raw.count - 1] == 29)
}
