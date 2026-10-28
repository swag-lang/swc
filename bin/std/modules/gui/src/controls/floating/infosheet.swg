#global public

using Core, Pixel

// The information sheet a key opens: the readings of what the window shows, floating at its
// trailing edge.
//
// This is the sheet of the charter (`I`): the surface ground on the floating corner,
// [[Gui.ThemeMetrics.infoSheet_Width]] wide, [[Gui.ThemeMetrics.floating_Inset]] from the
// trailing and bottom edges of its parent and clear of the window chrome at the top. It holds
// what an information band used to show, and only while the reader asks for it: a title, a mono
// line of identity, the facts the reader came for set large and light, readings as a label and a
// value, section labels, a paragraph, links in Arc, and at most one primary action. A picture of
// what the sheet describes — a poster, a cover, a capture — may head it.
//
// The sheet floats over the work ([[Gui.DockStyle.Float]]) and stays hidden until
// [[Gui.InfoSheet.open]]; the application binds the key that toggles it. Describe the content
// again with [[Gui.InfoSheet.clear]] and the `add` methods whenever what the window shows changes.
//
// ```swag
// with let sheet = InfoSheet.create(view)
// {
//     .setTitle("viewerchrome.swg")
//     .setIdentity("swagscope / src")
//     .addFact("612", "lines")
//     .addReading("Encoding", "UTF-8")
//     .addReading("Size", "24.1 KB")
// }
//
// sheet.toggle()
// ```
struct InfoSheet
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.

        readonly
        {
            title:    String           // Title of the sheet, set large and bold.
            identity: String           // Mono line of identity under the title: a path, a format, a date.
            action:   *PushButton?     // The one primary action of the sheet, when it has one.
            picture:  Texture          // Picture heading the sheet, borrowed from its owner; invalid for none.
        }
    }

    blocks:  Array'InfoSheetBlock
    hotLink: u64 = Swag.U64.Max
}

internal enum InfoSheetBlockKind
{
    Fact
    Reading
    Section
    Text
    Link
}

internal struct InfoSheetBlock
{
    kind:   InfoSheetBlockKind
    label:  String     // Label of a reading, unit of a fact, words of a section, a paragraph or a link.
    value:  String     // Value of a reading or of a fact.
    mono:   bool       // Whether the value is a measure, set in the fixed-width face.
    id:     WndId?     // Command a link posts.
    top:    f32        // Top of the block in the body, from the latest layout.
    height: f32        // Height of the block, from the latest layout.
}

impl IWnd for InfoSheet
{
    mtd impl onLayout()
    {
        let parent = .parent
        if not parent do
            return

        let metrics = .themeMetrics()
        let bounds  = parent.clientRect()
        let inset   = metrics.floating_Inset
        let width   = Math.min(metrics.infoSheet_Width, bounds.width - 2 * inset)
        let top     = bounds.y + Math.max(inset, parent.stripInset())
        let height  = Math.min(.measureBody(width), bounds.bottom() - inset - top)
        let left    = bounds.right() - inset - width
        liftFloating(me)
        .setPosition(Math.Rectangle{left, top, width, height})

        if .action
        {
            let pad = metrics.infoSheet_Padding
            .action.setPosition(Math.Rectangle{pad, height - pad - metrics.btnPush_Height, width - 2 * pad, metrics.btnPush_Height})
        }
    }

