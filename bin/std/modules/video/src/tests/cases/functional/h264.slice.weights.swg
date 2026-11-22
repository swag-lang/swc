#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Core.Errors

private func assertInvalidChromaOffset(payload: const [..] u8)
{
    var slice: H264.Slice
    slice.header.type        = H264.SliceTypeP
    slice.header.refCount[0] = 1
    slice.bits.init(payload)

    var rejected: Swag.Error
    discard catch slice.parseWeights() as rejected
    Swag.require(rejected.value() is InvalidFormatError)
}

// Both weighted chroma offsets use the same signed range as luma offsets.
#test
{
    const CbOffsetTooHigh: [3] u8 = [0x60, 0x10, 0x0C]
    const CrOffsetTooHigh: [3] u8 = [0x78, 0x04, 0x00]
    assertInvalidChromaOffset(CbOffsetTooHigh)
    assertInvalidChromaOffset(CrOffsetTooHigh)
}
