#global public

using Core, Pixel

// Owns a modal floating sheet: a title, a body and a row of actions on one surface.
//
// A dialog is the floating sheet of the charter. It stands over its owner on the floating
// corner and shadow ([[Gui.SurfaceFlags.Sheet]]), with no caption band and no close cross: its
// title is the first line of the body ([[Gui.Dialog.setTitle]]), the content follows in one
// column ([[Gui.Dialog.createContentView]]), and the actions end the body at the bottom right,
// the primary one rightmost ([[Gui.Dialog.addButton]]). A box that can be left without answering
// it says so with the faint name of the Escape key at the bottom left. Every measure comes from
// the `dialog_` group of [[Gui.ThemeMetrics]].
struct Dialog
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.

        // Runs before a result closes the dialog; returning false keeps the dialog open.
        validateResult: (func||(*Dialog, WndId)->bool)?

        readonly
        {
            late buttonBar: *StackLayoutCtrl        // Row of actions at the foot of the body, the primary one rightmost.
            buttons:        Array'(*PushButton)     // Buttons in insertion order.
            parentSurface:  *Surface?               // Surface that owns the modal dialog.
            title:          RichString              // Title set as the first line of the body, or empty for none.
            failure:        bool                    // Whether the title reports a failure, marked by the critical dot.
            leadingControl: *Wnd?                   // Quiet control holding the bottom-left slot of the actions.
        }
    }

    internal contentView: *Wnd?     // Body created by [[Gui.Dialog.createContentView]].
}

impl IWnd for Dialog
{
    mtd impl onSysCommandEvent(evt: *SysCommandEvent)
    {
        if evt.kind == .Close do
            .closeWithResult(BtnCancel)
        evt.accepted = true
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let metrics = .themeMetrics()
        let colors  = .themeColors()
        let pad     = metrics.dialog_Padding

        // The title is the first line of the body. A failure leads it with the critical dot, set
        // on the capitals of the line rather than on the middle of its box.
        if not .title.raw.isEmpty()
        {
            let font    = .titleFont()
            let centerY = pad + Math.ceil(font.height) * 0.5
            var x       = pad
            if .failure
            {
                let size = metrics.dialog_MarkSize
                painter.setParams(.Antialiased)
                painter.fillCircle(x + size * 0.5, centerY, size * 0.5, colors.critical)
                x += size + metrics.dialog_BtnPadding
            }

            // Cut with an ellipsis rather than run past the inset: a translated title is longer.
            var sf: RichStringFormat
            sf.font          = .theme().createDefaultFontFamily(metrics.dialog_TitleFontSize)
            sf.fontStyle     = .Bold
            sf.horzAlignment = .Left
            sf.vertAlignment = .Top
            sf.flags         = .Ellipsis
            sf.palette[0]    = colors.text
            let line = Math.Rectangle{x, font.opticalLineTop(centerY), .position.width - pad - x, Math.ceil(font.height)}
            painter.drawRichString(line, &.title, sf)
        }

    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .ThemeChanged or evt.kind == .LanguageChanged do
            .updateInset()
        evt.accepted = false
    }
}

impl Dialog
{
    newCmdId("BtnYes")
    newCmdId("BtnNo")
    newCmdId("BtnOk")
    newCmdId("BtnCancel")

    // Creates and centers a dialog owned by `from`, titled `title`.
    //
    // `width` and `height` are where the box starts; a box that fits itself to its content —
    // [[Gui.Dialog.fitHeightToContent]] — replaces the height.
    #[Swag.Discardable]
    func create(from: *Surface, width = 512, height = 300, title: string? = null, flags = SurfaceFlags.None)->*Dialog
    {
        let dlg = Wnd.create'Dialog()
        let srf = dlg.createSurface(from, 0, 0, width, height, flags)
        dlg.setTitle(title orelse "")
        srf.center(from)
        return dlg
    }

    // Returns the control the box opens the keyboard on, or `null` to take the reading order.
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
    mtd keyboardEntry()->*Wnd?
    {
        for stop in FocusOrder.collect(.surface!.wnd).stops where not stop.wndFlags.has(.ActivatesOnKey) do
            return stop
        return .surface.defaultButton
    }

