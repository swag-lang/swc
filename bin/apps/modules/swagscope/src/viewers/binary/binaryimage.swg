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
    // Loads the beginning of `fileName` and reports whether anything could be read.
    mtd load(fileName: string)->bool
    {
        .bytes = cast(const [..] u8) ""
        .region.close()
        .fileSize  = 0
        .truncated = false
        .failureReason.clear()

        var file = catch File.MappedFile.open(fileName) as openError
        if openError != null
        {
            .failureReason = Errors.message(openError)
            return false
        }

        let size = catch file.size() as sizeError
        if sizeError != null
        {
            .failureReason = Errors.message(sizeError)
            return false
        }

        .fileSize = size

        .region = catch file.map(0, Math.min(size, BinaryLoadLimit)) as mapError
        if mapError != null
        {
            .failureReason = Errors.message(mapError)
            return false
        }

        .bytes = .region.bytes()
        return true
    }

    // Returns whether `[offset, offset + count)` sits inside the loaded prefix.
    mtd const has(offset, count: u64)->bool
    {
        return offset <= .bytes.count and count <= .bytes.count - offset
    }

    // Returns whether the file is larger than the prefix that was loaded.
    mtd const isBounded()->bool => .fileSize > .bytes.count

    // Returns whether the bytes at `offset` are exactly `magic`.
    mtd const matches(offset: u64, magic: string)->bool
    {
        let count = magic.count
        if !.has(offset, count) do
            return false
        for index in count where .bytes[offset + index] != magic[index] do
            return false
        return true
    }

    // Returns `[offset, offset + count)`, or an empty slice when the prefix does not hold it.
    mtd const slice(offset, count: u64)->const [..] u8
    {
        if !.has(offset, count) do
            return .bytes[0 until 0]
        return .bytes[offset until offset + count]
    }

    // Assembles `size` bytes at `offset` in the image byte order.
    mtd scalarAt(offset, size: u64)->u64
    {
        if !.has(offset, size)
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

    // Returns the fixed-width text at `offset`, cut at its first NUL and trimmed of trailing blanks.
    mtd fixedTextAt(offset, length: u64)->String
    {
        if !.has(offset, length)
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
            if !unit do
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

    // Returns `length` bytes at `offset` with every unprintable byte shown as a dot.
    private mtd const printableAt(offset, length: u64)->String
    {
        if !length or !.has(offset, length) do
            return {}

        var text: Array'u8
        text.reserve(length)
        for index in length
        {
            let value = .bytes[offset + index]
            text.add(value >= 32 and value < 127 ? value : '.'u8)
        }

        return String.from(Swag.makeString(text.buffer!, text.count))
    }
}
