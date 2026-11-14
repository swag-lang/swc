#global internal

using Core, Pixel, Gui

// Shared vocabulary for image and video properties. Format-owned tag names remain literal.
enum MediaInfoField
{
    Custom
    Media
    Image
    Video
    Metadata
    Technical
    Document
    Text
    Sound
    Font
    Table
    Music
    Binary
    Format
    Codec
    Dimensions
    DisplaySize
    AspectRatio
    PixelFormat
    Depth
    Frames
    Pages
    Lines
    Sections
    Members
    Typeface
    Duration
    FrameRate
    ExactFrameRate
    Bitrate
    Audio
    Subtitles
    Name
    Language
    Encoding
    SampleRate
    Channels
    SampleSize
    Title
    Author
    Bookmarks
    Style
    UnitsPerEm
    Faces
    Separator
    Meter
    LineEnds
    Track
    Empty
    Unavailable
}

// Visible strings of the media readings added to the application information sheet.
struct MediaInfoStrings
{
    media:       string = "Media"
    image:       string = "Image"
    video:       string = "Video"
    metadata:    string = "Metadata"
    technical:   string = "Technical"
    document:    string = "Document"
    text:        string = "Text"
    sound:       string = "Sound"
    font:        string = "Font"
    table:       string = "Table"
    music:       string = "Music"
    binary:      string = "Binary"
    format:      string = "Format"
    codec:       string = "Video codec"
    dimensions:  string = "Dimensions"
    displaySize: string = "Display size"
    aspectRatio: string = "Aspect ratio"
    pixelFormat: string = "Pixel format"
    depth:       string = "Bits per pixel"
    frames:      string = "Frames"
    pages:       string = "Pages"
    lines:       string = "Lines"
    sections:    string = "Sections"
    members:     string = "Files"
    typeface:    string = "Typeface"
    duration:    string = "Duration"
    frameRate:   string = "Frame rate"
    exactFrameRate: string = "Exact frame rate"
    bitrate:     string = "Approx. bitrate"
    audio:       string = "Audio tracks"
    subtitles:   string = "Subtitle tracks"
    name:        string = "Name"
    language:    string = "Language"
    encoding:    string = "Encoding"
    sampleRate:  string = "Sample rate"
    channels:    string = "Channels"
    sampleSize:  string = "Sample size"
    title:       string = "Title"
    author:      string = "Author"
    bookmarks:   string = "Bookmarks"
    style:       string = "Style"
    unitsPerEm:  string = "Units per em"
    faces:       string = "Faces"
    separator:   string = "Separator"
    meter:       string = "Time signature"
    lineEnds:    string = "Line ends"
    oneLine:     string = "1 line"
    lineCount:   string = "% lines"
    oneWord:     string = "1 word"
    wordCount:   string = "% words"
    oneCharacter: string = "1 character"
    characterCount: string = "% characters"
    glyphCount:  string = "% glyphs"
    mono:        string = "mono"
    stereo:      string = "stereo"
    channelCount: string = "% channels"
    track:       string = "Track %"
    empty:       string = "None"
    unavailable: string = "Read error"
}

private const FrenchMediaStringsName = "lang/fr/scope.media.tweak"
private const FrenchMediaStrings     = #include("../datas/lang/fr/scope.media.tweak")

private var g_MediaInfoStrings: MediaInfoStrings

const VideoInfoFormatTag      = "ScopeVideoFormat"
const VideoInfoCodecTag       = "ScopeVideoCodec"
const VideoInfoDimensionsTag  = "ScopeVideoDimensions"
const VideoInfoDisplaySizeTag = "ScopeVideoDisplaySize"
const VideoInfoAspectRatioTag = "ScopeVideoAspectRatio"
const VideoInfoFrameRateTag   = "ScopeVideoFrameRate"
const VideoInfoExactRateTag   = "ScopeVideoExactRate"
const VideoInfoFramesTag      = "ScopeVideoFrames"
const VideoInfoBitrateTag     = "ScopeVideoBitrate"

