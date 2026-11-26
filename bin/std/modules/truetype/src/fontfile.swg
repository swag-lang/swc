using Swag, Core

// A small collection can be read in one cheaper operation. Larger files can contain
// megabytes of tables that the requested member never references.
const MinCollectionReadSize = 1024'u64 * 1024

private struct CollectionTable
{
    sourceOffset:    u32
    length:          u32
    directoryOffset: u32
}

private struct CollectionSource
{
    length: u64
    stream: *File.FileStream?
    bytes:  const [..] u8?
}

impl CollectionSource
{
    mtd readAt(offset: u64, buffer: [..] u8) fail
    {
        if offset > .length or buffer.count > .length - offset do
            try fault(0x03)
        if let stream = .stream
        {
            if not (try stream.readExactAt(offset, buffer)) do
                try fault(0x03)
        }
        else
        {
            let source = unwrap .bytes
            Memory.copy(buffer.buffer, source.buffer + offset, buffer.count)
        }
    }
}

// Copies one member into its own SFNT buffer. The directory keeps its original table
// order, with offsets adjusted to the copied tables. An empty result requests a full
// copy when a member cannot be represented in a smaller buffer.
private func readCollectionMember(source: *CollectionSource, faceIndex, faceCount: u32)->Array'u8 fail
{
    if faceIndex >= faceCount do
        try fault(0x0F)

    var memberAddress: [4] u8
    try source.readAt(12 + cast(u64, faceIndex) * 4, memberAddress)
    let memberOffset = cast(u64, try readU32(memberAddress, 0))

    var header: [12] u8
    try source.readAt(memberOffset, header)
    try checkSfntVersion(header, 0)
    let tableCount    = try readU16(header, 4)
    let directorySize = header.count + cast(u64, tableCount) * 16
    if directorySize == header.count or directorySize >= source.length do
        return {}

    var result: #returntype
    result.add(header)
    result.resize(directorySize)
    try source.readAt(memberOffset + header.count, result.toSlice()[header.count to])

    var tables: Array'CollectionTable
    tables.reserve(tableCount)
    var memberSize = directorySize
    for tableIndex in tableCount
    {
        let record = cast(u32, header.count) + cast(u32, tableIndex) * 16
        let offset = try readU32(result.toSlice(), record + 8)
        let length = try readU32(result.toSlice(), record + 12)
        if offset > source.length or length > source.length - offset do
            try fault(0x03)
        tables.add({offset, length, record})
        memberSize += (cast(u64, length) + 3) & ~3'u64
    }

    if memberSize >= source.length or memberSize > Swag.U32.Max do
        return {}

    // Read in file order even when the collection's directory is sorted by tag.
    tables.sort(func(a, b) => a.sourceOffset <=> b.sourceOffset)
    result.reserve(memberSize)
    let bytes  = unwrap result.buffer
    var target = directorySize
    for table in tables
    {
        if table.length do
            try source.readAt(table.sourceOffset, Swag.makeSlice(bytes + target, table.length))

        let encodedOffset = Math.nativeToBigEndian(cast(u32, target))
        Memory.copy(bytes + table.directoryOffset + 8, &encodedOffset, 4)
        let padding = (4 - (table.length & 3)) & 3
        if padding do
            Memory.clear(bytes + target + table.length, padding)
        target += cast(u64, table.length) + padding
    }

    result.count = memberSize
    return result
}

func readFontFile(path: string, faceIndex: u32)->{ bytes: Array'u8, faceIndex: u32 } fail
{
    var stream = try File.openRead(path)
    let length = try stream.size()
    if length >= MinCollectionReadSize and stream.canSeek
    {
        var header: [12] u8
        if (try stream.readExact(header)) and (try readU32(header, 0)) == TAG_TTCF
        {
            var source = CollectionSource{length: length, stream: &stream}
            var member = try readCollectionMember(&source, faceIndex, try readU32(header, 8))
            if not member.isEmpty() do
                return {bytes: #move member, faceIndex: 0}
        }

        try stream.seek(.Begin, 0)
    }

    var result: #returntype
    result.faceIndex = faceIndex
    if length
    {
        result.bytes.reserve(length)
        result.bytes.count = try stream.read(unwrap result.bytes.buffer, length)
    }

    return result
}

// Compacts a member when the caller already holds the collection bytes.
func copyFontMember(bytes: const [..] u8, faceIndex: u32)->Array'u8 fail
{
    if bytes.count < MinCollectionReadSize or (try readU32(bytes, 0)) != TAG_TTCF do
        return {}
    var source = CollectionSource{length: bytes.count, bytes: bytes}
    return try readCollectionMember(&source, faceIndex, try readU32(bytes, 8))
}
