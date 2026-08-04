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
    title:     string = ""                                   // Surface title; empty keeps the helper's default.
    icon:      Icon                                          // Optional large message icon.
    iconColor: Color                                         // Icon tint, or transparent for its descriptor color.
    textHorizontalAlignment = StringHorzAlignment.Center     // Horizontal message alignment.
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

        let metrics = from.wnd.themeMetrics()

        with dlg.label = Label.create(srf.view(), message, {})
        {
            .dockStyle = .Center
            .updateFlags(.WordWrap)
            .setTextAlignment(options.textHorizontalAlignment, options.textVerticalAlignment)
            .setAllPaddings(metrics.dialog_Padding)
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

    private mtd adaptSizeToMessage()
    {
        let metrics = .themeMetrics()

        // Evaluate size of text
        var fake: Painter
        fake.begin(layoutOnly: true)
        defer fake.end()
        var rsf: RichStringFormat
        rsf.font          = .font()
        rsf.flags         |= .WordWrap
        rsf.horzAlignment = .label.textHorizontalAlignment
        fake.drawRichString({0, 0, 512, 0}, &.label.name, rsf)
        .label.name.invalidate()

        // Width
        var w = 0'f32
        for btn in .buttons do
            w += btn.position.width
        w += cast(f32) ((.buttons.count - 1) * metrics.dialog_BtnPadding)
        w += 2 * metrics.dialog_Padding
        w += metrics.btnPush_Width

        var wl = .label.name.boundRect.width + 2 * metrics.dialog_Padding
        wl += 2 * metrics.wnd_BorderSize
        w  = Math.max(w, wl)

        if .extension
        {
            var wl1 = .extension.position.width + 2 * metrics.dialog_Padding
            wl1 += 2 * metrics.wnd_BorderSize
            w   = Math.max(w, wl1)
        }

        // Height
        var h = Math.min(512, .label.name.boundRect.height + .label.padding.y + .label.padding.w)
        if @isset(.labelIcon) do
            h += .labelIcon.position.height
        else do
            h += metrics.dialog_Padding
        h += .buttonBar.position.height
        h += 2 * metrics.wnd_BorderSize
        let srf = .surface!
        if srf.flags & .SmallCaption do
            h += metrics.wnd_SmallCaptionCY
        elif srf.flags & .LargeCaption do
            h += metrics.wnd_BigCaptionCY

        let ext = .extension
        if ext do
            h += ext.position.height

        var pos = srf.position
        pos.width  = w
        pos.height = h
        let sdw = srf.app.theme.metrics.surfaceWnd_ShadowSize
        pos.width  += sdw * 2
        pos.height += sdw * 2
        srf.setPosition(pos)
    }

    // Docks one extension below the message content.
    mtd setExtension(wndExtension: *Wnd)
    {
        Debug.assert(.extension == null)
        .extension           = wndExtension
        .extension.dockStyle = .Bottom
        .extension.margin.x  = .themeMetrics().dialog_Padding
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

        if !@isset(.labelIcon) do
            .labelIcon = Label.create(.surface!.wnd.view, "", {0, 0, 0, icon.sizeX + icon.sizeX * 0.5})
        .label.padding.y = 0

        with me.labelIcon
        {
            .dockStyle = .Top
            .setIcon(icon)
            .setIconColor(color)
            .setIconAlignment(.Center, .Center)
        }
    }

    // Shows a modal message with one OK action.
    func ok(from: *Surface, message: string, options: MessageDlgOptions = {})
    {
        with let dlg = create(from, message, options)
        {
            .addButton("OK", Dialog.BtnOk, true)
        }

        discard dlg.doModal()
    }

    // Shows a modal message with OK and Cancel actions.
    func okCancel(from: *Surface, message: string, defaultId = Dialog.BtnCancel, options: MessageDlgOptions = {})->WndId
    {
        with let dlg = create(from, message, options)
        {
            .addButton("OK", Dialog.BtnOk, defaultId == Dialog.BtnOk)
            .addButton("Cancel", Dialog.BtnCancel, defaultId == Dialog.BtnCancel)
        }

        return dlg.doModal()
    }

    // Shows a modal question with Yes and No actions.
    func yesNo(from: *Surface, message: string, defaultId = Dialog.BtnNo, options: MessageDlgOptions = {})->WndId
    {
        var opt = options
        if !opt.icon.isValid()
        {
            opt.icon      = from.app.theme.icon(ThemeIcons.Question, 64)
            opt.iconColor = Argb.White
        }

        with let dlg = create(from, message, opt)
        {
            .addButton("Yes", Dialog.BtnYes, defaultId == Dialog.BtnYes)
            .addButton("No", Dialog.BtnNo, defaultId == Dialog.BtnNo)
        }

        return dlg.doModal()
    }

    // Shows a modal question with Yes, No, and Cancel actions.
    func yesNoCancel(from: *Surface, message: string, defaultId = Dialog.BtnCancel, options: MessageDlgOptions = {})->WndId
    {
        var opt = options
        if !opt.icon.isValid()
        {
            opt.icon      = from.app.theme.icon(ThemeIcons.Question, 64)
            opt.iconColor = Argb.White
        }

        with let dlg = create(from, message, opt)
        {
            .addButton("Yes", Dialog.BtnYes, defaultId == Dialog.BtnYes)
            .addButton("No", Dialog.BtnNo, defaultId == Dialog.BtnNo)
            .addButton("Cancel", Dialog.BtnCancel, defaultId == Dialog.BtnCancel)
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
        txt += question orelse "<b>Do you want to continue?</b>"

        var opt = options
        if !@countof(opt.title) do
            opt.title = "Please confirm"

        return yesNo(from, txt.toString(), defaultId, opt)
    }

    // Message box to show a raised error. The caller captures the error ('catch f() as err') and
    // hands it in; when a SystemError is passed its message is appended to the shown text.
    func error(from: *Surface, message: #null string = null, err: #null any = null, options: MessageDlgOptions = {})
    {
        var txt: String = String.from(message)
        if !txt.isEmpty() do
            txt += "\n"

        if err != null
        {
            switch err
            {
            case Swag.SystemError:
                let sysErr = cast(Swag.SystemError) err
                txt += sysErr.message
            }
        }

        var opt = options
        if !opt.icon.isValid()
        {
            opt.icon      = from.app.theme.icon(.Critical, 64)
            opt.iconColor = Argb.White
        }

        if !@countof(opt.title) do
            opt.title = "Error"

        with let dlg = create(from, txt.toString(), opt)
        {
            .addButton("OK", Dialog.BtnOk, true)
        }

        discard dlg.doModal()
    }
}