    // Returns the button Escape stands for, or `null` when the box offers no way out other than answering it.
    //
    // A Cancel is the way out whenever the box has one; a No stands for it only in a box without one.
    mtd const cancelButton()->*PushButton?
    {
        for btn in .buttons where btn.id == BtnCancel do
            return btn
        for btn in .buttons where btn.id == BtnNo do
            return btn
        return null
    }

    // Creates and attaches the native surface used by this dialog.
    //
    // A dialog is a floating sheet ([[Gui.SurfaceFlags.Sheet]]) with its outline: no strip and no
    // close cross, whatever caption flags `flags` carries. A box is dismissed by its own actions
    // and by Escape. `width` and `height` are those of the visible box; the surface adds the
    // margin its shadow falls in around it.
    mtd createSurface(from: *Surface, x, y: s32, width = 512, height = 300, flags = SurfaceFlags.None)->*Surface
    {
        Swag.assert(from != null)
        .parentSurface = from

        let caption = SurfaceFlags.CloseButton |
                      SurfaceFlags.MinimizeButton |
                      SurfaceFlags.MaximizeButton |
                      SurfaceFlags.LargeCaption |
                      SurfaceFlags.SmallCaption
        let surfaceFlags = SurfaceFlags.Sheet | SurfaceFlags.ToolWindow | SurfaceFlags.Border | (flags & ~caption)
        let srf = expect from.app.createSurface(x, y, width, height, surfaceFlags, me)

        srf.wnd.view.backgroundStyle = .Dialog

        // The actions end the body on its own ground: no band and no rule, one gap above them.
        let metrics = .themeMetrics()
        with me.buttonBar = Wnd.create'StackLayoutCtrl(srf.wnd.view, "", Math.Rectangle{0, 0, 0, metrics.control_DialogHeight})
        {
            .spacing   = metrics.dialog_BtnPadding
            .mode      = .HorizontalEnd
            .dockStyle = .Bottom
        }

        .updateInset()
        return srf
    }

    // Returns the window the body of the dialog is laid out in, which is the dialog itself.
    mtd view()->*Wnd => .surface!.wnd.view

    // Names the box: `title` is set as the first line of its body and on its surface.
    //
    // A title that reports a situation is a sentence; one that names the command the box carries
    // out repeats that command's label. `failure` leads the title with the critical dot, which is
    // the whole severity vocabulary of a box.
    mtd setTitle(title: string, failure = false)
    {
        .title.set(title)
        .failure = failure
        .surface?.setTitle(title)
        .updateInset()
        .invalidate()
    }

    // Puts a quiet control in the bottom-left slot of the actions.
    //
    // The slot holds at most one thing that belongs to the actions without being one of them,
    // such as the type filter of a file dialog. The control keeps its width and takes the height
    // of an action.
    mtd setLeadingControl(control: *Wnd)
    {
        Swag.assert(.leadingControl == null, "a dialog has one leading control")
        control.setParent(me)
        control.dockStyle = .None
        .leadingControl   = control
        .placeLeadingControl()
        .invalidate()
    }

    // Creates the body: the window the content of the box goes in, under its title and above its actions.
    //
    // The dialog owns the inset, once, around its title, its body and its actions, so the content
    // only states the spacing between its own pieces — one gap, `dialog_BtnPadding * 2`.
    mtd createContentView()->*Wnd
    {
        Swag.assert(.contentView == null, "a dialog can only have one content view")

        let content = Wnd.create'Wnd(me)
        content.dockStyle       = .Center
        content.backgroundStyle = .Transparent
        .contentView            = content
        return content
    }

    // Returns the physical size a surface must take to really hand `logical` units to its content.
    //
    // A window is placed on whole physical pixels, and the tree inside it is laid out on whole
    // logical ones. A rectangle rounded by neither therefore comes back a fraction of a unit
    // smaller than it asked for — and a box fitted to the exact extent of its own content then
    // clips the very content it was fitted to. Rounding out costs at most one pixel and is what
    // makes a fitted box hold what it measured.
    internal mtd const physicalRoom(logical: f32)->f32 => Math.ceil(Math.ceil(logical) * .surface!.dpiScale)

    // Returns the room the box keeps above and below its content: the inset, the title, the actions, the outline and the shadow.
    internal mtd chromeHeight()->f32
    {
        let surface = unwrap .surface
        var result  = .padding.y + .padding.w
        result += .buttonBar.position.height + .buttonBar.margin.y
        result += 2 * .themeMetrics().wnd_BorderSize
        result += 2 * surface.shadowMargin()
        return result
    }

