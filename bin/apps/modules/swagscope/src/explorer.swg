#global internal

using Core, Gui, Pixel

enum ExplorerMode { Names, Details, Small, Medium, Large }

const ExplorerTilePreviewAspect: f32 = 0.8

// Each isolated renderer owns one decoder worker, for at most three CPU workers.
const ExplorerWorkerCount = 3

struct ExplorerTemporary
{
    file:  String
    title: String
}

// Owns exploration independently of the file currently being viewed.
struct Explorer
{
    using wnd: Wnd

    late
    {
        window:     *ViewerWindow
        bar:        *Wnd
        breadcrumb: *BreadcrumbCtrl
        pathScroll: *ScrollWnd
        status:     *Label
        modes:      *ComboBox
        filter:     *EditBox
        back:       *IconButton
        forward:    *IconButton
        up:         *IconButton
        refresh:    *IconButton
        panels:     *IconButton
        list:       *ListCtrl
        scroll:     *ScrollWnd
        grid:       *ExplorerGrid
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
    previews:        [ExplorerWorkerCount] ExplorerPreview
    generation:      u64
    selected:        u64 = Swag.U64.Max
    pendingOpen:     u64 = Swag.U64.Max
    temporaryFiles:  Array'ExplorerTemporary
    cached:          Array'u64
    sortColumn:      u32
    descending:      bool
    menuPaths:       Array'String
    previewSettings: String
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

        result.createBar()
        with result.status = Label.create(result, "", {0, 0, 0, 28}, null, .Ellipsis | .SecondaryText)
        {
            .dockStyle = .Bottom
            .margin    = {16, 0, 16, 0}
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
                if list.focusIndex < result.shown.count do
                    result.selected = result.shown[list.focusIndex]
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
        for ExplorerWorkerCount
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

    private mtd createBar()
    {
        with .bar = Wnd.create'Wnd(me, {0, 0, 0, 84})
        {
            .dockStyle       = .Top
            .padding         = {8, 4, 8, 4}
            .backgroundStyle = .ToolBar
        }

        with let navigation = Wnd.create'Wnd(.bar, {0, 0, 0, 36})
        {
            .dockStyle       = .Top
            .backgroundStyle = .Transparent
        }

        with .back = Viewer.createActionButton(navigation, .ChevronLeft)
        {
            .dockStyle  = .Left
            .toolTip    = appStrings().explore_Back
            .sigPressed += func|view = me|(_) { view.goBack() }
        }

        with .forward = Viewer.createActionButton(navigation, .ChevronRight)
        {
            .dockStyle  = .Left
            .toolTip    = appStrings().explore_Forward
            .sigPressed += func|view = me|(_) { view.goForward() }
        }

        with .up = Viewer.createActionButton(navigation, .ParentFolder)
        {
            .dockStyle  = .Left
            .toolTip    = appStrings().explore_Up
            .sigPressed += func|view = me|(_) { view.goUp() }
        }

        with .refresh = Viewer.createActionButton(navigation, .Update)
        {
            .dockStyle  = .Left
            .toolTip    = appStrings().explore_Refresh
            .sigPressed += func|view = me|(_) { view.navigate(view.listing.path, view.folder, false) }
        }

        with .panels = Viewer.createActionButton(navigation, .History)
        {
            .dockStyle  = .Right
            .sigPressed += func|view = me|(_) { view.window.toggleFilePanel() }
        }

        with .pathScroll = Wnd.create'ScrollWnd(navigation)
        {
            .dockStyle = .Center
            .margin.x  = 12
            .updateFlags(.CompactBars | .TransparentBars)
            .setFrameFlags(remove: .Borders)
        }

        with .breadcrumb = BreadcrumbCtrl.create(.pathScroll)
        {
            .backgroundStyle = .Transparent
            .sigItemPressed  += func|view = me|(path, index) { view.navigateBreadcrumb(path.items[index].tag) }
            .sigFillMenu     += func|view = me|(_, index, menu) { view.fillBreadcrumbMenu(index, menu) }
            .sigMenuSelected += func|view = me|(_, _, path) { view.navigateBreadcrumb(path) }
        }

        .pathScroll.setView(.breadcrumb)

        with let options = Wnd.create'Wnd(.bar, {0, 0, 0, 36})
        {
            .dockStyle       = .Center
            .backgroundStyle = .Transparent
            .margin          = {4, 4, 0, 0}
        }

        with .modes = ComboBox.create(options, {0, 0, 184, 36})
        {
            .dockStyle  = .Right
            .sigChanged += func|view = me|(_, index) { view.setMode(cast(ExplorerMode, index)) }
        }

        with .filter = EditBox.create(options, "", {0, 0, 0, 36}, flags: .ClearButton)
        {
            .dockStyle = .Center
            .margin.z  = 16
            .setIcon(me.theme().icon(.Search, themeActionIconSize(me.themeMetrics())))
            .setPlaceholder(appStrings().ui_FilterFiles)
            .sigTextChanged += func|view = me|(_) { view.fill() }
        }
    }

    mtd retranslate()
    {
        .modes.clear()
        let text = appStrings()
        .back.toolTip    = text.explore_Back
        .forward.toolTip = text.explore_Forward
        .up.toolTip      = text.explore_Up
        .refresh.toolTip = text.explore_Refresh
        .panels.toolTip  = text.explore_Panels
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
        .generation += 1
        .suspend()
        .pendingOpen     = Swag.U64.Max
        .requested       = path
        .requestedFolder = folder
        if remember do
            .history.push(Format.toString("%\n%", path, folder))
        .back.enable(.history.canGoBack())
        .forward.enable(.history.canGoForward())
        .status.setText(appStrings().explore_Loading)
        if not .load.started do
            .startListing()
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

    mtd updateBreadcrumb()
    {
        .breadcrumb.clear()
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
            .breadcrumb.addItem(name.count ? name : full, tag: Format.toString("%\n", full))
        }

        if .listing.isArchive
        {
            var begin: u64
            for offset in .folder.length where .folder[offset] == '/'u8
            {
                .breadcrumb.addItem(.folder.toString()[begin until offset],
                                    tag: Format.toString("%\n%", .listing.path, .folder.toString()[0 until offset + 1]))
                begin = offset + 1
            }
        }

        .breadcrumb.layout()
        let width = .breadcrumb.items.isEmpty() ? 0.0 : .breadcrumb.items.back().arrowRect.right()
        .pathScroll.setScrollSize(width, 0)
        .pathScroll.setScrollPos(width, 0)
        .breadcrumb.toolTip = Format.toString("% / %", .displayPath(.listing.path), .folder)
    }

    mtd fillBreadcrumbMenu(index: u64, menu: *MenuCtrl)
    {
        if index >= .breadcrumb.items.count do
            return
        let location = .breadcrumb.items[index].tag.toString()
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
            let selected = index + 1 < .breadcrumb.items.count and .breadcrumb.items[index + 1].tag == target
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
        .updateBreadcrumb()

        .filter.setText("", notify: false)
        .list.header.setSortIndicator(.sortColumn, .descending ? .Descending : .Ascending)
        .fill()
        .scroll.setScrollPos(0, 0)
        .window.refreshFileLists()
    }

    mtd entryIcon(index: u64, size: f32 = 16)->Icon
    {
        let entry = &.entries[index]
        if entry.directory do
            return .theme().icon(.OpenFile, size)
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

        .status.setText(.shown.isEmpty() ? appStrings().explore_Empty : Format.toString(appStrings().explore_Count, .shown.count))
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

    // Keep three independent renderers busy on visible tiles, with at most 128 uploaded previews.
    mtd requestPreview()
    {
        .refreshPreviewSettings()
        for &preview in .previews where not preview.started do
            .startPreview(preview)
    }

    mtd refreshPreviewSettings()
    {
        let settings = ThumbnailSettings.capture(.window)
        if .previewSettings == settings do
            return

        // The first snapshot precedes all jobs; later changes retire every old publication.
        if not .previewSettings.isEmpty()
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
            for &entry in .entries do
                entry.attempted = false
            .grid.invalidate()
        }

        .previewSettings = settings
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
            if .mode == .Names or .mode == .Details do
                return
            let range = .grid.visibleRange()
            for row in range.first until range.end
            {
                let index = .shown[row]
                if not .entries[index].directory and
                   not .entries[index].attempted and
                   .previewSlot(index) == Swag.U64.Max
                {
                    wanted = index
                    break
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
                for row in range.first until range.end where .shown[row] == cached do
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
        .pendingOpen        = Swag.U64.Max
        preview.path        = entry.path
        preview.index       = wanted
        preview.generation  = .generation
        preview.opening     = opening
        preview.settings    = .previewSettings
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
                .status.setText(error)
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
                            .status.setText(preview.error)
                    }
                    elif preview.image.isValid()
                    {
                        if .cached.count >= 128
                        {
                            let old = .cached[0]
                            .app().renderer.removeTexture(&.entries[old].texture)
                            .entries[old].attempted = false
                            .cached.removeAtOrdered(0)
                        }

                        .entries[preview.index].texture = .app().renderer.addImage(preview.image)
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
        case .F5:                                  .navigate(.listing.path, .folder, false)
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
        let width: f32 = .explorer.mode == .Small ? 128.0 : (.explorer.mode == .Large ? 256.0 : 192.0)
        let previewWidth = width - 24
        .cell    = Math.Point{width, previewWidth / ExplorerTilePreviewAspect + 48}
        .columns = Math.max(1'u64, cast(u64, Math.max(0.0, .clientRect().width - 24) / width))
        let rows = (.explorer.shown.count + .columns - 1) / .columns
        .explorer.scroll.setScrollSize(0, cast(f32, rows) * .cell.y + 24)
        .invalidate()
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
        var busy: [ExplorerWorkerCount] bool
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
                let width  = cast(f32, entry.texture.width) * scale
                let height = cast(f32, entry.texture.height) * scale
                painter.drawTexture(Math.Rectangle{preview.horzCenter() - width / 2, preview.vertCenter() - height / 2, width, height}, entry.texture)
            }
            elif slot != Swag.U64.Max
            {
                let size = .themeMetrics().spinner_Size
                .spinners[slot].setPosition(Math.Rectangle{preview.horzCenter() - size / 2, preview.vertCenter() - size / 2, size, size}, computeLayout: false)
                busy[slot] = true
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

        for slot in ExplorerWorkerCount do
            .spinners[slot].show(busy[slot])
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
