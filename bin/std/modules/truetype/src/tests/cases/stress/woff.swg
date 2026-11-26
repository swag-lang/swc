#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Independent compressed blocks fill their own table ranges and zero their padding.
#[Swag.TestTag("stress")]
#test
{
    const HeaderSize = 60'u64
    const LargeSize  = 2'u64 * 1024 * 1024 + 1
    const LargeSpan  = LargeSize + 3
    const RandomSize = 1024'u64 * 1024 + 32 * 1024
    var original: Array'u8
    original.resize(HeaderSize + 4 + LargeSpan * 2)
    writeBigU32(&original, 0, TAG_SFNT)
    writeBigU16(&original, 4, 3)
    writeBigU16(&original, 6, 32)
    writeBigU16(&original, 8, 1)
    writeBigU16(&original, 10, 16)

    let offsets:   [3] u64 = [HeaderSize, HeaderSize + 4, HeaderSize + 4 + LargeSpan]
    var generator: Random.Generator
    generator.seedU32(3014)
    for offset, index in offsets
    {
        let base   = 12 + index * 16
        let length = index ? LargeSize : 3
        writeBigU32(&original, base, imageTag('t', 'a', 'b', '0' + cast(u32, index)))
        writeBigU32(&original, base + 8, cast(u32, offset))
        writeBigU32(&original, base + 12, cast(u32, length))
        let seededBytes = index ? RandomSize : 3
        for position in seededBytes do
            original[offset + position] = cast(u8, generator.nextU32() & 0xFF)
    }

    var woff      = expect buildWoffFont(original.toSlice(), reverseBlocks: true)
    let directory = expect readWoffDirectory(woff.toSlice())
    Swag.require(directory.largeCompressedTables == 2)
    let restored = expect inflateWoff(woff.toSlice())
    Swag.require(Slice.equals(original.toSlice(), restored.toSlice()))

    // A table's checksum must still be verified after the other workers finish.
    let badTable     = directory.tables[2]
    let checksumByte = cast(u64, badTable.offset) + badTable.compLength - 1
    woff[checksumByte] ^= 1
    var outcome: Swag.Error
    discard catch inflateWoff(woff.toSlice()) as outcome
    Swag.require(outcome.value() is Errors.InvalidFormatError)
}
