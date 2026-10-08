using Core, Pixel

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

// One tool of the in-place edit bar: the mode it selects, the button id, its glyph and tooltip.
struct InPlaceEditTool
{
    mode: InPlaceEditMode
    id:   string
    icon: CaptureIcons
    tip:  string
}

// Returns the tools of the in-place edit bar, in the order the bar shows them.
func inPlaceEditTools()->[7] InPlaceEditTool
{
    let texts = appStrings()
    return [{.Draw, "draw", .Draw, texts.tip_InpDraw},
            {.Line, "line", .Line, texts.tip_InpLine},
            {.Circle, "circle", .Circle, texts.tip_InpCircle},
            {.Rect, "rect", .Rect, texts.tip_InpRect},
            {.Arrow, "arrow", .Arrow, texts.tip_InpArrow},
            {.Text, "text", .Text, texts.tip_InpText},
            {.Marker, "marker", .Highlight, texts.tip_InpMarker}]
}

struct InPlaceEditWnd
{
    using wnd: Wnd

    late
    {
        editWnd:   *EditWnd
        actionBar: *IconBar
        editBar:   *IconBar
    }

    capture:          *Capture?
    late newMain:     *MainWnd
    editMode:         InPlaceEditMode = .Arrow
    editColor:        Color = Argb.Red
    editColorHilight: Color = Argb.Yellow
    uiScale:          f32   = 1     // Residual chrome scale, relative to the overlay surface
    captureScale:     f32   = 1     // DPI scale of the monitor the capture sits on
}

// Returns the DPI scale of the monitor the captured area sits on.
//
// The capture holds that monitor's physical pixels, so every measurement expressed in
// image pixels — the stroke of an annotation, the size of its text — has to follow this
// scale to keep its intended weight against the content it annotates.
func captureMonitorScale(capture: *Capture)->f32
{
    let cx = cast(f32, g_DesktopX) - capture.backImagePos.x + cast(f32, capture.width) * 0.5
    let cy = cast(f32, g_DesktopY) - capture.backImagePos.y + cast(f32, capture.height) * 0.5
    for monitor in Env.getMonitors() where monitor.physicalBounds.contains(cx, cy) do
        return Math.max(monitor.scaleFactor, 1.0)
    return 1.0
}

impl InPlaceEditWnd
{
    func create(capture: *Capture, main: *MainWnd, parent: *Wnd)->*InPlaceEditWnd
    {
        with let frame = createMainFrame(main, parent, capture)
        {
            // The GUI already scales its logical units by the overlay surface's own monitor
            // scale, so the chrome only needs the residual factor: bars and buttons then keep
            // their intended size when the captured area sits on a differently scaled monitor.
            .captureScale = captureMonitorScale(capture)
            .uiScale      = .captureScale / parent.deviceScale()

            .createActionBar()
            .createEditBar(main)
            .setupCapture(capture)
        }

        return frame
    }

