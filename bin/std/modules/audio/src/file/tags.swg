//! Format: Descriptive tags of sound files.
//! Supported: ID3v2.2, v2.3, and v2.4 text frames at the head of an MP3 file, and the Vorbis comment block of a FLAC file.
//! Not supported: ID3v1 trailers, unsynchronised ID3 tags, Ogg and MP4 comments, pictures, and writing tags.
//! Role: This file owns reading the title, artist, album artist, album, and year a sound file declares.
//
#global public

using Core

// What a sound file says about the recording it holds.
//
// Every field is empty when the file does not name it.
struct SoundTags
{
    public
    {
        title:       String     // Name of the recording.
        artist:      String     // Performer or author of the recording.
        album:       String     // Collection the recording belongs to.
        year:        String     // Year of the recording or its release, as the file spells it.
        albumArtist: String     // Performer credited to the album, when the tag names one.
    }
}

private const Id3HeaderSize = 10'u64
private const TagSizeLimit  = 16 * 1024 * 1024'u64

impl SoundTags
{
    // Reports whether the file named nothing at all.
    mtd const isEmpty()->bool => .title.isEmpty() and
                                 .artist.isEmpty() and
                                 .album.isEmpty() and
                                 .year.isEmpty() and
                                 .albumArtist.isEmpty()

    // Reads the tags of `fileName`: the ID3v2 tag that opens an MP3 file, or the Vorbis comment
    // block of a FLAC file.
    //
    // Tags only describe a recording, so a file without them, a format this reader does not
    // know, a tag larger than 16 MiB, or one that does not decode all give empty tags rather
    // than an error.
    func read(fileName: string)->SoundTags
    {
        var result: #returntype
        var file = catch File.openReadLive(fileName) { return result }
        defer file.close()

        var head: [Id3HeaderSize] u8
        if not (catch file.readExactAt(0, head)) do
            return result

        if head[0] == 'I' and head[1] == 'D' and head[2] == '3'
        {
            let size = Id3HeaderSize + syncSafe(head[6 until 10])
            if size > TagSizeLimit do
                return result
            var tag: Array'u8
            tag.resize(size)
            if catch file.readExactAt(0, tag.toSlice()) do
                result.decodeId3(tag.toSlice())
            return result
        }

        if head[0] == 'f' and head[1] == 'L' and head[2] == 'a' and head[3] == 'C'
        {
            // Metadata blocks follow the signature, each a one-byte type, with the last-block
            // flag in its high bit, and a 24-bit length.
            var offset = 4'u64
            for
            {
                var block: [4] u8
                if not (catch file.readExactAt(offset, block)) do
                    break
                let last   = (block[0] & 0x80) != 0
                let kind   = block[0] & 0x7F
                let length = (cast(u64, block[1]) << 16) | (cast(u64, block[2]) << 8) | cast(u64, block[3])
                if kind == 4
                {
                    if length > TagSizeLimit do
                        break
                    var comment: Array'u8
                    comment.resize(length)
                    if catch file.readExactAt(offset + 4, comment.toSlice()) do
                        result.decodeVorbisComment(comment.toSlice())
                    break
                }

                if last do
                    break
                offset += 4 + length
            }
        }

        return result
    }
}

internal impl SoundTags
{
    // Reads the text frames of a complete ID3v2 tag, header included.
    mtd decodeId3(tag: const [..] u8)
    {
        if tag.count < Id3HeaderSize do
            return
        let version = tag[3]
        if version < 2 or version > 4 do
            return

        // An unsynchronised tag hides its frames behind inserted bytes; a reader that does not
        // undo the scheme would read garbage, so it reads nothing.
        let flags = tag[5]
        if (flags & 0x80) != 0 do
            return

        var offset = Id3HeaderSize
        if version >= 3 and (flags & 0x40) != 0
        {
            if offset + 4 > tag.count do
                return
            let extended = version == 4 ? syncSafe(tag[offset until offset + 4]) : bigEndian(tag[offset until offset + 4]) + 4
            offset += extended
        }

        let idSize     = version == 2 ? 3'u64 : 4'u64
        let headerSize = version == 2 ? 6'u64 : 10'u64
        while offset + headerSize <= tag.count
        {
            let id = cast(string, tag[offset until offset + idSize])
            if tag[offset] == 0 do
                break

            var size: u64
            switch version
            {
            case 2:
                size = (cast(u64, tag[offset + 3]) << 16) |
                       (cast(u64, tag[offset + 4]) << 8) |
                       cast(u64, tag[offset + 5])

            case 3:
                size = bigEndian(tag[offset + 4 until offset + 8])

            default:
                size = syncSafe(tag[offset + 4 until offset + 8])
            }

            let body = offset + headerSize
            if size > tag.count - body do
                break

            let text = tag[body until body + size]
            switch id
            {
            case "TIT2", "TT2":         .title = textFrame(text)
            case "TPE1", "TP1":         .artist = textFrame(text)
            case "TPE2", "TP2":         .albumArtist = textFrame(text)
            case "TALB", "TAL":         .album = textFrame(text)
            case "TYER", "TDRC", "TYE": .year = yearOf(textFrame(text))
            }

            offset = body + size
        }
    }

