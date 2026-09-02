#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func scalarCountZeroPositions(bytes: const [..] u8)->{ even: u64, odd: u64 }
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

// A byte-order mark answers on its own, and UTF-32 LE is not read as UTF-16 LE even though it
// opens with the same two bytes.
#test
{
    let utf8:    [4] u8 = [0xEF, 0xBB, 0xBF, 'a']
    let utf16le: [4] u8 = [0xFF, 0xFE, 'a', 0]
    let utf16be: [4] u8 = [0xFE, 0xFF, 0, 'a']
    let utf32le: [8] u8 = [0xFF, 0xFE, 0, 0, 'a', 0, 0, 0]
    let utf32be: [8] u8 = [0, 0, 0xFE, 0xFF, 0, 0, 0, 'a']

    Swag.assert(Text.detectEncoding(utf8) == .Utf8)
    Swag.assert(Text.detectEncoding(utf16le) == .Utf16Le)
    Swag.assert(Text.detectEncoding(utf16be) == .Utf16Be)
    Swag.assert(Text.detectEncoding(utf32le) == .Utf32Le)
    Swag.assert(Text.detectEncoding(utf32be) == .Utf32Be)

    Swag.assert(Text.hasBom(utf16le, .Utf16Le) and !Text.hasBom(utf16le, .Utf16Be))
    Swag.assert(Text.bomLength(.Utf8) == 3 and Text.bomLength(.Windows1252) == 0)
    Swag.assert(Text.unitSize(.Utf16Be) == 2 and Text.unitSize(.Utf32Le) == 4 and Text.unitSize(.Windows1252) == 1)
}

// Compare the vector mask split with the original scalar definition for every tail and for
// arbitrary zero positions on both parities.
#test
{
    var bytes: [80] u8
    for index in bytes.count do
        bytes[index] = ((index * 13 + 5) % 11) ? cast(u8) (index + 1) : 0

    for idx in 80
    {
        let slice    = Swag.makeSlice(bytes.buffer, idx)
        let actual   = Text.countZeroPositions(slice)
        let expected = scalarCountZeroPositions(slice)
        Swag.assert(actual.even == expected.even)
        Swag.assert(actual.odd == expected.odd)
    }
}

// Without a mark the content decides: ASCII stays UTF-8, the zero-byte pattern of Latin text in
// UTF-16 names its byte order, and a byte sequence that is none of those is a single-byte page.
#test
{
    Swag.assert(Text.detectEncoding(cast(const [..] u8) "plain ascii line\n") == .Utf8)
    Swag.assert(Text.detectEncoding(cast(const [..] u8) "café naïve\n") == .Utf8)

    let le: [12] u8 = ['H', 0, 'e', 0, 'l', 0, 'l', 0, 'o', 0, '!', 0]
    let be: [12] u8 = [0, 'H', 0, 'e', 0, 'l', 0, 'l', 0, 'o', 0, '!']
    Swag.assert(Text.detectEncoding(le) == .Utf16Le)
    Swag.assert(Text.detectEncoding(be) == .Utf16Be)

    // 0xE9 alone is not valid UTF-8 and carries no zero pattern: code page 1252 accepts it.
    let cp1252: [7] u8 = ['c', 'a', 'f', 0xE9, '\n', 'o', 'k']
    Swag.assert(Text.detectEncoding(cp1252) == .Windows1252)
}

// A probe is a prefix, so a multi-byte sequence cut by its end must not demote a UTF-8 file.
#test
{
    let full = cast(const [..] u8) "aaaaé"
    Swag.assert(Text.detectEncoding(full[0 until full.count - 1]) == .Utf8)
}

// Decoding produces the same UTF-8 whatever the source spells it in, including above the BMP.
#test
{
    let le:  [12] u8 = ['H', 0, 'e', 0, 'l', 0, 'l', 0, 'o', 0, '!', 0]
    let be:  [12] u8 = [0, 'H', 0, 'e', 0, 'l', 0, 'l', 0, 'o', 0, '!']
    let l32: [8] u8  = ['H', 0, 0, 0, 'i', 0, 0, 0]
    let b32: [8] u8  = [0, 0, 0, 'H', 0, 0, 0, 'i']

    Swag.assert(Text.decode(le, .Utf16Le) == "Hello!")
    Swag.assert(Text.decode(be, .Utf16Be) == "Hello!")
    Swag.assert(Text.decode(l32, .Utf32Le) == "Hi")
    Swag.assert(Text.decode(b32, .Utf32Be) == "Hi")

    // U+1F600, as a surrogate pair in both orders.
    let emojiLe: [4] u8 = [0x3D, 0xD8, 0x00, 0xDE]
    let emojiBe: [4] u8 = [0xD8, 0x3D, 0xDE, 0x00]
    Swag.assert(Text.decode(emojiLe, .Utf16Le) == "\U0001F600")
    Swag.assert(Text.decode(emojiBe, .Utf16Be) == "\U0001F600")

    // A lone surrogate is the file's error and becomes the replacement character.
    let lone: [2] u8 = [0x3D, 0xD8]
    Swag.assert(Text.decode(lone, .Utf16Le) == "�")
}

