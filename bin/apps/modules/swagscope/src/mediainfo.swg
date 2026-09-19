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

// Visible strings of the media information panel.
struct MediaInfoStrings
{
    title:       string = "Information"
    close:       string = "Close information"
    copy:        string = "Copy information"
    property:    string = "Property"
    value:       string = "Value"
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
    expect Gui.validateStrings'MediaInfoStrings(cast(string) FrenchMediaStrings)
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

    // Appends the metadata group of a picture: decoded Exif properties, PNG text, or the size of opaque records.
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
                let properties = catch Exif.decode(payload) as error
                if error != null
                {
                    .add(.Unavailable, Errors.message(error))
                    continue
                }

                for property in properties do
                    .addText(property.name().toString(), property.value.toString())
                continue
            }

            var tag: String
            for byte in record.tag do
                tag += cast(rune) (byte >= 32 ? byte : '?')
            if tag.isEmpty() do
                tag = Format.toString("APP%", record.signature)
            let bytes = record.toSlice()
            var text: String

            // PNG tEXt is Latin-1. Other opaque records keep a bounded size description.
            if pngText
            {
                for index in Math.min(bytes.count, 4096) do
                    text += cast(rune) (bytes[index] >= 32 or bytes[index] == 10 or bytes[index] == 9 ? bytes[index] : ' ')
                if bytes.count > 4096 do
                    text += "…"
            }
            else do
                text = StrConv.toDisplaySize(bytes.count)
            .addText(tag.toString(), text.toString())
        }
    }
}

// Host-owned side panel shared by the two visual media viewers.
struct MediaInfoPanel
{
    using wnd: Wnd

    late
    {
        title:       *Label
        closeButton: *IconButton
        copyButton:  *IconButton
        toggle:      *IconButton
        list:        *ListCtrl
    }

    data:  MediaInfoData
    lines: Array'(*ListLine)
}

impl MediaInfoPanel
{
    // Creates the panel and its toggle in the side lane of the viewer `host` is building.
    func create(host: Viewer.Host)->*MediaInfoPanel
    {
        registerMediaInfoStrings(host.application())
        let theme       = host.contentParent().theme()
        let side        = host.createSidePanel(368, theme.icon(.Information, themeActionIconSize(&theme.metrics)), g_MediaInfoStrings.title)
        with let result = Wnd.create'MediaInfoPanel(side.content)
        {
            .dockStyle       = .Center
            .backgroundStyle = .Transparent
            .padding         = {12, 8, 12, 8}
            .toggle          = side.toggle
        }

        let size        = themeCompactButtonSize(result.themeMetrics())
        with let header = Wnd.create'Wnd(result, {0, 0, 0, size})
        {
            .dockStyle       = .Top
            .backgroundStyle = .Transparent
        }

        with result.closeButton = IconButton.create(header, theme.icon(.WndClose, themeRowIconSize(result.themeMetrics())), {0, 0, size, size})
        {
            .dockStyle  = .Right
            .sigPressed += func|panel = result|(button)
            {
                discard button
                panel.toggle.setChecked(false)
                panel.toggle.sigCheckedChanged.call(panel.toggle)
            }
        }

        with result.copyButton = IconButton.create(header, theme.icon(.Copy, themeRowIconSize(result.themeMetrics())), {0, 0, size, size})
        {
            .dockStyle  = .Right
            .sigPressed += func|panel = result|(button)
            {
                discard button
                Clipboard.addString(panel.text().toString())
            }
        }

        with result.title = Label.create(header, "")
        {
            .dockStyle = .Center
            .setTextAlignment(.Left, .Center)
            .style.setFont(theme.createDefaultFont(13, .Bold), .Regular)
        }

        with result.list = ListCtrl.createMultiColumns(result)
        {
            .dockStyle       = .Center
            .margin.y        = 8
            .backgroundStyle = .Transparent
            .listView.backgroundStyle = .Transparent
            .setSelectionMode(.Single)
            .setFirstColumnIconMargin(false)
            .updateFlags(.HotTrack | .Ellipsis)
            .header.form = .Transparent
            .header.updateFlags(remove: .Clickable | .Separators)
            .addColumn("", 150)
            .addColumn("", 150)
        }

        result.retranslate()
        return result
    }

    // Returns every row as one line of text, for the clipboard.
    mtd text()->String
    {
        var result: retval
        for row in .data.rows
        {
            result += row.label()
            if not row.value.isEmpty() do
                result += Format.toString(": %", row.value)
            result += "\n"
        }

        return result
    }

    // Takes the rows of `data` and shows them, every group expanded.
    mtd publish(data: *MediaInfoData)
    {
        .data = #move data[]
        .lines.clear()
        .list.clear()
        var parent: *ListLine?
        var groups: Array'*ListLine
        for row in .data.rows
        {
            let line = .list.createLine(row.group ? null : parent)
            .lines.add(line)
            line.setItem(0, row.label())
            line.setItem(1, row.value.toString())
            if row.group
            {
                parent = line
                groups.add(line)
            }
        }

        for group in groups do
            .list.expand(group)
        .retranslate()
    }

    mtd retranslate()
    {
        .title.setText(g_MediaInfoStrings.title)
        .toggle.toolTip      = g_MediaInfoStrings.title
        .closeButton.toolTip = g_MediaInfoStrings.close
        .copyButton.toolTip  = g_MediaInfoStrings.copy
        .copyButton.enable(not .data.rows.isEmpty())
        .list.header.itemAt(0).name = g_MediaInfoStrings.property
        .list.header.itemAt(1).name = g_MediaInfoStrings.value
        .list.header.invalidate()
        for row, index in .data.rows do
            .lines[index].setItem(0, row.label())
        .list.computeLayout()
        .applyLayout()
        .invalidate()
    }
}

private impl IWnd for MediaInfoPanel
{
    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged do
            .retranslate()
        else do
            evt.accepted = false
    }
}
