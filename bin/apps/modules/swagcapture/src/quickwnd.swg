// A preset is a small picture of the shape it draws, in its own colours, painted by the painter
// of the canvas: a cell of the raised ground, the preset in force ringed in Arc.
//
// Five presets and the chip after them fill the width of the inspector, so the cell keeps the
// proportions of the pictures' 44 by 36 at a smaller size.
const QuickCellWidth  = 38.0     // Width of the cell of a preset.
const QuickCellHeight = 31.0     // Height of the cell of a preset.
const QuickCellCorner = 6.0      // Corner of the cell.
const QuickRingGap    = 1.5      // Air between the cell and the ring of the preset in force.
const QuickRingWidth  = 1.5      // Weight of that ring.
const QuickCellMargin = 5.0      // Least air between a sample and the edge of its cell.

// A chip holds its cell and the room of the ring around it, so two cells stand twice that room
// apart, and the ring is never cut by the chip.
const QuickChipInset  = QuickRingGap + QuickRingWidth
const QuickChipWidth  = QuickCellWidth + 2 * QuickChipInset
const QuickChipHeight = QuickCellHeight + 2 * QuickChipInset

// The size the sample of a preset is painted at, as a frame its shape is laid out in, before the
// room its stroke and its ends take is kept around it.
const QuickSampleWidth    = 24.0
const QuickSampleHeight   = 15.0
const QuickStrokeZoom     = 0.28'f32     // The scale a line or an arrow is painted at in its cell.
const QuickTextHeight     = 14.0'f32     // The size the "Aa" of a text is painted at in its cell.
const QuickMaskWidth      = 21.0         // Width of the pattern of a mask preset.
const QuickMaskHeight     = 14.0         // Height of the pattern of a mask preset.
const QuickLightDepth     = 0.09'f32     // How much deeper the cell of a light preset is, on a light ground.
const QuickPopoverPad     = 12.0         // Air inside the popover holding every preset of a tool.
const QuickPopoverColumns = 5            // Presets in a row of that popover.
const QuickCaptionHeight  = 20.0         // Height of the line naming the preset in force, under the row.

// The glyph of the trailing chip, which keeps the selected shape as a new preset.
const AddGlyphSize = 14.0

// Clears the ground the theme gives a button, in every state, on a chip that paints its own cell.
func clearChipGround(button: *IconButton)
{
    for key in ["btnIcon_Bk", "btnIcon_HotBk", "btnIcon_PressedBk", "btnIcon_CheckedBk", "btnIcon_CheckedHotBk", "btnIcon_CheckedPressedBk",
                "btnIcon_CheckedMark", "btnIcon_CheckedHotMark", "btnIcon_CheckedPressedMark", "btnIcon_CheckedRing"] do
        button.style.addStyleSheetColors(Format.toString("% 0x00000000", key))
}

// The preset forms one tool offers in the quick-style bar, and the name the reader gave each.
struct QuickStyle
{
    forms: Array'IForm
    names: Array'String     // Name of each preset, by index; empty for a preset not named yet.
    uses:  Array'u32        // How many times each preset was applied, by index; the row is ordered by it.
}

impl QuickStyle
{
    mtd opDrop()
    {
        .clear()
    }

    func isKnownForm(itf: IForm)->bool
    {
        let type = Swag.kindOf(itf)
        return type == FormArrow or
               type == FormDraw or
               type == FormImage or
               type == FormLine or
               type == FormPolygon or
               type == FormShape or
               type == FormStep or
               type == FormText or
               type == FormCallout
    }

    func deleteOne(itf: IForm)
    {
        Memory.delete(itf.buffer, Swag.kindOf(itf))
    }

    mtd sanitize()
    {
        var idx = 0'u64
        while idx < .forms.count
        {
            if isKnownForm(.forms[idx])
            {
                idx += 1
                continue
            }

            // Stale serialized interface values can point to an unresolved type.
            .forms.removeAtOrdered(idx)
            if idx < .names.count do
                .names.removeAtOrdered(idx)
        }

        .names.resize(.forms.count)
        .uses.resize(.forms.count)
    }

    // Adopts a freshly built form as the last preset of the set.
    mtd add(form: IForm)
    {
        form.setup(null)
        .forms.add(form)
        .names.resize(.forms.count)
        .uses.resize(.forms.count)
    }

    // Removes the preset `itf`, keeping the order of the others.
    mtd remove(itf: IForm)
    {
        let index = .indexOf(itf)
        if index >= .forms.count do
            return
        .forms.removeAtOrdered(index)
        if index < .names.count do
            .names.removeAtOrdered(index)
        if index < .uses.count do
            .uses.removeAtOrdered(index)
        deleteOne(itf)
    }

    mtd clear()
    {
        for i in .forms do
            deleteOne(i)
        .forms.clear()
        .names.clear()
        .uses.clear()
    }

    // Returns the index of the preset `itf`, or the count of presets when it is not one of them.
    mtd indexOf(itf: IForm)->u64
    {
        for f, i in .forms where f.buffer == itf.buffer do
            return i
        return .forms.count
    }

    // Returns the name of preset `index`: the one the reader gave it, or "Style" and its rank.
    mtd nameOf(index: u64)->String
    {
        if index < .names.count and not .names[index].isEmpty() do
            return .names[index]
        if index < .forms.count
        {
            // A mask says what it does, which is the best name it has until it is given one.
            let kind = quickStyleTip(.forms[index])
            if kind.count do
                return kind
        }

        return Format.toString(appStrings().ui_QuickStyleRank, index + 1)
    }

    // Names preset `index`.
    mtd setName(index: u64, name: string)
    {
        .names.resize(.forms.count)
        if index < .names.count do
            .names[index] = name
    }

    // Counts one more use of preset `index`, and moves it before the presets used less, so the
    // row shows the ones used most. Returns where the preset now stands.
    mtd countUse(index: u64)->u64
    {
        if index >= .forms.count do
            return index
        .names.resize(.forms.count)
        .uses.resize(.forms.count)
        .uses[index] += 1

        var at = index
        while at > 0 and .uses[at - 1] < .uses[at]
        {
            .swap(at - 1, at)
            at -= 1
        }

        return at
    }

    // Swaps presets `a` and `b`, with their names and their uses.
    mtd swap(a, b: u64)
    {
        let form = .forms[a]
        .forms[a] = .forms[b]
        .forms[b] = form
        let name: String = .names[a]
        .names[a] = .names[b]
        .names[b] = name
        let use = .uses[a]
        .uses[a] = .uses[b]
        .uses[b] = use
    }
}

// The popover holding every preset of a tool, which the keys go through: the arrows choose a
// cell, Enter applies it, Escape closes the popover.
struct PresetPopover
{
    using wnd:  Wnd
    late quick: *QuickWnd
    chosen:     u64     // The cell the keys stand on.
}

impl IWnd for PresetPopover
{
    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        evt.accepted = false
        if evt.kind != .Pressed do
            return

        let count = .children.count
        let cols  = cast(u64, QuickPopoverColumns)
        switch evt.key
        {
        case .Left:
            if .chosen > 0 do
                .choose(.chosen - 1)

        case .Right:
            if .chosen + 1 < count do
                .choose(.chosen + 1)

        case .Up:
            if .chosen >= cols do
                .choose(.chosen - cols)

        case .Down:
            if .chosen + cols < count do
                .choose(.chosen + cols)

        case .Return, .Space:
            .press()

        case .Escape:
            let quick = .quick
            let more  = quick.moreButton
            if more
            {
                more.hidePopup()
                quick.layout.setFocus()
                for cell, i in quick.rowCells() where cell == more do
                    quick.chooseRowCell(i)
            }

        default:
            return
        }

