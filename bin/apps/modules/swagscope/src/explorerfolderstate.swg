using Core, Gui, Pixel

// One location's presentation, including an archive's internal folder.
struct ExplorerFolderState
{
    path:       String
    folder:     String
    mode:       ExplorerMode          = .Medium
    forced:     bool
    board:      ExplorerBoard
    artwork:    ExplorerArtworkSource = .Online
    crop:       Image.SmartCropMode   = .Attention
    kind:       ExplorerKindFilter
    sortColumn: u32
    descending: bool
    query:      String
    selected:   String
    scroll:     Math.Point
}

impl ExplorerFolderState
{
    mtd const matches(path, folder: string)->bool => Path.equals(.path, path) and .folder == folder

    func capture(explorer: *Explorer)->ExplorerFolderState
    {
        with var result: #returntype
        {
            .path       = explorer.listing.path
            .folder     = explorer.folder
            .mode       = explorer.mode
            .forced     = explorer.forced
            .board      = explorer.forcedBoard
            .artwork    = explorer.artworkSource
            .crop       = explorer.thumbnailCrop
            .kind       = explorer.kindFilter
            .sortColumn = explorer.sortColumn
            .descending = explorer.descending
            .query      = explorer.filter.text()
            let scroll = explorer.isThumbnailView() ? explorer.scroll : explorer.list.scrollWnd
            .scroll = scroll.scrollPosition()
            if explorer.selected < explorer.entries.count do
                .selected = explorer.entries[explorer.selected].path
        }

        return result
    }

    mtd const apply(explorer: *Explorer)
    {
        explorer.mode          = cast(u32, .mode) < ExplorerModeValues.count ? .mode : .Medium
        explorer.forced        = .forced
        explorer.forcedBoard   = cast(u32, .board) < ExplorerBoardValues.count ? .board : .Grid
        explorer.artworkSource = cast(u32, .artwork) < ExplorerArtworkSourceValues.count ? .artwork : .Online
        explorer.thumbnailCrop = cast(u32, .crop) < ThumbnailCropModes.count ? .crop : .Attention
        explorer.kindFilter    = cast(u32, .kind) < ExplorerKindFilterValues.count ? .kind : .All
        explorer.sortColumn    = Math.min(.sortColumn, 3)
        explorer.descending    = .descending
        explorer.filter.setText(.query, notify: false)
        if explorer.window.isExploring() do
            explorer.window.searchBox.setText(.query, notify: false)
    }

    // Selection is restored only if it still belongs to the filtered listing.
    mtd const restorePosition(explorer: *Explorer)
    {
        for index, row in explorer.shown where not .selected.isEmpty() and explorer.entries[index].path == .selected
        {
            explorer.selected = index
            if not explorer.isThumbnailView()
            {
                explorer.list.setFocusedIndex(cast(u32, row), ensureVisible: false)
                explorer.list.selectLine(cast(u32, row))
            }
        }

        let scroll = explorer.isThumbnailView() ? explorer.scroll : explorer.list.scrollWnd
        scroll.setScrollPos(.scroll.x, .scroll.y)
        explorer.showMediaInfo()
    }
}
