// Geometry of the head rows of the property panel, which follow the rows of the inspector.
const ColorSwatchSize     = 20.0     // Side of the swatch of a colour row.
const ChoiceGap           = 4.0      // Air between two glyphs of a choice row.
const ChoiceGlyphSize     = 14.0     // Side of the shape a shape glyph draws.
const ChoiceGlyphInset    = 6.0      // Air between a dash sample and the edges of its cell.
const ChoiceStroke        = 1.5      // Weight of the strokes a glyph draws.
const CapGlyphStroke      = 2.5      // Weight of the stroke a line end is drawn on: the ends scale with it.
const MaxLayerRows        = 12       // Layers the inspector lists for several objects.
const PositionLetterWidth = 14.0     // Width of the letter before a value of the position strip.

// A colour a head row of the property panel edits on the selection.
enum ColorSlot
{
    Border            // The outline of a shape, the stroke of a line, the outline of a text.
    StrokeOutline     // The contour drawn around a line, an arrow or a drawing.
    Fill              // The fill of a shape, a text, a callout or a step.
    CalloutText       // The words of a callout.
}

// A choice a head row of the property panel offers as a row of glyphs.
enum ChoiceRow
{
    ShapeKind     // The kind of a shape.
    StepKind      // The shape of a step marker.
    Dash          // The dash pattern of an outline.
    StartCap      // The end at the start of a line.
    EndCap        // The end at the end of a line.
}

impl PropWnd
{
    // Appends a section label opening the head rows that follow.
    mtd addHeadSection(label: string)
    {
        SectionLabel.create(.topLayout, label, {0, 0, 0, .themeMetrics().inspector_SectionHeight})
    }

    // Appends a head row and returns the cell its editor fills: `label` in the label column of the
    // inspector and the editor after it, or, without a label, the editor across the whole row.
    mtd addHeadRow(label: string)->*Wnd
    {
        let metrics  = .themeMetrics()
        let height   = metrics.control_InspectorHeight
        with let row = Wnd.create'Wnd(.topLayout, {0, 0, 0, height})
        {
            .backgroundStyle = .Transparent
        }

        if label.count > 0
        {
            with let name = Label.create(row, label, {0, 0, metrics.inspector_LabelWidth + metrics.inspector_LabelGap, height}, flags: .SecondaryText)
            {
                .dockStyle = .Left
                .setTextAlignment(.Left, .Center)
            }
        }

        with let cell = Wnd.create'Wnd(row)
        {
            .dockStyle       = .Center
            .backgroundStyle = .Transparent
        }

        return cell
    }

    // Appends the name of a choice whose glyphs need the whole row, on a line of its own.
    mtd addHeadCaption(label: string)
    {
        with let name = Label.create(.topLayout, label, {0, 0, 0, .themeMetrics().control_InspectorHeight}, flags: .SecondaryText)
        {
            .setTextAlignment(.Left, .Center)
        }
    }

    // Returns the colour `slot` stands for on the selection, or on the model of the tool.
    mtd slotColor(slot: ColorSlot)->Color
    {
        let form = .getSelectedBaseForm()
        switch #complete slot
        {
        case .Border:
            return form.borderColor

        case .StrokeOutline:
            return .strokeOutlineColor()

        case .Fill:
            return form.subKind == .PixSel ? .main.pixSelFillCol : form.backColor

        case .CalloutText:
            let callout = .getSelectedForm'FormCallout()
            return callout ? callout.textColor : Argb.Black
        }
    }

