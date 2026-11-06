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
// value, section labels, a paragraph, links in Arc, and at most one primary action, which a
// secondary one may follow. A picture of what the sheet describes — a poster, a cover, a
// capture — may head it. When media readings and technical readings would make one long sheet,
// [[Gui.InfoSheet.beginPage]] separates them and a small arrow moves between pages.
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
    subjectFile:      String
    subjectDirectory: bool
    writingPage:      u32
    picturePage:      u32
    actionPage:       u32
    pageTop:          f32
    hotLink:          u64 = Swag.U64.Max
    actionTop:        f32     // Top of the action when it follows the head, from the latest layout.
    contentHeight:    f32     // Body height before the window clips it to the available room.
    scrollOffset:     f32     // Portion of a long body already passed by the reader.
    late closeButton: *IconButton
    late pageButton:  *IconButton
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
    left:   f32        // Indent of the block in the body, beside the picture, from the latest layout.
    top:    f32        // Top of the block in the body, from the latest layout.
    height: f32        // Height of the block, from the latest layout.
    page:   u32        // Page containing this block.
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
        let top       = bounds.y + Math.max(inset, parent.stripInset())
        .contentHeight = .measureBody(width)
        let height    = Math.min(.contentHeight, bounds.bottom() - inset - top)
        .scrollOffset = Math.clamp(.scrollOffset, 0, Math.max(.contentHeight - height, 0))
        let left      = bounds.right() - inset - width
        let closeSize = metrics.embInfo_CloseSize
        let controlInset = metrics.infoSheet_Padding - metrics.embInfo_CloseMargin
        let controlTop   = controlInset - metrics.embInfo_CloseMargin
        let closeX       = width - controlInset - closeSize
        liftFloating(me)
        .setPosition(Math.Rectangle{left, top, width, height})
        .closeButton.setPosition(Math.Rectangle{closeX, controlTop, closeSize, closeSize})
        .pageButton.show(.pages.count > 1)
        if .pages.count > 1
        {
            let next = .pageIndex + 1 < .pages.count ? .pageIndex + 1 : 0
            .pageButton.setPosition(Math.Rectangle{closeX - closeSize - metrics.embInfo_CloseMargin,
                                                    controlTop, closeSize, closeSize})
            .pageButton.setIcon(.theme().icon(next ? .ChevronRight : .ChevronLeft, themeRowIconSize(metrics)))
            .pageButton.toolTip = .pages[next]
        }

        // The primary action takes the foot of the sheet, or follows the head beside a picture;
        // with a secondary one, each takes half.
        let actionVisible = .action != null and .actionPage == .pageIndex
        .action?.show(actionVisible)
        .secondary?.show(actionVisible)
        if actionVisible
        {
            let pad  = metrics.infoSheet_Padding
            let y    = .besidePicture() ? .actionTop - .scrollOffset : height - pad - metrics.btnPush_Height
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
        let accent  = .accentColor()

        paintFloatingGround(me, painter, body, metrics.corner_Floating)

        // A sheet shorter than its blocks keeps its action whole: the blocks stop above it.
        var blocksArea = body
        if .action and .actionPage == .pageIndex and not .besidePicture() do
            blocksArea.height = Math.max(.action.position.y - metrics.infoSheet_BlockGap * 0.5 - body.y, 0)
        painter.pushClippingRect(blocksArea)
        defer painter.popClippingRect()

        let x     = body.x + pad
        let width = body.width - 2 * pad
        let pageHeight = .pages.count > 1 ? metrics.inspector_SectionHeight + metrics.infoSheet_BlockGap * 0.5 : 0
        var y     = body.y + pad + pageHeight - .scrollOffset

        // The picture keeps its proportions, on the corner of a control, at the head of the sheet
        // or at the left of the title.
        var headX = x
        if .picture.isValid() and .picturePage == .pageIndex
        {
            let size = .besidePicture() ? .besideSize() : .pictureSize(width)
            painter.setParams(.Antialiased)
            painter.fillRoundRect(Math.Rectangle{x, y, size.x, size.y}, metrics.corner_Control, metrics.corner_Control, Brush.createTexture(.picture))
            if .besidePicture() do
                headX = x + size.x + metrics.infoSheet_Padding * 0.5
            else do
                y += size.y + metrics.infoSheet_BlockGap
        }

        // Nothing runs past the padding: a line longer than the sheet ends with an ellipsis.
        let right      = x + width
        let controlInset = metrics.infoSheet_Padding - metrics.embInfo_CloseMargin
        let controls = .pages.count > 1 ? metrics.embInfo_CloseSize * 2 + controlInset + metrics.embInfo_CloseMargin :
                                        metrics.embInfo_CloseSize + controlInset
        // Paged sheets put their controls on the page line, above the title.
        let titleRight = .pages.count > 1 ? right : right - controls
        let scale      = .deviceScale()
        let titleFont  = theme.createDefaultFont(metrics.infoSheet_TitleFontSize, .Bold)
        if .pages.isEmpty() and (not .title.isEmpty() or not .identity.isEmpty())
        {
            painter.drawLine(x, y - metrics.infoSheet_LineGap * 2,
                             x + metrics.inspector_SectionHeight, y - metrics.infoSheet_LineGap * 2,
                             Pen.createSolid(accent, 2))
        }
        if not .title.isEmpty()
        {
            painter.drawString(headX, y, Painter.elideString(.title, titleFont, titleRight - headX, scale), titleFont, colors.text)
            y += titleFont.height
        }

        let monoFont = theme.createDefaultFontFs(metrics.defaultFontSize - 1)
        if not .identity.isEmpty()
        {
            painter.drawString(headX, y + metrics.infoSheet_LineGap, Painter.elideString(.identity, monoFont, titleRight - headX, scale), monoFont, colors.faintText)
        }

        if .pages.count > 1
        {
            let pageY = body.y + .pageTop - .scrollOffset
            let mark  = metrics.sectionLabel_FontSize
            painter.drawLine(x, pageY + metrics.inspector_SectionHeight * 0.5 - mark * 0.5,
                             x, pageY + metrics.inspector_SectionHeight * 0.5 + mark * 0.5,
                             Pen.createSolid(accent, 2))
            SectionLabel.paint(me, painter,
                               Math.Rectangle{x + metrics.iconText_Margin, pageY, width - metrics.iconText_Margin, metrics.inspector_SectionHeight},
                               .pages[.pageIndex])
        }

        let bodyFont  = theme.createDefaultFont(metrics.defaultFontSize)
        let valueMono = theme.createDefaultFontFs(metrics.defaultFontSize)
        let factFont  = theme.createDefaultFont(metrics.infoSheet_FactFontSize, .Light)
        for block, index in .blocks where block.page == .pageIndex
        {
            let top     = body.y + block.top - .scrollOffset
            let centerY = top + block.height * 0.5
            switch block.kind
            {
            case .Fact:
                let left = x + block.left
                painter.setAntialiased(true)
                painter.fillRoundRect(Math.Rectangle{left - metrics.infoSheet_LineGap, top,
                                                     right - left + metrics.infoSheet_LineGap, block.height},
                                      metrics.corner_Control, metrics.corner_Control, accent.withAlpha(0x20))
                let used = paintTextLine(painter, left, centerY, block.value, factFont, accent, right - left, scale)
                let unit = left + used + metrics.iconText_Margin * 0.5
                discard paintTextLine(painter, unit, centerY, block.label, monoFont, colors.faintText, right - unit, scale)

            case .Reading:

                // A label longer than its column pushes its value along rather than running into it.
                let used   = paintTextLine(painter, x, centerY, block.label, bodyFont, colors.softText)
                let valueX = Math.max(x + metrics.infoSheet_LabelWidth, Math.ceil(x + used + metrics.iconText_Margin))
                discard paintTextLine(painter, valueX, centerY, block.value, block.mono ? valueMono : bodyFont, colors.text, right - valueX, scale)

            case .Section:
                let mark = metrics.sectionLabel_FontSize * 0.5
                painter.drawLine(x - metrics.iconText_Margin, centerY - mark * 0.5,
                                 x - metrics.iconText_Margin, centerY + mark * 0.5,
                                 Pen.createSolid(accent, 2))
                SectionLabel.paint(me, painter, Math.Rectangle{x, top, width, block.height}, block.label)

            case .Text:
                var text: RichString
                text.set(block.label)
                painter.drawRichString(Math.Rectangle{x, top, width, block.height}, &text, .paragraphFormat())

            case .Link:
                let color = index == .hotLink ? colors.arc : colors.link
                discard paintTextLine(painter, x, centerY, block.label, bodyFont, color, width, scale)
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
    #[Swag.Discardable]
    func create(parent: *Wnd, id: WndId? = null)->*InfoSheet
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

        with result.pageButton = IconButton.create(result,
                                                   theme.icon(.ChevronRight, themeRowIconSize(theme.metrics)),
                                                   Math.Rectangle{0, 0, theme.metrics.embInfo_CloseSize, theme.metrics.embInfo_CloseSize})
        {
            .hide()
            .focusPolicy = .None
            .sigPressed += func|sheet = result|(_)
            {
                sheet.selectPage(cast(u32, (sheet.pageIndex + 1) % sheet.pages.count))
            }
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

    // Uses the theme's file-kind hue for this sheet's marks and prominent facts.
    // An empty file name restores the ordinary information hue.
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

    // Begins a named page; readings added afterward belong to it. A single page shows no arrow.
    // The next-page arrow cycles through the pages without closing the sheet.
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

    // Stands the picture at the left of the title, the title, the identity and the facts that
    // follow them beside it, and the action right under them, as a poster or a cover heads what
    // it describes; or back at the head of the sheet.
    mtd setPictureBeside(beside: bool)
    {
        .beside = beside
        .relayout()
    }

    // Appends a fact the reader came for, set large and light, with an optional faint unit.
    mtd addFact(value: string, unit: string? = null)
    {
        .blocks.add(InfoSheetBlock{kind: .Fact, label: unit orelse "", value: value, page: .writingPage})
        .relayout()
    }

    // Appends a reading: a soft label and its value, in the fixed-width face when it is a measure.
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

    // Appends a paragraph in the soft ink, wrapped to the width of the sheet.
    mtd addText(text: string)
    {
        .blocks.add(InfoSheetBlock{kind: .Text, label: text, page: .writingPage})
        .relayout()
    }

    // Appends a link in Arc that posts the command `id` when it is clicked.
    mtd addLink(text: string, id: WndId)
    {
        .blocks.add(InfoSheetBlock{kind: .Link, label: text, id: id, page: .writingPage})
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
        .scrollOffset = 0
        .relayout()
    }

    // Returns every word on the visible page, one line per piece in reading order: the title,
    // identity, page name, then each block, a reading as its label over its value.
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

        .pageTop = pad
        let pageHeight = .pages.count > 1 ? metrics.inspector_SectionHeight + metrics.infoSheet_BlockGap * 0.5 : 0
        var y      = pad + pageHeight
        let beside = .besidePicture()
        if .picture.isValid() and .picturePage == .pageIndex and not beside do
            y += .pictureSize(width - 2 * pad).y + metrics.infoSheet_BlockGap
        if not .title.isEmpty() do
            y += theme.createDefaultFont(metrics.infoSheet_TitleFontSize, .Bold).height
        if not .identity.isEmpty() do
            y += metrics.infoSheet_LineGap + theme.createDefaultFontFs(metrics.defaultFontSize - 1).height
        if not .title.isEmpty() or not .identity.isEmpty() do
            y += metrics.infoSheet_BlockGap

        let factHeight = theme.createDefaultFont(metrics.infoSheet_FactFontSize, .Light).height
        var first      = 0'u64
        if beside
        {
            // The facts that follow the title stand beside the picture with it, and the action
            // comes right under whichever ends lower.
            let left = .besideSize().x + pad * 0.5
            for &block in .blocks where block.page == .pageIndex
            {
                if block.kind != .Fact do
                    break
                block.left   = left
                block.top    = y
                block.height = factHeight
                y            += factHeight
                first        += 1
            }

            y = Math.max(y, pad + pageHeight + .besideSize().y) + metrics.infoSheet_BlockGap
            if .action and .actionPage == .pageIndex
            {
                .actionTop = y
                y += metrics.btnPush_Height + metrics.infoSheet_BlockGap
            }
        }

        var visibleIndex = 0'u64
        for &block in .blocks where block.page == .pageIndex
        {
            if visibleIndex < first
            {
                visibleIndex += 1
                continue
            }
            block.left = 0
            switch block.kind
            {
            case .Fact:
                block.height = factHeight

            case .Reading, .Link:
                block.height = metrics.infoSheet_LineHeight

            case .Section:
                y += visibleIndex == 0 ? 0 : metrics.infoSheet_BlockGap * 0.5
                block.height = metrics.inspector_SectionHeight

            case .Text:
                y += visibleIndex == 0 ? 0 : metrics.infoSheet_BlockGap * 0.5
                var text: RichString
                text.set(block.label)
                text.compute()
                Painter.computeLayout(Math.Rectangle{0, 0, Math.max(width - 2 * pad, 1), MaxTextLayoutExtent}, &text, .paragraphFormat(), .deviceScale())
                block.height = Math.ceil(text.boundRect.height) + metrics.infoSheet_LineGap
            }

            block.top = y
            y         += block.height
            visibleIndex += 1
        }

        if .action and .actionPage == .pageIndex and not beside do
            y += metrics.infoSheet_BlockGap + metrics.btnPush_Height
        return Math.ceil(y + pad)
    }

    // Returns the visible sheet: the window holds nothing else, its shadow falls outside it.
    private mtd body()->Math.Rectangle => .clientRect()

    // Resolves the kind on every paint so theme changes keep the correct palette role.
    private mtd accentColor()->Color
    {
        if .subjectFile.isEmpty() do
            return .themeColors().info
        let color = .theme().fileGlyph(.subjectFile, .subjectDirectory, 16).color
        return color == .themeColors().text ? .themeColors().info : color
    }

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
        for block, index in .blocks where block.kind == .Link and block.page == .pageIndex
        {
            let rect = Math.Rectangle{body.x, body.y + block.top - .scrollOffset, body.width, block.height}
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
