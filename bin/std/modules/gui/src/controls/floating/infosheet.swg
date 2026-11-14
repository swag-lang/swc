#global public

using Core, Pixel

// The information sheet a key opens: the readings of what the window shows, floating at its
// trailing edge.
//
// This is the sheet of the charter (`I`): the surface ground on the floating corner,
// [[Gui.ThemeMetrics.infoSheet_Width]] wide, [[Gui.ThemeMetrics.floating_Inset]] from the
// trailing and bottom edges of its parent and clear of the window chrome at the top. It holds
// what an information band used to show, and only while the reader asks for it: a title on up to
// two lines, a mono line of identity led by the glyph of the file it describes, the figures the
// reader came for set large and light on one line, at most one primary action right under them,
// which a secondary one may follow, then section labels, readings as a label and a value, tracks,
// a paragraph, a note, links in Arc, and footnotes saying where the readings came from.
//
// The sheet speaks in the neutral inks. Its only hue is the file-kind glyph of its identity line;
// Arc marks a link and the page shown, and Voltage the primary action. Sections are separated by
// air alone. A picture of what the sheet describes — a poster, a cover, a capture — may head it.
// When media readings and technical readings would make one long sheet,
// [[Gui.InfoSheet.beginPage]] separates them, and their names stand as tabs on the top line.
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
//     .addReading("Encoding", "UTF-8", mono: false)
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
            title:     String           // Title of the sheet, set large and bold.
            identity:  String           // Mono line of identity under the title: a path, a format, a date.
            action:    *PushButton?     // The one primary action of the sheet, when it has one.
            secondary: *PushButton?     // The action beside the primary one, when it has one.
            picture:   Texture          // Picture heading the sheet, borrowed from its owner; invalid for none.
            beside:    bool             // Whether the picture stands at the left of the title, as a poster or a cover does.
            pageIndex: u32              // Zero-based page currently shown when the sheet has pages.
        }

        sigCloseRequested: SigArray'func||(*InfoSheet)     // Emitted when the reader presses the sheet's close button.
    }

    blocks:           Array'InfoSheetBlock
    pages:            Array'String
    tabRects:         Array'Math.Rectangle     // Hit area of each page name, from the latest layout.
    titleLines:       Array'String             // The title as it is set, from the latest layout.
    subjectFile:      String
    subjectDirectory: bool
    writingPage:      u32
    picturePage:      u32
    actionPage:       u32
    hotLink:          u64 = Swag.U64.Max
    hotTab:           u64 = Swag.U64.Max
    headTop:          f32     // Top of the picture or the title, from the latest layout.
    actionTop:        f32     // Top of the action, from the latest layout.
    contentHeight:    f32     // Body height before the window clips it to the available room.
    scrollOffset:     f32     // Portion of a long body already passed by the reader.
    late closeButton: *IconButton
}

internal enum InfoSheetBlockKind
{
    Fact
    Reading
    Section
    Text
    Link
    Track
    Note
    Footnote
}

internal struct InfoSheetBlock
{
    kind:      InfoSheetBlockKind
    label:     String     // Label of a reading, unit of a fact, name of a track, words of a section, a paragraph, a note, a link or a footnote.
    value:     String     // Value of a reading or of a fact, measures of a track, link of a footnote.
    number:    String     // Number of a track.
    mono:      bool       // Whether the value is a measure, set in the fixed-width face.
    wrapped:   bool       // Whether the value of a reading runs on several lines, from the latest layout.
    id:        WndId?     // Command a link posts.
    commandId: String     // Owns a dynamically supplied link command for as long as the block exists.
    left:      f32        // Indent of the block in the body, from the latest layout.
    top:       f32        // Top of the block in the body, from the latest layout.
    width:     f32        // Width of a fact, or of the link of a footnote, from the latest layout.
    height:    f32        // Height of the block, from the latest layout.
    valueLeft: f32        // Indent of a reading's value or of a footnote's link, from the latest layout.
    valueTop:  f32        // Offset of a footnote's link below the top of the block, from the latest layout.
    page:      u32        // Page containing this block.
}

