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
    using wnd: Wnd
    #[Swag.Late]
    {
        editWnd:   *EditWnd
        actionBar: *IconBar
        editBar:   *IconBar
    }

    capture: #null *Capture
    #[Swag.Late]
    newMain:          *MainWnd
    editMode:         InPlaceEditMode = .Arrow
    editColor:        Color           = Argb.Red
    editColorHilight: Color           = Argb.Yellow
    uiScale:          f32             = 1     // DPI scale of the monitor the capture sits on
}

// The GUI already scales its logical units by the overlay surface's own monitor
// scale. The chrome only needs the *residual* factor for the monitor the captured
// area sits on, so bars and buttons keep their intended size when that monitor
// uses a different scale than the surface's main monitor.
func captureUIScale(capture: *Capture, surfaceScale: f32)->f32
{
    let cx = cast(f32) g_DesktopX - capture.backImagePos.x + cast(f32) capture.width * 0.5
    let cy = cast(f32) g_DesktopY - capture.backImagePos.y + cast(f32) capture.height * 0.5
    for m in Env.getMonitors()
    {
        let r = m.physicalBounds
        if cx >= r.x and cx < r.right() and cy >= r.y and cy < r.bottom() do
            return Math.max(m.scaleFactor, 1.0) / surfaceScale
    }

    return 1.0
}

impl InPlaceEditWnd
{
    func create(capture: *Capture, main: *MainWnd, parent: *Wnd)->*InPlaceEditWnd
    {
        with let frame = createMainFrame(main, parent, capture)
        {
            .uiScale = captureUIScale(capture, parent.deviceScale())
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

                // The capture is in physical desktop pixels and the view draws in
                // logical units; this zoom shows the image exactly one texel per
                // device pixel, aligned with the desktop underneath.
                .setZoom(1.0 / parent.deviceScale())
                .setFocus()
            }
        }

