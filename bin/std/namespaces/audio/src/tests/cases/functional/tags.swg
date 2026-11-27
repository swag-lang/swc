#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Appends one ID3v2.3 frame: its identifier, big-endian size, two flag bytes, and body.
func appendId3Frame(tag: *Array!{u8}, id: string, body: const [..] u8)
{
    for byte in id
    {
        tag.add(byte)
    }

    tag.add(cast(u8, (body.count >> 24) & 0xFF))
    tag.add(cast(u8, (body.count >> 16) & 0xFF))
    tag.add(cast(u8, (body.count >> 8) & 0xFF))
    tag.add(cast(u8, body.count & 0xFF))
    tag.add(0_u8)
    tag.add(0_u8)
    for byte in body
    {
        tag.add(byte)
    }
}

// Appends one ID3v2.2 frame: its three-byte identifier, 24-bit size, and body.
func appendId3v22Frame(tag: *Array!{u8}, id: string, body: const [..] u8)
{
    for byte in id
    {
        tag.add(byte)
    }

    tag.add(cast(u8, (body.count >> 16) & 0xFF))
    tag.add(cast(u8, (body.count >> 8) & 0xFF))
    tag.add(cast(u8, body.count & 0xFF))
    for byte in body
    {
        tag.add(byte)
    }
}

// Appends one ID3v2.4 frame: its identifier, syncsafe size, and two flag bytes.
func appendId3v24Frame(tag: *Array!{u8}, id: string, body: const [..] u8)
{
    for byte in id
    {
        tag.add(byte)
    }

    tag.add(cast(u8, (body.count >> 21) & 0x7F))
    tag.add(cast(u8, (body.count >> 14) & 0x7F))
    tag.add(cast(u8, (body.count >> 7) & 0x7F))
    tag.add(cast(u8, body.count & 0x7F))
    tag.add(0_u8)
    tag.add(0_u8)
    for byte in body
    {
        tag.add(byte)
    }
}

// Appends a little-endian 32-bit length, as a Vorbis comment block spells every count.
func appendLittle32(block: *Array!{u8}, value: u64)
{
    for shift in 4
    {
        block.add(cast(u8, (value >> (shift * 8)) & 0xFF))
    }
}

// An MP3 file names its recording in an ID3v2 tag, in Latin-1 or UTF-16 text frames.
#test
{
    var frames: Array!{u8}
    var title:  Array!{u8}
    title.add(3_u8)
    for byte in "Gymnopédie No. 1"
    {
        title.add(byte)
    }

    appendId3Frame(&frames, "TIT2", title.toSlice())

    // "Trois Gymnopédies" in ISO-8859-1, where é is the single byte 0xE9.
    var album: Array!{u8}
    album.add(0_u8)
    for byte in "Trois Gymnop"
    {
        album.add(byte)
    }

    album.add(0xE9_u8)
    for byte in "dies"
    {
        album.add(byte)
    }

    appendId3Frame(&frames, "TALB", album.toSlice())

    // "Satie" in UTF-16 with a little-endian byte-order mark.
    var artist: Array!{u8}
    artist.add(1_u8)
    artist.add(0xFF_u8)
    artist.add(0xFE_u8)
    for byte in "Satie"
    {
        artist.add(byte)
        artist.add(0_u8)
    }

    appendId3Frame(&frames, "TPE1", artist.toSlice())
    var albumArtist: Array!{u8}
    albumArtist.add(3_u8)
    for byte in "Various Artists"
    {
        albumArtist.add(byte)
    }

    appendId3Frame(&frames, "TPE2", albumArtist.toSlice())
    var year: Array!{u8}
    year.add(0_u8)
    for byte in "1888"
    {
        year.add(byte)
    }

    appendId3Frame(&frames, "TYER", year.toSlice())
    for frame in [{id: "TRCK", text: "1/3"}, {id: "TPOS", text: "1/1"}, {id: "TCON", text: "(32)Classical"}]
    {
        var body: Array!{u8}
        body.add(0_u8)
        for byte in frame.text
        {
            body.add(byte)
        }

        appendId3Frame(&frames, frame.id, body.toSlice())
    }

    var file: Array!{u8}
    for byte in "ID3"
    {
        file.add(byte)
    }

    file.add(3_u8)
    file.add(0_u8)
    file.add(0_u8)
    let size = frames.count
    file.add(cast(u8, (size >> 21) & 0x7F))
    file.add(cast(u8, (size >> 14) & 0x7F))
    file.add(cast(u8, (size >> 7) & 0x7F))
    file.add(cast(u8, size & 0x7F))
    for byte in frames
    {
        file.add(byte)
    }

    file.add(0xFF_u8)
    file.add(0xFB_u8)

    let fileName = Path.combine(Env.getSpecialDirectory(.Temp).toString(), Format.toString("swag_audio_tags_%.mp3", Guid64.random()).toString())
    defer discard catch File.delete(fileName)
    discard expect File.writeAllBytes(fileName, file.toSlice())

    let tags = SoundTags.read(fileName)
    Swag.require(tags.title == "Gymnopédie No. 1" and tags.artist == "Satie" and tags.year == "1888")
    Swag.require(tags.album == "Trois Gymnopédies")
    Swag.require(tags.albumArtist == "Various Artists")
    Swag.require(tags.track == "1/3" and tags.disc == "1/1" and tags.genre == "Classical", tags.genre)
}

