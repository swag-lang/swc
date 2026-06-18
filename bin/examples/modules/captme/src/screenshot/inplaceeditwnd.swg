using Core, Win32, Gdi32, Pixel

enum InPlaceEditMode
{
    Draw
    Line
    Circle
    Rect
    Arrow
    Text
    Marker
}

struct InPlaceEditWnd
{
    using wnd:            Wnd
    editWnd:              *EditWnd
    actionBar:            *IconBar
    editBar:              *IconBar
    capture:              *Capture
    newMain:              *MainWnd
    editMode:             InPlaceEditMode = .Arrow
    editColor:            Color = Argb.Red
    editColorHilight:     Color = Argb.Yellow
    uiScale:              f32 = 1 // DPI scale of the monitor the capture sits on
}

// The capture overlay spans the whole virtual desktop in physical pixels, so the
// editor chrome must be sized for the DPI of the monitor the captured area is on,
// otherwise the bars/buttons render at 96-DPI size and look tiny on a hi-DPI screen.
func captureUIScale(capture: *Capture)->f32
{
    let cx = cast(f32) g_DesktopX - capture.backImagePos.x + cast(f32) capture.width * 0.5
    let cy = cast(f32) g_DesktopY - capture.backImagePos.y + cast(f32) capture.height * 0.5
    foreach m in Env.getMonitors()
    {
        let r = m.rectReal
        if cx >= r.x and cx < r.right() and cy >= r.y and cy < r.bottom() do
            return Math.max(m.scale, 1.0)
    }
    return 1.0
}

impl InPlaceEditWnd
{
    func create(capture: *Capture, main: *MainWnd, parent: *Wnd)->*InPlaceEditWnd
    {
        with let frame = createMainFrame(main, parent, capture)
        {
            .uiScale = captureUIScale(capture)
            .createActionBar()
            .createEditBar(main)
            .setupCapture(capture)
        }

        return frame
    }

    // Private helper methods
    func createMainFrame(main: *MainWnd, parent: *Wnd, capture: *Capture)->*InPlaceEditWnd
    {
        let newMain = Wnd.create'MainWnd(main.parent, {})
        newMain.registerActions()
        newMain.registerShortcuts()
        newMain.inPlaceEdit = true

        with let frame = Wnd.create'InPlaceEditWnd(parent)
        {
            .owner   = newMain
            .capture = capture
            .newMain = newMain

            .editWnd           = EditWnd.create(newMain, frame)
            .editWnd.dockStyle = .Center
            newMain.editWnd    = .editWnd

            with let view = frame.editWnd.editView
            {
                .dockStyle   = .Center
                .viewMargin  = 0
                .inPlaceEdit = true
                .setCapture(capture)
                .setZoom(1)
                .setFocus()
            }
        }

        return frame
    }

    mtd createActionBar()
    {
        .actionBar                 = IconBar.create(.editWnd.editView, 24 * .uiScale, {})
        .actionBar.backgroundStyle = .Window
        let self                   = me

        let actions = [
            {"save", ThemeIcons24.Save, "Save capture as image file"},
            {"copy", ThemeIcons24.Copy, "Copy image to clipboard"},
            {"edit", ThemeIcons24.Edit, "Open in Captme editor"},
            {"close", ThemeIcons24.WndClose, "Cancel and discard capture"}]

        let theme = .getTheme()
        foreach action in actions do
            .actionBar.addItem(theme.getIcon24(action.item1), action.item0).toolTip = action.item2

        .actionBar.sigPressed += func|self|(btn) { self.handleActionBarPress(btn.id); }
    }

    mtd createEditBar(main: *MainWnd)
    {
        .editBar                 = IconBar.create(.editWnd.editView, 32 * .uiScale, {})
        .editBar.backgroundStyle = .Window
        .editBar.setIconBarFlags(.Vertical)
        let self = me

        let editTools = [
            {"draw", 7, "Free draw tool"},
            {"line", 1, "Draw straight line"},
            {"circle", 19, "Draw circle or ellipse"},
            {"rect", 20, "Draw rectangle or square"},
            {"arrow", 3, "Draw arrow"},
            {"text", 4, "Add text annotation"},
            {"marker", 9, "Highlight with marker"}]

        foreach tool in editTools do
            .editBar.addCheckableItem(Icon.from(&main.icons48, tool.item1), tool.item0).toolTip = tool.item2

        .editBar.sigCheckChanged += func|self|(btn) { self.handleEditModeChange(btn.id); }
        .createColorPicker()
    }