        evt.accepted = true
    }
}

impl PresetPopover
{
    // Moves the keys to cell `index`, which is ringed.
    mtd choose(index: u64)
    {
        if index >= .children.count do
            return
        .chosen = index
        for c, i in .children
        {
            let cell = assume cast(*QuickButton, c)
            cell.keyChosen = i == index
            cell.invalidate()
        }
    }

    // Applies the preset the keys stand on, or keeps the current style as a new one.
    mtd press()
    {
        if .chosen >= .children.count do
            return
        let cell  = assume cast(*QuickButton, .children[.chosen])
        let quick = .quick
        if cell.isModel do
            quick.addCurrentStyle()
        else do
            quick.applyPreset(unwrap cell.formItf, fromPopover: true)
    }
}

// One cell of the quick-style bar, painting the preset form it applies.
struct QuickButton
{
    using iconBtn: IconButton
    formItf:       IForm?
    late quickWnd: *QuickWnd

    // The trailing chip, which keeps the current tool style as a new preset.
    isModel: bool

    // The chip opening every preset of the tool, when the row cannot hold them all.
    isMore: bool

    // A cell of that popover: choosing it closes the popover and brings the preset into the row.
    inPopover: bool

    // Whether the keys stand on this cell of the popover.
    keyChosen: bool
}

// The disposable copy of a preset a cell paints. Painting a sample normalizes its geometry,
// text and points, so it never works on the style itself.
struct QuickStylePaintForm
{
    itf:   IForm?
    zoom:  f32  = 1        // The zoom the copy is painted at: a stroke is laid out larger and painted smaller.
    quick: bool = true     // Whether the copy is painted with the sizes the quick mode normalizes.
}

impl QuickStylePaintForm
{
    // Creates the copy of `srcItf` a cell of [[QuickCellWidth]] by [[QuickCellHeight]] paints,
    // laid out in the middle of the cell: a box, a stroke rising across, "Aa", a bubble with its
    // tail, a numbered disc, the pattern of a mask.
    func create(srcItf: IForm)->QuickStylePaintForm
    {
        let paintBase = MainWnd.newFormFromForm(srcItf)
        let paintItf  = assume cast(IForm, paintBase)

        var cxt: FormPaintContext
        cxt.z         = 1
        cxt.quickMode = true

        // A sample stands on the cell: a drop shadow would read as a glow around it.
        paintItf.paintShadow = false

        var w = QuickSampleWidth
        var h = QuickSampleHeight
        switch paintItf
        {
        case FormStep:  w, h = 14
        case FormImage: w, h = 19
        case FormText:  w, h = QuickCellHeight - 2 * QuickCellMargin
        }

        // A stroke keeps the weight and the ends the canvas gives it, which a cell this small
        // cannot hold: it is laid out larger, then painted at a small scale, like the canvas
        // zoomed out.
        var result: QuickStylePaintForm
        result.itf  = paintItf
        result.zoom = paintItf is FormLine or paintItf is FormArrow or paintItf is FormDraw ? QuickStrokeZoom : 1'f32

        // Words are drawn at their own size and outline, brought down to the cell, and a
        // highlighter at its own transparency; a callout at the small size its sample sets.
        if paintItf is FormText as text
        {
            result.zoom  = QuickTextHeight / Math.max(text.fontSize * Math.map(text.scale, 0, 100, 1'f32, 2'f32), 1)
            result.quick = false
        }

        if paintItf is FormCallout or paintItf.subKind == .Highlight do
            result.quick = false

        let m = sampleInset(paintItf, cxt) * result.zoom
        w = Math.min(w, QuickCellWidth - 2 * (QuickCellMargin + m))
        h = Math.min(h, QuickCellHeight - 2 * (QuickCellMargin + m))
        let rect = Math.Rectangle{Math.round((QuickCellWidth - w) * 0.5), Math.round((QuickCellHeight - h) * 0.5), w, h}

        switch paintItf
        {
        case FormPolygon as poly:

            // A regular pentagon, point up.
            poly.points.clear()
            for i in 5
            {
                let a = Math.ConstF32.TwoPi * cast(f32, i) / 5 - Math.ConstF32.Pi * 0.5
                poly.points.add({24 + 24 * Math.cos(a), 26 + 24 * Math.sin(a)})
            }

        case FormDraw as draw:

            // One straight stroke rising across the cell.
            draw.points.clear()
            draw.points.add({0, 36})
            draw.points.add({48, 12})

        case FormText as txt:
            txt.text      = "Aa"
            txt.alignHorz = .Center
            txt.alignVert = .Center
            txt.rotate    = 0

        case FormStep as step:
            step.index = 1
        }

        if paintItf is FormText
        {
            // "Aa" is wider than it is tall: the box takes the width of the cell.
            let k = 1 / result.zoom
            paintItf.setBaseForm(cast(QuickCellMargin * k), cast(rect.y * k), cast((QuickCellWidth - 2 * QuickCellMargin) * k), cast(rect.height * k))
        }
        elif paintItf is FormDraw
        {
            // A free stroke keeps its own path, laid out larger and painted smaller.
            let k = 1 / result.zoom
            paintItf.setBaseForm(cast(rect.x * k), cast(rect.y * k), cast(rect.width * k), cast(rect.height * k))
        }
        elif result.zoom != 1
        {
            // A stroke rises from the foot of the frame on the left to its top on the right.
            let k = 1 / result.zoom
            paintItf.setBaseForm(cast(rect.x * k), cast(rect.bottom() * k), cast(rect.width * k), cast(-rect.height * k))
        }
        else
        {
            paintItf.setBaseForm(cast(rect.x), cast(rect.y), cast(rect.width), cast(rect.height))
        }

        // The tail of a callout lives in canvas space and is never carried by a style: the sample
        // is a short body with "Aa" in it and its tail hanging below on the left.
        if paintItf is FormCallout as cl
        {
            cl.text       = "Aa"
            cl.fontSize   = 8
            cl.boldSize   = 0
            cl.roundSize  = Math.min(cl.roundSize, 4)
            cl.borderSize = Math.min(cl.borderSize, 1)
            cl.alignHorz  = .Center
            cl.alignVert  = .Center
            cl.x          = cast(s32, Math.round((QuickCellWidth - 24) * 0.5))
            cl.y          = cast(s32, Math.round((QuickCellHeight - 16) * 0.5))
            cl.w          = 24
            cl.h          = 12
            cl.tailX      = cl.x + 5
            cl.tailY      = cl.y + cl.h + 4
        }

        return result
    }

    // Frees the copy. A second call does nothing.
    mtd release()
    {
        if .itf do
            Memory.delete(.itf.buffer, Swag.kindOf(.itf))
        .itf = null
    }

    // Returns the room a sample needs between its own geometry and the edge of its cell.
    //
    // Everything a form paints outside its rectangle lives in there: half a stroke for a box, and
    // the line ends for a line or an arrow, which are as wide as the stroke times their scale and
    // stand across the diagonal the sample runs along. Answered too small, an arrow head is cut
    // flat by the cell and the preset reads as broken rather than as pointed.
    func sampleInset(itf: IForm, cxt: FormPaintContext)->f32
    {
        // An arrow is a line carrying its own defaults, so both answer through the line.
        if itf is FormLine as line
        {
            // The line ends are shaped from the stroke and the contour is pushed out around the
            // result, so the contour adds its own width once instead of widening the stroke the
            // ends are measured against.
            let sizes = line.paintSizes(cxt)
            let beg   = Painter.capStyleExtent(line.beginCap, sizes.stroke, sizes.begScale)
            let end   = Painter.capStyleExtent(line.endCap, sizes.stroke, sizes.endScale)

            // The sample runs corner to corner, so both axes of an end land on both axes of the
            // cell at the cosine of that diagonal: what stands across the line and what reaches
            // past its point add up there, and an end reserving only the larger of the two would
            // lose its far corner to the edge of the cell.
            let room = Math.max(beg.w + beg.l, end.w + end.l) + line.paintOutlineSize(cxt)
            return room * Math.ConstF32.OneBySqrt2
        }

        var inset = BaseForm.adaptSize(itf.borderSize / 2, MinBorderSize, MaxBorderSize, cxt)
        if itf is FormDraw as draw do
            inset += draw.paintOutlineSize(cxt)
        return inset
    }
}

