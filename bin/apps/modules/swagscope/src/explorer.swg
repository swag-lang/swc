#global internal

using Core, Gui, Pixel, Video

enum ExplorerMode { Names, Details, Small, Medium, Large }

// Width over height of a tile's picture: a page for a folder of documents, a screen for a folder
// that is mostly films.
const ExplorerTilePreviewAspect: f32 = 0.8
const ExplorerFilmPreviewAspect: f32 = 16.0 / 9.0

// Height over width of the card a folder tile stands on.
const ExplorerFolderCardAspect: f32 = 0.75

// The duration label of a film tile: small, bold, light ink on a translucent ink ground.
const ExplorerDurationFontSize = 11'u32
const ExplorerDurationGround   = 0xB30B0B0D'u32
const ExplorerDurationInk      = 0xFFE6E6EA'u32

// Writes a duration the way players do: hours only when there are some, minutes and seconds always.
func formatDuration(seconds: u64)->String
{
    let hours   = seconds / 3600
    let minutes = (seconds / 60) % 60
    if hours do
        return Format.toString("%:%{02}:%{02}", hours, minutes, seconds % 60)
    return Format.toString("%:%{02}", minutes, seconds % 60)
}

// Returns the duration a thumbnail is labelled with, in seconds, or zero when it carries none.
func thumbnailDuration(image: const *Image)->u64
{
    for &record in image.metadata where record.isTag(cast(const [..] u8, Viewer.ThumbnailDurationTag)) do
        return catch StrConv.toU64(cast(string, record.toSlice()))
    return 0
}

