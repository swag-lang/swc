#global internal

using Core

private const ZipLocalSignature     = 0x04034B50'u32
private const ZipDirectorySignature = 0x02014B50'u32
private const ZipEndSignature       = 0x06054B50'u32
private const Zip64EndSignature     = 0x06064B50'u32
private const Zip64LocatorSignature = 0x07064B50'u32
private const ZipEndSearch          = 0xFFFF + 22'u64
private const ZipEntryLimit         = 250_000'u64
private const ZipDirectoryLimit     = 512 * 1024 * 1024'u64
private const ZipPreviewLimit       = 256 * 1024 * 1024'u64
private const ZipFlagEncrypted      = 1'u16
private const ZipFlagUtf8           = 1'u16 << 11
private const ZipValue32Overflow    = 0xFFFF_FFFF'u64
private const ZipValue16Overflow    = 0xFFFF'u64

private const ZipCp437High: [128] rune = [
    0x00C7, 0x00FC, 0x00E9, 0x00E2, 0x00E4, 0x00E0, 0x00E5, 0x00E7, 0x00EA, 0x00EB, 0x00E8, 0x00EF, 0x00EE, 0x00EC, 0x00C4, 0x00C5,
    0x00C9, 0x00E6, 0x00C6, 0x00F4, 0x00F6, 0x00F2, 0x00FB, 0x00F9, 0x00FF, 0x00D6, 0x00DC, 0x00A2, 0x00A3, 0x00A5, 0x20A7, 0x0192,
    0x00E1, 0x00ED, 0x00F3, 0x00FA, 0x00F1, 0x00D1, 0x00AA, 0x00BA, 0x00BF, 0x2310, 0x00AC, 0x00BD, 0x00BC, 0x00A1, 0x00AB, 0x00BB, 0x2591, 0x2592,
    0x2593, 0x2502, 0x2524, 0x2561, 0x2562, 0x2556, 0x2555, 0x2563, 0x2551, 0x2557, 0x255D, 0x255C, 0x255B, 0x2510, 0x2514, 0x2534,
    0x252C, 0x251C, 0x2500, 0x253C, 0x255E, 0x255F, 0x255A, 0x2554, 0x2569, 0x2566, 0x2560, 0x2550, 0x256C, 0x2567, 0x2568, 0x2564,
    0x2565, 0x2559, 0x2558, 0x2552, 0x2553, 0x256B, 0x256A, 0x2518, 0x250C, 0x2588, 0x2584, 0x258C, 0x2590, 0x2580, 0x03B1, 0x00DF,
    0x0393, 0x03C0, 0x03A3, 0x03C3, 0x00B5, 0x03C4, 0x03A6, 0x0398, 0x03A9, 0x03B4, 0x221E, 0x03C6, 0x03B5, 0x2229, 0x2261, 0x00B1,
    0x2265, 0x2264, 0x2320, 0x2321, 0x00F7, 0x2248, 0x00B0, 0x2219, 0x00B7, 0x221A, 0x207F, 0x00B2, 0x25A0, 0x00A0]

struct ZipEntry
{
    path:             String
    compressedSize:   u64
    uncompressedSize: u64
    localOffset:      u64
    crc32:            u32
    method:           u16
    flags:            u16
    isDirectory:      bool
}

struct ZipArchive
{
    entries:          Array'ZipEntry
    compressedSize:   u64
    uncompressedSize: u64
    comment:          String
}

private func zipU16(bytes: const [..] u8, at: u64)->u16 fail
{
    if at > bytes.count or 2 > bytes.count - at do
        fail Errors.InvalidFormatError{"ZIP record ends before a 16-bit field"}
    return cast(u16) bytes[at] | (cast(u16) bytes[at + 1] << 8)
}

private func zipU32(bytes: const [..] u8, at: u64)->u32 fail
{
    if at > bytes.count or 4 > bytes.count - at do
        fail Errors.InvalidFormatError{"ZIP record ends before a 32-bit field"}
    return cast(u32) bytes[at] | (cast(u32) bytes[at + 1] << 8) | (cast(u32) bytes[at + 2] << 16) | (cast(u32) bytes[at + 3] << 24)
}

private func zipU64(bytes: const [..] u8, at: u64)->u64 fail
{
    let low  = cast(u64) try zipU32(bytes, at)
    let high = cast(u64) try zipU32(bytes, at + 4)
    return low | (high << 32)
}