impl IWnd for InfoSheet
{
    mtd impl onLayout()
    {
        let parent = .parent
        if not parent do
            return

        let metrics   = .themeMetrics()
        let bounds    = parent.clientRect()
        let inset     = metrics.floating_Inset
        let width     = Math.min(metrics.infoSheet_Width, bounds.width - 2 * inset)
        // The host can reserve a top row while document search is open.
        let top       = bounds.y + Math.max(inset, parent.stripInset()) + .margin.y
        .contentHeight = .measureBody(width)
        let height    = Math.min(.contentHeight, bounds.bottom() - inset - top)
        .scrollOffset = Math.clamp(.scrollOffset, 0, Math.max(.contentHeight - height, 0))
        let left      = bounds.right() - inset - width
        let closeSize = metrics.embInfo_CloseSize
        let closeX    = width - .controlInset() - closeSize
        liftFloating(me)
        .setPosition(Math.Rectangle{left, top, width, height})
        .closeButton.setPosition(Math.Rectangle{closeX, .controlTop(), closeSize, closeSize})

        // The action follows the head, the secondary one sharing its line half and half.
        let actionVisible = .action != null and .actionPage == .pageIndex
        .action?.show(actionVisible)
        .secondary?.show(actionVisible)
        if actionVisible
        {
            let pad  = metrics.infoSheet_Padding
            let y    = .actionTop - .scrollOffset
            let room = width - 2 * pad
            if .secondary
            {
                let gap  = metrics.infoSheet_LineGap * 2
                let half = Math.floor((room - gap) * 0.5)
                .action!.setPosition(Math.Rectangle{pad, y, half, metrics.btnPush_Height})
                .secondary.setPosition(Math.Rectangle{pad + half + gap, y, half, metrics.btnPush_Height})
            }
            else
            {
                .action!.setPosition(Math.Rectangle{pad, y, room, metrics.btnPush_Height})
            }
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
        let scale   = .deviceScale()

        paintFloatingGround(me, painter, body, metrics.corner_Floating)
        painter.pushClippingRect(body)
        defer painter.popClippingRect()

        let x     = body.x + pad
        let width = body.width - 2 * pad
        let right = x + width
        let shift = body.y - .scrollOffset

        // The page shown is the name in the ink of the text, on an Arc underline.
        let tabFont = .tabFont()
        for rect, index in .tabRects
        {
            let shown = index == .pageIndex
            let color = shown or index == .hotTab ? colors.text : colors.softText
            let top   = rect.y + shift
            discard paintTextLine(painter, body.x + rect.x, top + rect.height * 0.5, .pages[index], tabFont, color, rect.width + 1, scale)
            if shown do
                painter.fillRect(body.x + rect.x, top + rect.height - 2, rect.width, 2, colors.arc)
        }

        // The picture keeps its proportions, on the corner of a control, at the head of the sheet
        // or at the left of the title.
        var y     = shift + .headTop
        var headX = x
        if .picture.isValid() and .picturePage == .pageIndex
        {
            let size = .besidePicture() ? .besideSize() : .pictureSize(width)
            painter.setParams(.Antialiased)
            painter.fillRoundRect(Math.Rectangle{x, y, size.x, size.y}, metrics.corner_Control, metrics.corner_Control, Brush.createTexture(.picture))
            if .besidePicture() do
                headX = x + size.x + pad * 0.5
            else do
                y += size.y + metrics.infoSheet_BlockGap
        }

        let titleFont = .titleFont()
        for index in .titleLines.count
        {
            painter.drawString(headX, y, .titleLines[index], titleFont, colors.text)
            y += titleFont.height
        }

        // The identity is led by the glyph of the kind of file the sheet describes, the one hue
        // of the sheet.
        let monoFont = theme.createDefaultFontFs(metrics.defaultFontSize - 1)
        if not .identity.isEmpty()
        {
            let lineTop = y + metrics.infoSheet_LineGap
            let centerY = lineTop + monoFont.height * 0.5
            var textX   = headX
            if not .subjectFile.isEmpty()
            {
                let glyph = theme.fileGlyph(.subjectFile, .subjectDirectory, .identityGlyphSize())
                glyph.paint(painter, headX, Math.round(centerY - glyph.sizeY * 0.5), colors.faintText)
                textX += glyph.sizeX + metrics.infoSheet_LineGap * 1.5
            }

            discard paintTextLine(painter, textX, centerY, .identity, monoFont, colors.faintText, right - textX, scale)
        }

        let bodyFont  = theme.createDefaultFont(metrics.defaultFontSize)
        let valueMono = theme.createDefaultFontFs(metrics.defaultFontSize)
        let factFont  = .factFont()
        for block, index in .blocks where block.page == .pageIndex
        {
            let top     = shift + block.top
            let centerY = top + block.height * 0.5
            switch block.kind
            {
            case .Fact:
                let left = x + block.left
                let used = paintTextLine(painter, left, centerY, block.value, factFont, colors.text, right - left, scale)
                let unit = left + used + metrics.iconText_Margin * 0.5
                discard paintTextLine(painter, unit, centerY, block.label, monoFont, colors.faintText, right - unit, scale)

            case .Reading:
                // A label longer than its column pushes its value along rather than running into it.
                let lineCenter = top + metrics.infoSheet_LineHeight * 0.5
                discard paintTextLine(painter, x, lineCenter, block.label, bodyFont, colors.softText, block.valueLeft, scale)
                let valueX = x + block.valueLeft
                if block.wrapped
                {
                    var text = .plainRich(block.value)
                    let rect = .wrappedValueRect(valueX, top, right - valueX, block.height)
                    painter.drawRichString(rect, &text, .valueFormat(block.mono, colors.text))
                }
                else
                {
                    discard paintTextLine(painter, valueX, lineCenter, block.value, block.mono ? valueMono : bodyFont, colors.text, right - valueX, scale)
                }

            case .Section:
                SectionLabel.paint(me, painter, Math.Rectangle{x, top, width, block.height}, block.label)

            case .Text:
                var text: RichString
                text.set(block.label)
                painter.drawRichString(Math.Rectangle{x, top, width, block.height}, &text, .paragraphFormat(colors.softText))

            case .Link:
                let color = index == .hotLink ? colors.arc : colors.link
                discard paintTextLine(painter, x, centerY, block.label, bodyFont, color, width, scale)

            case .Track:
                let lineCenter = top + metrics.infoSheet_LineHeight * 0.5
                discard paintTextLine(painter, x, lineCenter, block.number, monoFont, colors.faintText, block.valueLeft, scale)
                let nameX = x + block.valueLeft
                discard paintTextLine(painter, nameX, lineCenter, block.label, bodyFont, colors.text, right - nameX, scale)
                if not block.value.isEmpty()
                {
                    let measures = top + metrics.infoSheet_LineHeight + monoFont.height * 0.5 - metrics.infoSheet_LineGap
                    discard paintTextLine(painter, nameX, measures, block.value, monoFont, colors.softText, right - nameX, scale)
                }

            case .Note:
                // A caution dot leads what the sheet could not read.
                let lineCenter = top + metrics.infoSheet_LineHeight * 0.5 - metrics.infoSheet_LineGap * 0.5
                painter.setAntialiased(true)
                painter.fillCircle(x + 3, lineCenter, 3, colors.caution)
                var text: RichString
                text.set(block.label)
                let indent = .noteIndent()
                painter.drawRichString(Math.Rectangle{x + indent, top, width - indent, block.height}, &text, .paragraphFormat(colors.softText))

            case .Footnote:
                let lineHeight = monoFont.height
                discard paintTextLine(painter, x, top + lineHeight * 0.5, block.label, .footFont(), colors.faintText, width, scale)
                if not block.value.isEmpty()
                {
                    let color = index == .hotLink ? colors.arc : colors.link
                    let linkX = x + block.valueLeft
                    discard paintTextLine(painter, linkX, top + block.valueTop + lineHeight * 0.5, block.value, .footFont(), color, right - linkX, scale)
                }
            }
        }

        // A long page shows how much remains below the visible readings.
        if .contentHeight > body.height
        {
            let trackHeight = Math.max(body.height - 2 * pad, 0)
            let thumbHeight = Math.min(trackHeight, Math.max(metrics.scrollBar_BoxMinSize,
                                                             trackHeight * body.height / .contentHeight))
            let thumbTop = body.y + pad + (trackHeight - thumbHeight) * .scrollOffset / (.contentHeight - body.height)
            let thumbWidth = metrics.scrollBar_Size - 2 * metrics.scrollBar_BoxPadding
            painter.fillRoundRect(Math.Rectangle{body.right() - metrics.scrollBar_Size, thumbTop,
                                                 thumbWidth, thumbHeight},
                                  thumbWidth * 0.5, thumbWidth * 0.5, colors.scrollBar_Box)
        }
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let pos = .surfaceToLocal(evt.surfacePos)
        switch evt.kind
        {
        case .Move:
            let hot    = .linkAt(pos)
            let hotTab = .tabAt(pos)
            if hot != .hotLink or hotTab != .hotTab
            {
                .hotLink = hot
                .hotTab  = hotTab
                .invalidate()
            }

        case .Leave:
            .hotLink = Swag.U64.Max
            .hotTab  = Swag.U64.Max
            .invalidate()

        case .Pressed:
            if evt.button != .Left do
                break
            let tab = .tabAt(pos)
            if tab != Swag.U64.Max
            {
                .selectPage(cast(u32, tab))
                break
            }

            let link = .linkAt(pos)
            if link != Swag.U64.Max do
                .postCommandEvent(.blocks[link].id)

        case .Wheel:
            let next = Math.clamp(.scrollOffset - evt.delta.y * .themeMetrics().infoSheet_LineHeight * 3,
                                  0,
                                  Math.max(.contentHeight - .position.height, 0))
            if next != .scrollOffset
            {
                .scrollOffset = next
                .itf.onLayout()
                .invalidate()
            }
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
    //
    // Set `closeButton` to false when a persistent opener toggles the sheet instead.
    #[Swag.Discardable]
    func create(parent: *Wnd, id: WndId? = null, closeButton = true)->*InfoSheet
    {
        with let result = Wnd.create'InfoSheet(parent, null, {}, id)
        {
            .dockStyle       = .Float
            .backgroundStyle = .Transparent
            .wndFlags.add(.Hidden)
        }

        let theme = result.theme()
        with result.closeButton = IconButton.create(result,
                                                    theme.icon(.WndClose, theme.metrics.embInfo_CloseGlyph),
                                                    Math.Rectangle{0, 0, theme.metrics.embInfo_CloseSize, theme.metrics.embInfo_CloseSize})
        {
            .toolTip    = Gui.strings().dlg_Close
            .focusPolicy = .None
            .sigPressed += func|sheet = result|(_)
            {
                sheet.close()
                sheet.sigCloseRequested.call(sheet)
            }
        }

        if not closeButton do
            result.closeButton.hide()

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
    //
    // A title wider than the sheet runs on a second line, and a second line still too long keeps
    // its end, so a file name keeps its extension.
    mtd setTitle(title: string)
    {
        .title = title
        .relayout()
    }

    // Names the file or folder the sheet describes; the glyph of its kind leads the identity line.
    // An empty file name removes the glyph.
    mtd setSubjectFile(fileName: string, directory = false)
    {
        .subjectFile = fileName
        .subjectDirectory = directory
        .invalidate()
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
        .picturePage = .writingPage
        .relayout()
    }

    // Begins a named page; readings added afterward belong to it. A single page shows no tabs.
    // The name of every page stands on the top line of the sheet, and a click shows its page.
    mtd beginPage(name: string)
    {
        .pages.add(name)
        .writingPage = cast(u32, .pages.count - 1)
        .relayout()
    }

    // Shows a page already added to the sheet, keeping its title and identity in place.
    mtd selectPage(index: u32)
    {
        if index >= .pages.count or index == .pageIndex do
            return
        .pageIndex = index
        .scrollOffset = 0
        .relayout()
    }

    // Stands the picture at the left of the title, the title, the identity and the figures beside
    // it, and the action right under them, as a poster or a cover heads what it describes; or back
    // at the head of the sheet.
    mtd setPictureBeside(beside: bool)
    {
        .beside = beside
        .relayout()
    }

    // Appends a figure the reader came for, set large and light, with an optional faint unit.
    //
    // The figures of a page stand on one line under the title, in the order they were added,
    // wherever they were added among the other readings: a viewer adds what its file is about and
    // the window adds the size after it.
    mtd addFact(value: string, unit: string? = null)
    {
        .blocks.add(InfoSheetBlock{kind: .Fact, label: unit orelse "", value: value, page: .writingPage})
        .relayout()
    }

    // Appends a reading: a soft label and its value, in the fixed-width face when it is a measure.
    //
    // A value wider than its column runs on the lines below it.
    mtd addReading(label: string, value: string, mono = true)
    {
        .blocks.add(InfoSheetBlock{kind: .Reading, label: label, value: value, mono: mono, page: .writingPage})
        .relayout()
    }

    // Appends a section label opening the readings that follow.
    mtd addSection(label: string)
    {
        .blocks.add(InfoSheetBlock{kind: .Section, label: label, page: .writingPage})
        .relayout()
    }

    // Appends a track of a section: its faint number, its name, and its measures in mono under it.
    mtd addTrack(number, name: string, measures: string = "")
    {
        .blocks.add(InfoSheetBlock{kind: .Track, number: number, label: name, value: measures, page: .writingPage})
        .relayout()
    }

    // Appends a paragraph in the soft ink, wrapped to the width of the sheet.
    mtd addText(text: string)
    {
        .blocks.add(InfoSheetBlock{kind: .Text, label: text, page: .writingPage})
        .relayout()
    }

    // Appends what the sheet could not read, led by a caution dot, wrapped to its width.
    mtd addNote(text: string)
    {
        .blocks.add(InfoSheetBlock{kind: .Note, label: text, page: .writingPage})
        .relayout()
    }

    // Appends a link in Arc that posts the command `id` when it is clicked.
    mtd addLink(text: string, id: WndId)
    {
        .blocks.add(InfoSheetBlock{kind: .Link, label: text, page: .writingPage})
        .blocks[.blocks.count - 1].commandId = id
        .blocks[.blocks.count - 1].id        = .blocks[.blocks.count - 1].commandId.toString()
        .relayout()
    }

    // Appends a faint footnote, such as where the readings came from, followed by a link in Arc
    // posting the command `id` when `link` is not empty.
    mtd addFootnote(text: string, link: string = "", id: WndId? = null)
    {
        .blocks.add(InfoSheetBlock{kind: .Footnote, label: text, value: link, page: .writingPage})
        if id
        {
            .blocks[.blocks.count - 1].commandId = id
            .blocks[.blocks.count - 1].id        = .blocks[.blocks.count - 1].commandId.toString()
        }
        .relayout()
    }

    // Sets the one primary action of the sheet, under its head, and returns its button.
    //
    // A sheet has at most one: calling this again replaces the caption and the command. A
    // `quiet` action wears the secondary form, for a screen where another primary action already
    // stands in Voltage.
    #[Swag.Discardable]
    mtd setAction(caption: string, id: WndId, quiet = false)->*PushButton
    {
        if .action do
            .action.destroy()
        .action = PushButton.create(me, caption, {}, id, quiet ? .Normal : .Strong)
        .actionPage = .writingPage
        .relayout()
        return .action
    }

    // Sets the action standing beside the primary one, and returns its button.
    //
    // It shows only with a primary action, and calling this again replaces it.
    #[Swag.Discardable]
    mtd setSecondaryAction(caption: string, id: WndId)->*PushButton
    {
        if .secondary do
            .secondary.destroy()
        .secondary = PushButton.create(me, caption, {}, id)
        .relayout()
        return .secondary
    }

    // Removes the title, the identity, every block and the actions.
    mtd clear()
    {
        .title.clear()
        .identity.clear()
        .picture = {}
        .beside  = false
        .blocks.clear()
        .pages.clear()
        .tabRects.clear()
        .subjectFile.clear()
        .subjectDirectory = false
        .pageIndex = 0
        .writingPage = 0
        if .action
        {
            .action.destroy()
            .action = null
        }

        if .secondary
        {
            .secondary.destroy()
            .secondary = null
        }

        .hotLink = Swag.U64.Max
        .hotTab  = Swag.U64.Max
        .scrollOffset = 0
        .relayout()
    }

    // Returns every word on the visible page, one line per piece in reading order: the title,
    // identity, page name, then each block, a reading as its label over its value and a track as
    // its number and name over its measures.
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

        if .pages.count > 1
        {
            result += .pages[.pageIndex]
            result += "\n"
        }

        for block in .blocks where block.page == .pageIndex
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

            case .Track:
                result += block.number
                result += " "
                result += block.label
                if not block.value.isEmpty()
                {
                    result += "\n"
                    result += block.value
                }

            case .Footnote:
                result += block.label
                if not block.value.isEmpty()
                {
                    result += " "
                    result += block.value
                }

            default:
                result += block.label
            }

            result += "\n"
        }

        if .action and .actionPage == .pageIndex
        {
            result += .action.name.raw
            result += "\n"
        }

        if .action and .secondary and .actionPage == .pageIndex
        {
            result += .secondary.name.raw
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
        let inner   = width - 2 * pad
        let scale   = .deviceScale()

        // The names of the pages stand on the line of the close button.
        var y = pad
        .tabRects.clear()
        if .pages.count > 1
        {
            let tabFont = .tabFont()
            var tabX    = pad
            for index in .pages.count
            {
                let tabWidth = Math.ceil(Painter.measureStringSnapped(.pages[index], tabFont, deviceScale: scale))
                .tabRects.add(Math.Rectangle{tabX, .controlTop(), tabWidth, metrics.embInfo_CloseSize})
                tabX += tabWidth + metrics.infoSheet_BlockGap + metrics.infoSheet_LineGap
            }

            y = .controlTop() + metrics.embInfo_CloseSize + metrics.infoSheet_BlockGap * 0.5
        }

        // A picture across the sheet starts under the close button, as the page names do.
        let beside = .besidePicture()
        if .picture.isValid() and .picturePage == .pageIndex and not beside do
            y = Math.max(y, .controlTop() + metrics.embInfo_CloseSize + metrics.infoSheet_BlockGap * 0.5)
        .headTop = y
        if .picture.isValid() and .picturePage == .pageIndex and not beside do
            y += .pictureSize(inner).y + metrics.infoSheet_BlockGap

        // The title, the identity and the figures, beside the picture when it stands beside them.
        let headLeft  = beside ? .besideSize().x + pad * 0.5 : 0
        let headWidth = inner - headLeft
        let titleFont = .titleFont()
        let controls  = .pages.count > 1 or not .closeButton.isLocallyVisible() ? 0 : metrics.embInfo_CloseSize + .controlInset() - pad
        .titleLines = .splitTitle(.title, titleFont, headWidth - controls, scale)
        var headY = y + cast(f32, .titleLines.count) * titleFont.height
        if not .identity.isEmpty() do
            headY += metrics.infoSheet_LineGap + theme.createDefaultFontFs(metrics.defaultFontSize - 1).height

        let factFont   = .factFont()
        let unitFont   = theme.createDefaultFontFs(metrics.defaultFontSize - 1)
        let factHeight = factFont.height
        let factGap    = metrics.infoSheet_BlockGap + metrics.infoSheet_LineGap
        var factX      = 0'f32
        var factTop    = headY + metrics.infoSheet_LineGap * 2
        var hasFacts   = false
        for &block in .blocks where block.page == .pageIndex and block.kind == .Fact
        {
            var factWidth = Painter.measureString(block.value, factFont).width
            if not block.label.isEmpty() do
                factWidth += metrics.iconText_Margin * 0.5 + Painter.measureString(block.label, unitFont).width
            factWidth = Math.ceil(factWidth)
            if factX > 0 and factX + factWidth > headWidth
            {
                factX   = 0
                factTop += factHeight
            }

            block.left   = headLeft + factX
            block.top    = factTop
            block.width  = factWidth
            block.height = factHeight
            factX        += factWidth + factGap
            hasFacts     = true
        }

        if hasFacts do
            headY = factTop + factHeight
        y = beside ? Math.max(headY, .headTop + .besideSize().y) : headY

        // What follows the head is separated from it by a block of air, and nothing ends on one.
        var trailingGap = 0'f32
        if .titleLines.count or not .identity.isEmpty() or hasFacts or beside
        {
            y           += metrics.infoSheet_BlockGap
            trailingGap = metrics.infoSheet_BlockGap
        }

        if .action and .actionPage == .pageIndex
        {
            .actionTop  = y
            y           += metrics.btnPush_Height + metrics.infoSheet_BlockGap
            trailingGap = metrics.infoSheet_BlockGap
        }

        let bodyFont  = theme.createDefaultFont(metrics.defaultFontSize)
        let valueMono = theme.createDefaultFontFs(metrics.defaultFontSize)
        let footFont  = .footFont()
        var first     = true
        var afterText = false

        // The values of a page share one column, wide enough for its longest label, so a long
        // label moves every value with it rather than its own alone.
        var valueLeft = metrics.infoSheet_LabelWidth
        for &block in .blocks where block.page == .pageIndex and block.kind == .Reading do
            valueLeft = Math.max(valueLeft, Math.ceil(Painter.measureString(block.label, bodyFont).width + metrics.iconText_Margin * 2))

        for &block in .blocks where block.page == .pageIndex and block.kind != .Fact
        {
            // Readings that follow a paragraph or a note keep the air a paragraph is given.
            block.left = 0
            if afterText and (block.kind == .Reading or block.kind == .Link or block.kind == .Track) do
                y += metrics.infoSheet_BlockGap * 0.5
            afterText = block.kind == .Text or block.kind == .Note
            switch block.kind
            {
            case .Reading:
                block.valueLeft = valueLeft
                let room       = Math.max(inner - block.valueLeft, 1)
                let valueWidth = Painter.measureString(block.value, block.mono ? valueMono : bodyFont).width
                block.wrapped = valueWidth > room
                block.height  = metrics.infoSheet_LineHeight
                if block.wrapped
                {
                    var text = .plainRich(block.value)
                    text.compute()
                    let rect = .wrappedValueRect(0, 0, room, MaxTextLayoutExtent)
                    Painter.computeLayout(rect, &text, .valueFormat(block.mono, .themeColors().text), scale)
                    block.height = Math.max(block.height, Math.ceil(text.boundRect.height) + metrics.infoSheet_LineGap)
                }

            case .Link:
                block.height = metrics.infoSheet_LineHeight

            case .Section:
                y += first ? 0 : metrics.infoSheet_BlockGap * 0.5
                block.height = metrics.inspector_SectionHeight

            case .Track:
                block.valueLeft = Math.ceil(Painter.measureString("00", valueMono).width + metrics.iconText_Margin)
                block.height    = metrics.infoSheet_LineHeight
                if not block.value.isEmpty() do
                    block.height += theme.createDefaultFontFs(metrics.defaultFontSize - 1).height

            case .Text, .Note:
                y += first ? 0 : metrics.infoSheet_BlockGap * 0.5
                let indent = block.kind == .Note ? .noteIndent() : 0
                var text: RichString
                text.set(block.label)
                text.compute()
                Painter.computeLayout(Math.Rectangle{0, 0, Math.max(inner - indent, 1), MaxTextLayoutExtent}, &text, .paragraphFormat(.themeColors().softText), scale)
                block.height = Math.ceil(text.boundRect.height) + metrics.infoSheet_LineGap

            case .Footnote:
                y += first ? 0 : metrics.infoSheet_BlockGap
                let lineHeight = unitFont.height
                block.valueLeft = 0
                block.valueTop  = 0
                block.width     = 0
                block.height    = lineHeight
                if not block.value.isEmpty()
                {
                    // The link follows its words on their line, or takes the next one.
                    let textWidth = Painter.measureString(block.label, footFont).width
                    let spaceWidth = Painter.measureString(" ", footFont).width
                    block.width = Math.ceil(Painter.measureString(block.value, footFont).width)
                    if block.label.isEmpty()
                    {
                        block.valueLeft = 0
                    }
                    elif textWidth + spaceWidth + block.width <= inner
                    {
                        block.valueLeft = Math.ceil(textWidth + spaceWidth)
                    }
                    else
                    {
                        block.valueTop = lineHeight
                        block.height   += lineHeight
                    }
                }

                block.height += metrics.infoSheet_LineGap

            default:
                break
            }

            block.top   = y
            y           += block.height
            first       = false
            trailingGap = 0
        }

        return Math.ceil(y - trailingGap + pad)
    }

    // Returns the visible sheet: the window holds nothing else, its shadow falls outside it.
    private mtd body()->Math.Rectangle => .clientRect()

    // Returns the top of the close button and of the page names, inside the padding.
    private mtd controlTop()->f32 => .controlInset() - .themeMetrics().embInfo_CloseMargin

    // Returns the air between the close button and the trailing edge.
    private mtd controlInset()->f32 => .themeMetrics().infoSheet_Padding - .themeMetrics().embInfo_CloseMargin

    private mtd titleFont()->*Font => .theme().createDefaultFont(.themeMetrics().infoSheet_TitleFontSize, .Bold)
    private mtd factFont()->*Font => .theme().createDefaultFont(.themeMetrics().infoSheet_FactFontSize, .Light)
    private mtd tabFont()->*Font => .theme().createDefaultFont(.themeMetrics().defaultFontSize, .SemiBold)
    private mtd footFont()->*Font => .theme().createDefaultFont(.themeMetrics().defaultFontSize - 1)
    private mtd identityGlyphSize()->f32 => .themeMetrics().defaultFontSize + 1
    private mtd noteIndent()->f32 => .themeMetrics().iconText_Margin + 6

    // Reports whether the picture stands at the left of the title.
    private mtd besidePicture()->bool => .beside and .picture.isValid() and .picturePage == .pageIndex

    // Returns the size of a picture standing beside the title: as wide as a poster in a sheet,
    // its proportions kept and its height bounded.
    private mtd besideSize()->Math.Point
    {
        const Width = 96.0'f32
        let ratio  = cast(f32, .picture.height) / cast(f32, Math.max(.picture.width, 1))
        let height = Math.min(Math.round(Width * ratio), .themeMetrics().infoSheet_PictureHeight)
        return {Math.round(height / Math.max(ratio, 0.01)), height}
    }

    // Returns the size of the picture within `width`, its proportions kept and its height bounded.
    private mtd pictureSize(width: f32)->Math.Point
    {
        let ratio  = cast(f32, .picture.height) / cast(f32, Math.max(.picture.width, 1))
        let height = Math.min(.themeMetrics().infoSheet_PictureHeight, Math.round(width * ratio))
        return {Math.round(height / Math.max(ratio, 0.01)), height}
    }

    // Splits `title` into the lines it is set on within `room`: one when it fits, else a first line
    // cut at the last separator that fits and a second line that keeps its end when it is still
    // too long, so a file name keeps its extension.
    private mtd splitTitle(title: string, font: *Font, room: f32, scale: f32)->Array'String
    {
        var result: #returntype
        if title.count == 0 do
            return result
        if Painter.measureString(title, font).width <= room
        {
            result.add(title)
            return result
        }

        // The longest prefix that fits, ending at a character boundary, then at a separator when
        // one stands in its second half.
        var cut = 0'u64
        for index in 1 to title.count
        {
            if index < title.count and (title[index] & 0xC0) == 0x80 do
                continue
            if Painter.measureString(title[until index], font).width > room do
                break
            cut = index
        }

        if cut == 0 do
            cut = 1
        let half = cut / 2
        var at   = cut
        while at > half
        {
            let c = title[at - 1]
            if c == ' ' or c == '-' or c == '_' or c == '.' or c == '/'
            {
                cut = at
                break
            }

            at -= 1
        }

        result.add(title[until cut])
        let rest = title[cut to]
        if Painter.measureString(rest, font).width <= room
        {
            result.add(rest)
            return result
        }

        // The end of the name stays: the extension and the characters before it.
        let extension = Path.extension(rest) orelse ""
        var keep      = Math.min(rest.count, extension.count + 6)
        while keep < rest.count and (rest[rest.count - keep] & 0xC0) == 0x80 do
            keep += 1
        let tail = rest[rest.count - keep to]
        var line = Painter.elideString(rest[until rest.count - keep], font, Math.max(room - Painter.measureString(tail, font).width, 0), scale)
        line += tail
        result.add(line)
        return result
    }

    // Returns where the wrapped value of a reading is drawn, its first line on the line of its label.
    private mtd wrappedValueRect(x, top, width, height: f32)->Math.Rectangle
    {
        let lead = (.themeMetrics().infoSheet_LineHeight - .valueLineHeight()) * 0.5
        return Math.Rectangle{x, top + lead, width, height}
    }

    private mtd valueLineHeight()->f32 => .themeMetrics().infoSheet_LineHeight - .themeMetrics().infoSheet_LineGap

    // Returns the text of a value as rich text that shows every character as written.
    private mtd plainRich(value: string)->RichString
    {
        var result: #returntype
        result.set(value)
        return result
    }

    private mtd valueFormat(mono: bool, color: Color)->RichStringFormat
    {
        var result: #returntype
        let size = .themeMetrics().defaultFontSize
        .theme().setTextColors(&result, color)
        result.font          = mono ? .theme().createDefaultFontFamilyFs(size) : .theme().createDefaultFontFamily(size)
        result.horzAlignment = .Left
        result.vertAlignment = .Top
        result.flags         = StringFormatFlags.WordWrap | StringFormatFlags.Ellipsis
        result.minLineHeight = .valueLineHeight()
        return result
    }

    private mtd paragraphFormat(color: Color)->RichStringFormat
    {
        var result: #returntype
        .theme().setTextColors(&result, color)
        result.font          = .theme().createDefaultFontFamily(.themeMetrics().defaultFontSize)
        result.horzAlignment = .Left
        result.vertAlignment = .Top
        result.flags         = .WordWrap
        return result
    }

    // Returns the index of the link under `pos`: a link row, or the link of a footnote.
    mtd linkAt(pos: Math.Point)->u64
    {
        let body = .body()
        let pad  = .themeMetrics().infoSheet_Padding
        for block, index in .blocks where block.page == .pageIndex
        {
            var rect: Math.Rectangle
            switch block.kind
            {
            case .Link:
                rect = Math.Rectangle{body.x, body.y + block.top - .scrollOffset, body.width, block.height}

            case .Footnote:
                if block.value.isEmpty() or not block.id do
                    continue
                let lineHeight = block.height - .themeMetrics().infoSheet_LineGap - block.valueTop
                rect = Math.Rectangle{body.x + pad + block.valueLeft, body.y + block.top + block.valueTop - .scrollOffset,
                                      block.width, lineHeight}

            default:
                continue
            }

            if rect.contains(pos) do
                return index
        }

        return Swag.U64.Max
    }

    // Returns the index of the page name under `pos`.
    private mtd tabAt(pos: Math.Point)->u64
    {
        let body = .body()
        for rect, index in .tabRects
        {
            let hit = Math.Rectangle{body.x + rect.x, body.y + rect.y - .scrollOffset, rect.width, rect.height}
            if hit.contains(pos) do
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