    mtd impl onBeforePaint(evt: *PaintEvent)
    {
        paintFloatingShadow(me, evt.paintContext.painter, .clientRect(), .themeMetrics().corner_Floating)
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let metrics = .themeMetrics()
        let colors  = .themeColors()
        let theme   = .theme()
        let body    = .body()
        let pad     = metrics.infoSheet_Padding

        paintFloatingGround(me, painter, body, metrics.corner_Floating)

        // A sheet shorter than its blocks keeps its action whole: the blocks stop above it.
        var blocksArea = body
        if .action do
            blocksArea.height = Math.max(.action.position.y - metrics.infoSheet_BlockGap * 0.5 - body.y, 0)
        painter.pushClippingRect(blocksArea)
        defer painter.popClippingRect()

        let x     = body.x + pad
        let width = body.width - 2 * pad
        var y     = body.y + pad

        // The picture keeps its proportions, on the corner of a control, at the head of the sheet.
        if .picture.isValid()
        {
            let size = .pictureSize(width)
            painter.setParams(.Antialiased)
            painter.fillRoundRect(Math.Rectangle{x, y, size.x, size.y}, metrics.corner_Control, metrics.corner_Control, Brush.createTexture(.picture))
            y += size.y + metrics.infoSheet_BlockGap
        }

        let titleFont = theme.createDefaultFont(metrics.infoSheet_TitleFontSize, .Bold)
        if not .title.isEmpty()
        {
            painter.drawString(x, y, .title, titleFont, colors.text)
            y += titleFont.height
        }

        let monoFont = theme.createDefaultFontFs(metrics.defaultFontSize - 1)
        if not .identity.isEmpty()
        {
            painter.drawString(x, y + metrics.infoSheet_LineGap, .identity, monoFont, colors.faintText)
        }

        let bodyFont  = theme.createDefaultFont(metrics.defaultFontSize)
        let valueMono = theme.createDefaultFontFs(metrics.defaultFontSize)
        let factFont  = theme.createDefaultFont(metrics.infoSheet_FactFontSize)
        for block, index in .blocks
        {
            let top     = body.y + block.top
            let centerY = top + block.height * 0.5
            switch block.kind
            {
            case .Fact:
                let used = paintTextLine(painter, x, centerY, block.value, factFont, colors.text)
                discard paintTextLine(painter, x + used + metrics.iconText_Margin * 0.5, centerY, block.label, monoFont, colors.faintText)

            case .Reading:
                // A label longer than its column pushes its value along rather than running into it.
                let used   = paintTextLine(painter, x, centerY, block.label, bodyFont, colors.softText)
                let valueX = Math.max(x + metrics.infoSheet_LabelWidth, Math.ceil(x + used + metrics.iconText_Margin))
                discard paintTextLine(painter, valueX, centerY, block.value, block.mono ? valueMono : bodyFont, colors.text)

            case .Section:
                paintSectionLabel(me, painter, Math.Rectangle{x, top, width, block.height}, block.label)

            case .Text:
                var text: RichString
                text.set(block.label)
                painter.drawRichString(Math.Rectangle{x, top, width, block.height}, &text, .paragraphFormat())

            case .Link:
                let color = index == .hotLink ? colors.arc : colors.link
                discard paintTextLine(painter, x, centerY, block.label, bodyFont, color)
            }
        }
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let pos = .surfaceToLocal(evt.surfacePos)
        switch evt.kind
        {
        case .Move:
            let hot = .linkAt(pos)
            if hot != .hotLink
            {
                .hotLink = hot
                .invalidate()
            }

        case .Leave:
            .hotLink = Swag.U64.Max
            .invalidate()

        case .Pressed:
            let link = .linkAt(pos)
            if evt.button == .Left and link != Swag.U64.Max do
                .postCommandEvent(.blocks[link].id)
        }
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .ThemeChanged or evt.kind == .LanguageChanged do
            .relayout()
        evt.accepted = false
    }
}

impl InfoSheet
{
    // Creates an empty, hidden information sheet floating over `parent`.
    #[Swag.Discardable]
    func create(parent: *Wnd, id: WndId? = null)->*InfoSheet
    {
        with let result = Wnd.create'InfoSheet(parent, null, {}, id)
        {
            .dockStyle       = .Float
            .backgroundStyle = .Transparent
            .wndFlags.add(.Hidden)
        }

        return result
    }

    // Shows the sheet at the trailing edge of its parent.
    //
    // It arrives from the edge it stands against.
    mtd open()
    {
        .itf.onLayout()
        .bringToFront()
        discard .app().animator.arrive(me, {.themeMetrics().motion_EdgeTravel, 0})
    }

    // Hides the sheet: it is gone for the hand at once and fades out.
    mtd close()
    {
        discard .app().animator.leave(me)
    }

    // Shows the sheet when it is hidden and hides it when it is shown, as its key does.
    mtd toggle()
    {
        if .isLocallyVisible() do
            .close()
        else do
            .open()
    }

    // Sets the title of the sheet.
    mtd setTitle(title: string)
    {
        .title = title
        .relayout()
    }

    // Sets the mono line of identity written under the title.
    mtd setIdentity(identity: string)
    {
        .identity = identity
        .relayout()
    }

    // Heads the sheet with `picture`, or removes the picture with an invalid texture.
    //
    // The sheet borrows the texture: its owner keeps it alive while the sheet shows it, and sets
    // another or clears the sheet before releasing it.
    mtd setPicture(picture: Texture)
    {
        .picture = picture
        .relayout()
    }

    // Appends a fact the reader came for, set large and light, with an optional faint unit.
    mtd addFact(value: string, unit: string? = null)
    {
        .blocks.add(InfoSheetBlock{kind: .Fact, label: unit orelse "", value: value})
        .relayout()
    }

    // Appends a reading: a soft label and its value, in the fixed-width face when it is a measure.
    mtd addReading(label: string, value: string, mono = true)
    {
        .blocks.add(InfoSheetBlock{kind: .Reading, label: label, value: value, mono: mono})
        .relayout()
    }

    // Appends a section label opening the readings that follow.
    mtd addSection(label: string)
    {
        .blocks.add(InfoSheetBlock{kind: .Section, label: label})
        .relayout()
    }

    // Appends a paragraph in the soft ink, wrapped to the width of the sheet.
    mtd addText(text: string)
    {
        .blocks.add(InfoSheetBlock{kind: .Text, label: text})
        .relayout()
    }

