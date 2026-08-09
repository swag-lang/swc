using Gui

struct ActionLibSort {}

impl ActionLibSort
{
    newCmdId("Recent")
    newCmdId("Modified")
    newCmdId("Name")
    newCmdId("Application")
    newCmdId("WindowTitle")
    newCmdId("Dimensions")
    newCmdId("FileSize")
    newCmdId("Similar")
    newCmdId("Invert")
}

impl IActionUI for ActionLibSort
{
    acceptOwnCmdIds()

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let libWnd = cast(*LibraryWnd) cxt.wnd!

        switch cxt.id
        {
        case .Recent:
            evt.updatedFields |= CommandStateEvent.UpdatedFields.Name | .Checked | .RenderingHint
            evt.renderingHint = .ExclusiveGroup
            evt.name          = appStrings().act_SortCapturedAt
            evt.checked       = libWnd.sortMethod == .Recent

        case .Modified:
            evt.updatedFields |= CommandStateEvent.UpdatedFields.Name | .Checked | .RenderingHint
            evt.renderingHint = .ExclusiveGroup
            evt.name          = appStrings().act_SortModified
            evt.checked       = libWnd.sortMethod == .Modified

        case .Name:
            evt.updatedFields |= CommandStateEvent.UpdatedFields.Name | .Checked | .RenderingHint
            evt.renderingHint = .ExclusiveGroup
            evt.name          = appStrings().act_SortName
            evt.checked       = libWnd.sortMethod == .Name

        case .Application:
            evt.updatedFields |= CommandStateEvent.UpdatedFields.Name | .Checked | .RenderingHint
            evt.renderingHint = .ExclusiveGroup
            evt.name          = appStrings().act_SortApplication
            evt.checked       = libWnd.sortMethod == .Application

        case .WindowTitle:
            evt.updatedFields |= CommandStateEvent.UpdatedFields.Name | .Checked | .RenderingHint
            evt.renderingHint = .ExclusiveGroup
            evt.name          = appStrings().act_SortWindowTitle
            evt.checked       = libWnd.sortMethod == .WindowTitle

        case .Dimensions:
            evt.updatedFields |= CommandStateEvent.UpdatedFields.Name | .Checked | .RenderingHint
            evt.renderingHint = .ExclusiveGroup
            evt.name          = appStrings().act_SortDimensions
            evt.checked       = libWnd.sortMethod == .Dimensions

        case .FileSize:
            evt.updatedFields |= CommandStateEvent.UpdatedFields.Name | .Checked | .RenderingHint
            evt.renderingHint = .ExclusiveGroup
            evt.name          = appStrings().act_SortFileSize
            evt.checked       = libWnd.sortMethod == .FileSize

        case .Similar:
            evt.updatedFields |= CommandStateEvent.UpdatedFields.Name | .Checked | .RenderingHint
            evt.renderingHint = .ExclusiveGroup
            evt.name          = appStrings().act_Similarity
            evt.checked       = libWnd.sortMethod == .Similar

        case .Invert:
            evt.updatedFields |= CommandStateEvent.UpdatedFields.Name | .Checked
            if libWnd.sortMethod == .Recent or libWnd.sortMethod == .Modified do
                evt.name = appStrings().act_OldestFirst
            elif libWnd.sortMethod == .FileSize do
                evt.name = appStrings().act_SmallerFirst
            elif libWnd.sortMethod == .Dimensions do
                evt.name = appStrings().act_SmallerImagesFirst
            elif libWnd.sortMethod == .Similar
            {
                evt.updatedFields |= .Disabled
                evt.disabled      = true
                evt.name          = appStrings().act_InvertOrder
            }
            else
            {
                evt.name = appStrings().act_InvertOrder
            }

            evt.checked = libWnd.invertSort
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let libWnd = cast(*LibraryWnd) cxt.wnd!

        switch cxt.id
        {
        case .Recent:      libWnd.setSortMethod(.Recent)
        case .Modified:    libWnd.setSortMethod(.Modified)
        case .Name:        libWnd.setSortMethod(.Name)
        case .Application: libWnd.setSortMethod(.Application)
        case .WindowTitle: libWnd.setSortMethod(.WindowTitle)
        case .Dimensions:  libWnd.setSortMethod(.Dimensions)
        case .FileSize:    libWnd.setSortMethod(.FileSize)
        case .Similar:     libWnd.setSortMethod(.Similar)
        case .Invert:      libWnd.setSortOrder(!libWnd.invertSort)
        }

        return true
    }
}
