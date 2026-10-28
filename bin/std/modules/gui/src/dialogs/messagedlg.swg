using Core, Pixel

// Displays a titled message, an optional technical detail and extension, and caller-defined actions.
//
// The box is the composition of [[Gui.Dialog]]: its title is the first line of the body, the
// message follows in the soft ink, and a failure carries the critical dot before its title and
// its technical detail on a mono faint line under the message. There is no icon: the absence of
// the dot is the information.
public struct MessageDlg
{
    public
    {
        using dialog: Dialog     // Embedded dialog state.

        readonly
        {
            late label:    *Label          // Rich message label.
            detailLabel:   *Label?         // Mono faint line carrying the technical detail, when there is one.
            extension:     *Wnd?           // Optional caller-owned extension docked below the message.
            messageScroll: *ScrollWnd?     // Scrollable message viewport, created when the fitted text exceeds the available height.
        }
    }
}

// Configures the title, detail, alignment and post-creation customization of a [[Gui.MessageDlg]].
public struct MessageDlgOptions
{
    public
    {
        title:   string = ""     // Title of the box; empty keeps the helper's default.
        failure: bool            // Whether the title reports a failure, led by the critical dot.

        // Technical detail set under the message on a mono faint line — an error code, the report
        // of the system — or empty for none. It is for whoever files the report, never a
        // substitute for the sentence.
        detail: string = ""

        textHorizontalAlignment = StringHorzAlignment.Left     // Horizontal message alignment.
        textVerticalAlignment   = StringVertAlignment.Top      // Vertical message alignment.
        onCreated: (func||(*MessageDlg))?     // Optional callback invoked before layout.
    }
}

public impl MessageDlg
{
    // Creates a message dialog without adding action buttons.
    //
    // Add the actions with [[Gui.Dialog.addButton]], then run the box with
    // [[Gui.MessageDlg.doModal]], which fits it to its message first.
    #[Swag.Discardable]
    func create(from: *Surface, message: string, options: MessageDlgOptions = {})->*MessageDlg
    {
        Swag.assert(from != null)
        let dlg = Wnd.create'MessageDlg()

        discard dlg.createSurface(from, 0, 0, cast(s32, MinMessageWidth), 300)
        dlg.setTitle(options.title, options.failure)

        let body = dlg.createContentView()
        if options.detail.count
        {
            with dlg.detailLabel = Label.create(body, options.detail, flags: .WordWrap | .Ellipsis)
            {
                .dockStyle = .Bottom
                .margin.y  = dlg.themeMetrics().dialog_BtnPadding
                .style.setFont(dlg.theme().createDefaultFontFs(dlg.themeMetrics().defaultFontSize - 1), .Regular)
                .style.addStyleSheetColors("label_Text $faintText")
                .setTextAlignment(.Left, .Top)
            }
        }

        let row = Wnd.create'Wnd(body)
        row.dockStyle = .Center

        with dlg.label = Label.create(row, message, {})
        {
            .dockStyle = .Center

            // Ellipsis backs the wrap up: a run that wrapping cannot break — a path, a URL —
            // is cut at the box's maximum width instead of forcing the box as wide as itself.
            .updateFlags(.WordWrap | .Ellipsis | .SecondaryText)
            .setTextAlignment(options.textHorizontalAlignment, options.textVerticalAlignment)
        }

        if options.onCreated do
            options.onCreated(dlg)
        dlg.sendResizeEvent()
        return dlg
    }

    // Adapts the surface to its content, centers it on its owner, and returns the modal result.
    mtd doModal()->WndId
    {
        .adaptSizeToMessage()
        .surface!.center(unwrap .parentSurface)
        return Dialog.doModal(me)
    }

    // Widest a message is allowed to run before it wraps.
    private const MaxMessageWidth = 512.0'f32

    // Narrowest a message box is allowed to be, whatever it holds.
    //
    // Fitted to a short question and to nothing else, a box came out barely wider than its own
    // actions: two buttons at the theme width then ran edge to edge under one short line, and the
    // box read as a pair of buttons with a title. Every box of the family opens at least this
    // wide, so a question and a prompt are one object on screen.
    internal const MinMessageWidth = 440.0'f32

    // Tallest a message viewport grows; additional text remains available by scrolling.
    private const MaxMessageHeight = 512.0'f32

