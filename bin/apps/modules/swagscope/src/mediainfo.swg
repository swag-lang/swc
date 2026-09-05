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

private const MediaFrenchName = "lang/fr/scope.media.tweak"
private const MediaFrench     = #include("../datas/lang/fr/scope.media.tweak")
private var g_MediaInfoStrings: MediaInfoStrings

func registerMediaInfoStrings(app: *Application)
{
    app.resources.addEmbedded(MediaFrenchName, MediaFrench)
    Gui.registerStrings'MediaInfoStrings(&g_MediaInfoStrings, "scope.media")
}

#run
{
    expect Gui.validateStrings'MediaInfoStrings(cast(string) MediaFrench)
}

struct MediaInfoRow
{
    field: MediaInfoField
    name:  String
    value: String
    group: bool
}

impl MediaInfoRow
{
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
    mtd add(field: MediaInfoField, value: string = "", group = false)
    {
        var row = MediaInfoRow{field: field, group: group}
        row.value = value
        .rows.add(#move row)
    }

    mtd addText(name, value: string)
    {
        var row: MediaInfoRow
        row.name  = name
        row.value = value
        .rows.add(#move row)
    }

    mtd addImageMetadata(records: const [..] ImageMetadata, pngText = false)
    {
        .add(.Metadata, group: true)
        if !records.count
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

    data: MediaInfoData
}

impl MediaInfoPanel
{
    func create(host: Viewer.Host)->*MediaInfoPanel
    {
        registerMediaInfoStrings(host.application())
        let theme  = host.contentParent().theme()
        let side   = host.createSidePanel(368, theme.icon(.Information, themeActionIconSize(&theme.metrics)), g_MediaInfoStrings.title)
        let result = Wnd.create'MediaInfoPanel(side.content)
        result.dockStyle       = .Center
        result.backgroundStyle = .Transparent
        result.padding         = {12, 8, 12, 8}
        result.toggle          = side.toggle

        let size   = themeCompactButtonSize(result.themeMetrics())
        let header = Wnd.create'Wnd(result, {0, 0, 0, size})
        header.dockStyle              = .Top
        header.backgroundStyle        = .Transparent
        result.closeButton            = IconButton.create(header, theme.icon(.WndClose, themeRowIconSize(result.themeMetrics())), {0, 0, size, size})
        result.closeButton.dockStyle  = .Right
        result.closeButton.sigPressed += func|panel = result|(button)
        {
            discard button
            panel.toggle.setChecked(false)
            panel.toggle.sigCheckedChanged.call(panel.toggle)
        }
        result.copyButton            = IconButton.create(header, theme.icon(.Copy, themeRowIconSize(result.themeMetrics())), {0, 0, size, size})
        result.copyButton.dockStyle  = .Right
        result.copyButton.sigPressed += func|panel = result|(button)
        {
            discard button
            Clipboard.addString(panel.text().toString())
        }
        result.title           = Label.create(header, "")
        result.title.dockStyle = .Center
        result.title.setTextAlignment(.Left, .Center)
        result.title.style.setFont(theme.createDefaultFont(13, .Bold), .Regular)

        with result.list = ListCtrl.createMultiColumns(result)
        {
            .dockStyle                = .Center
            .margin.y                 = 8
            .backgroundStyle          = .Transparent
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

    mtd text()->String
    {
        var result: retval
        for row in .data.rows
        {
            result += row.label()
            if !row.value.isEmpty() do
                result += Format.toString(": %", row.value)
            result += "\n"
        }

        return result
    }

    mtd publish(data: *MediaInfoData)
    {
        .data = #move data[]
        .retranslate()
    }

    mtd retranslate()
    {
        .title.setText(g_MediaInfoStrings.title)
        .toggle.toolTip      = g_MediaInfoStrings.title
        .closeButton.toolTip = g_MediaInfoStrings.close
        .copyButton.toolTip  = g_MediaInfoStrings.copy
        .copyButton.enable(!.data.rows.isEmpty())
        .list.header.itemAt(0).name = g_MediaInfoStrings.property
        .list.header.itemAt(1).name = g_MediaInfoStrings.value
        .list.header.invalidate()
        .list.clear()
        var parent: *ListLine?
        var groups: Array'*ListLine
        for row in .data.rows
        {
            let line = .list.createLine(row.group ? null : parent)
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
