#global if #command == Swag.CompilerCommand.Test
#global internal

using Core

// Luma motion compensation against a direct reading of section 8.4.2.2.1: every quarter-sample
// phase, every partition shape, over samples that push the six-tap filter to both clamps, at
// positions read in place and at positions that go through the clamped window copy.
struct InterReference
{
    frame: *H264.Frame
}

impl InterReference
{
    // The integer sample at `x`, `y`, clamped to the padded plane like the window copy.
    mtd sample(x, y: s32)->s32
    {
        let planeWidth  = .frame.mbWidth * 16
        let planeHeight = .frame.mbHeight * 16
        let clampedX    = Math.clamp(x, -H264.FramePadding, planeWidth + H264.FramePadding - 1)
        let clampedY    = Math.clamp(y, -H264.FramePadding, planeHeight + H264.FramePadding - 1)
        return cast(s32) .frame.pixLuma(clampedX, clampedY)[0]
    }

    mtd horizontalSum(x, y: s32)->s32 => .sample(x - 2, y) - 5 * .sample(x - 1, y) + 20 * .sample(x, y) + 20 * .sample(x + 1, y) - 5 * .sample(x + 2, y) + .sample(x + 3, y)
    mtd verticalSum(x, y: s32)->s32   => .sample(x, y - 2) - 5 * .sample(x, y - 1) + 20 * .sample(x, y) + 20 * .sample(x, y + 1) - 5 * .sample(x, y + 2) + .sample(x, y + 3)

    mtd halfH(x, y: s32)->s32 => cast(s32) H264.clampPixel((.horizontalSum(x, y) + 16) >> 5)
    mtd halfV(x, y: s32)->s32 => cast(s32) H264.clampPixel((.verticalSum(x, y) + 16) >> 5)
    mtd halfC(x, y: s32)->s32
    {
        let sum = .horizontalSum(x, y - 2) - 5 * .horizontalSum(x, y - 1) + 20 * .horizontalSum(x, y) + 20 * .horizontalSum(x, y + 1) - 5 * .horizontalSum(x, y + 2) + .horizontalSum(x, y + 3)
        return cast(s32) H264.clampPixel((sum + 512) >> 10)
    }

    // The predicted sample at full position `x`, `y` and quarter phase `fracX`, `fracY`.
    mtd predict(x, y, fracX, fracY: s32)->u8
    {
        let g = .sample(x, y)
        let b = .halfH(x, y)
        let h = .halfV(x, y)
        let j = .halfC(x, y)
        let s = .halfH(x, y + 1)
        let m = .halfV(x + 1, y)
        var value: s32
        switch fracY * 4 + fracX
        {
        case 0:  value = g
        case 1:  value = (g + b + 1) >> 1
        case 2:  value = b
        case 3:  value = (.sample(x + 1, y) + b + 1) >> 1
        case 4:  value = (g + h + 1) >> 1
        case 5:  value = (b + h + 1) >> 1
        case 6:  value = (b + j + 1) >> 1
        case 7:  value = (b + m + 1) >> 1
        case 8:  value = h
        case 9:  value = (h + j + 1) >> 1
        case 10: value = j
        case 11: value = (j + m + 1) >> 1
        case 12: value = (.sample(x, y + 1) + h + 1) >> 1
        case 13: value = (h + s + 1) >> 1
        case 14: value = (j + s + 1) >> 1
        default: value = (m + s + 1) >> 1
        }

        return cast(u8) value
    }
}