    // Sets the colour `slot` stands for, as one undo step that replaces the previous step of the
    // same pick unless `first`.
    mtd setSlotColor(slot: ColorSlot, color: Color, first: bool)
    {
        switch #complete slot
        {
        case .Border:
            .pushTypedValue(color.argb, BaseForm, #nameof(BaseForm.borderColor), first, true)

        case .StrokeOutline:
            .setStrokeOutlineColor(color, first)

        case .Fill:
            if .getSelectedBaseForm().subKind == .PixSel do
                .main.pixSelFillCol = color
            else do
                .pushTypedValue(color.argb, BaseForm, #nameof(BaseForm.backColor), first, true)

        case .CalloutText:
            .pushTypedValue(color.argb, FormCallout, #nameof(FormCallout.textColor), first)
        }
    }

    // Appends a colour row: a swatch and its value in hex, which open the colour picker.
    mtd addColorRow(label: string, slot: ColorSlot)
    {
        let cell        = .addHeadRow(label)
        with let button = IconButton.create(cell, {}, {}, flags: .Popup | .Flat)
        {
            .dockStyle = .Center
            .setArrowPosition(.None)
            .setCheckIndicator(.None)
            .toolTip = label
        }

        button.iconPainter = func|prop = me, slot|(btn, bc, pos, _)
        {
            let metrics = btn.themeMetrics()
            let colors  = btn.themeColors()
            let painter = bc.painter
            let color   = prop.slotColor(slot)
            let side    = ColorSwatchSize
            let swatch  = Math.Rectangle{pos.x, Math.round(pos.vertCenter() - side * 0.5), side, side}

            painter.setParams(.Antialiased)
            let font = btn.theme().createDefaultFontFs(metrics.defaultFontSize - 1)

            // No colour at all is a hatched swatch, and says so.
            if not color.a
            {
                painter.fillRoundRect(swatch, metrics.corner_Chip, metrics.corner_Chip, Brush.createHatch(.DiagonalForwardLight, colors.faintText))
                painter.drawRoundRect(swatch, metrics.corner_Chip, metrics.corner_Chip, colors.line, metrics.separator_HairlineSize)
                painter.drawString(swatch.right() + metrics.inspector_LabelGap, font.opticalLineTop(pos.vertCenter()), appStrings().ui_NoColor, font, colors.softText)
                return
            }

            if not color.isOpaque() do
                painter.fillRoundRect(swatch, metrics.corner_Chip, metrics.corner_Chip, Brush.createHatch(.CheckBoardLarge, Argb.DarkGray))
            painter.fillRoundRect(swatch, metrics.corner_Chip, metrics.corner_Chip, color)
            painter.drawRoundRect(swatch, metrics.corner_Chip, metrics.corner_Chip, colors.line, metrics.separator_HairlineSize)

            // The value is a measure, so it is set in the fixed-width family; an opacity under
            // full follows it in percent.
            var hex = Format.toString("%{X02}%{X02}%{X02}", color.r, color.g, color.b)
            if color.a != 255
            {
                // The percent sign is appended rather than formatted: '%' is the placeholder itself.
                hex += Format.toString(" · %", cast(s32, Math.round(cast(f32, color.a) * 100 / 255)))
                hex += " %"
            }

            painter.drawString(swatch.right() + metrics.inspector_LabelGap, font.opticalLineTop(pos.vertCenter()), hex, font, colors.softText)
        }

        button.sigPopupRequested += func|prop = me, slot, label|(button)
        {
            let popover = ColorPopover.open(assume cast(*IconButton, button), label, prop.slotColor(slot), &prop.main.recentColors)
            popover.standBeside(prop.main.inspector, button)

            // The undo step waits for the colour to change: opening the popover and closing it
            // without a pick leaves none, and later picks replace the step of the first.
            popover.sigColorChanged += func|prop, slot, button, var first = true|(pop)
            {
                prop.setSlotColor(slot, pop.color, first)
                first = false
                button.invalidate()
            }
        }
    }

    // Returns how many glyphs the choice `row` offers.
    func choiceCount(row: ChoiceRow)->u32
    {
        switch #complete row
        {
        case .ShapeKind, .StepKind:
            return cast(u32, FormShapeKind.count)

        case .Dash:
            return cast(u32, DashStyle.count) - 1     // `Pattern` takes its lengths from the pen and shows nothing alone.

        case .StartCap, .EndCap:
            return cast(u32, LineCapStyle.count)
        }
    }

    // Returns the value glyph `index` of the choice `row` stands for.
    func choiceValue(row: ChoiceRow, index: u32)->u32
    {
        if row == .Dash and index >= cast(u32, DashStyle.Pattern) do
            return index + 1
        return index
    }

    // Returns the value of the choice `row` on the selection, or on the model of the tool.
    mtd choiceCurrent(row: ChoiceRow)->u32
    {
        switch #complete row
        {
        case .ShapeKind:
            let shape = .getSelectedForm'FormShape()
            if shape do
                return cast(u32, shape.kind)

        case .StepKind:
            let step = .getSelectedForm'FormStep()
            if step do
                return cast(u32, step.kind)

        case .Dash:
            return cast(u32, .getSelectedBaseForm().dashStyle)

        case .StartCap:
            if .getSelectedBaseForm() is FormLine as line do
                return cast(u32, line.beginCap)

        case .EndCap:
            if .getSelectedBaseForm() is FormLine as line do
                return cast(u32, line.endCap)
        }

        return 0
    }

    // Sets the choice `row` to `value` on the selection, or on the model of the tool.
    mtd applyChoice(row: ChoiceRow, value: u32)
    {
        switch #complete row
        {
        case .ShapeKind: .pushTypedValue(value, FormShape, #nameof(FormShape.kind), true)
        case .StepKind:  .pushTypedValue(value, FormStep, #nameof(FormStep.kind), true)
        case .Dash:      .pushTypedValue(value, BaseForm, #nameof(BaseForm.dashStyle), true, true)
        case .StartCap:  .pushTypedValue(value, FormLine, #nameof(FormLine.beginCap), true)
        case .EndCap:    .pushTypedValue(value, FormLine, #nameof(FormLine.endCap), true)
        }
    }

    // Paints the glyph of `value` of the choice `row` in `pos`.
    func paintChoice(painter: *Painter, row: ChoiceRow, value: u32, pos: Math.Rectangle, color: Color)
    {
        painter.setParams(.Antialiased)
        switch #complete row
        {
        case .ShapeKind, .StepKind:
            drawShapeGlyph(painter, cast(FormShapeKind, value), pos, color, ChoiceGlyphSize)

        case .Dash:
            var rect = pos
            rect.inflate(-ChoiceGlyphInset, 0)
            var pen = Pen.createDash(cast(DashStyle, value), color, ChoiceStroke)
            pen.dashBlankScale = 0.5
            painter.drawLine(rect.x, rect.vertCenter(), rect.right(), rect.vertCenter(), pen)

        case .StartCap, .EndCap:
            drawCapGlyph(painter, cast(LineCapStyle, value), row == .StartCap, pos, color, CapGlyphStroke)
        }
    }

    // Appends the glyphs of the choice `row` to `cell`, the current one checked.
    mtd addChoiceGlyphs(cell: *Wnd, row: ChoiceRow, tip: string)
    {
        let metrics    = .themeMetrics()
        let size       = metrics.control_InspectorHeight
        with let stack = StackLayoutCtrl.create(cell, .Left, {})
        {
            .dockStyle = .Center
            .spacing   = ChoiceGap
        }

        let current = .choiceCurrent(row)
        for i in choiceCount(row)
        {
            let value = choiceValue(row, i)

            // A radio: a press on the glyph already chosen keeps it chosen; the row unchecks the
            // others itself.
            with let button = IconButton.create(stack, {}, {0, 0, size, size}, flags: .Radio)
            {
                .userData = enumToUserData(value)
                .toolTip  = tip
                .setForm(.RoundedRectangle)
                .setCheckIndicator(.Frame)
                .setChecked(value == current)
            }

            // The glyph takes the whole cell: a button without an icon hands its painter no room.
            button.iconPainter = func|row|(btn, bc, _, flags)
            {
                let colors = btn.themeColors()
                let color  = flags & .Checked ? colors.btnIcon_CheckedIcon : colors.btnIcon_Icon
                paintChoice(bc.painter, row, enumFromUserData'u32(btn.userData), btn.clientRect(), color)
            }

            button.sigPressed += func|prop = me, row, stack|(btn)
            {
                let value = enumFromUserData'u32(btn.userData)
                prop.applyChoice(row, value)
                for other in stack.children
                {
                    let glyph = assume cast(*IconButton, other)
                    glyph.setChecked(enumFromUserData'u32(glyph.userData) == value)
                }
            }
        }
    }

    // Returns the colour rows the selection has, with the name each colour takes on it.
    mtd addColorRows()
    {
        let form     = .getSelectedBaseForm()
        let formType = .getSelectedFormType()
        let pixSel   = form.subKind == .PixSel
        let isStroke = formType == FormLine or formType == FormArrow or formType == FormDraw

        var hasFill = pixSel or not isStroke
        if not pixSel and formType == FormImage do
            hasFill = (assume cast(*FormImage, form)).kind == .Image

        let hasBorder = form.subKind != .Highlight and not pixSel
        if not hasBorder and not hasFill do
            return

        // Several objects share what follows: the section says so.
        let capture = .main.getCapture()
        let several = capture and capture.selection.count > 1
        .addHeadSection(several ? appStrings().ui_Common : appStrings().ui_PropColor)

        // A stroke is its colour, then its outline; a shape its fill, its words, then its outline.
        if isStroke and not pixSel
        {
            if hasBorder do
                .addColorRow(appStrings().ui_PropColor, .Border)
            .addColorRow(appStrings().ui_PropOutline, .StrokeOutline)
            return
        }

        if hasFill do
            .addColorRow(appStrings().ui_PropFill, .Fill)
        if formType == FormCallout do
            .addColorRow(appStrings().act_Text, .CalloutText)
        if hasBorder do
            .addColorRow(formType == FormStep ? appStrings().act_Text : appStrings().ui_PropOutline, .Border)
    }

    // Appends the glyph choices of the selection: the kind of a shape or a step, the dash of an
    // outline, the two ends of a line.
    mtd addStyleRows()
    {
        let form     = .getSelectedBaseForm()
        let formType = .getSelectedFormType()
        let pixSel   = form.subKind == .PixSel
        let isLine   = formType == FormLine or formType == FormArrow
        let hasShape = (formType == FormShape and not pixSel) or formType == FormStep
        let hasDash  = (formType == FormShape or isLine or formType == FormPolygon) and form.subKind == .None
        if not hasShape and not hasDash and not isLine do
            return

        .addHeadSection(appStrings().ui_PropStyle)
        if hasShape
        {
            let row: ChoiceRow = formType == FormStep ? .StepKind : .ShapeKind
            .addChoiceGlyphs(.addHeadRow(appStrings().prop_Kind), row, appStrings().act_Shape)
        }

        if hasDash do
            .addChoiceGlyphs(.addHeadRow(appStrings().ui_PropDash), .Dash, appStrings().ui_PropDash)

        if isLine
        {
            .addHeadCaption(appStrings().ui_PropStart)
            .addChoiceGlyphs(.addHeadRow(""), .StartCap, appStrings().ui_PropStart)
            .addHeadCaption(appStrings().ui_PropEnd)
            .addChoiceGlyphs(.addHeadRow(""), .EndCap, appStrings().ui_PropEnd)
        }
    }

    // Appends the kinds of a mask as a list, one row per kind with its glyph, the kind in force on
    // the Arc ground: changing it keeps where the mask stands.
    mtd addMaskKindRows()
    {
        let found = .getSelectedForm'FormImage()
        if not found do
            return
        if found.subKind != .None do
            return
        let current = found.kind

        .addHeadSection(appStrings().prop_Kind)
        const Kinds  = [FormImageKind.Image, FormImageKind.Blur, FormImageKind.Pixelate, FormImageKind.Zoom, FormImageKind.Capture]
        const Glyphs = [CaptureIcons.Image, CaptureIcons.Blur, CaptureIcons.Pixelate, CaptureIcons.Zoom, CaptureIcons.Cube]
        for kind, i in Kinds
        {
            with let button = IconButton.create(.addHeadRow(""), .main.icon(Glyphs[i], .themeMetrics().menuPopup_IconSize), {}, flags: .Radio)
            {
                .dockStyle = .Center
                .userData  = enumToUserData(kind)
                .setText(quickStyleKindName(kind))
                .setTextPosition(.Right)
                .setForm(.RoundedRectangle)
                .setCheckIndicator(.Frame)
                .setChecked(current == kind)
            }

            // The panel is built again once the kind changed, which checks the new one.
            button.sigPressed += func|prop = me|(btn)
            {
                prop.pushTypedValue(cast(u32, enumFromUserData'FormImageKind(btn.userData)), FormImage, #nameof(FormImage.kind), true)
            }
        }
    }

    // Appends what several selected objects share beyond their settings: their alignment, their
    // order, and the layers of the capture with the selected ones chosen.
    mtd addArrangeRows()
    {
        let capture = .main.getCapture()
        if not capture or capture.selection.count < 2 do
            return

        let texts   = appStrings()
        let metrics = .themeMetrics()
        let size    = metrics.control_InspectorHeight

        .addHeadSection(texts.ui_MenuAlign)
        with let aligns = StackLayoutCtrl.create(.addHeadRow(""), .HorizontalFit, {})
        {
            .dockStyle = .Center
            .spacing   = ChoiceGap
        }

        const AlignIds    = [ActionAlign.AlignLeft, ActionAlign.AlignCenter, ActionAlign.AlignRight, ActionAlign.AlignTop, ActionAlign.AlignMiddle, ActionAlign.AlignBottom]
        const AlignGlyphs = [CaptureIcons.TextAlignLeft, CaptureIcons.TextAlignCenter, CaptureIcons.TextAlignRight, CaptureIcons.AlignTop, CaptureIcons.AlignMiddle, CaptureIcons.AlignBottom]
        for id, i in AlignIds
        {
            with let button = IconButton.create(aligns, .main.icon(AlignGlyphs[i], metrics.menuPopup_IconSize), {0, 0, size, size}, id)
            {
                .updateFlags(.IconOnly)
                .setForm(.RoundedRectangle)
            }
        }

        .addHeadSection(texts.ui_MenuArrange)
        const Arrange = [ActionAlign.SendToFront, ActionAlign.SendToBack, ActionAlign.MoveForward, ActionAlign.MoveBackward]
        let arrangeNames = [texts.act_SendToFront, texts.act_SendToBack, texts.act_MoveForward, texts.act_MoveBackward]
        for pair in 2
        {
            with let row = StackLayoutCtrl.create(.addHeadRow(""), .HorizontalFit, {})
            {
                .dockStyle = .Center
                .spacing   = ChoiceGap
            }

            // Words alone: the glyphs the commands carry for the lens would crowd a half column.
            for k in 2
            {
                let id = Arrange[pair * 2 + k]
                with let button = PushButton.create(row, arrangeNames[pair * 2 + k], {0, 0, 0, size}, form: .Flat)
                {
                    .sigPressed += func|prop = me, id|(_) { prop.main.postCommandEvent(id) }
                }
            }
        }

        // The layers, the one in front first; a row selects its object alone.
        .addHeadSection(texts.ui_Layers)
        var shown = 0
        for i in reversed(capture.forms.count)
        {
            if shown == MaxLayerRows do
                break
            shown += 1

            let form = capture.forms[i]
            let mode = MainWnd.formToEditMode(form)

            // A layer is named by its words when it has some, by its kind otherwise.
            var name: String = MainWnd.editModeName(mode)
            let words        = formEditableText(form)
            if words and not words.isEmpty() do
                name = words[]
            with let button = IconButton.create(.addHeadRow(""), .main.icon(MainWnd.editModeIcon(mode), metrics.menuPopup_IconSize), {}, flags: .Radio)
            {
                .dockStyle = .Center
                .userData  = cast(*void, cast(u64, i))
                .setText(name)
                .setTextPosition(.Right)
                .setForm(.RoundedRectangle)
                .setCheckIndicator(.Frame)
                .setChecked(capture.selection.contains(i))
                .sigPressed += func|prop = me|(btn)
                {
                    let capture = prop.main.getCapture()
                    if not capture do
                        return
                    capture.selection.clear()
                    capture.selection.add(cast(u64, btn.userData))
                    capture.selectionHasChanged()
                }
            }
        }
    }

    // Returns the outer contour color of a stroke form. Filled forms and text already use the
    // shared BaseForm outline, while these three forms need a second stroke around their core.
    // An arrow is a line, so it answers through the line case.
    mtd strokeOutlineColor()->Color
    {
        switch .getSelectedBaseForm()
        {
        case FormLine as line: return line.outlineColor
        case FormDraw as draw: return draw.outlineColor
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

    // The step type combo is generated by the grid (FormStep.typeIndex attribute); only the
    // "reset the global counter" command needs a row of its own.
    mtd propNextStep()
    {
        if .getSelectedFormType() != FormStep do
            return

        with let button = PushButton.create(.addHeadRow(""), "", id: ActionEdit.ResetSteps, form: .Flat)
        {
            .dockStyle = .Center
        }
    }

    // The commands of a pixel selection, one row each.
    mtd propPixSel()
    {
        if .getSelectedBaseForm().subKind != .PixSel do
            return

        for id in [ActionPixSel.Fill, ActionPixSel.SmartFill, ActionPixSel.Clear, ActionPixSel.SmartMove]
        {
            with let button = PushButton.create(.addHeadRow(""), "", id: id)
            {
                .dockStyle = .Center
            }
        }
    }

    // The position strip: X, Y, W and H in one row at the end of the generated settings, each a
    // faint letter and a value in the fixed-width family. Box forms only; X and Y may be negative,
    // since a form may stand outside the capture.
    mtd propXY()
    {
        if not .hasRealSelection() do
            return
        let t = .getSelectedFormType()
        if t != FormShape and t != FormText and t != FormCallout do
            return
        let curSel = .getSelectedBaseForm()

        func addBox(prop: *PropWnd, parent: *Wnd, label: string, name: string, value: s32, signed: bool)
        {
            let edit = EditCtrl.create(parent, label, Format.toString("%", value), flags: .ReleaseFocusOnEnterOrEscape)
            edit.setLayoutMetrics(PositionLetterWidth, 0, 0)
            edit.label.updateFlags(.SecondaryText)
            edit.edit.style.setFont(prop.theme().res.fontDefaultFs)

            if signed do
                edit.edit.setSignedIntegerRange()
            else do
                edit.edit.setUnsignedIntegerRange(1, 10000)
            edit.edit.sigCommitted += func|prop, name|(ed)
            {
                let {value: v, eat: _, ovf: _} = catch StrConv.parseS32(ed.text())
                prop.pushTypedValue(v, BaseForm, name, true, true)
            }
        }

        // The position opens with its own section label, as the other groups of settings.
        let section = .grid.addItem(Swag.TypeValue{name: "position.section"}, null, null, .themeMetrics().inspector_SectionHeight, .None)
        section.flags.add(.NoSeparator | .NoFocus)
        SectionLabel.create(section.line, appStrings().ui_PropPosition, {0, 0, 0, .themeMetrics().inspector_SectionHeight}).dockStyle = .Center

        // `name` must be a view of storage that outlives the grid (a literal): the TypeValue below
        // keeps the view, and a by-value String would hand it a dangling pointer.
        let v    = Swag.TypeValue{name: appStrings().ui_PropPosition}
        let item = .grid.addItem(v, null, null, .themeMetrics().control_InspectorHeight + GridRowInset, .None)
        item.flags.add(.NoSeparator)
        with let strip = StackLayoutCtrl.create(item.line, .HorizontalFit, {0, 0, 0, .themeMetrics().control_InspectorHeight})
        {
            .spacing = ChoiceGap
        }

        let texts = appStrings()
        addBox(me, strip, texts.ui_PosX, #nameof(BaseForm.x), curSel.x, true)
        addBox(me, strip, texts.ui_PosY, #nameof(BaseForm.y), curSel.y, true)
        addBox(me, strip, texts.ui_PosW, #nameof(BaseForm.w), curSel.w, false)
        addBox(me, strip, texts.ui_PosH, #nameof(BaseForm.h), curSel.h, false)
        .grid.endAppendRows()
    }
}
