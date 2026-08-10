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

    internal
    contentView: #null *Wnd     // Standard padded body created by the predefined dialog family.
}

impl IWnd for Dialog
{
    mtd impl onSysCommandEvent(evt: *SysCommandEvent)
    {
        if evt.kind == .Close do
            .closeWithResult(BtnCancel)
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

    // Returns the control the box opens the keyboard on, or null to take the reading order.
    //
    // A box with something to fill in opens on that, and its default action still answers Enter,
    // because a field hands the key on rather than consuming it. Anything the reader would *act*
    // on with a key is passed over, whatever it is and wherever it reads: a push button presses,
    // a check box or a toggle flips a preference, a radio button selects. Those all say so with
    // [[Gui.WndFlags.ActivatesOnKey]], so nothing here has to know one kind of button from another.
    //
    // A box made only of them is a question, and it opens on the action it names as its default
    // rather than on whichever control reads first — which is how a confirmation defaulting to
    // `No` would have answered `Yes`, and how one carrying a `Do not ask again` option opened on
    // the option instead of on the question. Tab still reaches everything; this is only where the
    // keyboard starts.
    mtd keyboardEntry()->#null *Wnd
    {
        for stop in FocusOrder.collect(.surface!.wnd).stops where !stop.wndFlags.has(.ActivatesOnKey) do
            return stop
        return .surface!.defaultButton
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
        h += 2 * metrics.dialog_BtnPadding
        with me.buttonBar = Wnd.create'StackLayoutCtrl(srf.wnd.view, "", {0, 0, 0, h})
        {
            .spacing         = metrics.dialog_BtnPadding
            .mode            = .HorizontalEnd
            .dockStyle       = .Bottom
            .backgroundStyle = .DialogBar
            .padding         = {metrics.dialog_Padding, metrics.dialog_BtnPadding, metrics.dialog_Padding, metrics.dialog_BtnPadding}
        }

        return srf
    }

    // Returns the content view above the action bar.
    mtd view()->*Wnd
    {
        return .surface!.wnd.view
    }

    // Creates the common body used by the predefined dialog family.
    //
    // The body owns the outer inset once, so individual dialogs only express the spacing
    // between their own pieces. A raised content ground and a quieter action ground then
    // separate the two bands without another border or accent rule.
    internal mtd createContentView()->*Wnd
    {
        Debug.assert(.contentView == null, "a dialog can only have one standard content view")

        let content = Wnd.create'Wnd(.surface!.wnd.view)
        content.dockStyle       = .Center
        content.backgroundStyle = .Transparent
        content.setAllPaddings(.themeMetrics().dialog_Padding)
        .contentView = content
        return content
    }

    // Runs the dialog modally and returns the accepted button identifier.
    //
    // The box opens ready for the keyboard: the focus goes where [[Gui.Dialog.keyboardEntry]] says,
    // unless the caller already placed it, so a dialog can be answered and dismissed without the
    // pointer.
    //
    // The ring showing where the keys will go is turned on with the box rather than by the first
    // Tab. A modal is a question, and the reader has to be told what pressing Enter now decides.
    mtd doModal()->WndId
    {
        let surface = .surface!
        surface.wnd.setInitialFocus(.keyboardEntry())
        surface.app.setFocusVisible(true)
        surface.bringToFront()
        surface.show()
        if .parentSurface and .parentSurface.isTopMost() do
            surface.setTopMost()
        return surface.app.doModalLoop(surface, restoreTo: .parentSurface)
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

        let srf = .surface!
        if isDefault do
            srf.defaultButton = btn

        if id == BtnCancel or id == BtnNo
        {
            srf.cancelButton = btn
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
