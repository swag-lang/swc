#global public
#global namespace Viewer

using Core

// Returns the standard spelling of a text encoding, as a reader chooses or reads it.
//
// It is the name of a format rather than prose, so it reads the same in every language.
func encodingName(encoding: Text.Encoding)->string
{
    switch #complete encoding
    {
    case .Utf8:        return "UTF-8"
    case .Utf16Le:     return "UTF-16 LE"
    case .Utf16Be:     return "UTF-16 BE"
    case .Utf32Le:     return "UTF-32 LE"
    case .Utf32Be:     return "UTF-32 BE"
    case .Windows1252: return "Windows-1252"
    }
}

// What the head of a file says about how it spells its characters.
struct TextProbe
{
    encoding:     Text.Encoding     // How the bytes read as characters.
    contentStart: u64               // First byte of text, past a byte-order mark.
    accepted:     bool              // Whether the decoded sample reads as text.
}

// Reads the head of a file once and reports how it spells its characters.
//
// A file that cannot be read reports the default probe, which accepts nothing.
func probeTextFile(fileName: string)->TextProbe
{
    var stream = catch File.openReadLive(fileName) { return {} }
    return catch probeTextStream(&stream) { return {} }
}

// Reads the encoding probe from an open stream at its beginning, leaving it after the probe.
internal func probeTextStream(stream: *File.FileStream)->TextProbe fail
{
    var bytes: Array'u8
    bytes.resize(Viewer.ProbeHeadSize)
    let count = try stream.read(bytes.toSlice())
    bytes.resize(count)
    return probeTextHead(bytes.toSlice())
}

// Reads a bounded, decoded excerpt without including a byte-order mark or splitting a character.
internal func readTextPrefix(fileName: string, budget: u64)->String fail
{
    var stream = try File.openReadLive(fileName)
    let probe = try probeTextStream(&stream)
    if not probe.accepted do
        return {}
    try stream.seek(.Begin, probe.contentStart)
    return try stream.readTextChunk(budget, probe.encoding)
}

// Reports how the beginning of a file spells its characters, and whether it is text at all.
//
// Deciding and accepting are two questions: code page 1252 gives every byte a meaning, so an
// executable also decodes into characters. The encoding answers the first, and what those
// characters are answers the second.
func probeTextHead(head: const [..] u8)->TextProbe
{
    var result: #returntype
    result.encoding     = Text.detectEncoding(head)
    result.contentStart = Text.hasBom(head, result.encoding) ? Text.bomLength(result.encoding) : 0
    result.accepted     = Text.looksLikeText(head[result.contentStart to], result.encoding)
    return result
}

// Returns the byte width of a decoded character in its source file.
internal func sourceRuneWidth(c: rune, utf8Width: u32, encoding: Text.Encoding)->u64
{
    switch #complete encoding
    {
    case .Utf8:              return utf8Width
    case .Utf16Le, .Utf16Be: return c > 0xFFFF ? 4 : 2
    case .Utf32Le, .Utf32Be: return 4
    case .Windows1252:       return 1
    }
}

// Returns the file byte count for a slice of decoded UTF-8 text, excluding any file marker.
internal func sourceByteCount(text: string, encoding: Text.Encoding)->u64
{
    if encoding == .Utf8 do
        return text.count
    var count: u64
    Utf8.visitRunes(text)
    {
        count += sourceRuneWidth(c, 0, encoding)
    }
    return count
}

// Maps a file byte position to a UTF-8 editor position, rounding down within a character.
func decodedTextOffset(text: string, offset: u64, encoding: Text.Encoding)->u64
{
    if encoding == .Utf8 do
        return Math.min(offset, text.count)
    var decoded, source: u64
    while decoded < text.count and source < offset
    {
        let r = Utf8.decodeRune(text[decoded to])
        let end = source + sourceRuneWidth(r.c, r.eat, encoding)
        if end > offset or not r.eat do
            break
        decoded += r.eat
        source = end
    }
    return decoded
}