func zipText(bytes: const [..] u8, utf8: bool)->String
{
    if !bytes.count do
        return {}
    if utf8 and Utf8.isValid(bytes) do
        return String.from(Swag.makeString(bytes.buffer, bytes.count))

    var result: retval
    for value in bytes
    {
        if value < 0x80 do
            result += value
        else do
            result += ZipCp437High[value - 0x80]
    }

    return result
}

private func cleanZipPath(path: string)->String
{
    var result: retval
    var previousSlash = false
    for value in path
    {
        let slash = value == '/' or value == '\\'
        if slash
        {
            if result.isEmpty() or previousSlash do
                continue
            result        += '/'u8
            previousSlash = true
            continue
        }

        if value < 32 do
            result += cast(rune) 0xFFFD
        else do
            result += value
        previousSlash = false
    }

    while !result.isEmpty() and result.back() == '/' do
        result.removeBack()
    return result
}

private func applyZip64Extra(extra: const [..] u8, plain, packed, local, disk: *u64) fail
{
    var at = 0'u64
    while at + 4 <= extra.count
    {
        let kind   = try zipU16(extra, at)
        let length = cast(u64) try zipU16(extra, at + 2)
        at += 4
        if length > extra.count - at do
            fail Errors.InvalidFormatError{"ZIP extra field extends past its directory entry"}
        if kind == 1
        {
            var valueAt = at
            let end     = at + length
            if plain[] == ZipValue32Overflow
            {
                if valueAt + 8 > end do
                    fail Errors.InvalidFormatError{"ZIP64 entry is missing its uncompressed size"}
                plain[] = try zipU64(extra, valueAt)
                valueAt += 8
            }

            if packed[] == ZipValue32Overflow
            {
                if valueAt + 8 > end do
                    fail Errors.InvalidFormatError{"ZIP64 entry is missing its compressed size"}
                packed[] = try zipU64(extra, valueAt)
                valueAt  += 8
            }

            if local[] == ZipValue32Overflow
            {
                if valueAt + 8 > end do
                    fail Errors.InvalidFormatError{"ZIP64 entry is missing its local-header offset"}
                local[] = try zipU64(extra, valueAt)
                valueAt += 8
            }

            if disk[] == ZipValue16Overflow
            {
                if valueAt + 4 > end do
                    fail Errors.InvalidFormatError{"ZIP64 entry is missing its disk number"}
                disk[] = cast(u64) try zipU32(extra, valueAt)
            }

            return
        }

        at += length
    }
}

private func zipDirectoryLocation(file: *File.MappedFile, endOffset: u64, endBytes: const [..] u8, endAt: u64)->{ offset, size, count: u64 } fail
{
    var result: retval
    result.count  = cast(u64) try zipU16(endBytes, endAt + 10)
    result.size   = cast(u64) try zipU32(endBytes, endAt + 12)
    result.offset = cast(u64) try zipU32(endBytes, endAt + 16)

    if result.count != ZipValue16Overflow and result.size != ZipValue32Overflow and result.offset != ZipValue32Overflow do
        return result
    if endOffset + endAt < 20 do
        fail Errors.InvalidFormatError{"ZIP64 end locator is missing"}

    let locatorOffset = endOffset + endAt - 20
    let locator       = try file.map(locatorOffset, 20)
    if try zipU32(locator.bytes(), 0) != Zip64LocatorSignature do
        fail Errors.InvalidFormatError{"ZIP64 end locator is missing"}
    if try zipU32(locator.bytes(), 4) or try zipU32(locator.bytes(), 16) != 1 do
        fail Errors.UnsupportedFormatError{"multi-disk ZIP64 archives are not supported"}
    let recordOffset = try zipU64(locator.bytes(), 8)
    let fileSize     = try file.size()
    if recordOffset > fileSize or 56 > fileSize - recordOffset do
        fail Errors.InvalidFormatError{"ZIP64 end record lies outside the file"}

    let record = try file.map(recordOffset, 56)
    if try zipU32(record.bytes(), 0) != Zip64EndSignature do
        fail Errors.InvalidFormatError{"ZIP64 end record has the wrong signature"}
    if try zipU32(record.bytes(), 16) or try zipU32(record.bytes(), 20) do
        fail Errors.UnsupportedFormatError{"multi-disk ZIP64 archives are not supported"}
    if try zipU64(record.bytes(), 24) != try zipU64(record.bytes(), 32) do
        fail Errors.UnsupportedFormatError{"multi-disk ZIP64 archives are not supported"}
    result.count  = try zipU64(record.bytes(), 32)
    result.size   = try zipU64(record.bytes(), 40)
    result.offset = try zipU64(record.bytes(), 48)
    return result
}

