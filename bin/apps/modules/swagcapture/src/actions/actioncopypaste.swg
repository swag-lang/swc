using Gui

// The clipboard commands on forms and on the image inside a form.
struct ActionCopyPaste {}

impl ActionCopyPaste
{
    newCmdId("Copy")
    newCmdId("Paste")
    newCmdId("Cut")
    newCmdId("PasteImageInside")
    newCmdId("CopyAsImage")
    newCmdId("Duplicate")
}

impl IActionUI for ActionCopyPaste
{
    acceptOwnCmdIds()

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let main    = mainWndOf(cxt)
        let capture = main.getCapture()
        let hasSel  = capture and capture.selection.count

        switch cxt.id
        {
        case .Copy:
            evt.updatedFields |= .Disabled | .Name | .Icon
            evt.disabled      = not hasSel
            evt.name          = appStrings().act_Copy
            evt.icon          = main.theme().icon(.Copy)

        case .Cut:
            evt.updatedFields |= .Disabled | .Name | .Icon
            evt.disabled      = not hasSel
            evt.name          = appStrings().act_Cut
            evt.icon          = main.theme().icon(.Cut)

        case .Paste:
            evt.updatedFields |= .Disabled | .Name | .Icon
            if not capture do
                evt.disabled = true
            elif not Clipboard.hasTypedValue(#typeof(CaptureClipboardForms)) and not Clipboard.hasImage() do
                evt.disabled = true
            evt.name = appStrings().act_Paste
            evt.icon = main.theme().icon(.Paste)

        case .PasteImageInside:
            evt.updatedFields        |= .Disabled | .Name | .Hidden
            evt.disabled, evt.hidden = true
            evt.name = appStrings().act_PasteInsideImage

            let hasImg = Clipboard.hasImage()
            if capture and hasSel
            {
                for it in capture.selection
                {
                    if capture.forms[it] is FormImage as image where image.kind == .Image
                    {
                        evt.hidden = false
                        if hasImg
                        {
                            evt.disabled = false
                            break
                        }
                    }
                }
            }

        case .CopyAsImage:
            evt.updatedFields |= .Disabled | .Name
            evt.disabled      = not capture
            evt.name          = appStrings().act_CopyImageToClipboard

        case .Duplicate:
            evt.updatedFields |= .Disabled | .Name | .Icon
            evt.disabled      = not hasSel
            evt.name          = appStrings().act_Duplicate
            evt.icon          = main.theme().icon(.Duplicate)
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main    = mainWndOf(cxt)
        let capture = unwrap main.getCapture()

        switch cxt.id
        {
        case .Copy:             capture.copy()
        case .Cut:              capture.cut()
        case .Paste:            capture.paste()
        case .PasteImageInside: capture.pasteImageInside()
        case .CopyAsImage:      capture.copyAll()
        case .Duplicate:        capture.duplicate()
        }

        return true
    }
}
