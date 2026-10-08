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

const CapPreviewSize = 10.0
const DashSize       = 6.0

// Geometry of the popups the style cells open. A popup is sized from what it lists, so a
// style added to an enum widens or lengthens its own list instead of falling outside it.
const PopupRowHeight    = 36.0      // One row of the dash list.
const PopupCapRowHeight = 44.0      // One row of the line-end list; its samples need the room.
const PopupCapWidth     = 120.0     // Width of the line-end list.
const PopupDashWidth    = 180.0     // Width of the dash list; its samples run along it.
const PopupCellSize     = 48.0      // One square cell of the shape list.
const PopupPadding      = 6.0       // Air the list keeps inside its frame.
const PopupSpacing      = 5.0       // Gap a stack and a wrap layout leave between two items by default.
const PopupFrameInset   = 5.0       // Room the frame itself takes around its view (frameWnd_SquarePadding).

// Room `count` items of `size` need along one axis, the air around them included.
//
// Every popup here is sized through this: written by hand, a dimension stopped matching its
// list the day a style was added to an enum, and the last entry fell outside the frame.
func popupExtent(count, size: f32)->f32 => count * size + Math.max(count - 1, 0) * PopupSpacing + 2 * PopupPadding + 2 * PopupFrameInset

// The enum popup buttons stash the value they represent in the untyped 'userData'
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

