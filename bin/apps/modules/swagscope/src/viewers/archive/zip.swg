#global internal
#global namespace Viewers.Archive

using Core

// One browseable file or directory in an archive.
struct ZipEntry
{
    path:             String
    compressedSize:   u64
    uncompressedSize: u64
    localOffset:      u64
    dataOffset:       u64      // Direct payload position for TAR entries.
    crc32:            u32
    method:           u16
    flags:            u16
    isDirectory:      bool
    isTar:            bool     // Payload is an uncompressed TAR member addressed by dataOffset.
    isGzip:           bool     // Payload must first be decoded from a GZIP stream.
    modified:         Time.DateTime     // Last modification recorded for the entry, in the archive's local time; zero when none.
}

// Archive members sorted by path, ignoring case.
struct Zip
{
    entries:          Array'ZipEntry
    compressedSize:   u64     // Sum over the file entries; directories do not count
    uncompressedSize: u64     // Sum over the file entries; directories do not count
    comment:          String
}

impl Zip
{
    // Returns the first entry stored at `path`, or null when the archive has none.
    //
    // Readers of packaged documents look up many parts, so the search halves the entries in their
    // sorted order, which ignores case, down to the paths equal to `path` but for case. The first
    // of them stored with exactly its case is the one a scan in that order would find.
    mtd const tryFindEntry(path: string)->const *ZipEntry?
    {
        var first = 0'u64
        var last  = .entries.count
        while first < last
        {
            let middle = first + (last - first) / 2
            if Utf8.compare(.entries[middle].path.toSlice(), path, .Latin1NoCase) < 0 do
                first = middle + 1
            else do
                last = middle
        }

        for index in first until .entries.count
        {
            let entry = &.entries[index]
            if Utf8.compare(entry.path.toSlice(), path, .Latin1NoCase) != 0 do
                break
            if entry.path == path do
                return entry
        }

        return null
    }

    // Decodes the MS-DOS time and date of an entry; an impossible date reads as none.
    func dosDateTime(time, date: u16)->Time.DateTime
    {
        var result: #returntype
        let month = (date >> 5) & 0xF
        let day   = date & 0x1F
        if month < 1 or month > 12 or day < 1 do
            return result
        result.year   = 1980 + (date >> 9)
        result.month  = month
        result.day    = day
        result.hour   = Math.min(time >> 11, 23)
        result.minute = Math.min((time >> 5) & 0x3F, 59)
        result.second = Math.min((time & 0x1F) * 2, 59)
        return result
    }

    // Decodes a stored name or comment: as UTF-8 when `utf8` is set and the bytes are valid, as CP437 otherwise.
    func text(bytes: const [..] u8, utf8: bool)->String
    {
        if not bytes.count do
            return {}
        if utf8 and Utf8.isValid(bytes) do
            return cast(string, bytes)

        var result: #returntype
        result.reserve(bytes.count)
        for value in bytes
        {
            if value < 0x80 do
                result += value
            else do
                result += Cp437High[value - 0x80]
        }

        return result
    }

    // The offset of the end record in `bytes`, the tail of the file: the last record whose comment
    // ends exactly with the file. `U64.Max` when there is none.
    func findEndRecord(bytes: const [..] u8)->u64 fail
    {
        for scan in reversed(bytes.count - 21)
        {
            if try readU32(bytes, scan) != EndSignature do
                continue
            let commentLength = cast(u64, try readU16(bytes, scan + 20))
            if scan + 22 + commentLength == bytes.count do
                return scan
        }

        return Swag.U64.Max
    }

