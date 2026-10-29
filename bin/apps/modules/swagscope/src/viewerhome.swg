#global internal

using Core, Gui, Pixel

// One row of the home: a file read lately.
struct ViewerHomeRow
{
    file:   String
    opened: u64      // Local ticks of the last time it was opened; zero when unknown.
    glyph:  Icon     // Glyph of the viewer the file opens in, the only picture a row carries.
}

// The window without a file: the Scope mark, one line inviting a drop, and under a hairline the
// last files read as quiet rows.
//
// It stays quiet on purpose: no title, no path at rest, no groups. The row under the pointer comes
// up on the raised ground with its folder and a faint `×` that takes it out of the history;
// "Clear…" appears under the list with the pointer and offers the partial clears and, apart, the
// whole one. Everything older is in the lens, under `/`.
struct ViewerHome
{
    using wnd: Wnd

    late window: *ViewerWindow
    message:     String     // Sentence standing in for the invitation, such as why a file did not open.
    rows:        Array'ViewerHomeRow
    hovered:     u64 = Swag.U64.Max
    chosen:      u64 = Swag.U64.Max
    pointerIn:   bool
    clearHot:    bool
    now:         u64     // Local ticks the times are written against; zero for the clock.
}

impl ViewerHome
{
    // The measures of the home, from its picture.
    const ListWidth   = 400.0
    const RowHeight   = 40.0
    const RowInset    = 12.0     // Air between the edge of a row and its glyph.
    const NameLeft    = 36.0     // Start of the name from the edge of the list.
    const MarkSize    = 64.0
    const MarkToLine  = 34.0     // From the foot of the mark to the middle of the invitation.
    const LineToRule  = 48.0
    const RuleToRows  = 16.0
    const RowsToClear = 20.0
    const MaxRows     = 6'u64
    const FontSize    = 14'u32
    const MonoSize    = 11'u32

    func create(parent: *Wnd, window: *ViewerWindow)->*ViewerHome
    {
        with let result = Wnd.create'ViewerHome(parent, "scope.home")
        {
            .dockStyle       = .Center
            .backgroundStyle = .Transparent
            .focusPolicy     = .Click
            .window          = window
        }

        return result
    }

    // Shows `message` in place of the invitation, or the invitation with an empty one.
    mtd setMessage(message: string)
    {
        .message = message
        .invalidate()
    }

    // Takes the last files read from the window's history again.
    mtd refresh()
    {
        .rows.clear()
        let window = .window
        for index in Math.min(window.recent.count, MaxRows)
        {
            let file     = window.recent[index].toString()
            with let row = .rows.emplaceInitAddress()
            {
                .file   = file
                .opened = index < window.recentOpened.count ? window.recentOpened[index] : 0
                .glyph  = me.theme().fileGlyph(file, false, themeRowIconSize(me.themeMetrics()))
            }
        }

        if .hovered >= .rows.count do
            .hovered = Swag.U64.Max
        if .chosen >= .rows.count do
            .chosen = .rows.isEmpty() ? Swag.U64.Max : .rows.count - 1
        .invalidate()
    }

    // Returns the rectangle of the list, the mark above it and the invitation, from the size of the home.
    private mtd layout()->{mark: Math.Rectangle, line: f32, rule: f32, list: Math.Rectangle}
    {
        let client = .clientRect()
        let width  = Math.min(ListWidth, Math.max(client.width - 2 * .themeMetrics().floating_Inset, 0))
        let rows   = cast(f32, .rows.count) * RowHeight
        let height = MarkSize + MarkToLine + LineToRule + (.rows.isEmpty() ? 0 : RuleToRows + rows + RowsToClear + RowHeight)
        let top    = Math.round(Math.max(client.y + 24, client.y + (client.height - height) * 0.42))
        let left   = Math.round(client.horzCenter() - width * 0.5)

        var result: #returntype
        result.mark = {Math.round(client.horzCenter() - MarkSize * 0.5), top, MarkSize, MarkSize}
        result.line = top + MarkSize + MarkToLine
        result.rule = result.line + LineToRule
        result.list = {left, result.rule + RuleToRows, width, rows}
        return result
    }

    // Returns the rectangle of row `index`; its ground stands out of the list by its inset.
    mtd rowRect(index: u64)->Math.Rectangle
    {
        let list = .layout().list
        return {list.x, list.y + cast(f32, index) * RowHeight, list.width, RowHeight}
    }

    private mtd clearRect()->Math.Rectangle
    {
        let list  = .layout().list
        let font  = .theme().createDefaultFont(FontSize - 1)
        let width = Painter.measureString(appStrings().home_Clear, font).width
        return {list.right() - width, list.bottom() + RowsToClear - RowHeight * 0.5 + 6, width, RowHeight * 0.6}
    }

    private mtd removeRect(index: u64)->Math.Rectangle
    {
        let row = .rowRect(index)
        return {row.right() - 20, row.vertCenter() - 10, 20, 20}
    }

