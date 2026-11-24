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
    newCmdId("RevealImage")
    newCmdId("Export")
    newCmdId("EditTags")
    newCmdId("Favorite")
    newCmdId("Move")
    newCmdId("Delete")
    newCmdId("Search")
    newCmdId("Rate0")
    newCmdId("Rate1")
    newCmdId("Rate2")
    newCmdId("Rate3")
    newCmdId("Rate4")
    newCmdId("Rate5")
}

const RatingCommandIds = [ActionLibSel.Rate0, ActionLibSel.Rate1, ActionLibSel.Rate2,
                          ActionLibSel.Rate3, ActionLibSel.Rate4, ActionLibSel.Rate5]

impl IActionUI for ActionLibSel
{
    acceptOwnCmdIds()

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        if cxt.id == .Delete
        {
            evt.updatedFields |= .RenderingHint
            evt.renderingHint |= .Critical
        }

        let libWnd = assume cast(*LibraryWnd, cxt.wnd)
        let view   = libWnd.view
        let item   = view.focusItem < view.items.count ? view.items[view.focusItem] : null
        let texts  = appStrings()
        let theme  = libWnd.theme()

        switch cxt.id
        {
        // The arrows start a walk on the first capture when none is chosen.
        case .Left, .Up, .Right, .Down, .Home, .End:
            switch cxt.id
            {
            case .Left:  evt.name = texts.act_LibraryPrevious
            case .Right: evt.name = texts.act_LibraryNext
            case .Up:    evt.name = texts.act_LibraryAbove
            case .Down:  evt.name = texts.act_LibraryBelow
            case .Home:  evt.name = texts.act_LibraryFirst
            case .End:   evt.name = texts.act_LibraryLast
            }

            evt.updatedFields |= .Name | .Disabled
            evt.disabled      = view.items.isEmpty()

        case .Open:
            evt.name     = texts.act_OpenSelected
            evt.icon     = theme.icon(.OpenFile)
            evt.disabled = libWnd.trashMode or not item or (item.kind != .Image and not item.capture)

        case .RevealImage:
            evt.name     = texts.act_LocateImage
            evt.icon     = theme.icon(.OpenExternal)
            evt.disabled = libWnd.trashMode or not item or item.kind != .Image

        case .Export, .EditTags, .Favorite:
            evt.disabled = libWnd.trashMode or not item or item.kind == .Image
            switch cxt.id
            {
            case .Export:
                evt.name     = texts.act_ExportSelected
                evt.icon     = theme.icon(.Export)
                evt.disabled = evt.disabled or libWnd.exporting

            case .EditTags:
                evt.name = texts.act_EditTags
                evt.icon = theme.icon(.Edit)

            case .Favorite:
                evt.name = texts.act_FavoriteCapture
                evt.icon = theme.icon(.Star)
                evt.updatedFields.add(.Checked)
                evt.checked = item and item.capture and item.capture.favorite
            }

        case .Move:
            evt.name     = texts.act_MoveSelected
            evt.icon     = theme.icon(.ExploreFolder)
            evt.disabled = libWnd.trashMode or not libWnd.hasSelected()

        case .Search:
            evt.name = texts.act_SearchLibrary
            evt.icon = theme.icon(.Search)

        case .Delete:
            evt.updatedFields |= .Name | .Disabled
            evt.name          = texts.act_DeleteCapture
            evt.disabled      = not libWnd.hasSelected()

        case .Rate0, .Rate1, .Rate2, .Rate3, .Rate4, .Rate5:
            evt.updatedFields |= .Name | .Disabled
            evt.disabled      = libWnd.trashMode or not item or item.kind == .Image or not libWnd.hasSelected()
            for id, rating in RatingCommandIds where id == cxt.id do
                evt.name = ratingLabel(cast(u8, rating))
        }

        if evt.icon.isValid() do
            evt.updatedFields |= .Name | .Icon | .Disabled
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
            libWnd.view.openItem(libWnd.view.items[libWnd.view.focusItem])

        case .RevealImage:
            discard Env.showInFileExplorer(libWnd.view.items[libWnd.view.focusItem].fi.fullName)

        case .Export:
            libWnd.exportSelected()

        case .EditTags:
            libWnd.editSelectedTags()

        case .Favorite:
            libWnd.toggleSelectedFavorite()

        case .Move:
            libWnd.moveSelected()

        // Delete sends the captures to the recycle bin, and erases them from there for good.
        case .Delete:
            libWnd.sendCommandEvent(libWnd.trashMode ? ActionLibTrash.DeleteForever : ActionFile.DeleteCapture)

        case .Search:
            libWnd.searchEdit.setFocus()

        case .Rate0, .Rate1, .Rate2, .Rate3, .Rate4, .Rate5:
            for id, rating in RatingCommandIds where id == cxt.id do
                libWnd.rateSelected(cast(u8, rating))
        }

        return true
    }
}
