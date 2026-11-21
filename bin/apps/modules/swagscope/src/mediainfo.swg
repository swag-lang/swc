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
    Levels
    SamplePeak
    RmsLevel
    FullScale
    Title
    Author
    Publisher
    Published
    Created
    Application
    Description
    Tags
    Artist
    Album
    AlbumArtist
    Year
    TrackNumber
    Disc
    Genre
    Weight
    Embedding
    Columns
    Tracks
    LongestLine
    ControlCharacters
    Replacements
    Transparency
    Character
    GlyphIndex
    Timing
    Overlaps
    ShortestCue
    Bookmarks
    TextLayer
    Style
    UnitsPerEm
    Faces
    Version
    Designer
    Copyright
    Separator
    Meter
    Tempo
    KeySignature
    LineEnds
    Coverage
    Track
    Empty
    Unavailable
}

// Visible strings of the media readings added to the application information sheet.
struct MediaInfoStrings
{
    media:             string = "Media"
    image:             string = "Image"
    video:             string = "Video"
    metadata:          string = "Metadata"
    technical:         string = "Technical"
    document:          string = "Document"
    text:              string = "Text"
    sound:             string = "Sound"
    font:              string = "Font"
    table:             string = "Table"
    music:             string = "Music"
    binary:            string = "Binary"
    format:            string = "Format"
    codec:             string = "Video codec"
    dimensions:        string = "Dimensions"
    displaySize:       string = "Display size"
    aspectRatio:       string = "Aspect ratio"
    pixelFormat:       string = "Pixel format"
    depth:             string = "Bits per pixel"
    frames:            string = "Frames"
    pages:             string = "Pages"
    lines:             string = "Lines"
    sections:          string = "Sections"
    members:           string = "Files"
    typeface:          string = "Typeface"
    duration:          string = "Duration"
    frameRate:         string = "Frame rate"
    exactFrameRate:    string = "Exact frame rate"
    bitrate:           string = "Approx. bitrate"
    audio:             string = "Audio tracks"
    subtitles:         string = "Subtitle tracks"
    name:              string = "Name"
    language:          string = "Language"
    encoding:          string = "Encoding"
    sampleRate:        string = "Sample rate"
    channels:          string = "Channels"
    sampleSize:        string = "Sample size"
    levels:            string = "Levels"
    samplePeak:        string = "Sample peak"
    rmsLevel:          string = "RMS level"
    fullScale:         string = "Full scale"
    title:             string = "Title"
    author:            string = "Author"
    publisher:         string = "Publisher"
    published:         string = "Published"
    created:           string = "Created"
    application:       string = "Application"
    description:       string = "Description"
    tags:              string = "Tags"
    artist:            string = "Artist"
    album:             string = "Album"
    albumArtist:       string = "Album artist"
    year:              string = "Year"
    trackNumber:       string = "Track"
    disc:              string = "Disc"
    genre:             string = "Genre"
    weight:            string = "Weight"
    embedding:         string = "Embedding"
    columns:           string = "Columns"
    tracks:            string = "Tracks"
    longestLine:       string = "Longest line"
    controls:          string = "Control characters"
    replacements:      string = "Unreadable characters (U+FFFD)"
    transparency:      string = "Transparency"
    character:         string = "Character"
    glyphIndex:        string = "Glyph index"
    timing:            string = "Timing"
    overlaps:          string = "Overlapping cues"
    shortestCue:       string = "Shortest cue"
    bookmarks:         string = "Bookmarks"
    textLayer:         string = "Text layer"
    style:             string = "Style"
    unitsPerEm:        string = "Units per em"
    faces:             string = "Faces"
    version:           string = "Version"
    designer:          string = "Designer"
    copyright:         string = "Copyright"
    separator:         string = "Separator"
    meter:             string = "Time signature"
    tempo:             string = "Tempo"
    keySignature:      string = "Key"
    lineEnds:          string = "Line ends"
    coverage:          string = "Coverage"
    oneLine:           string = "1 line"
    lineCount:         string = "% lines"
    oneWord:           string = "1 word"
    wordCount:         string = "% words"
    oneCharacter:      string = "1 character"
    characterCount:    string = "% characters"
    noFinalBreak:      string = "no break after the last line"
    glyphCount:        string = "% glyphs"
    mono:              string = "mono"
    stereo:            string = "stereo"
    channelCount:      string = "% channels"
    oneSample:         string = "1 sample"
    sampleCount:       string = "% samples"
    track:             string = "Track %"
    empty:             string = "None"
    unavailable:       string = "Read error"
    iccProfile:        string = "Embedded ICC profile"
    iccInspectionOnly: string = "% · inspection only"
    iccProfileError:   string = "Embedded ICC profile cannot be inspected: %"
    xmpPacketError:    string = "XMP packet cannot be inspected: %"
}