    // Decodes the central directory entry at `at`, and the length of its record. An entry whose
    // name cleans down to nothing comes back with an empty path, for the caller to skip.
    func readDirectoryEntry(data: const [..] u8, at: u64)->{entry: ZipEntry, length: u64} fail
    {
        var result: #returntype
        if at > data.count or 46 > data.count - at do
            fail Errors.InvalidFormatError{texts().err_DirectoryTruncated}
        if try readU32(data, at) != DirectorySignature do
            fail Errors.InvalidFormatError{texts().err_EntrySignature}

        let nameLength    = cast(u64, try readU16(data, at + 28))
        let extraLength   = cast(u64, try readU16(data, at + 30))
        let commentLength = cast(u64, try readU16(data, at + 32))
        let totalLength   = 46 + nameLength + extraLength + commentLength
        if totalLength > data.count - at do
            fail Errors.InvalidFormatError{texts().err_EntryOverflow}
        result.length = totalLength

        let entry = &result.entry
        with entry
        {
            .flags            = try readU16(data, at + 8)
            .method           = try readU16(data, at + 10)
            .crc32            = try readU32(data, at + 16)
            .compressedSize   = cast(u64, try readU32(data, at + 20))
            .uncompressedSize = cast(u64, try readU32(data, at + 24))
            .modified         = dosDateTime(try readU16(data, at + 12), try readU16(data, at + 14))
        }

        var diskNumber = cast(u64, try readU16(data, at + 34))
        entry.localOffset = cast(u64, try readU32(data, at + 42))

        let nameBytes  = data[at + 46 until at + 46 + nameLength]
        let extraBytes = data[at + 46 + nameLength until at + 46 + nameLength + extraLength]
        try applyZip64Extra(extraBytes, &entry.uncompressedSize, &entry.compressedSize, &entry.localOffset, &diskNumber)
        if diskNumber do
            fail Errors.UnsupportedFormatError{texts().err_MultiDiskEntry}

        let decoded = text(nameBytes, cast(bool, entry.flags & FlagUtf8))
        entry.path = cleanPath(decoded)
        if entry.path.isEmpty() do
            return result

        let external = try readU32(data, at + 38)
        let hasDirectorySuffix = nameBytes.count and
                                 (nameBytes[nameBytes.count - 1] == '/'u8 or nameBytes[nameBytes.count - 1] == '\\'u8)
        entry.isDirectory = hasDirectorySuffix or cast(bool, external & 0x10)
        return result
    }

