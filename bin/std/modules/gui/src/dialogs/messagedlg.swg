using Core, Pixel

// Displays a rich message, optional icon and extension, and caller-defined action buttons.
public struct MessageDlg
{
    public
    {
        using dialog: Dialog     // Embedded dialog state.

        readonly
        {
            late labelIcon: *Label     // Optional large icon label.
            late label:     *Label     // Rich message label.
            extension:      *Wnd?      // Optional caller-owned extension docked below the message.
        }
    }
}

// Configures message content alignment, icon presentation, and post-creation customization.
public struct MessageDlgOptions
{
    public
    {
        title:     string       = ""                             // Surface title; empty keeps the helper's default.
        icon:      Icon                                          // Optional large message icon.
        iconColor: Color                                         // Icon tint, or transparent for its descriptor color.
        textHorizontalAlignment = StringHorzAlignment.Left       // Horizontal message alignment.
        textVerticalAlignment   = StringVertAlignment.Center     // Vertical message alignment.
        onCreated: (func||(*MessageDlg))?                        // Optional callback invoked before icon setup and layout.
    }
}

public impl MessageDlg
{
    // Creates a message dialog without adding action buttons.
    #[Swag.Discardable]
    func create(from: *Surface, message: string, options: MessageDlgOptions = {})->*MessageDlg
    {
        Debug.assert(from != null)
        let dlg = Wnd.create'MessageDlg()

        let srf = dlg.createSurface(from, 0, 0, 500, 300)
        if options.title.count do
            srf.setTitle(options.title)

        let body = dlg.createContentView()
        let row  = Wnd.create'Wnd(body)
        row.dockStyle = .Center

        with dlg.label = Label.create(row, message, {})
        {
            .dockStyle = .Center

            // Ellipsis backs the wrap up: a run that wrapping cannot break — a path, a URL —
            // is cut at the box's maximum width instead of forcing the box as wide as itself.
            .updateFlags(.WordWrap | .Ellipsis)
            .setTextAlignment(options.textHorizontalAlignment, options.textVerticalAlignment)
        }

        if options.onCreated do
            options.onCreated(dlg)

        dlg.setIcon(options.icon)

        // setIcon only creates the icon label when an icon is provided; setting a
        // color without an icon is a no-op (and would otherwise assert).
        if options.icon.isValid() do
            dlg.setIconColor(options.iconColor)
        dlg.sendResizeEvent()
        return dlg
    }

    // Adapts the surface to its content, centers it on its owner, and returns the modal result.
    mtd doModal()->WndId
    {
        .adaptSizeToMessage()
        let srf = .surface!
        srf.center(.parentSurface!)
        return Dialog.doModal(me)
    }

    // Widest a message is allowed to run before it wraps.
    private const MaxMessageWidth = 512.0'f32

    // Narrowest a message box is allowed to be, whatever it holds.
    //
    // Fitted to a short question and to nothing else, a box came out barely wider than its own
    // action bar: two buttons at the theme width then ran edge to edge under one short line, and
    // the box read as a pair of buttons with a caption. This is the width the single-line prompt
    // of the same family opens at, so a question and a prompt are one object on screen.
    internal const MinMessageWidth = 450.0'f32

    // Tallest a message is allowed to grow before the box stops following it.
    private const MaxMessageHeight = 512.0'f32

    // Gives the surface the width its message wants and the height that width then calls for.
    internal mtd adaptSizeToMessage()
    {
        let metrics = .themeMetrics()
        let srf     = .surface!

        // The room the message loses to the frame and to the standard body inset, on each side.
        let chrome   = 2 * metrics.dialog_Padding + 2 * metrics.wnd_BorderSize
        let iconRoom = (.labelIcon != null) ? .labelIcon.position.width : 0

        // Width: what the actions need side by side, then whatever more the message wants, up to
        // the width it is allowed to run before wrapping. The label answers with its own format
        // and at the density its glyphs are really drawn at, so the measurement is the layout
        // the paint will do. Ellipsis is what keeps it bounded: a run that wrapping cannot break
        // — a path, a URL — is cut at the maximum instead of widening the box to its own length.
        var w = 0'f32
        for btn in .buttons do
            w += btn.position.width
        w += cast(f32) ((.buttons.count - 1) * metrics.dialog_BtnPadding)
        w += chrome
        w = Math.max(w, .label.itf.measureContent({MaxMessageWidth, 0}).x + iconRoom + chrome)

        if .extension do
            w = Math.max(w, .extension.position.width + chrome)

        w = Math.max(w, MinMessageWidth)

        // The width is committed before the height is measured, and the height then answers for
        // the width the message was really given rather than for the one just asked for. The two
        // differ: a window lands on whole physical pixels and its tree is laid out on whole
        // logical ones, so a box fitted to the exact extent of its own message came back a
        // fraction of a unit narrower, wrapped one line more than it had been made tall for, and
        // clipped its own text top and bottom — which is what every two-sentence error box did.
        var pos = srf.position
        pos.width = .physicalRoom(w + 2 * srf.shadowMargin())
        srf.setPosition(pos)
        .applyLayout()

        var contentHeight = Math.min(MaxMessageHeight, .label.itf.measureContent({.label.position.width, 0}).y)
        if .labelIcon != null do
            contentHeight = Math.max(contentHeight, .labelIcon.icon.sizeY)

        let ext = .extension
        if ext do
            contentHeight += ext.margin.y + ext.position.height + ext.margin.w

        .fitHeightToContent(contentHeight)
    }

