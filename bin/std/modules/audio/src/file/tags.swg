//! Format: Descriptive tags of sound files.
//! Supported: ID3v2.2, v2.3, and v2.4 text and picture frames at the head of an MP3 file, and the Vorbis comment and picture blocks of a FLAC file.
//! Not supported: ID3v1 trailers, unsynchronised ID3 tags, Ogg and MP4 comments, linked pictures, and writing tags.
//! Role: This file owns reading the title, artist, album artist, album, year and embedded picture a sound file declares.
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
        track:       String     // Position of the recording on its album, as the file spells it (`3` or `3/12`).
        disc:        String     // Disc of a set the recording is on, as the file spells it (`1/2`).
        genre:       String     // Genre named in words; a bare numeric ID3v1 reference is left out.

        // Encoded bytes of the picture the file embeds, its front cover when it names one, and
        // the extension of their format (`.jpg`, `.png`, `.gif`, `.bmp` or `.webp`). Read only
        // when asked for; empty when the file embeds none in a format named here.
        picture: Array'u8
        pictureExtension: String     // File extension of the embedded picture, including its leading dot.
    }

    pictureKind: u8     // Picture type the tag gives `picture`; 3 is the front cover.
}

private const Id3HeaderSize = 10'u64
private const TagSizeLimit  = 16 * 1024 * 1024'u64

impl SoundTags
{
    // Reports whether the file has no descriptive text; embedded artwork does not affect the result.
    mtd const isEmpty()->bool => .title.isEmpty() and
                                 .artist.isEmpty() and
                                 .album.isEmpty() and
                                 .year.isEmpty() and
                                 .albumArtist.isEmpty() and
                                 .track.isEmpty() and
                                 .disc.isEmpty() and
                                 .genre.isEmpty()

    // Reads the tags of `fileName`: the ID3v2 tag that opens an MP3 file, or the Vorbis comment
    // block of a FLAC file. With `withPicture`, the picture the file embeds is read too; a
    // listing that only names recordings leaves it out, as it can weigh megabytes.
    //
    // A file without tags, an unsupported format, a malformed tag, or a tag larger than 16 MiB
    // returns empty tags rather than an error.
    func read(fileName: string, withPicture = false)->SoundTags
    {
        var result: #returntype
        var file = catch File.openReadLive(fileName) { return result }
        defer file.close()

        var head: [Id3HeaderSize] u8
        if not (catch file.readExactAt(0, head) orelse false) do
            return result

        if head[0] == 'I' and head[1] == 'D' and head[2] == '3'
        {
            if not isSyncSafe(head[6 until 10]) do
                return result
            let size = Id3HeaderSize + syncSafe(head[6 until 10])
            if size > TagSizeLimit do
                return result
            var tag: Array'u8
            tag.resize(size)
            if catch file.readExactAt(0, tag.toSlice()) orelse false
            {
                var decoded: SoundTags
                if decoded.decodeId3(tag.toSlice(), withPicture) do
                    return decoded
            }

            return result
        }

        if head[0] == 'f' and head[1] == 'L' and head[2] == 'a' and head[3] == 'C'
        {
            var decoded: SoundTags

            // Metadata blocks follow the signature, each a one-byte type, with the last-block
            // flag in its high bit, and a 24-bit length.
            var offset = 4'u64
            for
            {
                var block: [4] u8
                if not (catch file.readExactAt(offset, block) orelse false) do
                    return result
                let last   = (block[0] & 0x80) != 0
                let kind   = block[0] & 0x7F
                let length = (cast(u64, block[1]) << 16) | (cast(u64, block[2]) << 8) | cast(u64, block[3])
                if (kind == 4 or (kind == 6 and withPicture)) and length > TagSizeLimit do
                    return result
                if kind == 4
                {
                    var comment: Array'u8
                    comment.resize(length)
                    if not (catch file.readExactAt(offset + 4, comment.toSlice()) orelse false) do
                        return result
                    if not decoded.decodeVorbisComment(comment.toSlice()) do
                        return result
                    if not withPicture do
                        return decoded
                }
                elif kind == 6 and withPicture
                {
                    var picture: Array'u8
                    picture.resize(length)
                    if not (catch file.readExactAt(offset + 4, picture.toSlice()) orelse false) do
                        return result
                    if not decoded.decodeFlacPicture(picture.toSlice()) do
                        return result
                }

                if last do
                    break
                offset += 4 + length
            }

            return decoded
        }

        return result
    }
}