    // Reads the title, artist, album artist, album, and date fields of a Vorbis comment block.
    mtd decodeVorbisComment(block: const [..] u8)
    {
        var offset = 0'u64
        if offset + 4 > block.count do
            return
        let vendor = littleEndian(block[offset until offset + 4])
        offset += 4
        if vendor > block.count - offset do
            return
        offset += vendor

        if offset + 4 > block.count do
            return
        let count = littleEndian(block[offset until offset + 4])
        offset += 4

        for count
        {
            if offset + 4 > block.count do
                return
            let length = littleEndian(block[offset until offset + 4])
            offset += 4
            if length > block.count - offset do
                return

            let field = cast(string, block[offset until offset + length])
            offset += length
            let equal = Utf8.indexOf(field, "=")
            if equal == Swag.U64.Max do
                continue

            // Field names are case-insensitive ASCII.
            let key   = field[until equal]
            let value = Latin1.trim(field[equal + 1 to])
            if Utf8.compare(key, "TITLE", .Latin1NoCase) == 0 do
                .title = String.from(value)
            elif Utf8.compare(key, "ARTIST", .Latin1NoCase) == 0 do
                .artist = String.from(value)
            elif Utf8.compare(key, "ALBUMARTIST", .Latin1NoCase) == 0 or Utf8.compare(key, "ALBUM ARTIST", .Latin1NoCase) == 0 do
                .albumArtist = String.from(value)
            elif Utf8.compare(key, "ALBUM", .Latin1NoCase) == 0 do
                .album = String.from(value)
            elif Utf8.compare(key, "DATE", .Latin1NoCase) == 0 do
                .year = yearOf(String.from(value))
        }
    }
}

// Returns the value of an ID3 text frame: its first string, in the encoding its first byte names.
private func textFrame(frame: const [..] u8)->String
{
    // The text is decoded into its own string and trimmed into the result: trimming a view of
    // the return slot into that same slot would read the bytes it is overwriting.
    var result: String
    if not frame.count do
        return result

    let body = frame[1 to]
    switch frame[0]
    {
    case 1, 2:

        // UTF-16, with a byte-order mark for encoding 1 and big-endian without one for 2.
        var bigEndianUnits = frame[0] == 2
        var start = 0'u64
        if frame[0] == 1 and body.count >= 2
        {
            bigEndianUnits = body[0] == 0xFE and body[1] == 0xFF
            start = 2
        }

        var units: Array'u16
        var index = start
        while index + 1 < body.count
        {
            let unit = bigEndianUnits ? (cast(u16, body[index]) << 8) | cast(u16, body[index + 1]) : (cast(u16, body[index + 1]) << 8) | cast(u16, body[index])
            if unit == 0 do
                break
            units.add(unit)
            index += 2
        }

        result = Utf8.fromUtf16(units.toSlice())

    case 3:
        var end = 0'u64
        while end < body.count and body[end] != 0 do
            end += 1
        result = String.from(cast(string, body[until end]))

    default:

        // ISO-8859-1, whose code points are its byte values.
        for byte in body
        {
            if byte == 0 do
                break
            result += cast(rune, byte)
        }
    }

    return String.from(Latin1.trim(result.toString()))
}

// Returns the year a date field starts with, or the whole field when it does not start with one.
private func yearOf(date: String)->String
{
    if date.count >= 4
    {
        var digits = true
        for index in 4 where date[index] < '0' or date[index] > '9' do
            digits = false
        if digits do
            return String.from(date.toString()[until 4])
    }

    return date
}

private func syncSafe(bytes: const [..] u8)->u64 => (cast(u64, bytes[0] & 0x7F) << 21) |
                                                    (cast(u64, bytes[1] & 0x7F) << 14) |
                                                    (cast(u64, bytes[2] & 0x7F) << 7) |
                                                    cast(u64, bytes[3] & 0x7F)
private func bigEndian(bytes: const [..] u8)->u64 => (cast(u64, bytes[0]) << 24) |
                                                     (cast(u64, bytes[1]) << 16) |
                                                     (cast(u64, bytes[2]) << 8) |
                                                     cast(u64, bytes[3])
private func littleEndian(bytes: const [..] u8)->u64 => (cast(u64, bytes[3]) << 24) |
                                                        (cast(u64, bytes[2]) << 16) |
                                                        (cast(u64, bytes[1]) << 8) |
                                                        cast(u64, bytes[0])
