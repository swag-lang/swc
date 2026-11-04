using Gui

// The commands that choose the order of the library.
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
        let libWnd = assume cast(*LibraryWnd, cxt.wnd)

        switch cxt.id
        {
        case .Recent:
            evt.updatedFields |= .Icon
            evt.icon          = cxt.wnd!.theme().icon(.History)
            evt.updatedFields |= CommandStateEvent.UpdatedFields.Name | .Checked | .RenderingHint
            evt.renderingHint = .ExclusiveGroup
            evt.name          = appStrings().act_SortCapturedAt
            evt.checked       = libWnd.sortMethod == .Recent

        case .Modified:
            evt.updatedFields |= .Icon
            evt.icon          = cxt.wnd!.theme().icon(.History)
            evt.updatedFields |= CommandStateEvent.UpdatedFields.Name | .Checked | .RenderingHint
            evt.renderingHint = .ExclusiveGroup
            evt.name          = appStrings().act_SortModified
            evt.checked       = libWnd.sortMethod == .Modified

        case .Name:
            evt.updatedFields |= .Icon
            evt.icon          = cxt.wnd!.theme().icon(.Sort)
            evt.updatedFields |= CommandStateEvent.UpdatedFields.Name | .Checked | .RenderingHint
            evt.renderingHint = .ExclusiveGroup
            evt.name          = appStrings().act_SortName
            evt.checked       = libWnd.sortMethod == .Name

        case .Application:
            evt.updatedFields |= .Icon
            evt.icon          = cxt.wnd!.theme().icon(.OpenExternal)
            evt.updatedFields |= CommandStateEvent.UpdatedFields.Name | .Checked | .RenderingHint
            evt.renderingHint = .ExclusiveGroup
            evt.name          = appStrings().act_SortApplication
            evt.checked       = libWnd.sortMethod == .Application

        case .WindowTitle:
            evt.updatedFields |= .Icon
            evt.icon          = cxt.wnd!.theme().icon(.Outline)
            evt.updatedFields |= CommandStateEvent.UpdatedFields.Name | .Checked | .RenderingHint
            evt.renderingHint = .ExclusiveGroup
            evt.name          = appStrings().act_SortWindowTitle
            evt.checked       = libWnd.sortMethod == .WindowTitle

        case .Dimensions:
            evt.updatedFields |= .Icon
            evt.icon          = cxt.wnd!.theme().icon(.ActualSize)
            evt.updatedFields |= CommandStateEvent.UpdatedFields.Name | .Checked | .RenderingHint
            evt.renderingHint = .ExclusiveGroup
            evt.name          = appStrings().act_SortDimensions
            evt.checked       = libWnd.sortMethod == .Dimensions

        case .FileSize:
            evt.updatedFields |= .Icon
            evt.icon          = cxt.wnd!.theme().icon(.File)
            evt.updatedFields |= CommandStateEvent.UpdatedFields.Name | .Checked | .RenderingHint
            evt.renderingHint = .ExclusiveGroup
            evt.name          = appStrings().act_SortFileSize
            evt.checked       = libWnd.sortMethod == .FileSize

        case .Similar:
            evt.updatedFields |= .Icon
            evt.icon          = cxt.wnd!.theme().icon(.Duplicate)
            evt.updatedFields |= CommandStateEvent.UpdatedFields.Name | .Checked | .RenderingHint
            evt.renderingHint = .ExclusiveGroup
            evt.name          = appStrings().act_Similarity
            evt.checked       = libWnd.sortMethod == .Similar

        case .Invert:
            evt.updatedFields |= .Icon
            evt.icon = cxt.wnd!.theme().icon(.Sort)
            evt.updatedFields |= CommandStateEvent.UpdatedFields.Name | .Checked
            switch libWnd.sortMethod
            {
            case .Recent, .Modified:
                evt.name = appStrings().act_OldestFirst

            case .FileSize:
                evt.name = appStrings().act_SmallerFirst

            case .Dimensions:
                evt.name = appStrings().act_SmallerImagesFirst

            // Similarity has no reverse order worth offering.
            case .Similar:
                evt.updatedFields |= .Disabled
                evt.disabled      = true
                evt.name          = appStrings().act_InvertOrder

            default:
                evt.name = appStrings().act_InvertOrder
            }

            evt.checked = libWnd.invertSort
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let libWnd = assume cast(*LibraryWnd, cxt.wnd)

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
        case .Invert:      libWnd.setSortOrder(not libWnd.invertSort)
        }

        return true
    }
}
