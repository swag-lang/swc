#global if #command == Swag.CompilerCommand.Test
#global private

using Core

// The 16-bit count permits 65,535 entries, which require 65,536 offsets.
#[Swag.TestTag("stress")]
#test
{
    const Count = 65535'u64
    const DataStart = 3 + (Count + 1) * 3
    var bytes: Array'u8
    bytes.resize(DataStart + Count)
    bytes[0] = 0xFF
    bytes[1] = 0xFF
    bytes[2] = 3
    for i in Count + 1
    {
        let offset = i + 1
        bytes[3 + i * 3]     = cast(u8, offset >> 16)
        bytes[3 + i * 3 + 1] = cast(u8, (offset >> 8) & 0xFF)
        bytes[3 + i * 3 + 2] = cast(u8, offset & 0xFF)
    }
    for i in Count do
        bytes[DataStart + i] = cast(u8, i % 251)

    let index = expect readCffIndex(bytes.toSlice(), 0)
    Swag.assert(index.count() == Count)
    Swag.assert(index.starts.count == Count + 1)
    Swag.assert(index.end == bytes.count)
    for i in Count
    {
        let item = expect index.item(bytes.toSlice(), cast(u32, i))
        Swag.assert(item.count == 1 and item[0] == cast(u8, i % 251))
    }
}