    // Reads a ZIP central directory, TAR headers, or one bounded GZIP member.
    //
    // The end record must close the file exactly. Multi-disk archives and directories beyond the
    // entry and size limits fail before any entry is decoded.
    func load(fileName: string)->Zip fail
    {
        var result: #returntype
        var file     = try File.MappedFile.open(fileName)
        let fileSize = try file.size()

        if fileSize >= 2
        {
            let first = try file.map(0, 2)
            let bytes = first.bytes()
            if bytes[0] == 0x1F and bytes[1] == 0x8B do
                return try loadGzip(&file, fileSize)
        }

        // TAR has no end directory. Its ustar header begins at byte zero; it shares the same
        // entry model so Explorer, previews, and nested browsing use the regular archive path.
        if fileSize >= TarBlockSize
        {
            let first = try file.map(0, TarBlockSize)
            if isTarHeader(first.bytes()) do
                return try loadTar(&file, fileSize)
        }
        if fileSize < 22 do
            fail Errors.InvalidFormatError{texts().err_TooShort}

        // Search backward for an end record that accounts for the trailing comment.
        let tailSize   = Math.min(fileSize, EndSearch)
        let tailOffset = fileSize - tailSize
        let tail       = try file.map(tailOffset, tailSize)
        let bytes      = tail.bytes()
        let endAt      = try findEndRecord(bytes)
        if endAt == Swag.U64.Max do
            fail Errors.InvalidFormatError{texts().err_EndMissing}

        let disk      = try readU16(bytes, endAt + 4)
        let startDisk = try readU16(bytes, endAt + 6)
        if disk or startDisk do
            fail Errors.UnsupportedFormatError{texts().err_MultiDisk}
        let diskEntries = try readU16(bytes, endAt + 8)
        let allEntries  = try readU16(bytes, endAt + 10)
        if diskEntries != allEntries do
            fail Errors.UnsupportedFormatError{texts().err_MultiDisk}

        let commentLength = cast(u64, try readU16(bytes, endAt + 20))
        if commentLength do
            result.comment = text(bytes[endAt + 22 until endAt + 22 + commentLength], true)

        // Validate the directory bounds before mapping its entries.
        let directory = try directoryLocation(&file, tailOffset, bytes, endAt)
        if directory.count > EntryLimit do
            fail Errors.UnsupportedFormatError{texts().err_TooManyEntries}
        if directory.size > DirectoryLimit do
            fail Errors.UnsupportedFormatError{texts().err_DirectoryTooLarge}
        if directory.offset > fileSize or directory.size > fileSize - directory.offset do
            fail Errors.InvalidFormatError{texts().err_DirectoryOutside}

        let region = try file.map(directory.offset, directory.size)
        let data   = region.bytes()
        var at     = 0'u64
        for directory.count
        {
            var read = try readDirectoryEntry(data, at)
            at += read.length
            if read.entry.path.isEmpty() do
                continue

            if not read.entry.isDirectory
            {
                if read.entry.compressedSize > Swag.U64.Max - result.compressedSize or
                   read.entry.uncompressedSize > Swag.U64.Max - result.uncompressedSize do
                    fail Errors.InvalidFormatError{texts().err_EntrySizes}
                result.compressedSize   += read.entry.compressedSize
                result.uncompressedSize += read.entry.uncompressedSize
            }

            result.entries.add(#move read.entry)
        }

        result.entries.sort(func(a, b) => Utf8.compare(a.path.toSlice(), b.path.toSlice(), .Latin1NoCase))
        return result
    }

    // Reads and validates one bounded archive entry in memory, enforcing its size, compression,
    // and CRC before anything is written for a preview.
    func loadEntry(archiveFileName: string, entry: const *ZipEntry)->Array'u8 fail
    {
        if entry.isDirectory do
            fail Errors.BadParameterError{texts().err_DirectoryContent}
        if entry.isGzip
        {
            let decoded = try decodeGzipFile(archiveFileName)
            if entry.isTar
            {
                if entry.dataOffset > decoded.bytes.count or entry.uncompressedSize > decoded.bytes.count - entry.dataOffset do
                    fail Errors.InvalidFormatError{texts().err_TarPayloadOutside}
                var result: #returntype
                result.add(decoded.bytes[entry.dataOffset until entry.dataOffset + entry.uncompressedSize])
                return result
            }

            if decoded.bytes.count != entry.uncompressedSize do
                fail Errors.InvalidFormatError{texts().err_GzipSize}

            return #move decoded.bytes
        }
        if entry.isTar
        {
            if entry.uncompressedSize > PreviewLimit do
                fail Errors.UnsupportedFormatError{texts().err_EntryTooLarge}
            var file   = try File.MappedFile.open(archiveFileName)
            let length = try file.size()
            if entry.dataOffset > length or entry.uncompressedSize > length - entry.dataOffset do
                fail Errors.InvalidFormatError{texts().err_TarPayloadOutside}
            let region = try file.map(entry.dataOffset, entry.uncompressedSize)
            var result: #returntype
            result.add(region.bytes())
            return result
        }
        if entry.flags & FlagEncrypted do
            fail Errors.UnsupportedFormatError{texts().err_Encrypted}
        if entry.uncompressedSize > PreviewLimit do
            fail Errors.UnsupportedFormatError{texts().err_EntryTooLarge}
        if entry.compressedSize > PreviewLimit do
            fail Errors.UnsupportedFormatError{texts().err_PackedTooLarge}
        if entry.method != 0 and entry.method != 8 do
            fail Errors.UnsupportedFormatError{Errors.mkString(Format.toString(texts().err_Method, entry.method))}

        var stream   = try File.openReadLive(archiveFileName)
        let fileSize = try stream.size()
        if entry.localOffset > fileSize or 30 > fileSize - entry.localOffset do
            fail Errors.InvalidFormatError{texts().err_LocalOutside}
        var header: [30] u8
        if not (try stream.readExactAt(entry.localOffset, header)) do
            fail Errors.InvalidFormatError{texts().err_LocalTruncated}
        if try readU32(header, 0) != LocalSignature do
            fail Errors.InvalidFormatError{texts().err_LocalSignature}

        let nameLength  = cast(u64, try readU16(header, 26))
        let extraLength = cast(u64, try readU16(header, 28))
        let headerEnd   = entry.localOffset + 30
        if nameLength > fileSize - headerEnd or extraLength > fileSize - headerEnd - nameLength do
            fail Errors.InvalidFormatError{texts().err_LocalFields}
        let dataOffset = headerEnd + nameLength + extraLength
        if dataOffset > fileSize or entry.compressedSize > fileSize - dataOffset do
            fail Errors.InvalidFormatError{texts().err_PayloadOutside}

        var packed: Array'u8
        packed.resize(entry.compressedSize)
        if entry.compressedSize and not (try stream.readExactAt(dataOffset, packed.toSlice())) do
            fail Errors.InvalidFormatError{texts().err_PayloadTruncated}

        var plain: #returntype
        if entry.method == 0
        {
            plain = #move packed
        }
        else
        {
            plain.reserve(entry.uncompressedSize)
            var inflater: Compress.Inflate
            try inflater.decompress(&plain, packed.toSlice(), maxOutputSize: entry.uncompressedSize)
        }

        if plain.count != entry.uncompressedSize do
            fail Errors.InvalidFormatError{texts().err_SizeMismatch}
        if Hash.Crc32.compute(plain.toSlice()) != entry.crc32 do
            fail Errors.InvalidFormatError{texts().err_Checksum}
        return plain
    }

    // Writes one validated archive entry to `destination`, where an embedded file viewer opens it.
    func extractEntry(archiveFileName: string, entry: const *ZipEntry, destination: string) fail
    {
        let plain = try loadEntry(archiveFileName, entry)
        var ownsDestination = false
        defer
        {
            if ownsDestination do
                discard catch File.delete(destination)
        }

        var output = try File.open(destination, .CreateNew, .Write, .Delete)
        ownsDestination = true
        try output.writeAll(plain.toSlice())
        output.close()
        ownsDestination = false
    }
}

// The fixed values of the ZIP format, and the readers the loader is built from.
private impl Zip
{
    const TarBlockSize = 512'u64
    const TarExtensionLimit = 1024 * 1024'u64
    const GzipHeaderLimit = 1024 * 1024'u64
    const GzipInputLimit = PreviewLimit

