#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Appends one ID3v2.3 frame: its identifier, big-endian size, two flag bytes, and body.
func appendId3Frame(tag: *Array'u8, id: string, body: const [..] u8)
{
    for byte in id do
        tag.add(byte)
    tag.add(cast(u8, (body.count >> 24) & 0xFF))
    tag.add(cast(u8, (body.count >> 16) & 0xFF))
    tag.add(cast(u8, (body.count >> 8) & 0xFF))
    tag.add(cast(u8, body.count & 0xFF))
    tag.add(0'u8)
    tag.add(0'u8)
    for byte in body do
        tag.add(byte)
}

// Appends a little-endian 32-bit length, as a Vorbis comment block spells every count.
func appendLittle32(block: *Array'u8, value: u64)
{
    for shift in 4 do
        block.add(cast(u8, (value >> (shift * 8)) & 0xFF))
}

// An MP3 file names its recording in an ID3v2 tag, in Latin-1 or UTF-16 text frames.
#test
{
    var frames: Array'u8
    var title:  Array'u8
    title.add(3'u8)
    for byte in "Gymnopédie No. 1" do
        title.add(byte)
    appendId3Frame(&frames, "TIT2", title.toSlice())

    // "Trois Gymnopédies" in ISO-8859-1, where é is the single byte 0xE9.
    var album: Array'u8
    album.add(0'u8)
    for byte in "Trois Gymnop" do
        album.add(byte)
    album.add(0xE9'u8)
    for byte in "dies" do
        album.add(byte)
    appendId3Frame(&frames, "TALB", album.toSlice())

    // "Satie" in UTF-16 with a little-endian byte-order mark.
    var artist: Array'u8
    artist.add(1'u8)
    artist.add(0xFF'u8)
    artist.add(0xFE'u8)
    for byte in "Satie"
    {
        artist.add(byte)
        artist.add(0'u8)
    }

    appendId3Frame(&frames, "TPE1", artist.toSlice())
    var albumArtist: Array'u8
    albumArtist.add(3'u8)
    for byte in "Various Artists" do
        albumArtist.add(byte)
    appendId3Frame(&frames, "TPE2", albumArtist.toSlice())
    var year: Array'u8
    year.add(0'u8)
    for byte in "1888" do
        year.add(byte)
    appendId3Frame(&frames, "TYER", year.toSlice())

    var file: Array'u8
    for byte in "ID3" do
        file.add(byte)
    file.add(3'u8)
    file.add(0'u8)
    file.add(0'u8)
    let size = frames.count
    file.add(cast(u8, (size >> 21) & 0x7F))
    file.add(cast(u8, (size >> 14) & 0x7F))
    file.add(cast(u8, (size >> 7) & 0x7F))
    file.add(cast(u8, size & 0x7F))
    for byte in frames do
        file.add(byte)
    file.add(0xFF'u8)
    file.add(0xFB'u8)

    let fileName = Path.combine(Env.getSpecialDirectory(.Temp).toString(), Format.toString("swag_audio_tags_%.mp3", Guid64.random()).toString())
    defer discard catch File.delete(fileName)
    discard expect File.writeAllBytes(fileName, file.toSlice())

    let tags = SoundTags.read(fileName)
    Swag.assert(tags.title == "Gymnopédie No. 1" and tags.artist == "Satie" and tags.year == "1888")
    Swag.assert(tags.album == "Trois Gymnopédies")
    Swag.assert(tags.albumArtist == "Various Artists")
}

// A FLAC file names its recording in a Vorbis comment block, whatever the case of its field names.
#test
{
    var comment: Array'u8
    appendLittle32(&comment, 4)
    for byte in "swag" do
        comment.add(byte)
    let fields = ["title=Clair de lune", "ARTIST=Debussy", "Album=Suite bergamasque", "DATE=1905-01-01", "albumartist=Various Artists"]
    appendLittle32(&comment, fields.count)
    for field in fields
    {
        appendLittle32(&comment, field.count)
        for byte in field do
            comment.add(byte)
    }

    var file: Array'u8
    for byte in "fLaC" do
        file.add(byte)

    // A STREAMINFO block of 34 bytes, then the comment as the last block.
    file.add(0'u8)
    file.add(0'u8)
    file.add(0'u8)
    file.add(34'u8)
    for 34 do
        file.add(0'u8)
    file.add(0x84'u8)
    file.add(cast(u8, (comment.count >> 16) & 0xFF))
    file.add(cast(u8, (comment.count >> 8) & 0xFF))
    file.add(cast(u8, comment.count & 0xFF))
    for byte in comment do
        file.add(byte)

    let fileName = Path.combine(Env.getSpecialDirectory(.Temp).toString(), Format.toString("swag_audio_tags_%.flac", Guid64.random()).toString())
    defer discard catch File.delete(fileName)
    discard expect File.writeAllBytes(fileName, file.toSlice())

    let tags = SoundTags.read(fileName)
    Swag.assert(tags.title == "Clair de lune" and tags.artist == "Debussy")
    Swag.assert(tags.album == "Suite bergamasque" and tags.year == "1905")
    Swag.assert(tags.albumArtist == "Various Artists")
}

// A file without tags, or one this reader does not know, simply names nothing.
#test
{
    Swag.assert(SoundTags.read("this-file-does-not-exist.mp3").isEmpty())
    let albumOnly = SoundTags{albumArtist: "Various Artists"}
    Swag.assert(not albumOnly.isEmpty())
}
