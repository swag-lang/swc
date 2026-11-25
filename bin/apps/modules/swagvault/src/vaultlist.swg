using Core, Gui, Pixel

// The notice under the title of the list that says what the latest step left behind.
//
// It is text on the ground, not a bar: a dot in the tone of what happened — Arc while work runs,
// critical when it stopped — and the sentence in the soft ink. While work of unknown length runs,
// a spinner takes the place of the dot. When there is nothing to say, the line is not there.
struct NoticeLine
{
    using wnd: Wnd

    late busy:    *Spinner
    late heading: *Label
    late detail:  *Label
    tone: StatusTone
}

impl NoticeLine
{
    const Height   = 24'f32     // Minimum height of the first line.
    const MarkSize = 16'f32     // Width of the lane the dot or the spinner stands in.
    const DotSize  = 7'f32      // Diameter of the dot.
    const TextGap  = 8'f32      // Air between that lane and the sentence.
    const TextLeft = MarkSize + TextGap

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

        let flags = LabelFlags.WordWrap | .AutoHeight | .Ellipsis | .SecondaryText
        result.heading = Label.create(result, "", flags: flags)
        result.heading.setTextAlignment(.Left, .OpticalCenter)
        result.detail = Label.create(result, "", flags: flags)
        result.detail.setTextAlignment(.Left, .Top)
        result.detail.hide()

        return result
    }

    // Places the explanation below the summary when there is one.
    mtd set(heading, detail: string, tone: StatusTone)
    {
        .heading.setText(heading)
        .heading.updateFlags(tone == .Stopped ? .None : .SecondaryText,
                             remove: tone == .Stopped ? .SecondaryText : .None)
        .detail.setText(detail)
        .detail.show(detail.count != 0)
        .tone = tone
        .invalidate()
    }

    // Puts the spinner in the place of the dot while work of unknown length runs.
    mtd setBusy(busy: bool)
    {
        .busy.show(busy)
        .invalidate()
    }

    // Returns the natural width before wrapping.
    mtd measureWidth()->f32
    {
        return TextLeft + Math.max(.heading.measure({}).preferred.x, .detail.measure({}).preferred.x)
    }

    mtd headingHeight(textWidth: f32)->f32
        => Math.max(Height, Math.ceil(.heading.measure({textWidth, 0}).preferred.y))

    mtd measureHeight(width: f32)->f32
    {
        let textWidth = Math.max(1, width - TextLeft)
        let detailH   = .detail.isLocallyVisible() ? Math.ceil(.detail.measure({textWidth, 0}).preferred.y) : 0
        return .headingHeight(textWidth) + detailH
    }

    mtd place(rect: Math.Rectangle)
    {
        .arrange(rect)
        let textWidth = Math.max(1, rect.width - TextLeft)
        let headingH  = .headingHeight(textWidth)
        .heading.arrange({TextLeft, 0, textWidth, headingH})
        .detail.arrange({TextLeft, headingH, textWidth, Math.max(0, rect.height - headingH)})
    }
}

impl IWnd for NoticeLine
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let colors  = .themeColors()
        let room    = .clientRect()
        let centerY = room.y + Height * 0.5

        painter.setParams(.Antialiased)
        if not .busy.isLocallyVisible() and .tone != .Idle
        {
            let dot = .tone == .Stopped ? colors.critical : colors.arc
            painter.fillCircle(room.x + MarkSize * 0.5, centerY, DotSize * 0.5, dot)
        }
    }
}

// The window's first page: the vaults Swag Vault knows, under the page title.
//
// It is the view of a scroll window, so a long list scrolls. The two ways to another vault, a new
// one or one to open from a file, stand at the end of the title's line. The vaults follow in two
// groups, each under its section label and its count: the mounted ones first, on their own ground,
// then the locked ones. The chosen locked vault unfolds into the card that unlocks it, laid over its
// row: the card opens its height while the rows below follow it, and the others recede.
//
// An empty list shows the home of the application. The mark, a short title and two lines
// introduce vaults. The ways to create or open one follow, with a hint for dropping a file.
struct VaultList
{
    using wnd: Wnd

    late
    {
        window:   *MainWindow
        scroll:   *ScrollWnd
        title:    *Label
        options:  *IconButton
        notice:   *NoticeLine
        heading:  *Label
        welcome:  *Label
        newVault: *PushButton
        openFile: *PushButton
    }