// Returns the name of what a preset cell shows, for its tooltip.
//
// A processed image form is the one family whose samples say what they do rather than how
// they look, so the word is worth having. It belongs on the tooltip and not inside the cell:
// printed there, it would overflow the cell on both axes and cross the sample it names.
func quickStyleTip(itf: IForm)->string
{
    let image = catch cast(*FormImage?, itf)
    if not image do
        return ""
    return quickStyleKindName(image.kind)
}

// Returns the name of the kind of an image form: a picture, or the effect it has on what it covers.
func quickStyleKindName(kind: FormImageKind)->string
{
    switch #complete kind
    {
    case .Image:    return appStrings().prop_KindImage
    case .Blur:     return appStrings().prop_KindBlur
    case .Pixelate: return appStrings().prop_KindPixelate
    case .Zoom:     return appStrings().prop_KindZoom
    case .Capture:  return appStrings().prop_KindCapture
    }
}

// The quick-style bar: the presets of every tool, showing those of the current one.
struct QuickWnd
{
    using scrollWnd: ScrollWnd

    late layout: *Wnd
    late main:   *MainWnd

    qsArrow:     QuickStyle
    qsShape:     QuickStyle
    qsImage:     QuickStyle
    qsStep:      QuickStyle
    qsLine:      QuickStyle
    qsPolygon:   QuickStyle
    qsText:      QuickStyle
    qsFavorites: QuickStyle
    qsDraw:      QuickStyle
    qsHighlight: QuickStyle
    qsPixSel:    QuickStyle
    qsCallout:   QuickStyle

    currentStyle: *QuickStyle?
    moreButton:   *QuickButton?     // The chip opening every preset, in the row of the tool.
    allPresets:   *Wnd?             // The cells of every preset, while the popover "•••" opens is up.
    caption:      *Label?           // The name of the preset in force, under the row.
    keyCell:      u64               // The chip of the row the keys stand on, among those shown; past the end while the row does not hold the keyboard.
}

impl IWnd for QuickWnd
{
    // The chips share the width the strip is given.
    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        .scrollWnd.IWnd.onResizeEvent(evt)
        .fitChips()
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if evt.kind == .Pressed and evt.button == .Right
        {
            .btnPopup(null, evt.surfacePos)
            evt.accepted = true
            return
        }

        .scrollWnd.IWnd.onMouseEvent(evt)
    }

    // A preset cell names what it shows on its tooltip, and that word is written once, when the
    // cell is built. A language switch has to write it again, which the rebuild does.
    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged do
            .updateQuickStyles(forceRebuild: true)
    }

    mtd impl onSerializeStateEvent(evt: *SerializeStateEvent)
    {
        catch
        {
            with evt.serializer
            {
                try .serialize("QuickWnd.qsArrow", &me.qsArrow)
                try .serialize("QuickWnd.qsShape", &me.qsShape)
                try .serialize("QuickWnd.qsImage", &me.qsImage)
                try .serialize("QuickWnd.qsStep", &me.qsStep)
                try .serialize("QuickWnd.qsLine", &me.qsLine)
                try .serialize("QuickWnd.qsPolygon", &me.qsPolygon)
                try .serialize("QuickWnd.qsText", &me.qsText)
                try .serialize("QuickWnd.qsFavorites", &me.qsFavorites)
                try .serialize("QuickWnd.qsDraw", &me.qsDraw)
                try .serialize("QuickWnd.qsHighlight", &me.qsHighlight)
                try .serialize("QuickWnd.qsPixSel", &me.qsPixSel)
                try .serialize("QuickWnd.qsCallout", &me.qsCallout)
            }
        }
    }
}

impl QuickWnd
{
    // Drops the unknown entries of every quick style set, refills the empty ones with their
    // defaults, and makes the first entry of each set the model of its tool.
    mtd setDefault()
    {
        .qsArrow.sanitize()
        .qsShape.sanitize()
        .qsImage.sanitize()
        .qsStep.sanitize()
        .qsLine.sanitize()
        .qsPolygon.sanitize()
        .qsText.sanitize()
        .qsFavorites.sanitize()
        .qsDraw.sanitize()
        .qsHighlight.sanitize()
        .qsPixSel.sanitize()
        .qsCallout.sanitize()

        if .qsArrow.forms.isEmpty() do
            .defaultQuickStyleArrow()
        if .qsShape.forms.isEmpty() do
            .defaultQuickStyleShape()
        if .qsImage.forms.isEmpty() do
            .defaultQuickStyleImage()
        if .qsStep.forms.isEmpty() do
            .defaultQuickStyleStep()
        if .qsLine.forms.isEmpty() do
            .defaultQuickStyleLine()
        if .qsPolygon.forms.isEmpty() do
            .defaultQuickStylePolygon()
        if .qsText.forms.isEmpty() do
            .defaultQuickStyleText()
        if .qsDraw.forms.isEmpty() do
            .defaultQuickStyleDraw()
        if .qsHighlight.forms.isEmpty() do
            .defaultQuickStyleHighlight()
        if .qsPixSel.forms.isEmpty() do
            .defaultQuickStylePixSel()
        if .qsCallout.forms.isEmpty() do
            .defaultQuickStyleCallout()

        .updateQuickStyles(forceRebuild: true)

        .main.updateModel(.qsArrow.forms[0])
        .main.updateModel(.qsLine.forms[0])
        .main.updateModel(.qsShape.forms[0])
        .main.updateModel(.qsImage.forms[0])
        .main.updateModel(.qsStep.forms[0])
        .main.updateModel(.qsPolygon.forms[0])
        .main.updateModel(.qsText.forms[0])
        .main.updateModel(.qsDraw.forms[0])
        .main.updateModel(.qsCallout.forms[0])
        .updateSelection()
    }

    // Shows the quick style menu at `pos`: remove the style `btn` holds, or reset the set.
    mtd btnPopup(btn: *Button?, pos: Math.Point)
    {
        with let menu = MenuCtrl.createPopup(me)
        {
            .addItem(appStrings().ui_RenameQuickStyle, "rename", disabled: not btn)
            .addItem(appStrings().ui_ReplaceQuickStyle, "replace", disabled: not btn)
            .addItem(appStrings().ui_RemoveQuickStyle, "0", disabled: not btn)
            .addSeparator()
            .addItem(ActionQuickStyle.Reset)
        }

        let result = menu.doModal(pos, autoDestroy: true)
        if not result or not btn or not .currentStyle do
            return

        let qbtn  = assume cast(*QuickButton, btn)
        let style = .currentStyle
        let form  = unwrap qbtn.formItf
        let index = style.indexOf(form)
        switch result
        {
        case "0":
            style.remove(form)
            qbtn.destroy()

        case "rename":
            let name = style.nameOf(index)
            var options: EditDlgOptions
            options.title   = appStrings().dlg_TitleRenameQuickStyle
            options.message = appStrings().ui_QuickStyleName
            options.text    = name
            let dialog = EditDlg.createSingleLine(unwrap .surface, options)
            if dialog.doModal() == Dialog.BtnOk do
                style.setName(index, dialog.text())

        case "replace":

            // The preset takes the style of the tool, or of the selection, keeping its name.
            if index < style.forms.count
            {
                let model = .main.newFormFromModel(.presetMode().mode)
                QuickStyle.deleteOne(style.forms[index])
                model.setup(null)
                style.forms[index] = model
            }
        }

        .updateQuickStyles(forceRebuild: true)
    }

