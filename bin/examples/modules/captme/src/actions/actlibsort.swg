using Gui

struct ActionLibSort {}

impl ActionLibSort
{
    newCmdId("Recent")
    newCmdId("FileSize")
    newCmdId("Similar")
    newCmdId("Invert")
}

impl IActionUI for ActionLibSort
{
    mtd impl accept(cxt: ActionContext)->bool
    {
        switch cxt.id
        {
        case Recent, FileSize, Invert, Similar:
            return true
        }

        return false
    }

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let libWnd = cast(*LibraryWnd) cxt.wnd

        switch cxt.id
        {
        case Recent:
            evt.setFlags |= .Name | .Checked | .RenderingHint
            evt.renderingHint = .ExclusiveGroup
            evt.name          = "Write Time"
            evt.checked       = libWnd.sortMethod == SortMethod.Recent

        case FileSize:
            evt.setFlags |= .Name | .Checked | .RenderingHint
            evt.renderingHint = .ExclusiveGroup
            evt.name          = "File Size"
            evt.checked       = libWnd.sortMethod == SortMethod.FileSize

        case Similar:
            evt.setFlags |= .Name | .Checked | .RenderingHint
            evt.renderingHint = .ExclusiveGroup
            evt.name          = "Similarity"
            evt.checked       = libWnd.sortMethod == SortMethod.Similar

        case Invert:
            evt.setFlags |= .Name | .Checked
            if libWnd.sortMethod == SortMethod.Recent do
                evt.name = "Oldest First"
            elif libWnd.sortMethod == SortMethod.FileSize do
                evt.name = "Smaller First"
            else
            {
                evt.setFlags |= .Disabled
                evt.disabled = true
                evt.name     = "Invert Order"
            }

            evt.checked = libWnd.invertSort
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let libWnd = cast(*LibraryWnd) cxt.wnd

        switch cxt.id
        {
        case Recent:
            libWnd.setSortMethod(SortMethod.Recent)
        case FileSize:
            libWnd.setSortMethod(SortMethod.FileSize)
        case Similar:
            libWnd.setSortMethod(SortMethod.Similar)

        case Invert:
            libWnd.setSortOrder(!libWnd.invertSort)
        }

        return true
    }
}