internal impl SoundTags
{
    // Reads the text frames of a complete ID3v2 tag, header included, and its picture frames
    // with `withPicture`.
    mtd decodeId3(tag: const [..] u8, withPicture = false)->bool
    {
        if tag.count < Id3HeaderSize do
            return false
        let version = tag[3]
        if version < 2 or version > 4 do
            return false

        // An unsynchronised tag hides its frames behind inserted bytes; a reader that does not
        // undo the scheme would read garbage, so it reads nothing.
        let flags = tag[5]
        if (flags & 0x80) != 0 do
            return false

        var offset = Id3HeaderSize
        var tagEnd = tag.count
        if version == 4 and (flags & 0x10) != 0
        {
            if tagEnd < offset + Id3HeaderSize do
                return false
            let footer = tag[tagEnd - Id3HeaderSize to]
            if footer[0] != '3' or
               footer[1] != 'D' or
               footer[2] != 'I' or
               footer[3] != version or
               footer[4] != tag[4] or
               footer[5] != flags or
               not Slice.equals(footer[6 until 10], tag[6 until 10]) do
                return false
            tagEnd -= Id3HeaderSize
        }

        if version >= 3 and (flags & 0x40) != 0
        {
            if offset + 4 > tagEnd do
                return false
            let extendedBytes = tag[offset until offset + 4]
            if version == 4 and not isSyncSafe(extendedBytes) do
                return false
            let extended = version == 4 ? syncSafe(extendedBytes) : bigEndian(extendedBytes) + 4
            if extended > tagEnd - offset do
                return false
            offset += extended
        }

        let idSize     = version == 2 ? 3'u64 : 4'u64
        let headerSize = version == 2 ? 6'u64 : 10'u64
        while offset < tagEnd
        {
            let remaining = tagEnd - offset
            if remaining < headerSize
            {
                for byte in tag[offset until tagEnd] where byte != 0 do
                    return false
                return true
            }

            let id = cast(string, tag[offset until offset + idSize])
            if tag[offset] == 0
            {
                for byte in tag[offset until tagEnd] where byte != 0 do
                    return false
                return true
            }

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
                let sizeBytes = tag[offset + 4 until offset + 8]
                if not isSyncSafe(sizeBytes) do
                    return false
                size = syncSafe(sizeBytes)
            }

            let body = offset + headerSize
            if size > tagEnd - body do
                return false

            let text = tag[body until body + size]
            switch id
            {
            case "TIT2", "TT2":
                if text.count and text[0] > 3 do
                    return false
                .title = textFrame(text)

            case "TPE1", "TP1":
                if text.count and text[0] > 3 do
                    return false
                .artist = textFrame(text)

            case "TPE2", "TP2":
                if text.count and text[0] > 3 do
                    return false
                .albumArtist = textFrame(text)

            case "TALB", "TAL":
                if text.count and text[0] > 3 do
                    return false
                .album = textFrame(text)

            case "TYER", "TDRC", "TYE":
                if text.count and text[0] > 3 do
                    return false
                .year = yearOf(textFrame(text))

            case "TRCK", "TRK":
                if text.count and text[0] > 3 do
                    return false
                .track = textFrame(text)

            case "TPOS", "TPA":
                if text.count and text[0] > 3 do
                    return false
                .disc = textFrame(text)

            case "TCON", "TCO":
                if text.count and text[0] > 3 do
                    return false
                .genre = genreOf(textFrame(text))

            case "APIC", "PIC":
                if withPicture and not .decodeId3Picture(text, version == 2) do
                    return false
            }

            offset = body + size
        }

