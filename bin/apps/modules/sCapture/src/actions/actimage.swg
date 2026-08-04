struct ActionImage {}

var g_KeepRatio:       bool = true
var g_ResizeMode:      u64  = 5
var g_Width, g_Height: s32

impl ActionImage
{
    newCmdId("TrimCapture")
    newCmdId("ResizeImage")
    newCmdId("ExpandImage")
    newCmdId("ExpandCapture")
    newCmdId("RestoreOrg")
    newCmdId("FlipImage")
    newCmdId("MirrorImage")
    newCmdId("RotateImageRight")
    newCmdId("RotateImageLeft")
}

impl IActionUI for ActionImage
{
    acceptOwnCmdIds()

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        if updateFromTable(cxt,
                           evt,
                           [
                               {ResizeImage,      "Resize Image...",    .Capture},
                               {ExpandImage,      "Expand Image...",    .Capture},
                               {ExpandCapture,    "Expand Capture...",  .Capture},
                               {TrimCapture,      "Trim Capture",       .Capture},
                               {FlipImage,        "Flip Image",         .Capture},
                               {MirrorImage,      "Mirror Image",       .Capture},
                               {RotateImageRight, "Rotate Image Right", .Capture},
                               {RotateImageLeft,  "Rotate Image Left",  .Capture}])
        {
            return true
        }

        let main    = cast(*MainWnd) cxt.wnd!
        let capture = main.getCapture()

        switch cxt.id
        {
        case .RestoreOrg:
            evt.updatedFields |= .Name | .Disabled
            evt.name          = "Restore to Original"
            evt.disabled      = !capture or !capture.backImgOriginal.isValid()
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main    = cast(*MainWnd) cxt.wnd!
        let capture = main.getCapture()!

        // The backImgOriginal snapshot (which enables "Restore to Original") is taken lazily
        // at the point backImg is genuinely mutated (see doProcessImage/trimCapture), not here:
        // several commands can early-return on dialog Cancel or never touch backImg at all.

        switch cxt.id
        {
        case .ResizeImage:
            main.resizeImage()

        case .ExpandImage:
            main.expandImage()

        case .FlipImage:
            main.doProcessImage(FlipImage)

        case .MirrorImage:
            main.doProcessImage(MirrorImage)

        case .RotateImageRight:
            main.doProcessImage(RotateImageRight)

        case .RotateImageLeft:
            main.doProcessImage(RotateImageLeft)

        case .ExpandCapture:
            main.expandCapture()

        case .TrimCapture:
            main.trimCapture()

        case .RestoreOrg:
            let undo = capture.newUndo(.RestoreOrg)
            capture.pushUndo(undo)
            main.invalidate()
        }

        return true
    }
}

impl MainWnd
{
    mtd doProcessImage(cmdId: WndId, l, t, r, b, w, h: s32 = 0)
    {
        let capture = .getCapture()!

        // A real backImg mutation is about to be committed: snapshot the first original now.
        if !capture.backImgOriginal.isValid() do
            capture.backImgOriginal = capture.backImg

        let serial = capture.undoMgr.newSerial()

        var img  = capture.backImg
        let oldW = img.width
        let oldH = img.height

        switch cmdId
        {
        case ActionImage.ResizeImage:      img.resize(w, h, .Bilinear)
        case ActionImage.ExpandImage:      img.expand(l, t, r, b)
        case ActionImage.FlipImage:        img.flip()
        case ActionImage.MirrorImage:      img.mirror()
        case ActionImage.RotateImageRight: img.rotate(.Clockwise90)
        case ActionImage.RotateImageLeft:  img.rotate(.Clockwise270)
        }

        let undo1 = capture.newUndo(.SetImage)
        undo1.newImg = img
        capture.pushUndo(undo1, serial)

        switch cmdId
        {
        case ActionImage.ResizeImage:
            let undo2 = capture.newUndo(.MoveCapture)
            undo2.newImg   = img
            undo2.newSizeX = w - capture.width
            undo2.newSizeY = h - capture.height
            capture.pushUndo(undo2, serial)

        case ActionImage.RotateImageRight, ActionImage.RotateImageLeft:
            let undo2 = capture.newUndo(.MoveCapture)
            undo2.newImg   = img
            undo2.newSizeX = img.width - oldW
            undo2.newSizeY = img.height - oldH
            capture.pushUndo(undo2, serial)
        }
    }