// ID3v2.2 uses three-byte frame identifiers and a 24-bit body size.
#test
{
    var frames: Array!{u8}
    var title:  Array!{u8}
    title.add(0_u8)
    for byte in "Aria"
    {
        title.add(byte)
    }

    appendId3v22Frame(&frames, "TT2", title.toSlice())

    var artist: Array!{u8}
    artist.add(3_u8)
    for byte in "Bach"
    {
        artist.add(byte)
    }

    appendId3v22Frame(&frames, "TP1", artist.toSlice())

    var file: Array!{u8}
    for byte in "ID3"
    {
        file.add(byte)
    }

    file.add(2_u8)
    file.add(0_u8)
    file.add(0_u8)
    let size = frames.count
    file.add(cast(u8, (size >> 21) & 0x7F))
    file.add(cast(u8, (size >> 14) & 0x7F))
    file.add(cast(u8, (size >> 7) & 0x7F))
    file.add(cast(u8, size & 0x7F))
    file.add(frames.toSlice())
    file.add(0xFF_u8)
    file.add(0xFB_u8)

    let fileName = Path.combine(Env.getSpecialDirectory(.Temp).toString(), Format.toString("swag_audio_tags_%.mp3", Guid64.random()).toString())
    defer discard catch File.delete(fileName)
    discard expect File.writeAllBytes(fileName, file.toSlice())

    let tags = SoundTags.read(fileName)
    Swag.require(tags.title == "Aria" and tags.artist == "Bach")
}

// ID3v2.4 frame sizes are syncsafe, unlike the big-endian sizes in v2.3.
#test
{
    var body: Array!{u8}
    body.add(3_u8)
    for byte in "2024-"
    {
        body.add(byte)
    }

    for 124
    {
        body.add('x')
    }

    Swag.require(body.count == 130)

    var frames: Array!{u8}
    appendId3v24Frame(&frames, "TDRC", body.toSlice())

    var file: Array!{u8}
    for byte in "ID3"
    {
        file.add(byte)
    }

    file.add(4_u8)
    file.add(0_u8)
    file.add(0_u8)
    let size = frames.count
    file.add(cast(u8, (size >> 21) & 0x7F))
    file.add(cast(u8, (size >> 14) & 0x7F))
    file.add(cast(u8, (size >> 7) & 0x7F))
    file.add(cast(u8, size & 0x7F))
    file.add(frames.toSlice())

    let fileName = Path.combine(Env.getSpecialDirectory(.Temp).toString(), Format.toString("swag_audio_tags_%.mp3", Guid64.random()).toString())
    defer discard catch File.delete(fileName)
    discard expect File.writeAllBytes(fileName, file.toSlice())

    let tags = SoundTags.read(fileName)
    Swag.require(tags.year == "2024", tags.year)
}

