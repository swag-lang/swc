// Distance, in capture pixels, between a duplicated form and its original.
const DuplicateOffset = 16's32

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
            if itf is FormImage as fimg where not imgDone and fimg.kind == .Image and fimg.image.isValid()
            {
                imgDone = true
                Clipboard.addImage(fimg.image)
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

        // Center the pasted forms on the mouse.
        let editView = unwrap .editView
        var pt       = editView.app().mouse.position()
        pt   = editView.screenToSurface(pt)
        pt   = editView.surfaceToLocal(pt)
        pt   += editView.scrollPos
        pt.x -= .paintRect.x
        pt.y -= .paintRect.y
        let zoom = .paintRect.width / .width
        pt.x /= zoom
        pt.y /= zoom

        for itf in result
        {
            let dx = -boundRect.x + pt.x - (boundRect.width * 0.5)
            let dy = -boundRect.y + pt.y - (boundRect.height * 0.5)
            itf.moveForm(cast(dx), cast(dy))
        }

        .addNewForms(result)
    }

    // Duplicates the selected forms as one undoable step. The copies stand a little below and to
    // the right of their originals and become the selection; the clipboard is left alone.
    mtd duplicate()
    {
        var payload: CaptureClipboardForms
        for s in .selection do
            payload.add(.forms[s])

        var result = payload.toForms(me)
        .remapGroups(result)
        for itf in result
        {
            itf.setup(me)
            itf.moveForm(DuplicateOffset, DuplicateOffset)
        }

        .addNewForms(result)
    }

    // Adds `forms` on top of the capture as one undoable step and makes them the selection.
    private mtd addNewForms(forms: Array'IForm)
    {
        let undo = .newUndo(.CreateForm)
        undo.oldForms = forms

        let countBefore = .forms.count
        .pushUndo(undo)

        .selection.clear()
        for i in undo.oldForms.count do
            .selection.add(countBefore + i)

        .selectionHasChanged()
    }
}