    mtd resizeImage()
    {
        let capture = .getCapture()!
        let ratio   = cast(f32) capture.width / capture.height

        let dlg = Dialog.create(.surface!, 350, 265, title: "Resize Image")
        dlg.addButton("Resize", Dialog.BtnOk, true)
        dlg.addButton("Cancel", Dialog.BtnCancel)
        let edit0 = EditCtrl.create(dlg, "Width", Format.toString("%", capture.width), {80, 15}, flags: .RightAligned)
        let edit1 = EditCtrl.create(dlg, "Height", Format.toString("%", capture.height), {80, 50}, flags: .RightAligned)
        edit0.edit.setUnsignedIntegerRange(cast() Capture.MinSize, cast() Capture.MaxSize)
        edit1.edit.setUnsignedIntegerRange(cast() Capture.MinSize, cast() Capture.MaxSize)
        let btnRatio = CheckButton.create(dlg, "Keep Ratio", {120, 85})
        btnRatio.setState(g_KeepRatio ? .Checked : .Unchecked)

        edit0.edit.sigTextChanged += func|ratio, btnRatio, edit1|(edt)
        {
            if btnRatio.isChecked()
            {
                let w = catch StrConv.toS32(edt.text())
                let h = Math.max(1, cast(s32) (w / ratio))
                edit1.edit.setText(Format.toString("%", h), notify: false)
            }
        }
        edit1.edit.sigTextChanged += func|ratio, btnRatio, edit0|(edt)
        {
            if btnRatio.isChecked()
            {
                let h = catch StrConv.toS32(edt.text())
                let w = Math.max(1, cast(s32) (h * ratio))
                edit0.edit.setText(Format.toString("%", w), notify: false)
            }
        }

        let res = dlg.doModal()
        g_KeepRatio = btnRatio.isChecked()
        if res != Dialog.BtnOk do
            return

        let w = catch StrConv.toS32(edit0.edit.text())
        if w < Capture.MinSize or w > Capture.MaxSize do
            return
        let h = catch StrConv.toS32(edit1.edit.text())
        if h < Capture.MinSize or h > Capture.MaxSize do
            return
        if w == capture.width and h == capture.height do
            return

        .doProcessImage(ActionImage.ResizeImage, w: w, h: h)
    }

    func createBtnGrid(dlg: *Wnd)
    {
        func createBtn(dlg: *Wnd, pos: Math.Rectangle, id: u64)
        {
            let btn = CheckButton.create(dlg, " ", pos)
            btn.setState(g_ResizeMode == id ? .Indeterminate : .Unchecked)
            btn.userData   = cast(*void) id
            btn.sigChanged += func(btn)
            {
                for c in btn.parent!.children
                {
                    if c.userData
                    {
                        let btnc = cast(*CheckButton) c
                        btnc.setState(c != btn ? .Unchecked : .Indeterminate)
                        btnc.invalidate()
                    }
                }
            }
        }

        const X = 175
        const Y = 15
        const S = 20
        const O = 4
        createBtn(dlg, {X, Y, S, S}, 1)
        createBtn(dlg, {X + S + O, Y, S, S}, 2)
        createBtn(dlg, {X + S + O + S + O, Y, S, S}, 3)
        createBtn(dlg, {X, Y + S + O, S, S}, 4)
        createBtn(dlg, {X + S + O, Y + S + O, S, S}, 5)
        createBtn(dlg, {X + S + O + S + O, Y + S + O, S, S}, 6)
        createBtn(dlg, {X, Y + S + O + S + O, S, S}, 7)
        createBtn(dlg, {X + S + O, Y + S + O + S + O, S, S}, 8)
        createBtn(dlg, {X + S + O + S + O, Y + S + O + S + O, S, S}, 9)
    }