    // Returns the room the box keeps beside its content: the inset, the outline and the shadow.
    internal mtd chromeWidth()->f32
    {
        let surface = unwrap .surface
        return .padding.x + .padding.z + 2 * .themeMetrics().wnd_BorderSize + 2 * surface.shadowMargin()
    }

    // Gives the surface exactly the vertical room `contentHeight` needs.
    //
    // `contentHeight` is the content alone: the inset, the title, the actions, the outline and
    // the shadow are added here, so no dialog carries a stale allowance for them when one of the
    // shared measures changes.
    mtd fitHeightToContent(contentHeight: f32)
    {
        Swag.assert(contentHeight >= 0, "dialog content height cannot be negative")

        let surface = unwrap .surface
        var pos     = surface.position
        pos.height = .physicalRoom(contentHeight + .chromeHeight())
        surface.setPosition(pos)
        .applyLayout()
        .placeLeadingControl()
    }

    // Keeps the visible box at least `width` by `height` when the reader resizes it; zero leaves an axis free.
    mtd setMinSize(width, height: f32)
    {
        let surface = unwrap .surface
        let margin  = 2 * surface.shadowMargin()
        surface.minSize = {width > 0 ? width + margin : 0, height > 0 ? height + margin : 0}
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
        let surface = unwrap .surface
        .placeLeadingControl()
        surface.wnd.setInitialFocus(.keyboardEntry())
        surface.app.setFocusVisible(true)
        surface.bringToFront()
        surface.show()
        if .parentSurface and .parentSurface.isTopMost() do
            surface.setTopMost()
        return surface.app.doModalLoop(surface, restoreTo: .parentSurface)
    }

    // Adds an action button and optionally makes it the default keyboard action.
    //
    // Pressing the button submits `id` through [[Gui.Dialog.closeWithResult]]. The default
    // button is the primary action: it takes the primary form and stands rightmost, the other
    // actions to its left in the order they were added, so the dismissing one, added last, stands
    // nearest the primary. A `BtnCancel` or `BtnNo` button also becomes the Escape action of the
    // surface, and a new default button demotes the previous one.
    #[Swag.Discardable]
    mtd addButton(str: string, id: WndId, isDefault: bool = false)->*PushButton
    {
        Swag.assert(str.count != 0, "dialog button text cannot be empty")
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

        // The eye finishes a box at its bottom right, which is where the answer belongs.
        for button in .buttons where button.form == .Default do
            button.bringToFront()

        let srf = unwrap .surface
        if isDefault do
            srf.defaultButton = btn
        if id == BtnCancel or id == BtnNo do
            srf.cancelButton = .cancelButton()

        .buttonBar.computeLayout()
        .invalidate()
        return btn
    }

    // Validates and submits a modal result, returning whether the dialog was allowed to close.
    #[Swag.Discardable]
    mtd closeWithResult(result: WndId?)->bool
    {
        let safeResult = result orelse ""
        let validator  = .validateResult
        if validator and not validator(me, safeResult) do
            return false
        .app().exitModal(safeResult)
        return true
    }
}

private impl Dialog
{
    // Returns the air between two pieces of one body.
    mtd bodyGap()->f32 => .themeMetrics().dialog_BtnPadding * 2

    // Returns the face the title is set in.
    mtd titleFont()->*Font => .theme().createDefaultFont(.themeMetrics().dialog_TitleFontSize, .Bold)

    // Keeps the inset around the body, the room of the title above it and the gap above the actions.
    mtd updateInset()
    {
        let metrics = .themeMetrics()
        let pad     = metrics.dialog_Padding
        var top     = pad
        if not .title.raw.isEmpty() do
            top += Math.ceil(.titleFont().height) + .bodyGap()
        .padding = Math.Vector4{pad, top, pad, pad}

        .buttonBar.margin.y        = .bodyGap()
        .buttonBar.position.height = metrics.control_DialogHeight
    }

    // Stands the leading control at the bottom left, on the row of the actions.
    mtd placeLeadingControl()
    {
        let control = .leadingControl
        if not control do
            return
        let bar = .buttonBar.position
        control.setPosition(Math.Rectangle{.padding.x, bar.y, control.position.width, bar.height})
    }
}
