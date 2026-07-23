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
        case Toggle:
            evt.setFlags |= .Name | .Checked
            evt.name    = "Recycle Bin"
            evt.checked = libWnd.trashMode

        case Empty:
            evt.setFlags |= .Name
            evt.name = "Empty Recycle Bin"

        case Restore:
            evt.setFlags |= .Name | .Disabled
            evt.name     = "Restore"
            evt.disabled = !hasSel

        case DeleteForever:
            evt.setFlags |= .Name | .Disabled
            evt.name     = "Delete Permanently"
            evt.disabled = !hasSel
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let libWnd = cast(*LibraryWnd) notnull cxt.wnd

        switch cxt.id
        {
        case Toggle:
            libWnd.setTrashMode(!libWnd.trashMode)

        case Empty:
            let res = MessageDlg.confirm(notnull libWnd.main.surface, "This will permanently erase every capture in the recycle bin.")
            if res == MessageDlg.BtnYes
            {
                Library.emptyTrash()
                if libWnd.trashMode do
                    catch libWnd.view.fill()
                libWnd.invalidate()
            }

        case Restore:
            libWnd.restoreSelected()

        case DeleteForever:
            let res = MessageDlg.confirm(notnull libWnd.main.surface, "This will permanently erase the selected capture(s).")
            if res == MessageDlg.BtnYes do
                libWnd.deleteForeverSelected()
        }

        return true
    }
}
