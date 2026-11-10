using Core, Gui, Pixel

// Capture kinds and their compact choices in the in-place overlay, after the charter picture of
// the aiming overlay.
const OptionChipInset  = 9.0      // Air on each side of the content of an option.
const OptionChipIcon   = 16.0     // Side of the glyph of an option.
const OptionChipGap    = 8.0      // Air between the glyph of an option and its words.

// The kinds a zone can become, in menu and Tab order. A kind joins when it can be taken.
const KindMedia = [CaptureMedia.Picture, CaptureMedia.Animation, CaptureMedia.Video]

// Returns the next capture kind for the overlay's Tab key.
func nextCaptureMedia(media: CaptureMedia)->CaptureMedia
{
    for kind, index in KindMedia where kind == media do
        return KindMedia[(index + 1) % KindMedia.count]
    return KindMedia[0]
}

// Returns the name of the kind of capture `media`.
func kindName(media: CaptureMedia)->string
{
    switch #complete media
    {
    case .Picture:   return appStrings().ui_MediaPicture
    case .Animation: return appStrings().ui_MediaAnimation
    case .Video:     return appStrings().ui_MediaVideo
    }
}

// Returns the glyph that identifies a capture kind in its menu and on the zone.
func kindIcon(main: *MainWnd, theme: *Theme, media: CaptureMedia)->Icon
{
    let size = theme.metrics.menuPopup_IconSize
    switch #complete media
    {
    case .Picture:   return main.icon(.Image, size)
    case .Animation: return theme.icon(.Play, size)
    case .Video:     return main.icon(.Video, size)
    }
}

// Stable menu IDs keep the choice independent of its translated name.
func kindMenuId(media: CaptureMedia)->string
{
    switch #complete media
    {
    case .Picture:   return "capture.kind.picture"
    case .Animation: return "capture.kind.animation"
    case .Video:     return "capture.kind.video"
    }
}

// An option of a recording: a glyph and its words, on a chosen ground while it is on. An inert
// option stays in its place out of reach, its words saying why.
struct OptionChip
{
    using wnd: Wnd

    sigPressed: SigArray'func||(*OptionChip)     // Emitted after a click on an option within reach.
    glyph:      Icon
    label:      String
    on:         bool
    inert:      bool
    pointed:    bool     // The pointer is over the option.
    pressing:   bool     // The left button went down on the option.
}

impl IWnd for OptionChip
{
    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        switch evt.kind
        {
        case .Enter, .Leave:
            .pointed = evt.kind == .Enter
            .invalidate()

        case .Pressed where evt.button == .Left and not .inert:
            .pressing = true
            .captureMouse()

        case .Released where evt.button == .Left and .pressing:
            .pressing = false
            .releaseMouse()
            if .clientRect().contains(.surfaceToLocal(evt.surfacePos)) do
                .sigPressed.call(me)
        }
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let colors  = .themeColors()
        let metrics = .themeMetrics()
        let client  = .clientRect()
        let cy      = client.vertCenter()
        let font    = .labelFont()

        painter.setParams(.Antialiased)
        if .on and not .inert do
            painter.fillRoundRect(client, metrics.corner_Control, metrics.corner_Control, colors.selection)
        elif .pointed and not .inert do
            painter.fillRoundRect(client, metrics.corner_Control, metrics.corner_Control, colors.raised)

        let ink  = .inert ? colors.disabled : colors.text
        let mark = .inert ? colors.disabled : (.on ? colors.arc : colors.softText)
        var x    = client.x + OptionChipInset
        .glyph.paint(painter, x, cy - OptionChipIcon * 0.5, mark)
        x += OptionChipIcon + OptionChipGap
        painter.drawString(x, font.opticalLineTop(cy), .label, font, ink)
    }
}

impl OptionChip
{
    // Creates the option `label` with `glyph` in `parent`, `on` or off; an `inert` option does not
    // answer the pointer.
    func create(parent: *Wnd, glyph: Icon, label: string, on: bool, inert = false)->*OptionChip
    {
        with let result = Wnd.create'OptionChip(parent)
        {
            .glyph           = glyph
            .label           = label
            .glyph.sizeX     = OptionChipIcon
            .glyph.sizeY     = OptionChipIcon
            .on              = on
            .inert           = inert
            .backgroundStyle = .Transparent
        }

        let width = 2 * OptionChipInset + OptionChipIcon + OptionChipGap + Painter.measureString(label, result.labelFont()).width
        result.resize(Math.ceil(width), parent.themeMetrics().miniBar_ButtonSize)
        return result
    }

    // Returns the face of the words.
    mtd labelFont()->*Font => .theme().createDefaultFont(.themeMetrics().defaultFontSize)
}