    // Gives the surface the width its message wants and the height that width then calls for.
    internal mtd adaptSizeToMessage(maxSurfaceHeight = Swag.F32.Inf)
    {
        let metrics = .themeMetrics()
        let srf     = unwrap .surface

        // The room the message loses to the inset and the outline, on both sides.
        let shadow = srf.shadowMargin()
        let chrome = .chromeWidth() - 2 * shadow

        // Width: what the actions need side by side, then whatever more the message wants, up to
        // the width it is allowed to run before wrapping. The label answers with its own format
        // and at the density its glyphs are really drawn at, so the measurement is the layout
        // the paint will do. Ellipsis is what keeps it bounded: a run that wrapping cannot break
        // — a path, a URL — is cut at the maximum instead of widening the box to its own length.
        var w = 0'f32
        for btn in .buttons do
            w += btn.position.width
        if .buttons.count > 1 do
            w += cast(f32, ((.buttons.count - 1) * metrics.dialog_BtnPadding))

        w = Math.max(w, .label.itf.measureContent({MaxMessageWidth, 0}).x)
        if .extension do
            w = Math.max(w, .extension.position.width)
        w = Math.max(w + chrome, MinMessageWidth)

        // The width is committed before the height is measured, and the height then answers for
        // the width the message was really given rather than for the one just asked for. The two
        // differ: a window lands on whole physical pixels and its tree is laid out on whole
        // logical ones, so a box fitted to the exact extent of its own message came back a
        // fraction of a unit narrower, wrapped one line more than it had been made tall for, and
        // clipped its own text top and bottom — which is what every two-sentence error box did.
        var pos = srf.position
        pos.width = .physicalRoom(w + 2 * shadow)

        srf.setPosition(pos)
        .applyLayout()

        let ext         = .extension
        var extraHeight = ext ? ext.margin.y + ext.position.height + ext.margin.w : 0
        let detail      = .detailLabel
        if detail
        {
            detail.position.height = Math.ceil(detail.itf.measureContent(Math.Point{detail.position.width, 0}).y)
            extraHeight += detail.margin.y + detail.position.height
        }

        var availableHeight = maxSurfaceHeight
        if srf.app.renderer.needsNativeWindow()
        {
            let monitor = Env.monitorForPoint(.parentSurface!.position.center())
            availableHeight = Math.min(availableHeight, monitor.physicalWorkArea.height / srf.dpiScale - 2 * metrics.dialog_Padding)
        }

        let overhead = .chromeHeight()
        let limit    = Math.max(1.0, Math.min(MaxMessageHeight, Math.floor(availableHeight - overhead - extraHeight) - 1))
        var needed   = .label.itf.measureContent(Math.Point{.label.position.width, 0}).y
        if needed > limit or .messageScroll
        {
            if not .messageScroll
            {
                with let scroll = Wnd.create'ScrollWnd(unwrap .label.parent)
                {
                    .dockStyle   = .Center
                    .padding     = 0
                    .focusPolicy = .Tab
                    .updateFlags(.DisableHorizontal | .CompactBars | .TransparentBars)
                    .createView'Wnd()
                }

                .label.setParent(scroll.view)
                .label.dockStyle   = .Top
                .messageScroll     = scroll
                scroll.hookOnEvent = func(wnd, evt)
                {
                    let key = catch cast(*KeyEvent?, evt)
                    if not key or key.kind != .Pressed or key.modifiers != .None do
                        return false
                    let scroll = assume cast (*ScrollWnd, wnd)
                    var y      = scroll.scrollPosition().y
                    switch key.key
                    {
                    case .Up:       y -= scroll.verticalScrollStep
                    case .Down:     y += scroll.verticalScrollStep
                    case .PageUp:   y -= scroll.view.position.height
                    case .PageDown: y += scroll.view.position.height
                    case .Home:     y = 0
                    case .End:      y = scroll.scrollSize.y
                    default:        return false
                    }

                    scroll.setScrollPos(0, y)
                    key.accepted = true
                    return true
                }
            }

            .messageScroll.setScrollSize(0, needed)
            .applyLayout()

            // The vertical bar takes horizontal room, which can add another wrapped line.
            needed = Math.ceil(.label.itf.measureContent(Math.Point{.messageScroll.view.position.width, 0}).y)
            .label.position.height = needed
            .messageScroll.setScrollSize(0, needed)
        }

        .fitHeightToContent(Math.min(limit, needed) + extraHeight)
    }

    // Docks one extension below the message content.
    mtd setExtension(wndExtension: *Wnd)
    {
        Swag.assert(.extension == null)
        Swag.assert(.contentView != null, "a message dialog needs its content view before adding an extension")

        wndExtension.setParent(.contentView)
        .extension = wndExtension
        .extension.dockStyle = .Bottom
        .extension.margin.y  = .themeMetrics().dialog_BtnPadding * 2
    }