private const FrenchMediaStringsName = "lang/fr/scope.media.tweak"
private const FrenchMediaStrings     = #include("../datas/lang/fr/scope.media.tweak")

private var g_MediaInfoStrings: MediaInfoStrings

func mediaInfoStrings()->*MediaInfoStrings => &g_MediaInfoStrings

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
        case .Custom:            return .name.toString()
        case .Media:             return s.media
        case .Image:             return s.image
        case .Video:             return s.video
        case .Metadata:          return s.metadata
        case .Technical:         return s.technical
        case .Document:          return s.document
        case .Text:              return s.text
        case .Sound:             return s.sound
        case .Font:              return s.font
        case .Table:             return s.table
        case .Music:             return s.music
        case .Binary:            return s.binary
        case .Format:            return s.format
        case .Codec:             return s.codec
        case .Dimensions:        return s.dimensions
        case .DisplaySize:       return s.displaySize
        case .AspectRatio:       return s.aspectRatio
        case .PixelFormat:       return s.pixelFormat
        case .Depth:             return s.depth
        case .Frames:            return s.frames
        case .Pages:             return s.pages
        case .Lines:             return s.lines
        case .Sections:          return s.sections
        case .Members:           return s.members
        case .Typeface:          return s.typeface
        case .Duration:          return s.duration
        case .FrameRate:         return s.frameRate
        case .ExactFrameRate:    return s.exactFrameRate
        case .Bitrate:           return s.bitrate
        case .Audio:             return s.audio
        case .Subtitles:         return s.subtitles
        case .Name:              return s.name
        case .Language:          return s.language
        case .Encoding:          return s.encoding
        case .SampleRate:        return s.sampleRate
        case .Channels:          return s.channels
        case .SampleSize:        return s.sampleSize
        case .Levels:            return s.levels
        case .SamplePeak:        return s.samplePeak
        case .RmsLevel:          return s.rmsLevel
        case .FullScale:         return s.fullScale
        case .Title:             return s.title
        case .Author:            return s.author
        case .Publisher:         return s.publisher
        case .Published:         return s.published
        case .Created:           return s.created
        case .Application:       return s.application
        case .Description:       return s.description
        case .Tags:              return s.tags
        case .Artist:            return s.artist
        case .Album:             return s.album
        case .AlbumArtist:       return s.albumArtist
        case .Year:              return s.year
        case .TrackNumber:       return s.trackNumber
        case .Disc:              return s.disc
        case .Genre:             return s.genre
        case .Weight:            return s.weight
        case .Embedding:         return s.embedding
        case .Columns:           return s.columns
        case .Tracks:            return s.tracks
        case .LongestLine:       return s.longestLine
        case .ControlCharacters: return s.controls
        case .Replacements:      return s.replacements
        case .Transparency:      return s.transparency
        case .Character:         return s.character
        case .GlyphIndex:        return s.glyphIndex
        case .Timing:            return s.timing
        case .Overlaps:          return s.overlaps
        case .ShortestCue:       return s.shortestCue
        case .Bookmarks:         return s.bookmarks
        case .TextLayer:         return s.textLayer
        case .Style:             return s.style
        case .UnitsPerEm:        return s.unitsPerEm
        case .Faces:             return s.faces
        case .Version:           return s.version
        case .Designer:          return s.designer
        case .Copyright:         return s.copyright
        case .Separator:         return s.separator
        case .Meter:             return s.meter
        case .Tempo:             return s.tempo
        case .KeySignature:      return s.keySignature
        case .LineEnds:          return s.lineEnds
        case .Coverage:          return s.coverage
        case .Track:             return .name.toString()
        case .Empty:             return s.empty
        case .Unavailable:       return s.unavailable
        }
    }

    // Reports whether the reading is a measure, set in the fixed-width face, rather than a name.
    mtd const isMeasure()->bool
    {
        switch .field
        {
        case .Dimensions, .DisplaySize, .AspectRatio, .Depth, .Frames, .Pages, .Lines,
             .Sections, .Members, .Duration, .FrameRate, .ExactFrameRate, .Bitrate, .SampleRate,
             .Channels, .SampleSize, .SamplePeak, .RmsLevel, .FullScale, .Bookmarks, .UnitsPerEm,
             .Faces, .Meter, .LineEnds, .LongestLine, .ControlCharacters, .Replacements:
            return true

        default: return false
        }
    }
}