    // Writes the name of the preset in force under the row, its menu being on its tooltip; no line
    // when no preset is in force.
    mtd updateCaption()
    {
        var name: String
        if .currentStyle
        {
            var i = 0'u64
            for c in .layout.children where not c.isPendingDestroy
            {
                let button = assume cast(*QuickButton, c)
                if button.isModel or button.isMore do
                    continue
                if button.isChecked
                {
                    name = .currentStyle.nameOf(i)
                    break
                }

                i += 1
            }
        }

        let caption = .caption
        if not caption do
            return
        if name.isEmpty()
        {
            caption.hide()
        }
        else
        {
            caption.setText(name)
            caption.show()
        }

        .fitChips()
    }

    // Builds the quick style strip: one row of preset chips, scrolling sideways when they outnumber
    // the width of the column, and the chip that keeps the current style as a preset.
    func create(parent: *Wnd, main: *MainWnd)->*QuickWnd
    {
        let metrics    = parent.themeMetrics()
        with let quick = Wnd.create'QuickWnd(parent, {0, 0, 0, QuickChipHeight + metrics.inspector_RowGap})
        {
            .backgroundStyle = .Transparent
            .updateFlags(.TransparentBars)

            // The presets stand in the column of the inspector, which keeps the margins, in rows
            // of chips; the strip keeps only the air between itself and the rows under it.
            .layout = Wnd.create'Wnd(quick, null, {0, 0, 0, QuickChipHeight})
            .layout.backgroundStyle = .Transparent
            .setView(quick.layout)

            // The row is one stop of Tab, and the keys go along it from there.
            .layout.focusPolicy = .Tab
            .layout.hookOnEvent = func|quick|(_, evt)->bool => quick.onRowEvent(evt)
            .keyCell = Swag.U64.Max

            let caption = Label.create(quick, "", {0, QuickChipHeight, 0, QuickCaptionHeight}, flags: .SecondaryText)
            caption.style.setFont(quick.theme().createDefaultFontFamily(metrics.defaultFontSize - 1))
            caption.setTextAlignment(.Left, .Center)
            caption.hide()
            .caption = caption

            .main = main
        }

        return quick
    }

    // Fills the arrow quick styles with the shipped set.
    mtd defaultQuickStyleArrow()
    {
        mtd add(startSize, borderSize, endSize: f32, color: Color, startCap = LineCapStyle.ArrowAnchor, dash = DashStyle.None)
        {
            with let form = Memory.new'FormArrow()
            {
                .startSize  = startSize
                .borderSize = borderSize
                .endSize    = endSize
                .dashStyle  = dash
                if startSize != 0 do
                    .beginCap = startCap
                if endSize != 0 do
                    .endCap = .ArrowAnchor
                .borderColor = color
            }

            .qsArrow.add(form)
        }

        const BorderSize = 10.0
        const ArrowSize  = 5.0

        .add(0, BorderSize, ArrowSize, ColorRed)
        .add(0, BorderSize, ArrowSize, ColorGreen)
        .add(0, BorderSize, ArrowSize, ColorBlue)
        .add(0, BorderSize, ArrowSize, ColorYellow)

        .add(ArrowSize, BorderSize, ArrowSize, ColorRed)
        .add(ArrowSize, BorderSize, ArrowSize, ColorGreen)
        .add(ArrowSize, BorderSize, ArrowSize, ColorBlue)
        .add(ArrowSize, BorderSize, ArrowSize, ColorYellow)

        .add(ArrowSize * 0.5, BorderSize, ArrowSize, ColorRed, .RoundAnchor, .Dot)
        .add(ArrowSize * 0.5, BorderSize, ArrowSize, ColorGreen, .RoundAnchor, .Dot)
        .add(ArrowSize * 0.5, BorderSize, ArrowSize, ColorBlue, .RoundAnchor, .Dot)
        .add(ArrowSize * 0.5, BorderSize, ArrowSize, ColorYellow, .RoundAnchor, .Dot)
    }

    // Fills the line quick styles with the shipped set.
    mtd defaultQuickStyleLine()
    {
        mtd add(borderSize: f32, color: Color)
        {
            with let form = Memory.new'FormLine()
            {
                .borderSize  = borderSize
                .borderColor = color
            }

            .qsLine.add(form)
        }

        const BorderSize = 10.0

        .add(BorderSize, ColorRed)
        .add(BorderSize, ColorGreen)
        .add(BorderSize, ColorBlue)
        .add(BorderSize, ColorYellow)
        .add(BorderSize, Argb.White)
        .add(BorderSize, Argb.Gray)
        .add(BorderSize, Argb.Black)
    }

    // Fills the shape quick styles with the shipped set.
    mtd defaultQuickStyleShape()
    {
        mtd add(borderSize: f32, kind: FormShapeKind, color: Color, backColor: Color)
        {
            with let form = Memory.new'FormShape()
            {
                .borderSize  = borderSize
                .borderColor = color
                .backColor   = backColor
                .kind        = kind
            }

            .qsShape.add(form)
        }

        const BorderSize = 10.0

        .add(BorderSize, .RoundRectangle, ColorRed, Argb.Zero)
        .add(BorderSize, .RoundRectangle, ColorGreen, Argb.Zero)
        .add(BorderSize, .RoundRectangle, ColorBlue, Argb.Zero)
        .add(BorderSize, .RoundRectangle, ColorYellow, Argb.Zero)

        // The row shows the first five until use reorders them: the fifth is another shape, so
        // it does not read as the first one again.
        .add(BorderSize, .Ellipse, ColorRed, Argb.Zero)
        .add(BorderSize, .Ellipse, ColorGreen, Argb.Zero)
        .add(BorderSize, .Ellipse, ColorBlue, Argb.Zero)
        .add(BorderSize, .Ellipse, ColorYellow, Argb.Zero)

        .add(BorderSize, .Rectangle, ColorRed, Argb.Zero)
        .add(BorderSize, .Rectangle, ColorGreen, Argb.Zero)
        .add(BorderSize, .Rectangle, ColorBlue, Argb.Zero)
        .add(BorderSize, .Rectangle, ColorYellow, Argb.Zero)

        .add(BorderSize, .Rectangle, Argb.White, Argb.Zero)
        .add(BorderSize, .Rectangle, Argb.Black, Argb.Zero)

        .add(0, .Rectangle, Argb.Zero, Argb.White)
        .add(0, .Rectangle, Argb.Zero, Argb.Black)
    }

    // Fills the image quick styles with the shipped set.
    mtd defaultQuickStyleImage()
    {
        mtd add(borderSize: f32, kind: FormImageKind, color: Color)
        {
            with let form = Memory.new'FormImage()
            {
                .borderSize  = borderSize
                .borderColor = color
                .backColor   = Argb.Gray
                .kind        = kind
                if borderSize == 0 do
                    .paintShadow = false
            }

            .qsImage.add(form)
        }

        .add(2, .Image, Argb.White)
        .add(2, .Zoom, Argb.White)
        .add(0, .Blur, Argb.Zero)
        .add(0, .Pixelate, Argb.Zero)
        .add(0, .Capture, Argb.Zero)
    }

