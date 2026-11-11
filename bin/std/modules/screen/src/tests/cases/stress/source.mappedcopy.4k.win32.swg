#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

using Swag, Core

// Measures pitched top-down readback into a bottom-up virtual-desktop image.
#[Swag.TestTag("stress")]
#test
{
    const Width = 7680'u64
    const Height = 2168'u64
    const SourcePitch = Width * 4 + 256
    const DestinationPitch = Width * 4 + 128
    const RowBytes = Width * 4
    const Iterations = 16'u64
    var source: Array'u8
    var output: Array'u8
    var reference: Array'u8
    source.resize(SourcePitch * Height)
    output.resize(DestinationPitch * Height)
    reference.resize(DestinationPitch * Height)
    Memory.set(output.storage(), 0x5A, output.count)
    Memory.set(reference.storage(), 0x5A, reference.count)
    for row in Height do
        Memory.set(source.storage() + row * SourcePitch, cast(u8, row % 256), RowBytes)

    let outputBottom = output.storage() + (Height - 1) * DestinationPitch
    var watch: Time.Stopwatch
    watch.start()
    for Iterations do
        copyMappedBgraRows(outputBottom, DestinationPitch, source.storage(), SourcePitch,
                           RowBytes, Height)
    watch.stop()
    let parallelMicros = watch.elapsedMicroseconds()

    let referenceBottom = reference.storage() + (Height - 1) * DestinationPitch
    watch.restart()
    for Iterations
    {
        for row in Height do
            Memory.copy(referenceBottom - row * DestinationPitch,
                        source.storage() + row * SourcePitch, RowBytes)
    }
    watch.stop()
    let serialMicros = watch.elapsedMicroseconds()

    Swag.require(Slice.equals(output.toSlice(), reference.toSlice()))
    Console.printf("Virtual desktop pitched BGRA copy: parallel % us, serial % us for % frames\n",
                   parallelMicros, serialMicros, Iterations)
}