    // Appends a link in Arc that posts the command `id` when it is clicked.
    mtd addLink(text: string, id: WndId)
    {
        .blocks.add(InfoSheetBlock{kind: .Link, label: text, id: id})
        .relayout()
    }

    // Sets the one primary action of the sheet, at its foot, and returns its button.
    //
    // A sheet has at most one: calling this again replaces the caption and the command.
    #[Swag.Discardable]
    mtd setAction(caption: string, id: WndId)->*PushButton
    {
        if .action do
            .action.destroy()
        .action = PushButton.create(me, caption, {}, id, .Strong)
        .relayout()
        return .action
    }

    // Removes the title, the identity, every block and the action.
    mtd clear()
    {
        .title.clear()
        .identity.clear()
        .picture = {}
        .blocks.clear()
        if .action
        {
            .action.destroy()
            .action = null
        }

        .hotLink = Swag.U64.Max
        .relayout()
    }

    // Returns every word the sheet shows, one line per piece in reading order: the title, the
    // identity, then each block, a reading as its label over its value.
    //
    // This is what a screen reader or a test reads of the sheet; the picture has no words.
    mtd text()->String
    {
        var result: #returntype
        for piece in [.title.toString(), .identity.toString()] where piece.count
        {
            result += piece
            result += "\n"
        }

        for block in .blocks
        {
            switch block.kind
            {
            case .Fact:
                result += block.value
                if not block.label.isEmpty()
                {
                    result += " "
                    result += block.label
                }
            case .Reading:
                result += block.label
                result += "\n"
                result += block.value
            default:
                result += block.label
            }

            result += "\n"
        }

        if .action
        {
            result += .action.name.raw
            result += "\n"
        }

        return result
    }

    // Returns the height the body needs at `width`, and places every block on the way.
    mtd measureBody(width: f32)->f32
    {
        let metrics = .themeMetrics()
        let theme   = .theme()
        let pad     = metrics.infoSheet_Padding

        var y = pad
        if .picture.isValid() do
            y += .pictureSize(width - 2 * pad).y + metrics.infoSheet_BlockGap
        if not .title.isEmpty() do
            y += theme.createDefaultFont(metrics.infoSheet_TitleFontSize, .Bold).height
        if not .identity.isEmpty() do
            y += metrics.infoSheet_LineGap + theme.createDefaultFontFs(metrics.defaultFontSize - 1).height
        if not .title.isEmpty() or not .identity.isEmpty() do
            y += metrics.infoSheet_BlockGap

        let factHeight = theme.createDefaultFont(metrics.infoSheet_FactFontSize).height
        for &block, index in .blocks
        {
            switch block.kind
            {
            case .Fact:
                block.height = factHeight

            case .Reading, .Link:
                block.height = metrics.infoSheet_LineHeight

            case .Section:
                y += index == 0 ? 0 : metrics.infoSheet_BlockGap * 0.5
                block.height = metrics.inspector_SectionHeight

            case .Text:
                y += index == 0 ? 0 : metrics.infoSheet_BlockGap * 0.5
                var text: RichString
                text.set(block.label)
                text.compute()
                Painter.computeLayout(Math.Rectangle{0, 0, Math.max(width - 2 * pad, 1), MaxTextLayoutExtent}, &text, .paragraphFormat(), .deviceScale())
                block.height = Math.ceil(text.boundRect.height) + metrics.infoSheet_LineGap
            }

            block.top = y
            y         += block.height
        }

        if .action do
            y += metrics.infoSheet_BlockGap + metrics.btnPush_Height
        return Math.ceil(y + pad)
    }

    // Returns the visible sheet: the window holds nothing else, its shadow falls outside it.
    private mtd body()->Math.Rectangle => .clientRect()

    // Returns the size of the picture within `width`, its proportions kept and its height bounded.
    private mtd pictureSize(width: f32)->Math.Point
    {
        let ratio  = cast(f32, .picture.height) / cast(f32, Math.max(.picture.width, 1))
        let height = Math.min(.themeMetrics().infoSheet_PictureHeight, Math.round(width * ratio))
        return {Math.round(height / Math.max(ratio, 0.01)), height}
    }

    private mtd paragraphFormat()->RichStringFormat
    {
        var result: #returntype
        .theme().setTextColors(&result, .themeColors().softText)
        result.font          = .theme().createDefaultFontFamily(.themeMetrics().defaultFontSize)
        result.horzAlignment = .Left
        result.vertAlignment = .Top
        result.flags         = .WordWrap
        return result
    }

    private mtd linkAt(pos: Math.Point)->u64
    {
        let body = .body()
        for block, index in .blocks where block.kind == .Link
        {
            let rect = Math.Rectangle{body.x, body.y + block.top, body.width, block.height}
            if rect.contains(pos) do
                return index
        }

        return Swag.U64.Max
    }

    private mtd relayout()
    {
        if .isLocallyVisible() do
            .itf.onLayout()
        .invalidate()
    }
}
