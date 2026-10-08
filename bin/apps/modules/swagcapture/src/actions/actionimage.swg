// The commands that change the capture image itself: trim, resize, expand, flip, rotate, and
// restore the original.
struct ActionImage {}

// The settings the resize and expand dialogs remember between uses. `g_ResizeMode` is the anchor
// an expansion grows around, a cell of a 3 × 3 grid numbered 1 to 9 from the top-left, row by row.
var g_KeepRatio:       bool = true
var g_ResizeMode:      u64  = 5
var g_Width, g_Height: s32

// How a size change of `delta` splits between the near and the far side when the anchor sits in
// `cell` (0 near, 1 center, 2 far) along that axis.
func anchorSplit(delta: s32, cell: u64)->{before: s32, after: s32}
{
    switch cell
    {
    case 0:  return {0, delta}
    case 1:  return {delta / 2, delta / 2}
    default: return {delta, 0}
    }
}

// Whether a capture can take the size `width` by `height`, and it differs from the current one.
private func acceptsNewSize(width, height, currentWidth, currentHeight: s32)->bool
{
    if width < Capture.MinSize or width > Capture.MaxSize or height < Capture.MinSize or height > Capture.MaxSize do
        return false
    return width != currentWidth or height != currentHeight
}

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
        if updateFromTable(cxt, evt, [
            {ResizeImage,      appStrings().act_ResizeImage,      .Capture, hideDisabled: false},
            {ExpandImage,      appStrings().act_ExpandImage,      .Capture, hideDisabled: false},
            {ExpandCapture,    appStrings().act_ExpandCapture,    .Capture, hideDisabled: false},
            {TrimCapture,      appStrings().act_TrimCapture,      .Capture, hideDisabled: false},
            {FlipImage,        appStrings().act_FlipImage,        .Capture, hideDisabled: false},
            {MirrorImage,      appStrings().act_MirrorImage,      .Capture, hideDisabled: false},
            {RotateImageRight, appStrings().act_RotateImageRight, .Capture, hideDisabled: false},
            {RotateImageLeft,  appStrings().act_RotateImageLeft,  .Capture, hideDisabled: false}])
        {
            return true
        }

        let main    = mainWndOf(cxt)
        let capture = main.getCapture()

        switch cxt.id
        {
        case .RestoreOrg:
            evt.updatedFields |= .Name | .Disabled
            evt.name          = appStrings().act_RestoreOriginal
            evt.disabled      = not capture or not capture.backImgOriginal.isValid()
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main    = mainWndOf(cxt)
        let capture = main.getCapture()!

        // The backImgOriginal snapshot (which enables appStrings().act_RestoreOriginal) is taken lazily
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
    // Applies the image command `cmdId` to the background image, and resizes or turns
    // the canvas with it, as one undo step. `l, t, r, b` are the margins an expansion
    // adds; `w, h` the size of a resize.
    mtd doProcessImage(cmdId: WndId, l, t, r, b, w, h: s32 = 0)
    {
        let capture = .getCapture()!

        // A real backImg mutation is about to be committed: snapshot the first original now.
        if not capture.backImgOriginal.isValid() do
            capture.backImgOriginal = capture.backImg

        let serial = capture.undoMgr.newSerial()

        var image = capture.backImg
        let oldW  = image.width
        let oldH  = image.height

        switch cmdId
        {
        case ActionImage.ResizeImage:      image.resize(w, h, .Bilinear)
        case ActionImage.ExpandImage:      image.expand(l, t, r, b)
        case ActionImage.FlipImage:        image.flip()
        case ActionImage.MirrorImage:      image.mirror()
        case ActionImage.RotateImageRight: image.rotate(.Clockwise90)
        case ActionImage.RotateImageLeft:  image.rotate(.Clockwise270)
        }

        let undo1 = capture.newUndo(.SetImage)
        undo1.newImg = image
        capture.pushUndo(undo1, serial)

        switch cmdId
        {
        case ActionImage.ResizeImage:
            with let undo2 = capture.newUndo(.MoveCapture)
            {
                .newImg   = image
                .newSizeX = w - capture.width
                .newSizeY = h - capture.height
            }

            capture.pushUndo(undo2, serial)

        case ActionImage.RotateImageRight, ActionImage.RotateImageLeft:
            with let undo2 = capture.newUndo(.MoveCapture)
            {
                .newImg   = image
                .newSizeX = image.width - oldW
                .newSizeY = image.height - oldH
            }

            capture.pushUndo(undo2, serial)
        }
    }

    // Asks for a new size and scales the background image to it, keeping the ratio when asked.
    mtd resizeImage()
    {
        let capture = .getCapture()!
        let ratio   = cast(f32, capture.width) / capture.height

        with let dialog = Dialog.create(.surface!, 350, 265, title: appStrings().dlg_TitleResizeImage)
        {
            .addButton(appStrings().dlg_BtnResize, Dialog.BtnOk, true)
            .addButton(Gui.strings().dlg_Cancel, Dialog.BtnCancel)
        }

        let edit0 = EditCtrl.create(dialog, appStrings().ui_Width, Format.toString("%", capture.width), {80, 15}, flags: .RightAligned)
        let edit1 = EditCtrl.create(dialog, appStrings().ui_Height, Format.toString("%", capture.height), {80, 50}, flags: .RightAligned)
        edit0.edit.setUnsignedIntegerRange(cast(Capture.MinSize), cast(Capture.MaxSize))
        edit1.edit.setUnsignedIntegerRange(cast(Capture.MinSize), cast(Capture.MaxSize))
        let btnRatio = CheckButton.create(dialog, appStrings().ui_KeepRatio, {120, 85})
        btnRatio.setState(g_KeepRatio ? .Checked : .Unchecked)

        edit0.edit.sigTextChanged += func|ratio, btnRatio, edit1|(edt)
        {
            if btnRatio.isChecked()
            {
                let w = catch StrConv.toS32(edt.text())
                let h = Math.max(1, cast(s32, w / ratio))
                edit1.edit.setText(Format.toString("%", h), notify: false)
            }
        }

        edit1.edit.sigTextChanged += func|ratio, btnRatio, edit0|(edt)
        {
            if btnRatio.isChecked()
            {
                let h = catch StrConv.toS32(edt.text())
                let w = Math.max(1, cast(s32, h * ratio))
                edit0.edit.setText(Format.toString("%", w), notify: false)
            }
        }

        let result = dialog.doModal()
        g_KeepRatio = btnRatio.isChecked()
        if result != Dialog.BtnOk do
            return

        let w = catch StrConv.toS32(edit0.edit.text())
        let h = catch StrConv.toS32(edit1.edit.text())
        if acceptsNewSize(w, h, capture.width, capture.height) do
            .doProcessImage(ActionImage.ResizeImage, w: w, h: h)
    }

    // Adds the 3 × 3 grid of anchor buttons to an expand dialog; exactly one is checked, the anchor
    // in `g_ResizeMode`.
    func createBtnGrid(dlg: *Wnd)
    {
        func createBtn(dlg: *Wnd, pos: Math.Rectangle, id: u64)
        {
            let button = CheckButton.create(dlg, " ", pos)
            button.setState(g_ResizeMode == id ? .Indeterminate : .Unchecked)
            button.userData   = cast(*void, id)
            button.sigChanged += func(button)
            {
                for c in button.parent!.children
                {
                    if c.userData
                    {
                        with let btnc = assume cast(*CheckButton, c)
                        {
                            .setState(c != button ? .Unchecked : .Indeterminate)
                            .invalidate()
                        }
                    }
                }
            }
        }

        const X = 175
        const Y = 15
        const S = 20
        const O = 4
        for cell in 9'u64
        {
            let x = X + cast(f32, cell % 3) * (S + O)
            let y = Y + cast(f32, cell / 3) * (S + O)
            createBtn(dlg, {x, y, S, S}, cell + 1)
        }
    }

    // Shows the expand dialog for a `w` by `h` image, and leaves the size and the anchor the reader
    // picked in `g_Width`, `g_Height`, and `g_ResizeMode`. Returns the button that closed it.
    mtd createExpandDialog(title: String, w, h: s32)->WndId
    {
        with let dialog = Dialog.create(.surface!, 350, 265, title: title)
        {
            .addButton(appStrings().dlg_BtnResize, Dialog.BtnOk, true)
            .addButton(Gui.strings().dlg_Cancel, Dialog.BtnCancel)
        }

        let ratio = cast(f32, w) / h

        g_Width  = w
        g_Height = h
        let edit0 = EditCtrl.create(dialog, appStrings().ui_Width, Format.toString("%", w), {30, 15}, flags: .RightAligned)
        let edit1 = EditCtrl.create(dialog, appStrings().ui_Height, Format.toString("%", h), {30, 50}, flags: .RightAligned)
        edit0.edit.setUnsignedIntegerRange(cast(Capture.MinSize), cast(Capture.MaxSize))
        edit1.edit.setUnsignedIntegerRange(cast(Capture.MinSize), cast(Capture.MaxSize))

        edit0.edit.sigTextChanged += func|ratio, edit1|(edt)
        {
            g_Width = catch StrConv.toS32(edt.text())
            if g_KeepRatio
            {
                g_Height = Math.max(1, cast(s32, g_Width / ratio))
                edit1.edit.setText(Format.toString("%", g_Height), notify: false)
            }
        }

        edit1.edit.sigTextChanged += func|ratio, edit0|(edt)
        {
            g_Height = catch StrConv.toS32(edt.text())
            if g_KeepRatio
            {
                g_Width = Math.max(1, cast(s32, g_Height * ratio))
                edit0.edit.setText(Format.toString("%", g_Width), notify: false)
            }
        }

        with let btnRatio = CheckButton.create(dialog, appStrings().ui_KeepRatio, {70, 85})
        {
            .setState(g_KeepRatio ? .Checked : .Unchecked)
            .sigChanged += func||(btn) { g_KeepRatio = btn.isChecked() }
        }

        dialog.createBtnGrid()

        let result = dialog.doModal()

        for c in dialog.children
        {
            if c.userData
            {
                let btnc = assume cast(*CheckButton, c)
                if btnc.state != .Unchecked
                {
                    g_ResizeMode = cast(u64, btnc.userData)
                    break
                }
            }
        }

        return result
    }

    mtd expandImage()
    {
        let capture = .getCapture()!
        let result  = .createExpandDialog(appStrings().dlg_TitleExpandImage, capture.backImg.width, capture.backImg.height)
        if result != Dialog.BtnOk do
            return

        let image = &capture.backImg
        if not acceptsNewSize(g_Width, g_Height, image.width, image.height) do
            return

        let horz = anchorSplit(g_Width - image.width, (g_ResizeMode - 1) % 3)
        let vert = anchorSplit(g_Height - image.height, (g_ResizeMode - 1) / 3)
        .doProcessImage(ActionImage.ExpandImage, horz.before, vert.before, horz.after, vert.after)
    }

    // Asks for a larger canvas and grows it around the chosen anchor, as one undo step.
    mtd expandCapture()
    {
        let capture = .getCapture()!
        let result  = .createExpandDialog(appStrings().dlg_TitleExpandCapture, capture.width, capture.height)
        if result != Dialog.BtnOk do
            return

        if not acceptsNewSize(g_Width, g_Height, capture.width, capture.height) do
            return

        let nw = g_Width - capture.width
        let nh = g_Height - capture.height

        with let undo = capture.newUndo(.MoveCapture)
        {
            .newSizeX = nw
            .newSizeY = nh
            .newPosX  = anchorSplit(nw, (g_ResizeMode - 1) % 3).before
            .newPosY  = anchorSplit(nh, (g_ResizeMode - 1) / 3).before
        }

        capture.pushUndo(undo)
    }

    // Whether column `x`, or row `y`, of `img` holds a pixel that is not fully transparent.
    func columnOpaque(img: const *Image, x: s32)->bool
    {
        for y in img.height where img.pixelColor(x, y).a do
            return true
        return false
    }

    func rowOpaque(img: const *Image, y: s32)->bool
    {
        for x in img.width where img.pixelColor(x, y).a do
            return true
        return false
    }

    // Shrinks the canvas to what it shows, the opaque pixels of the image and the forms, and drops
    // the forms left outside, as one undo step.
    mtd trimCapture()
    {
        let capture = .getCapture()!
        capture.selection.clear()

        var minX = Swag.F32.Max
        var minY = Swag.F32.Max
        var maxX = 0'f32
        var maxY = 0'f32

        for f, idx in capture.forms
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

        // The opaque pixels of the image inside the canvas widen the box too.
        let img = &capture.backImg
        let pos = capture.backImagePos
        for x in img.width where x + pos.x >= 0 and columnOpaque(img, x)
        {
            minX = Math.min(minX, x + pos.x)
            break
        }

        for x in img.width.reversed() where x + pos.x < capture.width and columnOpaque(img, x)
        {
            maxX = Math.max(maxX, x + pos.x + 1)
            break
        }

        for y in img.height where y + pos.y >= 0 and rowOpaque(img, y)
        {
            minY = Math.min(minY, y + pos.y)
            break
        }

        for y in img.height.reversed() where y + pos.y < capture.height and rowOpaque(img, y)
        {
            maxY = Math.max(maxY, y + pos.y + 1)
            break
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
                .newPosX  -= cast(s32, minX)
                .newSizeX -= cast(s32, minX)
                .newPosY  -= cast(s32, minY)
                .newSizeY -= cast(s32, minY)
                .newSizeX -= cast(s32, capture.width - maxX)
                .newSizeY -= cast(s32, capture.height - maxY)
            }

            capture.pushUndo(undo, serial)
        }

        // Remove forms outside the canvas
        if capture.selection.count do
            capture.pushUndo(capture.newUndo(.DeleteSelection), serial)

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
            if not capture.backImgOriginal.isValid() do
                capture.backImgOriginal = capture.backImg

            let undo = capture.newUndo(.SetImage)
            undo.newImg = capture.backImg.cropped(cropRect)
            capture.pushUndo(undo, serial)
        }

        capture.selectionHasChanged()
    }
}
