// The commands on a pixel selection: clear it, fill it, fill it from its border, or lift its
// pixels into a movable image and fill the hole they leave.
struct ActionPixSel {}

impl ActionPixSel
{
    newCmdId("Clear")
    newCmdId("Fill")
    newCmdId("SmartFill")
    newCmdId("SmartMove")
}

impl IActionUI for ActionPixSel
{
    acceptOwnCmdIds()

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        return updateFromTable(cxt, evt, [
            {Clear,     appStrings().act_Clear,     .PixSel, hideDisabled: true},
            {Fill,      appStrings().act_Fill,      .PixSel, hideDisabled: true},
            {SmartFill, appStrings().act_SmartFill, .PixSel, hideDisabled: true},
            {SmartMove, appStrings().act_SmartMove, .PixSel, hideDisabled: true}])
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main = mainWndOf(cxt)

        switch cxt.id
        {
        case .Clear:     main.pixSelClear()
        case .Fill:      main.pixSelFill()
        case .SmartFill: main.pixSelSmartFill()
        case .SmartMove: main.pixSelSmartMove()
        }

        return true
    }
}

impl MainWnd
{
    mtd getPixSels()->Array'IForm
    {
        var result: retval
        let capture = .getCapture()!
        foreachSelected'BaseForm(capture, capture.selection)
        {
            if form.subKind == .PixSel do
                result.add(itf)
        }

        return result
    }

    mtd pixSelClear()
    {
        .pixSelSetPixels(0)
    }

    mtd pixSelFill()
    {
        .pixSelSetPixels(g_Main!.pixSelFillCol.argb)
    }