        return frame
    }

    mtd createActionBar()
    {
        .actionBar                 = IconBar.create(.editWnd.editView!, 24 * .uiScale, {})
        .actionBar.backgroundStyle = .Window

        let actions = [
            {"save",  ThemeIcons.Save,     "Save capture as image file"},
            {"copy",  ThemeIcons.Copy,     "Copy image to clipboard"},
            {"edit",  ThemeIcons.Edit,     "Open in sCapture editor"},
            {"close", ThemeIcons.WndClose, "Cancel and discard capture"}]

        let theme = .theme()
        for action in actions do
            .actionBar.addButton(theme.icon(action.item1), action.item0).toolTip = action.item2

        .actionBar.sigPressed += func|self = me|(btn) { self.handleActionBarPress(btn.id orelse ""); }
    }

    mtd createEditBar(main: *MainWnd)
    {
        .editBar                 = IconBar.create(.editWnd.editView!, 32 * .uiScale, {})
        .editBar.backgroundStyle = .Window
        .editBar.setOrientation(.Vertical)

        let editTools = [
            {"draw",   CaptureIcons.Draw,      "Free draw tool"},
            {"line",   CaptureIcons.Line,      "Draw straight line"},
            {"circle", CaptureIcons.Circle,    "Draw circle or ellipse"},
            {"rect",   CaptureIcons.Rect,      "Draw rectangle or square"},
            {"arrow",  CaptureIcons.Arrow,     "Draw arrow"},
            {"text",   CaptureIcons.Text,      "Add text annotation"},
            {"marker", CaptureIcons.Highlight, "Highlight with marker"}]

        for tool in editTools do
            .editBar.addRadioButton(main.icon(tool.item1, 48), tool.item0).toolTip = tool.item2

        .editBar.sigCheckedChanged += func|self = me|(btn) { self.handleEditModeChange(btn.id orelse ""); }
        .createColorPicker()
    }

    mtd createColorPicker()
    {
        let btnColor = .editBar.addButton({}, "color", .Popup)

        btnColor.iconPainter = func|self = me|(btn, bc, pos, flags)
        {
            bc.painter.setParams(.Antialiased)
            var rect = pos
            rect.inflate(-2)
            let color = self.editMode == .Marker ? self.editColorHilight : self.editColor
            bc.painter.fillRoundRect(rect, 10, 10, color)
        }

        btnColor.sigPopupRequested += func|self = me|(btn)
        {
            let color  = self.editMode == .Marker ? self.editColorHilight : self.editColor
            let picker = PropWnd.createColorPicker(cast(*IconButton) btn, color)
            picker.sigColorChanged += func|self, picker, btn|(pk)
            {
                if self.editMode == .Marker do
                    self.editColorHilight = picker.color()
                else do
                    self.editColor = picker.color()
                self.updateEditMode()
                btn.invalidate()
            }
        }
    }

    mtd setupCapture(capture: *Capture)
    {
        capture.gizmo.sigHasChanged = func|self = me|() { self.moveButtons(); }
        .moveButtons()
        .updateEditMode()
    }

    mtd handleActionBarPress(actionId: string)
    {
        switch actionId
        {
        case "copy":
            let cap = me.capture!
            cap.crop()
            cap.copyAll()
            exitWithResult(false)

        case "close":
            exitWithResult(false)

        case "edit":
            let cap = me.capture!
            cap.crop()
            exitWithResult(true)

        case "save":

            // On a cancelled save dialog getSaveAsImageName() returns "": keep the
            // in-place editor open instead of writing an empty path and tearing the
            // session down (which would discard the capture being edited).
            let fileName = .newMain.getSaveAsImageName()
            if !fileName.isEmpty()
            {
                let cap = me.capture!
                cap.crop()
                .newMain.doSaveAsImage(fileName)
                exitWithResult(false)
            }
        }
    }

    mtd handleEditModeChange(toolId: string)
    {
        switch toolId
        {
        case "draw":   .editMode = .Draw
        case "line":   .editMode = .Line
        case "circle": .editMode = .Circle
        case "rect":   .editMode = .Rect
        case "arrow":  .editMode = .Arrow
        case "text":   .editMode = .Text
        case "marker": .editMode = .Marker
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
            .width, .widthOrg    = cast(s32) .backImg.width
            .height, .heightOrg  = cast(s32) .backImg.height
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

        for m in modeMap
        {
            let btn = .editBar.buttonById(m.item0)!
            btn.setChecked(.editMode == m.item1)
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
            case .Draw:
                .editMode                = .Draw
                .mdlFormDraw.borderSize  = BORDER_SIZE
                .mdlFormDraw.borderColor = me.editColor

            case .Line:
                .editMode                = .Line
                .mdlFormLine.borderSize  = BORDER_SIZE
                .mdlFormLine.borderColor = me.editColor

            case .Circle:
                .editMode                 = .Shape
                .mdlFormShape.kind        = .Ellipse
                .mdlFormShape.borderSize  = BORDER_SIZE
                .mdlFormShape.borderColor = me.editColor
                .mdlFormShape.backColor   = 0

            case .Rect:
                .editMode                 = .Shape
                .mdlFormShape.kind        = .RoundRectangle
                .mdlFormShape.borderSize  = BORDER_SIZE
                .mdlFormShape.borderColor = me.editColor
                .mdlFormShape.backColor   = 0

            case .Arrow:
                .editMode                 = .Arrow
                .mdlFormArrow.borderSize  = BORDER_SIZE
                .mdlFormArrow.endSize     = ARROW_END_SIZE
                .mdlFormArrow.endCap      = .ArrowAnchor
                .mdlFormArrow.borderColor = me.editColor

            case .Text:
                .editMode               = .Text
                .mdlFormText.fontSize   = TEXT_SIZE
                .mdlFormText.borderSize = 3
                .mdlFormText.text       = "A"
                .mdlFormText.boldSize   = TEXT_BOLD
                .mdlFormText.backColor  = me.editColor

            case .Marker:
                .editMode                = .Draw
                .mdlFormDraw.borderSize  = MARKER_SIZE
                .mdlFormDraw.borderColor = me.editColorHilight.withAlpha(160)
            }
        }
    }

    mtd moveButtons()
    {
        // The capture rectangle is in desktop-physical pixels; the bars are placed
        // in the logical units of the overlay surface.
        let capture = .capture!
        let k       = .deviceScale()
        var rect    = Math.Rectangle{-capture.backImagePos.x, -capture.backImagePos.y, capture.width, capture.height}
        rect.x      /= k
        rect.y      /= k
        rect.width  /= k
        rect.height /= k
        .positionActionBar(rect)
        .positionEditBar(rect)
    }

    mtd positionActionBar(rect: Math.Rectangle)
    {
        let margin = 4.0 * .uiScale
        let height = 40.0 * .uiScale
        let width  = .actionBar.position.width
        let x      = Math.max(10.0 * .uiScale, rect.right() - width)
        let limitY = cast(f32) g_ScreenHeight / .deviceScale()

        if rect.bottom() < limitY - height + margin do
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
        let limitX = cast(f32) g_ScreenWidth / .deviceScale()

        if rect.right() < limitX - width + margin do
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
        if evt.kind == .Pressed and evt.key == .Escape do
            g_Exit = true
    }
}
