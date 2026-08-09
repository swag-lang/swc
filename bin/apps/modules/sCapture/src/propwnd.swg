// The style cells of the panel head: one square each, holding a real sample of what the cell
// sets, at the toolbar size of the application chart. The surrounding air is what separates
// one cell from the next, so none of them needs a border to say where it ends.
//
// The name each cell used to print above its sample is on its tooltip now. Stacked, it made
// every cell twice as tall as its content to carry a word the sample already shows, and
// turned the head of the panel into a ribbon.
const StyleCellSize  = 48.0
const StyleGlyphSize = 26.0
const StyleCellGap   = 12.0

const CapSize  = 6.0
const DashSize = 6.0

// Geometry of the popups the style cells open. A popup is sized from what it lists, so a
// style added to an enum widens or lengthens its own list instead of falling outside it.
const PopupRowHeight    = 36.0     // One row of the dash list.
const PopupCapRowHeight = 44.0     // One row of the line-end list; its samples need the room.
const PopupCellSize     = 48.0     // One square cell of the shape list.
const PopupPadding      = 6.0      // Air the list keeps inside its frame.
const PopupSpacing      = 5.0      // Gap a stack and a wrap layout leave between two items by default.
const PopupFrameInset   = 5.0      // Room the frame itself takes around its view (frameWnd_SquarePadding).

// Room `count` items of `size` need along one axis, the air around them included.
//
// Every popup here is sized through this: written by hand, a dimension stopped matching its
// list the day a style was added to an enum, and the last entry fell outside the frame.
func popupExtent(count, size: f32)->f32
{
    return count * size + Math.max(count - 1, 0) * PopupSpacing + 2 * PopupPadding + 2 * PopupFrameInset
}

