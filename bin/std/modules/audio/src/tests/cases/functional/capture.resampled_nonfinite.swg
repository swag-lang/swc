#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Non-finite float samples are zeroed before they can contaminate the resampler history.
#test
{
    var input:     [256] f32
    var sanitized: [256] f32
    for frame in 128
    {
        let value = cast(f32, Math.sin(Math.ConstF64.TwoPi * 1_000.0 * frame / 96_000.0))
        input[frame * 2]     = value
        input[frame * 2 + 1] = -value
    }

    input[0]  = cast #bit (f32, 0x7FC0_0000'u32)
    input[3]  = cast #bit (f32, 0x7F80_0000'u32)
    input[62] = cast #bit (f32, 0xFF80_0000'u32)
    for index in input.count do
        sanitized[index] = Math.isFinite(input[index]) ? input[index] : 0

    var actualQueue   = expect CaptureQueue.create(48_000, 2, 0, 10_000_000)
    var expectedQueue = expect CaptureQueue.create(48_000, 2, 0, 10_000_000)
    var actual        = expect CaptureResampledFeeder.create(&actualQueue, 96_000)
    var expected      = expect CaptureResampledFeeder.create(&expectedQueue, 96_000)
    expect actual.pushFloat32(Swag.makeSlice(&input[0], input.count), 0, 0)
    expect expected.pushFloat32(Swag.makeSlice(&sanitized[0], sanitized.count), 0, 0)
    expect actual.finish()
    expect expected.finish()

    var actualPcm:   Array's16
    var expectedPcm: Array's16
    var block:       Array's16
    var info:        CaptureBlock
    while actualQueue.pop(&block, &info) do
        actualPcm.add(block.toSlice())
    while expectedQueue.pop(&block, &info) do
        expectedPcm.add(block.toSlice())
    Swag.require(Slice.equals(actualPcm.toSlice(), expectedPcm.toSlice()))
}
