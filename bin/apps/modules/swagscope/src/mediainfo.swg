#global internal

using Core, Pixel, Gui

// Shared vocabulary for image and video properties. Format-owned tag names remain literal.
enum MediaInfoField
{
    Custom
    Image
    Video
    Metadata
    Format
    Dimensions
    DisplaySize
    PixelFormat
    Depth
    Frames
    Duration
    FrameRate
    Audio
    Subtitles
    Name
    Language
    Encoding
    SampleRate
    Channels
    Empty
    Unavailable
}

// Visible strings of the media readings added to the application information sheet.
struct MediaInfoStrings
{
    image:       string = "Image"
    video:       string = "Video"
    metadata:    string = "Metadata"
    format:      string = "Format"
    dimensions:  string = "Dimensions"
    displaySize: string = "Display size"
    pixelFormat: string = "Pixel format"
    depth:       string = "Bits per pixel"
    frames:      string = "Frames"
    duration:    string = "Duration"
    frameRate:   string = "Frame rate"
    audio:       string = "Audio tracks"
    subtitles:   string = "Subtitle tracks"
    name:        string = "Name"
    language:    string = "Language"
    encoding:    string = "Encoding"
    sampleRate:  string = "Sample rate"
    channels:    string = "Channels"
    empty:       string = "None"
    unavailable: string = "Read error"
}

private const FrenchMediaStringsName = "lang/fr/scope.media.tweak"
private const FrenchMediaStrings     = #include("../datas/lang/fr/scope.media.tweak")

private var g_MediaInfoStrings: MediaInfoStrings

// Registers the media information string table and its embedded translation.
func registerMediaInfoStrings(app: *Application)
{
    app.resources.addEmbedded(FrenchMediaStringsName, FrenchMediaStrings)
    Gui.registerStrings'MediaInfoStrings(&g_MediaInfoStrings, "scope.media")
}

#run
{
    expect Gui.validateStrings'MediaInfoStrings(cast(string, FrenchMediaStrings))
}

// One property of the panel, or the heading of a group of them.
struct MediaInfoRow
{
    field: MediaInfoField
    name:  String
    value: String
    group: bool
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
        case .Image:       return s.image
        case .Video:       return s.video
        case .Metadata:    return s.metadata
        case .Format:      return s.format
        case .Dimensions:  return s.dimensions
        case .DisplaySize: return s.displaySize
        case .PixelFormat: return s.pixelFormat
        case .Depth:       return s.depth
        case .Frames:      return s.frames
        case .Duration:    return s.duration
        case .FrameRate:   return s.frameRate
        case .Audio:       return s.audio
        case .Subtitles:   return s.subtitles
        case .Name:        return s.name
        case .Language:    return s.language
        case .Encoding:    return s.encoding
        case .SampleRate:  return s.sampleRate
        case .Channels:    return s.channels
        case .Empty:       return s.empty
        case .Unavailable: return s.unavailable
        }
    }
}

// Owns values independently of the decoded pixels, file mapping, and language table.
struct MediaInfoData
{
    rows: Array'MediaInfoRow
}

impl MediaInfoData
{
    // Appends a row named by the shared vocabulary.
    mtd add(field: MediaInfoField, value: string = "", group = false)
    {
        var row = MediaInfoRow{field: field, group: group}
        row.value = value
        .rows.add(#move row)
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
    mtd describe(sheet: *InfoSheet)
    {
        for row in .rows
        {
            if row.group do
                sheet.addSection(row.label())
            elif row.value.isEmpty() do
                sheet.addText(row.label())
            else do
                sheet.addReading(row.label(), row.value)
        }
    }
}
