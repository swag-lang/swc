const BtnColorWidth  = 68.0
const BtnColorHeight = 88.0
const BtnStyleWidth  = 88.0
const BtnStyleHeight = 68.0

const CapSize  = 8.0
const DashSize = 8.0

const CmdIdTextHLeft   = "CmdIdTextHLeft"
const CmdIdTextHCenter = "CmdIdTextHCenter"
const CmdIdTextHRight  = "CmdIdTextHRight"
const CmdIdTextVTop    = "CmdIdTextVTop"
const CmdIdTextVCenter = "CmdIdTextVCenter"
const CmdIdTextVBottom = "CmdIdTextVBottom"
const CmdIdTextBold    = "CmdIdTextBold"
const CmdIdTextItalic  = "CmdIdTextItalic"

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

struct PropWnd
{
    using scrollWnd:     ScrollWnd
    mainLayout:          *StackLayoutCtrl
    main:                *MainWnd
    sysFonts:            Array'FontFamilyEnumerate
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

    // Common width for every slider's value box, so the column of edit boxes lines
    // up. Derived from the font height so it scales with the font size.
    mtd sliderEditSize()->f32
    {
        let fontR = .getFont().regular
        if !fontR do
            return 60
        return Math.round(fontR.height * 4)
    }

    mtd createSlider(name: string, minv, maxv: s64, val: f32)->*SliderCtrl
    {
        with let ctrl = SliderCtrl.create(me.mainLayout, name)
        {
            .setMinMaxS64(minv, maxv)
            // mainLayout owns row placement; a dock style would be applied again by generic relayouts.
            .autoEditSize = false
            .editSize     = me.sliderEditSize()
            .setValue(val)
        }

        return ctrl
    }

