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
            {Clear,     "Clear",      .PixSel, hideDisabled: true},
            {Fill,      "Fill",       .PixSel, hideDisabled: true},
            {SmartFill, "Smart Fill", .PixSel, hideDisabled: true},
            {SmartMove, "Smart Move", .PixSel, hideDisabled: true}])
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main = cast(*MainWnd) notnull cxt.wnd

        switch cxt.id
        {
        case Clear:     main.pixSelClear()
        case Fill:      main.pixSelFill()
        case SmartFill: main.pixSelSmartFill()
        case SmartMove: main.pixSelSmartMove()
        }

        return true
    }
}

impl MainWnd
{
    mtd getPixSels()->Array'IForm
    {
        var result: retval
        let capture = notnull .getCapture()
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
        .pixSelSetPixels((notnull g_Main).pixSelFillCol.argb)
    }

    // Set every pixel inside the pixel selection to the given color
    mtd pixSelSetPixels(argb: u32)
    {
        var forms = .getPixSels()
        if forms.count == 0 do
            return

        let capture = notnull .getCapture()
        let undo    = capture.newUndo(.SetImage)
        undo.newImagePos = capture.backImagePos
        undo.newImg      = capture.backImg

        var boundRects: Array'Math.Rectangle
        for f in forms do
            boundRects.add(f.boundRect())

        var params = {capture: capture, boundRects: boundRects.buffer, forms: &forms, argb: argb}
        undo.newImg.visitPixels(&params)
        {
            var p = cast(*#decltype(params)) notnull userData
            let boundRects = notnull p.boundRects
            for f, [idx] in dref p.forms
            {
                var pt = Math.Point{cast(f32) x, cast(f32) p.capture.backImg.height - y}
                pt.x += p.capture.backImagePos.x
                pt.y += p.capture.backImagePos.y
                if !boundRects[idx].contains(pt) do
                    continue

                if f.isInside(pt)
                {
                    dref cast(*u32) pix = p.argb
                    break
                }
            }
        }

        capture.pushUndo(undo)
    }

    mtd pixSelSmartFill(serial: u64 = 0, masks: #null *Array'Image = null)
    {
        var forms = .getPixSels()
        if forms.count == 0 do
            return

        let capture = notnull .getCapture()
        let undo    = capture.newUndo(.SetImage)
        undo.newImagePos = capture.backImagePos
        undo.newImg      = capture.backImg

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
                var img = Image.create(1 + cast(s32) br.width, 1 + cast(s32) br.height, .RGBA8)
                masks.add(#move img)
            }

            // Compute colors at the start and at the end of the column, to interpolate
            for [x] in undo.newImg.width
            {
                var col1, col2: Color
                var pt = Math.Point{cast(f32) x, 0}
                var y1 = cast(s32) (br.bottom() - capture.backImagePos.y)
                y1 = Math.clamp(y1, 0, undo.newImg.height - 1)
                y1 = undo.newImg.height - y1
                for [i] in undo.newImg.height
                {
                    pt.y = cast(f32) (capture.backImg.height - y1) + capture.backImagePos.y
                    if br.contains(pt) and f.isInside(pt)
                    {
                        var pix32 = undo.newImg.pixels.buffer + x * undo.newImg.bpp8
                        pix32     += y1 * undo.newImg.width * undo.newImg.bpp8
                        col1.argb = dref cast(*u32) notnull pix32
                        break
                    }

                    y1 += 1
                }

                var y2 = cast(s32) (br.y - capture.backImagePos.y)
                y2 = undo.newImg.height - y2
                y2 = Math.clamp(y2, 0, undo.newImg.height - 1)
                for [i] in undo.newImg.height
                {
                    pt.y = cast(f32) (capture.backImg.height - y2) + capture.backImagePos.y
                    if br.contains(pt) and f.isInside(pt)
                    {
                        var pix32 = undo.newImg.pixels.buffer + x * undo.newImg.bpp8
                        pix32     += y2 * undo.newImg.width * undo.newImg.bpp8
                        col2.argb = dref cast(*u32) notnull pix32
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
            var p = cast(*#decltype(params)) notnull userData
            let infos = notnull p.infos
            for f, [idx] in dref p.forms
            {
                var pt = Math.Point{cast(f32) x, cast(f32) p.capture.backImg.height - y}
                pt.x += p.capture.backImagePos.x
                pt.y += p.capture.backImagePos.y
                if !infos[idx].boundRect.contains(pt) do
                    continue

                if f.isInside(pt)
                {
                    let p1   = infos[idx].boundCols[x]
                    let col1 = p1.col1
                    let col2 = p1.col2
                    let y1   = p1.y1
                    let y2   = p1.y2
                    if y2 != y1
                    {
                        // Store pixel mask
                        if p.masks
                        {
                            let masks = notnull p.masks
                            let xx    = cast(s32) (pt.x - infos[idx].boundRect.x)
                            var yy    = cast(s32) (pt.y - infos[idx].boundRect.y)
                            let pmask = (notnull masks.buffer) + idx
                            yy = pmask.height - yy
                            if xx < pmask.width and yy < pmask.height
                            {
                                var pix1 = (notnull pmask.pixels.buffer) + xx * pmask.bpp8
                                pix1                         += yy * pmask.width * pmask.bpp8
                                dref cast(*u32) notnull pix1 = 0xFFFFFFFF
                            }
                        }

                        var fVert = (y - y1) / cast(f32) (y2 - y1)
                        fVert = Math.clamp(fVert, 0, 1)
                        let col = Color.getBlend(col1, col2, fVert)
                        dref cast(*u32) pix = col.argb
                    }

                    break
                }
            }
        }

        capture.pushUndo(undo, serial)
    }

    mtd pixSelSmartMove()
    {
        let forms = .getPixSels()
        if forms.count == 0 do
            return

        let capture = notnull .getCapture()

        let serial = capture.undoMgr.newSerial()

        var undo = capture.newUndo(.CreateForm)

        let startCount = capture.forms.count - forms.count
        for f in forms
        {
            let br = f.boundRect()

            with let nf = Memory.new'FormImage()
            {
                .kind             = .Capture
                .x                = cast(s32) br.x
                .y                = cast(s32) br.y
                .w                = cast(s32) br.width
                .h                = cast(s32) br.height
                .borderColor      = Argb.Zero
                .borderSize       = 0
                .paintShadow      = false
                .isReadyToCapture = true
                FormImage.IForm.setup(nf, capture)
                nf.backCapture()
            }

            undo.oldForms.add(cast(IForm) nf)
        }

        capture.pushUndo(undo, serial)

        var masks: Array'Image
        .pixSelSmartFill(serial, &masks)

        for f, [idx] in undo.oldForms
        {
            let nf = cast(*FormImage) f
            nf.backCaptureMask(notnull (masks.buffer + idx))
        }

        undo = capture.newUndo(.DeleteSelection)
        capture.pushUndo(undo, serial)

        capture.selection.clear()
        for [i] in startCount until capture.forms.count do
            capture.selection.add(i)
    }
}
