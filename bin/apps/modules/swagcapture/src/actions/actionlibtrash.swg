using Gui

// The commands on the library trash: show it, empty it, restore from it, delete for good.
struct ActionLibTrash {}

impl ActionLibTrash
{
    newCmdId("Toggle")
    newCmdId("Empty")
    newCmdId("Restore")
    newCmdId("DeleteForever")
}

impl IActionUI for ActionLibTrash
{
    acceptOwnCmdIds()

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        if cxt.id == .Empty or cxt.id == .DeleteForever
        {
            evt.updatedFields |= .RenderingHint
            evt.renderingHint |= .Critical
        }

        let libWnd = assume cast(*LibraryWnd, cxt.wnd)
        let hasSel = libWnd.view.focusItem != Swag.U32.Max

        switch cxt.id
        {
        case .Toggle:
            evt.updatedFields |= .Icon
            evt.icon          = cxt.wnd!.theme().icon(.Remove)
            evt.updatedFields |= .Name | .Checked
            evt.name          = appStrings().act_RecycleBin
            evt.checked       = libWnd.trashMode

        case .Empty:
            evt.updatedFields |= .Icon
            evt.icon          = cxt.wnd!.theme().icon(.RemoveAll)
            evt.updatedFields |= .Name
            evt.name          = appStrings().act_EmptyRecycleBin

        case .Restore:
            evt.updatedFields |= .Icon
            evt.icon          = cxt.wnd!.theme().icon(.Undo)
            evt.updatedFields |= .Name | .Disabled
            evt.name          = appStrings().act_Restore
            evt.disabled      = not hasSel

        case .DeleteForever:
            evt.updatedFields |= .Icon
            evt.icon          = cxt.wnd!.theme().icon(.Remove)
            evt.updatedFields |= .Name | .Disabled
            evt.name          = appStrings().act_DeletePermanently
            evt.disabled      = not hasSel
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let libWnd = assume cast(*LibraryWnd, cxt.wnd)

        switch cxt.id
        {
        case .Toggle:
            libWnd.setTrashMode(not libWnd.trashMode)

        case .Empty:
            let result = MessageDlg.confirm(unwrap libWnd.main.surface, appStrings().msg_EraseTrash)
            if result == MessageDlg.BtnYes
            {
                Library.emptyTrash()
                if libWnd.trashMode do
                    catch libWnd.view.fill()
                libWnd.invalidate()
            }

        case .Restore:
            libWnd.restoreSelected()

        case .DeleteForever:
            let result = MessageDlg.confirm(unwrap libWnd.main.surface, appStrings().msg_EraseSelected)
            if result == MessageDlg.BtnYes do
                libWnd.deleteForeverSelected()
        }

        return true
    }
}
