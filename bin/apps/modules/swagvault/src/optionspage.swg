using Core, Gui, Pixel

// One option of the privacy page: a title, a paragraph saying what it costs, and its switch.
//
// The switch stands at the end of the title's line, so the row reads as a sentence and its answer.
// What the option needs besides — the delay of the inactivity option — stands under the paragraph.
struct OptionRow
{
    using wnd: Wnd

    late
    {
        title:  *Label
        help:   *Label
        toggle: *ToggleButton
    }

    extra: *Wnd?     // Control under the paragraph, when the option needs one.
}

impl OptionRow
{
    const TitleHeight = 24'f32     // Height of the title's line, which the switch is centred on.
    const HelpGap     = 4'f32      // Air between the title and its paragraph.
    const ExtraGap    = 8'f32      // Air between the paragraph and the control under it.
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

        result.toggle = ToggleButton.create(result)
        return result
    }

    // Says the option again in the language now active.
    mtd setTexts(title, help: string)
    {
        .title.setText(title)
        .help.setText(help)
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
        if .extra
        {
            let extra = .extra.measure({}).preferred
            .extra.arrange(Math.Rectangle{room.x, .help.position.bottom() + ExtraGap, extra.x, extra.y})
        }
    }
}

impl IWnd for OptionRow
{
    mtd impl measureContent(available: Math.Point)->Math.Point
    {
        if .toggle == null do
            return {}
        let words  = .wordsWidth(available.x)
        var height = TitleHeight + HelpGap + .help.measure(Math.Point{words, 0}).preferred.y
        if .extra do
            height += ExtraGap + .extra.position.height
        return Math.Point{0, Math.ceil(height)}
    }

    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        .arrange()
    }
}

// The page of privacy and automatic unmounting: one row per option, each with its own switch.
//
// The rows are parted by space and one hairline, never by a box. The delay of the inactivity
// option stands under its paragraph, and is only live while the option is on.
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
        timeout: *ComboBox
    }

    head: PageHead
}

impl OptionsPage
{
    const RowPadding = 16'f32     // Air above and below the words of a row, on each side of its hairline.

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

        // The delay is as wide as the words it shows, not as a field of a form.
        with result.timeout = ComboBox.create(result.idle, Math.Rectangle{0, 0, 0, result.themeMetrics().comboBox_Height}, flags: .Flat)
        {
            .preferredSize.x = 0
            .style.setStyleSheetMetrics("comboBox_Width 0")
            .sigChanged += func|window|(_, _) { window.readAutoUnmountControls() }
        }

        result.idle.extra = result.timeout
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
        .timeout.clear()
        for minutes in MainWindow.IdleChoices do
            .timeout.addItem(Format.toString(texts.ui_Minutes, minutes))
        .arrange()
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