    // Writes when a file was opened: the time today, "yesterday", the day within the week, and
    // the date before that.
    func openedText(opened, now: u64)->String
    {
        if not opened do
            return {}
        let when  = Time.Timestamp.fromTicks(opened).toDateTime()
        let today = now / Time.TicksPerDay
        let day   = opened / Time.TicksPerDay
        if day == today do
            return Format.toString("%{02}:%{02}", when.hour, when.minute)
        if day + 1 == today do
            return appStrings().home_Yesterday
        if day + 7 > today
        {
            var names = Tokenize.split(appStrings().home_Weekdays, ' 'u8)
            let index = cast(u64, when.dayOfWeek())
            if index < names.count do
                return names[index]
        }

        return Format.toString("%-%{02}-%{02}", when.year, when.month, when.day)
    }

    // Names the folder of `file` by its last `levels` levels, as a reader recognises it.
    func folderText(file: string, levels = 3'u32)->String
    {
        var result: #returntype
        var path = Path.directoryName(file) orelse ""
        for levels
        {
            let name = Path.fileName(path) orelse ""
            if not name.count do
                break
            result = result.isEmpty() ? String.from(name) : Format.toString("% / %", name, result)
            let parent = Path.directoryName(path) orelse ""
            if parent == path do
                break
            path = parent
        }

        return result
    }

    // Takes row `index` out of the history.
    mtd removeRow(index: u64)
    {
        if index >= .rows.count do
            return
        let file = String.from(.rows[index].file)
        .window.forgetRecent(file)
    }

    // Opens the partial clears and, apart, the whole one.
    mtd showClearMenu()
    {
        const MissingId = "scope.home.clear.missing"
        const OlderId   = "scope.home.clear.older"
        const AllId     = "scope.home.clear.all"

        let texts   = appStrings()
        let missing = .window.missingRecentCount()
        let menu    = MenuCtrl.createPopup(me, owner: me)
        menu.addItem(texts.home_ClearMissing, MissingId, rightName: Format.toString("%", missing), disabled: missing == 0)
        menu.addItem(texts.home_ClearOlder, OlderId, disabled: .window.olderRecentCount() == 0)
        menu.addSeparator()
        menu.addItem(texts.home_ClearAll, AllId).critical = true

        var anchor = .clearRect()
        let point  = .localToSurface(Math.Point{anchor.right(), anchor.bottom() + 4})
        switch menu.doModal(point, .TopRight, autoDestroy: true) orelse ""
        {
        case MissingId: .window.removeMissingRecent()
        case OlderId:   .window.removeOlderRecent()
        case AllId:     .window.confirmClearRecent()
        }
    }

    private mtd rowAt(pos: Math.Point)->u64
    {
        for i in .rows.count where .rowRect(i).contains(pos) do
            return i
        return Swag.U64.Max
    }
}

impl IWnd for ViewerHome
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let theme   = .theme()
        let colors  = .themeColors()
        let metrics = .themeMetrics()
        let place   = .layout()
        let body    = theme.createDefaultFont(FontSize)
        let mono    = theme.createDefaultFontFs(MonoSize)
        let center  = .clientRect().horzCenter()
        painter.setAntialiased(true)

        // The mark gives the page its centre, as faint as a line.
        let mark = .app().appGlyph(MarkSize)
        if mark.isValid() do
            mark.paint(painter, place.mark.x, place.mark.y, colors.strongLine)

        // One line invites a drop or the key; a message that has to be read takes its place.
        if not .message.isEmpty()
        {
            let width = Painter.measureString(.message, body).width
            painter.drawString(Math.round(center - width * 0.5), body.opticalLineTop(place.line), .message, body, colors.softText)
        }
        else
        {
            let strings    = appStrings()
            let openFile   = Input.formatKeyShortcut(.Control, .O)
            let openFolder = Input.formatKeyShortcut(.Control, .E)
            let gap        = 6.0
            let separator  = "  ·  "
            let first      = Painter.measureString(strings.home_Invite, body).width
            let firstKey   = Painter.measureString(openFile, mono).width
            let middle     = Painter.measureString(separator, body).width
            let folder     = Painter.measureString(strings.home_InviteFolder, body).width
            let folderKey  = Painter.measureString(openFolder, mono).width
            let width      = first + gap + firstKey + middle + folder + gap + folderKey
            let left       = Math.round(center - width * 0.5)
            painter.drawString(left, body.opticalLineTop(place.line), strings.home_Invite, body, colors.softText)
            painter.drawString(left + first + gap, mono.opticalLineTop(place.line), openFile, mono, colors.faintText)
            let separatorX = left + first + gap + firstKey
            painter.drawString(separatorX, body.opticalLineTop(place.line), separator, body, colors.faintText)
            let folderX = separatorX + middle
            painter.drawString(folderX, body.opticalLineTop(place.line), strings.home_InviteFolder, body, colors.softText)
            painter.drawString(folderX + folder + gap, mono.opticalLineTop(place.line), openFolder, mono, colors.faintText)
        }