    struct GzipDocument
    {
        bytes: Array'u8
        name:  String
    }

    struct TarOverrides
    {
        path:    String
        size:    u64
        hasPath: bool
        hasSize: bool
    }
    // Signatures of the records the reader walks.
    const LocalSignature        = 0x04034B50'u32
    const DirectorySignature    = 0x02014B50'u32
    const EndSignature          = 0x06054B50'u32
    const Zip64EndSignature     = 0x06064B50'u32
    const Zip64LocatorSignature = 0x07064B50'u32

    // The end record is 22 bytes followed by a comment of at most 64 KiB, so it lies within this
    // distance of the end of the file.
    const EndSearch = 0xFFFF + 22'u64

    // Bounds that keep a hostile directory or entry from exhausting memory: the directory is read
    // whole, and an entry is inflated whole to be previewed.
    const EntryLimit     = 250_000'u64
    const DirectoryLimit = 512 * 1024 * 1024'u64
    const PreviewLimit   = 256 * 1024 * 1024'u64

    // General-purpose flags of an entry.
    const FlagEncrypted = 1'u16
    const FlagUtf8      = 1'u16 << 11

    // Confirms the ustar marker before treating a file as TAR.
    func isTarHeader(bytes: const [..] u8)->bool
    {
        if bytes.count < TarBlockSize do
            return false
        return bytes[257] == 'u' and bytes[258] == 's' and bytes[259] == 't' and
               bytes[260] == 'a' and bytes[261] == 'r'
    }

    // Reads an octal TAR number, rejecting base-256 encodings and invalid digits.
    func tarOctal(bytes: const [..] u8)->u64 fail
    {
        var result = 0'u64
        var digits = false
        for byte in bytes
        {
            if byte == 0 or byte == ' ' do
                continue
            if byte < '0' or byte > '7' do
                fail Errors.InvalidFormatError{texts().err_TarNumber}
            digits = true
            if result > (Swag.U64.Max - (byte - '0')) / 8 do
                fail Errors.InvalidFormatError{texts().err_TarNumber}
            result = result * 8 + (byte - '0')
        }
        if not digits do
            return 0
        return result
    }

    func tarField(bytes: const [..] u8)->string
    {
        var length = 0'u64
        while length < bytes.count and bytes[length] != 0 do
            length += 1
        return cast(string, bytes[until length])
    }

    func tarDecimal(bytes: const [..] u8)->u64 fail
    {
        if not bytes.count do
            fail Errors.InvalidFormatError{texts().err_TarExtended}
        var result = 0'u64
        for byte in bytes
        {
            if byte < '0' or byte > '9' or result > (Swag.U64.Max - (byte - '0')) / 10 do
                fail Errors.InvalidFormatError{texts().err_TarExtended}
            result = result * 10 + (byte - '0')
        }
        return result
    }

    // Reads bounded POSIX PAX records, retaining the path and size overrides used by this reader.
    func tarPaxOverrides(bytes: const [..] u8)->TarOverrides fail
    {
        var result: #returntype
        var at = 0'u64
        while at < bytes.count
        {
            var length = 0'u64
            var digits = 0'u64
            while at + digits < bytes.count and bytes[at + digits] != ' '
            {
                let byte = bytes[at + digits]
                if byte < '0' or byte > '9' or length > (Swag.U64.Max - (byte - '0')) / 10 do
                    fail Errors.InvalidFormatError{texts().err_TarExtended}
                length = length * 10 + (byte - '0')
                digits += 1
            }
            if not digits or at + digits >= bytes.count or length <= digits + 2 or length > bytes.count - at do
                fail Errors.InvalidFormatError{texts().err_TarExtended}
            let end = at + length
            if bytes[end - 1] != '\n' do
                fail Errors.InvalidFormatError{texts().err_TarExtended}

            let keyAt = at + digits + 1
            var equalsAt = keyAt
            while equalsAt < end - 1 and bytes[equalsAt] != '=' do
                equalsAt += 1
            if equalsAt == keyAt or equalsAt >= end - 1 do
                fail Errors.InvalidFormatError{texts().err_TarExtended}
            let key   = cast(string, bytes[keyAt until equalsAt])
            let value = bytes[equalsAt + 1 until end - 1]
            if key == "path"
            {
                if not Utf8.isValid(value) do
                    fail Errors.InvalidFormatError{texts().err_TarPath}
                for byte in value do
                    result.path += byte
                result.hasPath = true
            }
            elif key == "size"
            {
                result.size = try tarDecimal(value)
                result.hasSize = true
            }
            at = end
        }
        return result
    }

