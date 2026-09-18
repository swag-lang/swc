#global internal

using Core

// Bytes one analysis is allowed to hold at once.
//
// A header-driven format puts everything a report reads within a few hundred kilobytes of one end
// or the other, so this bound only ever cuts the tail of a very large archive. When it does, the
// report says so instead of quietly reading short.
const BinaryLoadLimit = 64 * 1024 * 1024'u64

// Loaded prefix of a file, read at absolute offsets in the byte order its format is written in.
//
// No read here fails. A field that runs past what was loaded reads as zero and raises
// [[BinaryImage.truncated]], so a malformed or bounded file still produces a report that names
// every structure it reached rather than stopping at the first bad offset.
#[Swag.NoCopy]
struct BinaryImage
{
    fileSize:      u64                                        // Size the file system reports.
    region:        File.MappedRegion                          // Read-only mapping that owns `bytes`.
    bytes:         const [..] u8 = cast(const [..] u8) ""     // Mapped prefix, at most `BinaryLoadLimit` bytes.
    bigEndian:     bool                                       // Byte order every multi-byte read uses; a parser sets it once.
    truncated:     bool                                       // Whether a read asked for bytes the prefix does not hold.
    failureReason: String                                     // File-system explanation when loading stops before any byte is available.
}

impl BinaryImage
{
    // Loads the beginning of `fileName`, and returns whether anything could be read.
    //
    // On failure, [[BinaryImage.failureReason]] says why.
    mtd load(fileName: string)->bool
    {
        .bytes = cast(const [..] u8) ""
        .region.close()
        .fileSize  = 0
        .truncated = false
        .failureReason.clear()

        var file = catch File.MappedFile.openSnapshot(fileName, BinaryLoadLimit) as openError
        if openError != null
        {
            .failureReason = Errors.message(openError)
            return false
        }

        let metadata = catch File.info(fileName) as sizeError
        if sizeError != null
        {
            .failureReason = Errors.message(sizeError)
            return false
        }

        .fileSize = metadata.size

        .region = catch file.mapAll() as mapError
        if mapError != null
        {
            .failureReason = Errors.message(mapError)
            return false
        }

        .bytes = .region.bytes()
        return true
    }

    // Returns whether `[offset, offset + count)` sits inside the loaded prefix.
    mtd const has(offset, count: u64)->bool => offset <= .bytes.count and count <= .bytes.count - offset

    // Returns whether the file is larger than the prefix that was loaded.
    mtd const isBounded()->bool => .fileSize > .bytes.count

    // Returns whether the bytes at `offset` are exactly `magic`.
    mtd const matches(offset: u64, magic: string)->bool
    {
        let count = magic.count
        if not .has(offset, count) do
            return false
        for index in count where .bytes[offset + index] != magic[index] do
            return false
        return true
    }

    // Returns the unsigned integer stored in `size` bytes at `offset`, in the image byte order.
    mtd scalarAt(offset, size: u64)->u64
    {
        if not .has(offset, size)
        {
            .truncated = true
            return 0
        }

        var result = 0'u64
        for index in size
        {
            let position = .bigEndian ? index : size - 1 - index
            result = (result << 8) | cast(u64) .bytes[offset + position]
        }

        return result
    }

    mtd u8At(offset: u64)->u8   => cast(u8) .scalarAt(offset, 1)
    mtd u16At(offset: u64)->u16 => cast(u16) .scalarAt(offset, 2)
    mtd u32At(offset: u64)->u32 => cast(u32) .scalarAt(offset, 4)
    mtd u64At(offset: u64)->u64 => .scalarAt(offset, 8)

    // Returns the NUL-terminated text at `offset`, bounded by `maxLength` bytes.
    //
    // Names reached this way come from the file, so every byte that is not printable is replaced:
    // a corrupt import table must not be able to put control codes into the view.
    mtd cstringAt(offset: u64, maxLength = 512'u64)->String
    {
        if offset >= .bytes.count
        {
            .truncated = true
            return {}
        }

        let limit = Math.min(.bytes.count, offset + Math.min(maxLength, .bytes.count))
        var end   = offset
        while end < limit and .bytes[end] do
            end += 1
        return .printableAt(offset, end - offset)
    }

    // Returns the `length`-byte field at `offset` as text, without the NULs and blanks that pad its end.
    mtd fixedTextAt(offset, length: u64)->String
    {
        if not .has(offset, length)
        {
            .truncated = true
            return {}
        }

        var end = length
        while end and (.bytes[offset + end - 1] == 0 or .bytes[offset + end - 1] == ' 'u8) do
            end -= 1
        return .printableAt(offset, end)
    }

    // Returns the UTF-16 text at `offset`, up to `maxUnits` code units or the first NUL.
    //
    // Windows writes resource names, version strings, and manifests in UTF-16, so a report that
    // could not read it would have to leave out everything an executable says about itself.
    mtd wideTextAt(offset, maxUnits: u64)->String
    {
        var result: retval
        var index:  u64

        while index < maxUnits
        {
            let unit = .u16At(offset + index * 2)
            if not unit do
                break
            index += 1

            var value = cast(rune) unit
            if unit >= 0xD800 and unit < 0xDC00 and index < maxUnits
            {
                let low = .u16At(offset + index * 2)
                if low >= 0xDC00 and low < 0xE000
                {
                    value = cast(rune) (0x10000 + ((cast(u32) unit - 0xD800) << 10) + (cast(u32) low - 0xDC00))
                    index += 1
                }
            }

            result.append(value < 32 ? cast(rune) '.' : value)
        }

        return result
    }

    // Returns the GUID at `offset` in the mixed-endian form Microsoft tools print it in.
    //
    // The first three fields are stored little endian and the last two big endian, so the order the
    // bytes are printed in is not the order they are stored in.
    mtd const guidTextAt(offset: u64)->String => .identifierTextAt(offset, mixedEndian: true)

    // Returns the UUID at `offset` in the plain byte order Apple's tools print it in.
    mtd const uuidTextAt(offset: u64)->String => .identifierTextAt(offset, mixedEndian: false)

    // Returns the sixteen bytes at `offset` in the hexadecimal 8-4-4-4-12 grouping of an identifier.
    //
    // `mixedEndian` reads the first three fields little endian. A prefix too short to hold the bytes
    // gives [[BinaryNoValue]].
    private mtd const identifierTextAt(offset: u64, mixedEndian: bool)->String
    {
        if not .has(offset, 16) do
            return String.from(BinaryNoValue)

        const MixedOrder = [3'u64, 2, 1, 0, 5, 4, 7, 6, 8, 9, 10, 11, 12, 13, 14, 15]

        var text: Array'u8
        for index in 16'u64
        {
            if index == 4 or index == 6 or index == 8 or index == 10 do
                text.add('-'u8)
            let value  = .bytes[offset + (mixedEndian ? MixedOrder[index] : index)]
            let digits = [cast(u8) (value >> 4), value & 0xF]
            for nibble in digits do
                text.add(nibble < 10 ? '0'u8 + nibble : 'A'u8 + nibble - 10)
        }

        return String.from(cast(string) text.toSlice())
    }

    // Returns `length` bytes at `offset` with every unprintable byte shown as a dot.
    private mtd const printableAt(offset, length: u64)->String
    {
        if not length or not .has(offset, length) do
            return {}

        var text: Array'u8
        text.reserve(length)
        for index in length
        {
            let value = .bytes[offset + index]
            text.add(value >= 32 and value < 127 ? value : '.'u8)
        }

        return String.from(cast(string) text.toSlice())
    }
}
