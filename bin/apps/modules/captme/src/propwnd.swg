const BtnColorWidth  = 68.0
const BtnColorHeight = 88.0
const BtnStyleWidth  = 88.0
const BtnStyleHeight = 68.0

const CapSize  = 8.0
const DashSize = 8.0


// The enum popup buttons stash the value they represent in the untyped 'userData'
// slot of the widget; these two helpers keep the double cast in one place.
func(T) enumToUserData(value: T)->*void => cast(*void) cast(u64) value
func(T) enumFromUserData(data: #null *void)->T => cast(T) cast(u64) data

// The ellipse/rectangle/round-rectangle glyph painted by the shape and step
// buttons and by their popups.
func drawShapeGlyph(painter: *Painter, kind: FormShapeKind, pos: Math.Rectangle, color: Color)
{
    var rect = pos
    rect.inflate(-9, -9)
    rect.x     = rect.horzCenter() - rect.height * 0.5
    rect.width = rect.height

    #[Swag.Complete]
    switch kind
    {
    case Ellipse:
        let radius = rect.width * 0.5
        painter.drawEllipse(pos.horzCenter(), pos.vertCenter(), radius, radius, color, 5)
    case Rectangle:
        painter.drawRect(rect, color, 5)
    case RoundRectangle:
        painter.drawRoundRect(rect, 5, 5, color, 5)
    }
}

// The tool properties panel. The exotic editors (color swatches, shape/cap/dash popup
// buttons...) are hand-built rows in 'topLayout'; every plain field (sliders, checkboxes,
// combos) is generated below them by a Properties grid from the attributes carried by the
// form fields (see BaseForm), with the edits recorded into the capture's own undo
// timeline. The compact x/y and w/h rows are hand-appended at the end of the grid.
struct PropWnd
{
    using frameWnd:     FrameWnd
    topLayout:          *StackLayoutCtrl
    grid:               *Properties
    main:               *MainWnd

    // Concrete type bound to the grid (BaseForm for an heterogeneous selection)
    gridBindType:       typeinfo

    // Set when a change handler needs the whole panel rebuilt: done on the next frame,
    // never from inside the grid's own change notification.
    needRebuild:        bool
}

impl PropWnd
{
    mtd hasRealSelection()->bool
    {
        let capture = .main.getCapture()
        if !capture or capture.selection.count == 0 do
            return false
        return true
    }

    mtd getSelectedBaseForm()->*BaseForm
    {
        let capture = .main.getCapture()
        if !capture or capture.selection.count == 0
        {
            let iform = .main.editModeToModel(.main.editMode)
            return cast(*BaseForm) @dataof(iform)
        }

        return assume capture.getSelectedBaseForm()
    }

    mtd getSelectedFormType()->typeinfo
    {
        let capture = .main.getCapture()
        if !capture or capture.selection.count == 0
        {
            let iform = .main.editModeToModel(.main.editMode)
            return @kindof(iform)
        }

        return assume capture.getSelectedFormType()
    }

    mtd pushTypedValue(val: u32, type: typeinfo, name: string, first: bool, common = false)
    {
        let capture = .main.getCapture()

        // Change model
        if !capture or !capture.selection.count
        {
            let form   = .getSelectedBaseForm()
            let field  = assume Reflection.getField(type, name)
            var valU32 = val
            Reflection.setFieldValue(form, field, &valU32, true)
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
            undo.valRef = Reflection.getField(type, name)
            capture.pushUndo(undo)
        }

        .main.quickWnd.updateSelection()
        .main.editWnd.invalidate()
    }

    func createArrowButton(stack: *Wnd, w, h: f32)->*IconButton
    {
        with let btn = IconButton.create(stack, {}, {0, 0, w, h})
        {
            .setForm(.RoundSquare)
            .style.addStyleSheetColors("btnIcon_Bk                  $lighterMedium")
            .style.addStyleSheetColors("btnIcon_HotBk               $lighterBig")
            .style.addStyleSheetColors("btnIcon_PressedBk           $lighterVeryBig")
            .style.addStyleSheetColors("btnIcon_CheckedPressedIcon  $btnIcon_Text")
            .style.addStyleSheetColors("btnIcon_CheckedPressedText  $btnIcon_Text")

            .iconBtnFlags.add(.Popup | .CheckableToggle)
            .arrowPos    = .Bottom
            .textPos     = .Top
            .checkedForm = .None
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
        let frame  = btn.createAnchorPopup(180, 66)
        let layout = frame.createView'WrapLayoutCtrl()
        layout.wrapWidth, layout.wrapHeight = 48
        layout.padding = 4

        func selectedKind(prop: *PropWnd, type: typeinfo, fieldName: string)->FormShapeKind
        {
            var val: u32
            let field = assume Reflection.getField(type, fieldName)
            Reflection.getFieldValue(&val, field, prop.getSelectedBaseForm(), true)
            return cast(FormShapeKind) val
        }

        func updateBtnState(prop: *PropWnd, layout: *Wnd, type: typeinfo, fieldName: string)
        {
            let cur = selectedKind(prop, type, fieldName)
            for c in layout.childs
            {
                let btn  = cast(*IconButton) c
                let kind = enumFromUserData'FormShapeKind(btn.userData)
                btn.isChecked = cur == kind
                btn.invalidate()
            }
        }

        let cur = selectedKind(me, type, fieldName)

        for i in @countof(FormShapeKind)
        {
            let btn0 = IconButton.create(frame.view, {})
            btn0.userData = enumToUserData(i)
            btn0.setForm(.RoundSquare)
            if cur == i do
                btn0.isChecked = true

            btn0.sigPaintIcon = func(btn, bc, pos, flags)
            {
                bc.painter.setParams(.Antialiased)
                let color = flags & .Checked ? btn.getThemeColors().btnIcon_CheckedIcon : btn.getThemeColors().btnIcon_Icon
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
        let frame  = btn.createAnchorPopup(100, @countof(LineCapStyle) * 46.0)
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
            for c in layout.childs
            {
                let btn = cast(*IconButton) c
                let cap = enumFromUserData'LineCapStyle(btn.userData)
                btn.isChecked = cur == cap
                btn.invalidate()
            }
        }

        let cur = selectedCap(me, begin)
        for i in LineCapStyle
        {
            let btn0 = IconButton.create(layout, {}, {0, 0, 0, 40})
            btn0.userData = enumToUserData(i)
            btn0.setForm(.RoundSquare)
            btn0.isChecked = cur == i

            btn0.sigPaintIcon = func|begin|(btn, bc, pos, flags)
            {
                bc.painter.setParams(.Antialiased)
                var rect  = pos
                rect.inflate(-9, -9)
                let cap   = enumFromUserData'LineCapStyle(btn.userData)
                let color = flags & .Checked ? btn.getThemeColors().btnIcon_CheckedIcon : btn.getThemeColors().btnIcon_Icon
                var pen   = Pen.createSolid(color, CapSize)
                if begin
                {
                    pen.begCapStyle = cap
                    pen.endCapStyle = .None
                    let (?, l0) = Painter.capStyleExtent(cap, CapSize, pen.capBegScaleX)
                    rect.moveLeft(l0)
                }
                else
                {
                    pen.begCapStyle = .None
                    pen.endCapStyle = cap
                    let (?, l0) = Painter.capStyleExtent(cap, CapSize, pen.capEndScaleX)
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
        let frame  = btn.createAnchorPopup(180, 170)
        let layout = StackLayoutCtrl.create(frame, .Top)
        frame.setView(layout)

        func updateBtnState(prop: *PropWnd, layout: *Wnd)
        {
            let curSel = prop.getSelectedBaseForm()
            for c in layout.childs
            {
                let btn  = cast(*IconButton) c
                let dash = enumFromUserData'DashStyle(btn.userData)
                btn.isChecked = curSel.dashStyle == dash
                btn.invalidate()
            }
        }

        let curSel = .getSelectedBaseForm()
        for i in DashStyle
        {
            if i == .Pattern do
                continue

            let btn0 = IconButton.create(layout, {}, {0, 0, 0, 32})
            btn0.userData = enumToUserData(i)
            btn0.setForm(.RoundSquare)
            btn0.isChecked = curSel.dashStyle == i

            btn0.sigPaintIcon = func|prop = me|(btn, bc, pos, flags)
            {
                bc.painter.setParams(.Antialiased)
                var rect   = pos
                rect.inflate(-9, -9)
                var dash  = enumFromUserData'DashStyle(btn.userData)
                let color = flags & .Checked ? btn.getThemeColors().btnIcon_CheckedIcon : btn.getThemeColors().btnIcon_Icon
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

        let btn  = createArrowButton(stack, BtnColorWidth, BtnColorHeight)

        let curSelType = .getSelectedFormType()
        switch curSelType
        {
        case FormLine, FormArrow, FormDraw:
            btn.name = "Color"
        case FormStep:
            btn.name = "Text"
        default:
            btn.name = "Outline"
        }

        btn.sigPaintIcon = func|prop = me|(btn, bc, pos, flags)
        {
            bc.painter.setParams(.Antialiased)
            let curSel = prop.getSelectedBaseForm()
            var rect   = pos
            rect.x = rect.horzCenter() - 16
            rect.y = rect.vertCenter() - 16
            rect.width, rect.height = 32
            if !curSel.borderColor.isOpaque() do
                bc.painter.drawRoundRect(rect, 5, 5, Pen.createHatch(.CheckBoardLarge, Argb.DarkGray, 5))
            bc.painter.drawRoundRect(rect, 5, 5, curSel.borderColor, 5)
        }

        btn.sigShowPopup += func|prop = me|(btn)
        {
            let curSel = prop.getSelectedBaseForm()
            var picker = createColorPicker(btn, curSel.borderColor)
            // Defer the undo entry until the color actually changes: `first` (closure-owned) is
            // true only on the first change, so opening then closing without picking leaves no
            // no-op undo entry, while later changes still replace the previous one (first = false).
            picker.sigChanged += func|prop, btn, first = true|(pk)
            {
                prop.pushTypedValue(pk.getColor().argb, BaseForm, #nameof(BaseForm.borderColor), first, true)
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

        let btn  = createArrowButton(stack, BtnColorWidth, BtnColorHeight)
        btn.name         = "Fill"
        btn.sigPaintIcon = func|prop = me|(btn, bc, pos, flags)
        {
            bc.painter.setParams(.Antialiased)
            var curSel = prop.getSelectedBaseForm()
            var rect   = pos
            rect.x = rect.horzCenter() - 21
            rect.y = rect.vertCenter() - 21
            rect.width, rect.height = 42
            var backCol = curSel.subKind == .PixSel ? g_Main.pixSelFillCol : curSel.backColor
            if !backCol.isOpaque() do
                bc.painter.fillRoundRect(rect, 10, 10, Brush.createHatch(.CheckBoardLarge, Argb.DarkGray))
            bc.painter.fillRoundRect(rect, 10, 10, backCol)
        }

        btn.sigShowPopup += func|prop = me|(btn)
        {
            var curSel  = prop.getSelectedBaseForm()
            var backCol = curSel.subKind == .PixSel ? g_Main.pixSelFillCol : curSel.backColor
            var picker  = createColorPicker(btn, backCol)
            if curSel.subKind == .PixSel
            {
                picker.sigChanged += func|btn|(pk)
                {
                    g_Main.pixSelFillCol = pk.getColor()
                    btn.invalidate()
                }
            }
            else
            {
                // Defer the undo entry until the color actually changes: `first` (closure-owned) is
                // true only on the first change, so opening then closing without picking leaves no
                // no-op undo entry, while later changes still replace the previous one (first = false).
                picker.sigChanged += func|prop, btn, first = true|(pk)
                {
                    prop.pushTypedValue(pk.getColor().argb, BaseForm, #nameof(BaseForm.backColor), first, true)
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

        let btn  = createArrowButton(stack, BtnColorWidth, BtnColorHeight)
        btn.name         = "Shape"
        btn.sigPaintIcon = func|prop = me|(btn, bc, pos, flags)
        {
            bc.painter.setParams(.Antialiased)
            let curSel = cast(*FormShape) prop.getSelectedBaseForm()
            drawShapeGlyph(bc.painter, curSel.kind, pos, btn.getThemeColors().btnIcon_Icon)
        }

        btn.sigShowPopup += func|prop = me|(btn)
        {
            prop.createPopupShapeKind(btn, FormShape, #nameof(FormShape.kind))
        }
    }

    mtd propStep(stack: *Wnd)
    {
        let curSelType = .getSelectedFormType()
        if curSelType != FormStep do
            return

        let btn  = createArrowButton(stack, BtnColorWidth, BtnColorHeight)
        btn.name         = "Shape"
        btn.sigPaintIcon = func|prop = me|(btn, bc, pos, flags)
        {
            bc.painter.setParams(.Antialiased)
            let curSel = cast(*FormStep) prop.getSelectedBaseForm()
            drawShapeGlyph(bc.painter, curSel.kind, pos, btn.getThemeColors().btnIcon_Icon)
        }

        btn.sigShowPopup += func|prop = me|(btn)
        {
            prop.createPopupShapeKind(btn, FormStep, #nameof(FormStep.kind))
        }
    }

    mtd propStartCapStyle(stack: *Wnd)
    {
        let curSelType = .getSelectedFormType()
        if curSelType != FormLine and curSelType != FormArrow do
            return

        let btn  = createArrowButton(stack, BtnStyleWidth, BtnStyleHeight)
        btn.name = "Start"

        btn.sigPaintIcon = func|prop = me|(btn, bc, pos, flags)
        {
            var curSel = cast(*FormLine) prop.getSelectedBaseForm()
            var rect   = pos
            rect.inflate(-9, -9)
            var pen = Pen.createSolid(btn.getThemeColors().btnIcon_Icon, CapSize)
            pen.begCapStyle = curSel.beginCap
            pen.endCapStyle = .None
            let (?, l0) = Painter.capStyleExtent(curSel.beginCap, CapSize, pen.capBegScaleX)
            rect.moveLeft(l0)

            bc.painter.setParams(.Antialiased)
            bc.painter.drawLine(rect.x, rect.vertCenter(), rect.right(), rect.vertCenter(), pen)
        }

        btn.sigShowPopup += func|prop = me|(btn)
        {
            prop.createPopupCapStyle(btn, begin: true)
        }
    }

    mtd propEndCapStyle(stack: *Wnd)
    {
        let curSelType = .getSelectedFormType()
        if curSelType != FormLine and curSelType != FormArrow do
            return

        let btn  = createArrowButton(stack, BtnStyleWidth, BtnStyleHeight)
        btn.name         = "End"
        btn.sigPaintIcon = func|prop = me|(btn, bc, pos, flags)
        {
            let curSel = cast(*FormLine) prop.getSelectedBaseForm()
            var rect   = pos
            rect.inflate(-9, -9)
            var pen = Pen.createSolid(btn.getThemeColors().btnIcon_Icon, CapSize)
            pen.begCapStyle = .None
            pen.endCapStyle = curSel.endCap
            let (?, l0) = Painter.capStyleExtent(curSel.endCap, CapSize, pen.capEndScaleX)
            rect.moveRight(-l0)

            bc.painter.setParams(.Antialiased)
            bc.painter.drawLine(rect.x, rect.vertCenter(), rect.right(), rect.vertCenter(), pen)
        }

        btn.sigShowPopup += func|prop = me|(btn)
        {
            prop.createPopupCapStyle(btn, begin: false)
        }
    }

    mtd propDashStyle(stack: *Wnd)
    {
        let curSelType = .getSelectedFormType()
        if curSelType != FormShape and curSelType != FormLine and curSelType != FormArrow and curSelType != FormPolygon do
            return

        let curSel = cast(*FormText) .getSelectedBaseForm()
        if curSel.subKind == .Highlight or curSel.subKind == .PixSel do
            return

        let btn  = createArrowButton(stack, BtnStyleWidth, BtnStyleHeight)
        btn.name         = "Dash"
        btn.sigPaintIcon = func|prop = me|(btn, bc, pos, flags)
        {
            bc.painter.setParams(.Antialiased)
            var curSel = prop.getSelectedBaseForm()
            var rect   = pos
            rect.inflate(-10, -10)
            var pen = Pen.createDash(curSel.dashStyle, btn.getThemeColors().btnIcon_Icon, DashSize)
            pen.dashBlankScale = 0.25
            bc.painter.drawLine(rect.x, rect.vertCenter(), rect.right(), rect.vertCenter(), pen)
        }

        btn.sigShowPopup += func|prop = me|(btn)
        {
            prop.createPopupDashStyle(btn)
        }
    }

    // The step type combo is generated by the grid (FormStep.typeIndex attribute);
    // only the "reset the global counter" action needs a hand-made row.
    mtd propNextStep()
    {
        let curSelType = .getSelectedFormType()
        if curSelType != FormStep do
            return

        let stack = Wnd.create'Wnd(.topLayout, {0, 0, 0, .getThemeMetrics().comboBox_Height})

        with let btn = PushButton.create(stack, "Reset", {0, 0, 60})
        {
            .margin.x  = 5
            .dockStyle = .Right
            .toolTip   = "Reset the global step count to 1"
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
        with let dlg = EditDlg.createMultiLine(main.surface)
        {
            .setMessage("Press Shift+Enter to add a new line")
            .setText(curText)
            .richEdit.selectAll()
            .surface.setTitle("Enter Text")
            .surface.center(main.surface)
            if main.inPlaceEdit do
                .surface.setTopMost()
        }
        if dlg.doModal() != Dialog.BtnOk do
            return curText
        let capture = assume main.getCapture()
        let undo    = capture.newUndo(.SetText)
        undo.text = dlg.getText()
        capture.pushUndo(undo)
        return undo.text
    }

    // Text-fill color swatch for a callout (the bubble fill/border reuse the generic
    // BaseForm color buttons; only the inner text color is callout-specific).
    mtd propCalloutText(stack: *Wnd)
    {
        if .getSelectedFormType() != FormCallout do
            return

        let btn = createArrowButton(stack, BtnColorWidth, BtnColorHeight)
        btn.name         = "Text"
        btn.sigPaintIcon = func|prop = me|(btn, bc, pos, flags)
        {
            bc.painter.setParams(.Antialiased)
            let curSel = cast(*FormCallout) prop.getSelectedBaseForm()
            var rect   = pos
            rect.x = rect.horzCenter() - 21
            rect.y = rect.vertCenter() - 21
            rect.width, rect.height = 42
            if !curSel.textColor.isOpaque() do
                bc.painter.fillRoundRect(rect, 10, 10, Brush.createHatch(.CheckBoardLarge, Argb.DarkGray))
            bc.painter.fillRoundRect(rect, 10, 10, curSel.textColor)
        }

        btn.sigShowPopup += func|prop = me|(btn)
        {
            let curSel = cast(*FormCallout) prop.getSelectedBaseForm()
            var picker = createColorPicker(btn, curSel.textColor)
            picker.sigChanged += func|prop, btn, first = true|(pk)
            {
                prop.pushTypedValue(pk.getColor().argb, FormCallout, #nameof(FormCallout.textColor), first)
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

        discard PushButton.create(.topLayout, "", id: ActionPixSel.Fill)
        discard PushButton.create(.topLayout, "", id: ActionPixSel.SmartFill)
        discard PushButton.create(.topLayout, "", id: ActionPixSel.Clear)
        discard PushButton.create(.topLayout, "", id: ActionPixSel.SmartMove)
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

        func addBox(prop: *PropWnd, parent: *Wnd, label: string, name: string, value: s32, signed: bool)
        {
            let edit = EditCtrl.create(parent, label, Format.toString("%", value), flags: .AutoLoseFocus)
            edit.labelSize = 15
            edit.editSize  = 0
            if signed do
                edit.edit.setInputS64()
            else do
                edit.edit.setInputU64(1, 10000)
            edit.edit.sigLoseFocus += func|prop, name|(ed)
            {
                let (v, ?, ?) = catch StrConv.parseS32(ed.text)
                prop.pushTypedValue(v, BaseForm, name, true, true)
            }
        }

        func addRow(prop: *PropWnd, name: string)->*Wnd
        {
            let v: Swag.TypeValue{name: name}
            let item = prop.grid.addItem(v, null, null, 40, .Zero)
            // No NoFocus: the rows embed edit boxes, so they stay keyboard-navigable
            item.flags.add(.NoSeparator)
            return StackLayoutCtrl.create(item.line, .HorzFit, {0, 0, 0, 40})
        }

        discard .grid.addSeparator("Position")

        with let l0 = addRow(me, "position")
        {
            addBox(me, l0, "x", #nameof(BaseForm.x), curSel.x, true)
            addBox(me, l0, "y", #nameof(BaseForm.y), curSel.y, true)
        }

        with let l1 = addRow(me, "size")
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
        var bases:  Array'(*u8)

        if !capture or !capture.selection.count
        {
            // Tool model: direct edition, no undo (as before)
            let mdl = .main.editModeToModel(.main.editMode)
            .gridBindType = @kindof(mdl)
            bases.add(cast(*u8) @dataof(mdl))
            .grid.setExternalUndoMgr(null)
            .grid.setUndoEnabled(false)
        }
        else
        {
            // Common concrete type of the selection: exact when homogeneous, FormLine for
            // a line/arrow mix (an arrow embeds a line), BaseForm otherwise
            var allSame  = true
            var lineOnly = true
            var firstType: typeinfo

            foreachSelected'BaseForm(capture, capture.selection)
            {
                let t = @kindof(itf)
                if !firstType do
                    firstType = t
                elif t != firstType do
                    allSame = false
                if t != FormLine and t != FormArrow do
                    lineOnly = false
                bases.add(cast(*u8) form)
            }

            if allSame do
                .gridBindType = firstType
            elif lineOnly do
                .gridBindType = FormLine
            else do
                .gridBindType = BaseForm

            .grid.setExternalUndoMgr(&capture.undoMgr)
            .grid.setUndoEnabled(true)
        }

        .grid.addStructMulti(.gridBindType, bases.toSlice(), null, onlyNamed: true)

        // The generated border-size slider serves every form as "Tickness"; a text form
        // edits its glyph outline instead: matching label and a much thinner range. The
        // slider keeps a normalized position, so re-set the value after the new range.
        if .gridBindType == FormText
        {
            for item in .grid.items
            {
                if item.typeValue.name != #nameof(BaseForm.borderSize) or !item.sliderBox do
                    continue
                item.sliderBox.label.setText("Outline")
                item.sliderBox.setMinMaxS64(cast() MinTextBorderSize, cast() MaxTextBorderSize)
                item.sliderBox.setValueNoChange(.getSelectedBaseForm().borderSize)
            }
        }
    }

    mtd selectionHasChanged()
    {
        for it in .topLayout.childs do
            it.destroy()
        .grid.clearStructs()

        if !.getSelectedBaseForm()
        {
            .applyLayout()
            return
        }

        let stack0 = StackLayoutCtrl.create(.topLayout, .HorzCenter, {0, 0, 0, BtnColorHeight + 12})
        .propBackColor(stack0)
        .propBorderColor(stack0)
        .propCalloutText(stack0)
        .propShape(stack0)
        .propStep(stack0)
        if stack0.childs.count == 0 do
            stack0.destroyNow()

        let stack1 = StackLayoutCtrl.create(.topLayout, .HorzCenter, {0, 0, 0, BtnStyleHeight + 12})
        .propStartCapStyle(stack1)
        .propDashStyle(stack1)
        .propEndCapStyle(stack1)
        if stack1.childs.count == 0 do
            stack1.destroyNow()

        .propNextStep()
        .propPixSel()

        .bindGrid()
        .propXY()

        .topLayout.computeLayout()
        .applyLayout()

        let capture = .main.getCapture()
        if capture do
            capture.editView.setFocus()
    }

    func create(parent: *Wnd, main: *MainWnd)->*PropWnd
    {
        with let prop = Wnd.create'PropWnd(parent, {0, 0, 0, 300})
        {
            .backgroundStyle = .Window

            .topLayout              = StackLayoutCtrl.create(prop)
            .topLayout.layoutKind   = .Top
            .topLayout.fitToContent = true
            .topLayout.dockStyle    = .Top
            .topLayout.padding      = 8
            .topLayout.padding.y    = 16

            .grid                 = Properties.create(prop, kind: .Panel)
            .grid.dockStyle       = .Center
            .grid.showReverts     = false
            // Most specific first: a form edits its own fields (text, caps, round...)
            // before the BaseForm style shared by every form
            .grid.usingFieldsLast = true
            // Always show a small vertical bar so the row width does not jump with the content
            .grid.scrollWnd.scrollWndFlags |= .ForceVertical | .SmallBar

            .main = main
            .grid.setNotify(cast(IPropertyNotify) prop)
        }

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
        // thick stroke, never what a captme form wants.
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
    mtd impl onPrePaintEvent(evt: *PaintEvent)
    {
        .frameWnd.IWnd.onPrePaintEvent(evt)
    }

    mtd impl onPaintEvent(evt: *PaintEvent)
    {
        .frameWnd.IWnd.onPaintEvent(evt)
    }

    mtd impl onPostPaintEvent(evt: *PaintEvent)
    {
        .frameWnd.IWnd.onPostPaintEvent(evt)
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
}

