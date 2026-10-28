// A preset is a small picture of the shape it draws, in its own colours, painted by the painter
// of the canvas: a cell of the raised ground, the preset in force ringed in Arc.
const QuickCellWidth  = 44.0     // Width of the cell of a preset.
const QuickCellHeight = 36.0     // Height of the cell of a preset.
const QuickCellCorner = 7.0      // Corner of the cell.
const QuickRingGap    = 2.0      // Air between the cell and the ring of the preset in force.
const QuickRingWidth  = 2.0      // Weight of that ring.
const QuickCellMargin = 6.0      // Least air between a sample and the edge of its cell.

// A chip holds its cell and the room of the ring around it, so two cells stand twice that room
// apart, and the ring is never cut by the chip.
const QuickChipInset  = QuickRingGap + QuickRingWidth
const QuickChipWidth  = QuickCellWidth + 2 * QuickChipInset
const QuickChipHeight = QuickCellHeight + 2 * QuickChipInset

// The size the sample of a preset is painted at, as a frame its shape is laid out in, before the
// room its stroke and its ends take is kept around it.
const QuickSampleWidth  = 28.0
const QuickSampleHeight = 18.0
const QuickStrokeZoom   = 0.35'f32     // The scale a line or an arrow is painted at in its cell.
const QuickTextHeight   = 16.0'f32     // The size the "Aa" of a text is painted at in its cell.

// The glyph of the trailing chip, which keeps the selected shape as a new preset.
const AddGlyphSize = 14.0

// Clears the ground the theme gives a button, in every state, on a chip that paints its own cell.
func clearChipGround(button: *IconButton)
{
    for key in ["btnIcon_Bk", "btnIcon_HotBk", "btnIcon_PressedBk", "btnIcon_CheckedBk", "btnIcon_CheckedHotBk", "btnIcon_CheckedPressedBk",
                "btnIcon_CheckedMark", "btnIcon_CheckedHotMark", "btnIcon_CheckedPressedMark", "btnIcon_CheckedRing"] do
        button.style.addStyleSheetColors(Format.toString("% 0x00000000", key))
}