    mtd createExpandDialog(title: String, w, h: s32)->WndId
    {
        let dlg = Dialog.create(.surface!, 350, 265, title: title)
        dlg.addButton("Resize", Dialog.BtnOk, true)
        dlg.addButton("Cancel", Dialog.BtnCancel)

        let ratio = cast(f32) w / h

        g_Width  = w
        g_Height = h
        let edit0 = EditCtrl.create(dlg, "Width", Format.toString("%", w), {30, 15}, flags: .RightAligned)
        let edit1 = EditCtrl.create(dlg, "Height", Format.toString("%", h), {30, 50}, flags: .RightAligned)
        edit0.edit.setUnsignedIntegerRange(cast() Capture.MinSize, cast() Capture.MaxSize)
        edit1.edit.setUnsignedIntegerRange(cast() Capture.MinSize, cast() Capture.MaxSize)

        edit0.edit.sigTextChanged += func|ratio, edit1|(edt)
        {
            g_Width = catch StrConv.toS32(edt.text())
            if g_KeepRatio
            {
                g_Height = Math.max(1, cast(s32) (g_Width / ratio))
                edit1.edit.setText(Format.toString("%", g_Height), notify: false)
            }
        }

        edit1.edit.sigTextChanged += func|ratio, edit0|(edt)
        {
            g_Height = catch StrConv.toS32(edt.text())
            if g_KeepRatio
            {
                g_Width = Math.max(1, cast(s32) (g_Height * ratio))
                edit0.edit.setText(Format.toString("%", g_Width), notify: false)
            }
        }

        let btnRatio = CheckButton.create(dlg, "Keep Ratio", {70, 85})
        btnRatio.setState(g_KeepRatio ? .Checked : .Unchecked)
        btnRatio.sigChanged += func||(btn) { g_KeepRatio = btn.isChecked() }

        dlg.createBtnGrid()

        let res = dlg.doModal()

        for c in dlg.children
        {
            if c.userData
            {
                let btnc = cast(*CheckButton) c
                if btnc.state != .Unchecked
                {
                    g_ResizeMode = cast(u64) btnc.userData
                    break
                }
            }
        }

        return res
    }

    mtd expandImage()
    {
        let capture = .getCapture()!
        let res     = .createExpandDialog("Expand Image", capture.backImg.width, capture.backImg.height)
        if res != Dialog.BtnOk do
            return

        let w = g_Width
        if w < Capture.MinSize or w > Capture.MaxSize do
            return
        let h = g_Height
        if h < Capture.MinSize or h > Capture.MaxSize do
            return
        if w == capture.backImg.width and h == capture.backImg.height do
            return

        var l, t, r, b: s32 = 0
        let cw              = w - cast(s32) capture.backImg.width
        let ch              = h - cast(s32) capture.backImg.height

        switch g_ResizeMode
        {
        case 1, 4, 7:
            r += cw

        case 2, 5, 8:
            l += cw / 2
            r += cw / 2

        case 3, 6, 9:
            l += cw
        }

        switch g_ResizeMode
        {
        case 1, 2, 3:
            b += ch

        case 4, 5, 6:
            t += ch / 2
            b += ch / 2

        case 7, 8, 9:
            t += ch
        }

        .doProcessImage(ActionImage.ExpandImage, l, t, r, b)
    }

    mtd expandCapture()
    {
        let capture = .getCapture()!
        let res     = .createExpandDialog("Expand Capture", capture.width, capture.height)
        if res != Dialog.BtnOk do
            return

        let w = g_Width
        if w < Capture.MinSize or w > Capture.MaxSize do
            return
        let h = g_Height
        if h < Capture.MinSize or h > Capture.MaxSize do
            return
        if w == capture.width and h == capture.height do
            return

        let nw = w - capture.width
        let nh = h - capture.height

        let undo = capture.newUndo(.MoveCapture)
        undo.newSizeX = nw
        undo.newSizeY = nh

        switch g_ResizeMode
        {
        case 2, 5, 8: undo.newPosX = nw / 2
        case 3, 6, 9: undo.newPosX = nw
        }

        switch g_ResizeMode
        {
        case 4, 5, 6: undo.newPosY = nh / 2
        case 7, 8, 9: undo.newPosY = nh
        }

        capture.pushUndo(undo)
    }