    // Shows a modal message with one OK action, which Escape presses as well.
    func ok(from: *Surface, message: string, options: MessageDlgOptions = {})
    {
        // Every box names itself, and a box left untitled read as one the application had
        // forgotten to finish.
        var opt = options
        if not opt.title.count do
            opt.title = strings().dlg_InfoTitle

        let dlg = create(from, message, opt)
        dlg.surface!.cancelButton = dlg.addButton(strings().dlg_Ok, Dialog.BtnOk, true)
        discard dlg.doModal()
    }

    // Shows a modal message with OK and Cancel actions.
    func okCancel(from: *Surface, message: string, defaultId = Dialog.BtnCancel, options: MessageDlgOptions = {})->WndId
    {
        var opt = options
        if not opt.title.count do
            opt.title = strings().dlg_ConfirmTitle

        with let dlg = create(from, message, opt)
        {
            .addButton(strings().dlg_Ok, Dialog.BtnOk, defaultId == Dialog.BtnOk)
            .addButton(strings().dlg_Cancel, Dialog.BtnCancel, defaultId == Dialog.BtnCancel)
        }

        return dlg.doModal()
    }

    // Shows a modal question with Yes and No actions.
    func yesNo(from: *Surface, message: string, defaultId = Dialog.BtnNo, options: MessageDlgOptions = {})->WndId
    {
        var opt = options
        if not opt.title.count do
            opt.title = strings().dlg_ConfirmTitle

        with let dlg = create(from, message, opt)
        {
            .addButton(strings().dlg_Yes, Dialog.BtnYes, defaultId == Dialog.BtnYes)
            .addButton(strings().dlg_No, Dialog.BtnNo, defaultId == Dialog.BtnNo)
        }

        return dlg.doModal()
    }

    // Shows a modal question with Yes, No, and Cancel actions.
    func yesNoCancel(from: *Surface, message: string, defaultId = Dialog.BtnCancel, options: MessageDlgOptions = {})->WndId
    {
        var opt = options
        if not opt.title.count do
            opt.title = strings().dlg_ConfirmTitle

        with let dlg = create(from, message, opt)
        {
            .addButton(strings().dlg_Yes, Dialog.BtnYes, defaultId == Dialog.BtnYes)
            .addButton(strings().dlg_No, Dialog.BtnNo, defaultId == Dialog.BtnNo)
            .addButton(strings().dlg_Cancel, Dialog.BtnCancel, defaultId == Dialog.BtnCancel)
        }

        return dlg.doModal()
    }

    // Shows a standardized confirmation question with Yes and No actions.
    //
    // `question` is set under `message` as its own paragraph; when it is `null`, the standard
    // confirmation line is set there in bold.
    func confirm(from: *Surface, message: string, question: string? = null, defaultId = Dialog.BtnNo, options: MessageDlgOptions = {})->WndId
    {
        var txt = String.from(message)
        while not txt.isEmpty() and txt.back() == '\n' do
            txt.removeBack()
        txt += "\n\n"
        if question != null
        {
            txt += question
        }
        else
        {
            txt += "<b>"
            txt += strings().dlg_ConfirmText
            txt += "</b>"
        }

        var opt = options
        if not opt.title.count do
            opt.title = strings().dlg_ConfirmTitle

        return yesNo(from, txt.toString(), defaultId, opt)
    }

    // Shows a modal error message with one Close action, which Escape presses as well.
    //
    // The title carries the critical dot. The caller captures the error (`catch f() as err`) and
    // hands it in; when it is a `Swag.SystemError`, its message is the technical detail, set on a
    // mono faint line under the sentence unless [[Gui.MessageDlgOptions.detail]] already names
    // one.
    func error(from: *Surface, message: string? = null, err: any? = null, options: MessageDlgOptions = {})
    {
        var opt = options
        opt.failure = true
        if not opt.title.count do
            opt.title = strings().dlg_ErrorTitle

        var detail = String.from(opt.detail)
        if detail.isEmpty()
        {
            if err is Swag.SystemError as sysErr do
                detail = String.from(sysErr.message)
        }

        opt.detail = detail.toString()

        let dlg = create(from, message orelse "", opt)
        dlg.surface!.cancelButton = dlg.addButton(strings().dlg_Close, Dialog.BtnOk, true)
        discard dlg.doModal()
    }
}
