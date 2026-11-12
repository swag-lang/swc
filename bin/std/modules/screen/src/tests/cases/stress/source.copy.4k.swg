#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// Measures the cache-to-caller copy at virtual-desktop size against a serial copy.
#[Swag.TestTag("stress")]
#test
{
    const Width = 7680'u64
    const Height = 2168'u64
    const Iterations = 16'u64
    var source = Image.create(cast(s32, Width), cast(s32, Height), .BGRA8)
    var output = Image.create(cast(s32, Width), cast(s32, Height), .BGRA8)
    var reference = Image.create(cast(s32, Width), cast(s32, Height), .BGRA8)
    let pixels = cast([*] u32, source.pixels.storage())
    for index in Width * Height do
        pixels[index] = cast(u32, (index * 2_654_435_761'u64) & 0xFFFF_FFFF)

    var watch: Time.Stopwatch
    watch.start()
    for Iterations do
        copyFrameBytes(output.pixels.storage(), source.pixels.storage(), source.byteCount)
    watch.stop()
    let parallelMicros = watch.elapsedMicroseconds()

    watch.restart()
    for Iterations do
        Memory.copy(reference.pixels.storage(), source.pixels.storage(), source.byteCount)
    watch.stop()
    let serialMicros = watch.elapsedMicroseconds()

    Swag.require(Slice.equals(output.pixels.toSlice(), reference.pixels.toSlice()))
    Console.printf("Virtual desktop BGRA copy: parallel % us, serial % us for % frames\n",
                   parallelMicros, serialMicros, Iterations)
}
