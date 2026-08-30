using Gui

struct ActionCopyPaste {}

impl ActionCopyPaste
{
    newCmdId("Copy")
    newCmdId("Paste")
    newCmdId("Cut")
    newCmdId("PasteImageInside")
    newCmdId("CopyAsImage")
}

impl IActionUI for ActionCopyPaste
{
    acceptOwnCmdIds()

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let main    = cast(*MainWnd) cxt.wnd!
        let capture = main.getCapture()
        let hasSel  = capture and capture.selection.count

        switch cxt.id
        {
        case .Copy:
            evt.updatedFields |= .Disabled | .Name | .Icon
            evt.disabled      = !hasSel
            evt.name          = appStrings().act_Copy
            evt.icon          = main.theme().icon(.Copy)

        case .Cut:
            evt.updatedFields |= .Disabled | .Name | .Icon
            evt.disabled      = !hasSel
            evt.name          = appStrings().act_Cut
            evt.icon          = main.theme().icon(.Cut)

        case .Paste:
            evt.updatedFields |= .Disabled | .Name | .Icon
            if !capture do
                evt.disabled = true
            elif !Clipboard.hasTypedValue(#typeof(CaptureClipboardForms)) and !Clipboard.hasImage() do
                evt.disabled = true
            evt.name = appStrings().act_Paste
            evt.icon = main.theme().icon(.Paste)

        case .PasteImageInside:
            evt.updatedFields        |= .Disabled | .Name | .Hidden
            evt.disabled, evt.hidden = true
            evt.name                 = appStrings().act_PasteInsideImage

            let hasImg = Clipboard.hasImage()
            if capture and hasSel
            {
                for it in capture.selection
                {
                    let itfForm = capture.forms[it]
                    if @kindof(itfForm) != FormImage do
                        continue
                    let b = cast(*FormImage) @dataof(itfForm)
                    if b.kind != .Image do
                        continue
                    evt.hidden = false
                    if hasImg
                    {
                        evt.disabled = false
                        break
                    }
                }
            }

        case .CopyAsImage:
            evt.updatedFields |= .Disabled | .Name
            evt.disabled      = !capture
            evt.name          = appStrings().act_CopyImageToClipboard
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main    = cast(*MainWnd) cxt.wnd!
        let capture = main.getCapture()!

        switch cxt.id
        {
        case .Copy:             capture.copy()
        case .Cut:              capture.cut()
        case .Paste:            capture.paste()
        case .PasteImageInside: capture.pasteImageInside()
        case .CopyAsImage:      capture.copyAll()
        }

        return true
    }
}
