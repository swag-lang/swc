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

        result.toggle = ToggleButton.create(result)
        return result
    }

    // Says the option again in the active language; RichString owns all inline layout.
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
    }
}

impl IWnd for OptionRow
{
    mtd impl measureContent(available: Math.Point)->Math.Point
    {
        if .toggle == null do
            return {}
        let words = .wordsWidth(available.x)
        let help  = .help.measure(Math.Point{words, 0}).preferred.y
        return Math.Point{0, Math.ceil(TitleHeight + HelpGap + help)}
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
        window:     *MainWindow
        column:     *StackLayoutCtrl
        headColumn: *StackLayoutCtrl
        privacy:    *OptionRow
        lock:       *OptionRow
        suspend:    *OptionRow
        idle:       *OptionRow
        timeout:    *Label
        resident:   *OptionRow
        startup:    *OptionRow
        scroll:     *ScrollWnd
    }

    head:         PageHead
    timeoutIndex: u32 = MainWindow.IdleDefaultIndex     // Entry of `MainWindow.IdleChoices` the delay says.
    arranging:    bool
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
        result.headColumn = createPageColumn(result)
        result.head       = PageHead.create(result.headColumn, texts.ui_PrivacyTitle, texts.ui_OptionsHelp)
        with result.scroll = Wnd.create'ScrollWnd(result)
        {
            .dockStyle  = .None
            .frameFlags = .None
            .updateFlags(.DisableHorizontal | .TransparentBars)
            .createView'Wnd()
        }

        result.column = createPageColumn(result.scroll.view)
        result.scroll.view.hookOnEvent = func|page = result|(_, event)->bool
        {
            if event is ResizeEvent do
                page.arrange()
            return false
        }

        result.head.back.sigPressed += func|window|(_)
        {
            window.showPage(.List)
        }

        result.privacy                    = result.addRow(texts.ui_PrivacyMode, texts.ui_PrivacyModeHelp, first: true)
        result.lock                       = result.addRow(texts.ui_UnmountOnLock, texts.ui_UnmountOnLockHelp)
        result.suspend                    = result.addRow(texts.ui_UnmountOnSuspend, texts.ui_UnmountOnSuspendHelp)
        result.idle                       = result.addRow(texts.ui_UnmountOnIdle, texts.ui_UnmountOnIdleHelp)
        result.resident                   = result.addRow(texts.ui_Resident, texts.ui_ResidentHelp)
        result.startup                    = result.addRow(texts.ui_SessionStartup, texts.ui_SessionStartupHelp)
        result.resident.toggle.sigChanged += func|window|(button) { window.resident.setEnabled(button.isChecked()) }
        result.startup.toggle.sigChanged  += func|window|(button) { window.resident.setSessionStartup(button.isChecked()) }

        // The delay is a rich-text action: the same layout, state and keyboard handling
        // used by every inline action label in GUI.
        result.timeout = result.idle.help
        result.timeout.updateFlags(.LinkActions)
        result.timeout.sigLinkActivated += func|page = result|(_, _) { page.chooseTimeout() }

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
            .margin.y = first ? 0 : RowPadding
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
        .resident.setTexts(texts.ui_Resident, texts.ui_ResidentHelp)
        .startup.setTexts(texts.ui_SessionStartup, texts.ui_SessionStartupHelp)
        .setTimeout(.timeoutIndex)
    }

    // Says the delay of entry `index` of `MainWindow.IdleChoices` in its sentence.
    mtd setTimeout(index: u32)
    {
        .timeoutIndex = index
        var words = Format.toString(appStrings().ui_Minutes, MainWindow.IdleChoices[index])
        words.replace(' ', "\u00A0")
        let action = Format.toString("<url>%</url>", words)
        .timeout.setText(Format.toString(appStrings().ui_UnmountOnIdleHelp, action))
        .timeout.setLinksEnabled(.window.autoUnmount.onIdle)
        .arrange()
    }

    // Offers the delays under the word, the one in force checked, and keeps the one chosen.
    mtd chooseTimeout()
    {
        let menu = MenuCtrl.createPopup(me, owner: me)
        for id, index in TimeoutIds do
            menu.addRadioItem(Format.toString(appStrings().ui_Minutes, MainWindow.IdleChoices[index]), id, checked: index == .timeoutIndex)

        let link   = .timeout.firstLinkRect()
        let bounds = .timeout.surfaceRect()
        let chosen = menu.doModal(Math.Point{bounds.x + link.x, bounds.y + link.bottom()}, .TopLeft, autoDestroy: true) orelse ""
        for id, index in TimeoutIds where chosen == id
        {
            .setTimeout(cast(u32, index))
            .window.readAutoUnmountControls()
        }
    }

    // The title and return stay visible; only the option rows scroll above the hint line.
    mtd arrange()
    {
        if .timeout == null or .arranging do
            return
        .arranging = true
        defer .arranging = false
        placePageColumn(me, .headColumn)
        let viewport = .clientRect()
        let top      = .headColumn.position.bottom() + PageHeadGap
        .scroll.arrange({0, top, viewport.width, Math.max(0, viewport.height - PageFoot - top)})
        let room   = .scroll.view.clientRect()
        let width  = Math.min(PageColumnWidth, Math.max(0, room.width - 2 * PageGutter))
        let height = Math.ceil(.column.measure({width, 0}).preferred.y)
        .column.arrange({Math.round((room.width - width) * 0.5), 0, width, height})
        .column.applyLayout()
        .scroll.setScrollSize(.scroll.view.position.width, .column.position.bottom() + PageGutter)
        for row in [.privacy, .lock, .suspend, .idle, .resident, .startup] do
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