// Counts samples as a reading says it.
func sampleCountText(count: u64)->String => count == 1 ? String.from(g_MediaInfoStrings.oneSample) : Format.toString(g_MediaInfoStrings.sampleCount, count)

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

// Counts characters as a reading says it.
func characterCountText(count: u64)->String => count == 1 ? String.from(g_MediaInfoStrings.oneCharacter) : Format.toString(g_MediaInfoStrings.characterCount, count)

// Counts the glyphs of a font as a figure says it.
func glyphCountText(count: u64)->String => Format.toString(g_MediaInfoStrings.glyphCount, count)

// Returns the default name of the track numbered `number`.
func trackText(number: u64)->String => Format.toString(g_MediaInfoStrings.track, number)

// Owns values independently of the decoded pixels, file mapping, and language table.
private const IccProfileLimit = 1024'u64 * 1024
private const XmpPacketLimit  = 1024'u64 * 1024

private struct XmpBinding
{
    prefix: String
    uri:    String
    depth:  u32
}

private struct XmpField
{
    name:  String
    value: String
}

private func xmpQNameParts(name: string, prefix: *String, local: *String)->bool
{
    let separator = Utf8.indexOf(name, ":")
    if separator == Swag.U64.Max or separator == 0 or separator + 1 >= name.count do
        return false
    prefix[] = String.from(name[until separator])
    local[]  = String.from(name[separator + 1 to])
    return true
}

private func xmpNamespace(bindings: const [..] XmpBinding, prefix: string)->string?
{
    var index = bindings.count
    while index
    {
        index -= 1
        if bindings[index].prefix == prefix do
            return bindings[index].uri.toString()
    }

    if prefix == "xml" do
        return "http://www.w3.org/XML/1998/namespace"
    return null
}

private func xmpProperty(name: string, bindings: const [..] XmpBinding, attribute: bool)->String
{
    var prefix: String
    var local:  String
    if not xmpQNameParts(name, &prefix, &local)
    {
        // XML's default namespace applies to element names, but never to attributes.
        if attribute or not name.count do
            return {}
        local = String.from(name)
    }

    let uri = xmpNamespace(bindings, prefix)
    if not uri do
        return {}
    if uri == "http://purl.org/dc/elements/1.1/" and
       (local == "title" or local == "creator" or local == "description" or local == "rights" or local == "subject") do
        return Format.toString("XMP %", name)
    if uri == "http://ns.adobe.com/xap/1.0/" and
       (local == "CreateDate" or local == "ModifyDate" or local == "CreatorTool") do
        return Format.toString("XMP %", name)
    return {}
}