    // Set every pixel inside the pixel selection to the given color
    mtd pixSelSetPixels(argb: u32)
    {
        var forms = .getPixSels()
        if forms.isEmpty() do
            return

        let capture = .getCapture()!

        with let undo = capture.newUndo(.SetImage)
        {
            .newImagePos = capture.backImagePos
            .newImg      = capture.backImg
        }

        var boundRects: Array'Math.Rectangle
        for f in forms do
            boundRects.add(f.boundRect())

        var params = {capture: capture, boundRects: boundRects.buffer, forms: &forms, argb: argb}
        undo.newImg.visitPixels(&params)
        {
            var p = cast(*#decltype(params), userData!)
            let boundRects = p.boundRects!
            for f, idx in p.forms[]
            {
                var pt = Math.Point{cast(f32, x), cast(f32, p.capture.backImg.height) - y}
                pt.x += p.capture.backImagePos.x
                pt.y += p.capture.backImagePos.y
                if not boundRects[idx].contains(pt) do
                    continue

                if f.isInside(pt)
                {
                    cast(*u32, pix)[] = p.argb
                    break
                }
            }
        }

        capture.pushUndo(undo)
    }

    // Fills every pixel selection with what surrounds it: each column blends from
    // the pixel above the selection to the pixel below. `masks`, when given,
    // receives the area each selection covers.
    mtd pixSelSmartFill(serial: u64 = 0, masks: *Array'Image? = null)
    {
        var forms = .getPixSels()
        if forms.isEmpty() do
            return

        let capture = .getCapture()!

        with let undo = capture.newUndo(.SetImage)
        {
            .newImagePos = capture.backImagePos
            .newImg      = capture.backImg
        }

        // What a smart fill samples around one selection: its bounds, and in each column the first
        // pixels inside it from the bottom and from the top, which the fill interpolates.
        struct Info
        {
            boundRect: Math.Rectangle
            boundCols: Array'{ y1: s32, y2: s32, col1: Color, col2: Color }
        }

        var infos: Array'Info

        for f in forms
        {
            var i: Info

            let br = f.boundRect()
            i.boundRect = br

            if masks
            {
                var image = Image.create(1 + cast(s32, br.width), 1 + cast(s32, br.height), .RGBA8)
                masks.add(#move image)
            }

            // Compute colors at the start and at the end of the column, to interpolate
            for x in undo.newImg.width
            {
                var col1, col2: Color
                var pt = Math.Point{cast(f32, x), 0}
                var y1 = cast(s32, (br.bottom() - capture.backImagePos.y))
                y1 = Math.clamp(y1, 0, undo.newImg.height - 1)
                y1 = undo.newImg.height - y1
                for undo.newImg.height
                {
                    pt.y = cast(f32, capture.backImg.height - y1) + capture.backImagePos.y
                    if br.contains(pt) and f.isInside(pt)
                    {
                        var pix32 = undo.newImg.pixels.buffer + x * undo.newImg.bytesPerPixel
                        pix32     += y1 * undo.newImg.width * undo.newImg.bytesPerPixel
                        col1.argb = cast(const *u32, pix32!)[]
                        break
                    }

                    y1 += 1
                }

                var y2 = cast(s32, br.y - capture.backImagePos.y)
                y2 = undo.newImg.height - y2
                y2 = Math.clamp(y2, 0, undo.newImg.height - 1)
                for undo.newImg.height
                {
                    pt.y = cast(f32, capture.backImg.height - y2) + capture.backImagePos.y
                    if br.contains(pt) and f.isInside(pt)
                    {
                        var pix32 = undo.newImg.pixels.buffer + x * undo.newImg.bytesPerPixel
                        pix32     += y2 * undo.newImg.width * undo.newImg.bytesPerPixel
                        col2.argb = cast(const *u32, pix32!)[]
                        break
                    }

                    y2 -= 1
                }

                i.boundCols.add({y1, y2, col1, col2})
            }

            infos.add(#move i)
        }

        var params = {capture: capture, infos: infos.buffer, forms: &forms, masks: masks}
        undo.newImg.visitPixels(&params)
        {
            var p     = cast(*#decltype(params), userData!)
            let infos = p.infos!

            // The pixel in capture coordinates, where the selections were drawn.
            var pt = Math.Point{cast(f32, x), cast(f32, p.capture.backImg.height) - y}
            pt.x += p.capture.backImagePos.x
            pt.y += p.capture.backImagePos.y

            for f, idx in p.forms[]
            {
                if not infos[idx].boundRect.contains(pt) or not f.isInside(pt) do
                    continue

                let column = infos[idx].boundCols[x]
                if column.y2 != column.y1
                {
                    // Store pixel mask
                    if p.masks
                    {
                        let masks = p.masks!
                        let xx    = cast(s32, pt.x - infos[idx].boundRect.x)
                        var yy    = cast(s32, pt.y - infos[idx].boundRect.y)
                        let pmask = masks.storage() + idx
                        yy = pmask.height - yy
                        if xx < pmask.width and yy < pmask.height
                        {
                            var pix1 = pmask.pixels.storage() + xx * pmask.bytesPerPixel
                            pix1 += yy * pmask.width * pmask.bytesPerPixel
                            cast(*u32, pix1)[] = 0xFFFFFFFF
                        }
                    }

                    var fVert = (y - column.y1) / cast(f32, column.y2 - column.y1)
                    fVert = Math.clamp(fVert, 0, 1)
                    let col = Color.lerp(column.col1, column.col2, fVert)
                    cast(*u32, pix)[] = col.argb
                }

                break
            }
        }

        capture.pushUndo(undo, serial)
    }

    // Lifts the pixels under each selection into an image form that can be moved, and fills the
    // holes they leave with a smart fill, as one undo step.
    mtd pixSelSmartMove()
    {
        let forms = .getPixSels()
        if forms.isEmpty() do
            return

        let capture = .getCapture()!

        let serial = capture.undoMgr.newSerial()

        var undo = capture.newUndo(.CreateForm)

        let startCount = capture.forms.count - forms.count
        for f in forms
        {
            let br = f.boundRect()

            with let nf = Memory.new'FormImage()
            {
                .kind             = .Capture
                .x                = cast(s32, br.x)
                .y                = cast(s32, br.y)
                .w                = cast(s32, br.width)
                .h                = cast(s32, br.height)
                .borderColor      = Argb.Zero
                .borderSize       = 0
                .paintShadow      = false
                .isReadyToCapture = true
                FormImage.IForm.setup(nf, capture)
                nf.backCapture()
            }

            undo.oldForms.add(nf)
        }

        capture.pushUndo(undo, serial)

        var masks: Array'Image
        .pixSelSmartFill(serial, &masks)

        for f, idx in undo.oldForms
        {
            let nf = assume cast(*FormImage, f)
            nf.backCaptureMask((masks.buffer + idx)!)
        }

        undo = capture.newUndo(.DeleteSelection)
        capture.pushUndo(undo, serial)

        capture.selection.clear()
        for i in startCount until capture.forms.count do
            capture.selection.add(i)
    }
}