// Returns how many isolated renderers the Explorer keeps busy.
//
// Each renderer is a child process decoding on one thread, so one per logical processor saturates
// the machine; two are left to the interface and to the decoders of the open viewer.
func explorerWorkerCount()->u64 => Math.max(cast(u64, Hardware.processorCount()), 3'u64) - 2

// How many previews of a folder on a network share run at once.
//
// A share answers a bounded number of scattered reads a second, and every renderer past what it
// keeps busy only lengthens the queue in front of it: on a NAS, twenty renderers filled the folder
// half as fast as a handful.
const ExplorerRemoteWorkerCount = 6'u64

struct ExplorerTemporary
{
    file:  String
    title: String
}

// Owns exploration independently of the file currently being viewed.
//
// The listing fills the document; everything else lives in the window's own bars, where the
// same places answer the same questions for a file. The information band names the location
// and how much it holds, the command bar carries the filter where a file has its search, and
// the way of showing the listing where a file has its viewer.
struct Explorer
{
    using wnd: Wnd

    late
    {
        window:       *ViewerWindow
        location:     *Wnd
        navigation:   *IconBar
        back:         *IconButton
        forward:      *IconButton
        up:           *IconButton
        address:      *ExplorerAddress
        status:       *Label
        modes:        *ComboBox
        mediaOptions: *IconButton
        mediaInfo:    *Label
        filter:       *EditBox
        list:         *ListCtrl
        scroll:       *ScrollWnd
        grid:         *ExplorerGrid
    }

    mode:            ExplorerMode = .Medium
    history:         NavigationHistory
    listing:         ExplorerListing
    entries:         Array'ExplorerEntry
    shown:           Array'u64
    folder:          String
    requested:       String
    requestedFolder: String
    load:            ExplorerListingLoad
    previews:        Array'ExplorerPreview     // Sized once: a running task borrows its preview.
    generation:      u64
    selected:        u64 = Swag.U64.Max
    pendingOpen:     u64 = Swag.U64.Max
    temporaryFiles:  Array'ExplorerTemporary
    cached:          Array'u64
    sortColumn:      u32
    descending:      bool
    menuPaths:       Array'String
    previewSettings: String
    bypassCache:     bool     // Whether the previews of the shown listing ignore the persistent cache, after a forced refresh.
    previewAspect:   f32 = ExplorerTilePreviewAspect     // Shape of the tiles, chosen from what the listing holds.
    previewBudget:   u64      // How many previews of the shown listing run at once.
}

impl Explorer
{
    func create(parent: *Wnd, window: *ViewerWindow)->*Explorer
    {
        with let result = Wnd.create'Explorer(parent, "scope.explorer")
        {
            .dockStyle       = .Center
            .backgroundStyle = .View
            .window          = window
        }

        result.createLocation()
        result.createViewControls()
        with result.mediaInfo = Label.create(result, "", flags: .WordWrap | .AutoHeight | .Ellipsis)
        {
            .dockStyle = .Bottom
            .padding   = {16, 8, 16, 8}
            .setTextAlignment(.Left, .Center)
            .setMaxLines(5)
            .hide()
        }

        with result.list = ListCtrl.createMultiColumns(result)
        {
            .dockStyle       = .Center
            .backgroundStyle = .View
            .updateFlags(.Ellipsis | .HotTrack)
            .addColumn(appStrings().explore_Name, 320)
            .addColumn(appStrings().explore_Type, 140)
            .addColumn(appStrings().explore_Size, 100)
            .addColumn(appStrings().explore_Modified, 160)
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
                    line.setItem(1, entry.directory ? appStrings().ui_Folder : (Path.extension(entry.name) orelse ""))
                    line.setItem(2, entry.directory ? {} : StrConv.toDisplaySize(entry.size))
                    line.setItem(3, entry.modified)
                }
            }

            .sigLeftDoubleClicked += func|result|(_, _)
            {
                result.activate(result.selected)
            }

            .sigKeyPressed += func|result|(_, evt)
            {
                if evt.key == .Return
                {
                    result.activate(result.selected)
                    evt.accepted = true
                }
            }
        }

        result.list.header.sigColumnClicked += func|result|(_, column)
        {
            result.descending = result.sortColumn == column and not result.descending
            result.sortColumn = column
            result.navigate(result.listing.path, result.folder, false)
        }

        with result.scroll = Wnd.create'ScrollWnd(result)
        {
            .dockStyle = .Center
            .updateFlags(.CompactBars | .DisableHorizontal)
            .sigScrollPositionChanged += func|result|(_, _, _) { result.prioritizeVisible() }
        }

        with result.grid = result.scroll.createView'ExplorerGrid()
        {
            .explorer        = result
            .backgroundStyle = .View
            .focusPolicy     = .Tab
        }

        result.retranslate()
        result.previews.resize(explorerWorkerCount())
        result.previewBudget = result.previews.count
        result.grid.busy.resize(result.previews.count)
        for result.previews.count
        {
            with let spinner = Spinner.create(result.grid)
            {
                .backgroundStyle = .Transparent
                .hide()
                .hookOnEvent = func|result|(_, evt)
                {
                    if evt is MouseEvent as mouse
                    {
                        result.grid.itf.onMouseEvent(mouse)
                        return true
                    }

                    return false
                }
            }

            result.grid.spinners.add(spinner)
        }

        result.setMode(.Medium)
        return result
    }

    // Builds what the information band shows in place of a file: the arrows that walk the
    // history and the parent folder as one cluster, the address of the location, and on the far
    // side how much the location holds.
    private mtd createLocation()
    {
        let info     = .window.infoContentGroup
        let metrics  = .themeMetrics()
        let iconSize = themeActionIconSize(metrics)
        with .location = Wnd.create'Wnd(info, "scope.explorer.location")
        {
            .backgroundStyle = .Transparent
        }

        info.locationGroup = .location

        // The arrows are one tool, so their cells touch: each is as wide as a field is tall, and
        // the cluster stands as high as the address beside it.
        with .navigation = IconBar.create(.location, iconSize, itemPadding: (themeCompactButtonSize(metrics) - iconSize) / 2)
        {
            .dockStyle = .Left
            .margin    = {0, 2, 0, 2}
        }

        with .back = .navigation.addButton(.theme().icon(.ChevronLeft, iconSize))
        {
            .sigPressed += func|view = me|(_) { view.goBack() }
        }

        with .forward = .navigation.addButton(.theme().icon(.ChevronRight, iconSize))
        {
            .sigPressed += func|view = me|(_) { view.goForward() }
        }

        with .up = .navigation.addButton(.theme().icon(.ParentFolder, iconSize))
        {
            .sigPressed += func|view = me|(_) { view.goUp() }
        }

        with .address = ExplorerAddress.create(.location, me)
        {
            .dockStyle = .Center
            .margin    = {8, 2, 0, 2}
        }

        with .status = Label.create(info, "", {0, 0, 0, 36}, null, .Ellipsis | .SecondaryText)
        {
            .style.setFont(me.theme().createDefaultFontFs(12), .Regular)
            .setTextAlignment(.Right, .OpticalCenter)
        }
    }

    // Builds the controls the command bar shows while exploring: the filter where a file has its
    // search, and the way of showing the listing where a file has its viewer.
    private mtd createViewControls()
    {
        let bar = .window.commandBar
        with .modes = ComboBox.create(bar, {0, 0, 184, 36})
        {
            .dockStyle  = .Right
            .sigChanged += func|view = me|(_, index) { view.setMode(cast(ExplorerMode, index)) }
        }

        with .mediaOptions = Viewer.createActionDropDown(bar, .Options)
        {
            .dockStyle = .Right
            .setArrowPosition(.RightDownward)
            .sigPressed += func|view = me|(_) { view.showMediaOptions() }
        }

        with .filter = EditBox.create(bar, "", {0, 0, ViewerWindow.SearchNoOptionsFieldWidth, 36}, flags: .ClearButton)
        {
            .setIcon(me.theme().icon(.Search, themeActionIconSize(me.themeMetrics())))
            .setPlaceholder(appStrings().ui_FilterFiles)
            .sigTextChanged += func|view = me|(_) { view.fill() }
        }
    }

    // Shows or hides the listing together with what it lends the window's bars.
    mtd setShown(visible: bool)
    {
        .show(visible)
        .location.show(visible)
        .status.show(visible)
        .modes.show(visible)
        .mediaOptions.show(visible)
        .filter.show(visible)
        if not visible do
            .mediaInfo.hide()
        else do
            .showMediaInfo()
        .window.infoFileGroup.show(not visible)
        .window.filesButton.toolTip = visible ? appStrings().explore_Panels : appStrings().ui_Files
        if visible
        {
            .window.commandBar.centerGroup = .filter
            .window.commandBar.centerContent()
        }

        .window.infoContentGroup.computeLayout()
    }

    // Reports what the location holds, or why it holds nothing, at the end of the information band.
    mtd setStatus(text: string)
    {
        .status.setText(text)
        .status.preferredSize.x = Math.ceil(.status.itf.measureContent({}).x)
        .window.infoContentGroup.computeLayout()
    }

    mtd showMediaOptions()
    {
        let menu = MenuCtrl.createPopup(me, owner: me)
        menu.addItem(appStrings().explore_OnlineMovies, "onlineMovies", checked: .window.onlineMovies)
        menu.addItem(appStrings().explore_OnlineMusic, "onlineMusic", checked: .window.onlineMusic)
        let musicSelected = .selected < .entries.count and
                            not .listing.isArchive and
                            not .entries[.selected].directory and
                            (Path.hasExtension(.entries[.selected].path, ".mp3") or Path.hasExtension(.entries[.selected].path, ".flac"))
        menu.addItem(appStrings().explore_ChooseMusic, "chooseMusic", disabled: not musicSelected or not .window.onlineMusic)
        let choice = menu.doModal(.mediaOptions, autoDestroy: true) orelse ""
        if choice == "chooseMusic"
        {
            .chooseMusic()
            return
        }

        if choice == "onlineMovies"
        {
            .window.onlineMovies = not .window.onlineMovies
        }
        elif choice == "onlineMusic"
        {
            .window.onlineMusic = not .window.onlineMusic
        }
        else
        {
            return
        }

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
        let previous   = musicChoiceId(.window.musicChoices.toSlice(), &.entries[selected])
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

        setMusicChoice(&.window.musicChoices, &.entries[selected], String.toLower(text))
        .retirePreviews()
        .requestPreview()
    }

    mtd createMusicChoiceDialog(previous: string)->*EditDlg
    {
        return EditDlg.createSingleLine(unwrap .window.surface, {title: appStrings().explore_ChooseMusic,
                                                                 message: appStrings().explore_ChooseMusicHelp,
                                                                 text: previous})
    }

    mtd showMediaInfo()
    {
        if .selected >= .entries.count
        {
            .mediaInfo.hide()
            return
        }

        var text = .entries[.selected].movie.text()
        if text.isEmpty() do
            text = .entries[.selected].music.text()
        .mediaInfo.setText(text)
        .mediaInfo.toolTip = text
        .mediaInfo.show(not text.isEmpty() and .isVisible())
        .applyLayout()
    }

    // Gives the keyboard to the listing, in whichever form it is shown.
    mtd focusContent()
    {
        if .mode == .Names or .mode == .Details do
            .list.setFocus()
        else do
            .grid.setFocus()
    }

    mtd retranslate()
    {
        .modes.clear()
        let text = appStrings()
        .back.toolTip            = text.explore_Back
        .forward.toolTip         = text.explore_Forward
        .up.toolTip              = text.explore_Up
        .address.refresh.toolTip = text.explore_Refresh
        .mediaOptions.toolTip    = text.explore_MediaOptions
        .showMediaInfo()
        .filter.setPlaceholder(text.ui_FilterFiles)
        .list.header.itemAt(0).name = text.explore_Name
        .list.header.itemAt(1).name = text.explore_Type
        .list.header.itemAt(2).name = text.explore_Size
        .list.header.itemAt(3).name = text.explore_Modified
        for name in [text.explore_Names, text.explore_Details, text.explore_Small, text.explore_Medium, text.explore_Large] do
            .modes.addItem(name)
        .modes.setSelectedIndex(cast(u32, .mode), notify: false)
    }

    mtd navigate(path: string, folder: string = "", remember = true)
    {
        .generation  += 1
        .bypassCache = false
        .suspend()
        .pendingOpen     = Swag.U64.Max
        .requested       = path
        .requestedFolder = folder
        if remember do
            .history.push(Format.toString("%\n%", path, folder))
        .back.enable(.history.canGoBack())
        .forward.enable(.history.canGoForward())
        .setStatus(appStrings().explore_Loading)
        if not .load.started do
            .startListing()
    }

    // Lists the folder again and renders its previews anew instead of reading them from the cache.
    //
    // The cache already follows a file that changed, so a forced refresh is what the user reaches
    // for when a preview is wrong anyway; the previews it renders replace the cached ones.
    mtd forceRefresh()
    {
        .navigate(.listing.path, .folder, false)
        .bypassCache = true
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
        let path = .displayPath(.listing.path)
        if .folder.isEmpty() do
            return path
        return Format.toString("%/%", path, .folder)
    }

    // Goes to a location typed into the address: the folder or archive it names, a folder inside
    // the archive on show, or the file it names, which opens as any other file does.
    //
    // A path copied from the system file browser comes between quotes, which are not part of it.
    mtd navigateTyped(text: string)
    {
        var typed = Latin1.trim(text)
        if typed.count >= 2 and typed[0] == '"'u8 and typed[typed.count - 1] == '"'u8 do
            typed = typed[1 until typed.count - 1]
        if typed.count == 0 or .locationText() == typed do
            return

        if .listing.isArchive
        {
            let archive = .displayPath(.listing.path)
            if Utf8.startsWith(typed, archive) and (typed.count == archive.count or typed[archive.count] == '/'u8)
            {
                var folder = typed[archive.count to]
                while folder.count and folder[0] == '/'u8 do
                    folder = folder[1 to]
                if folder.count and folder[folder.count - 1] != '/'u8 do
                    .navigate(.listing.path, Format.toString("%/", folder))
                else do
                    .navigate(.listing.path, folder)
                return
            }
        }

        if Directory.exists(typed) do
            .navigate(typed)
        elif File.exists(typed) do
            .window.queueFile(typed)
        else do
            .setStatus(appStrings().explore_NotFound)
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

        for ancestor in ancestors.reversed()
        {
            let full = ancestor.toString()
            let name = Path.fileName(full) orelse full
            breadcrumb.addItem(name.count ? name : full, tag: Format.toString("%\n", full))
        }

        if .listing.isArchive
        {
            var begin: u64
            for offset in .folder.length where .folder[offset] == '/'u8
            {
                breadcrumb.addItem(.folder.toString()[begin until offset],
                                   tag: Format.toString("%\n%", .listing.path, .folder.toString()[0 until offset + 1]))
                begin = offset + 1
            }
        }

        breadcrumb.toolTip = .locationText()
        .address.refreshPath()
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

        children.sort(func(a, b)->s32 { return Latin1.compareNatural(a.name, b.name) })
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
            menu.addItem(child.name, target, checked: selected)
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

    private mtd clearTextures()
    {
        for &entry in .entries where entry.texture.isValid() do
            .app().renderer.removeTexture(&entry.texture)
        .cached.clear()
    }

    private mtd publish()
    {
        .clearTextures()
        .entries  = #move .listing.entries
        .selected = Swag.U64.Max
        .mediaInfo.hide()
        .previewAspect = .listingPreviewAspect()
        .previewBudget = Directory.isRemote(.listing.path) ? Math.min(ExplorerRemoteWorkerCount, .previews.count) : .previews.count
        .updateBreadcrumb()

        .filter.setText("", notify: false)
        .list.header.setSortIndicator(.sortColumn, .descending ? .Descending : .Ascending)
        .fill()
        .scroll.setScrollPos(0, 0)
        .window.refreshFileLists()
    }

    // Chooses the shape of the tiles from the files listed, before any preview exists.
    //
    // A page-shaped tile leaves most of itself empty around a film, and a folder of films is a row of
    // screens; deciding from the names keeps the grid from changing shape while previews arrive.
    mtd listingPreviewAspect()->f32
    {
        var files, films: u64
        for &entry in .entries where not entry.directory
        {
            files += 1
            var pluginIndex: u64
            if .window.index.namePlugin(entry.path, &pluginIndex) and .window.index.plugins[pluginIndex].key == "video" do
                films += 1
        }

        if films * 2 > files do
            return .window.onlineMovies ? ExplorerTilePreviewAspect : ExplorerFilmPreviewAspect
        return ExplorerTilePreviewAspect
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

    mtd fill()
    {
        .grid.hovered = Swag.U64.Max
        .shown.clear()
        .list.clear()
        let query = .filter.text()
        for &entry, index in .entries
        {
            if query.count and Utf8.indexOf(entry.name, query, comparisonType: .Latin1NoCase) == Swag.U64.Max do
                continue
            .shown.add(index)
        }

        switch .shown.count
        {
        case 0:  .setStatus(appStrings().explore_Empty)
        case 1:  .setStatus(appStrings().explore_OneItem)
        default: .setStatus(Format.toString(appStrings().explore_Count, .shown.count))
        }

        .list.setVirtualCount(cast(u32, .shown.count))
        for index, row in .shown where index == .selected
        {
            .list.setFocusedIndex(cast(u32, row), ensureVisible: false)
            .list.selectLine(cast(u32, row))
            break
        }

        .grid.refreshLayout()
        .requestPreview()
    }

    mtd setMode(mode: ExplorerMode)
    {
        .mode = mode
        .modes.setSelectedIndex(cast(u32, mode), notify: false)
        let rows = mode == .Names or mode == .Details
        .list.show(rows)
        .list.header.show(mode == .Details)
        .scroll.show(not rows)
        .applyLayout()
        .fill()
    }

    mtd suspend()
    {
        for &preview in .previews
        {
            if preview.started and preview.generation == .generation and preview.index < .entries.count do
                .entries[preview.index].attempted = false
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
        for &preview in .previews where preview.started and not preview.opening
        {
            let range   = .grid.visibleRange()
            var visible = false
            for row in range.first until range.end where .shown[row] == preview.index do
                visible = true
            if not visible
            {
                if preview.generation == .generation and preview.index < .entries.count do
                    .entries[preview.index].attempted = false
                preview.task.cancel()
            }
        }

        .requestPreview()
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
            .window.queueFile(entry.path)
        }
    }

    // Keep every independent renderer busy on visible tiles, with at most 128 uploaded previews.
    mtd requestPreview()
    {
        .refreshPreviewSettings()
        var running = 0'u64
        for &preview in .previews where preview.started do
            running += 1
        for &preview in .previews where not preview.started
        {
            // Opening a file is what the user waits for; only background previews keep the budget.
            if running >= .previewBudget and .pendingOpen == Swag.U64.Max do
                break
            .startPreview(preview)
            if preview.started do
                running += 1
        }
    }

    mtd refreshPreviewSettings()
    {
        let settings = ThumbnailSettings.capture(.window)
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
        for &preview in .previews
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
            entry.attempted = false
            entry.movie     = {}
            entry.music     = {}
        }

        .showMediaInfo()
        .grid.invalidate()
    }

    // Returns the active slot for a tile, including work waiting for GUI publication.
    mtd previewSlot(index: u64)->u64
    {
        for &preview, slot in .previews where preview.started and
                                              not preview.opening and
                                              preview.generation == .generation and
                                              preview.index == index do
            return slot
        return Swag.U64.Max
    }

    private mtd startPreview(preview: *ExplorerPreview)
    {
        if .load.started or (not .isVisible() and .pendingOpen == Swag.U64.Max) do
            return
        var wanted  = .pendingOpen
        let opening = wanted != Swag.U64.Max
        if not opening
        {
            if .mode == .Names or .mode == .Details
            {
                if .selected >= .entries.count do
                    return
                let selected = &.entries[.selected]
                let movie    = .window.onlineMovies and Reader.canOpen(selected.path)
                let music    = .window.onlineMusic and (Path.hasExtension(selected.path, ".mp3") or Path.hasExtension(selected.path, ".flac"))
                if selected.directory or
                   selected.attempted or
                   not (movie or music) or
                   .previewSlot(.selected) != Swag.U64.Max do
                    return
                wanted = .selected
            }
            else
            {
                let range = .grid.visibleRange()
                for row in Math.min(range.first, .shown.count) until Math.min(range.end, .shown.count)
                {
                    let index = .shown[row]
                    if index < .entries.count and not .entries[index].directory and
                       not .entries[index].attempted and
                       .previewSlot(index) == Swag.U64.Max
                    {
                        wanted = index
                        break
                    }
                }
            }
        }

        if wanted >= .entries.count do
            return
        if not opening and .cached.count >= 128
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
                return
            let old = .cached[evict]
            .app().renderer.removeTexture(&.entries[old].texture)
            .entries[old].attempted = false
            .cached.removeAtOrdered(evict)
        }

        let entry = &.entries[wanted]
        if .listing.isArchive and entry.archiveIndex >= .listing.archive.entries.count do
            return
        .pendingOpen        = Swag.U64.Max
        preview.path        = entry.path
        preview.index       = wanted
        preview.generation  = .generation
        preview.opening     = opening
        preview.bypassCache = .bypassCache
        preview.settings    = ThumbnailSettings.capture(.window, entry)
        preview.archivePath = .listing.isArchive ? .listing.path : {}
        if .listing.isArchive do
            preview.entry = .listing.archive.entries[entry.archiveIndex]
        entry.attempted = true
        preview.start(me)
        .grid.invalidate()
    }
}