#test
{
    var frame: H264.Frame
    frame.prepare(4, 4, 1)

    // Runs of 0 and 255 drive the six-tap sums to both ends of their range, where the packed
    // center filter saturates; the rest is noise.
    var seed = 0x2545F491'u32
    for index in frame.luma.count
    {
        seed = seed * #wrap 1664525 + #wrap 1013904223
        let noise = cast(u8) (seed >> 24)
        frame.luma[index] = (index / 7) % 3 == 0 ? (((seed >> 20) & 1) == 0 ? 0 : 255) : noise
    }

    var reference = InterReference{frame: &frame}
    const Shapes  = [16's32, 16, 16, 8, 8, 16, 8, 8, 8, 4, 4, 8, 4, 4]
    const Origins = [0's32, 0, 5, 9, 23, 17, 40, 36, -3, -30, 60, 45, 50, 3]
    var predicted: [16 * 16] u8
    for shape in Shapes.count / 2
    {
        let width  = Shapes[shape * 2]
        let height = Shapes[shape * 2 + 1]
        for origin in Origins.count / 2
        {
            let x = Origins[origin * 2]
            let y = Origins[origin * 2 + 1]
            for phase in 16's32
            {
                let fracX = phase & 3
                let fracY = phase >> 2
                Memory.set(predicted.buffer, 0x5A, predicted.count)
                H264.mcLuma(predicted.buffer, 16, &frame, 0, x, y, fracX, fracY, width, height)
                for row in height
                {
                    for column in 16's32
                    {
                        let got = predicted[cast(u64) (row * 16 + column)]
                        if column >= width do
                            Swag.assert(got == 0x5A)
                        else do
                            Swag.assert(got == reference.predict(x + column, y + row, fracX, fracY))
                    }
                }
            }
        }
    }
}

struct ChromaReference
{
    frame: *H264.Frame
    plane: u32
}

impl ChromaReference
{
    // The chroma sample at `x`, `y`, clamped to the padded plane like the window copy.
    mtd sample(x, y: s32)->s32
    {
        let clampedX = Math.clamp(x, -H264.FramePadding, .frame.mbWidth * 8 + H264.FramePadding - 1)
        let clampedY = Math.clamp(y, -H264.FramePadding, .frame.mbHeight * 8 + H264.FramePadding - 1)
        return cast(s32) .frame.pixChroma(.plane, clampedX, clampedY)[0]
    }
}

// Chroma motion compensation against section 8.4.2.2.2: every eighth-sample phase and block
// shape, in place and through the clamped window, on both chroma planes.
#test
{
    var frame: H264.Frame
    frame.prepare(4, 4, 1)

    var seed = 0x9E3779B9'u32
    for index in frame.cb.count
    {
        seed = seed * #wrap 1664525 + #wrap 1013904223
        frame.cb[index] = cast(u8) (seed >> 24)
        seed = seed * #wrap 1664525 + #wrap 1013904223
        frame.cr[index] = (index / 5) % 2 == 0 ? (((seed >> 21) & 1) == 0 ? 0 : 255) : cast(u8) (seed >> 24)
    }

    const Shapes  = [8's32, 8, 8, 4, 4, 8, 4, 4, 4, 2, 2, 4, 2, 2]
    const Origins = [0's32, 0, 3, 5, 11, 9, 27, 20, -2, -30, 31, 25, -40, 50]
    var predicted: [16 * 8] u8
    for plane in 2'u32
    {
        var reference = ChromaReference{frame: &frame, plane: plane}
        for shape in Shapes.count / 2
        {
            let width  = Shapes[shape * 2]
            let height = Shapes[shape * 2 + 1]
            for origin in Origins.count / 2
            {
                let x = Origins[origin * 2]
                let y = Origins[origin * 2 + 1]
                for phase in 64's32
                {
                    let fracX = phase & 7
                    let fracY = phase >> 3
                    Memory.set(predicted.buffer, 0x5A, predicted.count)
                    H264.mcChroma(predicted.buffer, 16, &frame, plane, x, y, fracX, fracY, width, height)
                    for row in height
                    {
                        for column in 16's32
                        {
                            let got = predicted[cast(u64) (row * 16 + column)]
                            if column >= width
                            {
                                Swag.assert(got == 0x5A)
                                continue
                            }

                            let px    = x + column
                            let py    = y + row
                            let value = (8 - fracX) * (8 - fracY) * reference.sample(px, py) + fracX * (8 - fracY) * reference.sample(px + 1, py) +
                                        (8 - fracX) * fracY * reference.sample(px, py + 1) + fracX * fracY * reference.sample(px + 1, py + 1)
                            Swag.assert(got == cast(u8) ((value + 32) >> 6))
                        }
                    }
                }
            }
        }
    }
}
