using Core, Gui, Pixel

// The one line under the title of the list that says what the latest step left behind.
//
// It is text on the ground, not a bar: a dot in the tone of what happened — Arc while work runs,
// critical when it stopped — and the sentence in the soft ink. While work of unknown length runs,
// a spinner takes the place of the dot. When there is nothing to say, the line is not there.
struct NoticeLine
{
    using wnd: Wnd

    late busy: *Spinner

    text: String
    tone: StatusTone
}

impl NoticeLine
{
    const Height   = 24'f32     // Height of the line.
    const MarkSize = 16'f32     // Width of the lane the dot or the spinner stands in.
    const DotSize  = 7'f32      // Diameter of the dot.
    const TextGap  = 8'f32      // Air between that lane and the sentence.

    // Creates an empty line in `parent`.
    func create(parent: *Wnd)->*NoticeLine
    {
        with let result = Wnd.create'NoticeLine(parent, Math.Rectangle{0, 0, 0, Height})
        {
            .backgroundStyle = .Transparent
        }

        with result.busy = Spinner.create(result, Math.Rectangle{0, (Height - MarkSize) * 0.5, MarkSize, MarkSize})
        {
            .hide()
        }

        return result
    }

    // Says `text` in the tone of what it reports.
    mtd set(text: string, tone: StatusTone)
    {
        .text = text
        .tone = tone
        .invalidate()
    }

    // Puts the spinner in the place of the dot while work of unknown length runs.
    mtd setBusy(busy: bool)
    {
        .busy.show(busy)
        .invalidate()
    }
}

impl IWnd for NoticeLine
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let colors  = .themeColors()
        let room    = .clientRect()
        let centerY = room.vertCenter()

        painter.setParams(.Antialiased)
        if not .busy.isLocallyVisible() and .tone != .Idle
        {
            let dot = .tone == .Stopped ? colors.critical : colors.arc
            painter.fillCircle(room.x + MarkSize * 0.5, centerY, DotSize * 0.5, dot)
        }

        let font = .theme().createDefaultFont(.themeMetrics().defaultFontSize)
        painter.drawString(room.x + MarkSize + TextGap, font.opticalLineTop(centerY), .text, font, colors.softText)
    }
}

// The window's first page: the vaults Swag Vault knows, under the page title.
//
// It is the view of a scroll window, so a long list scrolls. Each vault is a row; the chosen locked
// vault unfolds into the card that unlocks it, laid over its row, while the rows below make room
// and the others recede. Two quiet words end the list: a new vault, or one to open from a file.
struct VaultList
{
    using wnd: Wnd

    late
    {
        window:   *MainWindow
        scroll:   *ScrollWnd
        title:    *Label
        notice:   *NoticeLine
        newVault: *IconButton
        openFile: *IconButton
    }

    card:      UnlockCard
    rows:      Array'*VaultRow
    arranging: bool
    built:     bool     // Whether the parts exist: the scroll window lays its view out as soon as it makes it.
}

impl VaultList
{
    const NoticeGap     = 8'f32        // Air between the title and the notice under it.
    const RowsGap       = 40'f32       // Air between the head of the page and the first row.
    const RowGap        = 4'f32        // Air between two rows.
    const LinksGap      = 44'f32       // Air between the last row and the two quiet words.
    const LinksSpacing  = 12'f32       // Air between the two quiet words.
    const BottomRoom    = 72'f32       // Room kept under the words for the hint line.
    const RecedeOpacity = 0.45'f32     // Opacity of the rows behind an unfolded vault.

    // Creates the page in `window`, empty.
    func create(window: *MainWindow)->*VaultList
    {
        with let scroll = Wnd.create'ScrollWnd(window, "vault.list", {})
        {
            .dockStyle = .Center
            .updateFlags(.TransparentBars | .DisableHorizontal)
        }

        with let result = scroll.createView'VaultList()
        {
            .window = window
            .scroll = scroll
        }

        let texts = appStrings()
        result.title  = createPageTitle(result, texts.ui_VaultsTitle)
        result.notice = NoticeLine.create(result)
        result.card   = UnlockCard.create(result, window)

        with result.newVault = createQuietLink(result, texts.ui_NewVault)
        {
            .sigPressed += func|window|(_) { window.showPage(.Create) }
        }

        with result.openFile = createQuietLink(result, texts.ui_OpenFile)
        {
            .sigPressed += func|window|(_) { window.openVaultFile() }
        }

        result.built = true
        return result
    }