impl IWnd for Explorer
{
    mtd impl onTaskEvent(evt: *TaskEvent)
    {
        if .load.claim(evt)
        {
            var listing: ExplorerListing
            let error = .load.finish(&listing)
            if .load.path != .requested or
               .load.folder != .requestedFolder or
               .load.sortColumn != .sortColumn or
               .load.descending != .descending
            {
                .startListing()
                return
            }

            if not error.isEmpty()
            {
                .setStatus(error)
                return
            }

            .listing = #move listing
            .folder  = .requestedFolder
            .publish()
        }
        else
        {
            for &preview, slot in .previews where preview.claim(evt)
            {
                preview.wait()
                .refreshPreviewSettings()
                .grid.spinners[slot].hide()
                .grid.invalidate()
                if preview.generation != .generation and not preview.temporary.isEmpty()
                {
                    catch File.delete(preview.temporary)
                    preview.temporary.clear()
                }

                if not preview.temporary.isEmpty()
                {
                    let title = Format.toString("% / %", .displayPath(preview.archivePath), preview.path)
                    .temporaryFiles.add(ExplorerTemporary{#move preview.temporary, title})
                }

                if preview.generation == .generation
                {
                    if preview.opening
                    {
                        if preview.error.isEmpty() and not .temporaryFiles.isEmpty() do
                            .window.queueFile(.temporaryFiles.back().file, remember: false)
                        else do
                            .setStatus(preview.error)
                    }
                    elif preview.image.isValid()
                    {
                        if preview.index == .selected and not preview.error.isEmpty() do
                            .setStatus(preview.error)
                        if .cached.count >= 128
                        {
                            let old = .cached[0]
                            .app().renderer.removeTexture(&.entries[old].texture)
                            .entries[old].attempted = false
                            .cached.removeAtOrdered(0)
                        }

                        .entries[preview.index].texture  = .app().renderer.addImage(preview.image)
                        .entries[preview.index].duration = thumbnailDuration(&preview.image)
                        .entries[preview.index].movie    = MovieSummary.fromImage(&preview.image)
                        .entries[preview.index].music    = MusicSummary.fromImage(&preview.image)
                        if .selected == preview.index do
                            .showMediaInfo()
                        .cached.add(preview.index)
                        .grid.invalidate()
                    }
                }

                .requestPreview()
                return
            }

            evt.accepted = false
        }
    }

    mtd impl onDestroyEvent(_: *DestroyEvent)
    {
        for &preview in .previews do
            preview.task.cancel()
        for &preview in .previews do
            preview.wait()
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
        case .F5:                                  .forceRefresh()
        case .L where evt.modifiers.has(.Control): .address.beginEdit()
        case .D where evt.modifiers.has(.Alt):     .address.beginEdit()
        case .Left where evt.modifiers.has(.Alt):  .goBack()
        case .Right where evt.modifiers.has(.Alt): .goForward()
        case .Up where evt.modifiers.has(.Alt):    .goUp()
        case .Back:                                .goUp()
        default:                                   evt.accepted = false
        }
    }
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
}

impl ExplorerGrid
{
    mtd rowAt(point: Math.Point)->u64
    {
        let local = point + .scrollPos - {12, 12}
        if local.x < 0 or local.y < 0 do
            return Swag.U64.Max
        let column = cast(u64, local.x / .cell.x)
        let line   = cast(u64, local.y / .cell.y)
        let row    = line * .columns + column
        if column >= .columns or
           row >= .explorer.shown.count or
           local.x - cast(f32, column) * .cell.x >= .cell.x - 8 or
           local.y - cast(f32, line) * .cell.y >= .cell.y - 8 do
            return Swag.U64.Max
        return row
    }