        if .rows.isEmpty() do
            return

        painter.fillRect(Math.Rectangle{place.list.x, place.rule, place.list.width, metrics.separator_HairlineSize}, colors.line)
        for &row, index in .rows
        {
            let rect    = .rowRect(index)
            let centerY = rect.vertCenter()
            let hot     = index == .hovered
            if hot or (index == .chosen and .hasFocus())
            {
                var ground = rect
                ground.x     -= 14
                ground.width += 28
                painter.fillRoundRect(ground, metrics.corner_Control, metrics.corner_Control, hot ? colors.raised : colors.selection)
            }

            // The faint glyph of the kind, and nothing heavier.
            if row.glyph.isValid()
            {
                var glyph = row.glyph
                glyph.sizeX, glyph.sizeY = metrics.menuPopup_IconSize
                glyph.paint(painter, rect.x + RowInset - 1, Math.round(centerY - glyph.sizeY * 0.5), glyph.color.a ? glyph.color : colors.faintText)
            }

            let file  = row.file.toString()
            let name  = Path.fileName(file) orelse file
            let nameX = rect.x + NameLeft
            let used  = Painter.measureString(name, body).width
            var right = rect.right()
            if hot
            {
                let cross = .removeRect(index)
                let x     = theme.icon(.WndClose, 12)
                x.paint(painter, Math.round(cross.horzCenter() - 6), Math.round(cross.vertCenter() - 6), colors.faintText)
                right = cross.x - 8
            }
            else
            {
                let time  = ViewerHome.openedText(row.opened, .now ? .now : Time.Timestamp.now().ticks)
                let width = Painter.measureString(time, mono).width
                painter.drawString(right - width, mono.opticalLineTop(centerY), time, mono, colors.faintText)
                right -= width + 12
            }

            let scale = .deviceScale()
            painter.pushClippingRect(Math.Rectangle{nameX, rect.y, Math.max(right - nameX, 0), rect.height})
            painter.drawString(nameX, body.opticalLineTop(centerY), Painter.elideString(name, body, right - nameX, scale), body, hot ? colors.text : colors.softText)

            // The folder is named only for the row the hand is on.
            if hot
            {
                // A narrow row gives up the farthest folders first; the nearest one is what the
                // reader recognises, and it ends with an ellipsis only when it alone is too long.
                let folderX = nameX + used + 10
                let room    = right - folderX
                var folder  = ViewerHome.folderText(file)
                for levels in [2'u32, 1] where Painter.measureStringSnapped(folder, mono, deviceScale: scale) > room do
                    folder = ViewerHome.folderText(file, levels)
                painter.drawString(folderX, mono.opticalLineTop(centerY), Painter.elideString(folder, mono, room, scale), mono, colors.faintText)
            }

            painter.popClippingRect()
        }

        if .pointerIn
        {
            let clear = .clearRect()
            let font  = theme.createDefaultFont(FontSize - 1)
            painter.drawString(clear.x, font.opticalLineTop(clear.vertCenter()), appStrings().home_Clear, font, .clearHot ? colors.softText : colors.faintText)
        }
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let pos = .surfaceToLocal(evt.surfacePos)
        switch evt.kind
        {
        case .Enter, .Move:
            let row   = .rowAt(pos)
            let clear = not .rows.isEmpty() and .clearRect().contains(pos)
            if row != .hovered or not .pointerIn or clear != .clearHot
            {
                .hovered   = row
                .pointerIn = true
                .clearHot  = clear
                .invalidate()
            }

            evt.accepted = false

        case .Leave:
            .hovered   = Swag.U64.Max
            .pointerIn = false
            .clearHot  = false
            .invalidate()

        case .Pressed where evt.button == .Left:
            .setFocus()
            if not .rows.isEmpty() and .clearRect().contains(pos)
            {
                .showClearMenu()
                return
            }

            let row = .rowAt(pos)
            if row >= .rows.count do
                return
            if .removeRect(row).contains(pos)
            {
                .removeRow(row)
                return
            }

            .chosen = row
            .window.queueFile(String.from(.rows[row].file))

        default:
            evt.accepted = false
        }
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind != .Pressed or evt.modifiers != .None or .rows.isEmpty()
        {
            evt.accepted = false
            return
        }

        switch evt.key
        {
        case .Up:
            .chosen = .chosen == Swag.U64.Max ? 0 : (.chosen ? .chosen - 1 : 0)

        case .Down:
            .chosen = .chosen == Swag.U64.Max ? 0 : Math.min(.chosen + 1, .rows.count - 1)

        case .Return where .chosen < .rows.count:
            .window.queueFile(String.from(.rows[.chosen].file))

        case .Delete where .chosen < .rows.count:
            .removeRow(.chosen)

        default:
            evt.accepted = false
            return
        }

        .invalidate()
    }

    mtd impl onFocusEvent(evt: *FocusEvent)
    {
        .invalidate()
        evt.accepted = false
    }
}
