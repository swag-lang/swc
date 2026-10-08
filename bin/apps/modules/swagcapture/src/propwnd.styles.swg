impl PropWnd
{
    // Adds the style cell for the outline color of the selection, named for what that color paints
    // on the selected kind of form.
    mtd propBorderColor(stack: *Wnd)
    {
        let curSel = .getSelectedBaseForm()
        if curSel.subKind == .Highlight or curSel.subKind == .PixSel do
            return

        var tip = appStrings().ui_PropOutline
        switch .getSelectedFormType()
        {
        case FormLine, FormArrow, FormDraw: tip = appStrings().ui_PropColor
        case FormStep: tip = appStrings().act_Text
        }

        let button = createStyleButton(stack, tip)

        button.iconPainter = func|prop = me|(?, bc, pos, ?)
        {
            bc.painter.setParams(.Antialiased)
            let curSel = prop.getSelectedBaseForm()
            var rect   = pos
            rect.x = rect.horzCenter() - StyleGlyphSize * 0.5
            rect.y = rect.vertCenter() - StyleGlyphSize * 0.5
            rect.width, rect.height = StyleGlyphSize
            if not curSel.borderColor.isOpaque() do
                bc.painter.drawRect(rect, Pen.createHatch(.CheckBoardLarge, Argb.DarkGray, 5))
            bc.painter.drawRect(rect, curSel.borderColor, 5)
        }

        button.sigPopupRequested += func|prop = me|(button)
        {
            let curSel = prop.getSelectedBaseForm()
            var picker = createColorPicker(button, curSel.borderColor)

            // Defer the undo entry until the color actually changes: `first` (closure-owned) is
            // true only on the first change, so opening then closing without picking leaves no
            // no-op undo entry, while later changes still replace the previous one (first = false).
            picker.sigColorChanged += func|prop, button, var first = true|(pk)
            {
                prop.pushTypedValue(pk.color().argb, BaseForm, #nameof(BaseForm.borderColor), first, true)
                first = false
                button.invalidate()
            }
        }
    }

    // Returns the outer contour color of a stroke form. Filled forms and text already use the
    // shared BaseForm outline, while these three forms need a second stroke around their core.
    mtd strokeOutlineColor()->Color
    {
        let curSel = .getSelectedBaseForm()
        switch .getSelectedFormType()
        {
        case FormLine:  return assume cast(*FormLine, curSel).outlineColor
        case FormArrow: return assume cast(*FormArrow, curSel).outlineColor
        case FormDraw:  return assume cast(*FormDraw, curSel).outlineColor
        }

        return Argb.Black
    }

    // Records the contour color against the concrete storage type, including FormLine inside
    // FormArrow. A stale color-picker callback can run after a selection change, so ignore a
    // selection that no longer has a stroke contour rather than reinterpret its bytes.
    mtd setStrokeOutlineColor(color: Color, first: bool)
    {
        switch .getSelectedFormType()
        {
        case FormLine, FormArrow: .pushTypedValue(color.argb, FormLine, #nameof(FormLine.outlineColor), first)
        case FormDraw: .pushTypedValue(color.argb, FormDraw, #nameof(FormDraw.outlineColor), first)
        }
    }

    // Adds the style cell for the outline drawn around a line, an arrow, or a drawing.
    mtd propStrokeOutlineColor(stack: *Wnd)
    {
        let curSel   = .getSelectedBaseForm()
        let formType = .getSelectedFormType()
        if curSel.subKind == .PixSel or
           (formType != FormLine and formType != FormArrow and formType != FormDraw) do
            return

        let button = createStyleButton(stack, appStrings().ui_PropOutline)
        button.iconPainter = func|prop = me|(?, bc, pos, ?)
        {
            bc.painter.setParams(.Antialiased)
            let color = prop.strokeOutlineColor()
            var rect  = pos
            rect.x = rect.horzCenter() - StyleGlyphSize * 0.5
            rect.y = rect.vertCenter() - StyleGlyphSize * 0.5
            rect.width, rect.height = StyleGlyphSize
            if not color.isOpaque() do
                bc.painter.drawRect(rect, Pen.createHatch(.CheckBoardLarge, Argb.DarkGray, 5))
            bc.painter.drawRect(rect, color, 5)
        }

        button.sigPopupRequested += func|prop = me|(button)
        {
            let picker = createColorPicker(button, prop.strokeOutlineColor())
            picker.sigColorChanged += func|prop, button, var first = true|(pk)
            {
                prop.setStrokeOutlineColor(pk.color(), first)
                first = false
                button.invalidate()
            }
        }
    }

    // Adds the style cell for the fill color of the selection, when its kind of form has a fill.
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
                let imgSel = assume cast(*FormImage, curSel)
                if imgSel.kind != .Image do
                    return
            }
        }

        let button = createStyleButton(stack, appStrings().ui_PropFill)
        button.iconPainter = func|prop = me|(?, bc, pos, ?)
        {
            bc.painter.setParams(.Antialiased)
            var curSel = prop.getSelectedBaseForm()
            var rect   = pos
            rect.x = rect.horzCenter() - StyleGlyphSize * 0.5
            rect.y = rect.vertCenter() - StyleGlyphSize * 0.5
            rect.width, rect.height = StyleGlyphSize
            var backCol = curSel.subKind == .PixSel ? g_Main!.pixSelFillCol : curSel.backColor
            if not backCol.isOpaque() do
                bc.painter.fillRect(rect, Brush.createHatch(.CheckBoardLarge, Argb.DarkGray))
            bc.painter.fillRect(rect, backCol)
        }

        button.sigPopupRequested += func|prop = me|(button)
        {
            var curSel  = prop.getSelectedBaseForm()
            var backCol = curSel.subKind == .PixSel ? g_Main!.pixSelFillCol : curSel.backColor
            var picker  = createColorPicker(button, backCol)
            if curSel.subKind == .PixSel
            {
                picker.sigColorChanged += func|button|(pk)
                {
                    g_Main!.pixSelFillCol = pk.color()
                    button.invalidate()
                }
            }
            else
            {
                // Defer the undo entry until the color actually changes: `first` (closure-owned) is
                // true only on the first change, so opening then closing without picking leaves no
                // no-op undo entry, while later changes still replace the previous one (first = false).
                picker.sigColorChanged += func|prop, button, var first = true|(pk)
                {
                    prop.pushTypedValue(pk.color().argb, BaseForm, #nameof(BaseForm.backColor), first, true)
                    first = false
                    button.invalidate()
                }
            }
        }
    }

    // Adds the style cell for the kind of a shape form.
    mtd propShape(stack: *Wnd)
    {
        let curSelType = .getSelectedFormType()
        if curSelType != FormShape do
            return
        let curSel = .getSelectedBaseForm()
        if curSel.subKind == .PixSel do
            return

        let button = createStyleButton(stack, appStrings().act_Shape)
        button.iconPainter = func|prop = me|(button, bc, pos, ?)
        {
            bc.painter.setParams(.Antialiased)
            let curSel = prop.getSelectedForm'FormShape()
            if not curSel do
                return
            drawShapeGlyph(bc.painter, curSel.kind, pos, button.themeColors().btnIcon_Icon)
        }

        button.sigPopupRequested += func|prop = me|(button)
        {
            prop.createPopupShapeKind(button, FormShape, #nameof(FormShape.kind))
        }
    }

    // Adds the style cell for the shape of a step marker.
    mtd propStep(stack: *Wnd)
    {
        let curSelType = .getSelectedFormType()
        if curSelType != FormStep do
            return

        let button = createStyleButton(stack, appStrings().act_Shape)
        button.iconPainter = func|prop = me|(button, bc, pos, ?)
        {
            bc.painter.setParams(.Antialiased)
            let curSel = prop.getSelectedForm'FormStep()
            if not curSel do
                return
            drawShapeGlyph(bc.painter, curSel.kind, pos, button.themeColors().btnIcon_Icon)
        }

        button.sigPopupRequested += func|prop = me|(button)
        {
            prop.createPopupShapeKind(button, FormStep, #nameof(FormStep.kind))
        }
    }

    // Adds the style cell for the cap at the start of a line or an arrow.
    mtd propStartCapStyle(stack: *Wnd)
    {
        let curSelType = .getSelectedFormType()
        if curSelType != FormLine and curSelType != FormArrow do
            return

        let button = createStyleButton(stack, appStrings().ui_PropStart)

        button.iconPainter = func|prop = me|(button, bc, pos, ?)
        {
            if prop.getSelectedFormType() != FormLine and prop.getSelectedFormType() != FormArrow do
                return
            let curSel = assume cast(*FormLine, prop.getSelectedBaseForm())
            bc.painter.setParams(.Antialiased)
            drawCapGlyph(bc.painter, curSel.beginCap, true, pos, button.themeColors().btnIcon_Icon)
        }

        button.sigPopupRequested += func|prop = me|(button)
        {
            prop.createPopupCapStyle(button, begin: true)
        }
    }

    // Adds the style cell for the cap at the end of a line or an arrow.
    mtd propEndCapStyle(stack: *Wnd)
    {
        let curSelType = .getSelectedFormType()
        if curSelType != FormLine and curSelType != FormArrow do
            return

        let button = createStyleButton(stack, appStrings().ui_PropEnd)
        button.iconPainter = func|prop = me|(button, bc, pos, ?)
        {
            if prop.getSelectedFormType() != FormLine and prop.getSelectedFormType() != FormArrow do
                return
            let curSel = assume cast(*FormLine, prop.getSelectedBaseForm())
            bc.painter.setParams(.Antialiased)
            drawCapGlyph(bc.painter, curSel.endCap, false, pos, button.themeColors().btnIcon_Icon)
        }

        button.sigPopupRequested += func|prop = me|(button)
        {
            prop.createPopupCapStyle(button, begin: false)
        }
    }

    // Adds the style cell for the dash pattern of an outline.
    mtd propDashStyle(stack: *Wnd)
    {
        let curSelType = .getSelectedFormType()
        if curSelType != FormShape and curSelType != FormLine and curSelType != FormArrow and curSelType != FormPolygon do
            return

        let curSel = .getSelectedBaseForm()
        if curSel.subKind == .Highlight or curSel.subKind == .PixSel do
            return

        let button = createStyleButton(stack, appStrings().ui_PropDash)
        button.iconPainter = func|prop = me|(button, bc, pos, ?)
        {
            bc.painter.setParams(.Antialiased)
            var curSel = prop.getSelectedBaseForm()
            var rect   = pos
            rect.inflate(-10, -10)
            var pen = Pen.createDash(curSel.dashStyle, button.themeColors().btnIcon_Icon, DashSize)
            pen.dashBlankScale = 0.25
            bc.painter.drawLine(rect.x, rect.vertCenter(), rect.right(), rect.vertCenter(), pen)
        }

        button.sigPopupRequested += func|prop = me|(button)
        {
            prop.createPopupDashStyle(button)
        }
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
            btn.sigPressed += func|prop = me|(?)
            {
                // The button outlives the panel build; the capture may be gone by the
                // time it is pressed, so guard instead of assuming it is still there.
                let capture = prop.main.getCapture()
                if not capture do
                    return
                capture.nextStepIndex = 1
            }
        }
    }

    // Asks for the text of the selected forms, starting from `curText`, and sets it as one undo
    // step. Returns the text the forms end up with.
    func editText(main: *MainWnd, curText: String)->String
    {
        var editOptions: EditDlgOptions
        editOptions.title = appStrings().dlg_TitleEnterText
        editOptions.text  = curText.toString()
        let dialog = EditDlg.createMultiLine(main.surface!, editOptions)
        if main.inPlaceEdit do
            dialog.surface?.setTopMost()

        if dialog.doModal() != Dialog.BtnOk do
            return curText
        let capture = main.getCapture()!
        let undo    = capture.newUndo(.SetText)
        undo.text = dialog.text()
        capture.pushUndo(undo)
        return undo.text
    }

    // Text-fill color swatch for a callout (the bubble fill/border reuse the generic
    // BaseForm color buttons; only the inner text color is callout-specific).
    mtd propCalloutText(stack: *Wnd)
    {
        if .getSelectedFormType() != FormCallout do
            return

        let button = createStyleButton(stack, appStrings().act_Text)
        button.iconPainter = func|prop = me|(?, bc, pos, ?)
        {
            bc.painter.setParams(.Antialiased)
            let curSel = prop.getSelectedForm'FormCallout()
            if not curSel do
                return
            var rect = pos
            rect.x = rect.horzCenter() - StyleGlyphSize * 0.5
            rect.y = rect.vertCenter() - StyleGlyphSize * 0.5
            rect.width, rect.height = StyleGlyphSize
            if not curSel.textColor.isOpaque() do
                bc.painter.fillRect(rect, Brush.createHatch(.CheckBoardLarge, Argb.DarkGray))
            bc.painter.fillRect(rect, curSel.textColor)
        }

        button.sigPopupRequested += func|prop = me|(button)
        {
            let curSel = prop.getSelectedForm'FormCallout()
            if not curSel do
                return
            var picker = createColorPicker(button, curSel.textColor)
            picker.sigColorChanged += func|prop, button, var first = true|(pk)
            {
                prop.pushTypedValue(pk.color().argb, FormCallout, #nameof(FormCallout.textColor), first)
                first = false
                button.invalidate()
            }
        }
    }

    mtd propPixSel()
    {
        let curSel = .getSelectedBaseForm()
        if curSel.subKind != .PixSel do
            return

        let topLayout = .topLayout
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
        if not .hasRealSelection() do
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
            edit.edit.sigCommitted += func|prop, name|(ed)
            {
                let {v, ?, ?} = catch StrConv.parseS32(ed.text())
                prop.pushTypedValue(v, BaseForm, name, true, true)
            }
        }

        // `name` must be a view of storage that outlives the grid (a literal): the
        // TypeValue below keeps the view, and a by-value String parameter would hand
        // it a dangling pointer into this frame's small-string storage.
        func addRow(prop: *PropWnd, name: string)->*Wnd
        {
            let v    = Swag.TypeValue{name: name}
            let item = prop.grid.addItem(v, null, null, 40, .None)

            // No NoFocus: the rows embed edit boxes, so they stay keyboard-navigable
            item.flags.add(.NoSeparator)
            return StackLayoutCtrl.create(item.line, .HorizontalFit, {0, 0, 0, 40})
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
}
