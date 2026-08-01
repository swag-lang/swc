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
    acceptOwnCmdIds()

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let libWnd = cast(*LibraryWnd) notnull cxt.wnd

        switch cxt.id
        {
        case .Recent:
            evt.updatedFields |= .Name | .Checked | .RenderingHint
            evt.renderingHint = .ExclusiveGroup
            evt.name          = "Write Time"
            evt.checked       = libWnd.sortMethod == .Recent

        case .FileSize:
            evt.updatedFields |= .Name | .Checked | .RenderingHint
            evt.renderingHint = .ExclusiveGroup
            evt.name          = "File Size"
            evt.checked       = libWnd.sortMethod == .FileSize

        case .Similar:
            evt.updatedFields |= .Name | .Checked | .RenderingHint
            evt.renderingHint = .ExclusiveGroup
            evt.name          = "Similarity"
            evt.checked       = libWnd.sortMethod == .Similar

        case .Invert:
            evt.updatedFields |= .Name | .Checked
            if libWnd.sortMethod == .Recent do
                evt.name = "Oldest First"
            elif libWnd.sortMethod == .FileSize do
                evt.name = "Smaller First"
            else
            {
                evt.updatedFields |= .Disabled
                evt.disabled      = true
                evt.name          = "Invert Order"
            }

            evt.checked = libWnd.invertSort
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let libWnd = cast(*LibraryWnd) notnull cxt.wnd

        switch cxt.id
        {
        case .Recent:   libWnd.setSortMethod(.Recent)
        case .FileSize: libWnd.setSortMethod(.FileSize)
        case .Similar:  libWnd.setSortMethod(.Similar)
        case .Invert:   libWnd.setSortOrder(!libWnd.invertSort)
        }

        return true
    }
}