    // Wire a slider to a form field through the undo system: the drag start pushes
    // the initial undo entry, each move then replaces it (see pushTypedValue). Float
    // fields travel as bit patterns, integer fields as plain values.
    mtd bindSlider(ctrl: *SliderCtrl, type: typeinfo, name: string, common = false, intValue = false)
    {
        ctrl.slider.sigStartChange += func|prop = me, type, name, common, intValue|(slider)
        {
            let v = intValue ? cast(u32) slider.getValue() : cast #bit (u32) slider.getValue()
            prop.pushTypedValue(v, type, name, true, common)
        }
        ctrl.slider.sigChanged += func|prop = me, type, name, common, intValue|(slider)
        {
            let v = intValue ? cast(u32) slider.getValue() : cast #bit (u32) slider.getValue()
            prop.pushTypedValue(v, type, name, false, common)
        }
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

    mtd propNextStep()
    {
        let curSelType = .getSelectedFormType()
        if curSelType != FormStep do
            return

        let stack = Wnd.create'Wnd(.mainLayout, {0, 0, 0, .getThemeMetrics().comboBox_Height})

        let curSel = cast(*FormStep) .getSelectedBaseForm()
        with let combo = ComboBox.create(stack)
        {
            combo.dockStyle = .Center
            .addItem("1...2...3...")
            .addItem("A...B...C...")
            .addItem("a...b...c...")
            .selectItem(cast(u32) curSel.typeIndex)
            .sigChanged += func|prop = me|(combo, val)
            {
                prop.pushTypedValue(cast() val, FormStep, #nameof(FormStep.typeIndex), true)
            }
        }

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

    // Round/font sliders and the text editor entry point for a callout.
    mtd propCallout()
    {
        if .getSelectedFormType() != FormCallout do
            return
        let curSel = cast(*FormCallout) .getSelectedBaseForm()

        let ctrlR = .createSlider("Round", cast() MinRoundSize, cast() MaxRoundSize, curSel.roundSize)
        .bindSlider(ctrlR, FormCallout, #nameof(FormCallout.roundSize))

        let ctrlF = .createSlider("Size", cast() MinFontSize, cast() MaxFontSize, cast() curSel.fontSize)
        .bindSlider(ctrlF, FormCallout, #nameof(FormCallout.fontSize))

        with let btn = PushButton.create(.mainLayout, "Edit Text...", {0, 0, 0, 40})
        {
            .margin.x = 5
            btn.sigPressed += func|prop = me|(btn)
            {
                prop.main.sendCommandEvent(ActionEdit.EditText)
            }
        }
    }

    mtd propText()
    {
        let curSelType = .getSelectedFormType()
        if curSelType != FormText do
            return
        let curSel = cast(*FormText) .getSelectedBaseForm()

        let stack = StackLayoutCtrl.create(.mainLayout, .Top, {0, 0, 0, 160})
        stack.padding = 8

        // Font
        let combo = ComboBox.create(stack)

        combo.addItem(g_App.theme.res.defaultTypeFaceR.getFamilyName())
        if !curSel.typeFace do
            combo.selectedIdx = 0
        combo.addSeparator()

        if .sysFonts.isEmpty() do
            .sysFonts = FontFamily.enumerateFromOs()
        for &fnt in .sysFonts
        {
            combo.addItem(fnt.name, userData0: fnt)
            if curSel.fontName == fnt.name do
                combo.selectedIdx = cast(u32) combo.items.count - 1
        }

        combo.sigChanged += func|prop = me|(combo, idx)
        {
            if idx == Swag.U32.Max do
                return

            var capture = assume prop.main.getCapture()
            var undo    = capture.newUndo(.SetFont)

            var sel = combo.items[idx]
            if sel.userData0
            {
                let p = cast(*FontFamilyEnumerate) sel.userData0
                undo.text = p.name
            }

            undo.fontStyle = .Regular
            capture.pushUndo(undo)
        }

        // Text
        let edt = EditBox.create(stack, curSel.text)
        edt.rightMargin = 24
        with let btnedt = IconButton.create(edt, me.getTheme().getIcon24(.More, 20), {0, 0, 20, 20})
        {
            .dockStyle = .Right
            .sigPressed += func|edt|(btn)
            {
                let txt = editText(g_Main, edt.text)
                edt.setText(txt)
            }
        }

        edt.name = "Enter text"
        edt.sigLoseFocus += func|prop = me|(edit)
        {
            let curSel = cast(*FormText) prop.getSelectedBaseForm()
            if curSel.text != edit.text
            {
                let capture = assume prop.main.getCapture()
                let undo    = capture.newUndo(.SetText)
                undo.text = edit.text
                capture.pushUndo(undo)
            }
        }

        // Bold/Italic
        let stack2 = StackLayoutCtrl.create(stack, .HorzCenter, {0, 0, 0, 30})
        with let bar2 = IconBar.create(stack2, 24)
        {
            .addCheckableToggleItem(Icon.from(&me.main.icons24, 16), CmdIdTextBold)
            .addCheckableToggleItem(Icon.from(&me.main.icons24, 17), CmdIdTextItalic)

            .sigUpdateState += func|prop = me|(evt)
            {
                let curSel = cast(*FormText) prop.getSelectedBaseForm()
                evt.setFlags.add(.Checked)
                evt.accepted = true

                switch evt.id
                {
                case CmdIdTextBold:
                    evt.checked = curSel.fontStyle == .Bold or curSel.fontStyle == .BoldItalic
                case CmdIdTextItalic:
                    evt.checked = curSel.fontStyle == .Italic or curSel.fontStyle == .BoldItalic
                }
            }

            .sigCheckChanged += func|prop = me|(btn)
            {
                let capture = assume prop.main.getCapture()
                let curSel  = cast(*FormText) prop.getSelectedBaseForm()
                var fstyle  = curSel.fontStyle
                switch btn.id
                {
                case CmdIdTextBold:
                    if btn.isChecked and fstyle == .Regular do
                        fstyle = .Bold
                    elif btn.isChecked and fstyle == .Italic do
                        fstyle = .BoldItalic
                    elif !btn.isChecked and fstyle == .Bold do
                        fstyle = .Regular
                    elif !btn.isChecked and fstyle == .BoldItalic do
                        fstyle = .Italic

                case CmdIdTextItalic:
                    if btn.isChecked and fstyle == .Regular do
                        fstyle = .Italic
                    elif btn.isChecked and fstyle == .Bold do
                        fstyle = .BoldItalic
                    elif !btn.isChecked and fstyle == .Italic do
                        fstyle = .Regular
                    elif !btn.isChecked and fstyle == .BoldItalic do
                        fstyle = .Bold
                }

                var undo = capture.newUndo(.SetFontStyle)
                undo.fontStyle = fstyle
                capture.pushUndo(undo)
            }

            bar2.updateCommandState()
        }

        // Align
        let stack1 = StackLayoutCtrl.create(stack, .HorzCenter, {0, 0, 0, 40})
        with let bar = IconBar.create(stack1, 24)
        {
            .addCheckableItem(Icon.from(&me.main.icons24, 8), CmdIdTextHLeft)
            .addCheckableItem(Icon.from(&me.main.icons24, 9), CmdIdTextHCenter)
            .addCheckableItem(Icon.from(&me.main.icons24, 10), CmdIdTextHRight)
            .addCheckableItem(Icon.from(&me.main.icons24, 11), CmdIdTextVTop)
            .addCheckableItem(Icon.from(&me.main.icons24, 12), CmdIdTextVCenter)
            .addCheckableItem(Icon.from(&me.main.icons24, 13), CmdIdTextVBottom)

            .sigUpdateState += func|prop = me|(evt)
            {
                var curSel = cast(*FormText) prop.getSelectedBaseForm()
                evt.setFlags.add(.Checked)
                evt.accepted = true

                switch evt.id
                {
                case CmdIdTextHLeft:
                    evt.checked = curSel.alignHorz == .LeftTop
                case CmdIdTextHCenter:
                    evt.checked = curSel.alignHorz == .Center
                case CmdIdTextHRight:
                    evt.checked = curSel.alignHorz == .RightBottom
                case CmdIdTextVTop:
                    evt.checked = curSel.alignVert == .LeftTop
                case CmdIdTextVCenter:
                    evt.checked = curSel.alignVert == .Center
                case CmdIdTextVBottom:
                    evt.checked = curSel.alignVert == .RightBottom
                }
            }

            .sigCheckChanged += func|prop = me|(btn)
            {
                switch btn.id
                {
                case CmdIdTextHLeft:
                    prop.pushTypedValue(cast(u32) FormTextAlign.LeftTop, FormText, #nameof(FormText.alignHorz), true)
                case CmdIdTextHCenter:
                    prop.pushTypedValue(cast(u32) FormTextAlign.Center, FormText, #nameof(FormText.alignHorz), true)
                case CmdIdTextHRight:
                    prop.pushTypedValue(cast(u32) FormTextAlign.RightBottom, FormText, #nameof(FormText.alignHorz), true)
                case CmdIdTextVTop:
                    prop.pushTypedValue(cast(u32) FormTextAlign.LeftTop, FormText, #nameof(FormText.alignVert), true)
                case CmdIdTextVCenter:
                    prop.pushTypedValue(cast(u32) FormTextAlign.Center, FormText, #nameof(FormText.alignVert), true)
                case CmdIdTextVBottom:
                    prop.pushTypedValue(cast(u32) FormTextAlign.RightBottom, FormText, #nameof(FormText.alignVert), true)
                }
            }

            bar.updateCommandState()
        }
    }

    mtd propStartSize()
    {
        let curSelType = .getSelectedFormType()
        if curSelType != FormLine and curSelType != FormArrow do
            return
        let curSel = cast(*FormLine) .getSelectedBaseForm()

        let ctrl = .createSlider("Start Size", cast() MinCapSize, cast() MaxCapSize, curSel.startSize)
        .bindSlider(ctrl, FormLine, #nameof(FormLine.startSize))
    }

    mtd propEndSize()
    {
        let curSelType = .getSelectedFormType()
        if curSelType != FormLine and curSelType != FormArrow do
            return

        let curSel = cast(*FormLine) .getSelectedBaseForm()
        let ctrl = .createSlider("End Size", cast() MinCapSize, cast() MaxCapSize, curSel.endSize)
        .bindSlider(ctrl, FormLine, #nameof(FormLine.endSize))
    }

    mtd propRoundSize()
    {
        let curSelType = .getSelectedFormType()
        if curSelType != FormShape do
            return

        let curSel = cast(*FormShape) .getSelectedBaseForm()
        if curSel.kind != .RoundRectangle do
            return

        let ctrl = .createSlider("Round", cast() MinRoundSize, cast() MaxRoundSize, curSel.roundSize)
        .bindSlider(ctrl, FormShape, #nameof(FormShape.roundSize))
    }

    mtd propXY()
    {
        if !.hasRealSelection() do
            return
        let curSelType = .getSelectedFormType()
        if curSelType != FormShape and curSelType != FormText and curSelType != FormCallout do
            return
        let curSel = .getSelectedBaseForm()

        {
            let l     = StackLayoutCtrl.create(.mainLayout, .HorzFit, {0, 0, 0, 40})
            let edit0 = EditCtrl.create(l, "x", Format.toString("%", curSel.x), flags: .AutoLoseFocus)
            edit0.labelSize = 15
            edit0.editSize  = 0
            // X can be negative (form may sit outside the canvas), and the value is read back with parseS32.
            edit0.edit.setInputS64()
            edit0.edit.sigLoseFocus += func|prop = me|(ed)
            {
                let (v, ?, ?) = catch StrConv.parseS32(ed.text)
                prop.pushTypedValue(v, BaseForm, #nameof(BaseForm.x), true, true)
            }

            let edit1 = EditCtrl.create(l, "y", Format.toString("%", curSel.y), flags: .AutoLoseFocus)
            edit1.labelSize = 15
            edit1.editSize  = 0
            // Y can be negative (form may sit outside the canvas), and the value is read back with parseS32.
            edit1.edit.setInputS64()
            edit1.edit.sigLoseFocus += func|prop = me|(ed)
            {
                let (v, ?, ?) = catch StrConv.parseS32(ed.text)
                prop.pushTypedValue(v, BaseForm, #nameof(BaseForm.y), true, true)
            }
        }

        {
            let l     = StackLayoutCtrl.create(.mainLayout, .HorzFit, {0, 0, 0, 40})
            let edit0 = EditCtrl.create(l, "w", Format.toString("%", curSel.w), flags: .AutoLoseFocus)
            edit0.labelSize = 15
            edit0.editSize  = 0
            edit0.edit.setInputU64(1, 10000)
            edit0.edit.sigLoseFocus += func|prop = me|(ed)
            {
                let (v, ?, ?) = catch StrConv.parseS32(ed.text)
                prop.pushTypedValue(v, BaseForm, #nameof(BaseForm.w), true, true)
            }

            let edit1 = EditCtrl.create(l, "h", Format.toString("%", curSel.h), flags: .AutoLoseFocus)
            edit1.labelSize = 15
            edit1.editSize  = 0
            edit1.edit.setInputU64(1, 10000)
            edit1.edit.sigLoseFocus += func|prop = me|(ed)
            {
                let (v, ?, ?) = catch StrConv.parseS32(ed.text)
                prop.pushTypedValue(v, BaseForm, #nameof(BaseForm.h), true, true)
            }
        }
    }

    mtd propBorderSize()
    {
        let curSelType = .getSelectedFormType()
        if curSelType == FormStep do
            return

        let curSel = .getSelectedBaseForm()
        if curSel.subKind == .PixSel do
            return

        var minS = MinBorderSize
        var maxS = MaxBorderSize
        var labl = "Tickness"
        if curSelType == FormText
        {
            minS = MinTextBorderSize
            maxS = MaxTextBorderSize
            labl = "Outline"
        }
        elif curSelType == FormDraw
        {
            minS = Math.max(minS, 1)
        }

        let ctrl = .createSlider(labl, cast() minS, cast() maxS, curSel.borderSize)
        .bindSlider(ctrl, BaseForm, #nameof(BaseForm.borderSize), common: true)
    }

    mtd propFontSize()
    {
        let curSelType = .getSelectedFormType()
        if curSelType != FormText do
            return

        let curSel = cast(*FormText) .getSelectedBaseForm()
        let ctrl   = .createSlider("Size", cast() MinFontSize, cast() MaxFontSize, cast() curSel.fontSize)
        .bindSlider(ctrl, FormText, #nameof(FormText.fontSize))
    }

    mtd propScale()
    {
        let curSelType = .getSelectedFormType()
        if curSelType != FormText do
            return

        let curSel = cast(*FormText) .getSelectedBaseForm()
        let ctrl = .createSlider("Scale", 0, 100, cast() curSel.scale)
        ctrl.edit.unit = "%"
        .bindSlider(ctrl, BaseForm, #nameof(BaseForm.scale), common: true)
    }

    mtd propRotate()
    {
        let curSelType = .getSelectedFormType()
        if curSelType != FormText and curSelType != FormShape and curSelType != FormImage do
            return
        let curSel = cast(*FormText) .getSelectedBaseForm()
        if curSel.subKind == .Highlight or curSel.subKind == .PixSel do
            return

        let ctrl = .createSlider("Rotate", 0, 360, cast() curSel.rotate)
        ctrl.edit.unit = "°"
        .bindSlider(ctrl, BaseForm, #nameof(BaseForm.rotate), common: true)
    }

    mtd propShadow()
    {
        let curSel = .getSelectedBaseForm()
        if curSel.subKind == .PixSel do
            return

        let ctrl = ComboCtrl.create(.mainLayout, "Shadow")
        ctrl.comboSize = 210
        with ctrl.combo
        {
            .addItem("No Shadow")
            .addItem("Small")
            .selectItem(curSel.paintShadow ? 1 : 0)
            .sigChanged += func|prop = me|(combo, val)
            {
                var b = val == 1 ? true : false
                prop.pushTypedValue(cast() b, BaseForm, #nameof(BaseForm.paintShadow), true, true)
            }
        }
    }

    mtd propSmooth()
    {
        let curSelType = .getSelectedFormType()
        if curSelType != FormLine and curSelType != FormArrow and curSelType != FormPolygon do
            return
        let curSel = cast(*BaseForm) .getSelectedBaseForm()
        if curSel.subKind == .PixSel do
            return

        let ctrl = ComboCtrl.create(.mainLayout, "Line")
        ctrl.comboSize = 210
        with ctrl.combo
        {
            .addItem("Straight")
            .addItem("Bezier")
            .selectItem(curSel.bezier ? 1 : 0)
            .sigChanged += func|prop = me|(combo, val)
            {
                var b = val == 1 ? true : false
                prop.pushTypedValue(cast() b, BaseForm, #nameof(BaseForm.bezier), true, true)
            }
        }
    }

    mtd propBoldSize()
    {
        let curSelType = .getSelectedFormType()
        if curSelType != FormText do
            return

        let curSel = cast(*FormText) .getSelectedBaseForm()
        let ctrl = .createSlider("Strengh", cast() MinBoldSize, cast() MaxBoldSize, cast() curSel.boldSize)
        .bindSlider(ctrl, FormText, #nameof(FormText.boldSize))
    }

    mtd propOpacity()
    {
        let curSel = .getSelectedBaseForm()
        if curSel.subKind == .PixSel do
            return

        let ctrl = .createSlider("Opacity", 0, 100, cast() curSel.alpha)
        ctrl.edit.unit = "%"
        .bindSlider(ctrl, BaseForm, #nameof(BaseForm.alpha), common: true, intValue: true)
    }

    mtd propImageKind()
    {
        let curSelType = .getSelectedFormType()
        if curSelType != FormImage do
            return

        let curSel = cast(*FormImage) .getSelectedBaseForm()

        let ctrl = ComboCtrl.create(.mainLayout, "Kind")
        ctrl.comboSize = 210
        with ctrl.combo
        {
            for v in #typeof(FormImageKind).values do
                .addItem(v.name)
            .selectItem(cast(u32) curSel.kind)
            .sigChanged += func|prop = me|(combo, val)
            {
                prop.pushTypedValue(val, FormImage, #nameof(FormImage.kind), true)
                prop.selectionHasChanged()
            }
        }

        let ctrl1 = ComboCtrl.create(.mainLayout, "Place")
        ctrl1.comboSize = 210
        with ctrl1.combo
        {
            for v in #typeof(FormImagePlacement).values do
                .addItem(v.name)
            .selectItem(cast(u32) curSel.place)
            .sigChanged += func|prop = me|(combo, val)
            {
                prop.pushTypedValue(val, FormImage, #nameof(FormImage.place), true)
            }
        }
    }

    mtd propStrength()
    {
        let curSelType = .getSelectedFormType()
        if curSelType != FormImage do
            return
        let curSel = cast(*FormImage) .getSelectedBaseForm()
        if curSel.kind == .Image do
            return

        let ctrl = .createSlider("Strength", 0, 100, cast() curSel.strength)
        .bindSlider(ctrl, FormImage, #nameof(FormImage.strength), intValue: true)
    }

    mtd propJoinStyle()
    {
        let curSelType = .getSelectedFormType()
        if curSelType != FormText and curSelType != FormPolygon do
            return
        let curSel = .getSelectedBaseForm()
        if curSel.subKind == .PixSel do
            return

        let ctrl = ComboCtrl.create(.mainLayout, "Joins")
        ctrl.comboSize = 210
        with ctrl.combo
        {
            .addItem("Bevel")
            .addItem("Round")
            .addItem("Miter")
            .addItem("MiterBevel")
            // The combo omits `JoinStyle.None` (0), so index = joinStyle - 1; guard against
            // `None` which would underflow the unsigned index and select nothing.
            .selectItem(curSel.joinStyle == .None ? 0 : cast(u32) curSel.joinStyle - 1)
            .sigChanged += func|prop = me|(combo, val)
            {
                var v = val + 1
                prop.pushTypedValue(cast() v, BaseForm, #nameof(BaseForm.joinStyle), true, true)
            }
        }
    }

    mtd propPixSel()
    {
        let curSel = .getSelectedBaseForm()
        if curSel.subKind != .PixSel do
            return

        discard PushButton.create(.mainLayout, "", id: ActionPixSel.Fill)
        discard PushButton.create(.mainLayout, "", id: ActionPixSel.SmartFill)
        discard PushButton.create(.mainLayout, "", id: ActionPixSel.Clear)
        discard PushButton.create(.mainLayout, "", id: ActionPixSel.SmartMove)
    }

    mtd propSep()
    {
        let sep = Wnd.create'Wnd(.mainLayout, {0, 0, 0, 1})
        sep.margin.y        = 15
        sep.margin.w        = 8
        sep.backgroundStyle = .Dialog
    }

    mtd selectionHasChanged()
    {
        for it in .mainLayout.childs do
            it.destroy()
        if !.getSelectedBaseForm() do
            return

        let stack0 = StackLayoutCtrl.create(.mainLayout, .HorzCenter, {0, 0, 0, BtnColorHeight + 12})
        .propBackColor(stack0)
        .propBorderColor(stack0)
        .propCalloutText(stack0)
        .propShape(stack0)
        .propStep(stack0)
        if stack0.childs.count == 0 do
            stack0.destroyNow()

        let stack1 = StackLayoutCtrl.create(.mainLayout, .HorzCenter, {0, 0, 0, BtnStyleHeight + 12})
        .propStartCapStyle(stack1)
        .propDashStyle(stack1)
        .propEndCapStyle(stack1)
        if stack1.childs.count == 0 do
            stack1.destroyNow()

        .propImageKind()
        .propStrength()
        .propNextStep()
        .propText()
        .propCallout()
        .propFontSize()
        .propBoldSize()
        .propBorderSize()
        .propStartSize()
        .propEndSize()
        .propRoundSize()
        .propJoinStyle()
        .propSmooth()
        .propPixSel()

        .propSep()

        .propScale()
        .propRotate()
        .propOpacity()
        .propShadow()

        .propSep()

        .propXY()

        .mainLayout.computeLayout()
        if .mainLayout.childs.count do
            .setScrollSize(0, .mainLayout.childs.back().position.bottom() + 16)
        else do
            .setScrollSize(0, 0)

        let capture = .main.getCapture()
        if capture do
            capture.editView.setFocus()
    }

    func create(parent: *Wnd, main: *MainWnd)->*PropWnd
    {
        with let prop = Wnd.create'PropWnd(parent, {0, 0, 0, 300})
        {
            .backgroundStyle = .Window
            .scrollWndFlags |= .ForceVertical | .SmallBar | .TransparentBar

            .mainLayout            = StackLayoutCtrl.create(prop)
            .mainLayout.layoutKind = .Top
            .mainLayout.padding    = 8
            .mainLayout.padding.y  = 16

            .setView(.mainLayout)

            .main = main
        }

        return prop
    }
}