    card:         UnlockCard
    rows:         Array'*VaultRow
    unfolding:    AnimationHandle
    noticeExtent: f32
    noticeTarget: f32
    arranging:    bool
    built:        bool     // Whether the parts exist: the scroll window lays its view out as soon as it makes it.

    // Where the arrangement put what the page paints itself: the section label of each group, empty
    // when the group is; and the mark and the hairline of the home's foot, empty while the list has
    // vaults.
    mountedHead:  Math.Rectangle
    lockedHead:   Math.Rectangle
    mountedCount: u64
    markRect:     Math.Rectangle
    ruleRect:     Math.Rectangle
}

impl VaultList
{
    const NoticeGap     = 8'f32        // Air between the title and the notice under it.
    const ActionsGap    = 8'f32        // Air between the two ways to another vault.
    const RowsGap       = 36'f32       // Air between the head of the page and the first group.
    const HeadHeight    = 20'f32       // Height of the line a group's section label stands on.
    const HeadGap       = 8'f32        // Air between a section label and the first row of its group.
    const GroupGap      = 28'f32       // Air between the last row of a group and the next label.
    const CountGap      = 8'f32        // Air between a section label and its count.
    const RowGap        = 4'f32        // Air between two rows.
    const BottomRoom    = 72'f32       // Room kept under the page for the hint line.
    const RecedeOpacity = 0.45'f32     // Opacity of the rows behind an unfolded vault.
    const OpenChannel   = "Vault.Card.Height"
    const RecedeChannel = "Vault.Row.Recede"
    const NoticeChannel = "Vault.Notice.Height"

    // The home: the mark, the title and its two lines, the two ways, then the foot under a hairline.
    const MarkSize         = 64'f32
    const MarkToHeading    = 28'f32
    const HeadingSize      = 22'u32
    const HeadingToWelcome = 10'f32
    const WelcomeToWays    = 28'f32
    const WaysToRule       = 44'f32
    const RuleWidth        = 400'f32
    const RuleToFoot       = 26'f32     // From the hairline to the middle of the drop hint.

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
        result.title = createPageTitle(result, texts.ui_VaultsTitle)
        with result.options = createQuietLink(result, texts.ui_OptionsLink)
        {
            .sigPressed += func|window|(_) { window.showPage(.Options) }
        }

        result.notice = NoticeLine.create(result)
        result.notice.hide()
        result.card   = UnlockCard.create(result, window)

        let headingFont = result.theme().createDefaultFont(HeadingSize, .Bold)
        with result.heading = Label.create(result, "", {0, 0, 0, headingFont.height})
        {
            .setTextAlignment(.Center, .Top)
            .style.setFont(headingFont, .Regular)
        }

        with result.welcome = Label.create(result, "", {}, null, .WordWrap | .SecondaryText | .AutoHeight)
        {
            .setTextAlignment(.Center, .Top)
        }

        // A new vault and an existing file are two buttons with their glyphs: the frequent first
        // task of the window needs no hidden key. Their forms follow the page, in `arrange`.
        let iconSize = themeRowIconSize(result.themeMetrics())
        with result.newVault = PushButton.create(result, texts.ui_NewVault)
        {
            .setIcon(.theme().icon(.Plus, iconSize))
            .sigPressed += func|window|(_) { window.showPage(.Create) }
        }

        with result.openFile = PushButton.create(result, texts.ui_OpenFile, form: .Flat)
        {
            .setIcon(.theme().icon(.OpenFile, iconSize))
            .sigPressed += func|window|(_) { window.openVaultFile() }
        }

