using Core, Pixel

// The tool the in-place editor draws with.
enum InPlaceEditMode
{
    Select
    Rect
    Circle
    Line
    Arrow
    Text
    Callout
    Step
    Draw
    Marker
}

// One tool of the bar of the in-place editor: the mode it selects, its glyph and tooltip.
struct InPlaceEditTool
{
    mode: InPlaceEditMode
    icon: CaptureIcons
    tip:  string
}

// Returns the tools of the bar of the in-place editor, in the order the bar shows them.
func inPlaceEditTools()->[10] InPlaceEditTool
{
    let texts = appStrings()
    return [InPlaceEditTool{.Select, .Select, texts.act_Select},
            InPlaceEditTool{.Rect, .Rect, texts.tip_InpRect},
            InPlaceEditTool{.Circle, .Circle, texts.tip_InpCircle},
            InPlaceEditTool{.Line, .Line, texts.tip_InpLine},
            InPlaceEditTool{.Arrow, .Arrow, texts.tip_InpArrow},
            InPlaceEditTool{.Text, .Text, texts.tip_InpText},
            InPlaceEditTool{.Callout, .Text, texts.act_Callout},
            InPlaceEditTool{.Step, .Step, texts.act_Step},
            InPlaceEditTool{.Draw, .Draw, texts.tip_InpDraw},
            InPlaceEditTool{.Marker, .Highlight, texts.tip_InpMarker}]
}

// The editor shown over a fresh capture, where the zone is annotated before it leaves the screen.
//
// The desktop stays dimmed and the zone stands in full light, its edges still movable. One bar
// hangs under the zone: the tools as glyphs, the colour, then where the capture goes — pinned on
// the screen, to the editor, to a file — and Copy, the primary action; the keys are at the foot.
struct InPlaceEditWnd
{
    using wnd: Wnd

    late
    {
        editWnd:  *EditWnd
        bar:      *MiniBar
        hintLine: *HintLine
    }

    capture:          *Capture?
    late newMain:     *MainWnd
    editMode:         InPlaceEditMode = .Arrow
    editColor:        Color = Argb.Red
    editColorHilight: Color = Argb.Yellow
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
    // Builds the in-place editor of `capture` over the grabbed area.
    func create(capture: *Capture, main: *MainWnd, parent: *Wnd)->*InPlaceEditWnd
    {
        with let frame = createMainFrame(main, parent, capture)
        {
            .captureScale = captureMonitorScale(capture)
            .createBar(main)
            .createHintLine()
            .setupCapture(capture)
        }

        return frame
    }

    // Builds the in-place editor over the grabbed area: a second main window in in-place mode that
    // edits `capture` where it was taken.
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

    // The one bar under the zone: the tools, the colour, the destinations in words, Copy, and the
    // faint cross that leaves without keeping anything.
    mtd createBar(main: *MainWnd)
    {
        let texts   = appStrings()
        let metrics = .themeMetrics()
        let size    = metrics.menuPopup_IconSize
        .bar = MiniBar.create(.editWnd.editView)

        for tool in inPlaceEditTools()
        {
            with let button = .bar.addButton(main.icon(tool.icon, size), toolTip: tool.tip, flags: .Radio)
            {
                .userData = enumToUserData(tool.mode)
                .sigPressed += func|editor = me|(btn)
                {
                    editor.editMode = enumFromUserData'InPlaceEditMode(btn.userData)
                    editor.updateEditMode()
                }
            }

            if tool.mode == .Callout do
                button.iconPainter = func(btn, bc, pos, flags) { MainWnd.drawCalloutGlyph(btn, bc, pos, flags) }
        }

        .bar.addSeparator()
        with let swatch = .bar.addButton({}, toolTip: texts.ui_PropColor, flags: .Popup)
        {
            .setArrowPosition(.None)
            .iconPainter = func|editor = me|(btn, bc, pos, _)
            {
                let radius = btn.themeMetrics().menuPopup_IconSize * 0.5
                bc.painter.setParams(.Antialiased)
                bc.painter.fillCircle(pos.horzCenter(), pos.vertCenter(), radius, editor.toolColor())
                bc.painter.drawCircle(pos.horzCenter(), pos.vertCenter(), radius, btn.themeColors().strongLine, 1)
            }

            .sigPopupRequested += func|editor = me|(btn)
            {
                let popover = ColorPopover.open(assume cast(*IconButton, btn), appStrings().ui_PropColor, editor.toolColor(), &editor.newMain.recentColors)
                popover.sigColorChanged += func|editor, btn|(pop)
                {
                    if editor.editMode == .Marker do
                        editor.editColorHilight = pop.color
                    else do
                        editor.editColor = pop.color
                    editor.updateEditMode()
                    btn.invalidate()
                }
            }
        }

        .bar.addSeparator()
        .bar.addTextButton(texts.act_Pin).sigPressed += func|editor = me|(_) { editor.pin() }
        .bar.addTextButton(texts.act_InpEditor).sigPressed += func|editor = me|(_) { editor.toEditor() }
        .bar.addTextButton(texts.act_InpSave).sigPressed += func|editor = me|(_) { editor.save() }

        let copyWidth = Math.ceil(Painter.measureString(texts.act_InpCopy, .theme().createDefaultFont(metrics.defaultFontSize)).width + 2 * metrics.btnPush_TextMargin)
        with let copy = PushButton.create(.bar, texts.act_InpCopy, {0, 0, copyWidth, metrics.miniBar_ButtonSize}, form: .Strong)
        {
            .sigPressed += func|editor = me|(_) { editor.copy() }
        }

        .bar.addItem(copy)
        .bar.addButton(.theme().icon(.WndClose, size), toolTip: texts.tip_InpClose).sigPressed += func(_) { exitWithResult(false) }
    }