// ID3v2.4 syncsafe size bytes with their high bit set do not decode as a tag.
#test
{
    var body: Array!{u8}
    body.add(3_u8)
    for byte in "2024"
    {
        body.add(byte)
    }

    var frames: Array!{u8}
    appendId3v24Frame(&frames, "TDRC", body.toSlice())

    var file: Array!{u8}
    for byte in "ID3"
    {
        file.add(byte)
    }

    file.add(4_u8)
    file.add(0_u8)
    file.add(0_u8)
    let size = frames.count
    file.add(cast(u8, (size >> 21) & 0x7F))
    file.add(cast(u8, (size >> 14) & 0x7F))
    file.add(cast(u8, (size >> 7) & 0x7F))
    file.add(cast(u8, size & 0x7F))
    file.add(frames.toSlice())

    var invalidHeader = file
    invalidHeader[6] |= 0x80
    let headerPath = Path.combine(Env.getSpecialDirectory(.Temp).toString(),
                                  Format.toString("swag_audio_tags_bad_header_%.mp3", Guid64.random()).toString())
    defer discard catch File.delete(headerPath)
    discard expect File.writeAllBytes(headerPath, invalidHeader.toSlice())
    Swag.require(SoundTags.read(headerPath).isEmpty())

    var invalidFrame = file
    invalidFrame[14] |= 0x80     // Frame size, after the ten-byte ID3 header and four-byte frame id.
    let framePath = Path.combine(Env.getSpecialDirectory(.Temp).toString(),
                                 Format.toString("swag_audio_tags_bad_frame_%.mp3", Guid64.random()).toString())
    defer discard catch File.delete(framePath)
    discard expect File.writeAllBytes(framePath, invalidFrame.toSlice())
    Swag.require(SoundTags.read(framePath).isEmpty())

    var invalidExtended: Array!{u8}
    for byte in "ID3"
    {
        invalidExtended.add(byte)
    }

    invalidExtended.add(4_u8)
    invalidExtended.add(0_u8)
    invalidExtended.add(0x40_u8)     // Extended header.
    let extendedTagSize = frames.count + 6
    invalidExtended.add(cast(u8, (extendedTagSize >> 21) & 0x7F))
    invalidExtended.add(cast(u8, (extendedTagSize >> 14) & 0x7F))
    invalidExtended.add(cast(u8, (extendedTagSize >> 7) & 0x7F))
    invalidExtended.add(cast(u8, extendedTagSize & 0x7F))
    for byte in [0x80_u8, 0, 0, 6, 1, 0]
    {
        // Extended size has a forbidden high bit.
        invalidExtended.add(byte)
    }

    invalidExtended.add(frames.toSlice())
    let extendedPath = Path.combine(Env.getSpecialDirectory(.Temp).toString(),
                                    Format.toString("swag_audio_tags_bad_extended_%.mp3", Guid64.random()).toString())
    defer discard catch File.delete(extendedPath)
    discard expect File.writeAllBytes(extendedPath, invalidExtended.toSlice())
    Swag.require(SoundTags.read(extendedPath).isEmpty())
}

// A FLAC file names its recording in a Vorbis comment block, whatever the case of its field names.
#test
{
    var comment: Array!{u8}
    appendLittle32(&comment, 4)
    for byte in "swag"
    {
        comment.add(byte)
    }

    let fields = ["title=Clair de lune", "ARTIST=Debussy", "Album=Suite bergamasque", "DATE=1905-01-01", "albumartist=Various Artists", "TRACKNUMBER=3", "genre=Impressionism"]
    appendLittle32(&comment, fields.count)
    for field in fields
    {
        appendLittle32(&comment, field.count)
        for byte in field
        {
            comment.add(byte)
        }
    }

    var file: Array!{u8}
    for byte in "fLaC"
    {
        file.add(byte)
    }

    // A STREAMINFO block of 34 bytes, then the comment as the last block.
    file.add(0_u8)
    file.add(0_u8)
    file.add(0_u8)
    file.add(34_u8)
    for 34
    {
        file.add(0_u8)
    }

    file.add(0x84_u8)
    file.add(cast(u8, (comment.count >> 16) & 0xFF))
    file.add(cast(u8, (comment.count >> 8) & 0xFF))
    file.add(cast(u8, comment.count & 0xFF))
    for byte in comment
    {
        file.add(byte)
    }

    let fileName = Path.combine(Env.getSpecialDirectory(.Temp).toString(), Format.toString("swag_audio_tags_%.flac", Guid64.random()).toString())
    defer discard catch File.delete(fileName)
    discard expect File.writeAllBytes(fileName, file.toSlice())

    let tags = SoundTags.read(fileName)
    Swag.require(tags.title == "Clair de lune" and tags.artist == "Debussy")
    Swag.require(tags.album == "Suite bergamasque" and tags.year == "1905")
    Swag.require(tags.albumArtist == "Various Artists")
    Swag.require(tags.track == "3" and tags.genre == "Impressionism" and tags.disc.isEmpty())
}

// A file without tags, or one this reader does not know, simply names nothing.
#test
{
    Swag.require(SoundTags.read("this-file-does-not-exist.mp3").isEmpty())
    let albumOnly = SoundTags{albumArtist: "Various Artists"}
    Swag.require(not albumOnly.isEmpty())
}

// Writes `tag` as the whole ID3v2.3 tag of an MP3 file, frames only, and returns its name.
func writeId3File(frames: const [..] u8)->String
{
    var file: Array!{u8}
    for byte in "ID3"
    {
        file.add(byte)
    }

    file.add(3_u8)
    file.add(0_u8)
    file.add(0_u8)
    let size = frames.count
    file.add(cast(u8, (size >> 21) & 0x7F))
    file.add(cast(u8, (size >> 14) & 0x7F))
    file.add(cast(u8, (size >> 7) & 0x7F))
    file.add(cast(u8, size & 0x7F))
    for byte in frames
    {
        file.add(byte)
    }

    file.add(0xFF_u8)
    file.add(0xFB_u8)
    let fileName = Path.combine(Env.getSpecialDirectory(.Temp).toString(), Format.toString("swag_audio_picture_%.mp3", Guid64.random()).toString())
    discard expect File.writeAllBytes(fileName, file.toSlice())
    return fileName
}