        result.built = true
        return result
    }

    // Says the list again from the vaults the window knows, and unfolds the chosen one.
    //
    // Rows are reused rather than rebuilt, so saying the list again never takes the keyboard off
    // the row it is on. They take the vaults mounted ones first, each group in the order of the
    // list, which is also the order of the keyboard.
    mtd refresh()
    {
        var previous = #move .rows
        for vault in .window.vaults where .window.isMounted(vault.path) do
            .rows.add(.takeRow(&previous, vault.path))
        .mountedCount = .rows.count
        for vault in .window.vaults where not .window.isMounted(vault.path) do
            .rows.add(.takeRow(&previous, vault.path))
        for removed in previous do
            removed.destroy()

        let chosen = .window.chosenLockedPath()
        // The rows and the overlay form the last block of children, in keyboard order.
        .card.panel.bringToFront()
        let firstRow = .children.count - .rows.count - 1
        for row, index in .rows
        {
            let childIndex = firstRow + index
            if .children[childIndex] != row
            {
                row.bringToFront()
                .moveLastChildrenTo(childIndex, 1)
            }

            row.refresh()
            row.show(row.path != chosen)
        }

        let texts = appStrings()
        .heading.setText(texts.ui_HomeTitle)
        .welcome.setText(Format.toString("%\n%", texts.ui_HomeWelcome, texts.ui_HomeKeeps))

        .card.header.setPath(chosen)
        .card.header.refresh()
        let keyFiles = .window.unlockKeyFiles.toSlice()
        if not .card.keyFileList.samePaths(keyFiles) do
            .card.setKeyFiles(keyFiles)
        .unfold(chosen)
        .arrange()

        // The card arrives over its row, and the other rows recede behind it.
        if chosen.count == 0 do
            discard .app().animator.leave(.card.panel)
        elif not .card.panel.isLocallyVisible() do
            discard .app().animator.arrive(.card.panel)
        .card.panel.bringToFront()

        let opacity = chosen.count == 0 ? 1'f32 : RecedeOpacity
        let channel = AnimationChannel.from(RecedeChannel)
        let animator = &.app().animator
        for row in .rows
        {
            if not row.isLocallyVisible()
            {
                row.opacityTarget = opacity
                row.setPresentationOpacity(opacity)
                continue
            }

            if row.opacityTarget == opacity and (row.presentationOpacity == opacity or animator.isActive(row, channel)) do
                continue

            row.opacityTarget = opacity
            var options: AnimationOptions
            options.duration = Time.Duration.fromSeconds(.themeMetrics().motion_QuickSeconds)
            options.easing   = .EaseOut
            discard animator.animateF32(row, channel, row.presentationOpacity, opacity, func(wnd, value) { wnd.setPresentationOpacity(value) }, options)
        }

        .invalidate()
    }

    private mtd takeRow(previous: *Array'(*VaultRow), path: string)->*VaultRow
    {
        for old, index in previous[] where old.path == path
        {
            let row = old
            previous.removeAtOrdered(index)
            return row
        }

        let row = VaultRow.create(me, .window)
        row.setPath(path)
        return row
    }

    // Closes the old slot and opens the new one from their current on-screen heights.
    mtd unfold(chosen: string)
    {
        let extra = chosen.count == 0 ? 0 : Math.max(0, .card.measureHeight(.rowWidth()) - VaultRow.Height)
        var changed = false
        for row in .rows
        {
            let target = row.path == chosen ? extra : 0
            changed = changed or row.expansionTarget != target
            row.expansionTarget = target
        }

        if not changed do
            return

        // Both slots use one clock owned by the list. The row under the card is hidden.
        let animator = &.app().animator
        animator.cancel(.unfolding)
        for row in .rows do
            row.expansionFrom = row.expansion

        var options: AnimationOptions
        options.duration = Time.Duration.fromSeconds(.themeMetrics().motion_PanelSeconds)
        options.easing   = .EaseInOut
        .unfolding = animator.animateF32(me, AnimationChannel.from(OpenChannel), 0, 1, func(list, amount)
        {
            for row in list.rows do
                row.expansion = Math.lerp(row.expansionFrom, row.expansionTarget, amount)
            list.arrange()
        }, options)
    }

    // Opens space under the title as a notice appears, and gives it back when it clears.
    mtd showNotice(visible: bool)
    {
        let target = visible ? NoticeGap + .notice.measureHeight(.rowWidth() - 2 * RowOutset) : 0
        let changed = target != .noticeTarget
        .noticeTarget = target
        .notice.show(visible)
        if .rows.isEmpty() or not .isVisible()
        {
            .noticeExtent = target
            .arrange()
            return
        }

        if not changed
        {
            .arrange()
            return
        }

        var options: AnimationOptions
        options.duration = Time.Duration.fromSeconds(.themeMetrics().motion_PanelSeconds)
        options.easing   = .EaseInOut
        discard .app().animator.animateF32(me, AnimationChannel.from(NoticeChannel), .noticeExtent, target, func(list, extent)
        {
            list.noticeExtent = extent
            list.arrange()
        }, options)
    }

    // Returns the width of a row: the column, and the outset its ground reaches past it on each side.
    mtd rowWidth()->f32 => Math.min(PageColumnWidth, Math.max(0, .scroll.clientRect().width - 2 * (PageGutter + RowOutset))) + 2 * RowOutset

    // Says the words the page wrote at construction again, in the language now active.
    mtd retranslate()
    {
        let texts = appStrings()
        .title.setText(texts.ui_VaultsTitle)
        .options.setQuietText(texts.ui_OptionsLink)
        .newVault.setText(texts.ui_NewVault)
        .openFile.setText(texts.ui_OpenFile)
        .card.retranslate(.window.unlockKeyFiles.count)
        .refresh()
    }

    // Lays the page out at the width of the view, as the list or as the home, and tells the scroll
    // window how tall it is.
    mtd arrange()
    {
        if .arranging or not .built do
            return
        .arranging = true
        defer .arranging = false

        let width = .rowWidth() - 2 * RowOutset
        let x     = Math.round((.scroll.clientRect().width - width) * 0.5)
        let home  = .rows.isEmpty()
        .title.show(not home)
        .heading.show(home)
        .welcome.show(home)

        // The navigation column stays centred in the window when the list gains a scrollbar.
        let navigation  = pageColumnBounds(.window.clientRect().width)
        let optionsSize = .options.measure({}).preferred
        .options.arrange(Math.Rectangle{navigation.right() - optionsSize.x - .options.margin.x,
                                        navigation.y, optionsSize.x, optionsSize.y})

        let bottom = home ? .arrangeHome(x, width) : .arrangeList(x, width)
        .scroll.setScrollSize(0, bottom + BottomRoom)
    }

    // Lays out the list: the title with the two ways at the end of its line, the notice, then each
    // group under its label, with the card over the chosen row. Returns the foot of what it placed.
    mtd arrangeList(x, width: f32)->f32
    {
        .markRect = {}
        .ruleRect = {}
        var y = Math.max(ListTop + .stripInset(), .options.position.bottom() + PageNavGap)
        .title.arrange(Math.Rectangle{x, y, width, .title.position.height})

        // Vault actions stay on the far edge of the title line.
        .newVault.setForm(.Normal)
        .openFile.setForm(.Flat)
        let newSize  = .newVault.measure({}).preferred
        let openSize = .openFile.measure({}).preferred
        let waysY    = Math.round(.title.position.vertCenter() - newSize.y * 0.5)
        .newVault.arrange(Math.Rectangle{x + width - newSize.x, waysY, newSize.x, newSize.y})
        .openFile.arrange(Math.Rectangle{.newVault.position.x - ActionsGap - openSize.x, waysY, openSize.x, openSize.y})
        y += .title.position.height

        if .noticeExtent == .noticeTarget
        {
            .noticeExtent = .notice.isLocallyVisible() ? NoticeGap + .notice.measureHeight(width) : 0
            .noticeTarget = .noticeExtent
        }
        if .notice.isLocallyVisible()
        {
            let height = Math.min(.notice.measureHeight(width), .noticeExtent + RowsGap - NoticeGap)
            .notice.setPresentationOpacity(Math.saturate(.noticeExtent / (NoticeGap + NoticeLine.Height)))
            .notice.place(Math.Rectangle{x, y + NoticeGap, width, height})
        }

        y += .noticeExtent + RowsGap

        let rowW = .rowWidth()
        let chosen = .window.chosenLockedPath()
        let channel = AnimationChannel.from(OpenChannel)

        // The rows reach past the column on both sides, so their words stand on its edge. A group
        // opens with its label; the open place holds the card while its vault is chosen, and its
        // row while it closes.
        .mountedHead = {}
        .lockedHead  = {}
        let rowX = x - RowOutset
        for row, index in .rows
        {
            if index == 0 and .mountedCount
            {
                .mountedHead = Math.Rectangle{x, y, width, HeadHeight}
                y += HeadHeight + HeadGap
            }

            if index == .mountedCount
            {
                if index do
                    y += GroupGap - RowGap
                .lockedHead = Math.Rectangle{x, y, width, HeadHeight}
                y += HeadHeight + HeadGap
            }

            let height = row.height()
            row.arrange(Math.Rectangle{rowX, y, rowW, height})
            if row.path == chosen
            {
                if row.expansionTarget > 0 and row.expansion == row.expansionTarget and not .app().animator.isActive(me, channel)
                {
                    row.expansion = Math.max(0, .card.measureHeight(rowW) - height)
                    row.expansionTarget = row.expansion
                }

                .card.place(Math.Rectangle{rowX, y, rowW, height + row.expansion})
            }
            y += height + row.expansion + RowGap
        }

        return y - RowGap
    }

    // Lays out the home: the mark, the title and its lines, the two ways and the notice under them,
    // then the hairline of the foot, centred together in the room the hint line leaves. Returns the
    // foot of what it placed.
    mtd arrangeHome(x, width: f32)->f32
    {
        .mountedHead = {}
        .lockedHead  = {}

        // Alone on the page, a new vault is the primary action; opening a file stays beside it.
        .newVault.setForm(.Strong)
        .openFile.setForm(.Normal)
        let newSize  = .newVault.measure({}).preferred
        let openSize = .openFile.measure({}).preferred
        let headingH = .heading.position.height
        let welcomeH = Math.ceil(.welcome.measure(Math.Point{width, 0}).preferred.y)
        let noticeW  = .notice.isLocallyVisible() ? Math.min(width, Math.ceil(.notice.measureWidth())) : 0
        let noticeH  = noticeW > 0 ? .notice.measureHeight(noticeW) : 0
        let footH    = WaysToRule + RuleToFoot + NoticeLine.Height * 0.5

        let height = MarkSize + MarkToHeading + headingH + HeadingToWelcome + welcomeH + WelcomeToWays + newSize.y +
                     (noticeH > 0 ? NoticeGap + noticeH : 0) + footH
        let room   = .scroll.clientRect()
        let center = Math.round(room.width * 0.5)
        var y      = Math.max(ListTop + .stripInset(), Math.round((room.height - PageFoot - height) * 0.5))

        .markRect = Math.Rectangle{center - MarkSize * 0.5, y, MarkSize, MarkSize}
        y         += MarkSize + MarkToHeading

        .heading.arrange(Math.Rectangle{x, y, width, headingH})
        y += headingH + HeadingToWelcome

        .welcome.arrange(Math.Rectangle{x, y, width, welcomeH})
        y += welcomeH + WelcomeToWays

        let waysX = Math.round(center - (newSize.x + ActionsGap + openSize.x) * 0.5)
        .newVault.arrange(Math.Rectangle{waysX, y, newSize.x, newSize.y})
        .openFile.arrange(Math.Rectangle{.newVault.position.right() + ActionsGap, y, openSize.x, openSize.y})
        y += newSize.y

        if noticeH > 0
        {
            y += NoticeGap
            .notice.setPresentationOpacity(1)
            .notice.place(Math.Rectangle{Math.round(center - noticeW * 0.5), y, noticeW, noticeH})
            y += noticeH
        }

        y += WaysToRule
        let ruleW = Math.min(width, RuleWidth)
        .ruleRect = Math.Rectangle{Math.round(center - ruleW * 0.5), y, ruleW, 1}
        return y + footH - WaysToRule
    }

    // Draws the hint below the hairline on the home page.
    mtd paintHomeFoot(painter: *Painter)
    {
        let colors = .themeColors()
        painter.fillRect(.ruleRect, colors.line)

        let text  = appStrings().ui_HomeDrop
        let font  = .theme().createDefaultFont(.themeMetrics().defaultFontSize)
        let width = Painter.measureString(text, font).width
        let x     = Math.round(.ruleRect.horzCenter() - width * 0.5)
        let y     = font.opticalLineTop(.ruleRect.y + RuleToFoot)
        painter.drawString(x, y, text, font, colors.faintText)
    }

    // Draws the section label of a group in `rect`, and its count after it in faint mono. An empty
    // `rect` is a group with no vault, which says nothing.
    mtd paintGroupHead(painter: *Painter, rect: Math.Rectangle, label: string, count: u64)
    {
        if rect.width <= 0 do
            return

        let labelW = SectionLabel.paint(me, painter, rect, label)
        let mono   = .theme().createDefaultFontFs(.themeMetrics().sectionLabel_FontSize)
        let words  = Format.toString("%", count)
        painter.drawString(rect.x + labelW + CountGap, mono.opticalLineTop(rect.vertCenter()), words, mono, .themeColors().faintText)
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

    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        painter.setParams(.Antialiased)

        // The mark gives the home its centre, as faint as a line.
        if .markRect.width > 0
        {
            let mark = .app().appGlyph(MarkSize)
            if mark.isValid() do
                mark.paint(painter, .markRect.x, .markRect.y, .themeColors().strongLine)
            .paintHomeFoot(painter)
            return
        }

        let texts = appStrings()
        .paintGroupHead(painter, .mountedHead, texts.ui_SectionMounted, .mountedCount)
        .paintGroupHead(painter, .lockedHead, texts.ui_SectionLocked, .rows.count - .mountedCount)
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
