using Core, Gui, Pixel

// One option of the privacy page: a title, a paragraph saying what it costs, and its switch.
//
// The switch stands at the end of the title's line, so the row reads as a sentence and its answer.
// What the option needs besides — the delay of the inactivity option — is a quiet word inside its
// paragraph, standing where the `%` of the sentence puts it.
struct OptionRow
{
    using wnd: Wnd

    late
    {
        title:  *Label
        help:   *Label
        toggle: *ToggleButton
    }

    helpText:   String         // The paragraph as the string table writes it, `%` standing for the choice.
    choice:     *Wnd?          // Quiet word inside the paragraph, when the option needs one.
    choiceTail: String         // Words of the paragraph after the choice, such as its closing period.
    tailPos:    Math.Point     // Where those words start, in the row: the end of the choice, on its line.
}

impl OptionRow
{
    const TitleHeight = 24'f32     // Height of the title's line, which the switch is centred on.
    const HelpGap     = 4'f32      // Air between the title and its paragraph.
    const ToggleGap   = 32'f32     // Least air between the words and the switch.

    // Creates the row of the option `title` in `parent`.
    func create(parent: *Wnd, title, help: string)->*OptionRow
    {
        with let result = Wnd.create'OptionRow(parent)
        {
            .backgroundStyle = .Transparent
        }

        with result.title = Label.create(result, title, Math.Rectangle{0, 0, 0, TitleHeight})
        {
            .setTextAlignment(.Left, .OpticalCenter)
            .style.setFont(result.theme().createDefaultFont(15, .Bold), .Regular)
        }

        with result.help = Label.create(result, help, {}, null, .WordWrap | .SecondaryText)
        {
            .preferredSize.y = 0     // The paragraph is as tall as its words at the width it is given.
            .setTextAlignment(.Left, .Top)
        }

        result.toggle   = ToggleButton.create(result)
        result.helpText = help
        return result
    }

    // Says the option again in the language now active.
    mtd setTexts(title, help: string)
    {
        .title.setText(title)
        .helpText = help
        .applyHelp()
    }

    // Sets `choice` inside the paragraph, where its `%` stands.
    mtd setChoice(choice: *Wnd)
    {
        .choice = choice
        .applyHelp()
    }

    // Writes the paragraph: whole, or up to the choice, keeping what follows it for the row to
    // write after the choice.
    private mtd applyHelp()
    {
        let mark = .choice ? Utf8.indexOf(.helpText.toSlice(), "%") : Swag.U64.Max
        if mark == Swag.U64.Max
        {
            .help.setText(.helpText)
            .choiceTail.clear()
            return
        }

        .help.setText(Latin1.trim(.helpText[until mark]))
        .choiceTail = .helpText[mark + 1 to]
    }

    // Lays the paragraph out at `width` and returns where the choice stands in it: after its last
    // word on the same line, or at the start of the next one when the line cannot hold it and the
    // words that follow it. The words of the choice line up with the words of the paragraph.
    private mtd choiceRect(width: f32)->Math.Rectangle
    {
        let chooser = unwrap .choice
        let size    = chooser.measure({}).preferred
        let inset   = chooser.padding.x
        let font    = unwrap .help.font().regular
        let tail    = Painter.measureString(.choiceTail, font).width - chooser.padding.z

        discard .help.measure(Math.Point{width, 0})
        var lineEnd, lineTop: f32
        var lineHeight = font.height
        for &chunk in .help.name.chunks where chunk.visible and not chunk.isEol
        {
            lineEnd    = chunk.pos.x + chunk.boundRect.width
            lineTop    = chunk.pos.y
            lineHeight = chunk.boundRect.height
        }

        var x = lineEnd + Painter.measureString(" ", font).width - inset
        if x + size.x + tail > width
        {
            x       = -inset
            lineTop += lineHeight
        }

        return Math.Rectangle{x, Math.round(lineTop + (lineHeight - size.y) * 0.5), size.x, size.y}
    }

    // Returns the width the words have beside the switch, in a row `width` wide.
    mtd wordsWidth(width: f32)->f32 => Math.max(0, width - .toggle.position.width - ToggleGap)

    // Stands the switch at the end of the title's line, and the words and the control under them
    // at the width left beside it. A new wording needs this even when the row keeps its size.
    mtd arrange()
    {
        // A window is laid out as soon as it is made, before its parts exist.
        if .toggle == null do
            return

        let room   = .clientRect()
        let words  = .wordsWidth(room.width)
        let toggle = .toggle.position
        .toggle.arrange(Math.Rectangle{room.right() - toggle.width, room.y + Math.round((TitleHeight - toggle.height) * 0.5), toggle.width, toggle.height})
        .title.arrange(Math.Rectangle{room.x, room.y, words, TitleHeight})

        let helpHeight = Math.ceil(.help.measure(Math.Point{words, 0}).preferred.y)
        .help.arrange(Math.Rectangle{room.x, room.y + TitleHeight + HelpGap, words, helpHeight})
        if .choice
        {
            var rect = .choiceRect(words)
            rect.offset(.help.position.x, .help.position.y)
            .choice.arrange(rect)

            // The words go on right after the chevron, where the choice's own air begins.
            .tailPos = Math.Point{rect.right() - .choice.padding.z, rect.vertCenter()}
        }
    }
}

impl IWnd for OptionRow
{
    mtd impl measureContent(available: Math.Point)->Math.Point
    {
        if .toggle == null do
            return {}
        let words = .wordsWidth(available.x)
        var help  = .help.measure(Math.Point{words, 0}).preferred.y
        if .choice do
            help = Math.max(help, .choiceRect(words).bottom())
        return Math.Point{0, Math.ceil(TitleHeight + HelpGap + help)}
    }