    // Reads one RFC 1952 member, including optional header fields and its CRC/size trailer.
    func decodeGzip(bytes: const [..] u8)->GzipDocument fail
    {
        if bytes.count < 18 or bytes[0] != 0x1F or bytes[1] != 0x8B or bytes[2] != 8 do
            fail Errors.InvalidFormatError{texts().err_GzipHeader}
        let flags = bytes[3]
        if flags & 0xE0 do
            fail Errors.InvalidFormatError{texts().err_GzipHeader}

        let trailerAt = bytes.count - 8
        var at        = 10'u64
        var result: #returntype
        if flags & 4
        {
            let extraSize = cast(u64, try readU16(bytes, at))
            at += 2
            if at > trailerAt or extraSize > trailerAt - at do
                fail Errors.InvalidFormatError{texts().err_GzipHeader}
            at += extraSize
        }
        if flags & 8
        {
            let nameAt = at
            while at < Math.min(trailerAt, GzipHeaderLimit) and bytes[at] do
                at += 1
            if at == trailerAt or at == GzipHeaderLimit do
                fail Errors.InvalidFormatError{texts().err_GzipHeader}
            result.name = text(bytes[nameAt until at], false)
            at += 1
        }
        if flags & 16
        {
            while at < Math.min(trailerAt, GzipHeaderLimit) and bytes[at] do
                at += 1
            if at == trailerAt or at == GzipHeaderLimit do
                fail Errors.InvalidFormatError{texts().err_GzipHeader}
            at += 1
        }
        if flags & 2
        {
            if at > trailerAt or 2 > trailerAt - at do
                fail Errors.InvalidFormatError{texts().err_GzipHeader}
            if cast(u16, Hash.Crc32.compute(bytes[0 until at])) != (try readU16(bytes, at)) do
                fail Errors.InvalidFormatError{texts().err_GzipHeader}
            at += 2
        }
        if at >= trailerAt or at > GzipHeaderLimit do
            fail Errors.InvalidFormatError{texts().err_GzipHeader}

        var inflater: Compress.Inflate
        try inflater.decompress(&result.bytes, bytes[at until trailerAt], maxOutputSize: PreviewLimit)
        if Hash.Crc32.compute(result.bytes.toSlice()) != (try readU32(bytes, trailerAt)) do
            fail Errors.InvalidFormatError{texts().err_GzipChecksum}
        if cast(u32, result.bytes.count) != (try readU32(bytes, trailerAt + 4)) do
            fail Errors.InvalidFormatError{texts().err_GzipSize}
        return result
    }

    // Maps and decodes one bounded GZIP file for browsing and extraction.
    func decodeGzipFile(fileName: string)->GzipDocument fail
    {
        var file = try File.MappedFile.open(fileName)
        let size = try file.size()
        if size > GzipInputLimit do
            fail Errors.UnsupportedFormatError{texts().err_GzipTooLarge}
        let mapped = try file.map(0, size)
        return try decodeGzip(mapped.bytes())
    }

