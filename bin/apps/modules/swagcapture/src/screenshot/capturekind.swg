using Core, Pixel

// The controls the bar of a fresh zone adds to its tools: the kinds of capture the zone can become,
// and the options of a recording, after the charter picture of the aiming overlay.
const KindSegmentInset = 2.0      // Air between the frame of the kinds and a kind.
const KindSegmentText  = 10.0     // Air on each side of the name of a kind.
const OptionChipInset  = 9.0      // Air on each side of the content of an option.
const OptionChipIcon   = 16.0     // Side of the glyph of an option.
const OptionChipGap    = 8.0      // Air between the glyph of an option and its words.

// The kinds of capture a zone can become, as segments in one frame. A kind is chosen with a click;
// the bar is then filled again for it.
struct KindSegments
{
    using wnd: Wnd

    sigChosen: SigArray'func||(*KindSegments)     // Emitted after a click chooses another kind.
    chosen:    CaptureMedia     // The kind shown chosen.
    hot:       s32 = -1         // The kind under the pointer, or -1.
    pressed:   s32 = -1         // The kind pressed; release elsewhere cancels the change.
}

impl IWnd for KindSegments
{
    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let index = .indexAt(.surfaceToLocal(evt.surfacePos))
        switch evt.kind
        {
        case .Move, .Enter:
            if index != .hot
            {
                .hot = index
                .invalidate()
            }

        case .Leave:
            .hot = -1
            .invalidate()

        case .Pressed where evt.button == .Left and index >= 0:
            .pressed = index
            .hot = index
            .captureMouse()
            .invalidate()

        case .Released where evt.button == .Left and .pressed >= 0:
            let chosen = .pressed
            .pressed = -1
            .releaseMouse()
            .hot = index
            .invalidate()
            if index != chosen do
                return
            let media = kindMedia(cast(u64, chosen))
            if media != .chosen
            {
                .chosen = media
                .invalidate()
                .sigChosen.call(me)
            }
        }
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let colors  = .themeColors()
        let metrics = .themeMetrics()
        let font    = .labelFont()
        let client  = .clientRect()
        let cy      = client.vertCenter()

        painter.setParams(.Antialiased)
        painter.fillRoundRect(client, metrics.corner_Control, metrics.corner_Control, colors.tabBar_RoundBk)
        for i in 0 until KindMedia.count
        {
            let r  = .segmentRect(i)
            let on = KindMedia[i] == .chosen
            if on
            {
                var lift = r
                lift.y += 1
                painter.fillRoundRect(lift, metrics.corner_Chip, metrics.corner_Chip, colors.tabItem_RoundLift)
                painter.fillRoundRect(r, metrics.corner_Chip, metrics.corner_Chip, colors.tabItem_RoundSelected)
            }
            elif cast(s32, i) == .hot
            {
                painter.fillRoundRect(r, metrics.corner_Chip, metrics.corner_Chip, colors.tabItem_RoundHot)
            }

            painter.drawString(r.x + KindSegmentText, font.opticalLineTop(cy), kindName(KindMedia[i]), font, on ? colors.text : colors.softText)
        }
    }
}

// The kinds a zone can become, in the order of their segments. A kind joins when it can be taken.
const KindMedia = [CaptureMedia.Picture, CaptureMedia.Animation]

// Returns the kind of the segment at `index`.
func kindMedia(index: u64)->CaptureMedia => KindMedia[index]

// Returns the name of the kind of capture `media`.
func kindName(media: CaptureMedia)->string => media == .Animation ? appStrings().ui_MediaAnimation : appStrings().ui_MediaPicture

impl KindSegments
{
    // Creates the kinds of capture in `parent`, `chosen` shown chosen, as wide as their names.
    func create(parent: *Wnd, chosen: CaptureMedia)->*KindSegments
    {
        with let result = Wnd.create'KindSegments(parent)
        {
            .chosen = chosen
            .backgroundStyle = .Transparent
        }

        var width = KindSegmentInset
        for media in KindMedia do
            width += measure(result, media) + KindSegmentInset
        result.resize(Math.ceil(width), parent.themeMetrics().miniBar_ButtonSize)
        return result
    }

    // Returns the width of the segment naming `media`.
    func measure(wnd: *KindSegments, media: CaptureMedia)->f32 => Painter.measureString(kindName(media), wnd.labelFont()).width + 2 * KindSegmentText

    // Returns the face of the names.
    mtd labelFont()->*Font => .theme().createDefaultFont(.themeMetrics().defaultFontSize)

    // Returns the segment at `index`, in local coordinates.
    mtd segmentRect(index: u64)->Math.Rectangle
    {
        let client = .clientRect()
        var x      = client.x + KindSegmentInset
        for i in 0 until index do
            x += measure(me, KindMedia[i]) + KindSegmentInset
        return {x, client.y + KindSegmentInset, measure(me, KindMedia[index]), client.height - 2 * KindSegmentInset}
    }

    // Returns the index of the segment at `pos`, in local coordinates, or -1.
    mtd indexAt(pos: Math.Point)->s32
    {
        for i in 0 until KindMedia.count where .segmentRect(i).contains(pos) do
            return cast(s32, i)
        return -1
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