// Endian conversion processes complete vectors and scalar tails identically for UTF-16 and
// UTF-32, including two-byte BMP characters, surrogate pairs and invalid runes.
#test
{
    var utf16: [24] u16
    var le16:  [48] u8
    var be16:  [48] u8
    for index in utf16.count
    {
        let value = cast(u16) (0x80 + index * 53 % 0x780)
        utf16[index]        = value
        le16[2 * index]     = cast(u8) (value & 0xFF)
        le16[2 * index + 1] = cast(u8) (value >> 8)
        be16[2 * index]     = cast(u8) (value >> 8)
        be16[2 * index + 1] = cast(u8) (value & 0xFF)
    }

    for count in utf16.count + 1
    {
        let expected = Utf8.fromUtf16(Swag.makeSlice(utf16.buffer, count))
        Swag.assert(Text.decode(Swag.makeSlice(le16.buffer, 2 * count), .Utf16Le) == expected)
        Swag.assert(Text.decode(Swag.makeSlice(be16.buffer, 2 * count), .Utf16Be) == expected)
    }

    let utf32: [9] rune = ['A'rune, 0x80, 0x7FF, 0x800, 0x20AC, 0xD800, 0x10000, 0x10FFFF, 0x110000]
    var le32:  [4 * utf32.count] u8
    var be32:  [4 * utf32.count] u8
    for value, index in utf32
    {
        let bits = cast(u32) value
        le32[4 * index]     = cast(u8) (bits & 0xFF)
        le32[4 * index + 1] = cast(u8) ((bits >> 8) & 0xFF)
        le32[4 * index + 2] = cast(u8) ((bits >> 16) & 0xFF)
        le32[4 * index + 3] = cast(u8) (bits >> 24)
        be32[4 * index]     = cast(u8) (bits >> 24)
        be32[4 * index + 1] = cast(u8) ((bits >> 16) & 0xFF)
        be32[4 * index + 2] = cast(u8) ((bits >> 8) & 0xFF)
        be32[4 * index + 3] = cast(u8) (bits & 0xFF)
    }

    for count in utf32.count + 1
    {
        let expected = Utf8.fromUnicode(Swag.makeSlice(utf32.buffer, count))
        Swag.assert(Text.decode(Swag.makeSlice(le32.buffer, 4 * count), .Utf32Le) == expected)
        Swag.assert(Text.decode(Swag.makeSlice(be32.buffer, 4 * count), .Utf32Be) == expected)
    }
}

// Code page 1252 is Latin-1 plus the punctuation an actual document uses, where Latin-1 leaves
// unused controls.
#test
{
    let bytes: [5] u8 = ['c', 'a', 'f', 0xE9, 0x85]
    Swag.assert(Text.decode(bytes, .Windows1252) == "café…")
    Swag.assert(Text.windows1252Rune(0x80) == 0x20AC)
    Swag.assert(Text.windows1252Rune(0x93) == 0x201C)
    Swag.assert(Text.windows1252Rune(0xE9) == 0x00E9)
}

// Every byte means something under code page 1252, so accepting a file cannot be left to the
// decoder: a null character or a crowd of controls is what says binary.
#test
{
    Swag.assert(Text.looksLikeText(cast(const [..] u8) "a line\tand\r\nanother\n", .Utf8))

    let withNul: [4] u8 = ['a', 0, 'b', 'c']
    Swag.assert(!Text.looksLikeText(withNul, .Windows1252))

    let controls: [8] u8 = [1, 2, 3, 4, 5, 6, 7, 'a']
    Swag.assert(!Text.looksLikeText(controls, .Windows1252))

    // The same zero bytes are ordinary content once they are read as UTF-16.
    let le: [12] u8 = ['H', 0, 'e', 0, 'l', 0, 'l', 0, 'o', 0, '!', 0]
    Swag.assert(Text.looksLikeText(le, .Utf16Le))
}

// A streamed segment never splits a character, and the position advances by the bytes consumed
// rather than by the length of the UTF-8 it returned.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("core_textchunk_%.bin", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    // "Hello!" repeated, in UTF-16 LE, with one emoji whose surrogate pair straddles a boundary.
    var bytes: Array'u8
    for 5
    {
        for c in "Hello!"
        {
            bytes.add(cast(u8) c)
            bytes.add(0)
        }
    }

    bytes.add(0x3D)
    bytes.add(0xD8)
    bytes.add(0x00)
    bytes.add(0xDE)
    discard expect File.writeAllBytes(fileName, bytes.toSlice())

    var stream = expect File.openRead(fileName)
    defer stream.close()

    var text: String
    var reads = 0'u32
    for 64
    {
        let chunk = expect stream.readTextChunk(10, .Utf16Le)
        if chunk.isEmpty() do
            break
        text  += chunk
        reads += 1
    }

    Swag.assert(reads > 1)
    Swag.assert(text == "Hello!Hello!Hello!Hello!Hello!\U0001F600")
    Swag.assert(expect stream.position() == bytes.count)
}