// Paints a line-end sample while keeping the cap itself inside `pos`. The same painter feeds the
// closed style cell and its list row, so both always show the value the line actually stores.
func drawCapGlyph(painter: *Painter, cap: LineCapStyle, begin: bool, pos: Math.Rectangle, color: Color, size: f32 = CapPreviewSize)
{
    var rect = pos
    rect.inflate(-5, -5)
    var pen = Pen.createSolid(color, size)
    if begin
    {
        pen.begCapStyle = cap
        pen.endCapStyle = .None
        let {?, l0} = Painter.capStyleExtent(cap, size, pen.capBegScaleX)
        rect.moveLeft(l0)
    }
    else
    {
        pen.begCapStyle = .None
        pen.endCapStyle = cap
        let {?, l0} = Painter.capStyleExtent(cap, size, pen.capEndScaleX)
        rect.moveRight(-l0)
    }

    painter.drawLine(rect.x, rect.vertCenter(), rect.right(), rect.vertCenter(), pen)
}

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

    // The chooser a style cell opens when what it lists are samples of a stroke. It is a
    // temporary list attached to the panel's top view, and it does not become a button grid just
    // because its entries are drawn rather than written.
    stylePopup: *PopupListCtrl?
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
            return assume cast(*BaseForm, iform)
        }

        return capture.getSelectedBaseForm()!
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

        return capture.getSelectedFormType()!
    }

    mtd pushTypedValue(val: u32, type: typeinfo, name: string, first: bool, common = false)
    {
        let capture = .main.getCapture()

        // Change model
        if not capture or not capture.selection.count
        {
            let form   = .getSelectedBaseForm()
            let field  = Reflection.findField(type, name)!
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
                .valRef = Reflection.findField(type, name)!
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
            // Common concrete type of the selection: exact when homogeneous, FormLine for
            // a line/arrow mix (an arrow embeds a line), BaseForm otherwise
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
                bases.add(cast(*u8?, form))
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

        .grid.addStructMulti(.gridBindType, cast([..] *u8, bases.toSlice()), null, onlyNamed: true)

        // The generated border-size slider serves every form as "Thickness"; a text form
        // edits its glyph outline instead: matching label and a much thinner range. The
        // slider keeps a normalized position, so re-set the value after the new range.
        if .gridBindType == FormText
        {
            for item in .grid.items
            {
                let it = item!
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
    mtd styleCategoryLabels()
    {
        for item in .grid.items
        {
            let it = item!
            if not it.flags.has(.Category) do
                continue
            it.label.style.setFont(.theme().res.fontDefault)
            it.label.updateFlags(.SecondaryText)
        }
    }

    // Gives every generated field the width of the widest visible label in the current
    // language. The controls otherwise reserve a fixed 60 pixels: enough for "Round", but
    // not for "Thickness", while a larger constant would waste the same room in shorter
    // translations. One measured column keeps sliders, combos and edits aligned.
    mtd fitFieldLabelColumn()
    {
        var width = 0'f32
        for item in .grid.items where item!.line.isVisible()
        {
            let it = item
            var label: *Label?
            if it.sliderBox != null
            {
                label = it.sliderBox.label
            }
            elif it.comboBox != null
            {
                if it.comboBox.parent is ComboCtrl as ctrl do
                    label = ctrl.label
            }
            elif it.editBox != null
            {
                if it.editBox.parent is EditCtrl as ctrl do
                    label = ctrl.label
            }

            if label do
                width = Math.max(width, Painter.measureString(label.name.raw, label.font().regular!).width)
        }

        width = Math.ceil(width)
        for item in .grid.items where item!.line.isVisible()
        {
            let it = item
            if it.sliderBox != null
            {
                let ctrl = it.sliderBox
                ctrl.setLayoutMetrics(width, ctrl.valueWidth, ctrl.spacing)
            }
            elif it.comboBox != null
            {
                if it.comboBox.parent is ComboCtrl as ctrl do
                    ctrl.setLayoutMetrics(width, ctrl.comboWidth, ctrl.spacing)
            }
            elif it.editBox != null
            {
                if it.editBox.parent is EditCtrl as ctrl do
                    ctrl.setLayoutMetrics(width, ctrl.editWidth, ctrl.spacing)
            }
        }
    }

    mtd selectionHasChanged()
    {
        .stylePopup?.cancel()

        for it in .topLayout.children do
            it.destroy()
        .grid.clear()

        // The cells start at the panel margin like every row under them, instead of floating
        // in the middle of the column: a group centred on its own is a third alignment on a
        // surface that already has one.
        let stack0 = StackLayoutCtrl.create(.topLayout, .HorizontalCenter, {0, 0, 0, StyleCellSize})
        stack0.spacing = StyleCellGap
        .propBackColor(stack0)
        .propBorderColor(stack0)
        .propStrokeOutlineColor(stack0)
        .propCalloutText(stack0)
        .propShape(stack0)
        .propStep(stack0)
        if stack0.children.isEmpty() do
            stack0.destroyNow()

        let stack1 = StackLayoutCtrl.create(.topLayout, .HorizontalCenter, {0, 0, 0, StyleCellSize})
        stack1.spacing = StyleCellGap
        .propStartCapStyle(stack1)
        .propDashStyle(stack1)
        .propEndCapStyle(stack1)
        if stack1.children.isEmpty() do
            stack1.destroyNow()

        .propNextStep()
        .propPixSel()

        .bindGrid()
        .styleCategoryLabels()
        .propXY()
        .fitFieldLabelColumn()

        .topLayout.computeLayout()
        .applyLayout()

        let capture = .main.getCapture()
        capture?.editView?.setFocus()
    }

    func create(parent: *Wnd, main: *MainWnd)->*PropWnd
    {
        with let prop = Wnd.create'PropWnd(parent, {0, 0, 0, 300})
        {
            .backgroundStyle = .Transparent

            .topLayout              = StackLayoutCtrl.create(prop)
            .topLayout.mode         = .Top
            .topLayout.fitToContent = true
            .topLayout.dockStyle    = .Top
            .topLayout.spacing      = StyleCellGap

            // The head keeps the margin of the panel on both edges, and a block of air
            // between itself and the rows the grid generates under it.
            .topLayout.padding = {12, 16, 12, 16}

            .grid = Properties.create(prop, kind: .Panel)
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
    mtd impl isItemVisible(?: *Properties, item: *PropertiesItem)->bool
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
                   base.subKind != .PixSel

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

        case #nameof(FormImage.strength):
            if .gridBindType == FormImage
            {
                let image = assume cast(*FormImage, base)
                return image.kind != .Image
            }
        }

        return true
    }

    mtd impl isEnumValueVisible(?: *Properties, item: *PropertiesItem, enumValue: Swag.TypeValue)->bool
    {
        // The join combo omits JoinStyle.None: no join drawn = notched corners on any
        // thick stroke, never what a Swag Capture form wants.
        if item.typeValue.name == #nameof(BaseForm.joinStyle) do
            return enumValue.name != #nameof(JoinStyle.None)

        return true
    }

    mtd impl itemHasChanged(?: *Properties, item: *PropertiesItem?)
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

    mtd impl onFrameEvent(?: *FrameEvent)
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