    func createMainFrame(main: *MainWnd, parent: *Wnd, capture: *Capture)->*InPlaceEditWnd
    {
        with let newMain = Wnd.create'MainWnd(main.parent, {})
        {
            .registerActions()
            .registerShortcuts()
            .inPlaceEdit = true
        }

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
                .dockStyle  = .Center
                .viewMargin = 0
                .setCapture(capture)

                // The capture is in physical desktop pixels and the view draws in logical
                // units; the in-place mode shows the image exactly one texel per device
                // pixel, aligned with the desktop underneath, and holds that zoom.
                .setInPlaceEdit(parent.deviceScale())
                .setFocus()
            }
        }

        return frame
    }

    mtd createActionBar()
    {
        // The padding scales with the icon, or the buttons come out chunkier the further the
        // grabbed monitor sits below the surface's own scale.
        with .actionBar = IconBar.create(.editWnd.editView, 24 * .uiScale, {}, itemPadding: 4 * .uiScale)
        {
            .backgroundStyle = .Window
            .sigPressed      += func|editor = me|(btn) { editor.handleActionBarPress(btn.id orelse "") }
        }

        let actions = [
            {"save",  ThemeIcons.Save,     appStrings().tip_InpSave},
            {"copy",  ThemeIcons.Copy,     appStrings().tip_InpCopy},
            {"edit",  ThemeIcons.Edit,     appStrings().tip_InpEdit},
            {"close", ThemeIcons.WndClose, appStrings().tip_InpClose}]

        let theme = .theme()
        for action in actions do
            .actionBar.addButton(theme.icon(action.item1), action.item0).toolTip = action.item2
    }

    mtd createEditBar(main: *MainWnd)
    {
        with .editBar = IconBar.create(.editWnd.editView, 32 * .uiScale, {}, itemPadding: 4 * .uiScale)
        {
            .backgroundStyle = .Window
            .setOrientation(.Vertical)
            .sigCheckedChanged += func|editor = me|(btn) { editor.handleEditModeChange(btn.id orelse "") }
        }

        for tool in inPlaceEditTools() do
            .editBar.addRadioButton(main.icon(tool.icon, 48), tool.id).toolTip = tool.tip
        .createColorPicker()
    }

    mtd createColorPicker()
    {
        let btnColor = .editBar.addButton({}, "color", .Popup)

        btnColor.iconPainter = func|editor = me|(?, bc, pos, ?)
        {
            bc.painter.setParams(.Antialiased)
            var rect = pos
            rect.inflate(-2)
            bc.painter.fillRoundRect(rect, 10, 10, editor.toolColor())
        }

        btnColor.sigPopupRequested += func|editor = me|(btn)
        {
            let picker = PropWnd.createColorPicker(assume cast(*IconButton, btn), editor.toolColor())
            picker.sigColorChanged += func|editor, picker, btn|(?)
            {
                if editor.editMode == .Marker do
                    editor.editColorHilight = picker.color()
                else do
                    editor.editColor = picker.color()
                editor.updateEditMode()
                btn.invalidate()
            }
        }
    }

    // Returns the color the current tool draws with: the marker keeps a highlight color of its own.
    mtd toolColor()->Color => .editMode == .Marker ? .editColorHilight : .editColor

    mtd setupCapture(capture: *Capture)
    {
        capture.gizmo.sigHasChanged = func|editor = me|() { editor.moveButtons() }
        .moveButtons()
        .updateEditMode()
    }

    mtd handleActionBarPress(actionId: string)
    {
        switch actionId
        {
        case "copy":
            with let cap = me.capture!
            {
                .cropToGrab()
                .copyAll()
            }

            exitWithResult(false)

        case "close":
            exitWithResult(false)

        case "edit":
            .capture!.cropToGrab()
            exitWithResult(true)

        case "save":

            // On a cancelled save dialog getSaveAsImageName() returns "": keep the
            // in-place editor open instead of writing an empty path and tearing the
            // session down (which would discard the capture being edited).
            let fileName = .newMain.getSaveAsImageName()
            if not fileName.isEmpty()
            {
                .capture!.cropToGrab()
                .newMain.doSaveAsImage(fileName)
                exitWithResult(false)
            }
        }
    }

    mtd handleEditModeChange(toolId: string)
    {
        for tool in inPlaceEditTools() where tool.id == toolId do
            .editMode = tool.mode
        .updateEditMode()
    }

    func exitWithResult(grabDone: bool)
    {
        g_Exit     = true
        g_GrabDone = grabDone
    }

    mtd updateEditMode()
    {
        .updateEditBarButtons()
        .configureMainWindowEditMode()
    }

    mtd updateEditBarButtons()
    {
        for tool in inPlaceEditTools() do
            .editBar.buttonById(tool.id)!.setChecked(.editMode == tool.mode)
    }

    mtd configureMainWindowEditMode()
    {
        // Lengths in image pixels, authored against a 100% capture and scaled to the density
        // of the monitor grabbed: a denser monitor packs more pixels into the same content, so
        // a fixed stroke would come out thinner and thinner against what it annotates.
        // `ArrowEndSize` stays out of it — a cap size is a multiple of the pen width, which
        // already carries the scale.
        let k = .captureScale

        let borderSize     = 8 * k
        let markerSize     = 30 * k
        let textSize       = 40 * k
        let textBold       = 2 * k
        let textBorderSize = 3 * k
        const ArrowEndSize = 5

        with me.newMain
        {
            switch me.editMode
            {
            case .Draw:
                .editMode = .Draw
                .mdlFormDraw.borderSize  = borderSize
                .mdlFormDraw.borderColor = me.editColor

            case .Line:
                .editMode = .Line
                .mdlFormLine.borderSize  = borderSize
                .mdlFormLine.borderColor = me.editColor

            case .Circle:
                .editMode = .Shape
                .mdlFormShape.kind        = .Ellipse
                .mdlFormShape.borderSize  = borderSize
                .mdlFormShape.borderColor = me.editColor
                .mdlFormShape.backColor   = 0

            case .Rect:
                .editMode = .Shape
                .mdlFormShape.kind        = .RoundRectangle
                .mdlFormShape.borderSize  = borderSize
                .mdlFormShape.borderColor = me.editColor
                .mdlFormShape.backColor   = 0

            case .Arrow:
                .editMode = .Arrow
                .mdlFormArrow.borderSize  = borderSize
                .mdlFormArrow.endSize     = ArrowEndSize
                .mdlFormArrow.endCap      = .ArrowAnchor
                .mdlFormArrow.borderColor = me.editColor

            case .Text:
                .editMode               = .Text
                .mdlFormText.fontSize   = textSize
                .mdlFormText.borderSize = textBorderSize
                .mdlFormText.text       = "A"
                .mdlFormText.boldSize   = textBold
                .mdlFormText.backColor  = me.editColor

            case .Marker:
                .editMode = .Draw
                .mdlFormDraw.borderSize  = markerSize
                .mdlFormDraw.borderColor = me.editColorHilight.withAlpha(160)
            }
        }
    }

    mtd moveButtons()
    {
        // The bars are children of the edit view, so they take the very rectangle the view
        // draws the capture into rather than converting the desktop-physical grab a second
        // time: one conversion, and the chrome cannot drift away from the selection.
        let rect = .editWnd.editView.getCaptureRect()
        .positionActionBar(rect)
        .positionEditBar(rect)
    }

    mtd positionActionBar(rect: Math.Rectangle)
    {
        let margin = 4.0 * .uiScale
        let height = 40.0 * .uiScale
        let width  = .actionBar.position.width
        let x      = Math.max(10.0 * .uiScale, rect.right() - width)
        let limitY = cast(f32, g_ScreenHeight) / .deviceScale()

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
        let limitX = cast(f32, g_ScreenWidth) / .deviceScale()

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

// The in-place editor works on the grabbed area of the desktop; these steps turn what it shows into
// an ordinary capture once the reader commits to it.
impl Capture
{
    // Crops the capture to the area the in-place editor shows, and makes it an ordinary capture.
    mtd cropToGrab()
    {
        .backImg.crop(Math.Rectangle{-.backImagePos.x, -.backImagePos.y, .width, .height})
        if .backImgOriginal.isValid() do
            .backImgOriginal = .backImg

        .width, .widthOrg    = cast(s32, .backImg.width)
        .height, .heightOrg  = cast(s32, .backImg.height)
        .backImagePos        = {}
        .gizmo.sigHasChanged = null
        .inPlaceEdit         = false
        .dirtyBackImg        = true
        .selection.clear()
    }
}
