#global public
#global namespace Text

using Swag

// How the bytes of a text file spell their characters.
//
// A reader meets these five families and nothing else in practice: UTF-8 everywhere, UTF-16 from
// Windows APIs and exports, UTF-32 from a few Unix pipelines, and one single-byte page for
// everything written before any of them. `Windows1252` stands for that page: it is a superset of
// Latin-1 that differs only in `0x80`-`0x9F`, where Latin-1 has unused controls and Windows put
// the quotation marks and dashes an actual document uses.
enum Encoding
{
    Utf8           // Variable width, one to four bytes per character.
    Utf16Le        // Two bytes per unit, least significant first, surrogate pairs above the BMP.
    Utf16Be        // Two bytes per unit, most significant first.
    Utf32Le        // Four bytes per character, least significant first.
    Utf32Be        // Four bytes per character, most significant first.
    Windows1252    // One byte per character, code page 1252.
}

// Bytes the encoding writes in front of the content to announce itself, if any.
//
// A byte-order mark is part of the file but not part of the text, so a reader skips exactly this
// many bytes at offset zero and never inside.
func bomLength(encoding: Encoding)->u64
{
    switch encoding
    {
    case .Utf8:                 return 3
    case .Utf16Le, .Utf16Be:    return 2
    case .Utf32Le, .Utf32Be:    return 4
    case .Windows1252:          return 0
    }
}

// Bytes one character occupies, or the size a chunk boundary must be a multiple of.
//
// UTF-8 and code page 1252 return one because a boundary is decided by the content rather than by
// arithmetic: the first cuts on a lead byte, the second cuts anywhere.
func unitSize(encoding: Encoding)->u64
{
    switch encoding
    {
    case .Utf16Le, .Utf16Be:    return 2
    case .Utf32Le, .Utf32Be:    return 4
    default:                    return 1
    }
}

// Reports whether `bytes` opens with the byte-order mark of `encoding`.
func hasBom(bytes: const [..] u8, encoding: Encoding)->bool
{
    let length = bomLength(encoding)
    if !length or @countof(bytes) < length do
        return false

    switch encoding
    {
    case .Utf8:       return bytes[0] == 0xEF and bytes[1] == 0xBB and bytes[2] == 0xBF
    case .Utf16Le:    return bytes[0] == 0xFF and bytes[1] == 0xFE
    case .Utf16Be:    return bytes[0] == 0xFE and bytes[1] == 0xFF
    case .Utf32Le:    return bytes[0] == 0xFF and bytes[1] == 0xFE and bytes[2] == 0 and bytes[3] == 0
    case .Utf32Be:    return bytes[0] == 0 and bytes[1] == 0 and bytes[2] == 0xFE and bytes[3] == 0xFF
    default:          return false
    }
}

// Number of zero bytes at even and at odd offsets of `bytes`.
//
// This is what separates UTF-16 from a single-byte page when no mark says so: text written in
// UTF-16 is mostly Latin, so every other byte is zero, and which half carries them is the byte
// order. Nothing else produces that pattern at that density.
private func countZeroPositions(bytes: const [..] u8)->{ even: u64, odd: u64 }
{
    var result: retval
    for value, index in bytes where !value
    {
        if index & 1 do
            result.odd += 1
        else do
            result.even += 1
    }

    return result
}

// Returns whether `bytes` is valid UTF-8, tolerating a sequence cut by the end of the probe.
private func isValidUtf8Prefix(bytes: const [..] u8)->bool
{
    if Utf8.isValid(bytes) do
        return true

    // A probe is a prefix of a file, so its last character can be incomplete. Only a
    // three-byte tail can be, since that is the longest UTF-8 sequence minus one byte.
    let count = @countof(bytes)
    for back in 1 to 3 where back < count
    {
        if Utf8.isValid(bytes[0 until count - back]) do
            return true
    }

    return false
}

// Decides how `probe` spells its characters.
//
// A byte-order mark answers on its own. Without one the content decides, in the order a wrong
// answer costs the most: valid UTF-8 stays UTF-8, since ASCII is valid UTF-8 and that is the
// overwhelming case; the zero-byte pattern of Latin text in UTF-16 is unmistakable; and what is
// left is read through code page 1252, which accepts every byte and therefore never fails.
//
// Pass the beginning of the file, a few kilobytes at most: a longer probe answers no better and a
// shorter one can miss the first non-ASCII character. Deciding is not the same as accepting — a
// binary file also gets an answer here, so ask [[Core.Text.looksLikeText]] before showing it.
func detectEncoding(probe: const [..] u8)->Encoding
{
    // UTF-32 LE opens with the two bytes of UTF-16 LE, so it has to be tested first.
    for candidate in [Encoding.Utf32Le, .Utf32Be, .Utf8, .Utf16Le, .Utf16Be] where hasBom(probe, candidate) do
        return candidate

    // A null byte is perfectly valid UTF-8, so validity alone would claim every UTF-16 file: what
    // separates them is that text written in UTF-8 never spells a null character at all.
    let zeros = countZeroPositions(probe)
    let total = zeros.even + zeros.odd
    if !total and isValidUtf8Prefix(probe) do
        return .Utf8

    if total * 4 >= @countof(probe)
    {
        if zeros.odd > zeros.even * 4 do
            return .Utf16Le
        if zeros.even > zeros.odd * 4 do
            return .Utf16Be
    }

    return .Windows1252
}

