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

                // Escape is the cancel button pressed from the keyboard, so it closes
                // exactly when there is one to press and returns what it would have
                // returned. A box with nothing to cancel stays put rather than inventing a
                // result its caller never offered the reader.
                let cancel = .cancelButton()
                if cancel do
                    .closeWithResult(cancel.id)
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

    // Returns the button Escape and the close cross stand for, or null when the box offers
    // no way out other than answering it.
    mtd const cancelButton()->#null *PushButton
    {
        for btn in .buttons where btn.id == BtnCancel or btn.id == BtnNo do
            return btn
        return null
    }

    // Creates and attaches the native surface used by this dialog.
    mtd createSurface(from: *Surface, x, y: s32, width = 512, height = 300, flags = SurfaceFlags.None)->*Surface
    {
        Debug.assert(from != null)
        .parentSurface = from

        // The close cross is the dialog's to decide, never the caller's: it says "this can
        // be dismissed without answering", which is true exactly when a cancel button is
        // there to say the same thing. Offered without one it is ambiguous — the reader
        // cannot tell what closing the window will have decided — so `addButton` is what
        // puts it on, and a caller asking for it here is ignored.
        // A modal box sits on an application cut from the same ink. Without an edge of its
        // own it reads as part of the surface underneath it, so every dialog is outlined.
        let surfaceFlags = SurfaceFlags.LargeCaption | SurfaceFlags.ToolWindow | SurfaceFlags.Border | (flags & ~SurfaceFlags.CloseButton)
        let srf          = (expect from.app.createSurface(x, y, width, height, surfaceFlags, me))!
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
        return .surface!.wnd.view
    }

    // Runs the dialog modally and returns the accepted button identifier.
    mtd doModal()->WndId
    {
        let surface = .surface!
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
            // One dominant action per box. Created `Strong`, every button of the bar was
            // filled and the bar said nothing about which one Enter would press.
            .setForm(isDefault ? .Default : .Normal)

            // The theme width stays the floor so short captions keep the familiar button
            // size, while a longer translated caption widens its button instead of clipping.
            .fitWidthToLabel(me.themeMetrics().btnPush_Width)

            .sigPressed += func|dlg = me|(btn) { dlg.closeWithResult(btn.id) }

            me.buttons.add(btn)
        }

        if id == BtnCancel or id == BtnNo
        {
            let srf = .surface!
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
