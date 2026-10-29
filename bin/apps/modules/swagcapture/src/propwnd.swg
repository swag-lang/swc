// Geometry of the sample a line-end glyph draws.
const CapPlainStroke  = 6.0     // Stroke a plain end is drawn on: heavy enough to show its shape.
const CapAnchorStroke = 2.0     // Stroke an anchor is drawn on.
const CapAnchorScale  = 4.0     // Scale of an anchor across its stroke, so it reads at glyph size.
const CapGlyphInset   = 5.0     // Air between the sample and the sides of its cell.

// Air the panel layout of the property grid keeps before each of its rows: the label column of a
// generated field is that much narrower than the inspector's, so both columns end on one edge.
const GridRowInset = 8.0

// Width of the value read beside a slider of the inspector: "100 %" in the fixed-width family.
// Wider, the track shortens and the value stands apart from it.
const SliderValueWidth = 44.0

// The enum popup buttons stash the value they represent in the untyped `userData`
// slot of the widget; these two helpers keep the double cast in one place.
func(T) enumToUserData(value: T)->*void   => cast(*void, cast(u64, value))
func(T) enumFromUserData(data: *void?)->T => cast(T, cast(u64, data))

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
        painter.drawLine(stop, y - tick, stop, y + tick, Pen.createSolid(color, 1))
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
}

impl PropWnd
{
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
                width = Math.max(width, Painter.measureString(label.name.raw, unwrap label.font().regular).width)
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
        .propXY()
        .fitFieldLabelColumn()

        .topLayout.computeLayout()
        .grid.layoutHeader()
        .applyLayout()

        let capture = .main.getCapture()
        capture?.editView?.setFocus()
    }

    // Builds the property panel: the row of style cells above the grid of fields.
    func create(parent: *Wnd, main: *MainWnd)->*PropWnd
    {
        with let prop = Wnd.create'PropWnd(parent, {0, 0, 0, 300})
        {
            .backgroundStyle = .Transparent

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
            .grid.setSectionRules(false)
            .grid.setRowGrounds(false)

            // The panel layout keeps its own margin before each row; the grid reaches past the
            // column by that much so its labels stand on the edge of the inspector's labels.
            .grid.margin = {-GridRowInset, 0, -GridRowInset, 0}
            .grid.setRevertButtonsVisible(false)

            // Most specific first: a form edits its own fields (text, caps, round...)
            // before the BaseForm style shared by every form
            .grid.setUsingFieldsLast(true)

            // Always show a small vertical bar so the row width does not jump with the content
            .grid.scrollWnd.updateFlags(.AlwaysShowVertical)

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

    mtd impl onFrameEvent(_: *FrameEvent)
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
