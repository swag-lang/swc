using Swag, Core

// Larger fonts can contain megabytes of tables outside the selected face or instance.
const MinFontCompactionSize = 1024'u64 * 1024
private const TagGvar       = imageTag('g'u32, 'v'u32, 'a'u32, 'r'u32)

private func isTrueTypeSfnt(signature: u32)->bool => signature == TAG_SFNT or signature == TAG_TRUE

private struct FontTable
{
    sourceOffset:    u32
    length:          u32
    directoryOffset: u32
}

private struct FontInput
{
    length: u64
    stream: *File.FileStream?
    bytes:  const [..] u8?
}

impl FontInput
{
    mtd readAt(offset: u64, buffer: [..] u8) fail
    {
        if offset > .length or buffer.count > .length - offset do
            try fault(0x03)
        if let stream = .stream
        {
            if (try readFontRange(stream, offset, buffer)) != buffer.count do
                try fault(0x03)
        }
        else
        {
            let source = unwrap .bytes
            Memory.copy(buffer.buffer, source.buffer + offset, buffer.count)
        }
    }
}

// Copies one SFNT into an owned buffer and adjusts the original directory offsets.
private func compactSfnt(source: *FontInput, memberOffset: u64, header: const [..] u8, collection: bool)->Array'u8 fail
{
    let trueType      = isTrueTypeSfnt(try readU32(header, 0))
    let tableCount    = try readU16(header, 4)
    let directorySize = header.count + cast(u64, tableCount) * 16
    if directorySize == header.count or directorySize >= source.length do
        return {}

    var result: #returntype
    result.add(header)
    result.resize(directorySize)
    try source.readAt(memberOffset + header.count, result.toSlice()[header.count to])

    var tables: Array'FontTable
    tables.reserve(tableCount)
    var memberSize        = directorySize
    var omittedVariations = false
    for tableIndex in tableCount
    {
        let record = cast(u32, header.count) + cast(u32, tableIndex) * 16
        let offset = try readU32(result.toSlice(), record + 8)
        var length = try readU32(result.toSlice(), record + 12)
        if offset > source.length or length > source.length - offset do
            try fault(0x03)

        // The default instance reads its outlines from glyf. Preserve the directory
        // and its range validation while omitting the unused glyph variation data.
        if trueType and
           length and
           (collection or length >= MinFontCompactionSize) and
           (try readU32(result.toSlice(), record)) == TagGvar
        {
            Memory.clear(unwrap result.buffer + record + 12, 4)
            length = 0
            omittedVariations = true
        }

        tables.add({offset, length, record})
        memberSize += (cast(u64, length) + 3) & ~3'u64
    }

    if (not collection and not omittedVariations) or
       memberSize >= source.length or
       memberSize > Swag.U32.Max do
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

private func readCollectionMember(source: *FontInput, faceIndex, faceCount: u32)->Array'u8 fail
{
    if faceIndex >= faceCount do
        try fault(0x0F)

    var memberAddress: [4] u8
    try source.readAt(12 + cast(u64, faceIndex) * 4, memberAddress)
    let memberOffset = cast(u64, try readU32(memberAddress, 0))

    var header: [12] u8
    try source.readAt(memberOffset, header)
    try checkSfntVersion(header, 0)
    return try compactSfnt(source, memberOffset, header, collection: true)
}

func readFontFile(path: string, faceIndex: u32)->{ bytes: Array'u8, faceIndex: u32 } fail
{
    var stream = try File.openRead(path)
    let length = try stream.size()
    if length >= MinFontCompactionSize and stream.canSeek
    {
        var header: [12] u8
        if try stream.readExact(header)
        {
            let signature = try readU32(header, 0)
            var source    = FontInput{length: length, stream: &stream}
            var member: Array'u8
            if signature == TAG_TTCF do
                member = try readCollectionMember(&source, faceIndex, try readU32(header, 8))
            elif not faceIndex and isTrueTypeSfnt(signature) do
                member = try compactSfnt(&source, 0, header, collection: false)
            if not member.isEmpty() do
                return {bytes: #move member, faceIndex: 0}
        }

        try stream.seek(.Begin, 0)
    }

    var bytes = try readCompleteFont(&stream, length)
    return {bytes: #move bytes, faceIndex: faceIndex}
}

func readFontSnapshot(path: string)->Array'u8 fail
{
    var stream = try File.openRead(path)
    return try readCompleteFont(&stream, try stream.size())
}

private func readCompleteFont(stream: *File.FileStream, length: u64)->Array'u8 fail
{
    var result: #returntype
    if not length do
        return result

    result.reserve(length)
    let buffer = Swag.makeSlice(unwrap result.buffer, length)
    result.count = try readFontRange(stream, 0, buffer, cursorAtOffset: true)
    return result
}

// Compacts a member when the caller already holds the collection bytes.
func copyFontMember(bytes: const [..] u8, faceIndex: u32)->Array'u8 fail
{
    if bytes.count < MinFontCompactionSize do
        return {}
    let signature = try readU32(bytes, 0)
    var source    = FontInput{length: bytes.count, bytes: bytes}
    if signature == TAG_TTCF do
        return try readCollectionMember(&source, faceIndex, try readU32(bytes, 8))
    if not faceIndex and isTrueTypeSfnt(signature) do
        return try compactSfnt(&source, 0, try getSlice(bytes, 0, 12), collection: false)
    return {}
}

private func readFontRange(stream: *File.FileStream, offset: u64, buffer: [..] u8, cursorAtOffset = false)->u64 fail
{
    #static if #os == Swag.TargetOs.Linux
    {
        let workers = stream.canSeek ? fontReadWorkers(buffer.count) : 0
        if workers > 1
        {
            let parallelRead = try readParallelFontRange(stream, offset, buffer, workers)
            if parallelRead.ok do
                return parallelRead.count
        }
    }

    if not cursorAtOffset do
        try stream.seek(.Begin, offset)
    return try stream.read(buffer)
}