    // Fills the step marker quick styles with the shipped set.
    mtd defaultQuickStyleStep()
    {
        mtd add(kind: FormShapeKind, color: Color, backColor: Color)
        {
            with let form = Memory.new'FormStep()
            {
                .borderColor = color
                .backColor   = backColor
                .kind        = kind
            }

            .qsStep.add(form)
        }

        .add(.Ellipse, Argb.White, ColorRed)
        .add(.Ellipse, Argb.White, ColorGreen)
        .add(.Ellipse, Argb.White, ColorBlue)
        .add(.Ellipse, Argb.White, ColorYellow)

        .add(.RoundRectangle, Argb.White, ColorRed)
        .add(.RoundRectangle, Argb.White, ColorGreen)
        .add(.RoundRectangle, Argb.White, ColorBlue)
        .add(.RoundRectangle, Argb.White, ColorYellow)
    }

    // Fills the polygon quick styles with the shipped set, straight and curved.
    mtd defaultQuickStylePolygon()
    {
        mtd add(borderSize: f32, color: Color, bezier = false)
        {
            with let form = Memory.new'FormPolygon()
            {
                .borderSize  = borderSize
                .borderColor = color
                .backColor   = 0
                .bezier      = bezier
            }

            .qsPolygon.add(form)
        }

        const BorderSize = 5.0

        .add(BorderSize, ColorRed)
        .add(BorderSize, ColorGreen)
        .add(BorderSize, ColorBlue)
        .add(BorderSize, ColorYellow)

        .add(BorderSize, ColorRed, true)
        .add(BorderSize, ColorGreen, true)
        .add(BorderSize, ColorBlue, true)
        .add(BorderSize, ColorYellow, true)

        .add(BorderSize, Argb.White)
        .add(BorderSize, Argb.Black)
    }

    // Fills the callout quick styles with the shipped set.
    mtd defaultQuickStyleCallout()
    {
        mtd add(bdColor, bkColor, txColor: Color)
        {
            with let form = Memory.new'FormCallout()
            {
                .borderSize  = 4
                .borderColor = bdColor
                .backColor   = bkColor
                .textColor   = txColor
                .roundSize   = 16
                .fontSize    = 40
                .text        = "A"
            }

            .qsCallout.add(form)
        }

        .add(Argb.White, ColorRed, Argb.White)
        .add(Argb.White, ColorGreen, Argb.White)
        .add(Argb.White, ColorBlue, Argb.White)
        .add(Argb.White, ColorYellow, Argb.Black)
        .add(Argb.White, Argb.Black, Argb.White)
        .add(Argb.Black, Argb.White, Argb.Black)
    }

    // Fills the text quick styles with the shipped set.
    mtd defaultQuickStyleText()
    {
        mtd add(borderSize, fontSize: f32, bdColor, bkColor: Color)
        {
            with let form = Memory.new'FormText()
            {
                .borderSize  = borderSize
                .borderColor = bdColor
                .backColor   = bkColor
                .fontSize    = fontSize
                .text        = "A"
            }

            .qsText.add(form)
        }

        .add(4, 24, Argb.White, ColorRed)
        .add(4, 24, Argb.White, ColorGreen)
        .add(4, 48, Argb.White, ColorBlue)
        .add(4, 48, Argb.White, ColorYellow)

        .add(4, 72, Argb.White, ColorRed)
        .add(4, 72, Argb.White, ColorGreen)
        .add(4, 72, Argb.White, ColorBlue)
        .add(4, 72, Argb.White, ColorYellow)

        .add(4, 48, Argb.Zero, Argb.White)
        .add(4, 48, Argb.Zero, Argb.Gray)
        .add(4, 48, Argb.Zero, Argb.Black)

        .add(4, 72, Argb.Zero, Argb.White)
        .add(4, 72, Argb.Zero, Argb.Gray)
        .add(4, 72, Argb.Zero, Argb.Black)
    }

    // Fills the freehand drawing quick styles with the shipped set.
    mtd defaultQuickStyleDraw()
    {
        mtd add(borderSize: f32, color: Color)
        {
            with let form = Memory.new'FormDraw()
            {
                .borderSize  = borderSize
                .borderColor = color
            }

            .qsDraw.add(form)
        }

        const BorderSize = 10.0

        .add(BorderSize, ColorRed)
        .add(BorderSize, ColorGreen)
        .add(BorderSize, ColorBlue)
        .add(BorderSize, ColorYellow)

        .add(BorderSize, Argb.White)
        .add(BorderSize, Argb.Gray)
        .add(BorderSize, Argb.Black)
    }

    // Fills the highlighter quick styles with the shipped set: strokes, rectangles, ellipses, and
    // polygons, all translucent.
    mtd defaultQuickStyleHighlight()
    {
        mtd addDraw(borderSize: f32, color: Color)
        {
            with let form = Memory.new'FormDraw()
            {
                .borderSize  = borderSize
                .borderColor = color
                .alpha       = 30
                .subKind     = .Highlight
            }

            .qsHighlight.add(form)
        }

        mtd addShape(kind: FormShapeKind, backColor: Color)
        {
            with let form = Memory.new'FormShape()
            {
                .borderSize  = 0
                .borderColor = Argb.Zero
                .backColor   = backColor
                .alpha       = 30
                .kind        = kind
                .subKind     = .Highlight
            }

            .qsHighlight.add(form)
        }

        mtd addPoly(backColor: Color)
        {
            with let form = Memory.new'FormPolygon()
            {
                .borderSize  = 0
                .borderColor = Argb.Zero
                .backColor   = backColor
                .alpha       = 30
                .subKind     = .Highlight
            }

            .qsHighlight.add(form)
        }

        const BorderSize = 20.0

        .addShape(.Rectangle, ColorRed)
        .addShape(.Rectangle, ColorGreen)
        .addShape(.Rectangle, ColorBlue)
        .addShape(.Rectangle, ColorYellow)

        .addDraw(BorderSize, ColorRed)
        .addDraw(BorderSize, ColorGreen)
        .addDraw(BorderSize, ColorBlue)
        .addDraw(BorderSize, ColorYellow)

        .addPoly(ColorRed)
        .addPoly(ColorGreen)
        .addPoly(ColorBlue)
        .addPoly(ColorYellow)
    }

    // Fills the pixel selection quick styles with the shipped set.
    mtd defaultQuickStylePixSel()
    {
        mtd addDraw()
        {
            with let form = Memory.new'FormDraw()
            {
                .subKind     = .PixSel
                .paintShadow = false
            }

            .qsPixSel.add(form)
        }

        mtd addShape(kind: FormShapeKind)
        {
            with let form = Memory.new'FormShape()
            {
                .kind        = kind
                .subKind     = .PixSel
                .paintShadow = false
            }

            .qsPixSel.add(form)
        }

        mtd addPoly()
        {
            with let form = Memory.new'FormPolygon()
            {
                .subKind     = .PixSel
                .paintShadow = false
            }

            .qsPixSel.add(form)
        }

        with me
        {
            .addShape(.Rectangle)
            .addShape(.Ellipse)
            .addPoly()
            .addDraw()
        }
    }

    // Returns the tool whose presets the row shows: the kind of the selection, or the tool in
    // hand without one. `found` is false for a selection of several kinds.
    mtd presetMode()->{found: bool, mode: EditMode}
    {
        let capture = .main.getCapture()
        if capture and not capture.selection.isEmpty()
        {
            let first = MainWnd.formToolMode(capture.forms[capture.selection[0]])
            for i in capture.selection where MainWnd.formToolMode(capture.forms[i]) != first do
                return {false, first}
            return {true, first}
        }

        return {true, .main.editMode == .Selection ? .main.getEditMode() : .main.editMode}
    }