    mtd createColorPicker()
    {
        let btnColor = .editBar.addItem({}, "color")
        let self     = me
        btnColor.iconBtnFlags.add(.Popup)

        btnColor.sigPaintIcon = func|self|(btn, bc, pos, flags)
        {
            bc.painter.setParams(.Antialiased)
            var rect = pos
            rect.inflate(-2)
            let color = self.editMode == .Marker ? self.editColorHilight : self.editColor
            bc.painter.fillRoundRect(rect, 10, 10, color)
        }

        btnColor.sigShowPopup += func|self|(btn)
        {
            let color  = self.editMode == .Marker ? self.editColorHilight : self.editColor
            let picker = PropWnd.createColorPicker(cast(*IconButton) btn, color)
            picker.sigChanged += func|self, picker, btn|(pk)
            {
                if self.editMode == .Marker do
                    self.editColorHilight = picker.getColor()
                else do
                    self.editColor = picker.getColor()
                self.updateEditMode()
                btn.invalidate()
            }
        }
    }

    mtd setupCapture(capture: *Capture)
    {
        let self = me
        capture.gizmo.sigHasChanged = func|self|() { self.moveButtons(); }
        .moveButtons()
        .updateEditMode()
    }

    mtd handleActionBarPress(actionId: string)
    {
        switch actionId
        {
        case "copy":
            .capture.crop()
            .capture.copyAll()
            exitWithResult(false)
        case "close":
            exitWithResult(false)
        case "edit":
            .capture.crop()
            exitWithResult(true)
        case "save":
            let fileName = .newMain.getSaveAsImageName()
            if !fileName.isEmpty() do
                .capture.crop()
            .newMain.doSaveAsImage(fileName)
            exitWithResult(false)
        }
    }

    mtd handleEditModeChange(toolId: string)
    {
        switch toolId
        {
        case "draw":
            .editMode = .Draw
        case "line":
            .editMode = .Line
        case "circle":
            .editMode = .Circle
        case "rect":
            .editMode = .Rect
        case "arrow":
            .editMode = .Arrow
        case "text":
            .editMode = .Text
        case "marker":
            .editMode = .Marker
        }

        .updateEditMode()
    }

    func exitWithResult(grabDone: bool)
    {
        g_Exit     = true
        g_GrabDone = grabDone
    }

    func crop(capture: *Capture)
    {
        let grabRect = calculateGrabRect(capture)
        capture.applyGrabRect(grabRect)
        capture.updateCaptureState()
    }

    func calculateGrabRect(capture: *Capture)->Math.Rectangle
    {
        return Math.Rectangle{-capture.backImagePos.x, -capture.backImagePos.y, capture.width, capture.height}
    }

    func applyGrabRect(capture: *Capture, rect: Math.Rectangle)
    {
        var grabRect = rect

        capture.backImg.crop(grabRect)
        if capture.backImgOriginal.isValid() do
            capture.backImgOriginal = capture.backImg
    }

    func updateCaptureState(capture: *Capture)
    {
        with capture
        {
            .width, .widthOrg = cast(s32) .backImg.width
            .height, .heightOrg = cast(s32) .backImg.height
            .backImagePos        = {}
            .gizmo.sigHasChanged = null
            .inPlaceEdit         = false
            .dirtyBackImg        = true
            .selection.clear()
        }
    }

    mtd updateEditMode()
    {
        .updateEditBarButtons()
        .configureMainWindowEditMode()
    }