    // The keys of the editor at the foot of the screen, on the dimmed desktop.
    mtd createHintLine()
    {
        let texts = appStrings()
        with .hintLine = HintLine.create(.editWnd.editView)
        {
            .addHint(texts.key_Return, texts.hint_CopyClose)
            .addHint(Input.formatKeyShortcut(.Control, .S), texts.hint_Save)
            .addHint(strings().key_Escape, texts.hint_Cancel)
        }
    }

    // Returns the color the current tool draws with: the marker keeps a highlight color of its own.
    mtd toolColor()->Color => .editMode == .Marker ? .editColorHilight : .editColor

    mtd setupCapture(capture: *Capture)
    {
        capture.gizmo.sigHasChanged = func|editor = me|() { editor.placeBar() }
        .updateEditMode()
        .placeBar()
    }

    // Copies the zone with what is drawn on it, and closes.
    mtd copy()
    {
        with let capture = unwrap me.capture
        {
            .cropToGrab()
            .copyAll()
        }

        g_Main?.confirm(appStrings().msg_Copied)
        exitWithResult(false)
    }

    // Opens the zone with what is drawn on it in the editor.
    mtd toEditor()
    {
        .capture!.cropToGrab()
        exitWithResult(true)
    }

    // Saves the zone as an image file, and closes; a cancelled file box keeps the editor open.
    mtd save()
    {
        let fileName = .newMain.getSaveAsImageName()
        if fileName.isEmpty() do
            return
        .capture!.cropToGrab()
        .newMain.doSaveAsImage(fileName)
        exitWithResult(false)
    }

    // Pins the zone with what is drawn on it on the screen, where it was taken, and closes.
    mtd pin()
    {
        let capture = unwrap .capture
        let grab    = getGrabRect()
        capture.cropToGrab()
        PinnedCapture.open(capture.toImage(), Math.Rectangle{g_DesktopX + grab.x, g_DesktopY + grab.y, grab.width, grab.height})
        g_Main?.confirm(appStrings().msg_Pinned)
        exitWithResult(false)
    }

    func exitWithResult(grabDone: bool)
    {
        g_Exit     = true
        g_GrabDone = grabDone
    }

    mtd updateEditMode()
    {
        for item in .bar.items
        {
            if item.wnd is IconButton as button where button.flags.has(.Radio) do
                button.setChecked(enumFromUserData'InPlaceEditMode(button.userData) == .editMode)
        }

        .configureMainWindowEditMode()
    }

    // Sets the tool models of the in-place editor to sizes that read the same on the monitor that
    // was grabbed, whatever its density.
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
            case .Select:
                .editMode = .Selection

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

            case .Callout:
                .editMode                  = .Callout
                .mdlFormCallout.fontSize   = textSize * 0.6
                .mdlFormCallout.backColor  = me.editColor
                .mdlFormCallout.borderSize = 0

            case .Step:
                .editMode               = .Step
                .mdlFormStep.backColor  = me.editColor

            case .Marker:
                .editMode = .Draw
                .mdlFormDraw.borderSize  = markerSize
                .mdlFormDraw.borderColor = me.editColorHilight.withAlpha(160)
            }
        }
    }

    // Hangs the bar under the zone, or above it, or inside its foot when the screen has room on
    // neither side. The bar is a child of the edit view, so it takes the very rectangle the view
    // draws the capture into: one conversion, and the bar cannot drift away from the zone.
    mtd placeBar()
    {
        .bar.showNear(.editWnd.editView.getCaptureRect(), below: true)
    }
}

impl IWnd for InPlaceEditWnd
{
    // Enter copies and closes, Ctrl+S saves, Escape leaves without keeping anything.
    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        evt.accepted = false
        if evt.kind != .Pressed do
            return

        switch
        {
        case evt.key == .Escape:
            exitWithResult(false)
        case evt.key == .Return and evt.modifiers == .None:
            .copy()
        case evt.key == .S and evt.modifiers == .Control:
            .save()
        default:
            return
        }

        evt.accepted = true
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

        .width, .widthOrg    = .backImg.width
        .height, .heightOrg  = .backImg.height
        .backImagePos        = {}
        .gizmo.sigHasChanged = null
        .inPlaceEdit         = false
        .dirtyBackImg        = true
        .selection.clear()
    }
}