    // Checks the quick style button that matches the model of the active tool.
    mtd updateSelection()
    {
        if not .currentStyle do
            return
        var done = false
        let mode = .presetMode().mode

        // The preset chips lead the strip in the order of the set; a chip of a previous set may
        // still be waiting for its deferred destruction, and the trailing chip adds a preset.
        var i = 0'u64
        for c in .layout.children where not c.isPendingDestroy
        {
            let button = assume cast(*QuickButton, c)
            if button.isModel or button.isMore or i >= .currentStyle.forms.count do
                continue

            let it  = .currentStyle.forms[i]
            let mdl = .main.modelFor(Swag.kindOf(it))
            button.setChecked(mode == MainWnd.formToolMode(it) and it.isSame(mdl))
            if button.isChecked do
                done = true
            i += 1
        }

        .updateCaption()
        .invalidate()
    }

    // Puts back the shipped quick styles of the active tool, after the reader confirms it.
    mtd resetQuickStyles()
    {
        if not .currentStyle do
            return

        if MessageDlg.confirm(unwrap .surface, appStrings().msg_ResetStyles) != MessageDlg.BtnYes do
            return

        .currentStyle.clear()

        // The style set was recreated in place: the existing buttons hold pointers to
        // the freed forms, so a full rebuild is mandatory (see updateQuickStyles).
        switch #complete .main.editMode
        {
        case .Arrow:     .defaultQuickStyleArrow()
        case .Shape:     .defaultQuickStyleShape()
        case .Image:     .defaultQuickStyleImage()
        case .Step:      .defaultQuickStyleStep()
        case .Line:      .defaultQuickStyleLine()
        case .Polygon:   .defaultQuickStylePolygon()
        case .Text:      .defaultQuickStyleText()
        case .Draw:      .defaultQuickStyleDraw()
        case .Highlight: .defaultQuickStyleHighlight()
        case .PixSel:    .defaultQuickStylePixSel()
        case .Callout:   .defaultQuickStyleCallout()
        case .Favorites: break
        case .Selection: break
        }

        .updateQuickStyles(forceRebuild: true)
    }

    // The presets of the tool `mode`; the selection tool has none of its own.
    mtd styleOf(mode: EditMode)->*QuickStyle?
    {
        switch #complete mode
        {
        case .Arrow:     return &.qsArrow
        case .Shape:     return &.qsShape
        case .Image:     return &.qsImage
        case .Step:      return &.qsStep
        case .Line:      return &.qsLine
        case .Polygon:   return &.qsPolygon
        case .Text:      return &.qsText
        case .Favorites: return &.qsFavorites
        case .Draw:      return &.qsDraw
        case .Highlight: return &.qsHighlight
        case .PixSel:    return &.qsPixSel
        case .Callout:   return &.qsCallout
        case .Selection: return null
        }
    }

    // Whether the trailing cell offers to keep the style of `model` as a preset: the highlighter
    // only keeps highlighter styles, and a pixel selection has no style worth keeping.
    mtd offersModel(model: *BaseForm)->bool
    {
        switch .main.editMode
        {
        case .Highlight: return model.subKind == .Highlight
        case .PixSel:    return false
        default:         return model.subKind != .Highlight and model.subKind != .PixSel
        }
    }

    // Returns the cell of a chip: the chip less the room of the ring.
    func presetCell(chip: *Wnd)->Math.Rectangle
    {
        var result = chip.clientRect()
        result.inflate(-QuickChipInset)
        return result
    }

    // Paints a preset: its cell on the raised ground, the picture of the shape it draws in its
    // own colours, and the Arc ring when it is the preset in force.
    func paintPreset(painter: *Painter, btnp: *QuickButton)
    {
        let colors = btnp.themeColors()
        let cell   = presetCell(btnp)

        painter.setParams(.Antialiased)

        // A light preset on a light ground stands on a slightly deeper cell, so its words or its
        // stroke still read. Not ringed: a ring around a cell is what marks the preset in force.
        let itf   = unwrap btnp.formItf
        let light = luminance(colors.raised) > 0.6 and
                    luminance(presetInk(itf)) > 0.75 and
                    not (itf is FormImage)
        painter.fillRoundRect(cell, QuickCellCorner, QuickCellCorner, light ? Color.lerpRgb(colors.raised, colors.text, QuickLightDepth) : colors.raised)

        // A mask shows what it does to what it covers.
        if itf is FormImage as image where image.subKind == .None
        {
            paintMaskPattern(painter, cell, image.kind, colors)
            paintPresetRing(painter, btnp, cell)
            return
        }

        // Each sample is painted at the zoom and with the sizes its copy chose for the cell.
        var paintForm = QuickStylePaintForm.create(itf)
        defer paintForm.release()
        painter.pushClippingRect(cell)
        painter.pushTransform()
        painter.translateTransform(cell.x, cell.y)
        Capture.paintForm(painter, {}, {0, 0, QuickCellWidth, QuickCellHeight}, unwrap paintForm.itf, zoom: paintForm.zoom, quickMode: paintForm.quick)
        painter.popTransform()
        painter.popClippingRect()

        paintPresetRing(painter, btnp, cell)
    }

    // Rings the cell of the preset in force in Arc, at a gap.
    func paintPresetRing(painter: *Painter, btnp: *QuickButton, cell: Math.Rectangle)
    {
        // The cell the keys stand on is ringed in the focus ink, the preset in force in Arc.
        if not btnp.isChecked and not btnp.keyChosen do
            return
        var ring = cell
        ring.inflate(QuickRingGap + QuickRingWidth * 0.5)
        let r      = QuickCellCorner + QuickRingGap + QuickRingWidth * 0.5
        let colors = btnp.themeColors()
        painter.drawRoundRect(ring, r, r, btnp.isChecked ? colors.arc : colors.focusRing, btnp.isChecked ? QuickRingWidth : 1.5)
    }

    // Returns the ink a preset is mostly seen in: the fill of words and of a step, the stroke of
    // everything else.
    func presetInk(itf: IForm)->Color
    {
        switch itf
        {
        case FormText as text:       return text.backColor
        case FormCallout as callout: return callout.backColor
        case FormStep as step:       return step.backColor
        }

        return itf.borderColor
    }

    // Returns how light `color` reads, from 0 to 1.
    func luminance(color: Color)->f32 => (0.299 * cast(f32, color.r) + 0.587 * cast(f32, color.g) + 0.114 * cast(f32, color.b)) / 255

    // Paints what a mask of `kind` does, in the middle of `cell`: the pixels of a pixelation,
    // the soft pixels of a blur, a solid picture, a magnifier, a captured window.
    func paintMaskPattern(painter: *Painter, cell: Math.Rectangle, kind: FormImageKind, colors: *ThemeColors)
    {
        let frame = Math.Rectangle{Math.round(cell.horzCenter() - QuickMaskWidth * 0.5), Math.round(cell.vertCenter() - QuickMaskHeight * 0.5), QuickMaskWidth, QuickMaskHeight}
        let dark  = colors.softText
        let pale  = colors.faintText
        switch #complete kind
        {
        case .Pixelate, .Blur:

            // Pixels in two tones; a blur keeps them closer and softer.
            let side = QuickMaskHeight / 4
            let cols = cast(s32, QuickMaskWidth / side)
            for y in 4
            {
                for x in cols
                {
                    var color = (x + y) % 2 ? dark : pale
                    if kind == .Blur do
                        color = Color.lerpRgb(dark, pale, cast(f32, (x * 2 + y) % 3) * 0.25 + 0.25)
                    painter.fillRect(Math.Rectangle{frame.x + cast(f32, x) * side, frame.y + cast(f32, y) * side, side, side}, color)
                }
            }

        case .Image:
            painter.fillRoundRect(frame, 2, 2, colors.text)

        case .Zoom:
            let r  = QuickMaskHeight * 0.36
            let cx = frame.horzCenter() - 2
            let cy = frame.vertCenter() - 2
            painter.drawCircle(cx, cy, r, dark, 1.8)
            painter.drawLine(cx + r * 0.72, cy + r * 0.72, cx + r * 1.5, cy + r * 1.5, dark, 2.2)

        case .Capture:
            painter.drawRoundRect(frame, 2, 2, dark, 1.5)
            painter.fillRect(Math.Rectangle{frame.x, frame.y, frame.width, 4}, dark)
        }
    }

