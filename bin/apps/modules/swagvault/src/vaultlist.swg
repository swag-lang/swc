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
// Without a vault — the first visit, and every visit while privacy mode keeps no list — the page is
// the home of the application: its mark, large and faint, gives the page its centre; a short title
// and two lines say what a vault is, and where the vaults went when privacy mode keeps none; the
// two ways stand under them, a new vault as the one primary action of the screen. Under a hairline,
// a faint foot names what protects a container and recalls that one can be dropped on the window.
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

    card:      UnlockCard
    rows:      Array'*VaultRow
    arranging: bool
    built:     bool     // Whether the parts exist: the scroll window lays its view out as soon as it makes it.

    // The vault whose place in the list is open, or closing back to a row; empty when every row rests.
    openPath:   String
    openHeight: f32     // Height that place takes now.
    openTarget: f32     // Height it is opening or closing to.

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

    // The home: the mark, the title and its two lines, the two ways, then the foot under a hairline.
    const MarkSize         = 64'f32
    const MarkToHeading    = 28'f32
    const HeadingSize      = 22'u32
    const HeadingToWelcome = 10'f32
    const WelcomeToWays    = 28'f32
    const WaysToRule       = 44'f32
    const RuleWidth        = 400'f32
    const RuleToFoot       = 26'f32     // From the hairline to the middle of the first line of the foot.
    const FootLineGap      = 22'f32     // From the middle of one line of the foot to the next.

    // What protects a container, named as its specifications spell it: format identifiers, not prose.
    const CipherNames = "ChaCha20-Poly1305 · Argon2id"

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
        while .rows.count > .window.vaults.count do
            .rows.popBack().destroy()
        while .rows.count < .window.vaults.count do
            .rows.add(VaultRow.create(me, .window))

        .mountedCount = 0
        for vault in .window.vaults where .window.isMounted(vault.path)
        {
            .rows[.mountedCount].setPath(vault.path)
            .mountedCount += 1
        }

        var index = .mountedCount
        for vault in .window.vaults where not .window.isMounted(vault.path)
        {
            .rows[index].setPath(vault.path)
            index += 1
        }

        let chosen = .window.chosenLockedPath()
        for row in .rows
        {
            row.refresh()
            row.show(row.path != chosen)
        }

        // The home says what a vault is; with privacy mode on, it also says why the list is empty.
        let texts   = appStrings()
        let privacy = .window.privacyMode
        .heading.setText(privacy ? texts.ui_HomeTitlePrivacy : texts.ui_HomeTitle)
        .welcome.setText(Format.toString("%\n%", texts.ui_HomeWelcome, privacy ? texts.ui_HomePrivacy : texts.ui_HomeKeeps))

        .card.header.setPath(chosen)
        .card.header.refresh()
        .card.setKeyFiles(.window.unlockKeyFiles.toSlice())
        .unfold(chosen)
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

    // Opens the place of `chosen` to the height of its card, the rows below following it, or closes
    // the open place back to a row when nothing is chosen. A vault chosen while another is open
    // takes the place from the height of its own row.
    mtd unfold(chosen: string)
    {
        if chosen.count != 0 and .openPath != chosen
        {
            .openPath   = chosen
            .openHeight = VaultRow.Height
            .openTarget = VaultRow.Height
        }

        if .openPath.isEmpty() do
            return

        let animator = &.app().animator
        let channel  = AnimationChannel.from(OpenChannel)
        let target   = chosen.count == 0 ? VaultRow.Height : .card.measureHeight(.rowWidth())
        if target == .openTarget and (animator.isActive(me, channel) or target == .openHeight) do
            return

        .openTarget = target

        var options: AnimationOptions
        options.duration = Time.Duration.fromSeconds(.themeMetrics().motion_PanelSeconds)
        options.easing   = .EaseInOut

        func follow(list: *VaultList, height: f32)
        {
            list.openHeight = height
            list.arrange()
        }

        discard animator.animateF32(me, channel, .openHeight, target, &follow, options, func|list = me|(result)
        {
            if result == .Completed and list.window.chosenLockedPath().count == 0 do
                list.openPath.clear()
        })
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

        if .notice.isLocallyVisible()
        {
            y += NoticeGap
            let height = .notice.measureHeight(width)
            .notice.place(Math.Rectangle{x, y, width, height})
            y += height
        }

        y += RowsGap

        // At rest, an open place follows what its card holds at this width, and a place whose vault
        // was folded is a row again.
        let rowW   = .rowWidth()
        let chosen = .window.chosenLockedPath()
        if not .app().animator.isActive(me, AnimationChannel.from(OpenChannel))
        {
            if chosen.count == 0
            {
                .openPath.clear()
            }
            elif .openPath == chosen
            {
                .openHeight = .card.measureHeight(rowW)
                .openTarget = .openHeight
            }
        }

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

            let open = not .openPath.isEmpty() and row.path == .openPath
            if open and row.path == chosen do
                .card.place(Math.Rectangle{rowX, y, rowW, .openHeight})
            else do
                row.arrange(Math.Rectangle{rowX, y, rowW, row.height()})
            y += (open ? .openHeight : row.height()) + RowGap
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
        let footH    = WaysToRule + RuleToFoot + FootLineGap + NoticeLine.Height * 0.5

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
            .notice.place(Math.Rectangle{Math.round(center - noticeW * 0.5), y, noticeW, noticeH})
            y += noticeH
        }

        y += WaysToRule
        let ruleW = Math.min(width, RuleWidth)
        .ruleRect = Math.Rectangle{Math.round(center - ruleW * 0.5), y, ruleW, 1}
        return y + footH - WaysToRule
    }

    // Draws the foot of the home under its hairline: what protects a container, in faint mono, then
    // the reminder that one can be dropped on the window.
    mtd paintHomeFoot(painter: *Painter)
    {
        let colors = .themeColors()
        let center = .ruleRect.horzCenter()
        painter.fillRect(.ruleRect, colors.line)

        func centred(painter: *Painter, center, middle: f32, text: string, font: *Font, color: Color)
        {
            let textW = Painter.measureString(text, font).width
            painter.drawString(Math.round(center - textW * 0.5), font.opticalLineTop(middle), text, font, color)
        }

        let texts = appStrings()
        let mono  = .theme().createDefaultFontFs(12)
        let font  = .theme().createDefaultFont(.themeMetrics().defaultFontSize)
        let first = .ruleRect.y + RuleToFoot
        centred(painter, center, first, Format.toString("% · %", CipherNames, texts.ui_HomeHidden), mono, colors.faintText)
        centred(painter, center, first + FootLineGap, texts.ui_HomeDrop, font, colors.faintText)
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