// The enum popup buttons stash the value they represent in the untyped 'userData'
// slot of the widget; these two helpers keep the double cast in one place.
func(T) enumToUserData(value: T)->*void        => cast(*void) cast(u64) value
func(T) enumFromUserData(data: #null *void)->T => cast(T) cast(u64) data

// The ellipse/rectangle/round-rectangle glyph painted by the shape and step
// buttons and by their popups.
func drawShapeGlyph(painter: *Painter, kind: FormShapeKind, pos: Math.Rectangle, color: Color)
{
    var rect = pos
    rect.inflate(-(pos.width - StyleGlyphSize) * 0.5, -(pos.height - StyleGlyphSize) * 0.5)
    rect.x     = rect.horzCenter() - rect.height * 0.5
    rect.width = rect.height

    // The stroke follows the glyph: kept at the weight the larger cell used, it closes the
    // counter of the shape and the sample reads as a filled blob.
    let stroke = Math.max(2.0, StyleGlyphSize * 0.15)

    switch #complete kind
    {
    case .Ellipse:
        let radius = rect.width * 0.5
        painter.drawEllipse(pos.horzCenter(), pos.vertCenter(), radius, radius, color, stroke)

    case .Rectangle:
        painter.drawRect(rect, color, stroke)

    case .RoundRectangle:
        painter.drawRoundRect(rect, 5, 5, color, stroke)
    }
}

// The tool properties panel. The exotic editors (color swatches, shape/cap/dash popup
// buttons...) are hand-built rows in 'topLayout'; every plain field (sliders, checkboxes,
// combos) is generated below them by a Properties grid from the attributes carried by the
// form fields (see BaseForm), with the edits recorded into the capture's own undo
// timeline. The compact x/y and w/h rows are hand-appended at the end of the grid.
struct PropWnd
{
    using frameWnd: FrameWnd
    #[Swag.Late]
    {
        topLayout: *StackLayoutCtrl
        grid:      *Properties
        main:      *MainWnd
    }

    // Concrete type bound to the grid (BaseForm for an heterogeneous selection)
    gridBindType: typeinfo = undefined

    // Set when a change handler needs the whole panel rebuilt: done on the next frame,
    // never from inside the grid's own change notification.
    needRebuild: bool
}

impl PropWnd
{
    mtd hasRealSelection()->bool
    {
        let capture = .main.getCapture()
        return capture and !capture.selection.isEmpty()
    }

    mtd getSelectedBaseForm()->*BaseForm
    {
        let capture = .main.getCapture()
        if !capture or capture.selection.isEmpty()
        {
            let iform = .main.editModeToModel(.main.editMode)
            return cast(*BaseForm) @dataof(iform)
        }

        return capture.getSelectedBaseForm()!
    }

    mtd getSelectedFormType()->typeinfo
    {
        let capture = .main.getCapture()
        if !capture or capture.selection.isEmpty()
        {
            let iform = .main.editModeToModel(.main.editMode)
            return @kindof(iform)
        }

        return capture.getSelectedFormType()!
    }

    mtd pushTypedValue(val: u32, type: typeinfo, name: string, first: bool, common = false)
    {
        let capture = .main.getCapture()

        // Change model
        if !capture or !capture.selection.count
        {
            let form   = .getSelectedBaseForm()
            let field  = Reflection.findField(type, name)!
            var valU32 = val
            Reflection.writeFieldValue(form, field, &valU32)
        }

        // Change selection
        else
        {
            if !first do
                capture.undo()
            let undo = capture.newUndo(.SetTypedValue)
            undo.valU32 = val
            if !common do
                undo.mdlType = type
            undo.valRef = Reflection.findField(type, name)!
            capture.pushUndo(undo)
        }

        .main.quickWnd.updateSelection()
        .main.editWnd.invalidate()
    }

    // One square style cell. `tip` names what the cell sets; the sample inside it shows the
    // current value, so the name is only needed when a reader asks for it.
    func createStyleButton(stack: *Wnd, tip: string)->*IconButton
    {
        with let btn = IconButton.create(stack, {}, {0, 0, StyleCellSize, StyleCellSize})
        {
            .setForm(.Rectangle)
            .style.addStyleSheetColors("btnIcon_Bk                  $veilSoft")
            .style.addStyleSheetColors("btnIcon_HotBk               $veilMedium")
            .style.addStyleSheetColors("btnIcon_PressedBk           $veilStrong")
            .style.addStyleSheetColors("btnIcon_CheckedPressedIcon  $btnIcon_Text")
            .style.addStyleSheetColors("btnIcon_CheckedPressedText  $btnIcon_Text")

            .updateFlags(.Popup | .Toggle)
            .setArrowPosition(.None)
            .setCheckIndicator(.None)
            .toolTip = tip
        }

        return btn
    }

    func createColorPicker(btn: *IconButton, color: Color)->*ColorPickerCtrl
    {
        let frame = btn.createAnchorPopup(356, 382)
        with var pal: Array'Color
        {
            .add(Argb.White)
            .add(Argb.Gray)
            .add(Argb.Black)
            .add(ColorRed)
            .add(ColorGreen)
            .add(ColorBlue)
            .add(ColorYellow)
            .add(Argb.Purple)
        }

        let picker = ColorPickerCtrl.createWithPalette(frame, {8, 54}, pal)
        picker.setColor(color)
        return picker
    }

    // Shared by the shape and step buttons: 'type' is the concrete form type and
    // 'fieldName' its FormShapeKind field, read back through reflection so both
    // forms go through the same popup.
    mtd createPopupShapeKind(btn: *IconButton, type: typeinfo, fieldName: string)
    {
        let cells  = cast(f32) @countof(FormShapeKind)
        let frame  = btn.createAnchorPopup(popupExtent(cells, PopupCellSize), popupExtent(1, PopupCellSize))
        let layout = frame.createView'WrapLayoutCtrl()
        layout.itemWidth, layout.itemHeight = PopupCellSize
        layout.spacing = PopupSpacing
        layout.padding = PopupPadding

        func selectedKind(prop: *PropWnd, type: typeinfo, fieldName: string)->FormShapeKind
        {
            var val: u32
            let field = Reflection.findField(type, fieldName)!
            Reflection.readFieldValue(&val, field, prop.getSelectedBaseForm())
            return cast(FormShapeKind) val
        }

        func updateBtnState(prop: *PropWnd, layout: *Wnd, type: typeinfo, fieldName: string)
        {
            let cur = selectedKind(prop, type, fieldName)
            for c in layout.children
            {
                let btn  = cast(*IconButton) c
                let kind = enumFromUserData'FormShapeKind(btn.userData)
                btn.setChecked(cur == kind)
                btn.invalidate()
            }
        }

        let cur = selectedKind(me, type, fieldName)

        for [i] in @countof(FormShapeKind)
        {
            let btn0 = IconButton.create(frame.view!, {}, {0, 0, PopupCellSize, PopupCellSize})
            btn0.userData = enumToUserData(i)
            btn0.setForm(.Rectangle)
            btn0.updateFlags(.Radio)
            if cur == i do
                btn0.setChecked(true)

            btn0.iconPainter = func(btn, bc, pos, flags)
            {
                bc.painter.setParams(.Antialiased)
                let color = flags & .Checked ? btn.themeColors().btnIcon_CheckedIcon : btn.themeColors().btnIcon_Icon
                drawShapeGlyph(bc.painter, enumFromUserData'FormShapeKind(btn.userData), pos, color)
            }

            btn0.sigPressed += func|prop = me, layout, type, fieldName|(btn)
            {
                let kind = enumFromUserData'u64(btn.userData)
                prop.pushTypedValue(cast() kind, type, fieldName, true)
                updateBtnState(prop, layout, type, fieldName)
            }
        }

        layout.computeLayout()
    }

    // One popup for both line ends: 'begin' selects the beginCap or endCap field
    // and mirrors the sample stroke accordingly.
    mtd createPopupCapStyle(btn: *IconButton, begin: bool)
    {
        let frame  = btn.createAnchorPopup(120, popupExtent(cast(f32) @countof(LineCapStyle), PopupCapRowHeight))
        let layout = StackLayoutCtrl.create(frame, .Top)
        frame.setView(layout)

        let fieldName = begin ? #nameof(FormLine.beginCap) : #nameof(FormLine.endCap)

        func selectedCap(prop: *PropWnd, begin: bool)->LineCapStyle
        {
            let curSel = cast(*FormLine) prop.getSelectedBaseForm()
            return begin ? curSel.beginCap : curSel.endCap
        }

        func updateBtnState(prop: *PropWnd, layout: *Wnd, begin: bool)
        {
            let cur = selectedCap(prop, begin)
            for c in layout.children
            {
                let btn = cast(*IconButton) c
                let cap = enumFromUserData'LineCapStyle(btn.userData)
                btn.setChecked(cur == cap)
                btn.invalidate()
            }
        }

        let cur = selectedCap(me, begin)
        for i in LineCapStyle
        {
            let btn0 = IconButton.create(layout, {}, {0, 0, 0, PopupCapRowHeight})
            btn0.userData = enumToUserData(i)
            btn0.setForm(.Rectangle)
            btn0.updateFlags(.Radio)
            btn0.setChecked(cur == i)

            btn0.iconPainter = func|begin|(btn, bc, pos, flags)
            {
                bc.painter.setParams(.Antialiased)
                var rect = pos
                rect.inflate(-9, -9)
                let cap   = enumFromUserData'LineCapStyle(btn.userData)
                let color = flags & .Checked ? btn.themeColors().btnIcon_CheckedIcon : btn.themeColors().btnIcon_Icon
                var pen   = Pen.createSolid(color, CapSize)
                if begin
                {
                    pen.begCapStyle = cap
                    pen.endCapStyle = .None
                    let {?, l0} = Painter.capStyleExtent(cap, CapSize, pen.capBegScaleX)
                    rect.moveLeft(l0)
                }
                else
                {
                    pen.begCapStyle = .None
                    pen.endCapStyle = cap
                    let {?, l0} = Painter.capStyleExtent(cap, CapSize, pen.capEndScaleX)
                    rect.moveRight(-l0)
                }

                bc.painter.drawLine(rect.x, rect.vertCenter(), rect.right(), rect.vertCenter(), pen)
            }

            btn0.sigPressed += func|prop = me, layout, fieldName, begin|(btn)
            {
                let kind = enumFromUserData'u64(btn.userData)
                prop.pushTypedValue(cast() kind, FormLine, fieldName, true)
                updateBtnState(prop, layout, begin)
            }
        }

        layout.computeLayout()
    }

    mtd createPopupDashStyle(btn: *IconButton)
    {
        // The frame is as tall as what it lists. Written by hand, the height stopped
        // matching the list the day a style was added and the last row fell outside it.
        var count = 0'f32
        for i in DashStyle where i != .Pattern do
            count += 1

        let frame  = btn.createAnchorPopup(180, popupExtent(count, PopupRowHeight))
        let layout = StackLayoutCtrl.create(frame, .Top)
        frame.setView(layout)

        func updateBtnState(prop: *PropWnd, layout: *Wnd)
        {
            let curSel = prop.getSelectedBaseForm()
            for c in layout.children
            {
                let btn  = cast(*IconButton) c
                let dash = enumFromUserData'DashStyle(btn.userData)
                btn.setChecked(curSel.dashStyle == dash)
                btn.invalidate()
            }
        }

        let curSel = .getSelectedBaseForm()
        for i in DashStyle
        {
            if i == .Pattern do
                continue

            let btn0 = IconButton.create(layout, {}, {0, 0, 0, PopupRowHeight})
            btn0.userData = enumToUserData(i)
            btn0.setForm(.Rectangle)
            btn0.updateFlags(.Radio)
            btn0.setChecked(curSel.dashStyle == i)

            btn0.iconPainter = func|prop = me|(btn, bc, pos, flags)
            {
                bc.painter.setParams(.Antialiased)
                var rect = pos
                rect.inflate(-9, -9)
                var dash  = enumFromUserData'DashStyle(btn.userData)
                let color = flags & .Checked ? btn.themeColors().btnIcon_CheckedIcon : btn.themeColors().btnIcon_Icon
                var pen   = Pen.createDash(dash, color, DashSize)
                pen.dashBlankScale = 0.25
                bc.painter.drawLine(rect.x, rect.vertCenter(), rect.right(), rect.vertCenter(), pen)
            }

            btn0.sigPressed += func|prop = me, layout|(btn)
            {
                let kind = enumFromUserData'u64(btn.userData)
                prop.pushTypedValue(cast() kind, BaseForm, #nameof(BaseForm.dashStyle), true, true)
                updateBtnState(prop, layout)
            }
        }

        layout.computeLayout()
    }

    mtd propBorderColor(stack: *Wnd)
    {
        let curSel = cast(*FormText) .getSelectedBaseForm()
        if curSel.subKind == .Highlight or curSel.subKind == .PixSel do
            return

        var tip = appStrings().ui_PropOutline
        switch .getSelectedFormType()
        {
        case FormLine, FormArrow, FormDraw: tip = appStrings().ui_PropColor
        case FormStep: tip = appStrings().act_Text
        }

        let btn = createStyleButton(stack, tip)

        btn.iconPainter = func|prop = me|(btn, bc, pos, flags)
        {
            bc.painter.setParams(.Antialiased)
            let curSel = prop.getSelectedBaseForm()
            var rect   = pos
            rect.x = rect.horzCenter() - StyleGlyphSize * 0.5
            rect.y = rect.vertCenter() - StyleGlyphSize * 0.5
            rect.width, rect.height = StyleGlyphSize
            if !curSel.borderColor.isOpaque() do
                bc.painter.drawRect(rect, Pen.createHatch(.CheckBoardLarge, Argb.DarkGray, 5))
            bc.painter.drawRect(rect, curSel.borderColor, 5)
        }

        btn.sigPopupRequested += func|prop = me|(btn)
        {
            let curSel = prop.getSelectedBaseForm()
            var picker = createColorPicker(btn, curSel.borderColor)

            // Defer the undo entry until the color actually changes: `first` (closure-owned) is
            // true only on the first change, so opening then closing without picking leaves no
            // no-op undo entry, while later changes still replace the previous one (first = false).
            picker.sigColorChanged += func|prop, btn, first = true|(pk)
            {
                prop.pushTypedValue(pk.color().argb, BaseForm, #nameof(BaseForm.borderColor), first, true)
                first = false
                btn.invalidate()
            }
        }
    }

    mtd propBackColor(stack: *Wnd)
    {
        let curSel = .getSelectedBaseForm()
        if curSel.subKind != .PixSel
        {
            let curSelType = .getSelectedFormType()
            if curSelType == FormLine or
               curSelType == FormArrow or
               curSelType == FormDraw do
                return

            if curSelType == FormImage
            {
                let imgSel = cast(*FormImage) curSel
                if imgSel.kind != .Image do
                    return
            }
        }

        let btn = createStyleButton(stack, appStrings().ui_PropFill)
        btn.iconPainter = func|prop = me|(btn, bc, pos, flags)
        {
            bc.painter.setParams(.Antialiased)
            var curSel = prop.getSelectedBaseForm()!
            var rect   = pos
            rect.x = rect.horzCenter() - StyleGlyphSize * 0.5
            rect.y = rect.vertCenter() - StyleGlyphSize * 0.5
            rect.width, rect.height = StyleGlyphSize
            var backCol = curSel.subKind == .PixSel ? g_Main!.pixSelFillCol : curSel.backColor
            if !backCol.isOpaque() do
                bc.painter.fillRect(rect, Brush.createHatch(.CheckBoardLarge, Argb.DarkGray))
            bc.painter.fillRect(rect, backCol)
        }

        btn.sigPopupRequested += func|prop = me|(btn)
        {
            var curSel  = prop.getSelectedBaseForm()!
            var backCol = curSel.subKind == .PixSel ? g_Main!.pixSelFillCol : curSel.backColor
            var picker  = createColorPicker(btn, backCol)
            if curSel.subKind == .PixSel
            {
                picker.sigColorChanged += func|btn|(pk)
                {
                    let mainWnd = g_Main!
                    mainWnd.pixSelFillCol = pk.color()
                    btn.invalidate()
                }
            }
            else
            {
                // Defer the undo entry until the color actually changes: `first` (closure-owned) is
                // true only on the first change, so opening then closing without picking leaves no
                // no-op undo entry, while later changes still replace the previous one (first = false).
                picker.sigColorChanged += func|prop, btn, first = true|(pk)
                {
                    prop.pushTypedValue(pk.color().argb, BaseForm, #nameof(BaseForm.backColor), first, true)
                    first = false
                    btn.invalidate()
                }
            }
        }
    }

    mtd propShape(stack: *Wnd)
    {
        let curSelType = .getSelectedFormType()
        if curSelType != FormShape do
            return
        let curSel = .getSelectedBaseForm()
        if curSel.subKind == .PixSel do
            return

        let btn = createStyleButton(stack, appStrings().act_Shape)
        btn.iconPainter = func|prop = me|(btn, bc, pos, flags)
        {
            bc.painter.setParams(.Antialiased)
            let curSel = cast(*FormShape) prop.getSelectedBaseForm()
            drawShapeGlyph(bc.painter, curSel.kind, pos, btn.themeColors().btnIcon_Icon)
        }

        btn.sigPopupRequested += func|prop = me|(btn) { prop.createPopupShapeKind(btn, FormShape, #nameof(FormShape.kind)) }
    }

    mtd propStep(stack: *Wnd)
    {
        let curSelType = .getSelectedFormType()
        if curSelType != FormStep do
            return

        let btn = createStyleButton(stack, appStrings().act_Shape)
        btn.iconPainter = func|prop = me|(btn, bc, pos, flags)
        {
            bc.painter.setParams(.Antialiased)
            let curSel = cast(*FormStep) prop.getSelectedBaseForm()
            drawShapeGlyph(bc.painter, curSel.kind, pos, btn.themeColors().btnIcon_Icon)
        }

        btn.sigPopupRequested += func|prop = me|(btn) { prop.createPopupShapeKind(btn, FormStep, #nameof(FormStep.kind)) }
    }

    mtd propStartCapStyle(stack: *Wnd)
    {
        let curSelType = .getSelectedFormType()
        if curSelType != FormLine and curSelType != FormArrow do
            return

        let btn = createStyleButton(stack, appStrings().ui_PropStart)

        btn.iconPainter = func|prop = me|(btn, bc, pos, flags)
        {
            var curSel = cast(*FormLine) prop.getSelectedBaseForm()
            var rect   = pos
            rect.inflate(-9, -9)
            var pen = Pen.createSolid(btn.themeColors().btnIcon_Icon, CapSize)
            pen.begCapStyle = curSel.beginCap
            pen.endCapStyle = .None
            let {?, l0} = Painter.capStyleExtent(curSel.beginCap, CapSize, pen.capBegScaleX)
            rect.moveLeft(l0)

            bc.painter.setParams(.Antialiased)
            bc.painter.drawLine(rect.x, rect.vertCenter(), rect.right(), rect.vertCenter(), pen)
        }

        btn.sigPopupRequested += func|prop = me|(btn) { prop.createPopupCapStyle(btn, begin: true) }
    }

    mtd propEndCapStyle(stack: *Wnd)
    {
        let curSelType = .getSelectedFormType()
        if curSelType != FormLine and curSelType != FormArrow do
            return

        let btn = createStyleButton(stack, appStrings().ui_PropEnd)
        btn.iconPainter = func|prop = me|(btn, bc, pos, flags)
        {
            let curSel = cast(*FormLine) prop.getSelectedBaseForm()
            var rect   = pos
            rect.inflate(-9, -9)
            var pen = Pen.createSolid(btn.themeColors().btnIcon_Icon, CapSize)
            pen.begCapStyle = .None
            pen.endCapStyle = curSel.endCap
            let {?, l0} = Painter.capStyleExtent(curSel.endCap, CapSize, pen.capEndScaleX)
            rect.moveRight(-l0)

            bc.painter.setParams(.Antialiased)
            bc.painter.drawLine(rect.x, rect.vertCenter(), rect.right(), rect.vertCenter(), pen)
        }

        btn.sigPopupRequested += func|prop = me|(btn) { prop.createPopupCapStyle(btn, begin: false) }
    }

    mtd propDashStyle(stack: *Wnd)
    {
        let curSelType = .getSelectedFormType()
        if curSelType != FormShape and curSelType != FormLine and curSelType != FormArrow and curSelType != FormPolygon do
            return

        let curSel = cast(*FormText) .getSelectedBaseForm()
        if curSel.subKind == .Highlight or curSel.subKind == .PixSel do
            return

        let btn = createStyleButton(stack, appStrings().ui_PropDash)
        btn.iconPainter = func|prop = me|(btn, bc, pos, flags)
        {
            bc.painter.setParams(.Antialiased)
            var curSel = prop.getSelectedBaseForm()
            var rect   = pos
            rect.inflate(-10, -10)
            var pen = Pen.createDash(curSel.dashStyle, btn.themeColors().btnIcon_Icon, DashSize)
            pen.dashBlankScale = 0.25
            bc.painter.drawLine(rect.x, rect.vertCenter(), rect.right(), rect.vertCenter(), pen)
        }

        btn.sigPopupRequested += func|prop = me|(btn) { prop.createPopupDashStyle(btn) }
    }

    // The step type combo is generated by the grid (FormStep.typeIndex attribute);
    // only the "reset the global counter" action needs a hand-made row.
    mtd propNextStep()
    {
        let curSelType = .getSelectedFormType()
        if curSelType != FormStep do
            return

        let stack = Wnd.create'Wnd(.topLayout, {0, 0, 0, .themeMetrics().comboBox_Height})

        with let btn = PushButton.create(stack, appStrings().ui_ResetSteps, {0, 0, 60})
        {
            .margin.x      = 5
            .dockStyle     = .Right
            .toolTip       = appStrings().tip_ResetSteps
            btn.sigPressed += func|prop = me|(btn)
            {
                // The button outlives the panel build; the capture may be gone by the
                // time it is pressed, so guard instead of assuming it is still there.
                let capture = prop.main.getCapture()
                if !capture do
                    return
                capture.nextStepIndex = 1
            }
        }
    }

    func editText(main: *MainWnd, curText: String)->String
    {
        var editOptions: EditDlgOptions
        editOptions.title   = appStrings().dlg_TitleEnterText
        editOptions.message = "Press Shift+Enter to add a new line"
        editOptions.text    = curText.toString()
        let dlg = EditDlg.createMultiLine(main.surface!, editOptions)
        if main.inPlaceEdit do
            dlg.surface?.setTopMost()

        if dlg.doModal() != Dialog.BtnOk do
            return curText
        let capture = main.getCapture()!
        let undo    = capture.newUndo(.SetText)
        undo.text = dlg.text()
        capture.pushUndo(undo)
        return undo.text
    }

    // Text-fill color swatch for a callout (the bubble fill/border reuse the generic
    // BaseForm color buttons; only the inner text color is callout-specific).
    mtd propCalloutText(stack: *Wnd)
    {
        if .getSelectedFormType() != FormCallout do
            return

        let btn = createStyleButton(stack, appStrings().act_Text)
        btn.iconPainter = func|prop = me|(btn, bc, pos, flags)
        {
            bc.painter.setParams(.Antialiased)
            let curSel = cast(*FormCallout) prop.getSelectedBaseForm()
            var rect   = pos
            rect.x = rect.horzCenter() - StyleGlyphSize * 0.5
            rect.y = rect.vertCenter() - StyleGlyphSize * 0.5
            rect.width, rect.height = StyleGlyphSize
            if !curSel.textColor.isOpaque() do
                bc.painter.fillRect(rect, Brush.createHatch(.CheckBoardLarge, Argb.DarkGray))
            bc.painter.fillRect(rect, curSel.textColor)
        }

        btn.sigPopupRequested += func|prop = me|(btn)
        {
            let curSel = cast(*FormCallout) prop.getSelectedBaseForm()
            var picker = createColorPicker(btn, curSel.textColor)
            picker.sigColorChanged += func|prop, btn, first = true|(pk)
            {
                prop.pushTypedValue(pk.color().argb, FormCallout, #nameof(FormCallout.textColor), first)
                first = false
                btn.invalidate()
            }
        }
    }

    mtd propPixSel()
    {
        let curSel = .getSelectedBaseForm()
        if curSel.subKind != .PixSel do
            return

        let topLayout = .topLayout!
        discard PushButton.create(topLayout, "", id: ActionPixSel.Fill)
        discard PushButton.create(topLayout, "", id: ActionPixSel.SmartFill)
        discard PushButton.create(topLayout, "", id: ActionPixSel.Clear)
        discard PushButton.create(topLayout, "", id: ActionPixSel.SmartMove)
    }

    // Position/size boxes: two compact hand-made rows (x/y and w/h) appended right after
    // the generated grid content, separated like a category. Box forms only. X/Y may be
    // negative (a form may sit outside the canvas).
    mtd propXY()
    {
        if !.hasRealSelection() do
            return
        let t = .getSelectedFormType()
        if t != FormShape and t != FormText and t != FormCallout do
            return
        let curSel = .getSelectedBaseForm()

        func addBox(prop: *PropWnd, parent: *Wnd, label: String, name: string, value: s32, signed: bool)
        {
            let edit = EditCtrl.create(parent, label, Format.toString("%", value), flags: .ReleaseFocusOnEnterOrEscape)
            edit.setLayoutMetrics(15, 0)

            // A coordinate is machine data, so it is set in the fixed-width theme family:
            // the digits then line up between the four boxes and stop shifting as they
            // change width.
            edit.edit.style.setFont(prop.theme().res.fontDefaultFs)

            if signed do
                edit.edit.setSignedIntegerRange()
            else do
                edit.edit.setUnsignedIntegerRange(1, 10000)
            edit.edit.sigFocusLost += func|prop, name|(ed)
            {
                let {v, ?, ?} = catch StrConv.parseS32(ed.text())
                prop.pushTypedValue(v, BaseForm, name, true, true)
            }
        }

        // 'name' must be a view of storage that outlives the grid (a literal): the
        // TypeValue below keeps the view, and a by-value String parameter would hand
        // it a dangling pointer into this frame's small-string storage.
        func addRow(prop: *PropWnd, name: string)->*Wnd
        {
            let v    = Swag.TypeValue{name: name}
            let item = prop.grid.addItem(v, null, null, 40, .None)

            // No NoFocus: the rows embed edit boxes, so they stay keyboard-navigable
            item.flags.add(.NoSeparator)
            return StackLayoutCtrl.create(item.line!, .HorizontalFit, {0, 0, 0, 40})
        }

        // Each row names itself, so no category separator sits above them: a heading
        // repeating what the two rows already say is one more line to step over.
        with let l0 = addRow(me, appStrings().ui_PropPosition)
        {
            addBox(me, l0, "x", #nameof(BaseForm.x), curSel.x, true)
            addBox(me, l0, "y", #nameof(BaseForm.y), curSel.y, true)
        }

        with let l1 = addRow(me, appStrings().ui_PropSize)
        {
            addBox(me, l1, "w", #nameof(BaseForm.w), curSel.w, false)
            addBox(me, l1, "h", #nameof(BaseForm.h), curSel.h, false)
        }

        .grid.endAppendRows()
    }

    // Bind the property grid to the current selection (or to the tool model when nothing
    // is selected). The grid builds one row per attributed field of the bound type — see
    // the Properties attributes on the form structs — and edits every selected instance
    // at once, recording each change into the capture's own undo timeline.
    mtd bindGrid()
    {
        let capture = .main.getCapture()
        var bases: Array'(#null *u8)

        if !capture or !capture.selection.count
        {
            // Tool model: direct edition, no undo (as before)
            let mdl = .main.editModeToModel(.main.editMode)
            .gridBindType = @kindof(mdl)
            bases.add(cast(#null *u8) @dataof(mdl))
            .grid.setExternalUndoMgr(null)
            .grid.setUndoEnabled(false)
        }
        else
        {
            // Common concrete type of the selection: exact when homogeneous, FormLine for
            // a line/arrow mix (an arrow embeds a line), BaseForm otherwise
            var allSame  = true
            var lineOnly = true
            var firstType: #null typeinfo

            foreachSelected'BaseForm(capture, capture.selection)
            {
                let t = @kindof(itf)
                if !firstType do
                    firstType = t
                elif t != firstType do
                    allSame = false
                if t != FormLine and t != FormArrow do
                    lineOnly = false
                bases.add(cast(#null *u8) form)
            }

            if allSame do
                .gridBindType = firstType orelse #typeof(BaseForm)
            elif lineOnly do
                .gridBindType = FormLine
            else do
                .gridBindType = BaseForm

            .grid.setExternalUndoMgr(&capture.undoMgr)
            .grid.setUndoEnabled(true)
        }

        .grid.addStructMulti(.gridBindType, cast([..] *u8) bases.toSlice(), null, onlyNamed: true)

        // The generated border-size slider serves every form as "Thickness"; a text form
        // edits its glyph outline instead: matching label and a much thinner range. The
        // slider keeps a normalized position, so re-set the value after the new range.
        if .gridBindType == FormText
        {
            for item in .grid.items
            {
                let it = item!
                if it.typeValue.name != #nameof(BaseForm.borderSize) or !@isset(it.sliderBox) do
                    continue
                let sliderBox = it.sliderBox
                sliderBox.label.setText(appStrings().ui_Outline)
                sliderBox.setSignedBounds(cast() MinTextBorderSize, cast() MaxTextBorderSize)
                sliderBox.setValueWithoutGesture(.getSelectedBaseForm()!.borderSize)
            }
        }
    }

    mtd selectionHasChanged()
    {
        for it in .topLayout.children do
            it.destroy()
        .grid.clear()

        if !.getSelectedBaseForm()
        {
            .applyLayout()
            return
        }

        // The cells start at the panel margin like every row under them, instead of floating
        // in the middle of the column: a group centred on its own is a third alignment on a
        // surface that already has one.
        let stack0 = StackLayoutCtrl.create(.topLayout!, .HorizontalCenter, {0, 0, 0, StyleCellSize})
        stack0.spacing = StyleCellGap
        .propBackColor(stack0)
        .propBorderColor(stack0)
        .propCalloutText(stack0)
        .propShape(stack0)
        .propStep(stack0)
        if stack0.children.count == 0 do
            stack0.destroyNow()

        let stack1 = StackLayoutCtrl.create(.topLayout!, .HorizontalCenter, {0, 0, 0, StyleCellSize})
        stack1.spacing = StyleCellGap
        .propStartCapStyle(stack1)
        .propDashStyle(stack1)
        .propEndCapStyle(stack1)
        if stack1.children.count == 0 do
            stack1.destroyNow()

        .propNextStep()
        .propPixSel()

        .bindGrid()
        .propXY()

        .topLayout.computeLayout()
        .applyLayout()

        let capture = .main.getCapture()
        if capture do
            capture.editView?.setFocus()
    }

    func create(parent: *Wnd, main: *MainWnd)->*PropWnd
    {
        with let prop = Wnd.create'PropWnd(parent, {0, 0, 0, 300})
        {
            .backgroundStyle = .Window

            .topLayout              = StackLayoutCtrl.create(prop)
            .topLayout.mode         = .Top
            .topLayout.fitToContent = true
            .topLayout.dockStyle    = .Top
            .topLayout.spacing      = StyleCellGap

            // The head keeps the margin of the panel on both edges, and a block of air
            // between itself and the rows the grid generates under it.
            .topLayout.padding = {12, 16, 12, 16}

            .grid           = Properties.create(prop, kind: .Panel)
            .grid.dockStyle = .Center
            .grid.setRevertButtonsVisible(false)

            // Most specific first: a form edits its own fields (text, caps, round...)
            // before the BaseForm style shared by every form
            .grid.setUsingFieldsLast(true)

            // Always show a small vertical bar so the row width does not jump with the content
            .grid.scrollWnd.updateFlags(.AlwaysShowVertical | .CompactBars)

            .main = main
            .grid.setNotify(prop)
        }

        // The panel defers a rebuild to the next frame (see `needRebuild`), so it has to ask for
        // the per-frame event: the one a surface view is sent before the loop starts is a startup
        // hook, and this panel is not a surface view. Asking is what makes the deferral run at
        // all — the registration used to be internal and unreachable, so it never did.
        prop.app().registerFrameEvent(prop)
        return prop
    }
}

// Host hooks of the property grid: dynamic visibility of the generated rows (rules the
// attributes cannot express: selection kind, PixSel/Highlight sub-kinds, dependent
// fields) and the reaction to every edit.
impl IPropertyNotify for PropWnd
{
    mtd impl isItemVisible(list: *Properties, item: *PropertiesItem)->bool
    {
        let base = .getSelectedBaseForm()
        if !base do
            return true

        // Category separators hide by themselves: the grid force-shows an item's parents,
        // so a separator appears exactly when its group has at least one visible row.
        if item.flags.has(.Category) do
            return false

        let name = item.typeValue.name

        switch name
        {
        case #nameof(BaseForm.borderSize):
            return .gridBindType != FormStep and base.subKind != .PixSel

        case #nameof(BaseForm.joinStyle):
            return (.gridBindType == FormText or .gridBindType == FormPolygon) and
                   base.subKind != .PixSel

        case #nameof(BaseForm.alpha), #nameof(BaseForm.paintShadow):
            return base.subKind != .PixSel

        case #nameof(BaseForm.scale):
            return .gridBindType == FormText

        case #nameof(BaseForm.rotate):
            return (.gridBindType == FormText or .gridBindType == FormShape or .gridBindType == FormImage) and
                   base.subKind == .None

        case #nameof(BaseForm.bezier):
            return (.gridBindType == FormLine or .gridBindType == FormArrow or .gridBindType == FormPolygon) and
                   base.subKind != .PixSel

        case #nameof(FormShape.roundSize):
            if .gridBindType == FormShape
            {
                let shape = cast(*FormShape) base
                return shape.kind == .RoundRectangle
            }

        case #nameof(FormImage.strength):
            if .gridBindType == FormImage
            {
                let img = cast(*FormImage) base
                return img.kind != .Image
            }
        }

        return true
    }

    mtd impl isEnumValueVisible(list: *Properties, item: *PropertiesItem, enumValue: Swag.TypeValue)->bool
    {
        // The join combo omits JoinStyle.None: no join drawn = notched corners on any
        // thick stroke, never what a sCapture form wants.
        if item.typeValue.name == #nameof(BaseForm.joinStyle) do
            return enumValue.name != #nameof(JoinStyle.None)

        return true
    }

    mtd impl itemHasChanged(list: *Properties, item: #null *PropertiesItem)
    {
        let capture = .main.getCapture()
        if capture and capture.selection.count
        {
            capture.updateModelFromSelection()
            capture.hasChanged()
        }

        .main.quickWnd.updateSelection()
        .main.editWnd.invalidate()

        // The image kind drives which rows and top buttons exist: rebuild the whole panel,
        // on the next frame (we are inside the grid's own change notification).
        if item and .gridBindType == FormImage and item.typeValue.name == #nameof(FormImage.kind) do
            .needRebuild = true
    }
}

impl IWnd for PropWnd
{
    // This impl shadows the whole FrameWnd one: forward its paint/resize methods
    mtd impl onBeforePaint(evt: *PaintEvent)
    {
        .frameWnd.IWnd.onBeforePaint(evt)
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        .frameWnd.IWnd.onPaint(evt)
    }

    mtd impl onAfterPaint(evt: *PaintEvent)
    {
        .frameWnd.IWnd.onAfterPaint(evt)
    }

    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        .frameWnd.IWnd.onResizeEvent(evt)
    }

    mtd impl onFrameEvent(evt: *FrameEvent)
    {
        if .needRebuild
        {
            .needRebuild = false
            .selectionHasChanged()
        }
    }

    // The panel is generated from attribute literals resolved when each row is built, and
    // the swatches beside it take their captions the same way, so the whole thing follows a
    // language switch by being built again.
    //
    // Built here and not through `needRebuild`: the deferral exists for a rebuild asked for
    // from inside the grid's own change notification, and a language notification arrives
    // from outside it.
    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged do
            .selectionHasChanged()
    }
}
