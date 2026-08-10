using Core, Pixel

// Displays a rich message, optional icon and extension, and caller-defined action buttons.
public struct MessageDlg
{
    using dialog: Dialog     // Embedded dialog state.
    readonly
    {
        #[Swag.Late]
        labelIcon: *Label     // Optional large icon label.
        #[Swag.Late]
        label:     *Label         // Rich message label.
        extension: #null *Wnd     // Optional caller-owned extension docked below the message.
    }
}

// Configures message content alignment, icon presentation, and post-creation customization.
public struct MessageDlgOptions
{
    title:     string       = ""                             // Surface title; empty keeps the helper's default.
    icon:      Icon                                          // Optional large message icon.
    iconColor: Color                                         // Icon tint, or transparent for its descriptor color.
    textHorizontalAlignment = StringHorzAlignment.Left       // Horizontal message alignment.
    textVerticalAlignment   = StringVertAlignment.Center     // Vertical message alignment.
    onCreated: #null func||(*MessageDlg)                     // Optional callback invoked before icon setup and layout.
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
        if @countof(options.title) do
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

    private mtd adaptSizeToMessage()
    {
        let metrics = .themeMetrics()

        // The room the message loses to the frame and to the standard body inset, on each side.
        let chrome = 2 * metrics.dialog_Padding + 2 * metrics.wnd_BorderSize

        // Measured at the density the glyphs are really drawn at. Laid out at a scale of one
        // and drawn at another, a run comes out a touch wider than the width reserved for it,
        // and a message that was measured on one line wraps onto two the box has no room for.
        // Ellipsis mirrors the label's own paint, and is what keeps the measurement bounded:
        // a run that wrapping cannot break is cut at the maximum width instead of widening the box.
        let deviceScale = .deviceScale()
        var rsf: RichStringFormat
        rsf.font          = .font()
        rsf.flags         |= .WordWrap | .Ellipsis
        rsf.horzAlignment = .label.textHorizontalAlignment

        .label.name.compute()
        Painter.computeLayout({0, 0, MaxMessageWidth, MaxTextLayoutExtent}, &.label.name, rsf, deviceScale)

        // Width
        var w = 0'f32
        for btn in .buttons do
            w += btn.position.width
        w += cast(f32) ((.buttons.count - 1) * metrics.dialog_BtnPadding)
        w += 2 * metrics.dialog_Padding
        w += metrics.btnPush_Width
        let iconRoom = @isset(.labelIcon) ? .labelIcon.position.width : 0
        w = Math.max(w, .label.name.boundRect.width + iconRoom + chrome)

        if .extension do
            w = Math.max(w, .extension.position.width + chrome)

        // Height, measured a second time at the width the message will really be given: the
        // widest line decides the box, and the box then decides how many lines there are.
        Painter.computeLayout({0, 0, Math.max(w - chrome - iconRoom, 1), MaxTextLayoutExtent}, &.label.name, rsf, deviceScale)
        .label.name.invalidate()

        var h = Math.min(512, .label.name.boundRect.height)
        if @isset(.labelIcon) do
            h = Math.max(h, .labelIcon.icon.sizeY)
        h += 2 * metrics.dialog_Padding
        h += .buttonBar.position.height
        h += 2 * metrics.wnd_BorderSize
        let srf = .surface!
        if srf.flags & .SmallCaption do
            h += metrics.wnd_SmallCaptionCY
        elif srf.flags & .LargeCaption do
            h += metrics.wnd_BigCaptionCY

        let ext = .extension
        if ext do
            h += ext.margin.y + ext.position.height + ext.margin.w

        let sdw = srf.app.theme.metrics.surfaceWnd_ShadowSize
        w += sdw * 2
        h += sdw * 2

        // Everything measured above is in logical units; a surface rectangle is physical.
        // Handed over unscaled, the box opened at a fraction of the room its message needs
        // on any display past 100 percent: the text lost its whole band to the button bar
        // and the reader was left with an icon and an unreachable button.
        var pos = srf.position
        pos.width  = w * srf.dpiScale
        pos.height = h * srf.dpiScale
        srf.setPosition(pos)
    }

    // Docks one extension below the message content.
    mtd setExtension(wndExtension: *Wnd)
    {
        Debug.assert(.extension == null)
        Debug.assert(.contentView != null, "a message dialog needs its standard content view before adding an extension")

        wndExtension.setParent(.contentView)
        .extension = wndExtension
        .extension.dockStyle = .Bottom
        .extension.margin.y  = .themeMetrics().dialog_BtnPadding * 2
    }

    // Changes the large icon tint.
    mtd setIconColor(color: Color)
    {
        Debug.assert(@isset(.labelIcon))
        .labelIcon.setIconColor(color)
    }

    // Creates or replaces the large message icon; an invalid icon leaves it unchanged.
    mtd setIcon(icon: Icon, color: Color = Argb.Zero)
    {
        if !icon.isValid() do
            return

        let gap = .themeMetrics().dialog_BtnPadding * 2
        if !@isset(.labelIcon) do
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

        with let dlg = create(from, message, opt)
        {
            .addButton(strings().dlg_Yes, Dialog.BtnYes, defaultId == Dialog.BtnYes)
            .addButton(strings().dlg_No, Dialog.BtnNo, defaultId == Dialog.BtnNo)
            .addButton(strings().dlg_Cancel, Dialog.BtnCancel, defaultId == Dialog.BtnCancel)
        }

        return dlg.doModal()
    }

    // Shows a standardized confirmation question with Yes and No actions.
    func confirm(from: *Surface, message: string, question: #null string = null, defaultId = Dialog.BtnNo, options: MessageDlgOptions = {})->WndId
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
        if !@countof(opt.title) do
            opt.title = strings().dlg_ConfirmTitle

        return yesNo(from, txt.toString(), defaultId, opt)
    }

    // Message box to show a raised error. The caller captures the error ('catch f() as err') and
    // hands it in; when a SystemError is passed its message is appended to the shown text.
    func error(from: *Surface, message: #null string = null, err: #null any = null, options: MessageDlgOptions = {})
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

        if !@countof(opt.title) do
            opt.title = strings().dlg_ErrorTitle

        with let dlg = create(from, txt.toString(), opt)
        {
            .addButton(strings().dlg_Ok, Dialog.BtnOk, true)
        }

        discard dlg.doModal()
    }
}