    // Writes the words of the paragraph that follow the choice, on the choice's line.
    mtd impl onPaint(evt: *PaintEvent)
    {
        if .choice == null or .choiceTail.isEmpty() do
            return
        let font    = unwrap .help.font().regular
        let painter = evt.paintContext.painter
        painter.drawString(.tailPos.x, font.opticalLineTop(.tailPos.y), .choiceTail, font, .themeColors().label_TextLight)
    }

    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        .arrange()
    }
}

// The page of privacy and automatic unmounting: one row per option, each with its own switch.
//
// The rows are parted by space and one hairline, never by a box. The delay of the inactivity
// option is a quiet word inside its paragraph, and is only live while the option is on.
struct OptionsPage
{
    using wnd: Wnd

    late
    {
        window:  *MainWindow
        column:  *StackLayoutCtrl
        privacy: *OptionRow
        lock:    *OptionRow
        suspend: *OptionRow
        idle:    *OptionRow
        timeout: *IconButton
    }

    head:         PageHead
    timeoutIndex: u32 = MainWindow.IdleDefaultIndex     // Entry of `MainWindow.IdleChoices` the delay says.
}

impl OptionsPage
{
    const RowPadding = 16'f32     // Air above and below the words of a row, on each side of its hairline.

    // Commands of the delay's menu, one per entry of `MainWindow.IdleChoices`.
    const TimeoutIds = ["vault.idle.5", "vault.idle.15", "vault.idle.30", "vault.idle.60"]

    // Creates the page in `window`, hidden.
    func create(window: *MainWindow)->*OptionsPage
    {
        with let result = Wnd.create'OptionsPage(window, "vault.options")
        {
            .window          = window
            .dockStyle       = .Center
            .backgroundStyle = .Transparent
            .hide()
        }

        let texts = appStrings()
        result.column = createPageColumn(result)
        result.head   = PageHead.create(result.column, texts.ui_PrivacyTitle, texts.ui_OptionsHelp)
        result.head.back.sigPressed += func|window|(_) { window.showPage(.List) }

        result.privacy = result.addRow(texts.ui_PrivacyMode, texts.ui_PrivacyModeHelp, first: true)
        result.lock    = result.addRow(texts.ui_UnmountOnLock, texts.ui_UnmountOnLockHelp)
        result.suspend = result.addRow(texts.ui_UnmountOnSuspend, texts.ui_UnmountOnSuspendHelp)
        result.idle    = result.addRow(texts.ui_UnmountOnIdle, texts.ui_UnmountOnIdleHelp)

        // The delay is a quiet word of the sentence, underlined so it reads as the one to change.
        with result.timeout = IconButton.createQuiet(result.idle, "vault.idleTimeout")
        {
            .updateFlags(.Underline)
            .sigPressed += func|page = result|(_) { page.chooseTimeout() }
        }

        result.idle.setChoice(result.timeout)
        result.privacy.toggle.sigChanged += func|window|(_) { window.readPrivacyControl() }
        for row in [result.lock, result.suspend, result.idle] do
            row.toggle.sigChanged += func|window|(_) { window.readAutoUnmountControls() }
        return result
    }

    // Adds the row of one option, under a hairline unless it is the first.
    private mtd addRow(title, help: string, first = false)->*OptionRow
    {
        if not first
        {
            // The column stacks the rule like any row, so it is taken out of the docking flow.
            with let rule = Separator.create(.column, .Top)
            {
                .dockStyle = .None
                .margin.y  = RowPadding
            }
        }

        with let result = OptionRow.create(.column, title, help)
        {
            .margin.y = first ? PageHeadGap : RowPadding
        }

        return result
    }

    // Says everything the page wrote at construction again, in the language now active.
    mtd retranslate()
    {
        let texts = appStrings()
        .head.retranslate(texts.ui_PrivacyTitle, texts.ui_OptionsHelp)
        .privacy.setTexts(texts.ui_PrivacyMode, texts.ui_PrivacyModeHelp)
        .lock.setTexts(texts.ui_UnmountOnLock, texts.ui_UnmountOnLockHelp)
        .suspend.setTexts(texts.ui_UnmountOnSuspend, texts.ui_UnmountOnSuspendHelp)
        .idle.setTexts(texts.ui_UnmountOnIdle, texts.ui_UnmountOnIdleHelp)
        .setTimeout(.timeoutIndex)
    }

    // Says the delay of entry `index` of `MainWindow.IdleChoices` in its sentence.
    mtd setTimeout(index: u32)
    {
        .timeoutIndex = index
        .timeout.setQuietText(Format.toString(appStrings().ui_Minutes, MainWindow.IdleChoices[index]))
        .arrange()
    }

    // Offers the delays under the word, the one in force checked, and keeps the one chosen.
    mtd chooseTimeout()
    {
        let menu = MenuCtrl.createPopup(me, owner: me)
        for id, index in TimeoutIds do
            menu.addRadioItem(Format.toString(appStrings().ui_Minutes, MainWindow.IdleChoices[index]), id, checked: index == .timeoutIndex)

        let chosen = menu.doModal(.timeout, autoDestroy: true) orelse ""
        for id, index in TimeoutIds where chosen == id
        {
            .setTimeout(cast(u32, index))
            .window.readAutoUnmountControls()
        }
    }

    // Places the column at the head of the page.
    mtd arrange()
    {
        if .timeout == null do
            return
        placePageColumn(me, .column)
        for row in [.privacy, .lock, .suspend, .idle] do
            row.arrange()
    }
}

impl IWnd for OptionsPage
{
    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        .arrange()
    }
}