    // Says the list again from the vaults the window knows, and unfolds the chosen one.
    //
    // Rows are reused rather than rebuilt, so saying the list again never takes the keyboard off
    // the row it is on.
    mtd refresh()
    {
        while .rows.count > .window.vaults.count do
            .rows.popBack().destroy()
        while .rows.count < .window.vaults.count do
            .rows.add(VaultRow.create(me, .window))

        let chosen = .window.chosenLockedPath()
        for index in .rows.count
        {
            let row = .rows[index]
            row.setPath(.window.vaults[index].path)
            row.refresh()
            row.show(row.path != chosen)
        }

        .card.header.setPath(chosen)
        .card.header.refresh()
        .card.setKeyFileCount(.window.unlockKeyFiles.count)
        .arrange()

        // The card arrives over its row, and the other rows recede behind it.
        if chosen.count == 0 do
            discard .app().animator.leave(.card.panel)
        elif not .card.panel.isLocallyVisible() do
            discard .app().animator.arrive(.card.panel)
        .card.panel.bringToFront()

        let opacity = chosen.count == 0 ? 1'f32 : RecedeOpacity
        for row in .rows where row.isLocallyVisible() and row.presentationOpacity != opacity
        {
            var options: AnimationOptions
            options.duration = Time.Duration.fromSeconds(.themeMetrics().motion_QuickSeconds)
            options.easing   = .EaseOut
            discard .app().animator.animateF32(row, AnimationChannel.from("Vault.Row.Recede"), row.presentationOpacity, opacity, func(wnd, value) { wnd.setPresentationOpacity(value) }, options)
        }

        .invalidate()
    }

    // Says the words the page wrote at construction again, in the language now active.
    mtd retranslate()
    {
        let texts = appStrings()
        .title.setText(texts.ui_VaultsTitle)
        .newVault.setText(texts.ui_NewVault)
        .openFile.setText(texts.ui_OpenFile)
        .card.retranslate(.window.unlockKeyFiles.count)
        .refresh()
    }

    // Lays the page out at the width of the view: the title, the notice, the rows with the card
    // over the chosen one, then the two quiet words; and tells the scroll window how tall it is.
    mtd arrange()
    {
        if .arranging or not .built do
            return
        .arranging = true
        defer .arranging = false

        let room  = .clientRect()
        let width = Math.min(PageColumnWidth, Math.max(0, room.width - 2 * (PageGutter + RowOutset)))
        let x     = Math.round((room.width - width) * 0.5)
        var y     = PageTop

        .title.arrange(Math.Rectangle{x, y, width, .title.position.height})
        y += .title.position.height

        if .notice.isLocallyVisible()
        {
            y += NoticeGap
            .notice.arrange(Math.Rectangle{x, y, width, NoticeLine.Height})
            y += NoticeLine.Height
        }

        y += RowsGap

        // The rows reach past the column on both sides, so their words stand on its edge.
        let chosen = .window.chosenLockedPath()
        let rowX   = x - RowOutset
        let rowW   = width + 2 * RowOutset
        for row in .rows
        {
            if row.path == chosen
            {
                let height = .card.measureHeight(rowW)
                .card.place(Math.Rectangle{rowX, y, rowW, height})
                y += height + RowGap
            }
            else
            {
                row.arrange(Math.Rectangle{rowX, y, rowW, VaultRow.Height})
                y += VaultRow.Height + RowGap
            }
        }

        if not .rows.isEmpty() do
            y += LinksGap - RowGap

        let pad      = .themeMetrics().btnIcon_Padding
        let newSize  = .newVault.measure({}).preferred
        let openSize = .openFile.measure({}).preferred
        .newVault.arrange(Math.Rectangle{x - pad, y, newSize.x, newSize.y})
        .openFile.arrange(Math.Rectangle{.newVault.position.right() + LinksSpacing, y, openSize.x, openSize.y})
        y += newSize.y + BottomRoom

        .scroll.setScrollSize(0, y)
    }

    // Returns the row showing the vault at `path`, or null.
    mtd rowOf(path: string)->*VaultRow?
    {
        for row in .rows where row.path == path do
            return row
        return null
    }
}

impl IWnd for VaultList
{
    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        .arrange()
    }

    // A press on the ground of the page folds the unfolded vault, as Escape does.
    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if evt.kind == .Pressed and evt.button == .Left
        {
            .window.foldVault()
            return
        }

        evt.accepted = false
    }
}