// Registers the media information string table and its embedded translation.
//
// The application registers it with its own strings: every sheet speaks this vocabulary, the
// explorer's pages included, before any viewer has been opened.
func registerMediaInfoStrings(bundle: *Core.Resources.Bundle)
{
    bundle.addEmbedded(FrenchMediaStringsName, FrenchMediaStrings)
    Gui.registerStrings'MediaInfoStrings(&g_MediaInfoStrings, "scope.media")
}

#run
{
    expect Gui.validateStrings'MediaInfoStrings(cast(string, FrenchMediaStrings))
}

// One property of the panel, or the heading of a group of them.
struct MediaInfoRow
{
    field:  MediaInfoField
    name:   String     // Name of a format-owned tag, or of a track.
    value:  String     // The reading, the measures of a track, or the count a section label carries.
    number: String     // Number of a track.
    group:  bool       // Whether the row opens a section.
    figure: bool       // Whether the reading is one of the figures heading the sheet.
}

impl MediaInfoRow
{
    // Returns the name of the row in the active language, or its own name for a format-owned tag.
    mtd const label()->string
    {
        let s = &g_MediaInfoStrings
        switch #complete .field
        {
        case .Custom:      return .name.toString()
        case .Media:       return s.media
        case .Image:       return s.image
        case .Video:       return s.video
        case .Metadata:    return s.metadata
        case .Technical:   return s.technical
        case .Document:    return s.document
        case .Text:        return s.text
        case .Sound:       return s.sound
        case .Font:        return s.font
        case .Table:       return s.table
        case .Music:       return s.music
        case .Binary:      return s.binary
        case .Format:      return s.format
        case .Codec:       return s.codec
        case .Dimensions:  return s.dimensions
        case .DisplaySize: return s.displaySize
        case .AspectRatio: return s.aspectRatio
        case .PixelFormat: return s.pixelFormat
        case .Depth:       return s.depth
        case .Frames:      return s.frames
        case .Pages:       return s.pages
        case .Lines:       return s.lines
        case .Sections:    return s.sections
        case .Members:     return s.members
        case .Typeface:    return s.typeface
        case .Duration:    return s.duration
        case .FrameRate:   return s.frameRate
        case .ExactFrameRate: return s.exactFrameRate
        case .Bitrate:     return s.bitrate
        case .Audio:       return s.audio
        case .Subtitles:   return s.subtitles
        case .Name:        return s.name
        case .Language:    return s.language
        case .Encoding:    return s.encoding
        case .SampleRate:  return s.sampleRate
        case .Channels:    return s.channels
        case .SampleSize:  return s.sampleSize
        case .Title:       return s.title
        case .Author:      return s.author
        case .Bookmarks:   return s.bookmarks
        case .Style:       return s.style
        case .UnitsPerEm:  return s.unitsPerEm
        case .Faces:       return s.faces
        case .Separator:   return s.separator
        case .Meter:       return s.meter
        case .LineEnds:    return s.lineEnds
        case .Track:       return .name.toString()
        case .Empty:       return s.empty
        case .Unavailable: return s.unavailable
        }
    }

    // Reports whether the reading is a measure, set in the fixed-width face, rather than a name.
    mtd const isMeasure()->bool
    {
        switch .field
        {
        case .Dimensions, .DisplaySize, .AspectRatio, .Depth, .Frames, .Pages, .Lines, .Sections,
             .Members, .Duration, .FrameRate, .ExactFrameRate, .Bitrate, .SampleRate, .Channels,
             .SampleSize, .Bookmarks, .UnitsPerEm, .Faces, .Meter, .LineEnds:
            return true
        }

        return false
    }
}

// Names a channel layout as a reader says it: mono, stereo, or a count.
func channelsText(channels: u32)->String
{
    let s = &g_MediaInfoStrings
    switch channels
    {
    case 1: return String.from(s.mono)
    case 2: return String.from(s.stereo)
    }

    return Format.toString(s.channelCount, channels)
}

