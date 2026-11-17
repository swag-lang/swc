// Geometry of the sample a line-end glyph draws.
const CapPlainStroke  = 6.0     // Stroke a plain end is drawn on: heavy enough to show its shape.
const CapAnchorStroke = 2.0     // Stroke an anchor is drawn on.
const CapAnchorScale  = 5.0     // Scale across the stroke, so anchors read at glyph size.
const CapAnchorDepth  = 1.0     // Keep the anchor short enough to leave a visible shaft.
const CapGlyphInset   = 5.0     // Air between the sample and the sides of its cell.

// Air the panel layout of the property grid keeps before each of its rows: the label column of a
// generated field is that much narrower than the inspector's, so both columns end on one edge.
const GridRowInset = 8.0

// Width of the value read beside a slider of the inspector: "100 %" in the fixed-width family.
// Wider, the track shortens and the value stands apart from it.
const SliderValueWidth = 44.0

// The enum popup buttons stash the value they represent in the untyped `userData` slot.
func(T) enumToUserData(value: T)->*void => cast(*void, cast(u64, value))

func(T) enumFromStoredValue(raw: u64)->T
{
    for value in T where cast(u64, value) == raw do
        return value
    Swag.panic("stored value is not a declared enum member", #curlocation)
}

func(T) enumFromUserData(data: *void?)->T => enumFromStoredValue'T(cast(u64, data))

// Reports whether a line end is one the "Start Size" and "End Size" rows can resize.
//
// The anchors are decorations placed at the end of a line and are scaled by those rows; the four
// plain ends are the terminal of the stroke itself and are as large as the stroke is thick, the
// way a cap is defined everywhere else. Showing a size row that a plain end silently ignores is
// what made the two rows read as broken; each anchor is the resizable form of the plain end
// beside it in the list, so the size is one choice away.
func capStyleHasSize(cap: LineCapStyle)->bool
{
    switch #complete cap
    {
    case .None, .Triangle, .Round, .Square: return false
    case .ArrowAnchor, .ArrowAnchor2, .SquareAnchor, .RoundAnchor: return true
    }
}

// Paints a line-end sample in `pos`, the end on the side `begin` names and the cap inside the cell.
//
// A plain end is the shape of the stroke itself: on a thin line a square, a round and a pointed
// end are the same few pixels. It is drawn on a heavy stroke, with a hairline tick where the line
// stops, so a square end shows its overhang and a round or a pointed one its bulge. An anchor is
// a mark set on the line, drawn on a thin stroke at a size that reads.
func drawCapGlyph(painter: *Painter, cap: LineCapStyle, begin: bool, pos: Math.Rectangle, color: Color)
{
    let plain = not capStyleHasSize(cap)
    let size  = plain ? CapPlainStroke : CapAnchorStroke
    var pen   = Pen.createSolid(color, size)
    pen.capBegScaleX, pen.capEndScaleX = CapAnchorScale
    pen.capBegScaleY, pen.capEndScaleY = CapAnchorDepth
    pen.begCapStyle, pen.endCapStyle   = LineCapStyle.None

    let {l: reach} = Painter.capStyleExtent(cap, size, CapAnchorScale)
    let y          = pos.vertCenter()
    var x0         = pos.x + CapGlyphInset
    var x1         = pos.right() - CapGlyphInset
    var stop: f32
    if begin
    {
        pen.begCapStyle = cap
        x0   += reach
        stop = x0
    }
    else
    {
        pen.endCapStyle = cap
        x1   -= reach
        stop = x1
    }

    painter.drawLine(x0, y, x1, y, pen)
    if plain
    {
        let tick = size * 0.5 + 3
        painter.drawLine(stop, y - tick, stop, y + tick, Pen.createSolid(color.withAlpha(64), 1))
    }
}

// The ellipse/rectangle/round-rectangle glyph of a shape kind, `size` wide, centred in `pos`.
func drawShapeGlyph(painter: *Painter, kind: FormShapeKind, pos: Math.Rectangle, color: Color, size: f32)
{
    let rect = Math.Rectangle{pos.horzCenter() - size * 0.5, pos.vertCenter() - size * 0.5, size, size}

    // The stroke is the interface outline weight: heavier, it closes the counter of the shape and
    // the sample reads as a filled blob.
    let stroke = 1.4'f32

    switch #complete kind
    {
    case .Ellipse:
        let radius = rect.width * 0.5
        painter.drawEllipse(pos.horzCenter(), pos.vertCenter(), radius, radius, color, stroke)

    case .Rectangle:
        painter.drawRect(rect, color, stroke)

    case .RoundRectangle:
        painter.drawRoundRect(rect, size * 0.25, size * 0.25, color, stroke)
    }
}

// Geometry of the head rows of the property panel, which follow the rows of the inspector.
const ColorSwatchSize     = 20.0     // Side of the swatch of a colour row.
const ChoiceGap           = 4.0      // Air between two glyphs of a choice row.
const ChoiceGlyphSize     = 14.0     // Side of the shape a shape glyph draws.
const ChoiceGlyphInset    = 5.0      // Air between a dash sample and the edges of its cell.
const DashStroke          = 2.0      // Weight of a dash sample: heavy enough for its dots, light enough for its gaps.
const ChoiceWideCellWidth = 34.0     // Shared width of shape and dash choices; holds a whole dash pattern.
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

// The tool properties panel. The exotic editors (color swatches, shape/cap/dash popup
// buttons...) are hand-built rows in `topLayout`; every plain field (sliders, checkboxes,
// combos) is generated below them by a Properties grid from the attributes carried by the
// form fields (see BaseForm), with the edits recorded into the capture's own undo
// timeline. The compact x/y and w/h rows are hand-appended at the end of the grid.
struct PropWnd
{
    using frameWnd: FrameWnd

    late
    {
        topLayout: *StackLayoutCtrl
        grid:      *Properties
        main:      *MainWnd
    }

    // Concrete type bound to the grid (BaseForm for an heterogeneous selection)
    late gridBindType: typeinfo

    // Set when a change handler needs the whole panel rebuilt: done on the next frame,
    // never from inside the grid's own change notification.
    needRebuild: bool

    // A colour popover of the panel is open. Its button stands in a row, and a rebuild would
    // destroy the row, the button and the popover with it while the colour is still being
    // picked: the rebuild waits for the popover to close.
    colorPicking: bool
}

impl PropWnd
{
    // Reports whether the settings are scrolled under the presets above them, and whether more
    // of them lie below the visible part.
    mtd scrollEdges()->{above: bool, below: bool}
    {
        let scroll = .grid.scrollWnd
        let shown  = scroll.view.clientRect().height
        return {scroll.view.scrollPos.y > 0.5, scroll.view.scrollPos.y + shown < scroll.scrollSize.y - 0.5}
    }

    mtd hasRealSelection()->bool
    {
        let capture = .main.getCapture()
        return capture and not capture.selection.isEmpty()
    }

    mtd getSelectedBaseForm()->*BaseForm
    {
        let capture = .main.getCapture()
        if not capture or capture.selection.isEmpty()
        {
            let iform = .main.editModeToModel(.main.editMode)
            return iform
        }

        return unwrap capture.getSelectedBaseForm()
    }

    // Returns the selected form as a `T`, or null when the selection is not one.
    //
    // An editor is built for the kind that was selected, but the painters and the handlers it
    // installs run again long after that: a panel is rebuilt from an event, a frame is not, so by
    // the time one of them fires the selection may be another kind entirely. Casting whatever
    // survives to the kind the editor was made for reads one form's bytes as another's, and a
    // field the two do not share comes back as whatever lay at that offset — which is how a
    // '#complete switch' over a three-value enum ends up with a value it has no case for.
    mtd(T) getSelectedForm()->*T? => (catch cast(*T?, .getSelectedBaseForm()))

    mtd getSelectedFormType()->typeinfo
    {
        let capture = .main.getCapture()
        if not capture or capture.selection.isEmpty()
        {
            let iform = .main.editModeToModel(.main.editMode)
            return Swag.kindOf(iform)
        }

        return unwrap capture.getSelectedFormType()
    }

    // Sets field `name` to `val`: on the model of the active tool when nothing is selected,
    // otherwise on the selected forms as one undo step that replaces the previous step of the same
    // edit unless `first`. `common` applies the value to every selected kind of form.
    mtd pushTypedValue(val: u32, type: typeinfo, name: string, first: bool, common = false)
    {
        let capture = .main.getCapture()

        // Change model
        if not capture or not capture.selection.count
        {
            let form   = .getSelectedBaseForm()
            let field  = unwrap Reflection.findField(type, name)
            var valU32 = val
            Reflection.writeFieldValue(form, field, &valU32)
        }
        // Change selection
        else
        {
            if not first do
                capture.undo()
            with let undo = capture.newUndo(.SetTypedValue)
            {
                .valU32 = val
                if not common do
                    .mdlType = type
                .valRef = unwrap Reflection.findField(type, name)
            }

            capture.pushUndo(undo)
        }

        .main.quickWnd.updateSelection()
        .main.editWnd.invalidate()

        // A style cell sets a value the generated rows read to decide whether they belong on the
        // panel at all — the line ends decide their own size rows, a shape kind decides its
        // corner row. Rebuild on the next frame so the panel follows the cell that was just
        // clicked instead of waiting for the next selection change.
        .needRebuild = true
    }

    // Returns the type the settings of the selection are edited through: the kind of every
    // selected form when they share one, a line for lines and arrows together (an arrow is a
    // line with its own defaults), and the base of every form otherwise. Without a selection,
    // the kind of the model of the tool.
    mtd commonFormType()->typeinfo
    {
        let capture = .main.getCapture()
        if not capture or not capture.selection.count do
            return .getSelectedFormType()

        var allSame  = true
        var lineOnly = true
        var firstType: typeinfo?
        foreachSelected'BaseForm(capture, capture.selection)
        {
            let t = Swag.kindOf(itf)
            if not firstType do
                firstType = t
            elif t != firstType do
                allSame = false
            if t != FormLine and t != FormArrow do
                lineOnly = false
        }

        if allSame do
            return firstType orelse #typeof(BaseForm)
        if lineOnly do
            return FormLine
        return BaseForm
    }

    // Bind the property grid to the current selection (or to the tool model when nothing
    // is selected). The grid builds one row per attributed field of the bound type — see
    // the Properties attributes on the form structs — and edits every selected instance
    // at once, recording each change into the capture's own undo timeline.
    mtd bindGrid()
    {
        let capture = .main.getCapture()
        var bases: Array'(*u8?)

        if not capture or not capture.selection.count
        {
            // Tool model: direct edition, no undo (as before)
            let mdl = .main.editModeToModel(.main.editMode)
            .gridBindType = Swag.kindOf(mdl)
            bases.add(cast(*u8?, mdl.buffer))
            .grid.setExternalUndoMgr(null)
            .grid.setUndoEnabled(false)
        }
        else
        {
            foreachSelected'BaseForm(capture, capture.selection)
            {
                bases.add(cast(*u8?, form))
            }

            .gridBindType = .commonFormType()

            .grid.setExternalUndoMgr(&capture.undoMgr)
            .grid.setUndoEnabled(true)
        }

        .grid.addStructMulti(.gridBindType, cast([..] *u8, bases.toSlice()), null, onlyNamed: true)

        // The generated border-size slider serves every form as "Thickness"; a text form
        // edits its glyph outline instead: matching label and a much thinner range. The
        // slider keeps a normalized position, so re-set the value after the new range.
        if .gridBindType == FormText
        {
            for item in .grid.items
            {
                let it = unwrap item
                if it.typeValue.name != #nameof(BaseForm.borderSize) or it.sliderBox == null do
                    continue
                let sliderBox = it.sliderBox
                sliderBox.label.setText(appStrings().ui_Outline)
                sliderBox.setSignedBounds(cast(MinTextBorderSize), cast(MaxTextBorderSize))
                sliderBox.setValueWithoutGesture(.getSelectedBaseForm().borderSize)
            }
        }
    }

    // A panel category is a quiet section cue, like the labels used by the other standard
    // applications. Keep the system face at its normal weight and let the live theme supply
    // its secondary ink; bold property-grid headings read as a second title hierarchy here.
    // The sections of the generated settings read like those of the head: small spaced capitals,
    // flush with the labels of the column, with no air of their own past the height of a row.
    mtd styleCategoryLabels()
    {
        for item in .grid.items
        {
            let it = unwrap item
            if not it.flags.has(.Category) or it.label == null do
                continue
            it.line.margin.y = 0
            it.line.margin.w = 0
        }
    }

    // Puts the labels of the generated fields in the label column of the inspector, flush with
    // the labels of the head rows, so every editor of the column starts on one edge. A label
    // longer than the column in the current language widens it for the whole panel rather than
    // being cut.
    mtd fitFieldLabelColumn()
    {
        let metrics = .themeMetrics()
        var width   = metrics.inspector_LabelWidth
        for item in .grid.items where item!.line.isVisible()
        {
            let label = fieldLabel(item)
            if label do
                width = Math.max(width, Painter.measureString(label.name.text, unwrap label.font().regular).width)
        }

        width = Math.ceil(width)
        let gap    = metrics.inspector_LabelGap
        let height = metrics.control_InspectorHeight
        for item in .grid.items where item!.line.isVisible()
        {
            fieldLabel(item)?.setTextAlignment(.Left, .Center)

            // Every row is the height of a control of the inspector, so the rows keep its pitch.
            for c in item.line.children where c.position.height > height do
                c.resize(c.position.width, height)
            if item.sliderBox != null
            {
                // The value of a slider is a measure read beside its track: mono, with no box
                // around it; it still takes a typed value.
                let ctrl = item.sliderBox
                ctrl.setLayoutMetrics(width, SliderValueWidth, gap)
                ctrl.edit.setForm(.Transparent)
                ctrl.edit.updateFlags(.ReleaseFocusOnEnterOrEscape)
                ctrl.edit.style.setFont(.theme().res.fontDefaultFs)
            }
            elif fieldComboCtrl(item)
            {
                let ctrl = unwrap fieldComboCtrl(item)
                ctrl.setLayoutMetrics(width, ctrl.comboWidth, gap)
            }
            elif item.editBox != null
            {
                if item.editBox.parent is EditCtrl as ctrl do
                    ctrl.setLayoutMetrics(width, ctrl.editWidth, gap)
            }
        }
    }

    // Returns the labelled combo of a field: the one the grid knows, or the one an editor of
    // Swag Capture built on the line of the row.
    func fieldComboCtrl(item: *PropertiesItem)->*ComboCtrl?
    {
        if item.comboBox != null
        {
            if item.comboBox.parent is ComboCtrl as ctrl do
                return ctrl
            return null
        }

        for child in item.line.children
        {
            if child is ComboCtrl do
                return assume cast(*ComboCtrl, child)
        }

        return null
    }

    // Returns the label a generated field writes before its editor, or null for a field that
    // names itself another way.
    func fieldLabel(item: *PropertiesItem)->*Label?
    {
        if item.sliderBox != null do
            return item.sliderBox.label
        if fieldComboCtrl(item)
        {
            return fieldComboCtrl(item)!.label
        }
        elif item.editBox != null
        {
            if item.editBox.parent is EditCtrl as ctrl do
                return ctrl.label
        }

        return null
    }

    // Rebuilds the panel for the current selection, or for the model of the active tool: the
    // colours and the glyph choices on top, in the rows of the inspector, then one row per
    // editable field.
    mtd selectionHasChanged()
    {
        for it in .topLayout.children do
            it.destroy()
        .grid.clear()

        // What several objects share comes first, then how to align, arrange and pick them. A
        // mask ends its head with what it does, so the strength or the placement of that kind,
        // the first generated rows, read directly under the list.
        .addColorRows()
        .addMaskKindRows()
        .addArrangeRows()
        .addStyleRows()
        .propPixSel()

        .bindGrid()

        // The sections read in the order of the pictures, whichever structure files them.
        .grid.orderCategories(["Text", "Shape", "Stroke", "Ends", "Effects"])
        .styleCategoryLabels()
        .propTime()
        .propXY()
        .fitFieldLabelColumn()

        .topLayout.computeLayout()
        .grid.layoutHeader()
        .applyLayout()
    }

    // Builds the property panel: the row of style cells above the grid of fields.
    func create(parent: *Wnd, main: *MainWnd)->*PropWnd
    {
        with let prop = Wnd.create'PropWnd(parent, {0, 0, 0, 300})
        {
            .backgroundStyle = .Transparent
            let gutter = .themeMetrics().scrollBar_HitSize + .themeMetrics().scrollBar_EdgeInset

            .topLayout              = StackLayoutCtrl.create(prop)
            .topLayout.mode         = .Top
            .topLayout.fitToContent = true

            // The head rows stand in the column of the inspector, which already keeps its
            // margins; only the air before the generated rows is the panel's own.
            .topLayout.spacing = prop.themeMetrics().inspector_RowPitch - prop.themeMetrics().control_InspectorHeight
            .topLayout.padding = {0, 0, 0, 0}

            .grid = Properties.create(prop, kind: .Panel)
            .grid.dockStyle = .Center

            // The settings stand at the pitch of the inspector, denser than a panel's.
            let metrics = prop.themeMetrics()
            .grid.setRowMetrics(metrics.control_InspectorHeight, metrics.inspector_RowPitch - metrics.control_InspectorHeight)
            .grid.setRowInsets(cast(s32, GridRowInset), 0)
            .grid.setSectionRules(false)
            .grid.setRowGrounds(false)

            // The grid grows into the inspector's trailing room. It lends that same
            // room to its scroll child, so the editor width and leading edge stay fixed.
            .grid.padding.z = gutter
            .grid.margin    = {-GridRowInset, 0, 0, 0}
            .grid.setRevertButtonsVisible(false)

            // Most specific first: a form edits its own fields (text, caps, round...)
            // before the BaseForm style shared by every form
            .grid.setUsingFieldsLast(true)

            // The edges the panel marks follow the scroll (see `scrollEdges`), over the grid.
            prop.wndFlags.add(.AfterChildrenPaint)
            .grid.scrollWnd.sigScrollPositionChanged += func|prop|(_, _, _) { prop.invalidate() }
            .grid.scrollWnd.sigScrollSizeChanged     += func|prop|(_, _, _) { prop.invalidate() }

            .main = main
            .grid.setNotify(prop)

            // The head rows scroll with the generated ones: one column of settings, read from
            // the top down. The grid reaches past the column; the head keeps to it.
            .grid.setHeader(prop.topLayout)
            .topLayout.margin = {GridRowInset, 0, GridRowInset, 0}
        }

        // The panel defers a rebuild to the next frame (see `needRebuild`), so it has to ask for
        // the per-frame event: the one a surface view is sent before the loop starts is a startup
        // hook, and this panel is not a surface view. Asking is what makes the deferral run at
        // all — the registration used to be internal and unreachable, so it never did.
        prop.app().registerFrameEvent(prop)
        return prop
    }

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

        button.sigPopupClosed += func|prop = me|(_)
        {
            prop.colorPicking = false
        }

        button.sigPopupRequested += func|prop = me, slot, label|(button)
        {
            let popover = ColorPopover.open(assume cast(*IconButton, button), label, prop.slotColor(slot), &prop.main.recentColors)
            prop.colorPicking = true
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
            drawShapeGlyph(painter, FormShapeKindValues[value], pos, color, ChoiceGlyphSize)

        case .Dash:
            var rect = pos
            rect.inflate(-ChoiceGlyphInset, 0)
            let pen = Pen.createDash(DashStyleValues[value], color, DashStroke)
            painter.drawLine(rect.x, rect.vertCenter(), rect.right(), rect.vertCenter(), pen)

        case .StartCap, .EndCap:
            drawCapGlyph(painter, LineCapStyleValues[value], row == .StartCap, pos, color)
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
            let width       = row == .StartCap or row == .EndCap ? size : ChoiceWideCellWidth
            with let button = IconButton.create(stack, {}, {0, 0, width, size}, flags: .Radio)
            {
                .userData = enumToUserData(value)
                .toolTip  = tip
                .setForm(.RoundedRectangle)
                .setCheckIndicator(.Full)
                .setChecked(value == current)
            }

            // The glyph takes the whole cell: a button without an icon hands its painter no room.
            button.iconPainter = func|row|(btn, bc, _, flags)
            {
                let colors = btn.themeColors()
                let color  = flags & .Checked ? colors.btnIcon_CheckedIcon : colors.btnIcon_Icon
                paintChoice(bc.painter, row, cast(u32, cast(u64, btn.userData)), btn.clientRect(), color)
            }

            button.sigPressed += func|prop = me, row, stack|(btn)
            {
                let value = cast(u32, cast(u64, btn.userData))
                prop.applyChoice(row, value)
                for other in stack.children
                {
                    let glyph = assume cast(*IconButton, other)
                    glyph.setChecked(cast(u32, cast(u64, glyph.userData)) == value)
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

        // A highlighter stroke is its colour alone; a highlighted area is its fill alone.
        let highlight = form.subKind == .Highlight
        let hasBorder = not pixSel and (not highlight or isStroke)
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
            if not highlight do
                .addColorRow(appStrings().ui_PropOutline, .StrokeOutline)
            return
        }

        // A pixel selection has no fill of its own: its colour is the one its Fill command lays.
        if hasFill do
            .addColorRow(pixSel ? appStrings().ui_PropColor : appStrings().ui_PropFill, .Fill)
        if formType == FormCallout do
            .addColorRow(appStrings().act_Text, .CalloutText)
        if hasBorder do
            .addColorRow(formType == FormStep ? appStrings().act_Text : appStrings().ui_PropOutline, .Border)
    }

    // Reports whether every selected form, or the model of the tool, draws a dashed outline: a
    // plain shape, a line, an arrow or a polygon.
    mtd allSelectedDash()->bool
    {
        func dashes(form: *BaseForm, type: typeinfo)->bool
        {
            if form.subKind != .None do
                return false
            return type == FormShape or type == FormLine or type == FormArrow or type == FormPolygon
        }

        let capture = .main.getCapture()
        if not capture or not capture.selection.count do
            return dashes(.getSelectedBaseForm(), .getSelectedFormType())

        foreachSelected'BaseForm(capture, capture.selection)
        {
            if not dashes(form, Swag.kindOf(itf)) do
                return false
        }

        return true
    }

    // Appends the glyph choices of the selection: the kind of a shape or a step, the dash of an
    // outline, the two ends of a line. Several objects are offered only what they all have.
    mtd addStyleRows()
    {
        let form     = .getSelectedBaseForm()
        let formType = .commonFormType()
        let pixSel   = form.subKind == .PixSel
        let isLine   = formType == FormLine or formType == FormArrow
        let hasShape = (formType == FormShape and not pixSel) or formType == FormStep
        let hasDash  = .allSelectedDash()
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
                .setCheckIndicator(.Full)
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
            let mode = MainWnd.formToolMode(form)

            // A layer is named by its words when it has some, by its kind otherwise: a shape is a
            // rectangle or an ellipse, as the title of the inspector counts it.
            var name: String = mode.name()
            if form is FormShape as shape where mode == .Shape do
                name = shape.kind == .Ellipse ? texts.kind_Ellipse : texts.kind_Rectangle
            let words = formEditableText(form)
            if words and not words.isEmpty() do
                name = words[]
            with let button = IconButton.create(.addHeadRow(""), .main.icon(mode.glyph(), metrics.menuPopup_IconSize), {}, flags: .Radio)
            {
                .dockStyle = .Center
                .userData  = cast(*void, cast(u64, i))
                .setText(name)
                .setTextPosition(.Right)
                .setForm(.RoundedRectangle)
                .setCheckIndicator(.Full)
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

    // The commands of a pixel selection, in words, two to a row as the arrangement of several
    // objects stands: what fills the pixels, then what clears or moves them.
    mtd propPixSel()
    {
        if .getSelectedBaseForm().subKind != .PixSel do
            return

        .addHeadSection(appStrings().ui_MenuEdit)
        let size = .themeMetrics().control_InspectorHeight
        const Commands = [ActionPixSel.Fill, ActionPixSel.SmartFill, ActionPixSel.Clear, ActionPixSel.SmartMove]
        for pair in 2
        {
            with let row = StackLayoutCtrl.create(.addHeadRow(""), .HorizontalFit, {})
            {
                .dockStyle = .Center
                .spacing   = ChoiceGap
            }

            for k in 2
            {
                let button = PushButton.create(row, "", {0, 0, 0, size}, id: Commands[pair * 2 + k], form: .Flat)
                button.setIconSize(.themeMetrics().menuPopup_IconSize, .themeMetrics().menuPopup_IconSize)
            }
        }
    }

    // Seconds of the selected form's span, with an action that restores the whole recording.
    mtd propTime()
    {
        let capture = .main.getCapture()
        if not capture or not capture.isTimed() or capture.selection.count != 1 do
            return

        let form: *BaseForm = capture.forms[capture.selection[0]]
        let duration = cast(f64, capture.timeline.duration) / 1_000_000
        let section = .grid.addItem(Swag.TypeValue{name: "time.section"}, null, null,
                                    .themeMetrics().inspector_SectionHeight, .None)
        section.flags.add(.NoSeparator | .NoFocus)
        SectionLabel.create(section.line, appStrings().ui_PropTime,
                            {0, 0, 0, .themeMetrics().inspector_SectionHeight}).dockStyle = .Center

        func addTime(prop: *PropWnd, label: string, time: u64, start: bool, duration: f64)
        {
            let item = prop.grid.addItem(Swag.TypeValue{name: start ? "time.start" : "time.end"},
                                         null, null, prop.themeMetrics().control_InspectorHeight, .None)
            item.flags.add(.NoSeparator)
            let seconds = cast(f64, time) / 1_000_000
            let edit = EditCtrl.create(item.line, label, Format.toString("%", seconds),
                                       flags: .ReleaseFocusOnEnterOrEscape)
            edit.dockStyle = .Center
            edit.setLayoutMetrics(prop.themeMetrics().inspector_LabelWidth, 0,
                                  prop.themeMetrics().inspector_LabelGap)
            edit.edit.setFloatingPointRange(0, duration)
            edit.edit.style.setFont(prop.theme().res.fontDefaultFs)
            edit.edit.sigCommitted += func|prop, start|(ed)
            {
                if ed.revalidate() != .Valid do
                    return
                let {value, eat: _, ovf: _} = catch StrConv.parseF64(ed.text())
                let capture = prop.main.getCapture()
                if not capture or not capture.isTimed() or capture.selection.count != 1 do
                    return
                let microseconds = cast(u64, Math.round(value * 1_000_000))
                capture.setSelectionSpanAt(start, time: microseconds)
                prop.main.timeline?.invalidate()
                prop.needRebuild = true
            }
        }

        addTime(me, appStrings().ui_TimeStart, form.timeStart, true, duration)
        addTime(me, appStrings().ui_TimeEnd, form.timeEnd ? form.timeEnd : capture.timeline.duration,
                false, duration)

        let item = .grid.addItem(Swag.TypeValue{name: "time.whole"}, null, null,
                                 .themeMetrics().control_InspectorHeight, .None)
        item.flags.add(.NoSeparator)
        let button = PushButton.create(item.line, appStrings().act_ShowAlways,
                                       {0, 0, 180, .themeMetrics().control_InspectorHeight}, form: .Flat)
        button.dockStyle = .CenterKeepSizeVert
        button.sigPressed += func|prop = me|(_)
        {
            prop.main.getCapture()?.clearSelectionSpan()
            prop.main.timeline?.invalidate()
            prop.needRebuild = true
        }
        .grid.endAppendRows()
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
                if ed.revalidate() != .Valid do
                    return
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

// Host hooks of the property grid: dynamic visibility of the generated rows (rules the
// attributes cannot express: selection kind, PixSel/Highlight sub-kinds, dependent
// fields) and the reaction to every edit.
impl IPropertyNotify for PropWnd
{
    mtd impl isItemVisible(_: *Properties, item: *PropertiesItem)->bool
    {
        let base = .getSelectedBaseForm()

        // Category separators hide by themselves: the grid force-shows an item's parents,
        // so a separator appears exactly when its group has at least one visible row.
        if item.flags.has(.Category) do
            return false

        let name = item.typeValue.name

        switch name
        {
        case #nameof(BaseForm.borderSize):
            return .gridBindType != FormStep and base.subKind != .PixSel

        case #nameof(FormLine.outlineSize):
            return (.gridBindType == FormLine or .gridBindType == FormArrow or .gridBindType == FormDraw) and
                   base.subKind == .None

        case #nameof(BaseForm.joinStyle):
            return (.gridBindType == FormText or .gridBindType == FormPolygon) and
                   base.subKind != .PixSel

        // The words are typed in place, and how the lines stand in the box is set from the
        // mini-bar beside the selection.
        case #nameof(FormText.text), #nameof(FormText.alignHorz), #nameof(FormText.alignVert):
            return false

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

        case #nameof(FormLine.startSize), #nameof(FormLine.endSize):
            if .gridBindType == FormLine or .gridBindType == FormArrow
            {
                let line = assume cast(*FormLine, base)
                let cap  = name == #nameof(FormLine.startSize) ? line.beginCap : line.endCap
                return base.subKind != .PixSel and capStyleHasSize(cap)
            }

            return false

        case #nameof(FormShape.roundSize):
            if .gridBindType == FormShape
            {
                let shape = assume cast(*FormShape, base)
                return shape.kind == .RoundRectangle
            }

        // The kinds of a mask are the list of the head, with their glyphs.
        case #nameof(FormImage.kind):
            return false

        case #nameof(FormImage.strength):
            if .gridBindType == FormImage
            {
                let image = assume cast(*FormImage, base)
                return image.kind == .Blur or image.kind == .Pixelate or image.kind == .Zoom
            }

        case #nameof(FormImage.place):
            if .gridBindType == FormImage
            {
                let image = assume cast(*FormImage, base)
                return image.kind == .Image
            }
        }

        return true
    }

    mtd impl isEnumValueVisible(_: *Properties, item: *PropertiesItem, enumValue: Swag.TypeValue)->bool
    {
        // The join combo omits JoinStyle.None: no join drawn = notched corners on any
        // thick stroke, never what a Swag Capture form wants.
        if item.typeValue.name == #nameof(BaseForm.joinStyle) do
            return enumValue.name != #nameof(JoinStyle.None)

        return true
    }

    mtd impl itemHasChanged(_: *Properties, item: *PropertiesItem?)
    {
        let capture = .main.getCapture()
        if capture and (capture.selection.count or item == null)
        {
            // Grid edits bypass the capture's typed undo commands. Replaying a grid
            // command can also touch a form that is no longer selected.
            if item
            {
                for index in capture.selection do
                    capture.invalidateFormCache(capture.forms[index])
            }
            else
            {
                capture.invalidateAllFormCaches()
            }

            if capture.selection.count do
                capture.updateModelFromSelection()
            capture.hasChanged()
        }

        if .main.miniBar != null do
            .main.miniBar.refreshTextControls()
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

        // A hairline marks where the settings pass under the presets, and where more of them
        // wait below: the cut stays an edge, not a row sliced through its words.
        let edges = .scrollEdges()
        if not edges.above and not edges.below do
            return
        let painter = evt.paintContext.painter
        let color   = .themeColors().line
        let width   = .clientRect().width
        if edges.above do
            painter.fillRect(Math.Rectangle{GridRowInset, 0, width - 2 * GridRowInset, 1}, color)
        if edges.below do
            painter.fillRect(Math.Rectangle{GridRowInset, .clientRect().height - 1, width - 2 * GridRowInset, 1}, color)
    }

    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        .frameWnd.IWnd.onResizeEvent(evt)
    }

    mtd impl onFrameEvent(_: *FrameEvent)
    {
        if .needRebuild and not .colorPicking
        {
            .needRebuild = false
            .selectionHasChanged()
            if .main.miniBar != null do
                .main.miniBar.refreshTextControls()
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