    // Docks one extension below the message content.
    mtd setExtension(wndExtension: *Wnd)
    {
        Debug.assert(.extension == null)
        Debug.assert(.contentView != null, "a message dialog needs its standard content view before adding an extension")

        wndExtension.setParent(.contentView)
        .extension           = wndExtension
        .extension.dockStyle = .Bottom
        .extension.margin.y  = .themeMetrics().dialog_BtnPadding * 2
    }

    // Changes the large icon tint.
    mtd setIconColor(color: Color)
    {
        Debug.assert((.labelIcon != null))
        .labelIcon.setIconColor(color)
    }

    // Creates or replaces the large message icon; an invalid icon leaves it unchanged.
    mtd setIcon(icon: Icon, color: Color = Argb.Zero)
    {
        if !icon.isValid() do
            return

        let gap = .themeMetrics().dialog_BtnPadding * 2
        if !(.labelIcon != null) do
            .labelIcon = Label.create(.label.parent!, "", {0, 0, icon.sizeX + gap, 0})

        with me.labelIcon
        {
            .position.width = icon.sizeX + gap
            .dockStyle      = .Left
            .setIcon(icon)
            .setIconColor(color)
            .setIconAlignment(.Left, .Center)
        }
    }

    // Shows a modal message with one OK action.
    func ok(from: *Surface, message: string, options: MessageDlgOptions = {})
    {
        var opt = options
        if !opt.icon.isValid()
        {
            opt.icon      = from.app.theme.icon(.Information, 48)
            opt.iconColor = from.app.theme.colors.dlg_InformationIcon
        }

        // Every box names itself. Left empty the caption still takes its band, so the box opened
        // under an empty bar and read as one the application had forgotten to finish.
        if !opt.title.count do
            opt.title = strings().dlg_InfoTitle

        with let dlg = create(from, message, opt)
        {
            .addButton(strings().dlg_Ok, Dialog.BtnOk, true)
        }

        discard dlg.doModal()
    }

    // Shows a modal message with OK and Cancel actions.
    func okCancel(from: *Surface, message: string, defaultId = Dialog.BtnCancel, options: MessageDlgOptions = {})->WndId
    {
        var opt = options
        if !opt.icon.isValid()
        {
            opt.icon      = from.app.theme.icon(.Question, 48)
            opt.iconColor = from.app.theme.colors.dlg_InformationIcon
        }

        if !opt.title.count do
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
        if !opt.icon.isValid()
        {
            opt.icon      = from.app.theme.icon(ThemeIcons.Question, 48)
            opt.iconColor = from.app.theme.colors.dlg_InformationIcon
        }

        if !opt.title.count do
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
        if !opt.icon.isValid()
        {
            opt.icon      = from.app.theme.icon(ThemeIcons.Question, 48)
            opt.iconColor = from.app.theme.colors.dlg_InformationIcon
        }

        if !opt.title.count do
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
    func confirm(from: *Surface, message: string, question: string? = null, defaultId = Dialog.BtnNo, options: MessageDlgOptions = {})->WndId
    {
        var txt = String.from(message)
        while !txt.isEmpty() and txt.back() == '\n' do
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
        if !opt.title.count do
            opt.title = strings().dlg_ConfirmTitle

        return yesNo(from, txt.toString(), defaultId, opt)
    }

    // Message box to show a raised error. The caller captures the error ('catch f() as err') and
    // hands it in; when a SystemError is passed its message is appended to the shown text.
    func error(from: *Surface, message: string? = null, err: any? = null, options: MessageDlgOptions = {})
    {
        // The detail is a paragraph under the message, and only when there is one: appended
        // unconditionally, the separator left an empty line the box still had to be tall
        // enough to hold.
        var txt: String = String.from(message)
        if err != null
        {
            switch err
            {
            case Swag.SystemError:
                let sysErr = cast(Swag.SystemError) err
                if !txt.isEmpty() do
                    txt += "\n\n"
                txt += sysErr.message
            }
        }

        // The glyph carries the severity, so it is set in the colour that reports one. Filled
        // white it was the loudest thing on the surface and said nothing the title had not
        // said already.
        var opt = options
        if !opt.icon.isValid()
        {
            opt.icon      = from.app.theme.icon(.Critical, 48)
            opt.iconColor = from.app.theme.colors.error
        }

        if !opt.title.count do
            opt.title = strings().dlg_ErrorTitle

        with let dlg = create(from, txt.toString(), opt)
        {
            .addButton(strings().dlg_Ok, Dialog.BtnOk, true)
        }

        discard dlg.doModal()
    }
}