    mtd updateEditBarButtons()
    {
        let modeMap = [
            {"draw", InPlaceEditMode.Draw}, {"line", InPlaceEditMode.Line}, {"circle", InPlaceEditMode.Circle}, {"rect", InPlaceEditMode.Rect},
            {"arrow", InPlaceEditMode.Arrow}, {"text", InPlaceEditMode.Text}, {"marker", InPlaceEditMode.Marker}]

        foreach m in modeMap
        {
            let btn = assume .editBar.getButton(m.item0)
            btn.setCheck(.editMode == m.item1)
        }
    }

    mtd configureMainWindowEditMode()
    {
        const BORDER_SIZE    = 8
        const MARKER_SIZE    = 30
        const TEXT_SIZE      = 40
        const TEXT_BOLD      = 2
        const ARROW_END_SIZE = 5

        with me.newMain
        {
            switch me.editMode
            {
            case Draw:
                .editMode                = .Draw
                .mdlFormDraw.borderSize  = BORDER_SIZE
                .mdlFormDraw.borderColor = me.editColor

            case Line:
                .editMode                = .Line
                .mdlFormLine.borderSize  = BORDER_SIZE
                .mdlFormLine.borderColor = me.editColor

            case Circle:
                .editMode                 = .Shape
                .mdlFormShape.kind        = .Ellipse
                .mdlFormShape.borderSize  = BORDER_SIZE
                .mdlFormShape.borderColor = me.editColor
                .mdlFormShape.backColor   = 0

            case Rect:
                .editMode                 = .Shape
                .mdlFormShape.kind        = .RoundRectangle
                .mdlFormShape.borderSize  = BORDER_SIZE
                .mdlFormShape.borderColor = me.editColor
                .mdlFormShape.backColor   = 0

            case Arrow:
                .editMode                 = .Arrow
                .mdlFormArrow.borderSize  = BORDER_SIZE
                .mdlFormArrow.endSize     = ARROW_END_SIZE
                .mdlFormArrow.endCap      = .ArrowAnchor
                .mdlFormArrow.borderColor = me.editColor

            case Text:
                .editMode               = .Text
                .mdlFormText.fontSize   = TEXT_SIZE
                .mdlFormText.borderSize = 3
                .mdlFormText.text       = "A"
                .mdlFormText.boldSize   = TEXT_BOLD
                .mdlFormText.backColor  = me.editColor

            case Marker:
                .editMode                = .Draw
                .mdlFormDraw.borderSize  = MARKER_SIZE
                .mdlFormDraw.borderColor = me.editColorHilight.withAlpha(160)
            }
        }
    }

    mtd moveButtons()
    {
        let rect = Math.Rectangle{-.capture.backImagePos.x, -.capture.backImagePos.y, .capture.width, .capture.height}
        .positionActionBar(rect)
        .positionEditBar(rect)
    }

    mtd positionActionBar(rect: Math.Rectangle)
    {
        let margin = 4.0 * .uiScale
        let height = 40.0 * .uiScale
        let width  = .actionBar.position.width
        let x      = Math.max(10.0 * .uiScale, rect.right() - width)

        if rect.bottom() < g_ScreenHeight - height + margin do
            .actionBar.setPosition(x, rect.bottom() + margin, width, height)
        elif rect.y > height + margin do
            .actionBar.setPosition(x, rect.y - height - margin, width, height)
        else do
            .actionBar.setPosition(x, rect.bottom() - height - margin, width, height)
    }

    mtd positionEditBar(rect: Math.Rectangle)
    {
        let margin = 4.0 * .uiScale
        let width  = 40.0 * .uiScale
        let height = .editBar.position.height

        if rect.right() < g_ScreenWidth - width + margin do
            .editBar.setPosition(rect.right() + margin, rect.bottom() - height, width, height)
        elif rect.x > width + margin do
            .editBar.setPosition(rect.x - width - margin, rect.bottom() - height, width, height)
        else do
            .editBar.setPosition(rect.right() - width - margin, rect.bottom() - height - margin, width, height)
    }
}

impl IWnd for InPlaceEditWnd
{
    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        evt.accepted = false
        if evt.kind == .KeyPressed and evt.key == .Escape do
            g_Exit = true
    }
}