// The preset forms one tool offers in the quick-style bar.
struct QuickStyle
{
    forms: Array'IForm
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
        }
    }

    // Adopts a freshly built form as the last preset of the set.
    mtd add(form: IForm)
    {
        form.setup(null)
        .forms.add(form)
    }

    mtd remove(itf: IForm)
    {
        deleteOne(itf)
        .forms.remove(itf)
    }

    mtd clear()
    {
        for i in .forms do
            deleteOne(i)
        .forms.clear()
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
        case FormStep:  w, h = 18
        case FormImage: w, h = 22
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

        let m    = sampleInset(paintItf, cxt) * result.zoom
        w = Math.min(w, QuickCellWidth - 2 * (QuickCellMargin + m))
        h = Math.min(h, QuickCellHeight - 2 * (QuickCellMargin + m))
        let rect = Math.Rectangle{Math.round((QuickCellWidth - w) * 0.5), Math.round((QuickCellHeight - h) * 0.5), w, h}

        switch paintItf
        {
        case FormPolygon as poly: poly.setDefaultShape()
        case FormDraw as poly:    poly.setDefaultShape()
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
            cl.text      = "Aa"
            cl.fontSize  = 8
            cl.boldSize  = 0
            cl.roundSize = Math.min(cl.roundSize, 4)
            cl.borderSize = Math.min(cl.borderSize, 1)
            cl.alignHorz = .Center
            cl.alignVert = .Center
            cl.x         = cast(s32, Math.round((QuickCellWidth - 26) * 0.5))
            cl.y         = 10
            cl.w         = 26
            cl.h         = 13
            cl.tailX     = cl.x + 6
            cl.tailY     = cl.y + cl.h + 5
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
            .addItem(appStrings().ui_RemoveQuickStyle, "0", disabled: not btn)
            .addSeparator()
            .addItem(ActionQuickStyle.Reset)
        }

        let result = menu.doModal(pos, autoDestroy: true)
        if result == "0" and btn
        {
            let qbtn = assume cast(*QuickButton, btn)
            .currentStyle!.remove(unwrap qbtn.formItf)
            qbtn.destroy()
            .updateQuickStyles(forceRebuild: true)
        }
    }

    // Builds the quick style strip: one row of preset chips, scrolling sideways when they outnumber
    // the width of the column, and the chip that keeps the current style as a preset.
    func create(parent: *Wnd, main: *MainWnd)->*QuickWnd
    {
        let metrics = parent.themeMetrics()
        with let quick = Wnd.create'QuickWnd(parent, {0, 0, 0, QuickChipHeight + metrics.inspector_RowGap})
        {
            .backgroundStyle = .Transparent
            .updateFlags(.TransparentBars)

            // The presets stand in the column of the inspector, which keeps the margins, in rows
            // of chips; the strip keeps only the air between itself and the rows under it.
            .layout = Wnd.create'Wnd(quick, null, {0, 0, 0, QuickChipHeight})
            .layout.backgroundStyle = .Transparent
            .setView(quick.layout)

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

        .add(BorderSize, .Rectangle, ColorRed, Argb.Zero)
        .add(BorderSize, .Rectangle, ColorGreen, Argb.Zero)
        .add(BorderSize, .Rectangle, ColorBlue, Argb.Zero)
        .add(BorderSize, .Rectangle, ColorYellow, Argb.Zero)

        .add(BorderSize, .Ellipse, ColorRed, Argb.Zero)
        .add(BorderSize, .Ellipse, ColorGreen, Argb.Zero)
        .add(BorderSize, .Ellipse, ColorBlue, Argb.Zero)
        .add(BorderSize, .Ellipse, ColorYellow, Argb.Zero)

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

    // Checks the quick style button that matches the model of the active tool.
    mtd updateSelection()
    {
        if not .currentStyle do
            return
        var done = false
        let mode = .main.getEditMode()

        // The preset chips lead the strip in the order of the set; a chip of a previous set may
        // still be waiting for its deferred destruction, and the trailing chip adds a preset.
        var i = 0'u64
        for c in .layout.children where not c.isPendingDestroy
        {
            let button = assume cast(*QuickButton, c)
            if button.isModel or i >= .currentStyle.forms.count do
                continue

            let it  = .currentStyle.forms[i]
            let mdl = .main.modelFor(Swag.kindOf(it))
            button.setChecked(mode == MainWnd.formToEditMode(it) and it.isSame(mdl))
            if button.isChecked do
                done = true
            i += 1
        }

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
        painter.fillRoundRect(cell, QuickCellCorner, QuickCellCorner, colors.raised)

        // Each sample is painted at the zoom and with the sizes its copy chose for the cell.
        var paintForm = QuickStylePaintForm.create(unwrap btnp.formItf)
        defer paintForm.release()
        painter.pushClippingRect(cell)
        painter.pushTransform()
        painter.translateTransform(cell.x, cell.y)
        Capture.paintForm(painter, {}, {0, 0, QuickCellWidth, QuickCellHeight}, unwrap paintForm.itf, zoom: paintForm.zoom, quickMode: paintForm.quick)
        painter.popTransform()
        painter.popClippingRect()

        if btnp.isChecked
        {
            var ring = cell
            ring.inflate(QuickRingGap + QuickRingWidth * 0.5)
            let r = QuickCellCorner + QuickRingGap + QuickRingWidth * 0.5
            painter.drawRoundRect(ring, r, r, colors.arc, QuickRingWidth)
        }
    }

    // Paints the trailing chip: a hairline cell and its "+".
    func paintAddPreset(painter: *Painter, btnp: *QuickButton)
    {
        let colors  = btnp.themeColors()
        let metrics = btnp.themeMetrics()
        let cell    = presetCell(btnp)
        painter.setParams(.Antialiased)
        painter.drawRoundRect(cell, QuickCellCorner, QuickCellCorner, colors.line, metrics.separator_HairlineSize)
        var icon = btnp.theme().icon(.Plus, AddGlyphSize)
        icon.paint(painter, Math.round(cell.horzCenter() - AddGlyphSize * 0.5), Math.round(cell.vertCenter() - AddGlyphSize * 0.5), colors.softText)
    }

    // Adds the cell of one preset; checking it applies the preset to the tool and to the selection.
    mtd addPresetButton(form: IForm)
    {
        with let button = Wnd.create'QuickButton(me.layout, null, {0, 0, QuickChipWidth, QuickChipHeight})
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
            .toolTip  = quickStyleTip(form)

            .iconPainter     = func(button, bc, _, _) { paintPreset(bc.painter, assume cast(*QuickButton, button)) }
            .sigRightPressed += func(button) { button.quickWnd.btnPopup(button, button.surfaceRect().center()) }
        }

        button.sigCheckedChanged += func(button)
        {
            if not button.isChecked do
                return

            let quick = button.quickWnd
            let it    = unwrap button.formItf
            quick.main.updateModel(it)

            let capture = unwrap quick.main.getCapture()
            if not capture.selection.isEmpty()
            {
                with let undo = capture.newUndo(.SetFormFromModel)
                {
                    .mdlType  = Swag.kindOf(it)
                    .mdlValue = MainWnd.newFormFromForm(it)
                }

                capture.pushUndo(undo)
            }

            quick.updateSelection()
            quick.main.updateState()
        }
    }

    // Adds the trailing chip, which keeps the current style of the tool as a new preset.
    mtd addModelButton(form: IForm)
    {
        with let btn = Wnd.create'QuickButton(me.layout, null, {0, 0, QuickChipWidth, QuickChipHeight})
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

        btn.sigPressed += func|quickWnd = me|(_)
        {
            let main = quickWnd.main
            let mdl  = main.newFormFromModel(main.getEditMode())
            quickWnd.currentStyle!.forms.add(mdl)
            quickWnd.updateQuickStyles()
        }
    }

    // Shows the quick styles of the active tool, rebuilding the buttons when the set changed or
    // `forceRebuild` asks for it.
    mtd updateQuickStyles(forceRebuild = false)
    {
        let edMode    = .main.editMode == .Selection ? .main.getEditMode() : .main.editMode
        let prevStyle = .currentStyle
        let style     = .styleOf(edMode)
        if not style do
            return
        .currentStyle = style

        let formItf     = .main.editModeToModel(.main.getEditMode())
        let canAddModel = .offersModel(formItf)

        // Light path: same style target and same button population. Destroying and
        // recreating every button is only needed when the style set itself changed;
        // check states and the model button repaint from live data.
        let wantBtns = style.forms.count + (canAddModel ? 1 : 0)
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
        for it in style.forms do
            .addPresetButton(it)
        if canAddModel do
            .addModelButton(formItf)

        .updateSelection()
        .fitChips()
    }

    // Lays the chips in rows across the width of the inspector column, as many as fit, and makes
    // the strip as tall as its rows.
    mtd fitChips()
    {
        if .layout == null do
            return

        let perRow = Math.max(1, cast(s32, Math.floor((.position.width + 0.5) / QuickChipWidth)))
        var count  = 0's32
        for c in .layout.children where not c.isPendingDestroy
        {
            let col = count % perRow
            let row = count / perRow
            c.setPosition(Math.Rectangle{cast(f32, col) * QuickChipWidth, cast(f32, row) * QuickChipHeight, QuickChipWidth, QuickChipHeight})
            count += 1
        }

        let rows   = Math.max(1, (count + perRow - 1) / perRow)
        let height = cast(f32, rows) * QuickChipHeight
        .layout.setPosition(Math.Rectangle{0, 0, cast(f32, Math.min(count, perRow)) * QuickChipWidth, height})
        .setScrollSize(0, 0)
        let wanted = height + .themeMetrics().inspector_RowGap
        if .position.height != wanted
        {
            .resize(.position.width, wanted)
            .parent?.applyLayout()
        }
    }

}
