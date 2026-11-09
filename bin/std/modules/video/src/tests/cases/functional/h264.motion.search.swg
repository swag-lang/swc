#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// A shifted textured tile remains detectable against a lossy decoded reference.
#test
{
    const Width = 64'u64
    var reference: [Width * Width] u8
    var current: [Width * Width] u8
    for row in Width
    {
        for column in Width
        {
            let offset = row * Width + column
            reference[offset] = cast(u8, (column * 7 + row * 11) & 255)
            current[offset] = reference[offset]
        }
    }
    for row in 16'u64
    {
        for column in 16'u64
        {
            let prior = (24 + row) * Width + 16 + column
            let target = (32 + row) * Width + 32 + column
            current[target] = cast(u8, Math.clamp(cast(s32, reference[prior]) +
                                                   (column & 1 ? 1 : -1), 0, 255))
        }
    }
    Swag.require(H264.preferShiftedInterPrediction(current.buffer, reference.buffer,
                                                   64, 64, 2, 2, -16, -8))
    Swag.require(not H264.preferShiftedInterPrediction(current.buffer, reference.buffer,
                                                       64, 64, 0, 0, -16, -8))
    Swag.require(not H264.preferShiftedInterPrediction(current.buffer, reference.buffer,
                                                       64, 64, 2, 2, -15, -8))
}

// Flat color changes, identical pictures and cropped edges keep zero motion.
#test
{
    var reference: [64 * 64] u8
    var current: [64 * 64] u8
    for index in reference.count
    {
        reference[index] = 100
        current[index] = 105
    }
    Swag.require(not H264.preferShiftedInterPrediction(current.buffer, reference.buffer,
                                                       64, 64, 2, 2, -16, -8))
    for index in reference.count do
        current[index] = reference[index]
    Swag.require(not H264.preferShiftedInterPrediction(current.buffer, reference.buffer,
                                                       64, 64, 2, 2, -16, -8))
    Swag.require(not H264.preferShiftedInterPrediction(current.buffer, reference.buffer,
                                                       62, 62, 3, 3, -16, -8))
    Swag.require(not H264.preferShiftedInterPrediction(current.buffer, reference.buffer,
                                                       64, 64, 2, 2, 0, 0))
}

// Rough cost on a 4K screen with four moving tiles; no CI timing threshold.
#[Swag.TestTag("stress")]
#test
{
    const Width = 3840'u64
    const Height = 2160'u64
    const Tile = 512'u64
    var reference: Array'u8
    var current: Array'u8
    reference.resize(Width * Height)
    current.resize(Width * Height)
    for index in reference.count
    {
        reference[index] = 100
        current[index] = 105
    }
    for quadrant in 4'u64
    {
        let oldX = (quadrant & 1) * 1_920 + 32
        let oldY = (quadrant >> 1) * 1_080 + 32
        for row in Tile
        {
            for column in Tile
            {
                let value = cast(u8, (column * 7 + row * 11) & 255)
                let old = (oldY + row) * Width + oldX + column
                let shifted = (oldY + 8 + row) * Width + oldX + 16 + column
                reference[old] = cast(u8, Math.min(cast(u32, value) +
                                                    cast(u32, column & 1), 255))
                current[shifted] = value
            }
        }
    }
    var watch: Time.Stopwatch
    var accepted = 0'u64
    watch.start()
    for mbY in Height / 16
    {
        for mbX in Width / 16
        {
            if H264.preferShiftedInterPrediction(current.storage(), reference.storage(),
                                                 cast(s32, Width), cast(s32, Height),
                                                 cast(u32, mbX), cast(u32, mbY), -16, -8) do
                accepted += 1
        }
    }
    watch.stop()
    Console.printf("H264 4K sparse diagonal search: % candidates in % us\n",
                   accepted, watch.elapsedMicroseconds())
    Swag.require(accepted > 2_000 and accepted < 6_000)
}
