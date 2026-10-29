using Gui

// The keyboard commands of the library grid: they move the selection through it, open, delete and
// rate the chosen captures, and reach the search field.
struct ActionLibSel {}

impl ActionLibSel
{
    newCmdId("Left")
    newCmdId("Right")
    newCmdId("Up")
    newCmdId("Down")
    newCmdId("Home")
    newCmdId("End")
    newCmdId("Open")
    newCmdId("Delete")
    newCmdId("Search")
    newCmdId("Rate0")
    newCmdId("Rate1")
    newCmdId("Rate2")
    newCmdId("Rate3")
    newCmdId("Rate4")
    newCmdId("Rate5")
}

impl IActionUI for ActionLibSel
{
    acceptOwnCmdIds()

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let libWnd = assume cast(*LibraryWnd, cxt.wnd)
        let hasSel = libWnd.view.focusItem != Swag.U32.Max

        switch cxt.id
        {
        case .Left, .Up, .Right, .Down,
             .Home, .End, .Open, .Delete:
            evt.updatedFields |= .Disabled
            evt.disabled      = not hasSel

        // A capture in the recycle bin is not rated; an image has no rating to keep.
        case .Rate0, .Rate1, .Rate2, .Rate3, .Rate4, .Rate5:
            evt.updatedFields |= .Disabled
            evt.disabled      = not hasSel or libWnd.trashMode or libWnd.selectedCaptureFiles().isEmpty()
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let libWnd = assume cast(*LibraryWnd, cxt.wnd)

        switch cxt.id
        {
        case .Left:
            libWnd.moveSelLeft()

        case .Up:
            libWnd.moveSelTop()

        case .Right:
            libWnd.moveSelRight()

        case .Down:
            libWnd.moveSelBottom()

        case .Home:
            libWnd.moveSelHome()

        case .End:
            libWnd.moveSelEnd()

        case .Open:
            if libWnd.view.focusItem < libWnd.view.items.count do
                libWnd.view.openItem(libWnd.view.items[libWnd.view.focusItem])

        // Delete sends the captures to the recycle bin, and erases them from there for good.
        case .Delete:
            libWnd.sendCommandEvent(libWnd.trashMode ? ActionLibTrash.DeleteForever : ActionFile.DeleteCapture)

        case .Search:
            libWnd.searchEdit.setFocus()

        case .Rate0:
            libWnd.rateSelected(0)

        case .Rate1:
            libWnd.rateSelected(1)

        case .Rate2:
            libWnd.rateSelected(2)

        case .Rate3:
            libWnd.rateSelected(3)

        case .Rate4:
            libWnd.rateSelected(4)

        case .Rate5:
            libWnd.rateSelected(5)
        }

        return true
    }
}
