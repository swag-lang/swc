#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// Compares the 32-bit downsampler with the byte-copy reference at virtual-desktop size.
#[Swag.TestTag("stress")]
#test
{
    const SourceWidth = 7680'u64
    const SourceHeight = 2168'u64
    const OutputWidth = 4096'u64
    const OutputHeight = 1156'u64
    const Iterations = 16'u64
    var source = Image.create(cast(s32, SourceWidth), cast(s32, SourceHeight), .BGRA8)
    var output = Image.create(cast(s32, OutputWidth), cast(s32, OutputHeight), .BGRA8)
    var serialOutput = Image.create(cast(s32, OutputWidth), cast(s32, OutputHeight), .BGRA8)
    var reference = Image.create(cast(s32, OutputWidth), cast(s32, OutputHeight), .BGRA8)
    let pixels = cast([*] u32, source.pixels.storage())
    for index in SourceWidth * SourceHeight do
        pixels[index] = cast(u32, (index * 2_654_435_761'u64) >> 16)

    var columns: Array'u32
    columns.resize(OutputWidth)
    for column in OutputWidth do
        columns[column] = cast(u32, column * SourceWidth / OutputWidth)

    var watch: Time.Stopwatch
    watch.start()
    for Iterations do
        reduceBgraNearest(&source, &output, columns.storage())
    watch.stop()
    let parallelMicros = watch.elapsedMicroseconds()

    let sourcePixels = cast(const [*] u32, source.pixels.storage())
    let serialPixels = cast([*] u32, serialOutput.pixels.storage())
    let columnPixels = columns.storage()
    watch.restart()
    for Iterations
    {
        for row in OutputHeight
        {
            let inputRow = sourcePixels + (row * SourceHeight / OutputHeight) * SourceWidth
            let outputRow = serialPixels + row * OutputWidth
            for column in OutputWidth do
                outputRow[column] = inputRow[columnPixels[column]]
        }
    }
    watch.stop()
    let serialMicros = watch.elapsedMicroseconds()

    let input = source.pixels.storage()
    let target = reference.pixels.storage()
    watch.restart()
    for Iterations
    {
        for row in OutputHeight
        {
            let inputRow = input + (row * SourceHeight / OutputHeight) * SourceWidth * 4
            let targetRow = target + row * OutputWidth * 4
            for column in OutputWidth do
                Memory.copy(targetRow + column * 4, inputRow + columns[column] * 4, 4)
        }
    }
    watch.stop()
    let referenceMicros = watch.elapsedMicroseconds()

    Swag.require(Slice.equals(output.pixels.toSlice(), reference.pixels.toSlice()))
    Swag.require(Slice.equals(serialOutput.pixels.toSlice(), reference.pixels.toSlice()))
    Console.printf("Virtual desktop BGRA reduction: parallel % us, serial % us, byte-copy % us for % frames\n",
                   parallelMicros, serialMicros, referenceMicros, Iterations)
}
