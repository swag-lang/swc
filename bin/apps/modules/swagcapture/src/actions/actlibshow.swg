using Gui

struct ActionLibFilter {}

impl ActionLibFilter
{
    newCmdId("Reset")
    newCmdId("AllItems")
    newCmdId("Captures")
    newCmdId("ScreenCaptures")
    newCmdId("ImportedCaptures")
    newCmdId("Images")
    newCmdId("FavoritesOnly")
    newCmdId("RatingAny")
    newCmdId("Rating1")
    newCmdId("Rating2")
    newCmdId("Rating3")
    newCmdId("Rating4")
    newCmdId("Rating5")
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
        case .Reset:
            evt.updatedFields |= .Name
            evt.name          = appStrings().act_ResetFilters

        case .AllItems, .Captures, .ScreenCaptures, .ImportedCaptures, .Images:
            evt.updatedFields |= .Name | .Checked | .RenderingHint
            evt.renderingHint = .ExclusiveGroup
            switch cxt.id
            {
            case .AllItems:
                evt.name    = appStrings().act_FilterAllItems
                evt.checked = libWnd.contentFilter == .All

            case .Captures:
                evt.name    = appStrings().act_FilterCaptures
                evt.checked = libWnd.contentFilter == .Captures

            case .ScreenCaptures:
                evt.name    = appStrings().act_FilterScreenCaptures
                evt.checked = libWnd.contentFilter == .ScreenCaptures

            case .ImportedCaptures:
                evt.name    = appStrings().act_FilterImportedCaptures
                evt.checked = libWnd.contentFilter == .ImportedCaptures

            case .Images:
                evt.name    = appStrings().act_FilterImages
                evt.checked = libWnd.contentFilter == .Images
            }

        case .FavoritesOnly:
            evt.updatedFields |= .Name | .Checked
            evt.name          = appStrings().act_FilterFavorites
            evt.checked       = libWnd.favoritesOnly

        case .RatingAny, .Rating1, .Rating2, .Rating3, .Rating4, .Rating5:
            evt.updatedFields |= .Name | .Checked | .RenderingHint
            evt.renderingHint = .ExclusiveGroup
            switch cxt.id
            {
            case .RatingAny:
                evt.name    = appStrings().act_FilterAnyRating
                evt.checked = libWnd.minimumRating == 0

            case .Rating1:
                evt.name    = appStrings().act_FilterRating1
                evt.checked = libWnd.minimumRating == 1

            case .Rating2:
                evt.name    = appStrings().act_FilterRating2
                evt.checked = libWnd.minimumRating == 2

            case .Rating3:
                evt.name    = appStrings().act_FilterRating3
                evt.checked = libWnd.minimumRating == 3

            case .Rating4:
                evt.name    = appStrings().act_FilterRating4
                evt.checked = libWnd.minimumRating == 4

            case .Rating5:
                evt.name    = appStrings().act_FilterRating5
                evt.checked = libWnd.minimumRating == 5
            }

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
        case .Reset:
            libWnd.contentFilter = .All
            libWnd.favoritesOnly = false
            libWnd.minimumRating = 0
            libWnd.applicationFilter.clear()
            libWnd.tagFilter.clear()
            libWnd.showUpToDateLinkedImage = true
            libWnd.showUnSavedLinkedImage  = true
            libWnd.showLinkedImage         = true
            libWnd.showUnLinkedImage       = true
            libWnd.view.filter()

        case .AllItems:
            libWnd.contentFilter = .All
            libWnd.view.filter()

        case .Captures:
            libWnd.contentFilter = .Captures
            libWnd.view.filter()

        case .ScreenCaptures:
            libWnd.contentFilter = .ScreenCaptures
            libWnd.view.filter()

        case .ImportedCaptures:
            libWnd.contentFilter = .ImportedCaptures
            libWnd.view.filter()

        case .Images:
            libWnd.contentFilter = .Images
            libWnd.view.filter()

        case .FavoritesOnly:
            libWnd.favoritesOnly = !libWnd.favoritesOnly
            libWnd.view.filter()

        case .RatingAny:
            libWnd.minimumRating = 0
            libWnd.view.filter()

        case .Rating1:
            libWnd.minimumRating = 1
            libWnd.view.filter()

        case .Rating2:
            libWnd.minimumRating = 2
            libWnd.view.filter()

        case .Rating3:
            libWnd.minimumRating = 3
            libWnd.view.filter()

        case .Rating4:
            libWnd.minimumRating = 4
            libWnd.view.filter()

        case .Rating5:
            libWnd.minimumRating = 5
            libWnd.view.filter()

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