    // Exposes a single compressed file or the members of a TAR.GZ through the archive model.
    func loadGzip(file: *File.MappedFile, fileSize: u64)->Zip fail
    {
        if fileSize > GzipInputLimit do
            fail Errors.UnsupportedFormatError{texts().err_GzipTooLarge}
        let mapped = try file.map(0, fileSize)
        let decoded = try decodeGzip(mapped.bytes())
        if decoded.bytes.count >= TarBlockSize and isTarHeader(decoded.bytes.toSlice())
        {
            var result = try loadTarBytes(decoded.bytes.toSlice())
            for &entry in result.entries do
                entry.isGzip = true
            result.compressedSize = fileSize
            return result
        }

        var path = decoded.name
        if path.isEmpty()
        {
            path = Path.fileName(file.name) orelse "content.gz"
            if Utf8.endsWith(path.toSlice(), ".gz") do
                path = path.toString()[0 until path.count - 3]
        }
        path = cleanPath(path.toString())
        if path.isEmpty() do
            path = "content"
        var entry: ZipEntry
        entry.path             = #move path
        entry.compressedSize   = fileSize
        entry.uncompressedSize = decoded.bytes.count
        entry.isGzip           = true
        var result: #returntype
        result.compressedSize   = fileSize
        result.uncompressedSize = decoded.bytes.count
        result.entries.add(#move entry)
        return result
    }

    // Validates one POSIX header checksum, treating its checksum field as eight spaces.
    func validTarChecksum(header: const [..] u8)->bool fail
    {
        let expected = try tarOctal(header[148 until 156])
        var actual   = 0'u64
        for byte, index in header do
            actual += index >= 148 and index < 156 ? 32 : byte
        return expected == actual
    }

    // Parses a bounded ustar archive, keeping file payloads as source offsets until preview.
    func loadTar(file: *File.MappedFile, fileSize: u64)->Zip fail
    {
        let mapped = try file.map(0, fileSize)
        return try loadTarBytes(mapped.bytes())
    }

    // Parses a bounded ustar archive from either a mapped file or a validated GZIP payload.
    func loadTarBytes(bytes: const [..] u8)->Zip fail
    {
        let fileSize = bytes.count
        var result: #returntype
        var at          = 0'u64
        var entryCount  = 0'u64
        var zeroHeaders = 0'u8
        var globalPax: TarOverrides
        var pendingPax: TarOverrides
        while at <= fileSize and TarBlockSize <= fileSize - at
        {
            let header = bytes[at until at + TarBlockSize]
            var allZero = true
            for byte in header where byte do
                allZero = false
            if allZero
            {
                zeroHeaders += 1
                at += TarBlockSize
                if zeroHeaders >= 2 do
                    break
                continue
            }
            zeroHeaders = 0
            if not try validTarChecksum(header) do
                fail Errors.InvalidFormatError{texts().err_TarChecksum}

            let name   = tarField(header[0 until 100])
            let prefix = tarField(header[345 until 500])
            var path: String = name
            if prefix.count do
                path = Format.toString("%/%", prefix, name)
            let kind = header[156]
            if kind != 0 and kind != '0' and kind != '5' and kind != 'x' and kind != 'g' do
                fail Errors.UnsupportedFormatError{Errors.mkString(Format.toString(texts().err_TarType, kind))}

            let headerSize = try tarOctal(header[124 until 136])
            if headerSize > fileSize - at - TarBlockSize do
                fail Errors.InvalidFormatError{texts().err_TarPayloadOutside}
            let dataAt = at + TarBlockSize
            let headerPadded = headerSize > Swag.U64.Max - (TarBlockSize - 1) ?
                               Swag.U64.Max : (headerSize + TarBlockSize - 1) & ~(TarBlockSize - 1)
            if headerPadded > fileSize - dataAt do
                fail Errors.InvalidFormatError{texts().err_TarPayloadOutside}

            if kind == 'x' or kind == 'g'
            {
                if headerSize > TarExtensionLimit do
                    fail Errors.UnsupportedFormatError{texts().err_TarExtended}
                let overrides = try tarPaxOverrides(bytes[dataAt until dataAt + headerSize])
                if kind == 'g'
                {
                    if overrides.hasPath
                    {
                        globalPax.path = #move overrides.path
                        globalPax.hasPath = true
                    }
                    if overrides.hasSize
                    {
                        globalPax.size = overrides.size
                        globalPax.hasSize = true
                    }
                }
                else
                {
                    if overrides.hasPath
                    {
                        pendingPax.path = #move overrides.path
                        pendingPax.hasPath = true
                    }
                    if overrides.hasSize
                    {
                        pendingPax.size = overrides.size
                        pendingPax.hasSize = true
                    }
                }
                at = dataAt + headerPadded
                continue
            }

            if not Utf8.isValid(path.toSlice()) do
                fail Errors.InvalidFormatError{texts().err_TarPath}
            if globalPax.hasPath do
                path = globalPax.path.toString()
            if pendingPax.hasPath do
                path = pendingPax.path.toString()
            var size = pendingPax.hasSize ? pendingPax.size : globalPax.hasSize ? globalPax.size : headerSize
            pendingPax = {}
            if kind == '5' do
                size = 0
            if size > fileSize - dataAt do
                fail Errors.InvalidFormatError{texts().err_TarPayloadOutside}
            let padded = size > Swag.U64.Max - (TarBlockSize - 1) ?
                         Swag.U64.Max : (size + TarBlockSize - 1) & ~(TarBlockSize - 1)
            if padded > fileSize - dataAt do
                fail Errors.InvalidFormatError{texts().err_TarPayloadOutside}

            path = cleanPath(path)
            if not path.isEmpty()
            {
                var entry: ZipEntry
                entry.path           = path
                entry.localOffset    = at
                entry.dataOffset     = dataAt
                entry.compressedSize = kind == '5' ? 0 : size
                entry.uncompressedSize = kind == '5' ? 0 : size
                entry.isDirectory    = kind == '5' or Utf8.endsWith(path, "/")
                entry.isTar          = true
                if not entry.isDirectory
                {
                    if size > Swag.U64.Max - result.uncompressedSize or
                       size > Swag.U64.Max - result.compressedSize do
                        fail Errors.InvalidFormatError{texts().err_TarNumber}
                    result.uncompressedSize += size
                    result.compressedSize   += size
                }
                result.entries.add(#move entry)
                entryCount += 1
                if entryCount > EntryLimit do
                    fail Errors.UnsupportedFormatError{texts().err_TooManyEntries}
            }

            at = dataAt + padded
        }

        if zeroHeaders < 2 or result.entries.isEmpty() do
            fail Errors.InvalidFormatError{texts().err_TarEnd}
        result.entries.sort(func(a, b) => Utf8.compare(a.path.toSlice(), b.path.toSlice(), .Latin1NoCase))
        return result
    }

    // A size, offset, or count saturated at its field's maximum is stored in the ZIP64 extra field.
    const Value32Overflow = 0xFFFF_FFFF'u64
    const Value16Overflow = 0xFFFF'u64

    // The upper half of code page 437, the encoding of names stored without the UTF-8 flag.
    const Cp437High: [128] rune = [
        0x00C7, 0x00FC, 0x00E9, 0x00E2, 0x00E4, 0x00E0, 0x00E5, 0x00E7, 0x00EA, 0x00EB, 0x00E8, 0x00EF, 0x00EE, 0x00EC, 0x00C4, 0x00C5,
        0x00C9, 0x00E6, 0x00C6, 0x00F4, 0x00F6, 0x00F2, 0x00FB, 0x00F9, 0x00FF, 0x00D6, 0x00DC, 0x00A2, 0x00A3, 0x00A5, 0x20A7, 0x0192,
        0x00E1, 0x00ED, 0x00F3, 0x00FA, 0x00F1, 0x00D1, 0x00AA, 0x00BA, 0x00BF, 0x2310, 0x00AC, 0x00BD, 0x00BC, 0x00A1, 0x00AB, 0x00BB,
        0x2591, 0x2592, 0x2593, 0x2502, 0x2524, 0x2561, 0x2562, 0x2556, 0x2555, 0x2563, 0x2551, 0x2557, 0x255D, 0x255C, 0x255B, 0x2510,
        0x2514, 0x2534, 0x252C, 0x251C, 0x2500, 0x253C, 0x255E, 0x255F, 0x255A, 0x2554, 0x2569, 0x2566, 0x2560, 0x2550, 0x256C, 0x2567,
        0x2568, 0x2564, 0x2565, 0x2559, 0x2558, 0x2552, 0x2553, 0x256B, 0x256A, 0x2518, 0x250C, 0x2588, 0x2584, 0x258C, 0x2590, 0x2580,
        0x03B1, 0x00DF, 0x0393, 0x03C0, 0x03A3, 0x03C3, 0x00B5, 0x03C4, 0x03A6, 0x0398, 0x03A9, 0x03B4, 0x221E, 0x03C6, 0x03B5, 0x2229,
        0x2261, 0x00B1, 0x2265, 0x2264, 0x2320, 0x2321, 0x00F7, 0x2248, 0x00B0, 0x2219, 0x00B7, 0x221A, 0x207F, 0x00B2, 0x25A0, 0x00A0]

    func readU16(bytes: const [..] u8, at: u64)->u16 fail
    {
        if at > bytes.count or 2 > bytes.count - at do
            fail Errors.InvalidFormatError{texts().err_ShortField16}
        return Math.make16(bytes[at + 1], bytes[at])
    }

    func readU32(bytes: const [..] u8, at: u64)->u32 fail
    {
        if at > bytes.count or 4 > bytes.count - at do
            fail Errors.InvalidFormatError{texts().err_ShortField32}
        return Math.make32(bytes[at + 3], bytes[at + 2], bytes[at + 1], bytes[at])
    }

    func readU64(bytes: const [..] u8, at: u64)->u64 fail
    {
        let low  = try readU32(bytes, at)
        let high = try readU32(bytes, at + 4)
        return Math.make64(high, low)
    }

    // Normalizes a stored path to single forward slashes, without a leading or trailing one.
    //
    // Control characters become U+FFFD, so a name cannot disturb the tree that shows it.
    func cleanPath(path: string)->String
    {
        var result: #returntype
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
                result += cast(rune, 0xFFFD)
            else do
                result += value
            previousSlash = false
        }

        while not result.isEmpty() and result.back() == '/' do
            result.removeBack()
        return result
    }

    // Replaces each directory field saturated at its 16- or 32-bit maximum with its ZIP64 extra-field value.
    func applyZip64Extra(extra: const [..] u8, plain, packed, local, disk: *u64) fail
    {
        var at = 0'u64
        while at + 4 <= extra.count
        {
            let kind   = try readU16(extra, at)
            let length = cast(u64, try readU16(extra, at + 2))
            at += 4
            if length > extra.count - at do
                fail Errors.InvalidFormatError{texts().err_ExtraField}
            if kind == 1
            {
                var valueAt = at
                let end     = at + length
                if plain[] == Value32Overflow
                {
                    if valueAt + 8 > end do
                        fail Errors.InvalidFormatError{texts().err_Zip64Uncompressed}
                    plain[] = try readU64(extra, valueAt)
                    valueAt += 8
                }

                if packed[] == Value32Overflow
                {
                    if valueAt + 8 > end do
                        fail Errors.InvalidFormatError{texts().err_Zip64Compressed}
                    packed[] = try readU64(extra, valueAt)
                    valueAt  += 8
                }

                if local[] == Value32Overflow
                {
                    if valueAt + 8 > end do
                        fail Errors.InvalidFormatError{texts().err_Zip64Offset}
                    local[] = try readU64(extra, valueAt)
                    valueAt += 8
                }

                if disk[] == Value16Overflow
                {
                    if valueAt + 4 > end do
                        fail Errors.InvalidFormatError{texts().err_Zip64Disk}
                    disk[] = cast(u64, try readU32(extra, valueAt))
                }

                return
            }

            at += length
        }
    }

    // Returns where the central directory lies and how many entries it holds.
    //
    // `tail` is the mapped end of the file starting at `tailOffset`, and `endAt` locates the end
    // record inside it. A saturated field sends the lookup through the ZIP64 locator and end record.
    func directoryLocation(file: *File.MappedFile,
                           tailOffset: u64,
                           tail: const [..] u8,
                           endAt: u64)->{ offset, size, count: u64 } fail
    {
        with var result: #returntype
        {
            .count  = cast(u64, try readU16(tail, endAt + 10))
            .size   = cast(u64, try readU32(tail, endAt + 12))
            .offset = cast(u64, try readU32(tail, endAt + 16))
        }

        if result.count != Value16Overflow and
           result.size != Value32Overflow and
           result.offset != Value32Overflow do
            return result
        if tailOffset + endAt < 20 do
            fail Errors.InvalidFormatError{texts().err_Zip64Locator}

        let locatorOffset = tailOffset + endAt - 20
        let locator       = try file.map(locatorOffset, 20)
        if try readU32(locator.bytes(), 0) != Zip64LocatorSignature do
            fail Errors.InvalidFormatError{texts().err_Zip64Locator}
        if try readU32(locator.bytes(), 4) or try readU32(locator.bytes(), 16) != 1 do
            fail Errors.UnsupportedFormatError{texts().err_Zip64MultiDisk}
        let recordOffset = try readU64(locator.bytes(), 8)
        let fileSize     = try file.size()
        if recordOffset > fileSize or 56 > fileSize - recordOffset do
            fail Errors.InvalidFormatError{texts().err_Zip64EndOutside}

        let record = try file.map(recordOffset, 56)
        if try readU32(record.bytes(), 0) != Zip64EndSignature do
            fail Errors.InvalidFormatError{texts().err_Zip64EndSignature}
        if try readU32(record.bytes(), 16) or try readU32(record.bytes(), 20) do
            fail Errors.UnsupportedFormatError{texts().err_Zip64MultiDisk}
        if try readU64(record.bytes(), 24) != try readU64(record.bytes(), 32) do
            fail Errors.UnsupportedFormatError{texts().err_Zip64MultiDisk}
        result.count  = try readU64(record.bytes(), 32)
        result.size   = try readU64(record.bytes(), 40)
        result.offset = try readU64(record.bytes(), 48)
        return result
    }
}
