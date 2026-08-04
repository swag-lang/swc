using Gui

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
        let libWnd = cast(*LibraryWnd) notnull cxt.wnd
        let hasSel = libWnd.view.focusItem != Swag.U32.Max

        switch cxt.id
        {
        case .Toggle:
            evt.updatedFields |= .Name | .Checked
            evt.name          = appStrings().act_RecycleBin
            evt.checked       = libWnd.trashMode

        case .Empty:
            evt.updatedFields |= .Name
            evt.name          = appStrings().act_EmptyRecycleBin

        case .Restore:
            evt.updatedFields |= .Name | .Disabled
            evt.name          = appStrings().act_Restore
            evt.disabled      = !hasSel

        case .DeleteForever:
            evt.updatedFields |= .Name | .Disabled
            evt.name          = appStrings().act_DeletePermanently
            evt.disabled      = !hasSel
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let libWnd = cast(*LibraryWnd) notnull cxt.wnd

        switch cxt.id
        {
        case .Toggle:
            libWnd.setTrashMode(!libWnd.trashMode)

        case .Empty:
            let res = MessageDlg.confirm(notnull libWnd.main.surface, appStrings().msg_EraseTrash)
            if res == MessageDlg.BtnYes
            {
                Library.emptyTrash()
                if libWnd.trashMode do
                    catch libWnd.view.fill()
                libWnd.invalidate()
            }

        case .Restore:
            libWnd.restoreSelected()

        case .DeleteForever:
            let res = MessageDlg.confirm(notnull libWnd.main.surface, appStrings().msg_EraseSelected)
            if res == MessageDlg.BtnYes do
                libWnd.deleteForeverSelected()
        }

        return true
    }
}
