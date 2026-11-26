using Swag, Core

// Header and directory fields needed to rebuild a WOFF1 font as sfnt.
struct WoffHeader
{
    flavor:           u32
    length:           u32
    totalSfntSize:    u32
    numTables:        u16
    fontMajorVersion: u16
    fontMinorVersion: u16
}

struct WoffTableRecord
{
    tag:        u32
    offset:     u32
    compLength: u32
    origLength: u32
    checksum:   u32
}

// WOFF blocks are four-byte aligned with at most three zero padding bytes.
func checkWoffPadding(block: const [..] u8, start, end: u64) fail
{
    if end < start or end - start > 3 do
        try fault(0x08)

    var offset = start
    while offset < end
    {
        if try readU8(block, offset) != 0 do
            try fault(0x08)
        offset += 1
    }
}

// Parses the WOFF1 header and table directory without expanding compressed tables.
func readWoffDirectory(block: const [..] u8)->{ header: WoffHeader, tables: Array'WoffTableRecord } fail
{
    var result: #returntype
    if block.count < 44 do
        try fault(0x08)
    if try readU32(block, 0) != TAG_WOFF do
        try fault(0x08)

    result.header.flavor           = try readU32(block, 4)
    result.header.length           = try readU32(block, 8)
    result.header.numTables        = try readU16(block, 12)
    result.header.totalSfntSize    = try readU32(block, 16)
    result.header.fontMajorVersion = try readU16(block, 20)
    result.header.fontMinorVersion = try readU16(block, 22)

    if result.header.flavor != TAG_SFNT and
       result.header.flavor != TAG_TRUE and
       result.header.flavor != TAG_OTTO do
        try fault(0x08)

    // The reconstructed sfnt searchRange is stored in 16 bits, so at most 4095
    // directory entries can be represented without overflowing it.
    if result.header.length != block.count or
       (try readU16(block, 14)) != 0 or
       not result.header.numTables or
       result.header.numTables > 4095 do
        try fault(0x08)

    let directoryEnd = 44'u64 + cast(u64, result.header.numTables) * 20
    try assertRange(block, 44, directoryEnd - 44)

    // Optional metadata and private blocks must use an all-zero pair when absent,
    // and otherwise fit in the file after the fixed header and directory.
    let metadataOffset     = try readU32(block, 24)
    let metadataLength     = try readU32(block, 28)
    let metadataOrigLength = try readU32(block, 32)
    if metadataOffset == 0
    {
        if metadataLength or metadataOrigLength do
            try fault(0x08)
    }
    else
    {
        if not metadataLength or
           not metadataOrigLength or
           metadataOffset < directoryEnd or
           (metadataOffset & 3) != 0 do
            try fault(0x08)
        try assertRange(block, metadataOffset, metadataLength)
    }

    let privateOffset = try readU32(block, 36)
    let privateLength = try readU32(block, 40)
    if privateOffset == 0
    {
        if privateLength do
            try fault(0x08)
    }
    else
    {
        if not privateLength or privateOffset < directoryEnd or (privateOffset & 3) != 0 do
            try fault(0x08)
        try assertRange(block, privateOffset, privateLength)
    }

    result.tables.resize(result.header.numTables)
    var physicalOrder: Array'u64
    physicalOrder.reserve(result.header.numTables)
    var previousTag      = 0'u32
    var expectedSfntSize = 12'u64 + cast(u64, result.header.numTables) * 16
    for index in result.header.numTables
    {
        let base = 44'u64 + cast(u64, index) * 20
        var record: WoffTableRecord
        record.tag        = try readU32(block, base)
        record.offset     = try readU32(block, base + 4)
        record.compLength = try readU32(block, base + 8)
        record.origLength = try readU32(block, base + 12)
        record.checksum   = try readU32(block, base + 16)

        if (index and record.tag <= previousTag) or
           record.compLength > record.origLength or
           record.offset < directoryEnd or
           (record.offset & 3) != 0 do
            try fault(0x08)

        try assertRange(block, record.offset, record.compLength)
        physicalOrder.add((cast(u64, record.offset) << 32) | record.compLength)
        previousTag          = record.tag
        expectedSfntSize     += (cast(u64, record.origLength) + 3) & ~3'u64
        result.tables[index] = record
    }

    if expectedSfntSize != result.header.totalSfntSize do
        try fault(0x08)

    // Check padding and overlap in file order. At a shared offset, visit empty blocks first.
    physicalOrder.sort()
    var previousDataEnd = directoryEnd
    for entry in physicalOrder
    {
        let offset = entry >> 32
        let length = entry & Swag.U32.Max
        try checkWoffPadding(block, previousDataEnd, offset)
        previousDataEnd = offset + length
    }

    let metadataEnd = cast(u64, metadataOffset) + metadataLength
    let privateEnd  = cast(u64, privateOffset) + privateLength
    if (metadataOffset != 0 and cast(u64, metadataOffset) < previousDataEnd) or
       (privateOffset != 0 and cast(u64, privateOffset) < previousDataEnd) or
       (privateOffset != 0 and metadataOffset != 0 and cast(u64, privateOffset) < metadataEnd) do
        try fault(0x08)
    var lastBlockEnd = previousDataEnd
    if metadataOffset
    {
        try checkWoffPadding(block, previousDataEnd, metadataOffset)
        lastBlockEnd = metadataEnd
    }

    if privateOffset
    {
        let privatePaddingStart = metadataOffset ? metadataEnd : previousDataEnd
        try checkWoffPadding(block, privatePaddingStart, privateOffset)
        lastBlockEnd = privateEnd
    }

    try checkWoffPadding(block, lastBlockEnd, result.header.length)

    return result
}

private func writeWoffU16(bytes: *Array'u8, offset: u64, value: u16)
{
    bytes[offset]     = cast(u8, value >> 8)
    bytes[offset + 1] = cast(u8, value & 0xFF)
}

private func writeWoffU32(bytes: *Array'u8, offset: u64, value: u32)
{
    bytes[offset]     = cast(u8, (value >> 24) & 0xFF)
    bytes[offset + 1] = cast(u8, (value >> 16) & 0xFF)
    bytes[offset + 2] = cast(u8, (value >> 8) & 0xFF)
    bytes[offset + 3] = cast(u8, value & 0xFF)
}

// Rebuilds one WOFF1 font into the sfnt representation shared by the face parser.
func inflateWoff(block: const [..] u8)->Array'u8 fail
{
    let directory = try readWoffDirectory(block)
    let header    = directory.header

    var result: #returntype
    result.reserve(header.totalSfntSize)
    result.resize(12'u64 + cast(u64, header.numTables) * 16)
    writeWoffU32(&result, 0, header.flavor)
    writeWoffU16(&result, 4, header.numTables)

    var searchPower   = 1'u32
    var entrySelector = 0'u16
    while searchPower * 2 <= header.numTables
    {
        searchPower   *= 2
        entrySelector += 1
    }

    let searchRange = searchPower * 16
    writeWoffU16(&result, 6, cast(u16, searchRange))
    writeWoffU16(&result, 8, entrySelector)
    writeWoffU16(&result, 10, cast(u16, cast(u32, header.numTables) * 16 - searchRange))

    var zlib: Compress.ZLib
    for record, index in directory.tables
    {
        let tableOffset     = result.count
        let directoryOffset = 12'u64 + cast(u64, index) * 16
        writeWoffU32(&result, directoryOffset, record.tag)
        writeWoffU32(&result, directoryOffset + 4, record.checksum)
        writeWoffU32(&result, directoryOffset + 8, cast(u32, tableOffset))
        writeWoffU32(&result, directoryOffset + 12, record.origLength)

        let bytes = try getSlice(block, record.offset, record.compLength)
        if record.compLength == record.origLength do
            result.add(bytes)
        else do
            try zlib.decompress(&result, bytes, maxOutputSize: record.origLength)
        if result.count - tableOffset != record.origLength do
            try fault(0x08)

        result.resize((result.count + 3) & ~3'u64)
    }

    return result
}