    mtd refreshLayout()
    {
        let width: f32   = .explorer.mode == .Small ? 128.0 : (.explorer.mode == .Large ? 256.0 : 192.0)
        let previewWidth = width - 24
        .cell    = Math.Point{width, previewWidth / .explorer.previewAspect + 48}
        .columns = Math.max(1'u64, cast(u64, Math.max(0.0, .clientRect().width - 24) / width))
        let rows = (.explorer.shown.count + .columns - 1) / .columns
        .explorer.scroll.setScrollSize(0, cast(f32, rows) * .cell.y + 24)
        .invalidate()
    }

    // Draws a preview with the interface corner, its edge, and the duration of a film.
    //
    // A dark frame on the dark gallery ground loses its outline, so the rule draws it. The duration
    // sits on the picture, the way a media library labels a film; its ground stays ink in every
    // theme because it is read against the picture rather than against the interface.
    mtd paintThumbnail(painter: *Painter, picture: Math.Rectangle, entry: const *ExplorerEntry)
    {
        let radius = .themeRects().btnIcon_RoundSquareBk.radius
        painter.pushState()
        defer painter.popState()
        painter.setAntialiased(true)
        painter.fillRoundRect(picture, radius, radius, Brush.createTexture(entry.texture))

        // The rule is inset by half its weight, so it takes the corner stepped in by that half.
        var edge = picture
        edge.inflate(-0.5)
        painter.drawRoundRect(edge, radius - 0.5, radius - 0.5, .themeColors().border)

        if not entry.duration do
            return
        let label = formatDuration(entry.duration)
        let font  = .app().renderer.fontCache().createFont(.theme().res.defaultTypeFaceB, ExplorerDurationFontSize)
        let text  = Painter.measureString(label, font)
        var chip  = Math.Rectangle{0, 0, Math.round(text.width) + 8, Math.round(font.height) + 2}
        if chip.width + 8 > picture.width or chip.height + 8 > picture.height do
            return
        chip.x = picture.right() - chip.width - 4
        chip.y = picture.bottom() - chip.height - 4
        painter.fillRoundRect(chip, radius, radius, Color.fromArgb(ExplorerDurationGround))
        painter.drawString(chip.x + 4, chip.y + 1, label, font, Color.fromArgb(ExplorerDurationInk))
    }

    // Draws a folder as a quiet card standing where a picture would, its glyph on it.
    //
    // A file the gallery has no picture for shows its glyph on the bare ground, so a folder that
    // did the same read as one more such file. The card gives it a ground of its own in the panel
    // tone, the interface corner and the line of names a picture stands on, and stays fainter
    // than any picture beside it.
    mtd paintFolder(painter: *Painter, preview: Math.Rectangle, glyph: Icon)
    {
        let radius = .themeRects().btnIcon_RoundSquareBk.radius
        let height = Math.round(Math.min(preview.height, preview.width * ExplorerFolderCardAspect))
        let width  = Math.round(Math.min(preview.width, height / ExplorerFolderCardAspect))
        let card   = Math.Rectangle{Math.round(preview.horzCenter() - width / 2), Math.round(preview.bottom() - height), width, height}
        painter.pushState()
        defer painter.popState()
        painter.setAntialiased(true)
        painter.fillRoundRect(card, radius, radius, .themeColors().wnd_Bk)
        glyph.paint(painter, Math.round(card.horzCenter() - glyph.sizeX / 2), Math.round(card.vertCenter() - glyph.sizeY / 2), .themeColors().label_TextFaint)
    }

    mtd visibleRange()->{first: u64, end: u64}
    {
        let first = cast(u64, Math.max(0.0, .scrollPos.y - 12) / .cell.y) * .columns
        let rows  = cast(u64, Math.max(0.0, .clientRect().height) / .cell.y) + 2
        return {first: Math.min(first, .explorer.shown.count), end: Math.min(first + rows * .columns, .explorer.shown.count)}
    }

    mtd select(row: u64)
    {
        if row >= .explorer.shown.count do
            return
        .explorer.selected = .explorer.shown[row]
        .explorer.showMediaInfo()
        let top = 12 + cast(f32, row / .columns) * .cell.y
        if top < .scrollPos.y do
            .explorer.scroll.setScrollPos(0, top)
        elif top + .cell.y > .scrollPos.y + .clientRect().height do
            .explorer.scroll.setScrollPos(0, top + .cell.y - .clientRect().height)
        .invalidate()
    }
}

impl IWnd for ExplorerGrid
{
    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        if .explorer != null do
            .refreshLayout()
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let range   = .visibleRange()
        .busy.fill(false)
        for row in range.first until range.end
        {
            let index = .explorer.shown[row]
            let entry = &.explorer.entries[index]
            var rect  = Math.Rectangle{12 + cast(f32, row % .columns) * .cell.x,
                                       12 + cast(f32, row / .columns) * .cell.y, .cell.x - 8, .cell.y - 8}
            if .explorer.selected == index do
                .theme().drawSubRect(painter, rect, &.themeRects().selectionBox_Bk, .themeColors().listItem_SelectedBk)
            elif .hovered == row do
                .theme().drawSubRect(painter, rect, &.themeRects().selectionBox_Bk, .themeColors().listItem_HotBk)
            let slot    = .explorer.previewSlot(index)
            let preview = Math.Rectangle{rect.x + 8, rect.y + 8, rect.width - 16, rect.height - 40}
            if entry.texture.isValid()
            {
                let scale  = Math.min(preview.width / cast(f32, entry.texture.width), preview.height / cast(f32, entry.texture.height))
                let width  = Math.round(cast(f32, entry.texture.width) * scale)
                let height = Math.round(cast(f32, entry.texture.height) * scale)

                // Previews stand on the line of their names, so a row of films of any shape reads
                // as one row and each picture stays next to what it is called.
                .paintThumbnail(painter, Math.Rectangle{Math.round(preview.horzCenter() - width / 2), Math.round(preview.bottom() - height), width, height}, entry)
            }
            elif slot != Swag.U64.Max
            {
                let size = .themeMetrics().spinner_Size
                .spinners[slot].setPosition(Math.Rectangle{preview.horzCenter() - size / 2, preview.vertCenter() - size / 2, size, size}, computeLayout: false)
                .busy[slot] = true
            }
            elif entry.directory
            {
                .paintFolder(painter, preview, .explorer.entryIcon(index, 32))
            }
            else
            {
                let icon = .explorer.entryIcon(index, 32)
                icon.paint(painter, preview.horzCenter() - 16, preview.vertCenter() - 16, .themeColors().label_TextFaint)
            }

            var name:   RichString = entry.name
            var format: RichStringFormat
            format.font = .font()
            me.theme().setTextColors(&format, me.themeColors().label_Text)
            format.horzAlignment = .Center
            format.flags         = .Ellipsis
            painter.drawRichString(Math.Rectangle{rect.x + 4, rect.bottom() - 28, rect.width - 8, 24}, &name, format)
        }

        for spinner, slot in .spinners do
            spinner.show(.busy[slot])
        .explorer.requestPreview()
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if evt.kind == .Move or evt.kind == .Enter or evt.kind == .Leave
        {
            let row = evt.kind == .Leave ? Swag.U64.Max : .rowAt(.surfaceToLocal(evt.surfacePos))
            if .hovered != row
            {
                .hovered = row
                .invalidate()
            }

            return
        }

        if (evt.kind != .Pressed and evt.kind != .DoubleClick) or evt.button != .Left
        {
            evt.accepted = false
            return
        }

        let row = .rowAt(.surfaceToLocal(evt.surfacePos))
        .select(row)
        .setFocus()
        if evt.kind == .DoubleClick and row < .explorer.shown.count do
            .explorer.activate(.explorer.selected)
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
        case .Return: .explorer.activate(.explorer.selected)
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