    // Paints the trailing chip, a hairline cell and its "+", or the chip opening every preset and
    // its "•••".
    func paintAddPreset(painter: *Painter, btnp: *QuickButton, more = false)
    {
        let colors  = btnp.themeColors()
        let metrics = btnp.themeMetrics()
        let cell    = presetCell(btnp)
        painter.setParams(.Antialiased)
        painter.drawRoundRect(cell, QuickCellCorner, QuickCellCorner, colors.line, metrics.separator_HairlineSize)
        paintPresetRing(painter, btnp, cell)
        var icon = btnp.theme().icon(more ? ThemeIcons.More : ThemeIcons.Plus, AddGlyphSize)
        icon.paint(painter, Math.round(cell.horzCenter() - AddGlyphSize * 0.5), Math.round(cell.vertCenter() - AddGlyphSize * 0.5), colors.softText)
    }

    // Adds the cell of one preset to `parent`, the row when null; checking it applies the preset to
    // the tool and to the selection.
    #[Swag.Discardable]
    mtd addPresetButton(form: IForm, parent: *Wnd? = null)->*QuickButton
    {
        with let button = Wnd.create'QuickButton(parent orelse me.layout, null, {0, 0, QuickChipWidth, QuickChipHeight})
        {
            .updateFlags(.Radio)
            .setForm(.RoundedRectangle)
            .backgroundStyle = .Transparent

            // The picked preset is the cell that is lit, not the cell with a bar under it: a
            // rule in the accent below a sample drawn in the user's own colors reads as one
            // more thing painted in the cell rather than as the state of the cell.
            .setCheckIndicator(.None)
            clearChipGround(button)
            .formItf  = form
            .quickWnd = me
            .toolTip  = me.currentStyle ? Format.toString(appStrings().ui_QuickStyleTip, me.currentStyle.nameOf(me.currentStyle.indexOf(form))) : ""

            .iconPainter     = func(button, bc, _, _) { paintPreset(bc.painter, assume cast(*QuickButton, button)) }
            .sigRightPressed += func(button) { button.quickWnd.btnPopup(button, button.surfaceRect().center()) }
        }

        button.sigCheckedChanged += func(button)
        {
            if not button.isChecked do
                return
            button.quickWnd.applyPreset(unwrap button.formItf, fromPopover: button.inPopover)
        }

        return button
    }

    // Applies the preset `it` to the tool and to the selection, as one step of the history, and
    // counts the use: the presets used most lead the row.
    mtd applyPreset(it: IForm, fromPopover = false)
    {
        .main.updateModel(it)

        let capture = unwrap .main.getCapture()
        if not capture.selection.isEmpty()
        {
            with let undo = capture.newUndo(.SetFormFromModel)
            {
                .mdlType  = Swag.kindOf(it)
                .mdlValue = MainWnd.newFormFromForm(it)
            }

            capture.pushUndo(undo)
        }

        if .currentStyle
        {
            let index = .currentStyle.indexOf(it)
            let moved = .currentStyle.countUse(index) != index
            if fromPopover and .moreButton do
                .moreButton.hidePopup()
            if moved or fromPopover do
                .updateQuickStyles(forceRebuild: true)
        }

        .updateSelection()
        .main.updateState()
    }

    // Adds the chip opening every preset of the tool in a popover, shown when the row cannot hold
    // them all.
    mtd addMoreButton()
    {
        with let btn = Wnd.create'QuickButton(me.layout, null, {0, 0, QuickChipWidth, QuickChipHeight})
        {
            .updateFlags(.Popup)
            .isMore   = true
            .quickWnd = me
            .toolTip  = appStrings().tip_AllQuickStyles
            .setForm(.RoundedRectangle)
            .setCheckIndicator(.None)
            .setArrowPosition(.None)
            .backgroundStyle = .Transparent
            clearChipGround(btn)
            .iconPainter = func(button, bc, _, _) { paintAddPreset(bc.painter, assume cast(*QuickButton, button), more: true) }
        }

        btn.sigPopupRequested += func|quick = me|(button)
        {
            quick.openAllPresets(assume cast(*QuickButton, button))
        }

        // Down on the chip opens the popover, and the keys go on in it.
        btn.hookOnEvent = func|quick = me|(button, evt)->bool
        {
            if evt is KeyEvent as key where key.kind == .Pressed and key.key == .Down and quick.allPresets == null
            {
                quick.openAllPresets(assume cast(*QuickButton, button))
                key.accepted = true
                return true
            }

            return false
        }

        btn.sigPopupClosed += func|quick = me|(_)
        {
            quick.allPresets = null
        }

        .moreButton = btn
    }

    // Returns the chips the row shows, from left to right.
    mtd rowCells()->Array'(*QuickButton)
    {
        var result: #returntype
        for c in .layout.children where not c.isPendingDestroy and c.isLocallyVisible() do
            result.add(assume cast(*QuickButton, c))
        result.sort(func(a, b: *QuickButton)->s32 => a.position.x < b.position.x ? -1 : (a.position.x > b.position.x ? 1 : 0))
        return result
    }

    // Moves the keys to chip `index` of the row, which is ringed; past the end, to none.
    mtd chooseRowCell(index: u64)
    {
        let cells = .rowCells()
        .keyCell = index < cells.count ? index : Swag.U64.Max
        for cell, i in cells
        {
            cell.keyChosen = i == .keyCell
            cell.invalidate()
        }
    }

    // Returns where the keys enter the row: the preset in force, or the first chip.
    mtd rowStart()->u64
    {
        for cell, i in .rowCells() where cell.isChecked do
            return i
        return 0
    }

    // Answers the keys while the row holds the keyboard. Left and Right go along the chips; Enter
    // or Space applies the preset the keys stand on, opens the popover on "•••" and keeps the
    // current style on "+"; Down on "•••" opens the popover too.
    mtd onRowEvent(evt: IEvent)->bool
    {
        if evt is FocusEvent as focus
        {
            if focus.kind == .Gained do
                .chooseRowCell(.rowStart())
            elif focus.kind == .Lost and .allPresets == null do
                .chooseRowCell(Swag.U64.Max)
            return false
        }

        let key = catch cast(*KeyEvent?, evt)
        if not key or key.kind != .Pressed or not key.modifiers.equals(.None) do
            return false

        let cells = .rowCells()
        if .keyCell >= cells.count do
            .keyCell = .rowStart()
        if .keyCell >= cells.count do
            return false
        let cell = cells[.keyCell]

        switch key.key
        {
        case .Left:
            if .keyCell > 0 do
                .chooseRowCell(.keyCell - 1)

        case .Right:
            if .keyCell + 1 < cells.count do
                .chooseRowCell(.keyCell + 1)

        case .Down:
            if not cell.isMore or .allPresets != null do
                return false
            .openAllPresets(cell)

        case .Return, .Space:
            if cell.isMore
            {
                if .allPresets == null do
                    .openAllPresets(cell)
            }
            elif cell.isModel
            {
                .addCurrentStyle()
            }
            else
            {
                .applyPreset(unwrap cell.formItf)
                .chooseRowCell(.rowStart())
            }

        default:
            return false
        }

        key.accepted = true
        return true
    }