        return true
    }

    // Reads one ID3 picture frame: its text encoding, the format (a MIME type, or three letters in
    // ID3v2.2), the picture type, a description, then the picture.
    mtd decodeId3Picture(frame: const [..] u8, threeLetterFormat: bool)->bool
    {
        if frame.count < 2 or frame[0] > 3 do
            return false
        let encoding = frame[0]
        var at       = 1'u64
        if threeLetterFormat
        {
            if frame.count < 5 do
                return false
            at += 3
        }
        else
        {
            while at < frame.count and frame[at] != 0 do
                at += 1
            if at == frame.count do
                return false
            at += 1
        }

        if at >= frame.count do
            return false
        let kind = frame[at]
        at += 1

        // The description ends with one zero byte, or with a zero unit in UTF-16.
        if encoding == 1 or encoding == 2
        {
            var terminated = false
            while at + 1 < frame.count and (frame[at] != 0 or frame[at + 1] != 0) do
                at += 2
            if at + 1 < frame.count do
                terminated = true
            if not terminated do
                return false
            at += 2
        }
        else
        {
            while at < frame.count and frame[at] != 0 do
                at += 1
            if at == frame.count do
                return false
            at += 1
        }

        if at < frame.count do
            .offerPicture(kind, frame[at to])
        return true
    }

    // Reads a FLAC picture block: big-endian picture type, MIME type, description, four
    // dimensions, then the picture.
    mtd decodeFlacPicture(block: const [..] u8)->bool
    {
        if block.count < 8 do
            return false
        let kind = bigEndian(block[0 until 4])
        var at   = 4'u64
        for 2
        {
            if at + 4 > block.count do
                return false
            let length = bigEndian(block[at until at + 4])
            at += 4
            if length > block.count - at do
                return false
            at += length
        }

        if at + 20 > block.count do
            return false
        at += 16
        let length = bigEndian(block[at until at + 4])
        at += 4
        if length > block.count - at do
            return false
        .offerPicture(cast(u8, Math.min(kind, 255)), block[at until at + length])
        return true
    }

    // Keeps `bytes` as the picture when none is kept yet, or when it is the front cover and the
    // kept one is not. A picture in a format not named here is left out.
    mtd offerPicture(kind: u8, bytes: const [..] u8)
    {
        let extension = pictureExtensionOf(bytes)
        if not extension.count do
            return
        if not .picture.isEmpty() and (.pictureKind == 3 or kind != 3) do
            return
        .picture.clear()
        .picture.add(bytes)
        .pictureExtension = extension
        .pictureKind      = kind
    }

    // Reads the title, artist, album artist, album, and date fields of a Vorbis comment block.
    mtd decodeVorbisComment(block: const [..] u8)->bool
    {
        var offset = 0'u64
        if offset + 4 > block.count do
            return false
        let vendor = littleEndian(block[offset until offset + 4])
        offset += 4
        if vendor > block.count - offset do
            return false
        offset += vendor

        if offset + 4 > block.count do
            return false
        let count = littleEndian(block[offset until offset + 4])
        offset += 4

        for count
        {
            if offset + 4 > block.count do
                return false
            let length = littleEndian(block[offset until offset + 4])
            offset += 4
            if length > block.count - offset do
                return false

            let field = cast(string, block[offset until offset + length])
            offset += length
            let equal = Utf8.indexOf(field, "=")
            if equal == Swag.U64.Max do
                return false

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
            elif Utf8.compare(key, "TRACKNUMBER", .Latin1NoCase) == 0 do
                .track = String.from(value)
            elif Utf8.compare(key, "DISCNUMBER", .Latin1NoCase) == 0 do
                .disc = String.from(value)
            elif Utf8.compare(key, "GENRE", .Latin1NoCase) == 0 do
                .genre = String.from(value)
        }

        return offset == block.count
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

// Returns the file extension of the image format `bytes` start with, or an empty string. The
// signature decides rather than the declared MIME type, which taggers often get wrong.
private func pictureExtensionOf(bytes: const [..] u8)->string
{
    if bytes.count >= 3 and bytes[0] == 0xFF and bytes[1] == 0xD8 and bytes[2] == 0xFF do
        return ".jpg"
    if bytes.count >= 8 and
       bytes[0] == 0x89 and
       bytes[1] == 'P' and
       bytes[2] == 'N' and
       bytes[3] == 'G' do
        return ".png"
    if bytes.count >= 4 and bytes[0] == 'G' and bytes[1] == 'I' and bytes[2] == 'F' and bytes[3] == '8' do
        return ".gif"
    if bytes.count >= 12 and
       bytes[0] == 'R' and
       bytes[1] == 'I' and
       bytes[2] == 'F' and
       bytes[3] == 'F' and
       bytes[8] == 'W' and
       bytes[9] == 'E' and
       bytes[10] == 'B' and
       bytes[11] == 'P' do
        return ".webp"
    if bytes.count >= 2 and bytes[0] == 'B' and bytes[1] == 'M' do
        return ".bmp"
    return ""
}

// Returns the year a date field starts with, or the whole field when it does not start with one.
// Returns a genre the way a reader names it. ID3v2.3 may lead the name with a numeric ID3v1
// reference in parentheses, `(17)Rock`; the reference goes, and a reference alone, which only a
// table would name, says nothing.
private func genreOf(value: String)->String
{
    let text = value.toString()
    var at   = 0'u64
    while at < text.count and text[at] == '('
    {
        let close = Utf8.indexOf(text[at to], ")")
        if close == Swag.U64.Max do
            break
        var numeric = close > 1
        for digit in text[at + 1 until at + close] where digit < '0' or digit > '9' do
            numeric = false
        if not numeric do
            break
        at += close + 1
    }

    let rest    = Latin1.trim(text[at to])
    var numeric = rest.count != 0
    for c in rest where not Latin1.isDigit(c) do
        numeric = false
    if numeric do
        return {}
    return String.from(rest)
}

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

private func isSyncSafe(bytes: const [..] u8)->bool
{
    if bytes.count != 4 do
        return false
    for byte in bytes where (byte & 0x80) != 0 do
        return false
    return true
}

private func syncSafe(bytes: const [..] u8)->u64 => (cast(u64, bytes[0]) << 21) |
                                                    (cast(u64, bytes[1]) << 14) |
                                                    (cast(u64, bytes[2]) << 7) |
                                                    cast(u64, bytes[3])
private func bigEndian(bytes: const [..] u8)->u64 => (cast(u64, bytes[0]) << 24) |
                                                     (cast(u64, bytes[1]) << 16) |
                                                     (cast(u64, bytes[2]) << 8) |
                                                     cast(u64, bytes[3])
private func littleEndian(bytes: const [..] u8)->u64 => (cast(u64, bytes[3]) << 24) |
                                                        (cast(u64, bytes[2]) << 16) |
                                                        (cast(u64, bytes[1]) << 8) |
                                                        cast(u64, bytes[0])