    mtd trimCapture()
    {
        let capture = .getCapture()!
        capture.selection.clear()

        var minX = Swag.F32.Max
        var minY = Swag.F32.Max
        var maxX = 0'f32
        var maxY = 0'f32

        for f, [idx] in capture.forms
        {
            let r = f.boundRect()
            if r.x > 0 do
                minX = Math.min(minX, r.x)
            if r.y > 0 do
                minY = Math.min(minY, r.y)
            if r.right() < capture.width do
                maxX = Math.max(maxX, r.right())
            if r.bottom() < capture.height do
                maxY = Math.max(maxY, r.bottom())

            // Select forms outside capture
            if r.right() < 0 or
               r.bottom() < 0 or
               r.x >= capture.width or
               r.y >= capture.height
            {
                capture.selection.add(idx)
            }
        }

        #scope(Left)
            for [x] in capture.backImg.width
        {
            if x + capture.backImagePos.x < 0 do
                continue
            for [y] in capture.backImg.height
            {
                let col = capture.backImg.pixelColor(x, y)
                if col.a
                {
                    minX = Math.min(minX, x + capture.backImagePos.x)
                    break to Left
                }
            }
        }

        #scope(Right)
            for #reverse [x] in capture.backImg.width
        {
            if x + capture.backImagePos.x >= capture.width do
                continue
            for [y] in capture.backImg.height
            {
                let col = capture.backImg.pixelColor(x, y)
                if col.a
                {
                    maxX = Math.max(maxX, x + capture.backImagePos.x + 1)
                    break to Right
                }
            }
        }

        #scope(Up)
            for [y] in capture.backImg.height
        {
            if y + capture.backImagePos.y < 0 do
                continue
            for [x] in capture.backImg.width
            {
                let col = capture.backImg.pixelColor(x, y)
                if col.a
                {
                    minY = Math.min(minY, y + capture.backImagePos.y)
                    break to Up
                }
            }
        }

        #scope(Down)
            for #reverse [y] in capture.backImg.height
        {
            if y + capture.backImagePos.y >= capture.height do
                continue
            for [x] in capture.backImg.width
            {
                let col = capture.backImg.pixelColor(x, y)
                if col.a
                {
                    maxY = Math.max(maxY, y + capture.backImagePos.y + 1)
                    break to Down
                }
            }
        }

        let serial = capture.undoMgr.newSerial()

        // Resize capture.
        // With no opaque pixel and no in-bounds form, none of the scan loops fire and the
        // accumulators stay at their init sentinels (minX/minY = F32.Max, maxX/maxY = 0), so
        // minX > maxX. Require a valid content box first, otherwise the offsets below would be
        // computed from F32.Max and produce a corrupt MoveCapture undo.
        if minX <= maxX and minY <= maxY and (minX or minY or maxX != capture.width or maxY != capture.height)
        {
            with let undo = capture.newUndo(.MoveCapture)
            {
                .newPosX  -= cast(s32) minX
                .newSizeX -= cast(s32) minX
                .newPosY  -= cast(s32) minY
                .newSizeY -= cast(s32) minY
                .newSizeX -= cast(s32) (capture.width - maxX)
                .newSizeY -= cast(s32) (capture.height - maxY)
            }

            capture.pushUndo(undo, serial)
        }

        // Remove forms outside the cavenas
        if capture.selection.count
        {
            let undo = capture.newUndo(.DeleteSelection)
            capture.pushUndo(undo, serial)
        }

        // Crop image
        if capture.backImagePos.x < 0 or
           capture.backImagePos.y < 0 or
           capture.backImagePos.x + capture.backImg.width > capture.width or
           capture.backImagePos.y + capture.backImg.height > capture.height
        {
            var cropRect = Math.Rectangle{0, 0, capture.backImg.width, capture.backImg.height}

            let dx = Math.max(0, -capture.backImagePos.x)
            let dy = Math.max(0, -capture.backImagePos.y)
            let dw = Math.max(0, (capture.backImagePos.x + capture.backImg.width) - capture.width)
            let dh = Math.max(0, (capture.backImagePos.y + capture.backImg.height) - capture.height)
            cropRect.moveLeft(dx)
            cropRect.moveTop(dy)
            cropRect.width  -= dw
            cropRect.height -= dh

            // Cropping is a real backImg mutation: snapshot the first original before it.
            if !capture.backImgOriginal.isValid() do
                capture.backImgOriginal = capture.backImg

            let undo = capture.newUndo(.SetImage)
            undo.newImg = capture.backImg.cropped(cropRect)
            capture.pushUndo(undo, serial)
        }

        capture.selectionHasChanged()
    }
}
