using Gui

struct ActionLibFilter {}

impl ActionLibFilter
{
    newCmdId("UpToDateLinkedImage")
    newCmdId("LinkedImage")
    newCmdId("UnSavedLinkedImage")
    newCmdId("UnLinkedImage")
}

impl IActionUI for ActionLibFilter
{
    acceptOwnCmdIds()

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let libWnd = cast(*LibraryWnd) cxt.wnd!

        switch cxt.id
        {
        case .UpToDateLinkedImage:
            evt.updatedFields |= .Name | .Checked
            evt.name          = appStrings().act_UpToDateLinked
            evt.checked       = libWnd.showUpToDateLinkedImage

        case .UnSavedLinkedImage:
            evt.updatedFields |= .Name | .Checked
            evt.name          = appStrings().act_UnsavedLinked
            evt.checked       = libWnd.showUnSavedLinkedImage

        case .LinkedImage:
            evt.updatedFields |= .Name | .Checked
            evt.name          = appStrings().act_FilterHasLinked
            evt.checked       = libWnd.showLinkedImage

        case .UnLinkedImage:
            evt.updatedFields |= .Name | .Checked
            evt.name          = appStrings().act_FilterNoLinked
            evt.checked       = libWnd.showUnLinkedImage
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let libWnd = cast(*LibraryWnd) cxt.wnd!

        switch cxt.id
        {
        case .UpToDateLinkedImage:
            libWnd.showUpToDateLinkedImage = !libWnd.showUpToDateLinkedImage
            libWnd.view.filter()

        case .UnSavedLinkedImage:
            libWnd.showUnSavedLinkedImage = !libWnd.showUnSavedLinkedImage
            libWnd.view.filter()

        case .LinkedImage:
            libWnd.showLinkedImage = !libWnd.showLinkedImage
            libWnd.view.filter()

        case .UnLinkedImage:
            libWnd.showUnLinkedImage = !libWnd.showUnLinkedImage
            libWnd.view.filter()
        }

        return true
    }
}