// Returns a track language worth writing: empty for the undetermined code `und`.
func knownLanguage(language: string)->String
{
    if language.count == 0 or Latin1.compare(language, "und", ignoreCase: true) == 0 do
        return {}
    return String.from(language)
}

// Joins the measures of a track with the middle dot of the sheet's mono lines.
func joinMeasures(measures: const [..] String)->String
{
    var result: #returntype
    for index in measures.count where not measures[index].isEmpty()
    {
        if result.count do
            result += " · "
        result += measures[index]
    }

    return result
}

// Counts the glyphs of a font as a figure says it.
func glyphCountText(count: u64)->String => Format.toString(g_MediaInfoStrings.glyphCount, count)

// Returns the default name of the track numbered `number`.
func trackText(number: u64)->String => Format.toString(g_MediaInfoStrings.track, number)

// Owns values independently of the decoded pixels, file mapping, and language table.
struct MediaInfoData
{
    rows: Array'MediaInfoRow
}

impl MediaInfoData
{
    // Recovers stream readings recorded beside a film thumbnail, independently of its artwork.
    func fromVideoThumbnail(image: const *Image)->MediaInfoData
    {
        var result: #returntype
        for &record in image.metadata
        {
            let value = cast(string, record.toSlice())
            if record.isTag(cast(const [..] u8, VideoInfoFormatTag)) do
                result.add(.Format, value)
            elif record.isTag(cast(const [..] u8, VideoInfoCodecTag)) do
                result.add(.Codec, value)
            elif record.isTag(cast(const [..] u8, VideoInfoDimensionsTag)) do
                result.add(.Dimensions, value)
            elif record.isTag(cast(const [..] u8, VideoInfoDisplaySizeTag)) do
                result.add(.DisplaySize, value)
            elif record.isTag(cast(const [..] u8, VideoInfoAspectRatioTag)) do
                result.add(.AspectRatio, value)
            elif record.isTag(cast(const [..] u8, VideoInfoFrameRateTag)) do
                result.add(.FrameRate, value)
            elif record.isTag(cast(const [..] u8, VideoInfoExactRateTag)) do
                result.add(.ExactFrameRate, value)
            elif record.isTag(cast(const [..] u8, VideoInfoFramesTag)) do
                result.add(.Frames, value)
            elif record.isTag(cast(const [..] u8, VideoInfoBitrateTag)) do
                result.add(.Bitrate, value)
        }

        return result
    }

