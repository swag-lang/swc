#global if #command == Swag.CompilerCommand.Test

using ExportApi

struct MemoryFields
{
    before:     u64
    refIndex:   [2, 4] s8
    contextRef: [2, 4] s8
    intraModes: [16] u8
    after:      u64
}

func assertBytes(buffer: const [..] u8, prefix, value, suffix: u8, first, count: u64)
{
    for byte, index in buffer
    {
        let expected = index < first ? prefix : index < first + count ? value : suffix
        @assert(byte == expected)
    }
}

func prepareMemoryFields(fields: *MemoryFields)
{
    depMemorySet(&fields.refIndex, 0xFF, #sizeof(fields.refIndex))
    depMemorySet(&fields.contextRef, 0xFF, #sizeof(fields.contextRef))
    depMemorySet(&fields.intraModes, 2, #sizeof(fields.intraModes))
}

func extendMemoryRow(row: [*] u8, width: u32, padding: u64)
{
    depMemorySet(row - padding, row[0], padding)
    depMemorySet(row + cast(u64) width, row[cast(u64) width - 1], padding)
}

func extendMemoryPlane(base: [*] u8, width, height: u32)
{
    const Padding = 32'u64
    const Stride  = Padding * 2 + 4
    var row = base + Padding
    for height
    {
        depMemorySet(row - Padding, row[0], Padding)
        depMemorySet(row + cast(u64) width, row[cast(u64) width - 1], Padding)
        row += Stride
    }
}

#test
{
    var clearBuffer: [40] u8
    @memset(&clearBuffer, 0xA5, #sizeof(clearBuffer))
    depMemoryClear(&clearBuffer[3], 33)
    assertBytes(clearBuffer[to], 0xA5, 0, 0xA5, 3, 33)

    var setBuffer: [40] u8
    @memset(&setBuffer, 0xA5, #sizeof(setBuffer))
    depMemorySet(&setBuffer[3], 0x6D, 33)
    assertBytes(setBuffer[to], 0xA5, 0x6D, 0xA5, 3, 33)

    const source: [40] u8 = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39]
    var copied: [40] u8
    @memset(&copied, 0xA5, #sizeof(copied))
    depMemoryCopy(&copied[3], &source[2], 33)
    @assert(copied[2] == 0xA5 and copied[36] == 0xA5)
    @assert(depMemoryCompare(&copied[3], &source[2], 33) == 0)

    var moved = source
    depMemoryMove(&moved[3], &moved[0], 33)
    @assert(moved[2] == 2 and moved[3] == 0 and moved[35] == 32 and moved[36] == 36)
    @assert(depMemoryCompare(&moved[3], &source[0], 33) == 0)
    @assert(depMemoryCompare(&moved[3], &source[1], 33) < 0)

    var fields: MemoryFields
    fields.before = 0x1122334455667788
    fields.after  = 0x8877665544332211
    prepareMemoryFields(&fields)
    for value in fields.refIndex do
        @assert(value == -1)
    for value in fields.contextRef do
        @assert(value == -1)
    for value in fields.intraModes do
        @assert(value == 2)
    @assert(fields.before == 0x1122334455667788)
    @assert(fields.after == 0x8877665544332211)

    var paddedRow: [32] u8
    @memset(&paddedRow, 0xA5, #sizeof(paddedRow))
    paddedRow[8]  = 0x31
    paddedRow[9]  = 0x42
    paddedRow[10] = 0x53
    paddedRow[11] = 0x64
    extendMemoryRow(&paddedRow[8], 4, 8)
    for value in paddedRow[0 until 8] do
        @assert(value == 0x31)
    for value in paddedRow[12 until 20] do
        @assert(value == 0x64)
    @assert(paddedRow[20] == 0xA5)

    var plane: [136] u8
    plane[32]  = 0x11
    plane[33]  = 0x22
    plane[34]  = 0x33
    plane[35]  = 0x44
    plane[100] = 0x55
    plane[101] = 0x66
    plane[102] = 0x77
    plane[103] = 0x88
    extendMemoryPlane(&plane[0], 4, 2)
    for value in plane[0 until 32] do
        @assert(value == 0x11)
    for value in plane[36 until 68] do
        @assert(value == 0x44)
    for value in plane[68 until 100] do
        @assert(value == 0x55)
    for value in plane[104 until 136] do
        @assert(value == 0x88)
}
