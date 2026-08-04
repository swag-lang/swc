#global public

// Owns a modal surface, a content view, and an optional validated action bar.
struct Dialog
{
    using wnd: Wnd     // Embedded window behavior and presentation.

    // Called before a button result closes the dialog; return false to keep it open.
    validateResult: #null func||(*Dialog, WndId)->bool

    readonly
    {
        buttonBar:     *StackLayoutCtrl = undefined     // Bottom action bar owned by the dialog.
        buttons:       Array'(*PushButton)              // Buttons in insertion order.
        parentSurface: #null *Surface                   // Surface that owns the modal dialog.
    }
}

impl IWnd for Dialog
{
    mtd impl onSysCommandEvent(evt: *SysCommandEvent)
    {
        if evt.kind == .Close do
            .closeWithResult(BtnCancel)
        evt.accepted = true
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind == .Pressed
        {
            // Pressing enter validates the default button
            switch evt.key
            {
            case .Tab, .Right:
                for btn, [idx] in .buttons
                {
                    if btn.form == .Default
                    {
                        btn.setForm(.Normal)
                        btn.invalidate()
                        let nextBtn = .buttons[(idx + 1) % .buttons.count]
                        nextBtn.setForm(.Default)
                        nextBtn.invalidate()
                        break
                    }
                }

            case .Left:
                for btn, [idx] in .buttons
                {
                    if btn.form == .Default
                    {
                        btn.setForm(.Normal)
                        btn.invalidate()
                        let prevBtn = idx ? .buttons[idx - 1] : .buttons.back()
                        prevBtn.setForm(.Default)
                        prevBtn.invalidate()
                        break
                    }
                }

            case .Enter:
                for btn in .buttons
                {
                    if btn.form == .Default
                    {
                        .closeWithResult(btn.id)
                        break
                    }
                }

            case .Escape:
                if (notnull .surface).flags.has(.CloseButton)
                {
                    .closeWithResult(BtnCancel)
                    break
                }

                for btn in .buttons
                {
                    if btn.id == BtnNo or btn.id == BtnCancel
                    {
                        .closeWithResult(btn.id)
                        break
                    }
                }
            }
        }

        evt.accepted = true
    }
}

impl Dialog
{
    newCmdId("BtnYes")
    newCmdId("BtnNo")
    newCmdId("BtnOk")
    newCmdId("BtnCancel")

    // Creates and centers a dialog surface owned by `from`.
    #[Swag.Discardable]
    func create(from: *Surface, width = 512, height = 300, title: #null string = null, flags = SurfaceFlags.None)->*Dialog
    {
        let dlg = Wnd.create'Dialog()
        let srf = dlg.createSurface(from, 0, 0, width, height, flags)
        srf.setTitle(title)
        srf.center(from)
        return dlg
    }

    // Creates and attaches the native surface used by this dialog.
    mtd createSurface(from: *Surface, x, y: s32, width = 512, height = 300, flags = SurfaceFlags.None)->*Surface
    {
        Debug.assert(from != null)
        .parentSurface = from
        let surfaceFlags = SurfaceFlags.LargeCaption | SurfaceFlags.ToolWindow | flags
        let srf          = notnull (expect from.app.createSurface(x, y, width, height, surfaceFlags, me))
        srf.wnd.view.backgroundStyle = .Dialog

        let metrics = .themeMetrics()
        var h       = metrics.btnPush_Height
        h += 2 * metrics.dialog_Padding
        with me.buttonBar = Wnd.create'StackLayoutCtrl(srf.wnd.view, "", {0, 0, 0, h})
        {
            .spacing         = 10
            .mode            = .Center
            .dockStyle       = .Bottom
            .backgroundStyle = .DialogBar
            .setAllPaddings(metrics.dialog_Padding)
        }

        .setFocus()
        return srf
    }

    // Returns the content view above the action bar.
    mtd view()->*Wnd
    {
        return (notnull .surface).wnd.view
    }

    // Runs the dialog modally and returns the accepted button identifier.
    mtd doModal()->WndId
    {
        let surface = notnull .surface
        surface.bringToFront()
        surface.show()
        if .parentSurface and .parentSurface.isTopMost() do
            surface.setTopMost()
        return surface.app.doModalLoop(surface)
    }

    // Adds an action button and optionally makes it the default keyboard action.
    #[Swag.Discardable]
    mtd addButton(str: string, id: WndId, isDefault: bool = false)->*PushButton
    {
        Debug.assert(@countof(str) != 0, "dialog button text cannot be empty")
        if isDefault
        {
            for button in .buttons where button.form == .Default do
                button.setForm(.Normal)
        }

        with let btn = PushButton.create(me.buttonBar, str, {}, id)
        {
            .setForm(isDefault ? .Default : .Strong)

            // The theme width stays the floor so short captions keep the familiar button
            // size, while a longer translated caption widens its button instead of clipping.
            .fitWidthToLabel(me.themeMetrics().btnPush_Width)

            .sigPressed += func|dlg = me|(btn) { dlg.closeWithResult(btn.id) }

            me.buttons.add(btn)
        }

        if id == BtnCancel or id == BtnNo
        {
            let srf = notnull .surface
            srf.updateFlags(add: .CloseButton)
        }

        return btn
    }

    // Validates and submits a modal result, returning whether the dialog was allowed to close.
    #[Swag.Discardable]
    mtd closeWithResult(result: #null WndId)->bool
    {
        let safeResult = result orelse ""
        let validator  = .validateResult
        if validator and !validator(me, safeResult) do
            return false
        .app().exitModal(safeResult)
        return true
    }
}