// Characters code page 1252 puts where Latin-1 leaves unused controls, `0x80` through `0x9F`.
private const Windows1252Supplement: [32] rune = [
    0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
    0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
    0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
    0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178]

// Returns the character one code page 1252 byte spells.
func windows1252Rune(value: u8)->rune
{
    if value >= 0x80 and value <= 0x9F do
        return Windows1252Supplement[value - 0x80]
    return cast(rune) value
}

// Reads one unit of `bytes` at `offset`, in the byte order `encoding` names.
private func readUnit(bytes: const [..] u8, offset: u64, encoding: Encoding)->u32
{
    switch encoding
    {
    case .Utf16Le:    return cast(u32) bytes[offset] | (cast(u32) bytes[offset + 1] << 8)
    case .Utf16Be:    return (cast(u32) bytes[offset] << 8) | cast(u32) bytes[offset + 1]
    case .Utf32Le:    return cast(u32) bytes[offset] | (cast(u32) bytes[offset + 1] << 8) | (cast(u32) bytes[offset + 2] << 16) | (cast(u32) bytes[offset + 3] << 24)
    default:          return (cast(u32) bytes[offset] << 24) | (cast(u32) bytes[offset + 1] << 16) | (cast(u32) bytes[offset + 2] << 8) | cast(u32) bytes[offset + 3]
    }
}

// Converts `bytes` to UTF-8, reading them as `encoding` spells characters.
//
// `bytes` must start and end on a character boundary; [[Core.FileStream.readTextChunk]] is what
// guarantees that while streaming. A byte-order mark at the head is content here and is not
// removed: the caller knows whether it is reading offset zero.
//
// Nothing fails. A malformed sequence becomes the replacement character, because a viewer that
// refuses a whole file over one bad byte in the middle is less useful than one that shows the bad
// byte where it is.
func decode(bytes: const [..] u8, encoding: Encoding)->String
{
    var result: retval
    if !@countof(bytes) do
        return result

    switch encoding
    {
    case .Utf8:
        result = @mkstring(@dataof(bytes), @countof(bytes))
        return result

    case .Windows1252:
        var runes: Array'rune
        runes.reserve(@countof(bytes))
        for value in bytes do
            runes.add(windows1252Rune(value))
        result = Utf8.fromUnicode(runes.toSlice())
        return result

    case .Utf16Le, .Utf16Be:
        var runes: Array'rune
        runes.reserve(@countof(bytes) / 2)
        var offset = 0'u64
        while offset + 2 <= @countof(bytes)
        {
            let unit = readUnit(bytes, offset, encoding)
            offset += 2

            // A surrogate pair spells one character across two units; a lone half is the file's
            // error and becomes the replacement character rather than a wrong character.
            if unit >= Utf16.Surr1 and unit < Utf16.Surr2 and offset + 2 <= @countof(bytes)
            {
                let low = readUnit(bytes, offset, encoding)
                if low >= Utf16.Surr2 and low < Utf16.Surr3
                {
                    offset += 2
                    runes.add(cast(rune) (Utf16.SurrSelf + ((unit - Utf16.Surr1) << 10) + (low - Utf16.Surr2)))
                    continue
                }
            }

            if unit >= Utf16.Surr1 and unit < Utf16.Surr3 do
                runes.add(Utf16.RuneError)
            else do
                runes.add(cast(rune) unit)
        }

        result = Utf8.fromUnicode(runes.toSlice())
        return result

    case .Utf32Le, .Utf32Be:
        var runes: Array'rune
        runes.reserve(@countof(bytes) / 4)
        var offset = 0'u64
        while offset + 4 <= @countof(bytes)
        {
            let value = readUnit(bytes, offset, encoding)
            offset += 4
            runes.add(Utf8.isValidRune(cast(rune) value) ? cast(rune) value : Utf16.RuneError)
        }

        result = Utf8.fromUnicode(runes.toSlice())
        return result
    }
}

// Reports whether `probe`, read as `encoding`, is text a reader should be shown.
//
// Every byte means something under code page 1252 and half of them mean something under UTF-16, so
// a decoder alone never says no — an executable decodes into thousands of characters. What
// separates text from a binary that happens to decode is the control characters: a document uses
// tab, newline and carriage return and nothing else below `0x20`, and it never contains a null
// character at all.
func looksLikeText(probe: const [..] u8, encoding: Encoding)->bool
{
    if !@countof(probe) do
        return true

    let text = decode(probe, encoding)
    if text.isEmpty() do
        return false

    var controls = 0'u64
    var count    = 0'u64
    for c in text
    {
        count += 1
        if !c do
            return false
        if c < 0x20 and c != '\t' and c != '\n' and c != '\r' and c != 0x0C do
            controls += 1
    }

    // One in twenty is already generous for a document and far below what any binary reaches.
    return controls * 20 <= count
}