    // Appends a row named by the shared vocabulary.
    mtd add(field: MediaInfoField, value: string = "", group = false)
    {
        var row = MediaInfoRow{field: field, group: group}
        row.value = value
        .rows.add(#move row)
    }

    // Appends one of the figures heading the sheet: what the file is about, set large.
    mtd addFigure(field: MediaInfoField, value: string)
    {
        var row = MediaInfoRow{field: field, figure: true}
        row.value = value
        .rows.add(#move row)
    }

    // Appends a track of the current section: its number, its name and its measures.
    mtd addTrack(number: u64, name, measures: string)
    {
        var row = MediaInfoRow{field: .Track}
        row.number = Format.toString("%", number)
        row.name   = name
        row.value  = measures
        .rows.add(#move row)
    }

    // Appends the figures of a counted text, its lines first, then its words and characters when
    // `withWords`, and how its lines end as a reading of the current section.
    mtd addTextStatistics(statistics: const *TextStatistics, withWords = true)
    {
        let s = &g_MediaInfoStrings
        .addFigure(.Lines, statistics.lines == 1 ? String.from(s.oneLine) : Format.toString(s.lineCount, statistics.lines))
        if withWords
        {
            .addFigure(.Custom, statistics.words == 1 ? String.from(s.oneWord) : Format.toString(s.wordCount, statistics.words))
            .addFigure(.Custom, statistics.characters == 1 ? String.from(s.oneCharacter) : Format.toString(s.characterCount, statistics.characters))
        }

        let ends = statistics.lineEnds()
        if ends.count do
            .add(.LineEnds, ends)
    }

    // Appends a row whose name the format owns, shown as written.
    mtd addText(name, value: string)
    {
        var row: MediaInfoRow
        row.name  = name
        row.value = value
        .rows.add(#move row)
    }

    // Appends decoded Exif properties, PNG text, or a size description for opaque records.
    mtd addImageMetadata(records: const [..] ImageMetadata, pngText = false)
    {
        .add(.Metadata, group: true)
        if not records.count
        {
            .add(.Empty)
            return
        }

        for record in records
        {
            if record.signature == 1 and record.isTag("Exif")
            {
                // JPEG splits APP1 at its first NUL, leaving the second prefix NUL in value.
                let bytes      = record.toSlice()
                let payload    = bytes.count and bytes[0] == 0 ? bytes[1 to] : bytes
                let properties = catch Exif.decode(payload)
                {
                    .add(.Unavailable, Viewer.failureText(Swag.err))
                    continue
                }

                for property in properties do
                    .addText(property.name(), property.value)
                continue
            }

            var tag: String
            for byte in record.tag do
                tag += cast(rune, byte >= 32 ? byte : '?')
            if tag.isEmpty() do
                tag = Format.toString("APP%", record.signature)
            let bytes = record.toSlice()
            var text: String

            // PNG tEXt is Latin-1. Other opaque records keep a bounded size description.
            if pngText
            {
                for index in Math.min(bytes.count, 4096)
                {
                    let byte   = bytes[index]
                    let isText = byte >= 32 or byte == 10 or byte == 9
                    text += cast(rune, isText ? byte : ' ')
                }

                if bytes.count > 4096 do
                    text += "…"
            }
            else
            {
                text = StrConv.toDisplaySize(bytes.count)
            }

            .addText(tag, text)
        }
    }

    // Adds these viewer-owned readings to the application information sheet.
    //
    // Dimensions and the rows added as figures head the sheet. A section is written only once a
    // reading follows it, so a group whose only answer is that there is nothing to read leaves
    // no trace; what could not be read is a note.
    mtd describe(sheet: *InfoSheet)
    {
        var section: String
        for row in .rows
        {
            if row.group
            {
                section = row.value.isEmpty() ? String.from(row.label()) : Format.toString("% · %", row.label(), row.value)
                continue
            }

            if row.field == .Empty do
                continue
            if row.figure or row.field == .Dimensions
            {
                addFigure(sheet, row.value)
                continue
            }

            if not section.isEmpty()
            {
                sheet.addSection(section)
                section.clear()
            }

            switch
            {
            case row.field == .Unavailable:
                sheet.addNote(row.value.isEmpty() ? row.label() : row.value.toString())
            case row.field == .Track:
                sheet.addTrack(row.number, row.name, row.value)
            case row.value.isEmpty():
                sheet.addText(row.label())
            default:
                sheet.addReading(row.label(), row.value, mono: row.isMeasure())
            }
        }
    }
}

// Adds `value` to the figures of `sheet`, its trailing unit apart: "1920 × 1080 px" stands as
// "1920 × 1080" with the faint unit "px".
func addFigure(sheet: *InfoSheet, value: string)
{
    let space = Utf8.lastIndexOf(value, " ")
    if space != Swag.U64.Max and space + 1 < value.count and Latin1.isLetter(value[space + 1]) do
        sheet.addFact(value[0 until space], value[space + 1 to])
    else do
        sheet.addFact(value)
}

// Returns the displayed picture shape as a reduced width-to-height ratio.
func videoAspectRatio(width, height: s32)->String
{
    if width <= 0 or height <= 0 do
        return ""
    let divisor = expect Math.gcd(width, height)
    return Format.toString("%:%", width / divisor, height / divisor)
}

// Approximates the overall file rate, including sound, subtitles, and container overhead.
func videoBitrate(size: u64, duration: f64)->String
{
    if not size or duration <= 0 do
        return ""
    return Format.toString("%{f0} kb/s", cast(f64, size) * 8 / duration / 1_000)
}
