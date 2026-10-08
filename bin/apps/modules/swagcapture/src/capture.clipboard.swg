impl Capture
{
    mtd copyAll()
    {
        Cursor.activateWait()
        Clipboard.addImage(.toImage())
    }

    // Puts the selected forms on the clipboard as Swag Capture forms; the first plain picture
    // among them also goes as a bitmap for other applications.
    mtd copy()
    {
        var payload: CaptureClipboardForms

        var imgDone = false
        for s in .selection
        {
            let itf = .forms[s]

            // The first plain picture also travels as a bitmap, for the applications that
            // cannot read forms.
            if not imgDone and Swag.kindOf(itf) == FormImage
            {
                let fimg = assume cast(*FormImage, itf)
                if fimg.kind == .Image and fimg.image.isValid()
                {
                    imgDone = true
                    Clipboard.addImage(fimg.image)
                }
            }

            payload.add(itf)
        }

        Clipboard.addTypedValue(&payload, #typeof(payload))
    }

    mtd cut()
    {
        .copy()
        .pushUndo(.newUndo(.DeleteSelection))
    }

    mtd pasteImageInside()
    {
        let image = Clipboard.getImage()
        if not image.isValid() do
            return

        let undo = .newUndo(.SetImageInside)
        undo.newImg = image
        .pushUndo(undo)
        .selectionHasChanged()
    }

    mtd clearImageInside()
    {
        .pushUndo(.newUndo(.SetImageInside))
        .selectionHasChanged()
    }

    // Pastes the clipboard as one undoable step: Swag Capture forms when it holds some, otherwise
    // an image as a new image form. The pasted forms are centered on the mouse and selected.
    mtd paste()
    {
        var result:  Array'IForm
        var payload: CaptureClipboardForms
        if Clipboard.getTypedValue(&payload, #typeof(payload))
        {
            result = payload.toForms(me)
        }
        else
        {
            let image = Clipboard.getImage()
            if image.isValid()
            {
                with let formImg = Memory.new'FormImage()
                {
                    .w             = image.width
                    .h             = image.height
                    .image         = image
                    .borderColor.a = 0
                    .backColor.a   = 0
                }

                result.add(formImg)
            }
            else
            {
                return
            }
        }

        // Pasted copies keep their internal grouping but must not re-join the originals
        // (or collide with groups from another capture file), so mint fresh ids.
        .remapGroups(result)

        let undo = .newUndo(.CreateForm)
        .selection.clear()

        var boundRect: Math.Rectangle

        for itf, idx in result
        {
            itf.setup(me)
            let bound = itf.boundRect()
            if idx == 0 do
                boundRect = bound
            else do
                boundRect.combine(bound)
        }

        undo.oldForms = result

        // Center the pasted forms on the mouse.
        let editView = .editView!
        var pt       = editView.app().mouse.position()
        pt   = editView.screenToSurface(pt)
        pt   = editView.surfaceToLocal(pt)
        pt   += editView.scrollPos
        pt.x -= .paintRect.x
        pt.y -= .paintRect.y
        let zoom = .paintRect.width / .width
        pt.x /= zoom
        pt.y /= zoom

        for itf in undo.oldForms
        {
            let dx = -boundRect.x + pt.x - (boundRect.width * 0.5)
            let dy = -boundRect.y + pt.y - (boundRect.height * 0.5)
            itf.moveForm(cast(dx), cast(dy))
        }

        let countBefore = .forms.count
        .pushUndo(undo)

        // Select added forms
        .selection.clear()
        for i in undo.oldForms.count do
            .selection.add(countBefore + i)

        .selectionHasChanged()
    }
}