// Parses a small descriptive XMP subset by namespace URI. The XML scanner disables DTDs and
// external entities; size and depth are bounded before any value is surfaced.
private func readXmp(bytes: const [..] u8, fields: *Array'XmpField, problem: *String)->bool
{
    if bytes.count > XmpPacketLimit
    {
        problem[] = "XMP packet exceeds the 1 MiB inspection limit"
        return false
    }

    if not bytes.count or not Utf8.isValid(bytes)
    {
        problem[] = "XMP packet is empty or is not valid UTF-8"
        return false
    }

    let source      = cast(string, bytes)
    var scanner     = Viewers.Package.Scanner.create(source)
    var token:       Viewers.Package.Token
    var bindings:    Array'XmpBinding
    var elements:    Array'String
    var activeName:  String
    var activeValue: String
    var activeDepth = 0'u32
    var depth       = 0'u32
    var rootSeen    = false
    var rootClosed  = false

    while scanner.next(&token)
    {
        switch token.kind
        {
        case .Start:
            if depth >= 64
            {
                problem[] = "XMP XML nesting exceeds the 64-element limit"
                return false
            }

            if not depth
            {
                if rootSeen
                {
                    problem[] = "XMP packet contains more than one root element"
                    return false
                }

                rootSeen = true
            }

            depth += 1
            elements.add(String.from(token.name))

            // Preserve namespace scope by recording declarations at their source depth; bindings
            // are removed as their elements close, so a nested prefix override cannot leak out.
            for &attribute in token.attributes
            {
                if attribute.name == "xmlns" do
                    bindings.add(XmpBinding{{}, String.from(attribute.value), depth})
                elif Utf8.startsWith(attribute.name.toString(), "xmlns:")
                    do
                    bindings.add(XmpBinding{String.from(cast(string, attribute.name.toSlice()[6 to])), String.from(attribute.value), depth})
            }

            // XMP commonly stores simple values as attributes on rdf:Description as well as child
            // elements. Keep their qualified property names so they remain distinct from EXIF.
            let propertyName = xmpProperty(token.name, bindings.toSlice(), false)
            if propertyName.count and not activeName.count
            {
                activeName = propertyName
                activeValue.clear()
                activeDepth = depth
            }

            for &attribute in token.attributes
            {
                let attributeName = xmpProperty(attribute.name.toString(), bindings.toSlice(), true)
                if attributeName.count
                {
                    let value = Latin1.trim(attribute.value.toString())
                    if value.count do
                        fields.add(XmpField{attributeName, String.from(value)})
                }
            }

            if token.empty
            {
                if activeName.count and activeDepth == depth
                {
                    let value = Latin1.trim(activeValue.toString())
                    if value.count do
                        fields.add(XmpField{#move activeName, String.from(value)})
                    activeValue.clear()
                    activeDepth = 0
                }

                while bindings.count and bindings[bindings.count - 1].depth == depth do
                    bindings.removeBack()
                elements.removeBack()
                depth -= 1
                if not depth do
                    rootClosed = true
            }

        case .Text:
            if activeName.count and depth >= activeDepth and token.text.count
            {
                if activeValue.count and Latin1.trim(token.text.toString()).count do
                    activeValue += "; "
                activeValue += token.text
            }

        case .End:
            if not depth or elements[depth - 1] != token.name
            {
                problem[] = "XMP XML has mismatched or unexpected closing elements"
                return false
            }

            if activeName.count and activeDepth == depth
            {
                let value = Latin1.trim(activeValue.toString())
                if value.count do
                    fields.add(XmpField{#move activeName, String.from(value)})
                activeValue.clear()
                activeDepth = 0
            }

            while bindings.count and bindings[bindings.count - 1].depth == depth do
                bindings.removeBack()
            elements.removeBack()
            depth -= 1
            if not depth do
                rootClosed = true
        }
    }

    if scanner.damaged or not rootSeen or not rootClosed or depth
    {
        problem[] = "XMP XML is malformed or incomplete"
        return false
    }

    return true
}

private func readIccU32(bytes: const [..] u8, offset: u64, value: *u32)->bool
{
    if offset > bytes.count or bytes.count - offset < 4 do
        return false
    value[] = (cast(u32, bytes[offset]) << 24) |
              (cast(u32, bytes[offset + 1]) << 16) |
              (cast(u32, bytes[offset + 2]) << 8) |
              cast(u32, bytes[offset + 3])
    return true
}

private func iccSignature(bytes: const [..] u8, offset: u64)->String
{
    var result: #returntype
    for index in 4
    {
        let byte = bytes[offset + index]
        result += cast(rune, byte >= 32 and byte <= 126 ? byte : '?')
    }

    return result
}

// Reads a bounded ICC `mluc` description, preferring an English locale and otherwise the first
// valid record. Malformed UTF-16 or record ranges fail rather than displaying replacement text.
private func readIccMlucName(bytes: const [..] u8, name: *String, problem: *String)->bool
{
    if bytes.count < 16 or iccSignature(bytes, 0) != "mluc"
    {
        problem[] = "profile `mluc` description header is truncated"
        return false
    }

    var count:      u32
    var recordSize: u32
    if not readIccU32(bytes, 8, &count) or
       not readIccU32(bytes, 12, &recordSize) or
       count == 0 or
       count > 64 or
       recordSize < 12 or
       recordSize > 128
    {
        problem[] = "profile `mluc` record table is invalid or exceeds the inspection limit"
        return false
    }

    if cast(u64, count) > (bytes.count - 16) / recordSize
    {
        problem[] = "profile `mluc` record table is truncated"
        return false
    }

    let tableEnd = 16 + cast(u64, count) * recordSize
    var firstValid: String
    var english:    String
    for index in count
    {
        let at = 16 + cast(u64, index) * recordSize
        var byteLength: u32
        var offset:     u32
        if not readIccU32(bytes, at + 4, &byteLength) or
           not readIccU32(bytes, at + 8, &offset) or
           byteLength > 512 or
           byteLength % 2 != 0 or
           cast(u64, offset) < tableEnd or
           cast(u64, offset) > bytes.count or
           cast(u64, byteLength) > bytes.count - cast(u64, offset)
        {
            problem[] = "profile `mluc` text range is invalid or exceeds the 512-byte limit"
            return false
        }

        if not byteLength do
            continue

        var units: Array'u16
        units.resize(byteLength / 2)
        for unit in units.count
        {
            let byteAt = cast(u64, offset) + unit * 2
            units[unit] = (cast(u16, bytes[byteAt]) << 8) | cast(u16, bytes[byteAt + 1])
            let value = units[unit]
            if value >= Utf16.Surr1 and value < Utf16.Surr2
            {
                if unit + 1 >= units.count or
                   units[unit + 1] < Utf16.Surr2 or
                   units[unit + 1] >= Utf16.Surr3
                {
                    problem[] = "profile `mluc` text contains an unpaired high surrogate"
                    return false
                }
            }
            elif value >= Utf16.Surr2 and value < Utf16.Surr3
            {
                if unit == 0 or units[unit - 1] < Utf16.Surr1 or units[unit - 1] >= Utf16.Surr2
                {
                    problem[] = "profile `mluc` text contains an unpaired low surrogate"
                    return false
                }
            }
        }

        var candidate = Utf8.fromUtf16(units.toSlice())
        candidate = Latin1.trim(candidate)
        if not candidate.count do
            continue
        if not firstValid.count do
            firstValid = candidate
        let englishLocale = bytes[at] == 'e' and bytes[at + 1] == 'n'
        if englishLocale and not english.count do
            english = candidate
    }

    if english.count
    {
        name[] = #move english
    }
    elif firstValid.count
    {
        name[] = #move firstValid
    }
    else
    {
        problem[] = "profile `mluc` has no nonempty valid locale description"
        return false
    }

    return true
}

// Reads only the bounded ICC header and optional ASCII `desc` tag. This names embedded profile
// data; it does not validate color transforms or imply that the display pipeline applies it.
private func inspectIccProfile(bytes: const [..] u8, identity: *String, problem: *String)->bool
{
    if bytes.count > IccProfileLimit
    {
        problem[] = "profile exceeds the 1 MiB inspection limit"
        return false
    }

    if bytes.count < 128
    {
        problem[] = "profile header is shorter than 128 bytes"
        return false
    }

    var declaredSize: u32
    if not readIccU32(bytes, 0, &declaredSize) or declaredSize < 128 or declaredSize > bytes.count
    {
        problem[] = "declared profile size is outside the embedded data"
        return false
    }

    let profile = bytes[until declaredSize]
    if iccSignature(profile, 36) != "acsp"
    {
        problem[] = "profile header has no `acsp` signature"
        return false
    }

    let colorSpace = iccSignature(profile, 16)
    let pcs        = iccSignature(profile, 20)
    var name:     String
    var tagCount: u32
    if declaredSize >= 132 and readIccU32(profile, 128, &tagCount)
    {
        // Profile tag tables are small in conforming files; do not walk attacker-sized tables.
        if tagCount > 256 or cast(u64, tagCount) > (declaredSize - 132) / 12
        {
            problem[] = "profile tag table is truncated or exceeds the inspection limit"
            return false
        }

        for index in tagCount
        {
            let recordAt = 132 + cast(u64, index) * 12
            if iccSignature(profile, recordAt) != "desc" do
                continue

            var offset: u32
            var length: u32
            if not readIccU32(profile, recordAt + 4, &offset) or
               not readIccU32(profile, recordAt + 8, &length) or
               offset > declaredSize or
               length < 12 or
               cast(u64, offset) + length > declaredSize
            {
                problem[] = "profile description tag points outside the embedded data"
                return false
            }

            let description = profile[offset until cast(u64, offset) + length]
            if iccSignature(description, 0) == "mluc"
            {
                if not readIccMlucName(description, &name, problem) do
                    return false
            }
            elif iccSignature(description, 0) == "desc"
            {
                var textLength: u32
                if not readIccU32(description, 8, &textLength) or
                   textLength > 512 or
                   textLength > length - 12
                {
                    problem[] = "profile description text is truncated or too long"
                    return false
                }

                for byte in description[12 until 12 + textLength]
                {
                    if byte == 0 do
                        break
                    name += cast(rune, byte >= 32 and byte <= 126 ? byte : '?')
                }

                name = Latin1.trim(name)
            }

            break
        }
    }

    identity[] = Format.toString("Embedded ICC · % · PCS %", colorSpace, pcs)
    if name.count do
        identity[] += Format.toString(" · %", name)
    return true
}

private struct JpegIccChunk
{
    bytes:   Array'u8
    present: bool
}

// Reassembles bounded JPEG APP2 ICC_PROFILE records in their declared sequence order.
private func assembleJpegIccProfile(records: const [..] ImageMetadata, profile: *Array'u8, problem: *String)->bool
{
    var segmentCount: u8
    var chunkCount:   u64
    for record in records where record.signature == 2 and record.isTag("ICC_PROFILE")
    {
        chunkCount += 1
        let bytes = record.toSlice()
        if bytes.count < 2
        {
            problem[] = "JPEG ICC segment is missing its sequence header"
            return false
        }

        let sequence = bytes[0]
        let count    = bytes[1]
        if count == 0 or sequence == 0 or sequence > count
        {
            problem[] = "JPEG ICC segment has an invalid sequence number"
            return false
        }

        if segmentCount and segmentCount != count
        {
            problem[] = "JPEG ICC segments disagree on their total count"
            return false
        }

        segmentCount = count
    }

    if not chunkCount do
        return false
    if chunkCount != segmentCount
    {
        problem[] = "JPEG ICC profile is missing one or more segments"
        return false
    }

    var chunks: Array'JpegIccChunk
    chunks.resize(segmentCount)
    var totalBytes = 0'u64
    for record in records where record.signature == 2 and record.isTag("ICC_PROFILE")
    {
        let bytes       = record.toSlice()
        let sequence    = bytes[0]
        let payloadSize = bytes.count - 2
        if chunks[sequence - 1].present
        {
            problem[] = "JPEG ICC profile contains a duplicate segment"
            return false
        }

        if payloadSize > IccProfileLimit - totalBytes
        {
            problem[] = "JPEG ICC profile exceeds the 1 MiB assembly limit"
            return false
        }

        totalBytes += payloadSize
        chunks[sequence - 1].bytes   = bytes[2 to]
        chunks[sequence - 1].present = true
    }

    profile[].reserve(totalBytes)
    for chunk in chunks
    {
        if not chunk.present
        {
            problem[] = "JPEG ICC profile is missing one or more segments"
            return false
        }

        profile[].add(chunk.bytes.toSlice())
    }

    return true
}

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

        // A text broken into lines whose last one has no break says so, as a diff would.
        var ends = statistics.lineEnds()
        if ends.count and statistics.unended do
            ends = Format.toString("% · %", ends, s.noFinalBreak)
        if ends.count do
            .add(.LineEnds, ends)

        // The widest line, then what may not read as text: control characters and the U+FFFD that
        // bytes the encoding could not read become.
        if statistics.lines > 1 do
            .add(.LongestLine, characterCountText(statistics.longest))
        if statistics.controls do
            .add(.ControlCharacters, Format.toString("%", statistics.controls))
        if statistics.replaced do
            .add(.Replacements, Format.toString("%", statistics.replaced))
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

        var hasJpegIcc = false
        for record in records where record.signature == 2 and record.isTag("ICC_PROFILE") do
            hasJpegIcc = true
        if hasJpegIcc
        {
            let strings = &g_MediaInfoStrings
            var profile:  Array'u8
            var identity: String
            var problem:  String
            if assembleJpegIccProfile(records, &profile, &problem)
            {
                if inspectIccProfile(profile.toSlice(), &identity, &problem)
                    do
                    .addText(strings.iccProfile, Format.toString(strings.iccInspectionOnly, identity))
                else do
                    .add(.Unavailable, Format.toString(strings.iccProfileError, problem))
            }
            else
            {
                .add(.Unavailable, Format.toString(strings.iccProfileError, problem))
            }
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

            if record.isTag("ICC")
            {
                let strings = &g_MediaInfoStrings
                var identity: String
                var problem:  String
                if inspectIccProfile(record.toSlice(), &identity, &problem)
                    do
                    .addText(strings.iccProfile, Format.toString(strings.iccInspectionOnly, identity))
                else do
                    .add(.Unavailable, Format.toString(strings.iccProfileError, problem))
                continue
            }

            let jpegXmp = record.signature == 1 and cast(string, record.tag.toSlice()) == "http://ns.adobe.com/xap/1.0/"
            if record.isTag("XMP") or jpegXmp
            {
                var fields:  Array'XmpField
                var problem: String
                if readXmp(record.toSlice(), &fields, &problem)
                {
                    for &field in fields do
                        .addText(field.name, field.value)
                    if not fields.count do
                        .addText("XMP packet", "No supported descriptive fields")
                }
                else
                {
                    .add(.Unavailable, Format.toString(g_MediaInfoStrings.xmpPacketError, problem))
                }

                continue
            }

            if record.signature == 2 and record.isTag("ICC_PROFILE") do
                continue

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
            case row.field == .Unavailable: sheet.addNote(row.value.isEmpty() ? row.label() : row.value.toString())
            case row.field == .Track:       sheet.addTrack(row.number, row.name, row.value)
            case row.value.isEmpty():       sheet.addText(row.label())
            default: sheet.addReading(row.label(), row.value, mono: row.isMeasure())
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
