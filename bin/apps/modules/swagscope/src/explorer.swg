#global internal

using Core, Gui, Pixel, Video

enum ExplorerMode { Names, Details, Small, Medium, Large }
enum ExplorerKindFilter { All, Videos, Images, Audio, Documents, Subtitles, Archives, Folders }
enum ExplorerArtworkSource { Online, Local }
const ExplorerModeValues:          [5] ExplorerMode          = [.Names, .Details, .Small, .Medium, .Large]
const ExplorerKindFilterValues:    [8] ExplorerKindFilter    = [.All, .Videos, .Images, .Audio, .Documents, .Subtitles, .Archives, .Folders]
const ExplorerArtworkSourceValues: [2] ExplorerArtworkSource = [.Online, .Local]

func explorerBoardName(text: const *AppStrings, index: u64)->string
{
    switch index
    {
    case 1:  return text.board_Grid
    case 2:  return text.board_Posters
    case 3:  return text.board_Covers
    default: return text.board_Automatic
    }
}

// The shape the tiles of a folder take, read from what most of it holds.
enum ExplorerBoard
{
    Grid        // Anything: one even grid, with wide cells for folders of films.
    Posters     // Films: upright posters.
    Covers      // Music: square covers, the album then who made it and when.
    Album       // One album: the cover large, then its tracks.
}

const ExplorerBoardValues: [4] ExplorerBoard = [.Grid, .Posters, .Covers, .Album]

// Width over height of a tile's picture: a page for a folder of documents, a screen for a folder
// that is mostly films.
const ExplorerTilePreviewAspect: f32 = 0.8
const ExplorerFilmPreviewAspect: f32 = 16.0 / 9.0
const ExplorerFilmTileAspect:    f32 = 9.0 / 16.0

// Reports whether `word` opens a declaration or a statement, which a code cell sets in Arc.
func isCardKeyword(word: string)->bool
{
    const Keywords = ["impl", "mtd", "func", "let", "var", "const", "for", "if", "while", "struct", "enum", "using", "return",
                      "fn", "def", "class", "import", "public", "private", "static", "void", "int", "pub", "use"]
    for one in Keywords where one == word do
        return true
    return false
}

// Returns the title of a track from its file name: without its extension and without the
// number and separator a ripper writes before it.
func trackTitle(name: string)->String
{
    let stem = Path.fileNameWithoutExtension(name) orelse name
    var at   = 0'u64
    while at < stem.count and Latin1.isDigit(stem[at]) do
        at += 1
    if at == 0 or at == stem.count do
        return String.from(stem)
    while at < stem.count and (stem[at] == ' ' or stem[at] == '-' or stem[at] == '.' or stem[at] == '_') do
        at += 1
    return String.from(stem[at to])
}

// Writes a duration the way players do: hours only when there are some, minutes and seconds always.
// Writes a length on the information sheet: a film's as hours and minutes, as under its poster,
// anything shorter as minutes and seconds.
func sheetDuration(seconds: u64)->String
{
    if seconds < 3600 do
        return formatDuration(seconds)
    let minutes = Format.toString("%{02}", (seconds / 60) % 60)
    return Format.toString(appStrings().explore_Length, seconds / 3600, minutes)
}

func formatDuration(seconds: u64)->String
{
    let hours   = seconds / 3600
    let minutes = (seconds / 60) % 60
    if hours do
        return Format.toString("%:%{02}:%{02}", hours, minutes, seconds % 60)
    return Format.toString("%:%{02}", minutes, seconds % 60)
}

// Writes a local file time in the current interface language and date order.
func explorerFileTime(time, now: Time.DateTime, language: string)->String
{
    if time.year == now.year and time.month == now.month and time.day == now.day do
        return time.toString(.TimeIsoHm)

    let months = Tokenize.split(appStrings().explore_DateMonths, ';'rune)
    let month  = months[time.month - 1]
    let date   = language == "fr" ? Format.toString("% %", time.day, month) : Format.toString("% %", month, time.day)
    if time.year == now.year do
        return Format.toString(appStrings().explore_DateSameYear, date, time.toString(.TimeIsoHm))
    return Format.toString(appStrings().explore_DateOtherYear, date, time.year)
}

// Returns the duration a thumbnail is labelled with, in seconds, or zero when it carries none.
func thumbnailDuration(image: const *Image)->u64
{
    for &record in image.metadata where record.isTag(cast(const [..] u8, Viewer.ThumbnailDurationTag)) do
        return catch StrConv.toU64(cast(string, record.toSlice())) orelse 0
    return 0
}

struct ExplorerTemporary
{
    file:    String
    title:   String
    path:    String
    archive: String
}

// Owns exploration independently of the file currently being viewed.
//
// The folder keeps its path in the window strip, a permanent filename filter and quiet menus
// choosing the order and the way of showing it, above a contact sheet of
// what it holds. Moving through the history, refreshing, the online media choices — everything
// else is an entry of the window's lens, and the item chosen is described in the window's sheet.
struct Explorer
{
    using wnd: Wnd

    late
    {
        window:        *ViewerWindow
        header:        *Wnd
        tools:         *StackLayoutCtrl
        address:       *PathBar
        title:         *Label
        status:        *Label
        failure:       *ViewerErrorView
        extractAll:    *IconButton
        kindMenu:      *IconButton
        sortMenu:      *IconButton
        modeMenu:      *IconButton
        filter:        *EditBox
        list:          *ListCtrl
        archiveHeader: *Header
        scroll:        *ScrollWnd
        grid:          *ExplorerGrid
    }

    detailNameWidth: f32
    layingHeader:    bool
    mode:            ExplorerMode          = .Medium
    history:         NavigationHistory
    listing:         ExplorerListing
    entries:         Array'ExplorerEntry
    sortOrder:       Array'u64
    shown:           Array'u64
    folder:          String
    requested:       String
    requestedFolder: String
    load:            ExplorerListingLoad
    watchTimer:      *Timer?
    refreshPending:  bool
    dragSource:      *Wnd?
    dragOrigin:      Math.Point
    dragPath:        String
    draggingFile:    bool
    previews:        Array'*ExplorerPreview     // Stable task storage while the runtime owns each preview.
    generation:      u64
    selectedFiles:   Array'u64
    selected:        u64                   = Swag.U64.Max
    pendingOpen:     u64                   = Swag.U64.Max
    temporaryFiles:  Array'ExplorerTemporary
    cached:          Array'u64
    sortColumn:      u32
    descending:      bool
    kindFilter:      ExplorerKindFilter
    artworkSource:   ExplorerArtworkSource = .Online
    thumbnailCrop:   Image.SmartCropMode   = .Attention
    showTileCaption: bool                  = true
    menuPaths:       Array'String
    previewSettings: String
    previewEpoch:    u64
    previewAspect:   f32                   = ExplorerTilePreviewAspect     // Shape of the tiles, chosen from what the listing holds.
    extraction:      ArchiveExtraction
    cacheClear:      ExplorerCacheClear
    clearingCaches:  bool
    cacheRoot:       String
    toast:           *Toast?
    forcedBoard:     ExplorerBoard     // The board the view menu forces, when `forced`.
    forced:          bool
    holdsMedia:      bool     // Whether the page shows films or albums, whose pictures may come from online.
    restoredView:    ExplorerFolderState
    restoringView:   bool
    privateView:     bool     // A private visit stays transient until the location is entered again.
}

// Returns the glyph of the kinds of file `filter` keeps.
func kindFilterIcon(filter: ExplorerKindFilter)->ThemeIcons
{
    switch filter
    {
    case .Videos:    return .FileVideo
    case .Images:    return .FileImage
    case .Audio:     return .FileAudio
    case .Documents: return .File
    case .Subtitles: return .Outline
    case .Archives:  return .FileArchive
    case .Folders:   return .Folder
    default:         return .File
    }
}

impl Explorer
{
    // The air between the page and the edges of the document, the air between the line of the
    // path and the page under it, and the size the title of an album is set in.
    const PageMargin       = 72.0
    const HeaderGap        = 8.0
    const TitleFontSize    = 36'u32
    const MinTitleFontSize = 28'u32
    const ToolHeight       = 32.0