// A parenthesized genre prefix is removed only when it contains a numeric ID3v1 reference.
#test
{
    var frames: Array!{u8}
    var genre:  Array!{u8}
    genre.add(3_u8)
    for byte in "(Live)Rock"
    {
        genre.add(byte)
    }

    appendId3Frame(&frames, "TCON", genre.toSlice())

    let fileName = writeId3File(frames.toSlice())
    defer discard catch File.delete(fileName)
    Swag.require(SoundTags.read(fileName).genre == "(Live)Rock")
}

// A malformed field after a valid title discards the whole tag instead of returning partial tags.
#test
{
    var frames: Array!{u8}
    var title:  Array!{u8}
    title.add(3_u8)
    for byte in "Before malformed text"
    {
        title.add(byte)
    }

    appendId3Frame(&frames, "TIT2", title.toSlice())

    var artist: Array!{u8}
    artist.add(4_u8)
    artist.add('X')
    appendId3Frame(&frames, "TPE1", artist.toSlice())

    let fileName = writeId3File(frames.toSlice())
    defer discard catch File.delete(fileName)
    Swag.require(SoundTags.read(fileName).isEmpty())
}

// An MP3 file embeds its sleeve in a picture frame; the front cover wins over another picture,
// past a UTF-16 description, and a reader that does not ask for it gets no picture.
#test
{
    var frames: Array!{u8}
    var back:   Array!{u8}
    back.add(0_u8)
    for byte in "image/png"
    {
        back.add(byte)
    }

    back.add(0_u8)
    back.add(4_u8)
    back.add(0_u8)
    for byte in [0x89_u8, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2]
    {
        back.add(byte)
    }

    appendId3Frame(&frames, "APIC", back.toSlice())

    var front: Array!{u8}
    front.add(1_u8)
    for byte in "image/jpeg"
    {
        front.add(byte)
    }

    front.add(0_u8)
    front.add(3_u8)
    for byte in [0xFF_u8, 0xFE, 0x46, 0, 0, 0, 0xFF, 0xD8, 0xFF, 0xE0, 7, 7]
    {
        front.add(byte)
    }

    appendId3Frame(&frames, "APIC", front.toSlice())

    let fileName = writeId3File(frames.toSlice())
    defer discard catch File.delete(fileName)
    Swag.require(SoundTags.read(fileName).picture.isEmpty())
    let tags = SoundTags.read(fileName, withPicture: true)
    Swag.require(tags.isEmpty())
    Swag.require(tags.pictureExtension == ".jpg" and tags.picture.count == 6 and tags.picture[5] == 7)
}

// A FLAC file embeds its sleeve in a picture block after the comment.
#test
{
    var picture: Array!{u8}

    func appendBig32(block: *Array!{u8}, value: u64)
    {
        for shift in 4
        {
            block.add(cast(u8, (value >> ((3 - shift) * 8)) & 0xFF))
        }
    }

    appendBig32(&picture, 3)
    appendBig32(&picture, 9)
    for byte in "image/png"
    {
        picture.add(byte)
    }

    appendBig32(&picture, 0)
    for 16
    {
        picture.add(0_u8)
    }

    let png = [0x89_u8, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 42]
    appendBig32(&picture, png.count)
    for byte in png
    {
        picture.add(byte)
    }

    var comment: Array!{u8}
    appendLittle32(&comment, 0)
    appendLittle32(&comment, 0)

    var file: Array!{u8}
    for byte in "fLaC"
    {
        file.add(byte)
    }

    for byte in [4_u8, 0, 0, cast(u8, comment.count)]
    {
        file.add(byte)
    }

    for byte in comment
    {
        file.add(byte)
    }

    for byte in [0x86_u8, 0, 0, cast(u8, picture.count)]
    {
        file.add(byte)
    }

    for byte in picture
    {
        file.add(byte)
    }

    let fileName = Path.combine(Env.getSpecialDirectory(.Temp).toString(), Format.toString("swag_audio_picture_%.flac", Guid64.random()).toString())
    defer discard catch File.delete(fileName)
    discard expect File.writeAllBytes(fileName, file.toSlice())
    let tags = SoundTags.read(fileName, withPicture: true)
    Swag.require(tags.pictureExtension == ".png" and tags.picture.count == png.count and tags.picture[8] == 42)
}
