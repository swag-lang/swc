#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// Compares the 32-bit downsampler with the byte-copy reference at virtual-desktop size.
#[Swag.TestTag("stress")]
#test
{
    const SourceWidth  = 7680'u64
    const SourceHeight = 2168'u64
    const OutputWidth  = 4096'u64
    const OutputHeight = 1156'u64
    var source       = Image.create(cast(s32, SourceWidth), cast(s32, SourceHeight), .BGRA8)
    var output       = Image.create(cast(s32, OutputWidth), cast(s32, OutputHeight), .BGRA8)
    var reference    = Image.create(cast(s32, OutputWidth), cast(s32, OutputHeight), .BGRA8)
    let pixels       = cast([*] u32, source.pixels.storage())
    for index in SourceWidth * SourceHeight do
        pixels[index] = cast #wrap (u32, (index * 2_654_435_761'u64) >> 16)

    var columns: Array'u32
    columns.resize(OutputWidth)
    for column in OutputWidth do
        columns[column] = cast(u32, column * SourceWidth / OutputWidth)

    reduceBgraNearest(&source, &output, columns.storage())

    let input  = source.pixels.storage()
    let target = reference.pixels.storage()
    for row in OutputHeight
    {
        let inputRow  = input + (row * SourceHeight / OutputHeight) * SourceWidth * 4
        let targetRow = target + row * OutputWidth * 4
        for column in OutputWidth do
            Memory.copy(targetRow + column * 4, inputRow + columns[column] * 4, 4)
    }

    Swag.require(Slice.equals(output.pixels.toSlice(), reference.pixels.toSlice()))
}