func loadZipArchive(fileName: string)->ZipArchive fail
{
    var result: retval
    var file     = try File.MappedFile.open(fileName)
    let fileSize = try file.size()
    if fileSize < 22 do
        fail Errors.InvalidFormatError{"file is too short to contain a ZIP end record"}

    let tailSize   = Math.min(fileSize, ZipEndSearch)
    let tailOffset = fileSize - tailSize
    let tail       = try file.map(tailOffset, tailSize)
    let bytes      = tail.bytes()
    var endAt      = Swag.U64.Max
    var scan       = tailSize - 22
    while true
    {
        if try zipU32(bytes, scan) == ZipEndSignature
        {
            let commentLength = cast(u64) try zipU16(bytes, scan + 20)
            if scan + 22 + commentLength == tailSize
            {
                endAt = scan
                break
            }
        }

        if !scan do
            break
        scan -= 1
    }

    if endAt == Swag.U64.Max do
        fail Errors.InvalidFormatError{"ZIP end record is missing"}

    let disk      = try zipU16(bytes, endAt + 4)
    let startDisk = try zipU16(bytes, endAt + 6)
    if disk or startDisk do
        fail Errors.UnsupportedFormatError{"multi-disk ZIP archives are not supported"}
    let diskEntries = try zipU16(bytes, endAt + 8)
    let allEntries  = try zipU16(bytes, endAt + 10)
    if diskEntries != allEntries do
        fail Errors.UnsupportedFormatError{"multi-disk ZIP archives are not supported"}

    let commentLength = cast(u64) try zipU16(bytes, endAt + 20)
    if commentLength do
        result.comment = zipText(bytes[endAt + 22 until endAt + 22 + commentLength], true)

    let directory = try zipDirectoryLocation(&file, tailOffset, bytes, endAt)
    if directory.count > ZipEntryLimit do
        fail Errors.UnsupportedFormatError{"ZIP archive contains too many entries"}
    if directory.size > ZipDirectoryLimit do
        fail Errors.UnsupportedFormatError{"ZIP central directory is too large"}
    if directory.offset > fileSize or directory.size > fileSize - directory.offset do
        fail Errors.InvalidFormatError{"ZIP central directory lies outside the file"}

    let region = try file.map(directory.offset, directory.size)
    let data   = region.bytes()
    var at     = 0'u64
    for index in directory.count
    {
        discard index
        if at > data.count or 46 > data.count - at do
            fail Errors.InvalidFormatError{"ZIP central directory ends inside an entry"}
        if try zipU32(data, at) != ZipDirectorySignature do
            fail Errors.InvalidFormatError{"ZIP central-directory entry has the wrong signature"}

        let nameLength    = cast(u64) try zipU16(data, at + 28)
        let extraLength   = cast(u64) try zipU16(data, at + 30)
        let commentLength = cast(u64) try zipU16(data, at + 32)
        let totalLength   = 46 + nameLength + extraLength + commentLength
        if totalLength > data.count - at do
            fail Errors.InvalidFormatError{"ZIP central-directory entry extends past the directory"}

        var entry: ZipEntry
        entry.flags            = try zipU16(data, at + 8)
        entry.method           = try zipU16(data, at + 10)
        entry.crc32            = try zipU32(data, at + 16)
        entry.compressedSize   = cast(u64) try zipU32(data, at + 20)
        entry.uncompressedSize = cast(u64) try zipU32(data, at + 24)
        var diskNumber = cast(u64) try zipU16(data, at + 34)
        entry.localOffset = cast(u64) try zipU32(data, at + 42)

        let nameBytes  = data[at + 46 until at + 46 + nameLength]
        let extraBytes = data[at + 46 + nameLength until at + 46 + nameLength + extraLength]
        try applyZip64Extra(extraBytes, &entry.uncompressedSize, &entry.compressedSize, &entry.localOffset, &diskNumber)
        if diskNumber do
            fail Errors.UnsupportedFormatError{"multi-disk ZIP entries are not supported"}

        let decoded = zipText(nameBytes, cast(bool) (entry.flags & ZipFlagUtf8))
        entry.path = cleanZipPath(decoded.toString())
        if entry.path.isEmpty()
        {
            at += totalLength
            continue
        }

        let external = try zipU32(data, at + 38)
        entry.isDirectory = (nameBytes.count and (nameBytes[nameBytes.count - 1] == '/'u8 or nameBytes[nameBytes.count - 1] == '\\'u8)) or cast(bool) (external & 0x10)
        if !entry.isDirectory
        {
            if entry.compressedSize > Swag.U64.Max - result.compressedSize or entry.uncompressedSize > Swag.U64.Max - result.uncompressedSize do
                fail Errors.InvalidFormatError{"ZIP entry sizes exceed the supported range"}
            result.compressedSize   += entry.compressedSize
            result.uncompressedSize += entry.uncompressedSize
        }

        result.entries.add(#move entry)
        at += totalLength
    }

    result.entries.sort(func(a, b) { return Utf8.compare(a.path.toSlice(), b.path.toSlice(), .Latin1NoCase) })
    return result
}

// Reads and validates one bounded archive entry without materializing a temporary file.
//
// Archive previews write this result to a disposable path, while container readers such as ODF
// consume trusted XML in memory. Both paths therefore share the same size, compression, and CRC
// boundary.
func loadZipEntry(archiveFileName: string, entry: const *ZipEntry)->Array'u8 fail
{
    if entry.isDirectory do
        fail Errors.BadParameterError{"a ZIP directory has no file content"}
    if entry.flags & ZipFlagEncrypted do
        fail Errors.UnsupportedFormatError{"encrypted ZIP entries are not supported"}
    if entry.uncompressedSize > ZipPreviewLimit do
        fail Errors.UnsupportedFormatError{"ZIP entry is too large to preview"}
    if entry.compressedSize > ZipPreviewLimit do
        fail Errors.UnsupportedFormatError{"compressed ZIP entry is too large to preview"}
    if entry.method != 0 and entry.method != 8 do
        fail Errors.UnsupportedFormatError{Errors.mkString(Format.toString("ZIP compression method % is not supported", entry.method).toString())}

    var stream   = try File.openRead(archiveFileName)
    let fileSize = try stream.size()
    if entry.localOffset > fileSize or 30 > fileSize - entry.localOffset do
        fail Errors.InvalidFormatError{"ZIP local header lies outside the file"}
    var header: [30] u8
    if !(try stream.readExactAt(entry.localOffset, header)) do
        fail Errors.InvalidFormatError{"ZIP local header is truncated"}
    if try zipU32(header, 0) != ZipLocalSignature do
        fail Errors.InvalidFormatError{"ZIP local header has the wrong signature"}

    let nameLength  = cast(u64) try zipU16(header, 26)
    let extraLength = cast(u64) try zipU16(header, 28)
    let headerEnd   = entry.localOffset + 30
    if nameLength > fileSize - headerEnd or extraLength > fileSize - headerEnd - nameLength do
        fail Errors.InvalidFormatError{"ZIP local header fields lie outside the file"}
    let dataOffset = headerEnd + nameLength + extraLength
    if dataOffset > fileSize or entry.compressedSize > fileSize - dataOffset do
        fail Errors.InvalidFormatError{"ZIP entry payload lies outside the file"}

    var packed: Array'u8
    packed.resize(entry.compressedSize)
    if entry.compressedSize and !(try stream.readExactAt(dataOffset, packed.toSlice())) do
        fail Errors.InvalidFormatError{"ZIP entry payload is truncated"}

    var plain: retval
    if entry.method == 0 do
        plain = #move packed
    else
    {
        plain.reserve(entry.uncompressedSize)
        var inflater: Compress.Inflate
        try inflater.decompress(&plain, packed.toSlice(), maxOutputSize: entry.uncompressedSize)
    }

    if plain.count != entry.uncompressedSize do
        fail Errors.InvalidFormatError{"ZIP entry expands to a different size than its directory declares"}
    if Hash.Crc32.compute(plain.toSlice()) != entry.crc32 do
        fail Errors.InvalidFormatError{"ZIP entry checksum does not match its directory"}
    return #move plain
}

// Extracts one validated archive entry for an embedded file viewer.
func extractZipEntry(archiveFileName: string, entry: const *ZipEntry, destination: string) fail
{
    let plain = try loadZipEntry(archiveFileName, entry)
    if try File.writeAllBytes(destination, plain.toSlice()) != plain.count do
        fail Swag.SystemError{"temporary preview file was not written completely"}
}