    func create(parent: *Wnd, window: *ViewerWindow)->*Explorer
    {
        with let result = Wnd.create'Explorer(parent, "scope.explorer")
        {
            .dockStyle       = .Center
            .backgroundStyle = .View
            .window          = window
        }

        result.createHeader()
        result.registerKeyShortcut(.None, .Oem2, ViewerCommands.Find)

        // The tiles draw from the cell edge, so the sheet steps in by the air a cell keeps, and
        // its pictures line up with the title above them.
        let sheetMargin = PageMargin - ExplorerGrid.CellInset
        with result.archiveHeader = Header.create(result)
        {
            .dockStyle   = .Top
            .form        = .Transparent
            .padding.x   = ExplorerGrid.CellInset
            .padding.z   = ExplorerGrid.CellInset
            .ruleInset   = ExplorerGrid.CellInset
            .itemPadding = ExplorerGrid.ArchiveCellInset
            .updateFlags(remove: .Separators)
            let text = appStrings()
            .addColumn(text.explore_Name)
            .addColumn(text.explore_Compression, align: .Right).isClickable = false
            .addColumn(text.explore_Size, align: .Right)
            .addColumn(text.explore_Modified, align: .Right)
            .sigColumnClicked += func|result|(_, column)
            {
                result.sortBy(column, result.sortColumn == column and not result.descending)
            }

            .hide()
        }

        with result.list = ListCtrl.createMultiColumns(result)
        {
            .dockStyle       = .Center
            .backgroundStyle = .View
            .margin          = Math.Vector4{sheetMargin, 0, sheetMargin, 0}
            .updateFlags(.Ellipsis | .HotTrack)
            if result.window.workspace do
                .setSelectionMode(.Multi)
            .addColumn(appStrings().explore_Name, 320)
            .addColumn(appStrings().explore_Type, 96)
            .addColumn(appStrings().explore_Size, 88, align: .Right)
            .addColumn(appStrings().explore_Modified, 130)
            .addColumn(appStrings().explore_Duration, 80, align: .Right)
            .header.itemAt(4).isClickable = false
            .sigSelectionChanged += func|result|(list)
            {
                if list.focusIndex < result.shown.count
                {
                    result.selected = result.shown[list.focusIndex]
                    result.showMediaInfo()
                    result.requestPreview()
                }
            }

            .onFillVirtualLine = func(list, line, row)
            {
                if not line do
                    return
                let explorer = unwrap list.ancestorByType'Explorer()
                let index    = explorer.shown[row]
                let entry    = &explorer.entries[index]
                line.setItem(0, entry.name, explorer.entryIcon(index))
                if explorer.mode == .Details
                {
                    // The measures read in faint mono, each aligned as its column's title is.
                    let faint = explorer.themeColors().faintText
                    line.setItem(1, entry.directory ? appStrings().ui_Folder : (Path.extension(entry.name) orelse "")).colorFg = faint
                    with let size = line.setItem(2, entry.directory ? {} : StrConv.toDisplaySize(entry.size))
                    {
                        .horzAlign = .Right
                        .colorFg   = faint
                        .mono      = true
                    }

                    with let modified = line.setItem(3, entry.when.year ? explorerFileTime(entry.when, Time.DateTime.now(), explorer.window.language) : "")
                    {
                        .colorFg = faint
                        .mono    = true
                    }

                    with let duration = line.setItem(4, entry.duration ? formatDuration(entry.duration) : "")
                    {
                        .horzAlign = .Right
                        .colorFg   = faint
                        .mono      = true
                    }
                }
            }

            .sigLeftDoubleClicked += func|result|(_, _)
            {
                result.activate(result.selected)
            }

            .sigRightClicked += func|result|(_, point)
            {
                let list = result.list
                result.showEntryMenu(list.hotIndex, list.listView.localToSurface(point))
            }

            .sigKeyPressed += func|result|(_, evt)
            {
                if evt.key == .Return
                {
                    result.openSelection()
                    evt.accepted = true
                }
            }
        }

        result.list.listView.hookOnEvent = func|result|(source, evt)->bool
        {
            if evt is ResizeEvent and result.mode == .Names do
                result.fitNameColumn()
            if evt is MouseEvent as mouse do
                return result.handleFileDrag(source, mouse)
            return false
        }

        result.list.header.sigColumnClicked += func|result|(_, column)
        {
            result.sortBy(column, result.sortColumn == column and not result.descending)
        }

        with result.scroll = Wnd.create'ScrollWnd(result)
        {
            .dockStyle = .Center
            .margin    = Math.Vector4{sheetMargin, 0, sheetMargin, 0}
            .updateFlags(.DisableHorizontal)
            .sigScrollPositionChanged += func|result|(_, _, _) { result.prioritizeVisible() }
        }

        with result.grid = result.scroll.createView'ExplorerGrid()
        {
            .explorer        = result
            .backgroundStyle = .View
            .focusPolicy     = .Tab
        }

        with result.failure = ViewerErrorView.create(result, "", .Folder)
        {
            .dockStyle = .Center
            .margin    = Math.Vector4{PageMargin, 0, PageMargin, 0}
            .hide()
        }

        result.retranslate()
        result.previews.add(Memory.new'ExplorerPreview())
        result.setMode(.Medium)
        return result
    }

    // Builds the permanent query and listing controls; the location belongs to the caption.
    private mtd createHeader()
    {
        with .header = Wnd.create'Wnd(me, Math.Rectangle{0, 0, 0, 2 * ToolHeight + HeaderGap}, "scope.explorer.header")
        {
            .dockStyle       = .Top
            .backgroundStyle = .Transparent
            .padding         = Math.Vector4{PageMargin, 0, PageMargin, HeaderGap}
        }

        with let line = Wnd.create'Wnd(.header)
        {
            .dockStyle       = .Center
            .backgroundStyle = .Transparent
        }

        // The tools stand below the path, where their labels cannot read as path components.
        with .tools = StackLayoutCtrl.create(line, .Left, {0, 0, 0, 0})
        {
            .backgroundStyle = .Transparent
            .spacing         = 8
        }

        with .status = Label.create(.tools, "", {0, 0, 0, ToolHeight}, null, .SecondaryText)
        {
            .layoutSpec.alignY = .End
            .margin.z = 8
            .style.setFont(me.theme().createDefaultFontFs(12), .Regular)
            .style.addStyleSheetColors("label_TextLight $label_TextFaint")
            .setTextAlignment(.Right, .OpticalCenter)
        }

        // Retain the folder query while the shared editor is used by an open document.
        with .filter = EditBox.create(line,
                                      "",
                                      {0, 0, ViewerWindow.SearchNoOptionsFieldWidth, ToolHeight},
                                      flags: .ClearButton | .ReleaseFocusOnEnterOrEscape)
        {
            .dockStyle = .Center
            .setForm(.Transparent)
            .setIcon(me.theme().icon(.Search, themeRowIconSize(me.themeMetrics())))
            .setPlaceholder(appStrings().ui_FilterFiles)
            .hide()
            .sigTextChanged += func|view = me|(_)
            {
                view.fill()
                view.layoutTools()
            }

            .sigSubmitted += func|view = me|(_)
            {
                view.focusContent()
            }

            .sigCancelled += func|view = me|(_)
            {
                view.filter.setText("")
                view.focusContent()
            }
        }

        // An archive offers to extract all it holds, a quiet word acting at once.
        with .extractAll = IconButton.createQuiet(.tools, ViewerCommands.ExtractAll, menu: false)
        {
            .layoutSpec.alignY = .End
            .hide()
        }

        with .sortMenu = IconButton.createQuiet(.tools)
        {
            .layoutSpec.alignY = .End
            .setIcon(me.theme().icon(.Sort, themeRowIconSize(me.themeMetrics())))
            .sigPressed += func|view = me|(_) { view.showSortMenu() }
        }

        with .kindMenu = IconButton.createQuiet(.tools)
        {
            .layoutSpec.alignY = .End
            .setIcon(me.theme().icon(.Filter, themeRowIconSize(me.themeMetrics())))
            .toolTip    = appStrings().explore_FilterByType
            .sigPressed += func|view = me|(_) { view.showKindFilterMenu() }
        }

        with .modeMenu = IconButton.createQuiet(.tools)
        {
            .layoutSpec.alignY = .End
            .toolTip           = appStrings().explore_View
            .sigPressed        += func|view = me|(_) { view.showModeMenu() }
        }

        with .address = PathBar.create(.window, "scope.explorer.address")
        {
            .focusPolicy                = .Click
            .breadcrumb.maxVisibleItems = 3
            .breadcrumb.overflowIcon    = .Folder
            .breadcrumb.overflowCommand = ViewerCommands.ChooseFolder
            .position.height            = ToolHeight
            .sigNavigate                += func|explorer = me|(_, path)
            {
                explorer.navigateBreadcrumb(path)
            }

            .sigEditFinished += func|explorer = me|(_)
            {
                explorer.focusContent()
            }

            .breadcrumb.sigFillMenu += func|explorer = me|(_, index, menu)
            {
                explorer.fillBreadcrumbMenu(index, menu)
            }

            .breadcrumb.hookOnEvent = func|explorer = me|(_, evt)
            {
                if evt is MouseEvent as mouse where mouse.kind == .Released and mouse.button == .Right
                {
                    explorer.showBreadcrumbMenu(mouse.surfacePos)
                    return true
                }

                return false
            }

            .edit.hookOnEvent = func|explorer = me|(_, evt)
            {
                if evt is KeyEvent as key where key.kind == .Pressed and key.key == .Return
                {
                    explorer.submitAddress()
                    return true
                }

                return false
            }

            .edit.sigTextChanged += func|explorer = me|(_)
            {
                explorer.clearAddressError()
            }

            .edit.sigFocusLost += func|explorer = me|(_)
            {
                explorer.clearAddressError()
            }
        }

        // The breadcrumb names the folder: the title stays hidden and only holds the location's
        // name.
        with .title = Label.create(line, "", {}, null, .Ellipsis)
        {
            .style.setFont(me.theme().createDefaultFont(TitleFontSize, .Bold), .Regular)
            .setTextAlignment(.Left, .Bottom)
            .hide()
        }
    }

    // Shows the filter of the listing and gives it the keyboard.
    mtd revealFilter()
    {
        .window.showSearch()
    }

    // Keeps the path in the strip and the permanent filter beside the listing controls.
    mtd fitHeader() => .layoutTools()

    mtd layoutTools()
    {
        if .layingHeader or .grid == null do
            return
        .layingHeader = true
        defer .layingHeader = false

        let metrics = .themeMetrics()
        let inset   = Math.clamp(.clientRect().width / 16, metrics.miniBar_Padding, PageMargin)
        .header.padding.x       = inset
        .header.padding.z       = inset
        .list.margin.x          = inset - ExplorerGrid.CellInset
        .list.margin.z          = inset - ExplorerGrid.CellInset
        .archiveHeader.margin.x = .list.margin.x
        .archiveHeader.margin.z = .list.margin.z
        .scroll.margin.x        = .list.margin.x
        .scroll.margin.z        = .list.margin.z
        .title.hide()
        .tools.show()
        .extractAll.show(.listing.isArchive)
        .status.hide()
        let frame = .window.surface!.wnd
        frame.applyLayout()
        var room = frame.captionRoomRect()
        room.x     += metrics.wnd_CaptionPathGap
        room.width = Math.max(room.width - metrics.wnd_CaptionPathGap, 0)
        let hasClose = .window.hasSoloCaption() or (.window.workspace?.usesCellCaptions() orelse false)
        let closeWidth = hasClose ? ViewerWorkspace.ViewTitleHeight : 0.0
        // Below this width the ancestor menu alone would consume the title strip.
        let inCaption = .window.stripInset() > 0 and (.window.workspace?.scenes.count orelse 0) < 2 and
                        room.width >= closeWidth + ToolHeight * 4
        let rowY      = inCaption ? 0 : ToolHeight + HeaderGap
        .header.position.height = rowY + ToolHeight + HeaderGap
        .applyLayout()

        let line  = unwrap .tools.parent
        let space = line.clientRect().width
        .sortMenu.show()
        .kindMenu.show()
        .tools.spacing = 8
        .sortMenu.setQuietText(.sortName())
        .kindMenu.setQuietText(.filterKindName())
        .modeMenu.setQuietText("")
        var width = Math.ceil(.tools.itf.measureContent({}).x)
        if width > space * 0.55
        {
            .sortMenu.setQuietText("")
            .kindMenu.setQuietText("")
            .modeMenu.setQuietText("")
            .tools.spacing = 4
            width = Math.ceil(.tools.itf.measureContent({}).x)
        }

        // At split-pane widths leave room to type. The settings sheet holds the displaced actions.
        let compact = space - width < ToolHeight * 4
        if compact
        {
            .sortMenu.hide()
            .kindMenu.hide()
            .extractAll.hide()
            width = Math.ceil(.tools.itf.measureContent({}).x)
        }

        .modeMenu.toolTip = compact ? appStrings().explore_ListingOptions : appStrings().explore_View
        let right = Math.max(space - width, 0)
        .tools.setPosition({right, rowY, width, ToolHeight})
        .tools.computeLayout()
        if .window.isExploring()
        {
            let group = .window.searchGroup
            group.setParent(line)
            group.setPosition({0, rowY, Math.max(right - (compact ? metrics.miniBar_Padding : metrics.floating_Inset), 0), ToolHeight})
            .window.searchCloseButton.hide()
            .window.searchNavigation.hide()
            .window.searchOptionsButton.show(not compact)
            var fieldWidth = group.position.width
            if not compact
            {
                let options = themeDropDownButtonWidth(metrics)
                .window.searchOptionsButton.setPosition({fieldWidth - options, 0, options, ToolHeight})
                fieldWidth -= options + ViewerWindow.SearchGroupSpacing
            }
            let field = .window.searchBox
            field.setPosition({0, 0, Math.max(fieldWidth, 0), ToolHeight})
            let full = appStrings().ui_FilterFiles
            let font = field.font().regular orelse .theme().createDefaultFont(metrics.defaultFontSize)
            let textWidth = Painter.measureStringSnapped(full, font, deviceScale: .deviceScale())
            let room = field.paddedClientRect().width - field.icon.sizeX - metrics.iconText_Margin
            let placeholder = compact or textWidth > room ? appStrings().ui_FilterMode : full
            if field.name.text != placeholder do
                field.setPlaceholder(placeholder)
        }

        if inCaption
        {
            let height = Math.min(ToolHeight, room.height)
            let origin = .window.surfaceToLocal(frame.localToSurface(Math.Point{room.x, room.vertCenter() - height * 0.5}))
            .address.setPosition({origin.x, origin.y, Math.min(metrics.wnd_CaptionPathWidth, room.width - closeWidth), height})
        }
        else
        {
            let origin = .window.surfaceToLocal(line.localToSurface(Math.Point{}))
            .address.setPosition({origin.x, origin.y, Math.min(metrics.wnd_CaptionPathWidth, Math.max(0, space - closeWidth)), ToolHeight})
        }
        .address.refreshPath()
        if hasClose and not .address.edit.isLocallyVisible() and not .address.breadcrumb.items.isEmpty()
        {
            let leaf = .address.breadcrumb.items.backPtr()
            let width = Math.ceil(Math.max(leaf.bodyRect.right(), leaf.arrowRect.right()))
            if width > 0 do
                .address.resize(Math.min(width, .address.position.width), .address.position.height)
        }
        .address.show(.isVisible() and (not inCaption or .window.isWorkspaceActive()))
        .window.layoutCellCaption()
    }

    // Shows the listing presentation and its thumbnail options in one compact sheet.
    mtd showModeMenu()
    {
        let sheet = OptionSheet.View.create(.modeMenu, func|view = me|(page) { view.describeViewOptions(page) }, owner: me)
        sheet.doModal(.modeMenu, autoDestroy: true)
    }

    mtd describeViewOptions(page: *OptionSheet.Page)
    {
        let text = appStrings()
        let size = themeRowIconSize(.themeMetrics())
        page.addCommandLink(text.explore_View, ViewerCommands.Modes, .window, .window.explorerModeIcon(.mode))

        if not .sortMenu.isLocallyVisible()
        {
            const SortOptions = [ViewerCommands.SortName, ViewerCommands.SortType, ViewerCommands.SortSize,
                                 ViewerCommands.SortModified, ViewerCommands.SortAscending, ViewerCommands.SortDescending]
            const TextOptions = [ViewerCommands.MatchCase, ViewerCommands.WholeWord, ViewerCommands.RegularExpression]
            page.addCommandLink(text.explore_Sort, SortOptions, .window, .theme().icon(.Sort, size))
            page.addCommandLink(text.explore_FilterByType, ViewerCommands.KindFilters, .window, .theme().icon(.Filter, size))
            page.addCommandLink(text.ui_SearchOptions, TextOptions,
                                .window, .theme().icon(.Search, size))
            if .listing.isArchive do
                page.addCommand(ViewerCommands.ExtractAll, .window)
        }

        if .isThumbnailView()
        {
            if not .listing.isArchive
            {
            page.addLink(text.explore_Organization,
                         .viewName(),
                         func|view = me|(choices)
                         {
                                 for id in ViewerCommands.Boards do
                                     choices.addCommand(id, view.window)
                         },
                             icon: .theme().icon(.Grid, size))
        }

            page.addCommandLink(text.explore_ThumbnailFraming, ViewerCommands.ThumbnailCrops, .window, .theme().icon(.CenterCrop, size))
        }

        if .showsMedia() do
            page.addCommandLink(text.explore_ArtworkSection, ViewerCommands.Artwork, .window, .theme().icon(.FileImage, size))

        page.addCommand(ViewerCommands.ThumbnailCaptions, .window)
    }

    mtd setTileCaption(show: bool)
    {
        if .showTileCaption == show do
            return
        .showTileCaption = show
        .grid.toolTip    = ""
        .grid.refreshLayout()
        .prioritizeVisible()
    }

    // Reports whether the thumbnails show films or music, whose illustrations may come from
    // online. The choice holds in every arrangement, an even grid included, because the films
    // and the albums of the page take their pictures from it whatever shape their tiles have.
    mtd showsMedia()->bool => .holdsMedia and .isThumbnailView() and not .listing.isArchive

    mtd setThumbnailCrop(mode: Image.SmartCropMode)
    {
        if .thumbnailCrop == mode do
            return
        .thumbnailCrop = mode
        .grid.invalidate()
    }

    mtd setArtworkSource(source: ExplorerArtworkSource)
    {
        if .artworkSource == source do
            return
        .artworkSource = source
        .refreshQuietMenus()
        .refreshPreviewSettings()
        .fill()
    }

    // Forces the shape of the tiles to `board`, or without `forced` gives it back to what the
    // folder holds.
    mtd forceBoard(forced: bool, board = ExplorerBoard.Grid)
    {
        .forced      = forced
        .forcedBoard = board
        if .mode == .Names or .mode == .Details do
            .setMode(.Medium)
        else do
            .fill()
    }

    // Shows the orders of the listing under its menu: the column, then the direction, each one
    // exclusive choice.
    //
    // The menu posts the chosen command to its owner, which routes it to the window: running it
    // here as well would apply it twice, and a choice that depends on the current state would
    // undo itself.
    mtd showSortMenu()
    {
        let text = appStrings()
        let menu = MenuCtrl.createPopup(me, owner: me)
        for id in [ViewerCommands.SortName, ViewerCommands.SortType, ViewerCommands.SortSize, ViewerCommands.SortModified] do
            menu.addRadioItem(sortCommandName(sortColumnOf(id)), id, checked: .sortColumn == sortColumnOf(id))
        menu.addSeparator()
        menu.addRadioItem(text.cmd_SortAscending, ViewerCommands.SortAscending, checked: not .descending)
        menu.addRadioItem(text.cmd_SortDescending, ViewerCommands.SortDescending, checked: .descending)
        discard menu.doModal(.sortMenu, autoDestroy: true)
    }

    // Filters the folder by the kind of file the reader wants to see. The choice of every item
    // stands apart from the kinds that narrow the listing.
    mtd showKindFilterMenu()
    {
        let text  = appStrings()
        let menu  = MenuCtrl.createPopup(me, owner: me)
        let names = [text.explore_FilterAll, text.explore_FilterVideos, text.explore_FilterImages,
                     text.explore_FilterAudio, text.explore_FilterDocuments, text.explore_FilterSubtitles,
                     text.explore_FilterArchives, text.explore_FilterFolders]
        for id, index in ViewerCommands.KindFilters
        {
            let item = menu.addRadioItem(names[index], id, checked: cast(u64, .kindFilter) == index)
            item.icon = .theme().icon(kindFilterIcon(ExplorerKindFilterValues[index]), themeRowIconSize(.themeMetrics()))
            if index == 0 do
                menu.addSeparator()
        }

        discard menu.doModal(.kindMenu, autoDestroy: true)
    }

    // Writes the chosen kind on its menu so the active filter stays visible.
    mtd filterKindName()->string
    {
        let text = appStrings()
        switch .kindFilter
        {
        case .Videos:    return text.explore_FilterVideos
        case .Images:    return text.explore_FilterImages
        case .Audio:     return text.explore_FilterAudio
        case .Documents: return text.explore_FilterDocuments
        case .Subtitles: return text.explore_FilterSubtitles
        case .Archives:  return text.explore_FilterArchives
        case .Folders:   return text.explore_FilterFolders
        default:         return text.explore_FilterAll
        }
    }

    mtd setKindFilter(filter: ExplorerKindFilter)
    {
        if .kindFilter == filter do
            return
        .kindFilter = filter
        .refreshQuietMenus()
        .fill()
    }

    // Sorts the published entries by index so selection, active jobs and cached tiles keep their identity.
    mtd sortBy(column: u32, descending: bool)
    {
        if .sortColumn == column and .descending == descending do
            return
        .sortColumn = column
        .descending = descending
        if .load.started
        {
        .refreshQuietMenus()
            return
        }

        let explorer = me
        .sortOrder.resize(.entries.count)
        for position in .sortOrder.count do
            .sortOrder[position] = position
        .sortOrder.sort(func|explorer, column, descending|(first, second)->s32
        {
            return explorer.entries[first].compareForSort(&explorer.entries[second], column, descending)
        })
        .updateSortIndicators()
        .fill()
    }

    private mtd updateSortIndicators()
    {
        let direction = .descending ? HeaderSortDirection.Descending : .Ascending
        .list.header.setSortIndicator(.sortColumn, direction)
        if .archiveHeader.itemAt(.sortColumn).isClickable do
            .archiveHeader.setSortIndicator(.sortColumn, direction)
        else do
            .archiveHeader.clearSortIndicator()
    }

    // Writes the order, filter, and presentation on their menus. The words of each name what the
    // page shows now; the glyphs of the order and the filter name what their menu does, and the
    // glyph of the view the shape of the page, as a view switch shows it.
    mtd refreshQuietMenus()
    {
        let text = appStrings()
        let size = themeRowIconSize(.themeMetrics())
        .sortMenu.setIcon(.theme().icon(.Sort, size))
        .kindMenu.setIcon(.theme().icon(.Filter, size))
        .modeMenu.setIcon(.theme().icon(.Settings, size))
        .modeMenu.toolTip = text.explore_View
        .sortMenu.toolTip = Format.toString("% · %", sortCommandName(.sortColumn), .descending ? text.cmd_SortDescending : text.cmd_SortAscending)
        .extractAll.setQuietText(text.cmd_ExtractAll)
        .window.refreshExplorerCaption()

        .layoutTools()
    }

    // Writes the selected sort order and its direction as a short label for the Explorer line.
    mtd sortName()->String
    {
        let text = appStrings()
        var name: string
        switch .sortColumn
        {
        case 1:  name = text.sort_Type
        case 2:  name = text.sort_Size
        case 3:  name = text.sort_Modified
        default: name = text.sort_Name
        }

        return Format.toString("% %", name, .descending ? "↓" : "↑")
    }

    // Names what the page shows: the list it is, or the shape of its thumbnails.
    mtd viewName()->string
    {
        let text = appStrings()
        switch .mode
        {
        case .Names:   return text.explore_Names
        case .Details: return text.explore_Details
        case .Small, .Medium, .Large: break
        }

        switch .listingBoard()
        {
        case .Posters: return text.board_Posters
        case .Covers:  return text.board_Covers
        case .Album:   return text.explore_Album
        default:       return text.board_Grid
        }
    }

    // Returns the name of the explored location, as the page title and the window title show it.
    mtd locationName()->String
    {
        let path    = .logicalPath(.listing.path)
        let location: String = .folder.isEmpty() ? String.from(path) : Format.toString("%/%", path, .folder)
        var trimmed = location.toString()
        while trimmed.count > 1 and trimmed[trimmed.count - 1] == '/'u8 do
            trimmed = trimmed[0 until trimmed.count - 1]
        return Path.fileName(trimmed) orelse trimmed
    }

    // Turns the online movie and music details on or off, and shows the tiles again under them.
    mtd setOnlineMedia(movies, music: bool)
    {
        .window.applyOnlineMedia(movies, music)
        catch .window.saveState()
    }

    // Reports whether the chosen item is a piece of music the reader may match by hand.
    mtd canChooseMusic()->bool => .selected < .entries.count and
                                  .window.onlineMusic and
                                  not .listing.isArchive and
                                  not .entries[.selected].directory and
                                  (Path.hasExtension(.entries[.selected].path, ".mp3") or Path.hasExtension(.entries[.selected].path, ".flac"))

    // Shows or hides the listing.
    mtd setShown(visible: bool)
    {
        if not visible do
            .clearFileDrag()
        .show(visible)
        .window.registerKeyShortcut(.None, .F5, visible ? ViewerCommands.Refresh : ViewerCommands.Reload)
        .updateWatchTimer()
        .window.teachHints(visible)
        .showMediaInfo()
        .window.updateSearchAvailability()
        if visible
        {
            .setStatus(.status.text())
            .requestPreview()
        }
    }

    // Reports what the location holds, or why it holds nothing, on the shared bottom line.
    mtd setStatus(text: string)
    {
        .status.setText(text)
        .status.position.width = Math.ceil(.status.itf.measureContent({}).x)
        if .isLocallyVisible()
        {
            .window.showFileInfo(text, "")
            .window.layoutFileInfo()
        }

        .layoutTools()
        .window.refreshTitle()
    }

    mtd refreshMediaOptions()
    {
        .previewAspect = .listingPreviewAspect()
        .grid.refreshLayout()
        .refreshPreviewSettings()
        .requestPreview()
        .grid.invalidate()
    }

    mtd chooseMusic()
    {
        if .selected >= .entries.count do
            return
        let selected   = .selected
        let generation = .generation
        let previous   = .window.privacy.selectedMusicId(&.entries[selected])
        let dialog     = .createMusicChoiceDialog(previous)
        if dialog.doModal() != Dialog.BtnOk do
            return
        if generation != .generation or selected != .selected or selected >= .entries.count do
            return
        let answer = dialog.text()
        let text   = Latin1.trim(answer.toString())
        if text.count and not validMusicId(text)
        {
            .setStatus(appStrings().explore_InvalidMusicId)
            return
        }

        .window.privacy.rememberMusicChoice(&.entries[selected], String.toLower(text), .listing.isArchive ? .listing.path.toString() : .entries[selected].path.toString())
        .retirePreviews()
        .requestPreview()
    }

    mtd createMusicChoiceDialog(previous: string)->*EditDlg
    {
        return EditDlg.createSingleLine(unwrap .window.surface, {title: appStrings().explore_ChooseMusic,
                                                                 message: appStrings().explore_ChooseMusicHelp,
                                                                 text: previous})
    }

    // Describes the chosen item again in the window's sheet, when the sheet is showing.
    mtd showMediaInfo()
    {
        if not .window.infoSheet.isLocallyVisible() do
            return
        .window.refreshInformation()
    }

    // Opens the window's sheet on the chosen item.
    mtd showInformation()
    {
        .window.refreshInformation()
        .window.infoSheet.open()
        .window.sheetToggled(true)
    }

    // Returns whether the selected filesystem item is the file now shown by the window.
    mtd describesFile(path: string)->bool
    {
        if .listing.isArchive or .selected >= .entries.count do
            return false
        var selectedPath = String.from(.entries[.selected].path)
        Path.normalize(&selectedPath)
        return Path.equals(selectedPath, path)
    }

    // Plays what is chosen: an album from its first track, a piece of music with the folder
    // after it.
    mtd playChosen()
    {
        if .grid.board == .Album
        {
            .playAlbum(false)
            return
        }

        if .grid.board != .Covers or .selected >= .entries.count do
            return
        .window.setPlayMode(.Folder)
        let entry = &.entries[.selected]
        if not entry.albumTrack.isEmpty()
        {
            .window.queueFile(entry.albumTrack)
            return
        }

        .activate(.selected)
    }

    // Opens the first track of the album, or one drawn by chance with the folder played in
    // shuffle, every track once before any comes again.
    mtd playAlbum(shuffle: bool)
    {
        if shuffle do
            .window.setPlayMode(.Shuffle)
        for index in .shown
        {
            let entry = &.entries[index]
            if entry.directory or .theme().fileGlyph(entry.name, false, 16).index != cast(s32, ThemeIcons.FileAudio) do
                continue
            .activate(index)
            return
        }
    }

    // Asks where to extract, then extracts the whole archive into a folder named after it there,
    // or, without `all`, the chosen member or folder of the archive right there.
    mtd chooseExtraction(all: bool)
    {
        if not .listing.isArchive or .extraction.started do
            return
        if not all and .selected >= .entries.count do
            return

        with var options: FileDlgOptions
        {
            .mode  = .SelectFolder
            .title = all ? appStrings().cmd_ExtractAll : appStrings().cmd_Extract
            .state = &me.window.fileDlgState
        }

        let dialog = FileDlg.create(unwrap .window.surface, options)
        if dialog.doModal() != Dialog.BtnOk do
            return
        let chosen = dialog.selectedPath()
        if all
        {
            let name = Path.fileNameWithoutExtension(.logicalPath(.listing.path)) orelse "archive"
            .extractTo(Path.combine(chosen, name), all: true)
        }
        else
        {
            .extractTo(chosen, all: false)
        }
    }

    // Extracts into `target`: the whole archive with `all`, else the chosen member or folder.
    mtd extractTo(target: string, all: bool)
    {
        if not .listing.isArchive or .extraction.started do
            return
        var members: Array'Viewers.Archive.ZipEntry
        var strip:   String
        if all
        {
            members = .listing.archive.entries
        }
        else
        {
            if .selected >= .entries.count do
                return
            let entry = &.entries[.selected]
            strip = .folder
            if entry.directory
            {
                for &member in .listing.archive.entries where Utf8.startsWith(member.path, entry.path) do
                    members.add(member[])
            }
            elif entry.archiveIndex < .listing.archive.entries.count
            {
                members.add(.listing.archive.entries[entry.archiveIndex])
            }
        }

        .extraction.start(.listing.path, #move members, strip, target, me)
    }

    // Says how the extraction went, in a toast over the page.
    private mtd finishExtraction()
    {
        .extraction.wait()
        let text = appStrings()
        if not .toast do
            .toast = Toast.create(me, "scope.explorer.toast")
        if not .extraction.error.isEmpty()
        {
            .toast.show(text.explore_ExtractFailed, .extraction.error, .Failure)
            return
        }

        var message: String
        if .extraction.written == 1 do
            message = String.from(text.explore_ExtractedOne)
        else do
            message = Format.toString(text.explore_Extracted, .extraction.written)
        if .extraction.kept do
            message = Format.toString(text.explore_ExtractedKept, message, .extraction.kept)
        .toast.show(message, .extraction.target)
    }

    // Gives the keyboard to the listing, in whichever form it is shown.
    mtd focusContent()
    {
        if .list.isLocallyVisible() do
            .list.setFocus()
        else do
            .grid.setFocus()
    }

    mtd retranslate()
    {
        let text = appStrings()
        .failure.retranslate()
        .showMediaInfo()
        .filter.setPlaceholder(text.ui_FilterFiles)
        .kindMenu.toolTip = text.explore_FilterByType
        .address.breadcrumb.toolTip = text.cmd_EditLocation
        .kindMenu.setIcon(.theme().icon(.Filter, themeRowIconSize(.themeMetrics())))
        .filter.setIcon(.theme().icon(.Search, themeRowIconSize(.themeMetrics())))
        .list.header.itemAt(0).name   = text.explore_Name
        .list.header.itemAt(1).name   = text.explore_Type
        .list.header.itemAt(2).name   = text.explore_Size
        .list.header.itemAt(3).name   = text.explore_Modified
        .list.header.itemAt(4).name   = text.explore_Duration
        .archiveHeader.itemAt(0).name = text.explore_Name
        .archiveHeader.itemAt(1).name = text.explore_Compression
        .archiveHeader.itemAt(2).name = text.explore_Size
        .archiveHeader.itemAt(3).name = text.explore_Modified
        .archiveHeader.invalidate()
        .refreshQuietMenus()
    }

    mtd navigate(path: string, folder: string = "", remember = true)
    {
        .clearFileDrag()
        .rememberView()
        if not Path.equals(.requested, path) or .requestedFolder != folder
        {
            let wasPrivate = .privateView
            .privateView = not .window.privacy.mayRemember(path)
            if wasPrivate and not .privateView
            {
                .filter.setText("", notify: false)
                if .window.isExploring() do
                    .window.searchBox.setText("", notify: false)
            }

            .restoringView = false
            if let state = .window.privacy.folderView(path, folder)
            {
                .restoredView  = state[]
                .restoringView = true
                state.apply(me)
            }
        }

        .failure.hide()
        .generation += 1
        .suspend()
        .pendingOpen     = Swag.U64.Max
        .requested       = path
        .requestedFolder = folder
        if .window.isExploring() do
            .window.workspace?.updateDocumentPath(.window, .sourceArchivePath(path))
        .refreshPending  = false
        if remember do
            .history.push(Format.toString("%\n%", path, folder))
        .window.refreshExplorerCaption()
        .setStatus(appStrings().explore_Loading)
        if not .load.started do
            .startListing()
    }

    mtd rememberView()
    {
        if .listing.path.isEmpty() or .load.started or .failure.isLocallyVisible() do
            return
        if not .window.privacy.mayRemember(.listing.path) do
            .privateView = true
        .window.privacy.rememberFolderView(ExplorerFolderState.capture(me), transient: .privateView)
    }

    // Lists the folder again and gives its previews a fresh cache identity. This also refreshes
    // media on shares whose timestamps do not change when their contents do.
    mtd forceRefresh()
    {
        if .requested.isEmpty() do
            return
        .previewEpoch = Time.Timestamp.utcNow().ticks
        .previewSettings.clear()
        if .load.started do
            .refreshPending = true
        else do
            .reloadListing()
    }

    private mtd reloadListing()
    {
        .leave()
        .startListing()
    }

    private mtd updateWatchTimer()
    {
        if not .isLocallyVisible()
        {
            .stopTimer(&.watchTimer)
        }
        elif not .load.started
        {
            if not .load.watcher.isOpen() do
                .stopTimer(&.watchTimer)
            elif not .watchTimer do
                .watchTimer = .addTimer(250'ms)
        }
    }

    mtd clearCaches(root: string = "")
    {
        if .clearingCaches do
            return
        .clearingCaches = true
        .cacheRoot      = root
        .previewEpoch   = Time.Timestamp.utcNow().ticks
        .previewSettings.clear()
        .setStatus(appStrings().explore_ClearingCaches)
        .retirePreviews()
        for &entry in .entries
        {
            entry.duration  = 0
            entry.technical = {}
        }

        .startCacheClearWhenIdle()
    }

    private mtd startCacheClearWhenIdle()
    {
        if not .clearingCaches or .cacheClear.started do
            return
        for preview in .previews where preview.started do
            return
        .cacheClear.start(me, .cacheRoot)
    }

    private mtd startListing()
    {
        .load.start(.requested, .requestedFolder, .sortColumn, .descending, me)
    }

    private mtd visit(location: string)
    {
        let split = Utf8.indexOf(location, "\n")
        .navigate(location[0 until split], location[split + 1 to], false)
    }

    mtd navigateBreadcrumb(location: string)
    {
        let split = Utf8.indexOf(location, "\n")
        .navigate(location[0 until split], location[split + 1 to])
    }

    // Returns the explored location as one path: the folder, or the archive and the folder inside it.
    mtd locationText()->String
    {
        let path = .logicalPath(.listing.path)
        if .folder.isEmpty() do
            return path
        return Format.toString("%/%", path, .folder)
    }

    mtd nativeArchivePath()->string => .listing.isArchive ? .sourceArchivePath(.listing.path) : ""

    private mtd sourceArchivePath(path: string)->string
    {
        for file in .temporaryFiles where file.file == path do
            return file.archive
        return path
    }

    // Goes to a location typed into the address: the folder or archive it names, a folder inside
    // the archive on show, or the file it names, which opens as any other file does.
    //
    // A path copied from the system file browser comes between quotes, which are not part of it.
    #[Swag.Discardable]
    mtd navigateTyped(text: string)->bool
    {
        var typed = Latin1.trim(text)
        if typed.count >= 2 and typed[0] == '"'u8 and typed[typed.count - 1] == '"'u8 do
            typed = typed[1 until typed.count - 1]
        if .locationText() == typed and typed.count do
            return true
        if .listing.isArchive
        {
            let archive = .logicalPath(.listing.path)
            if typed == archive
            {
                .navigate(.listing.path)
                return true
            }

            if typed.count > archive.count and
               Utf8.startsWith(typed, archive) and
               Path.isDirectorySeparator(typed[archive.count])
            {
                var member = String.from(typed[archive.count + 1 to])
                member.replace("\\", "/")
                if member.isEmpty()
                {
                    .navigate(.listing.path)
                    return true
                }

                if not Utf8.endsWith(member, "/") do
                    member += '/'u8
                for &entry in .listing.archive.entries where Utf8.startsWith(entry.path, member)
                {
                    .navigate(.listing.path, member)
                    return true
                }

                return false
            }
        }

        if not Path.isValidPathName(typed) do
            return false
        let base     = .listing.isArchive ? (Path.directoryName(.listing.path) orelse "") : .listing.path.toString()
        let path     = Path.isRooted(typed) ? String.from(typed) : Path.combine(base, typed)
        let absolute = catch Path.absolute(path) { return false }
        if Directory.exists(absolute) do
            .navigate(absolute)
        elif File.exists(absolute) do
            .window.queueFile(absolute)
        else do
            return false
        return true
    }

    private mtd submitAddress()
    {
        if .navigateTyped(.address.edit.text())
        {
            .address.endEdit()
            .focusContent()
            return
        }

        let message = appStrings().explore_NotFound
        .address.edit.toolTip = message
        .address.edit.setValidator(func||(_) => .InvalidVisible)
        if not .toast do
            .toast = Toast.create(me, "scope.explorer.toast")
        .toast.show(message, "")
    }

    private mtd clearAddressError()
    {
        if .address.edit.isValid() do
            return
        .address.edit.toolTip = ""
        .address.edit.setValidator(null)
    }

    mtd chooseFolder()
    {
        .address.endEdit()
        let initialFolder = .listing.isArchive ? (Path.directoryName(.nativeArchivePath()) orelse "") : .listing.path.toString()
        let chosen        = .window.selectExplorerFolder(initialFolder)
        if chosen.isEmpty() do
            return
        if .listing.isArchive or not Path.equals(chosen, .listing.path) do
            .navigate(chosen)
        .focusContent()
    }

    private mtd showBreadcrumbMenu(position: Math.Point)
    {
        let breadcrumb = .address.breadcrumb
        let point      = breadcrumb.surfaceToLocal(position) + breadcrumb.scrollPos
        var path       = .listing.path.toString()
        var folder     = .folder.toString()
        for &item in breadcrumb.items where item.bodyRect.contains(point) or item.arrowRect.contains(point)
        {
            let tag   = item.tag.toString()
            let split = Utf8.indexOf(tag, "\n")
            if split != Swag.U64.Max
            {
                path   = tag[0 until split]
                folder = tag[split + 1 to]
            }

            break
        }

        if path.count == 0 do
            return
        if .listing.isArchive and path == .listing.path
        {
            let archive  = .logicalPath(path)
            let location = folder.count == 0 ? String.from(archive) : Format.toString("%/%", archive, folder)
            .showLocationMenu(location, position, archive: .nativeArchivePath())
        }
        else
        {
            .showLocationMenu(path, position, directory: true)
        }
    }

    mtd showEntryMenu(row: u64, position: Math.Point)
    {
        if .load.started or row >= .shown.count do
            return
        if .window.workspace and .selectionPaths().count > 1
        {
            let menu = MenuCtrl.createPopup(me, owner: .window)
            menu.addItems([ViewerCommands.OpenChosen, SceneCommands.CompareSelection])
            discard menu.doModal(position, autoDestroy: true)
            return
        }
        if .isThumbnailView()
        {
            .grid.select(row)
        }
        else
        {
            .selected = .shown[row]
            .showMediaInfo()
            .requestPreview()
        }

        let entry = &.entries[.shown[row]]
        let path  = String.from(entry.path)
        if .listing.isArchive
        {
            let archive  = .logicalPath(.listing.path)
            let location = Format.toString("%/%", archive, path)
            .showLocationMenu(location, position, archive: .nativeArchivePath())
        }
        elif entry.directory
        {
            .showLocationMenu(path, position, directory: true)
        }
        else
        {
            .window.showFileActions(path, position)
        }
    }

    private mtd showLocationMenu(path: string, position: Math.Point, directory = false, archive: string = "")
    {
        let stableArchive = String.from(archive)
        let texts         = appStrings()
        let size          = themeRowIconSize(.themeMetrics())
        let menu          = MenuCtrl.createPopup(me, owner: me)

        // The pointer supplies this menu's target. The lens computes state for the current location.
        menu.hookOnEvent = func(_, evt)
        {
            if evt is CommandStateEvent as command where command.kind == .Compute
            {
                command.accepted = true
                return true
            }

            return false
        }

        if directory do
            menu.addItem(texts.explore_OpenSystemFolder, ViewerCommands.OpenSystemFolder, .theme().icon(.OpenExternal, size))
        elif not stableArchive.isEmpty() do
            menu.addItem(texts.explore_RevealArchive, ViewerCommands.RevealArchive, .theme().icon(.Folder, size))
        menu.addItem(texts.ui_MenuCopyPath, ViewerCommands.CopyLocation, .theme().icon(.Copy, size))
        let location = String.from(path)
        let chosen   = menu.doModal(position, autoDestroy: true, dispatchCommand: false)
        if chosen
        {
            let target = chosen == ViewerCommands.RevealArchive ? stableArchive.toString() : location.toString()
            discard .window.runCommand(chosen, contextPath: target)
        }
    }

    mtd updateBreadcrumb()
    {
        let breadcrumb = .address.breadcrumb
        breadcrumb.clear()
        var ancestors: Array'String
        var path = .listing.path.toString()
        while path.count
        {
            ancestors.add(path)
            let parent = Path.directoryName(path) orelse ""
            if not parent.count or parent == path do
                break
            path = parent
        }

        // Include the current folder so the address names the complete location on its own.
        for ancestor in ancestors.reversed()
        {
            let full     = ancestor.toString()
            let name     = Path.fileName(full) orelse full
            let hasArrow = full != .listing.path or not .folder.isEmpty()
            breadcrumb.addItem(name.count ? name : full, hasArrow: hasArrow, tag: Format.toString("%\n", full))
        }

        if .listing.isArchive
        {
            var begin: u64
            for offset in .folder.length where .folder[offset] == '/'u8
            {
                breadcrumb.addItem(.folder.toString()[begin until offset],
                                   hasArrow: offset + 1 < .folder.length,
                                   tag: Format.toString("%\n%", .listing.path, .folder.toString()[0 until offset + 1]))
                begin = offset + 1
            }
        }

        .address.setText(.locationText())
        .address.refreshPath()
        .title.setText(.locationName())
        .window.refreshTitle()
    }

    mtd fillBreadcrumbMenu(index: u64, menu: *MenuCtrl)
    {
        let breadcrumb = .address.breadcrumb
        if index >= breadcrumb.items.count do
            return
        let location = breadcrumb.items[index].tag.toString()
        let split    = Utf8.indexOf(location, "\n")
        let path     = location[0 until split]
        let folder   = location[split + 1 to]
        var children: Array'ExplorerEntry
        if .listing.isArchive and path == .listing.path.toString()
        {
            children = .listing.children(folder)
        }
        else
        {
            let directories = catch Directory.enumerateDirectories(path)
            {
                return
            }

            for directory in directories do
                children.add({name: Path.fileName(directory.fullName) orelse directory.fullName.toString(),
                              path: directory.fullName, directory: true})
        }

        children.sort(func(a, b)->s32 { return Text.compareNames(a.name, b.name) })
        .menuPaths.clear()
        .menuPaths.reserve(children.count)
        for &child in children where child.directory
        {
            let target = .listing.isArchive and path == .listing.path.toString() ?
                         Format.toString("%\n%", path, child.path) : Format.toString("%\n", child.path)
            .menuPaths.add(target)
        }

        var item: u64
        for &child in children where child.directory
        {
            let target   = .menuPaths[item].toString()
            let selected = index + 1 < breadcrumb.items.count and breadcrumb.items[index + 1].tag == target
            menu.addItem(child.name, target, .theme().icon(.Folder, .themeMetrics().menuPopup_IconSize), checked: selected)
            item += 1
        }
    }

    mtd goBack()
    {
        if .history.canGoBack() do
            .visit(.history.goBack())
    }

    mtd goForward()
    {
        if .history.canGoForward() do
            .visit(.history.goForward())
    }

    mtd goUp()
    {
        if not .canGoUp() do
            return
        if .listing.isArchive and not .folder.isEmpty()
        {
            let trimmed = .folder.toString()[0 until .folder.length - 1]
            let parent  = Path.directoryName(trimmed) orelse ""
            .navigate(.listing.path, parent.count ? Format.toString("%/", parent) : {})
        }
        else
        {
            if .listing.isArchive and .history.canGoBack()
            {
                .goBack()
            }
            else
            {
                let parent = Path.directoryName(.listing.path) orelse ""
                if parent.count do
                    .navigate(parent)
            }
        }
    }

    mtd canGoUp()->bool
    {
        if .listing.isArchive and (not .folder.isEmpty() or .history.canGoBack()) do
            return true
        let parent = Path.directoryName(.listing.path) orelse ""
        return parent.count != 0 and parent != .listing.path.toString()
    }

    private mtd clearTextures()
    {
        for &entry in .entries where entry.texture.isValid() do
            .app().renderer.removeTexture(&entry.texture)
        .cached.clear()
    }

    private mtd publish()
    {
        .clearTextures()
        let entering = .listing.isArchive and not .grid.rows
        .entries = #move .listing.entries
        .sortOrder.clear()
        .shown.clear()
        .selected = Swag.U64.Max
        .selectedFiles.clear()
        .showMediaInfo()
        .updateBreadcrumb()

        .updateSortIndicators()
        if entering and not .restoringView do
            .setMode(.Details)
        else do
            .setMode(.mode)
        .scroll.setScrollPos(0, 0)
        if .restoringView
        {
            .restoredView.restorePosition(me)
            .restoringView = false
        }

        .window.privacy.refreshIndicator()
    }

    // Chooses the preview shape from the files listed, before any image arrives. A folder of films
    // uses wide cells whether its previews come from local frames or online artwork.
    mtd listingPreviewAspect()->f32
    {
        var files, films: u64
        for index in .shown
        {
            let entry = &.entries[index]
            if entry.directory do
                continue
            files += 1
            var pluginIndex: u64
            if .window.index.namePlugin(entry.path, &pluginIndex) and .window.index.plugins[pluginIndex].key == "video" do
                films += 1
        }

        if films * 2 > files do
            return ExplorerFilmPreviewAspect
        return ExplorerTilePreviewAspect
    }

    // Returns the shape of the tiles, from what most of the folder holds: films whose posters are
    // looked up stand upright, pieces of music show their covers, or one album when they all
    // belong to the same, and anything else uses an even grid.
    mtd listingBoard()->ExplorerBoard
    {
        if .listing.isArchive do
            return .Grid
        if .forced do
            return .forcedBoard
        if .kindFilter == .Videos do
            return .Posters
        if .kindFilter == .Images do
            return .Grid
        if .kindFilter == .Audio do
            return .Covers
        var files, films, sounds: u64
        var album: String
        var oneAlbum = true
        for index in .shown
        {
            let entry = &.entries[index]
            if entry.directory and entry.albumTrack.isEmpty() and entry.children == Swag.U64.Max do
                continue
            files += 1
            if entry.directory
            {
                if not entry.albumTrack.isEmpty() do
                    sounds += 1
                oneAlbum = false
                continue
            }

            let kind = .theme().fileGlyph(entry.name, false, 16).index
            if kind == cast(s32, ThemeIcons.FileVideo)
            {
                films += 1
            }
            elif kind == cast(s32, ThemeIcons.FileAudio)
            {
                sounds += 1
                if entry.music.title.isEmpty() do
                    oneAlbum = false
                elif album.isEmpty() do
                    album = entry.music.title
                elif album != entry.music.title do
                    oneAlbum = false
            }
        }

        if not files do
            return .Grid
        if films * 2 > files do
            return .Posters
        if sounds * 2 > files do
            return oneAlbum and sounds >= 2 ? .Album : .Covers
        return .Grid
    }

    mtd entryIcon(index: u64, size: f32 = 16)->Icon
    {
        let entry = &.entries[index]
        if entry.directory do
            return .theme().icon(.Folder, size)
        var pluginIndex: u64
        if .window.index.namePlugin(entry.path, &pluginIndex) do
            return .window.pluginIcon(&.window.index.plugins[pluginIndex], size)
        return .theme().icon(.OpenFile, size)
    }

    // Keeps folders navigable in file-kind filters, while the folder choice isolates them.
    private mtd matchesKind(index: u64)->bool
    {
        let entry = &.entries[index]
        if .kindFilter == .All do
            return true
        if .kindFilter == .Folders do
            return entry.directory
        if entry.directory do
            return true

        var pluginIndex: u64
        if not .window.index.namePlugin(entry.path, &pluginIndex) do
            return false
        let key   = .window.index.plugins[pluginIndex].key
        let glyph = .theme().fileGlyph(entry.name, false, 16).index
        switch .kindFilter
        {
        case .Videos:
            return glyph == cast(s32, ThemeIcons.FileVideo)

        case .Images:
            return glyph == cast(s32, ThemeIcons.FileImage)

        case .Audio:
            return glyph == cast(s32, ThemeIcons.FileAudio)

        case .Subtitles:
            return key == "subtitle"

        case .Archives:
            return glyph == cast(s32, ThemeIcons.FileArchive)

        case .Documents:
            return glyph == cast(s32, ThemeIcons.FileCode) or
                   (glyph == cast(s32, ThemeIcons.File) and key != "binary")

        default:
            return true
        }
    }

    mtd fill()
    {
        .grid.hovered = Swag.U64.Max
        .shown.clear()
        .list.clear()
        let query   = .filter.text()
        let options = Viewer.SearchOptions{matchCase: .window.searchMatchCaseOption,
                                           wholeWord: .window.searchWholeWordOption,
                                           regularExpression: .window.searchRegexOption}
        let validPattern = Viewer.patternIsValid(query, options)
        var matcher: Text.NameMatcher
        if query.count and validPattern do
            matcher = assume Viewer.createNameMatcher(query, options)

        var matches: Array'Viewer.SearchMatch
        let sorted = .sortOrder.count == .entries.count
        for position in .entries.count
        {
            let index = sorted ? .sortOrder[position] : position
            let entry = &.entries[index]
            if not .matchesKind(index) do
                continue
            if query.count
            {
                if not validPattern do
                    continue
                matches.clear()
                Viewer.collectTextMatches(entry.name, &matcher, 0, 0, 0, &matches)
                if matches.isEmpty() do
                    continue
            }

            .shown.add(index)
        }

        var selectionVisible = false
        for index in .shown where index == .selected do
            selectionVisible = true
        if not selectionVisible do
            .selected = Swag.U64.Max
        .previewAspect = .listingPreviewAspect()
        .holdsMedia    = false
        for index in .shown
        {
            let entry = &.entries[index]
            if isFilmFile(entry) or
               not entry.albumTrack.isEmpty() or
               (not entry.directory and albumAudio(entry.name))
            {
                .holdsMedia = true
                break
            }
        }

        let board = .listingBoard()

        var count: String
        switch .shown.count
        {
        case 0:  count = Format.toString(appStrings().explore_Count, 0)
        case 1:  count = appStrings().explore_OneItem
        default: count = Format.toString(appStrings().explore_Count, .shown.count)
        }

        // A homogeneous media folder can count in its own words. Forcing a board only changes
        // presentation; the count must still describe every item left on the page.
        if .shown.count > 1 and not .forced
        {
            var albums: Array'String
            var tracks, albumFolders, films: u64
            for index in .shown
            {
                let entry = &.entries[index]
                if isFilmFile(entry) do
                    films += 1
                if not entry.albumTrack.isEmpty()
                {
                    albumFolders += 1
                    continue
                }

                let kind = .theme().fileGlyph(entry.name, entry.directory, 16).index
                if kind == cast(s32, ThemeIcons.FileAudio)
                {
                    tracks += 1
                    var known = false
                    for one in albums where one[] == entry.music.title do
                        known = true
                    if not known do
                        albums.add(entry.music.title.isEmpty() ? entry.name : entry.music.title)
                }
            }

            if board == .Covers and albumFolders == .shown.count do
                count = Format.toString(appStrings().explore_Albums, albumFolders)
            elif board == .Covers and tracks == .shown.count do
                count = Format.toString("% · %", Format.toString(appStrings().explore_Albums, albums.count), Format.toString(appStrings().explore_Tracks, tracks))
            elif board == .Album and tracks == .shown.count do
                count = Format.toString(appStrings().explore_Tracks, tracks)
            elif board == .Posters and films == .shown.count do
                count = Format.toString(appStrings().explore_Films, films)
        }

        // A folder says what its files weigh; an archive what it weighs packed and what it will
        // weigh once extracted.
        if not .listing.isArchive and .shown.count
        {
            var weight = 0'u64
            for index in .shown where not .entries[index].directory do
                weight += .entries[index].size
            if weight do
                count = Format.toString("% · %", count, StrConv.toDisplaySize(weight))
        }

        if .listing.isArchive and .shown.count
        {
            let zip = &.listing.archive
            count = Format.toString(appStrings().explore_ArchiveSummary, count, StrConv.toDisplaySize(zip.compressedSize), StrConv.toDisplaySize(zip.uncompressedSize))
        }

        .setStatus(count)
        .list.setEmptyText(query.count or .kindFilter != .All ? appStrings().explore_NoMatches : appStrings().explore_Empty)

        .list.setVirtualCount(cast(u32, .shown.count))
        for index, row in .shown where index == .selected
        {
            .list.setFocusedIndex(cast(u32, row), ensureVisible: false)
            .list.selectLine(cast(u32, row))
            break
        }

        .grid.refreshLayout()
        .refreshQuietMenus()
        .prioritizeVisible()
        .window.teachHints(.isLocallyVisible())
    }

    private mtd fitNameColumn()
    {
        let width = .list.listView.paddedClientRect().width
        if width > 0 and .list.header.itemWidthForColumn(0) != width do
            .list.header.setItemWidthForColumn(0, width)
    }

    mtd setMode(mode: ExplorerMode)
    {
        if mode != .mode do
            .clearFileDrag()
        .mode = mode
        let namesOnly = .list.scrollWnd.flags.has(.DisableHorizontal)
        if mode == .Names and not namesOnly
        {
            .detailNameWidth = .list.header.itemWidthForColumn(0)
            .list.scrollWnd.updateFlags(.DisableHorizontal)
            .fitNameColumn()
        }
        elif mode != .Names and namesOnly
        {
            .list.header.setItemWidthForColumn(0, .detailNameWidth)
            .list.scrollWnd.updateFlags(remove: .DisableHorizontal)
        }
        .refreshQuietMenus()

        // Archive details keep their compression readings in a dedicated column.
        .grid.rows = mode == .Details and .listing.isArchive
        let rows = (mode == .Names or mode == .Details) and not .grid.rows
        .list.show(rows)
        .list.header.show(mode == .Details)
        .archiveHeader.show(.grid.rows)
        .scroll.show(not rows)
        .applyLayout()
        .fill()
    }

    mtd isThumbnailView()->bool => .mode != .Names and .mode != .Details

    private mtd clearFileDrag()
    {
        let source = .dragSource
        .dragSource = null
        .dragPath.clear()
        if source and source.mouseCapture() == source do
            source.releaseMouse()
    }

    // Leaves ordinary clicks to the list or grid. Capture lets the drag start even when the
    // first move beyond the desktop's threshold is already outside the source control.
    private mtd handleFileDrag(source: *Wnd, evt: *MouseEvent)->bool
    {
        if evt.kind == .Pressed and evt.button == .Left
        {
            .clearFileDrag()
            if .listing.isArchive do
                return false

            let row = source == .grid ? .grid.rowAt(source.surfaceToLocal(evt.surfacePos)) : cast(u64, .list.rowAt(evt.surfacePos))
            if row < .shown.count
            {
                let entry = &.entries[.shown[row]]
                if not entry.directory and not entry.path.isEmpty()
                {
                    .dragPath   = entry.path
                    .dragOrigin = evt.surfacePos
                    .dragSource = source
                    source.captureMouse()
                }
            }

            return false
        }

        if .dragSource != source do
            return false

        if evt.kind == .Released and evt.button == .Left
        {
            .clearFileDrag()
            return not source.surfaceRect().contains(evt.surfacePos)
        }

        if evt.kind != .Move do
            return false
        if source.mouseCapture() != source or not .app().mouse.isButtonPressed(.Left)
        {
            .clearFileDrag()
            return false
        }

        if not source.exceedsDragThreshold(.dragOrigin, evt.surfacePos) do
            return false

        var data: DragData
        data.addFile(.dragPath)
        .clearFileDrag()
        .draggingFile = true
        defer .draggingFile = false
        discard source.startDrag(&data, .Copy)
        return true
    }

    mtd suspend()
    {
        for preview in .previews
        {
            if preview.started and preview.generation == .generation and preview.index < .entries.count
            {
                if preview.online do
                    .entries[preview.index].onlinePending = true
                else do
                    .entries[preview.index].attempted = false
            }

            preview.task.cancel()
        }
    }

    mtd leave()
    {
        .suspend()
        .generation  += 1
        .pendingOpen = Swag.U64.Max
    }

    mtd displayPath(path: string)->string
    {
        for file in .temporaryFiles where file.file == path do
            return file.title
        return path
    }

    // Retains archive ancestry without the presentation spaces used by displayPath.
    // Path operations consume this name; filesystem operations still consume the temporary file.
    mtd logicalPath(path: string)->string
    {
        for file in .temporaryFiles where file.file == path do
            return file.path
        return path
    }

    // Called only after the foreground viewer has retired. Archive sources retained by navigation stay alive.
    mtd releasePreviews()
    {
        for index in reversed(.temporaryFiles.count)
        {
            let file     = &.temporaryFiles[index]
            var retained = .listing.path == file.file
            for location in .history.entries where Utf8.startsWith(location[], file.file) do
                retained = true
            if retained do
                continue
            catch File.delete(file.file)
            .temporaryFiles.removeAtOrdered(index)
        }
    }

    private mtd prioritizeVisible()
    {
        .grid.hovered = Swag.U64.Max
        let tiles = .isThumbnailView() or .grid.rows
        var range: #decltype(.grid.visibleRange())
        if tiles do
            range = .grid.visibleRange()
        for preview in .previews where preview.started and not preview.opening and preview.generation == .generation
        {
            var visible = not tiles and preview.index == .selected
            for row in range.first until range.end where .shown[row] == preview.index
            {
                visible = true
                break
            }

            if visible do
                continue

            if preview.index < .entries.count
                {
                    if preview.online do
                        .entries[preview.index].onlinePending = true
                    else do
                        .entries[preview.index].attempted = false
                }

                preview.generation = Swag.U64.Max
                preview.task.cancel()
        }

        .requestPreview()
    }

    mtd isSelected(index: u64)->bool =>
        .selectedFiles.isEmpty() ? .selected == index : .selectedFiles.contains(index)

    mtd selectionPaths()->Array'String
    {
        var result: #returntype
        if .listing.isArchive or not .window.workspace do
            return result
        let rows = .list.isLocallyVisible()
        for index, row in .shown where not .entries[index].directory
        {
            let selected = rows ? .list.isLineSelected(cast(u32, row)) : .isSelected(index)
            if selected do
                result.add(.entries[index].path)
        }
        return result
    }

    mtd openSelection(compare = false)
    {
        let paths = .selectionPaths()
        if paths.count > 1
        {
            .window.workspace!.openScene(paths.toSlice(), compare ? .SideBySide : .Auto, compare)
            return
        }
        .activate(.selected)
    }

    mtd activate(index: u64)
    {
        if .load.started or index >= .entries.count do
            return
        let entry = &.entries[index]
        if entry.directory
        {
            if not .isLocallyVisible() do
                .window.closeFile()
            if .listing.isArchive do
                .navigate(.listing.path, entry.path)
            else do
                .navigate(entry.path)
        }
        elif .listing.isArchive
        {
            .leave()
            .pendingOpen = index
            .requestPreview()
        }
        else
        {
            .window.resumeFile(entry.path, fromHistory: false)
        }
    }

    // Names the action opening the chosen item, in the sheet and in the lens alike: where it takes
    // a file up again, or only Open.
    mtd openActionName()->String
    {
        let entry = .selected < .entries.count ? &.entries[.selected] : null
        let point = entry and not entry.directory ? .window.resumePoint(entry.path) : null
        return point ? point.positionText() : String.from(appStrings().cmd_OpenChosen)
    }

    // Submit every useful visible preview; the runtime admits background work for the host.
    mtd requestPreview()
    {
        if .clearingCaches or .load.started or (.shown.isEmpty() and .pendingOpen == Swag.U64.Max) do
            return
        .refreshPreviewSettings()

        for preview in .previews where not preview.started
        {
            if not .startPreview(preview) do
                return
        }

        for
        {
            let preview = Memory.new'ExplorerPreview()
            .previews.add(preview)
            if not .startPreview(preview) do
                return
        }
    }

    mtd refreshPreviewSettings()
    {
        let settings = ThumbnailSettings.capture(.window,
                                                 localArtworkOnly: .artworkSource == .Local,
                                                 previewEpoch: .previewEpoch)
        if .previewSettings == settings do
            return

        // The first snapshot precedes all jobs; later changes retire every old publication.
        if not .previewSettings.isEmpty() do
            .retirePreviews()

        .previewSettings = settings
    }

    private mtd retirePreviews()
    {
        // Extracting an opened archive member does not depend on its thumbnail appearance.
        for preview in .previews
        {
            if preview.opening and preview.generation == .generation do
                preview.generation += 1
            else do
                preview.task.cancel()
        }

        .generation += 1
        .clearTextures()
        for &entry in .entries
        {
            entry.attempted     = false
            entry.onlinePending = false
            entry.movie         = {}
            entry.music         = {}
        }

        .showMediaInfo()
        .grid.invalidate()
    }

    // Returns the active slot for a tile, including work waiting for GUI publication.
    mtd previewSlot(index: u64)->u64
    {
        for preview, slot in .previews where preview.started and
                                             not preview.opening and
                                             preview.generation == .generation and
                                             preview.index == index do
            return slot
        return Swag.U64.Max
    }

    private mtd startPreview(preview: *ExplorerPreview)->bool
    {
        if .load.started or (not .isVisible() and .pendingOpen == Swag.U64.Max) do
            return false
        var wanted  = .pendingOpen
        var online  = false
        let opening = wanted != Swag.U64.Max
        if not opening
        {
            if .mode == .Names or .mode == .Details
            {
                if .selected >= .entries.count do
                    return false
                let selected = &.entries[.selected]
                var pluginIndex: u64
                let movie    = File.exists(selected.path) and
                               .window.index.namePlugin(selected.path, &pluginIndex) and
                               .window.index.plugins[pluginIndex].key == "video"
                let music = File.exists(selected.path) and albumAudio(selected.path)
                if (selected.directory and selected.albumTrack.isEmpty()) or
                   (selected.attempted and not selected.onlinePending) or
                   not (movie or music or .grid.rows) or
                   .previewSlot(.selected) != Swag.U64.Max do
                    return false
                wanted = .selected
                online = selected.onlinePending
            }
            else
            {
                let range = .grid.visibleRange()
                for row in Math.min(range.first, .shown.count) until Math.min(range.end, .shown.count)
                {
                    let index = .shown[row]
                    if index < .entries.count and
                       (not .entries[index].directory or not .entries[index].albumTrack.isEmpty() or (.grid.board == .Covers and .entries[index].children == Swag.U64.Max)) and
                       not .entries[index].attempted and
                       .previewSlot(index) == Swag.U64.Max
                    {
                        wanted = index
                        break
                    }
                }

                // Music keeps its local cover pass before online enrichment.
                if wanted == Swag.U64.Max
                {
                    for row in Math.min(range.first, .shown.count) until Math.min(range.end, .shown.count)
                    {
                        let index = .shown[row]
                        if index < .entries.count and
                           .entries[index].onlinePending and
                           .previewSlot(index) == Swag.U64.Max
                        {
                            wanted = index
                            online = true
                            break
                        }
                    }
                }
            }
        }

        if wanted >= .entries.count do
            return false
        if not opening and not online and .cached.count >= 128
        {
            let range = .grid.visibleRange()
            var evict = Swag.U64.Max
            for cached, position in .cached
            {
                var visible = false
                for row in Math.min(range.first, .shown.count) until Math.min(range.end, .shown.count) where .shown[row] == cached do
                    visible = true
                if not visible
                {
                    evict = position
                    break
                }
            }

            if evict == Swag.U64.Max do
                return false
            let old = .cached[evict]
            .app().renderer.removeTexture(&.entries[old].texture)
            .entries[old].attempted = false
            .cached.removeAtOrdered(evict)
            if old == .selected do
                .showMediaInfo()
        }

        let entry = &.entries[wanted]
        if .listing.isArchive and entry.archiveIndex >= .listing.archive.entries.count do
            return false
        .pendingOpen        = Swag.U64.Max
        preview.path        = entry.path
        preview.mediaFile   = entry.albumTrack
        preview.index       = wanted
        preview.generation  = .generation
        preview.opening     = opening
        preview.settings    = ThumbnailSettings.capture(.window, entry, localArtworkOnly: .artworkSource == .Local, previewEpoch: .previewEpoch)
        preview.archivePath = .listing.isArchive ? .listing.path : {}
        preview.privacy     = .listing.isArchive ? .window.privacy.policy(.listing.path) : {}
        if .listing.isArchive do
            preview.entry = .listing.archive.entries[entry.archiveIndex]
        if not opening and
           not online and
           preview.archivePath.isEmpty() and
           not albumAudio(entry.path) and
           Reader.canOpen(entry.path)
        {
            let settings = catch ThumbnailSettings.decode(preview.settings) orelse {}
            if onlinePreviewWanted(entry.path, &settings, entry.duration) do
                online = true
        }

        preview.online  = online
        entry.attempted = true
        if online do
            entry.onlinePending = false
        preview.start(me, durationHint: entry.duration)
        .grid.invalidate()
        return true
    }
}

impl IWnd for Explorer
{
    mtd impl onResizeEvent(_: *ResizeEvent) => .layoutTools()

    mtd impl onDragDropEvent(evt: *DragDropEvent)
    {
        // A drag released over its own listing must not bubble up and open the source file.
        evt.accepted = .draggingFile
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .watchTimer
        {
            evt.accepted = false
            return
        }

        if not .load.started and .load.pollChanges() do
            .reloadListing()
    }

    mtd impl onTaskEvent(evt: *TaskEvent)
    {
        if .cacheClear.claim(evt)
        {
            .cacheClear.wait()
            .clearingCaches = false
            .cacheRoot.clear()
            .setStatus("")
            for preview in .previews do
                Memory.delete(preview)
            .previews.clear()
            .previews.add(Memory.new'ExplorerPreview())
            if not .toast do
                .toast = Toast.create(me, "scope.explorer.toast")
            if .cacheClear.error.isEmpty() do
                .toast.show(appStrings().explore_CachesCleared)
            else do
                .toast.show(appStrings().explore_CacheClearFailed, .cacheClear.error, .Failure)
            .requestPreview()
            return
        }

        if .extraction.claim(evt)
        {
            .finishExtraction()
            return
        }

        if .load.claim(evt)
        {
            var listing: ExplorerListing
            let error = .load.finish(&listing)
            if .load.path != .requested or
               .load.folder != .requestedFolder or
               .load.sortColumn != .sortColumn or
               .load.descending != .descending or
               .refreshPending
            {
                .refreshPending = false
                .startListing()
                return
            }

            .updateWatchTimer()
            if not error.isEmpty()
            {
                .setStatus("")
                .failure.setReason(error)
                .list.hide()
                .archiveHeader.hide()
                .scroll.hide()
                .failure.show()
                return
            }

            if not .restoringView and
               Path.equals(.listing.path, listing.path) and
               .folder == .requestedFolder
            {
                .restoredView  = ExplorerFolderState.capture(me)
                .restoringView = true
            }

            .failure.hide()
            .listing = #move listing
            .folder  = .requestedFolder
            .publish()
        }
        else
        {
            for preview in .previews where preview.claim(evt)
            {
                preview.wait()
                .refreshPreviewSettings()
                .grid.invalidate()
                if preview.generation != .generation and not preview.temporary.isEmpty()
                {
                    catch File.delete(preview.temporary)
                    preview.temporary.clear()
                }

                if not preview.temporary.isEmpty()
                {
                    let title   = Format.toString("% / %", .displayPath(preview.archivePath), preview.path)
                    let path    = Format.toString("%/%", .logicalPath(preview.archivePath), preview.path)
                    let archive = String.from(.sourceArchivePath(preview.archivePath))
                    .window.privacy.inherit(preview.temporary, preview.archivePath)
                    .temporaryFiles.add(ExplorerTemporary{#move preview.temporary, title, path, archive})
                }

                if preview.generation == .generation
                {
                    if not preview.opening and preview.durationHint do
                        .entries[preview.index].duration = preview.durationHint
                    if not preview.opening and not preview.online do
                        .entries[preview.index].onlinePending = preview.needsOnline
                    if preview.index == .selected and not preview.error.isEmpty() do
                        .setStatus(preview.error)
                    if preview.opening
                    {
                        if preview.error.isEmpty() and not .temporaryFiles.isEmpty() do
                            .window.queueFile(.temporaryFiles.back().file, remember: false)
                        else do
                            .setStatus(preview.error)
                    }
                    elif preview.image.isValid() and (preview.online or not preview.needsOnline)
                    {
                        if .entries[preview.index].directory and not preview.mediaFile.isEmpty() do
                            .entries[preview.index].albumTrack = preview.mediaFile
                        let uploaded = .app().renderer.addImage(preview.image)
                        if not uploaded.isValid()
                        {
                            .requestPreview()
                            return
                        }

                        let replacing = .entries[preview.index].texture.isValid()
                        if not replacing and .cached.count >= 128
                        {
                            let old = .cached[0]
                            .app().renderer.removeTexture(&.entries[old].texture)
                            .entries[old].attempted = false
                            .cached.removeAtOrdered(0)
                            if old == .selected do
                                .showMediaInfo()
                        }

                        if replacing do
                            .app().renderer.removeTexture(&.entries[preview.index].texture)
                        .entries[preview.index].texture = uploaded
                        .entries[preview.index].framing = ThumbnailFraming.fromImage(&preview.image)
                        let duration = thumbnailDuration(&preview.image)
                        if duration or not preview.online do
                            .entries[preview.index].duration = duration
                        .entries[preview.index].movie = MovieSummary.fromImage(&preview.image)
                        let technical = MediaInfoData.fromVideoThumbnail(&preview.image)
                        if technical.rows.count do
                            .entries[preview.index].technical = #move technical
                        var music      = MusicSummary.fromImage(&preview.image)
                        let localMusic = &.entries[preview.index].music
                        if not localMusic.track.isEmpty() do
                            music.track = localMusic.track
                        if not localMusic.albumArtist.isEmpty() do
                            music.albumArtist = localMusic.albumArtist
                        if music.title.isEmpty() and
                           (not .entries[preview.index].albumTrack.isEmpty() or not localMusic.track.isEmpty())
                        {
                            music = .entries[preview.index].music
                            if music.title.isEmpty() do
                                music.title = .entries[preview.index].name
                        }

                        .entries[preview.index].music = #move music
                        if .selected == preview.index do
                            .showMediaInfo()
                        if not replacing do
                            .cached.add(preview.index)
                        if .grid.board == .Album or .grid.board == .Covers do
                            .grid.refreshLayout()
                        .grid.invalidate()
                    }
                }

                .requestPreview()
                .startCacheClearWhenIdle()
                return
            }

            evt.accepted = false
        }
    }

    mtd impl onDestroyEvent(_: *DestroyEvent)
    {
        .address.destroy()

        // A listing or an extraction still running would report its end to a window and an
        // application that are going away: both are waited for here, the listing told to stop.
        .load.task.cancel()
        .load.wait()
        .extraction.wait()

        for preview in .previews do
            preview.task.cancel()
        for preview in .previews
        {
            preview.wait()
            Memory.delete(preview)
        }

        .cacheClear.task.cancel()
        .cacheClear.wait()
        .clearTextures()
        for file in .temporaryFiles do
            catch File.delete(file.file)
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged
        {
            .retranslate()
            .fill()
        }

        .wnd.IWnd.onNotifyEvent(evt)
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind != .Pressed
        {
            evt.accepted = false
            return
        }

        switch evt.key
        {
        case .L where evt.modifiers.has(.Control): .address.beginEdit()
        case .D where evt.modifiers.has(.Alt):     .address.beginEdit()
        case .Left where evt.modifiers.has(.Alt):  .goBack()
        case .Right where evt.modifiers.has(.Alt): .goForward()
        case .Up where evt.modifiers.has(.Alt):    .goUp()
        case .Back:                                .goUp()
        case .P where evt.modifiers == .None:      .playChosen()
        default:                                   evt.accepted = false
        }
    }
}

// Reports whether `entry` is a film file: what the video reader opens, apart from album audio.
private func isFilmFile(entry: const *ExplorerEntry)->bool => not entry.directory and not albumAudio(entry.name) and Reader.canOpen(entry.name)

private struct ExplorerNameScroll
{
    row:     u64
    tick:    u64
    endTick: u64
    step:    u64
}

// A virtual tile viewport: one painted cell per visible file, independent of directory size.
struct ExplorerGrid
{
    using wnd:     Wnd
    late explorer: *Explorer
    columns:       u64        = 1
    cell:          Math.Point = {160, 152}
    hovered:       u64        = Swag.U64.Max
    spinners:      Array'(*Spinner)
    busy:          Array'bool     // Which spinners a visible tile claimed during the current paint.
    spinnerUse:    u64
    nameTimer:     *Timer?
    nameScrolls:   [2] ExplorerNameScroll     // At most the hovered and selected titles.
    rows:          bool     // Whether the entries stand one per line, as an archive lists them.
    posters:       bool     // Whether the tiles stand upright, as the posters of a folder of films.
    tile:          Math.Point = {160, 142}
    board:         ExplorerBoard
    places:        Array'Math.Rectangle     // Where each album track stands.
    contentHeight: f32
    albumCover:    Math.Rectangle
    albumText:     Math.Rectangle
    playButton:    *PushButton?
    shuffleButton: *PushButton?
}

impl ExplorerGrid
{
    // The air a cell keeps around its tile, the height of the name and of the mono line of what
    // is known of the item under its picture, and the weight of the ring around the chosen one.
    const CellInset = 12.0

    // The tiles: the air between two of them, the narrowest a tile gets and its height over its
    // width, upright for posters; and the room under a tile for its name and its facts.
    const Gap          = 24.0
    const TileWidth    = 160.0
    const TileAspect   = 3.0 / 4.0
    const PosterWidth  = 170.0
    const PosterAspect = 1.38

    // Reveal the whole name even when the overflow would take too long at one pixel per tick.
    const NameScrollInterval: Time.Duration = 50'ms
    const NameScrollMaxTicks = 100'u64

    // One album: the side of its cover, the air between the cover and the tracks, and the pitch of
    // a track.
    const CoverSide  = 280.0
    const AlbumGap   = 48.0
    const TrackPitch = 38.0
    const AlbumHead  = 156.0

    // Archive rows share their column bounds with the header above the viewport.
    const RowPitch         = 34.0
    const RatioWidth       = 64.0
    const ArchiveCellInset = 12.0

    // Reuses standard animated marks for every visible tile waiting for a final preview.
    mtd ensureSpinners(count: u64)
    {
        while .spinners.count < count
        {
            with let spinner = Spinner.create(me)
            {
                .backgroundStyle = .Transparent
                .hide()
                .hookOnEvent = func|grid = me|(_, evt)
                {
                    if evt is MouseEvent as mouse
                    {
                        grid.itf.onMouseEvent(mouse)
                        return true
                    }

                    return false
                }
            }

            .spinners.add(spinner)
        }

        .busy.resize(.spinners.count)
    }

    mtd rowAt(point: Math.Point)->u64
    {
        if .board == .Album
        {
            let at = point + .scrollPos
            for place, row in .places where place.width > 0 and place.contains(at) do
                return row
            return Swag.U64.Max
        }

        let local = point + .scrollPos - Math.Point{CellInset, CellInset}
        if local.x < 0 or local.y < 0 do
            return Swag.U64.Max
        let column = cast(u64, local.x / .cell.x)
        let line   = cast(u64, local.y / .cell.y)
        let row    = line * .columns + column
        if column >= .columns or
           row >= .explorer.shown.count or
           local.x - cast(f32, column) * .cell.x >= .cell.x - (.rows ? 0 : Gap) or
           local.y - cast(f32, line) * .cell.y >= .cell.y - (.rows ? 0 : Gap) do
            return Swag.U64.Max
        return row
    }

    mtd refreshLayout()
    {
        if .rows
        {
            .stopTimer(&.nameTimer)
            .board   = .Grid
            .posters = false
            .refreshAlbumButtons()
            .columns = 1
            .cell    = Math.Point{Math.max(.clientRect().width - 2 * CellInset, 0), RowPitch}
            .fitArchiveColumns()
            .explorer.scroll.setScrollSize(0, cast(f32, .explorer.shown.count) * RowPitch + 2 * CellInset)
            .invalidate()
            return
        }

        // Every tile has the same size and the grid fills the width of the page: as many columns
        // as the narrowest tile allows, the tiles sharing what is left. A folder of films stands
        // its posters upright; anything else on a tile a little wider than tall.
        .board   = .explorer.listingBoard()
        .posters = .board == .Posters
        .refreshAlbumButtons()
        if .board == .Album
        {
            .stopTimer(&.nameTimer)
            .layoutAlbum()
            return
        }

        let aspect = .posters ? PosterAspect :
                     (.board == .Covers ? 1.0 :
                      (.board == .Grid and .explorer.previewAspect == ExplorerFilmPreviewAspect ?
                       ExplorerFilmTileAspect : TileAspect))
        var narrowest = .posters ? PosterWidth : TileWidth
        switch .explorer.mode
        {
        case .Small: narrowest *= 0.75
        case .Large: narrowest *= 1.4
        case .Names, .Details, .Medium: break
        }

        let room = Math.max(.clientRect().width - 2 * CellInset, 1)
        .columns = Math.max(1'u64, cast(u64, (room + Gap) / (narrowest + Gap)))
        let width = Math.floor((room - Gap * cast(f32, .columns - 1)) / cast(f32, .columns))
        .tile = Math.Point{width, Math.round(width * cast(f32, aspect))}
        .cell = Math.Point{width + Gap, .tile.y + (.explorer.showTileCaption ? FileTile.captionHeight(me) : 0) + Gap}
        let rows = (.explorer.shown.count + .columns - 1) / .columns
        .explorer.scroll.setScrollSize(0, cast(f32, rows) * .cell.y + 2 * CellInset)
        .invalidate()
        .startNameScroll()
    }

    mtd fitArchiveColumns()
    {
        let header = .explorer.archiveHeader
        let room   = Math.max(.cell.x - 3 * .themeMetrics().header_Separator, 0)
        // Give a narrow cell the complete name and size first, then the date and compression.
        let size   = room >= 176 ? Math.clamp(Math.floor(room * 0.18), 80.0, 96.0) : 0
        let date   = room >= 320 ? Math.clamp(Math.floor(room * 0.24), 112.0, 136.0) : 0
        let ratio  = room >= 480 ? Math.min(124.0, Math.floor(room * 0.23)) : 0
        header.setItemWidth(0, room - ratio - size - date)
        header.setItemWidth(1, ratio)
        header.setItemWidth(2, size)
        header.setItemWidth(3, date)
    }

    // Lays one album out: its cover at the left, then at its right its title over its tracks, one
    // per line.
    mtd layoutAlbum()
    {
        let explorer = .explorer
        let width    = Math.max(.clientRect().width - 2 * CellInset, 1)
        let stacked  = width < CoverSide * 2 + AlbumGap
        let cover    = Math.min(stacked ? TileWidth : CoverSide, width)
        .albumCover = Math.Rectangle{CellInset, CellInset, cover, cover}
        let gap   = stacked ? .themeMetrics().floating_Inset : AlbumGap
        let textX = CellInset + cover + gap
        .albumText = Math.Rectangle{textX, CellInset, Math.max(width - cover - gap, 1), AlbumHead}
        .places.clear()
        .places.resize(explorer.shown.count)
        .columns = 1
        .cell    = Math.Point{stacked ? width : .albumText.width, TrackPitch}
        var y = stacked ? Math.max(.albumText.bottom(), .albumCover.bottom() + .themeMetrics().btnPush_Height + AlbumGap) : .albumText.bottom()
        for index, at in explorer.shown
        {
            let entry = &explorer.entries[index]
            if entry.directory or .theme().fileGlyph(entry.name, false, 16).index != cast(s32, ThemeIcons.FileAudio) do
                continue
            .places[at] = Math.Rectangle{stacked ? CellInset : .albumText.x, y, .cell.x, TrackPitch - 4}
            y += TrackPitch
        }

        .contentHeight = Math.max(y, CellInset + CoverSide + 80) + CellInset
        explorer.scroll.setScrollSize(0, .contentHeight)
        .refreshAlbumButtons()
        .invalidate()
    }

    // Shows Play and Shuffle under the cover of an album, and hides them otherwise.
    mtd refreshAlbumButtons()
    {
        let album = .board == .Album
        if album and not .playButton
        {
            let play    = PushButton.create(me, appStrings().explore_Play, {}, ViewerCommands.AlbumPlay, .Strong)
            let shuffle = PushButton.create(me, appStrings().explore_Shuffle, {}, ViewerCommands.AlbumShuffle)

            .playButton    = play
            .shuffleButton = shuffle
        }

        if not .playButton do
            return
        let height = .themeMetrics().btnPush_Height
        let top    = .albumCover.bottom() + .themeMetrics().infoSheet_BlockGap
        .playButton.setPosition(Math.Rectangle{CellInset, top, 96, height})
        .shuffleButton!.setPosition(Math.Rectangle{CellInset + 106, top, 96, height})
        .playButton.setText(appStrings().explore_Play)
        .shuffleButton.setText(appStrings().explore_Shuffle)
        .playButton.show(album)
        .shuffleButton.show(album)
    }

    // Returns where the tile of `row` stands in the grid.
    mtd tileRect(row: u64)->Math.Rectangle
    {
        if .board == .Album and row < .places.count do
            return .places[row]
        return Math.Rectangle{CellInset + cast(f32, row % .columns) * .cell.x,
                              CellInset + cast(f32, row / .columns) * .cell.y, .tile.x, .tile.y}
    }

    // A tile's caption and selection ring reach outside its image rectangle.
    private mtd tilePaintRect(tile: Math.Rectangle)->Math.Rectangle
    {
        var rect = tile
        if .explorer.showTileCaption do
            rect.height += FileTile.captionHeight(me)
        let metrics = .themeMetrics()

        // Keep the selection stroke and its antialiased fringe inside the repaint.
        rect.inflate(metrics.fileTile_RingGap + metrics.fileTile_RingWidth * 2 + 2)
        return rect
    }

    private mtd invalidateTile(row: u64)
    {
        if row >= .explorer.shown.count do
            return
        var rect = .tilePaintRect(.tileRect(row))
        rect.offset(-.scrollPos.x, -.scrollPos.y)
        rect.intersect(.clientRect())
        .invalidateRect(rect)
    }

    // The virtual grid supplies data and custom document previews; Gui owns the tile rendering.
    mtd paintTile(painter: *Painter, row: u64, tile: Math.Rectangle)
    {
        let index = .explorer.shown[row]
        let entry = &.explorer.entries[index]
        let glyph = .theme().fileGlyph(entry.name, entry.directory, 32)
        let name  = safeMediaText(.tileName(entry))
        let facts = .reading(entry)
        let size  = .sizeText(entry)
        let hovered = .hovered == row
        let badge   = hovered and entry.duration and not .explorer.showTileCaption and not .posters ? formatDuration(entry.duration) : String{}
        let ext   = entry.directory ? "" : (Path.extension(entry.name) orelse "")
        var content: FileTile.Content
        content.texture     = entry.texture
        content.icon        = glyph
        if .explorer.showTileCaption do
            content.captionIcon = .explorer.entryIcon(index, .themeMetrics().chevron_Size)
        content.name        = name
        content.facts       = facts
        content.detail      = size
        content.badge       = badge
        content.placeholder = ext
        var options: FileTile.Options
        options.fit         = .Contain
        options.hovered     = hovered
        options.selected    = .explorer.isSelected(index)
        options.showCaption = .explorer.showTileCaption
        for scroll in .nameScrolls where scroll.endTick and scroll.row == row do
            options.nameTick = scroll.tick
        options.previewPainter = func|grid = me, index|(_, painter, tile)->bool
        {
            let entry = &grid.explorer.entries[index]
            let glyph = grid.theme().fileGlyph(entry.name, entry.directory, 16)
            if entry.texture.isValid() and
               (entry.texture.width > 1 or entry.texture.height > 1 or glyph.index == cast(s32, ThemeIcons.FileImage) or glyph.index == cast(s32, ThemeIcons.FileVideo))
            {
                let mode = grid.explorer.thumbnailCrop
                let relativeAspect = cast(f32, entry.texture.width) * tile.height /
                                     (cast(f32, entry.texture.height) * tile.width)
                // Automatic framing keeps the whole image when filling would discard over two thirds.
                let severeCrop = relativeAspect > 3 or relativeAspect < 1.0'f32 / 3
                if mode == .None or (mode != .Center and severeCrop) do
                    return false
                let shape: ThumbnailShape = grid.posters ? .Poster :
                                            (grid.board == .Covers ? .Square :
                                             (grid.explorer.previewAspect == ExplorerFilmPreviewAspect ? .Wide : .Grid))
                entry.framing.paint(grid, painter, entry.texture, tile, shape, mode)
                return true
            }

            if grid.board == .Grid and grid.paintCard(painter, tile, entry) do
                return true
            if grid.board == .Covers and entry.texture.isValid() and entry.texture.width <= 1
            {
                grid.paintBlankCover(painter, tile)
                return true
            }

            return false
        }

        FileTile.paint(me, painter, tile, &content, options)

        // A file left in its middle carries how far it was read along the foot of its picture.
        if not entry.directory
        {
            if let point = .explorer.window.resumePoint(entry.path)
            {
                let emphasized = hovered or options.selected
                let thread = emphasized ? .themeMetrics().fileTile_RingWidth : 1.0
                let ink    = emphasized ? .themeColors().arc : .themeColors().arc.withAlphaF32(0.6)
                painter.fillRect(Math.Rectangle{tile.x, tile.bottom() - thread, Math.round(tile.width * point.progress), thread}, ink)
            }
        }
    }

    private mtd positionTileSpinner(index: u64, tile: Math.Rectangle)
    {
        let entry = &.explorer.entries[index]
        let slot  = .explorer.previewSlot(index)

        // Keep the generic tile under the spinner until a local image or online artwork is ready.
        // A queued online music pass has no worker slot yet, but is still busy.
        let eligible = not entry.path.isEmpty() and
                       (not entry.directory or not entry.albumTrack.isEmpty() or (.board == .Covers and entry.children == Swag.U64.Max))
        if not entry.texture.isValid() and
           (slot != Swag.U64.Max or entry.onlinePending or (eligible and not entry.attempted))
        {
            let metrics = .themeMetrics()
            let size    = metrics.spinner_Size
            let spinner = .spinners[.spinnerUse]
            spinner.setPosition(Math.Rectangle{tile.right() - size - metrics.fileTile_Inset,
                                               tile.y + metrics.fileTile_Inset,
                                               size, size},
                                computeLayout: false)
            .busy[.spinnerUse] = true
            .spinnerUse        += 1
        }
    }

    // A missing album image stays a neutral sleeve, never a byte-map page masquerading as art.
    mtd paintBlankCover(painter: *Painter, tile: Math.Rectangle)
    {
        let colors = .themeColors()
        let radius = Math.max(12.0, Math.min(tile.width, tile.height) * 0.32)
        let center = Math.Point{tile.horzCenter(), tile.vertCenter()}
        painter.drawCircle(center.x, center.y, radius, colors.faintText, 1.5)
        painter.drawCircle(center.x, center.y, radius * 0.68, colors.line)
        painter.fillCircle(center.x, center.y, 5, colors.softText)
    }

    // Draws what a file of the mixed board is, as its picture shows it, and returns whether it
    // did: a PDF its first page on a paper card, code its first lines in mono, Markdown its
    // heading over its lines, a font "Aa".
    mtd paintCard(painter: *Painter, tile: Math.Rectangle, entry: const *ExplorerEntry)->bool
    {
        let colors = .themeColors()
        let ext    = Path.lowercaseExtension(entry.name)
        if ext == ".pdf"
        {
            // A page standing on the tile, with the shadow of paper.
            let height = tile.height - 24
            let width  = Math.round(height * 0.72)
            let page   = Math.Rectangle{Math.round(tile.horzCenter() - width * 0.5), tile.y + 12, width, height}
            .theme().drawFloatingShadow(painter, page, 2)
            painter.fillRoundRect(page, 2, 2, Color.fromArgb(Argb.White))
            if entry.texture.isValid()
            {
                var room = page
                room.inflate(-2)
                painter.fillRect(room, Brush.createTexture(entry.texture))
            }
            else
            {
                let ink  = Color.fromArgb(0xFF1A1A1E)
                let rule = Color.fromArgb(0xFFDADAD6)
                let x    = page.x + 10
                painter.fillRect(Math.Rectangle{x, page.y + 14, width * 0.45, 6}, ink)
                for i in 4 do
                    painter.fillRect(Math.Rectangle{x, page.y + 30 + cast(f32, i) * 7, (width - 20) * (i == 3 ? 0.6 : 1.0), 2}, rule)
                painter.fillRect(Math.Rectangle{x, page.y + 66, width - 20, 28}, Color.fromArgb(0xFFEAE8E4))
            }

            return true
        }

        if not entry.excerpt.isEmpty() and (ext == ".md" or ext == ".markdown")
        {
            // The first heading in bold, then the lines under it as rules, the next heading in soft.
            let bold     = .theme().createDefaultFont(13, .Bold)
            let small    = .theme().createDefaultFont(10, .Bold)
            var y        = tile.y + 22
            var headings = 0'u64
            for line in Tokenize.split(entry.excerpt, '\n'rune)
            {
                if y > tile.bottom() - 16 do
                    break
                if line.count and line[0] == '#'
                {
                    var at = 0'u64
                    while at < line.count and (line[at] == '#' or line[at] == ' ') do
                        at += 1
                    let font = headings == 0 ? bold : small
                    painter.pushClippingRect(Math.Rectangle{tile.x + 18, tile.y, tile.width - 36, tile.height})
                    painter.drawString(tile.x + 18, font.opticalLineTop(y), line[at to], font, headings == 0 ? colors.text : colors.softText)
                    painter.popClippingRect()
                    headings += 1
                    y        += 18
                }
                elif line.count
                {
                    let width = Math.min(cast(f32, line.count) * 3.0, tile.width - 36)
                    painter.fillRect(Math.Rectangle{tile.x + 18, y - 1, width, 2}, colors.line)
                    y += 8
                }
            }

            return true
        }

        if not entry.excerpt.isEmpty()
        {
            // The first lines in mono, a keyword in Arc.
            let mono = .theme().createDefaultFontFs(10)
            var y    = tile.y + 22
            painter.pushClippingRect(Math.Rectangle{tile.x + 14, tile.y + 8, tile.width - 22, tile.height - 16})
            for line in Tokenize.split(entry.excerpt, '\n'rune)
            {
                if y > tile.bottom() - 12 do
                    break
                var indent = 0'u64
                while indent < line.count and (line[indent] == ' ' or line[indent] == '\t') do
                    indent += 1
                var word = indent
                while word < line.count and Latin1.isLetter(line[word]) do
                    word += 1
                let x       = tile.x + 16 + cast(f32, indent) * 3.5
                let keyword = isCardKeyword(line[indent until word])
                painter.drawString(x, mono.opticalLineTop(y), line[indent until word], mono, keyword ? colors.arc : colors.softText)
                let used = Painter.measureString(line[indent until word], mono).width
                painter.drawString(x + used, mono.opticalLineTop(y), line[word to], mono, colors.softText)
                y += 14
            }

            painter.popClippingRect()
            return true
        }

        if ext == ".ttf" or ext == ".otf"
        {
            let font = .theme().createDefaultFont(32, .Bold)
            let text = "Aa"
            let size = Painter.measureString(text, font)
            painter.drawString(Math.round(tile.horzCenter() - size.width * 0.5), font.opticalLineTop(tile.vertCenter()), text, font, colors.softText)
            return true
        }

        return false
    }

    // Returns the same title the tile paints: a catalogue title when the board has one, otherwise
    // the file name.
    mtd tileName(entry: const *ExplorerEntry)->String
    {
        if .posters and entry.movie.title.length do
            return entry.movie.title
        if .board == .Covers and entry.music.title.length do
            return entry.music.title
        return entry.name
    }

    // Paints one album: its cover at the left, then its kind and year, its title, who made it and
    // its facts over its tracks, each a number, a title and a length, the chosen one on the Arc
    // ground led by ▶.
    mtd paintAlbum(painter: *Painter)
    {
        let explorer = .explorer
        let colors   = .themeColors()
        let metrics  = .themeMetrics()
        let radius   = metrics.corner_Control
        let mono     = .theme().createDefaultFontFs(12)
        let body     = .theme().createDefaultFont(15)
        painter.setAntialiased(true)

        // The cover is the picture of the first track that has one.
        var cover: const *ExplorerEntry?
        var first: const *ExplorerEntry?
        var tracks, seconds, bytes: u64
        for index, at in explorer.shown where .places[at].height > 0
        {
            let entry = &explorer.entries[index]
            if not first do
                first = entry
            if not cover and entry.texture.isValid() and entry.texture.width > 1 do
                cover = entry
            tracks  += 1
            seconds += entry.duration
            bytes   += entry.size
        }

        let coverRect = .albumCover
        painter.fillRoundRect(coverRect, radius, radius, colors.raised)
        if cover and cover.texture.width > 1
        {
            if explorer.thumbnailCrop == .None
            {
                let content = FileTile.Content{texture: cover.texture}
                FileTile.paint(me, painter, coverRect, &content, {fit: .Contain, showCaption: false})
            }
            else
            {
                cover.framing.paint(me, painter, cover.texture, coverRect, .Square, explorer.thumbnailCrop)
            }
        }
        else
        {
            .paintBlankCover(painter, coverRect)
        }

        if not first do
            return
        let left  = .albumText.x
        let top   = .albumText.y
        let texts = appStrings()
        var kind  = String.from(texts.explore_Album)
        if first.music.date.length >= 4 do
            kind = Format.toString("% · %", kind, first.music.date.toString()[0 until 4])
        painter.pushClippingRect(.albumText)
        painter.drawString(left, mono.opticalLineTop(top + 8), String.toUpper(kind.toString(), .Unicode), mono, colors.faintText)

        var title     = first.music.title.length ? String.from(first.music.title) : explorer.locationName()
        var titleFont = .theme().createDefaultFont(Explorer.TitleFontSize, .Bold)
        if Painter.measureString(title, titleFont).width > .albumText.width do
            titleFont = .theme().createDefaultFont(Explorer.MinTitleFontSize, .Bold)
        painter.drawString(left, titleFont.opticalLineTop(top + 48), title, titleFont, colors.text)
        if first.music.artist.length do
            painter.drawString(left, body.opticalLineTop(top + 86), first.music.artist, body, colors.softText)

        var facts = Format.toString(texts.explore_Tracks, tracks)
        if seconds
        {
            if seconds >= 3600 do
                facts = Format.toString("% · %", facts, Format.toString(texts.explore_Length, seconds / 3600, Format.toString("%{02}", (seconds / 60) % 60)))
            else do
                facts = Format.toString("% · % min", facts, (seconds + 30) / 60)
        }

        if bytes do
            facts = Format.toString("% · %", facts, StrConv.toDisplaySize(bytes))
        painter.drawString(left, mono.opticalLineTop(top + 114), facts, mono, colors.faintText)

        painter.popClippingRect()

        // The tracks.
        var number = 0'u64
        for index, at in explorer.shown
        {
            let place = .places[at]
            if place.height <= 0 do
                continue
            number += 1
            let entry   = &explorer.entries[index]
            let chosen  = explorer.isSelected(index)
            let centerY = place.vertCenter()
            if chosen do
                painter.fillRoundRect(place, radius, radius, colors.selection)
            elif .hovered == at do
                painter.fillRoundRect(place, radius, radius, colors.raised)

            let ink   = chosen ? colors.arc : colors.text
            let label = Format.toString("%", number)
            painter.drawString(place.x + 12, mono.opticalLineTop(centerY), label, mono, colors.faintText)

            let length      = entry.duration ? formatDuration(entry.duration) : String.from("")
            let lengthWidth = Painter.measureString(length, mono).width
            painter.drawString(place.right() - 12 - lengthWidth, mono.opticalLineTop(centerY), length, mono, colors.faintText)
            painter.pushClippingRect(Math.Rectangle{place.x + 48, place.y, Math.max(place.width - 48 - lengthWidth - 32, 0), place.height})
            painter.drawString(place.x + 48, body.opticalLineTop(centerY), trackTitle(entry.name), body, ink)
            painter.popClippingRect()
        }
    }

    // Returns what a file weighs, written at the right of its facts; nothing for a folder.
    mtd sizeText(entry: const *ExplorerEntry)->String
    {
        if entry.directory or not entry.size or .posters or .board == .Covers do
            return {}
        return StrConv.toDisplaySize(entry.size)
    }

    // Paints the entries `first` until `end` as rows: the glyph, the name, a thin Arc bar of how
    // much the member packed, the size and the date in mono, a folder its count instead.
    mtd paintRows(painter: *Painter, first, end: u64)
    {
        let explorer   = .explorer
        let header     = explorer.archiveHeader
        let colors     = .themeColors()
        let metrics    = .themeMetrics()
        let body       = .theme().createDefaultFont(14)
        let mono       = .theme().createDefaultFontFs(11)
        let nameRight  = header.itemPositionAt(0) + header.itemWidthAt(0)
        let ratioX     = header.itemPositionAt(1)
        let ratioRoom  = Math.max(header.itemWidthAt(1) - 2 * ArchiveCellInset, 0)
        let ratioWidth = Math.min(RatioWidth, ratioRoom)
        let ratioRight = ratioX + header.itemWidthAt(1) - ArchiveCellInset
        let sizeX      = header.itemPositionAt(2)
        let dateX      = header.itemPositionAt(3)
        let sizeWidth  = header.itemWidthAt(2)
        let dateWidth  = header.itemWidthAt(3)
        painter.setAntialiased(true)
        for row in first until end
        {
            let index   = explorer.shown[row]
            let entry   = &explorer.entries[index]
            let rect    = Math.Rectangle{CellInset, CellInset + cast(f32, row) * .cell.y, .cell.x, .cell.y}
            let centerY = rect.vertCenter()
            if explorer.isSelected(index) do
                painter.fillRoundRect(rect, metrics.corner_Control, metrics.corner_Control, colors.selection)
            elif .hovered == row do
                painter.fillRoundRect(rect, metrics.corner_Control, metrics.corner_Control, colors.raised)

            let glyph    = explorer.entryIcon(index, metrics.menuPopup_IconSize)
            let glyphInk = explorer.isSelected(index) ? colors.arc : colors.softText
            glyph.paint(painter, rect.x + ArchiveCellInset, Math.round(centerY - glyph.sizeY * 0.5), glyphInk)

            let nameX = rect.x + 36
            painter.pushClippingRect({nameX, rect.y, Math.max(nameRight - nameX - ArchiveCellInset, 0), rect.height})
            painter.drawString(nameX, body.opticalLineTop(centerY), entry.name, body, colors.text)
            painter.popClippingRect()

            // The date as briefly as a list reads it: the time today, the day this year, the date before.
            let date      = entry.when.year ? explorerFileTime(entry.when, Time.DateTime.now(), explorer.window.language) : String.from("")
            let lineY     = mono.opticalLineTop(centerY)
            let dateRight = dateX + dateWidth - ArchiveCellInset
            painter.pushClippingRect({dateX, rect.y, dateWidth, rect.height})
            painter.drawString(dateRight - Painter.measureStringSnapped(date, mono, deviceScale: .deviceScale()), lineY, date, mono, colors.faintText)
            painter.popClippingRect()

            var size: String
            if entry.directory
            {
                let children = explorer.listing.isArchive ? explorer.listing.children(entry.path).count : 0
                size = children == 1 ? String.from(appStrings().explore_OneItem) : Format.toString(appStrings().explore_Count, children)
            }
            else
            {
                size = StrConv.toDisplaySize(entry.size)
                if ratioWidth >= 3 and entry.archiveIndex < explorer.listing.archive.entries.count
                {
                    let member = &explorer.listing.archive.entries[entry.archiveIndex]

                    // The bar measures what packing saved: a stored member keeps an empty track, so a
                    // full bar never reads as a member that did not pack at all.
                    if member.uncompressedSize
                    {
                        let saved = 1 - Math.clamp(cast(f32, member.compressedSize) / cast(f32, member.uncompressedSize), 0, 1)
                        let track = Math.Rectangle{ratioRight - ratioWidth, Math.round(centerY - 1.5), ratioWidth, 3}
                        let fill  = Math.round(ratioWidth * saved)
                        painter.fillRoundRect(track, 1.5, 1.5, colors.raised)
                        if fill >= 1 do
                            painter.fillRoundRect(Math.Rectangle{track.x, track.y, Math.max(fill, 3), 3}, 1.5, 1.5, colors.arc)
                    }
                }
            }

            let sizeRight = sizeX + sizeWidth - ArchiveCellInset
            painter.pushClippingRect({sizeX, rect.y, sizeWidth, rect.height})
            painter.drawString(sizeRight - Painter.measureStringSnapped(size, mono, deviceScale: .deviceScale()), lineY, size, mono, colors.faintText)
            painter.popClippingRect()
        }
    }

    // Returns the facts written under the name of a tile, at the left: the year and length of a
    // film, the length of anything else that plays, how many items a folder holds.
    mtd reading(entry: const *ExplorerEntry)->String
    {
        var result: #returntype
        if .board == .Covers and not entry.albumTrack.isEmpty()
        {
            result = entry.music.artist
            if entry.music.date.length >= 4
            {
                if result.length do
                    result += " · "
                result += entry.music.date.toString()[0 until 4]
            }

            return result
        }

        if entry.directory
        {
            if entry.children == 1 do
                result = String.from(appStrings().explore_OneItem)
            elif entry.children != Swag.U64.Max do
                result = Format.toString(appStrings().explore_Count, entry.children)
            return result
        }

        // A cover says who made the album and when.
        if .board == .Covers and entry.music.title.length
        {
            result = entry.music.artist
            if entry.music.date.length >= 4
            {
                if result.length do
                    result += " · "
                result += entry.music.date.toString()[0 until 4]
            }

            return result
        }

        // What a file measures: a picture its size, a document its pages, code its lines,
        // Markdown its sections, a font its face.
        let texts = appStrings()
        if entry.width and entry.height do
            return Format.toString("% × %", entry.width, entry.height)
        if entry.pages do
            return entry.pages == 1 ? String.from(texts.explore_OnePage) : Format.toString(texts.explore_Pages, entry.pages)
        if entry.sections do
            return Format.toString(texts.explore_Sections, entry.sections)
        if entry.lines do
            return Format.toString(texts.explore_Lines, entry.lines)
        if not entry.face.isEmpty() do
            return String.from(entry.face)
        if entry.members do
            return Format.toString(texts.explore_Files, entry.members)

        if not entry.movie.date.isEmpty() do
            result = entry.movie.date.toString()[0 until Math.min(entry.movie.date.length, 4'u64)]
        if entry.duration
        {
            if not result.isEmpty() do
                result += " · "

            // A film is as long as its hours and minutes, the way a programme lists it.
            if .posters and entry.duration >= 3600 do
                result += Format.toString(appStrings().explore_Length, entry.duration / 3600, Format.toString("%{02}", (entry.duration / 60) % 60))
            else do
                result += formatDuration(entry.duration)
        }

        return result
    }

    mtd visibleRange()->{first: u64, end: u64}
    {
        if .board == .Album
        {
            let top    = .scrollPos.y
            let bottom = top + .clientRect().height
            var first  = Swag.U64.Max
            var end    = 0'u64
            for place, row in .places where place.height > 0 and place.bottom() >= top and place.y <= bottom
            {
                first = Math.min(first, row)
                end   = row + 1
            }

            if first == Swag.U64.Max do
                return {first: 0, end: 0}
            return {first: first, end: end}
        }

        let first = cast(u64, Math.max(0.0, .scrollPos.y - CellInset) / .cell.y) * .columns
        let rows  = cast(u64, Math.max(0.0, .clientRect().height) / .cell.y) + 2
        return {first: Math.min(first, .explorer.shown.count), end: Math.min(first + rows * .columns, .explorer.shown.count)}
    }

    private mtd nameScrollRect(row: u64)->Math.Rectangle
    {
        let tile = .tileRect(row)
        let rect = Math.Rectangle{tile.x - .scrollPos.x, tile.bottom() - .scrollPos.y,
                                  tile.width, FileTile.captionHeight(me)}
        return Math.Rectangle.intersect(rect, .clientRect())
    }

    mtd startNameScroll()
    {
        .stopTimer(&.nameTimer)
        for scroll in .nameScrolls where scroll.endTick and scroll.tick do
            .invalidateRect(.nameScrollRect(scroll.row))
        Swag.init(&.nameScrolls, 1)
        if .rows or .board == .Album or not .isVisible() or .app().isReducedMotion() do
            return

        let range = .visibleRange()
        var count = 0'u64
        for row in range.first until range.end
        {
            let index = .explorer.shown[row]
            if (row != .hovered and index != .explorer.selected) or .nameScrollRect(row).isEmpty() do
                continue
            let name = safeMediaText(.tileName(&.explorer.entries[index]))
            let end  = FileTile.nameScrollTicks(me, name, .tile.x, .explorer.entryIcon(index, .themeMetrics().chevron_Size))
            if not end do
                continue

            .nameScrolls[count] = {row: row, endTick: end, step: (end + NameScrollMaxTicks - 1) / NameScrollMaxTicks}
            count += 1
        }

        if count do
            .nameTimer = .addTimer(NameScrollInterval)
    }

    mtd select(row: u64, modifiers = Input.KeyModifiers.None)
    {
        if row >= .explorer.shown.count do
            return
        let explorer = .explorer
        let entry = explorer.shown[row]
        if explorer.window.workspace and not explorer.listing.isArchive and not explorer.entries[entry].directory and
           (modifiers.has(.Control) or modifiers.has(.Shift))
        {
            let before = explorer.selected
            if explorer.selectedFiles.isEmpty() and before < explorer.entries.count and not explorer.entries[before].directory do
                explorer.selectedFiles.add(before)
            if modifiers.has(.Shift)
            {
                var anchor = row
                for index, slot in explorer.shown where index == before do
                    anchor = slot
                explorer.selectedFiles.clear()
                for slot in Math.min(row, anchor) to Math.max(row, anchor)
                {
                    let index = explorer.shown[slot]
                    if not explorer.entries[index].directory do
                        explorer.selectedFiles.add(index)
                }
            }
            elif explorer.selectedFiles.contains(entry)
            {
                explorer.selectedFiles.remove(entry)
            }
            else
            {
                explorer.selectedFiles.add(entry)
            }

            explorer.selected = explorer.selectedFiles.isEmpty() ? Swag.U64.Max : explorer.selectedFiles.back()
        }
        else
        {
            explorer.selectedFiles.clear()
            explorer.selected = entry
        }
        .explorer.showMediaInfo()
        if .rows do
            .explorer.requestPreview()
        let place = .tileRect(row)
        let top   = .rows ? CellInset + cast(f32, row) * .cell.y : place.y - CellInset
        let reach = .rows ? .cell.y : place.height + (.board == .Album ? 0 : FileTile.captionHeight(me) + Gap)
        if top < .scrollPos.y do
            .explorer.scroll.setScrollPos(0, top)
        elif top + reach > .scrollPos.y + .clientRect().height do
            .explorer.scroll.setScrollPos(0, top + reach - .clientRect().height)
        .startNameScroll()
        .invalidate()
    }
}

impl IWnd for ExplorerGrid
{
    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .nameTimer do
            return
        if not .isVisible() or .surface!.isMinimized or .app().isReducedMotion()
        {
            Swag.init(&.nameScrolls, 1)
            .stopTimer(&.nameTimer)
            return
        }

        var moving = false
        for &scroll in .nameScrolls where scroll.endTick
        {
            let rect = .nameScrollRect(scroll.row)
            scroll.tick += scroll.step
            let active = scroll.row < .explorer.shown.count and
                         (scroll.row == .hovered or .explorer.shown[scroll.row] == .explorer.selected)
            if not active or rect.isEmpty() or scroll.tick >= scroll.endTick do
                scroll.endTick = 0
            else do
                moving = true
            .invalidateRect(rect)
        }

        if not moving do
            .stopTimer(&.nameTimer)
    }

    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        if .explorer != null
        {
            .refreshLayout()
            if .isVisible() do
                .explorer.prioritizeVisible()
        }
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let range   = .visibleRange()
        if .explorer.shown.isEmpty()
        {
            let filtered = .explorer.filter.text().count or .explorer.kindFilter != .All
            let text     = filtered ? appStrings().explore_NoMatches : appStrings().explore_Empty
            let font = unwrap .font().regular
            let x    = Math.max(CellInset, (.clientRect().width - Painter.measureString(text, font).width) * 0.5)

            // The sentence answers the filter, so it stands under the find bar floating over
            // the page rather than behind it.
            let inset = .themeMetrics().floating_Inset
            var y     = inset * 2
            let bar   = .explorer.window.searchBar
            if bar.isLocallyVisible()
            {
                let below = .surfaceToLocal(Math.Point{0, bar.surfaceRect().bottom()}).y + .scrollPos.y
                y = Math.max(y, below + inset * 1.5)
            }

            painter.drawString(x, font.opticalLineTop(y), text, font, .themeColors().faintText)
            for spinner in .spinners do
                spinner.hide()
            return
        }

        if .rows
        {
            .paintRows(painter, range.first, range.end)
            for spinner in .spinners do
                spinner.hide()
            return
        }

        .ensureSpinners(range.end - range.first)
        .busy.fill(false)
        .spinnerUse = 0
        if .board == .Album
        {
            .paintAlbum(painter)
        }
        else
        {
            let transform = painter.transform()
            var clip      = painter.clippingRect()
            clip.offset(-transform.tx, -transform.ty)
            for row in range.first until range.end
            {
                let tile = .tileRect(row)
                if .tilePaintRect(tile).intersects(clip) do
                    .paintTile(painter, row, tile)
                .positionTileSpinner(.explorer.shown[row], tile)
            }
        }

        for spinner, slot in .spinners do
            spinner.show(.busy[slot])
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if .explorer.handleFileDrag(me, evt) do
            return

        if evt.kind == .Move or evt.kind == .Enter or evt.kind == .Leave
        {
            let row = evt.kind == .Leave ? Swag.U64.Max : .rowAt(.surfaceToLocal(evt.surfacePos))
            if not .explorer.showTileCaption and
               not .rows and
               .board != .Album and
               row < .explorer.shown.count do
                .toolTip = .tileToolTip(row)
            else do
                .toolTip = ""
            if .hovered != row
            {
                let previous = .hovered
                .hovered = row
                .startNameScroll()
                if .rows or .board == .Album
                {
                    .invalidate()
                }
                else
                {
                    .invalidateTile(previous)
                    .invalidateTile(row)
                }
            }

            return
        }

        if evt.kind == .Released and evt.button == .Right
        {
            .explorer.showEntryMenu(.rowAt(.surfaceToLocal(evt.surfacePos)), evt.surfacePos)
            return
        }

        if (evt.kind != .Pressed and evt.kind != .DoubleClick) or evt.button != .Left
        {
            evt.accepted = false
            return
        }

        let row = .rowAt(.surfaceToLocal(evt.surfacePos))
        .select(row, evt.modifiers)
        .setFocus()
        if evt.kind == .DoubleClick and row < .explorer.shown.count do
            .explorer.activate(.explorer.selected)
    }

    private mtd tileToolTip(row: u64)->String
    {
        let text   = appStrings()
        let entry  = &.explorer.entries[.explorer.shown[row]]
        var result = safeMediaText(.tileName(entry))
        result += Format.toString("\n%: %", text.explore_Type, entry.directory ? text.ui_Folder : (Path.extension(entry.name) orelse text.explore_File))
        if not entry.directory do
            result += Format.toString("\n%: %", text.explore_Size, StrConv.toDisplaySize(entry.size))
        if entry.when.year do
            result += Format.toString("\n%: %", text.explore_Modified, explorerFileTime(entry.when, Time.DateTime.now(), .explorer.window.language))
        if entry.duration do
            result += Format.toString("\n%", formatDuration(entry.duration))
        var pluginIndex: u64
        if not entry.directory and .explorer.window.index.namePlugin(entry.path, &pluginIndex) do
            result += Format.toString("\n%", .explorer.window.index.plugins[pluginIndex].displayName())
        return result
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind != .Pressed or evt.modifiers.has(.Alt)
        {
            evt.accepted = false
            return
        }

        var row = 0'u64
        if .explorer.selected == Swag.U64.Max and
           (evt.key == .Left or evt.key == .Right or evt.key == .Up or evt.key == .Down)
        {
            .select(0)
            return
        }

        for index, at in .explorer.shown where index == .explorer.selected do
            row = at
        switch evt.key
        {
        case .Return: .explorer.openSelection()
        case .Left:   .select(row > 0 ? row - 1 : 0)
        case .Right:  .select(row + 1)
        case .Up:     .select(row >= .columns ? row - .columns : 0)
        case .Down:   .select(row + .columns)
        case .Home:   .select(0)
        case .End where not .explorer.shown.isEmpty(): .select(.explorer.shown.count - 1)
        case .Back:   .explorer.goUp()
        default:      evt.accepted = false
        }
    }
}