    // Opens every preset of the tool in a popover under `button`, in rows as wide as the inspector
    // row; the preset in force is ringed there too.
    mtd openAllPresets(button: *QuickButton)
    {
        let style = .currentStyle
        if not style do
            return

        let model     = .main.editModeToModel(.presetMode().mode)
        let canAdd    = .offersModel(model)
        let count     = style.forms.count + (canAdd ? 1 : 0)
        let perRow    = cast(u64, QuickPopoverColumns)
        let rows      = (count + perRow - 1) / perRow
        let width     = cast(f32, Math.min(count, perRow)) * QuickChipWidth + 2 * QuickPopoverPad
        let height    = cast(f32, rows) * QuickChipHeight + 2 * QuickPopoverPad
        let frame     = button.createAnchorPopup(width, height)
        with let body = Wnd.create'PresetPopover(frame, null, {})
        {
            .dockStyle       = .Center
            .backgroundStyle = .Transparent
            .focusPolicy     = .Tab
            .quick           = me
        }

        .allPresets = body

        let mode = .presetMode().mode
        for it, i in style.forms
        {
            let cell = .addPresetButton(it, body)
            cell.inPopover = true
            cell.setPosition(Math.Rectangle{QuickPopoverPad + cast(f32, i % perRow) * QuickChipWidth, QuickPopoverPad + cast(f32, i / perRow) * QuickChipHeight, QuickChipWidth, QuickChipHeight})
            cell.setChecked(mode == MainWnd.formToolMode(it) and it.isSame(.main.modelFor(Swag.kindOf(it))))
        }

        // "+" closes the popover too, keeping the current style as a new preset.
        if canAdd
        {
            let i   = style.forms.count
            let add = .addModelButton(model, body)
            add.inPopover = true
            add.setPosition(Math.Rectangle{QuickPopoverPad + cast(f32, i % perRow) * QuickChipWidth, QuickPopoverPad + cast(f32, i / perRow) * QuickChipHeight, QuickChipWidth, QuickChipHeight})
        }

        // The keys stand on the preset in force, or on the first one.
        var start = 0'u64
        for c, i in body.children
        {
            if (assume cast(*QuickButton, c)).isChecked do
                start = i
        }

        body.choose(start)
        body.setFocus()
    }

    // Adds the chip keeping the current style of the tool as a new preset to `parent`, the row
    // when null.
    #[Swag.Discardable]
    mtd addModelButton(form: IForm, parent: *Wnd? = null)->*QuickButton
    {
        with let btn = Wnd.create'QuickButton(parent orelse me.layout, null, {0, 0, QuickChipWidth, QuickChipHeight})
        {
            .isModel = true
            .formItf = form
            .toolTip = appStrings().tip_AddQuickStyle
            .setForm(.RoundedRectangle)
            .setCheckIndicator(.None)
            .backgroundStyle = .Transparent
            clearChipGround(btn)
            .iconPainter = func(button, bc, _, _) { paintAddPreset(bc.painter, assume cast(*QuickButton, button)) }
        }

        btn.sigPressed += func|quickWnd = me|(_) { quickWnd.addCurrentStyle() }
        return btn
    }

    // Keeps the current style of the tool, or of the selection, as a new preset.
    mtd addCurrentStyle()
    {
        let style = .currentStyle
        if not style do
            return
        style.add(.main.newFormFromModel(.presetMode().mode))
        if .moreButton do
            .moreButton.hidePopup()
        .updateQuickStyles(forceRebuild: true)
    }

    // Shows the quick styles of the active tool, rebuilding the buttons when the set changed or
    // `forceRebuild` asks for it.
    mtd updateQuickStyles(forceRebuild = false)
    {
        let presets   = .presetMode()
        let prevStyle = .currentStyle
        let style     = presets.found ? .styleOf(presets.mode) : null
        if not style
        {
            // A selection of several kinds has no preset in common: the row leaves.
            for c in .layout.children do
                c.destroy()
            .currentStyle = null
            .moreButton   = null
            if .isVisible()
            {
                .hide()
                .parent?.applyLayout()
            }

            return
        }

        .currentStyle = style
        if not .isVisible()
        {
            .show()
            .parent?.applyLayout()
        }

        let formItf     = .main.editModeToModel(presets.mode)
        let canAddModel = .offersModel(formItf)

        // Light path: same style target and same button population. Destroying and
        // recreating every button is only needed when the style set itself changed;
        // check states and the model button repaint from live data.
        let wantBtns = style.forms.count + 1 + (canAddModel ? 1 : 0)
        var liveBtns = 0'u64
        for c in .layout.children where not c.isPendingDestroy do
            liveBtns += 1
        if not forceRebuild and style == prevStyle and liveBtns == wantBtns
        {
            .updateSelection()
            return
        }

        for c in .layout.children do
            c.destroy()
        .moreButton = null
        for it in style.forms do
            .addPresetButton(it)
        .addMoreButton()
        if canAddModel do
            .addModelButton(formItf)

        .updateSelection()
        .fitChips()
    }

    // Lays the chips in one row across the width of the inspector column: the presets the row
    // holds, the most recently chosen first, then "+", or "•••" when some are left out.
    mtd fitChips()
    {
        if .layout == null do
            return

        var presets: Array'(*Wnd)
        var more:    *Wnd?
        var model:   *Wnd?
        for c in .layout.children where not c.isPendingDestroy
        {
            let button = assume cast(*QuickButton, c)
            if button.isMore do
                more = c
            elif button.isModel do
                model = c
            else do
                presets.add(c)
        }

        // When the row cannot hold every preset and "+", it holds the first presets and "•••",
        // and "+" moves into the popover "•••" opens.
        let perRow = cast(u64, Math.max(1, cast(s32, Math.floor((.position.width + 0.5) / QuickChipWidth))))
        let all    = presets.count + (model ? 1 : 0) <= perRow
        let shown  = all ? presets.count : perRow - 1

        var x = 0'f32
        for c, i in presets
        {
            c.show(i < shown)
            if i < shown
            {
                c.setPosition(Math.Rectangle{x, 0, QuickChipWidth, QuickChipHeight})
                x += QuickChipWidth
            }
        }

        if more
        {
            more.show(not all)
            if not all
            {
                more.setPosition(Math.Rectangle{x, 0, QuickChipWidth, QuickChipHeight})
                x += QuickChipWidth
            }
        }

        if model
        {
            model.show(all)
            if all
            {
                model.setPosition(Math.Rectangle{x, 0, QuickChipWidth, QuickChipHeight})
                x += QuickChipWidth
            }
        }

        // The name of the preset in force stands under the row, across the column.
        var height  = QuickChipHeight
        let caption = .caption
        if caption and caption.isVisible()
        {
            caption.setPosition(Math.Rectangle{x: QuickChipInset, y: height, width: Math.max(.position.width - 2 * QuickChipInset, 0), height: QuickCaptionHeight})
            height += QuickCaptionHeight
        }

        .layout.setPosition(Math.Rectangle{x: 0, y: 0, width: x, height: QuickChipHeight})
        .setScrollSize(0, 0)
        let wanted = height + .themeMetrics().inspector_RowGap
        if .position.height != wanted
        {
            .resize(.position.width, wanted)
            .parent?.applyLayout()
        }
    }
}
