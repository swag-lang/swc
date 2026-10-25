#global internal

using Core, Gui, Pixel

enum ExplorerMode { Names, Details, Small, Medium, Large }

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
        window:    *ViewerWindow
        bar:       *Wnd
        pathLabel: *Label
        status:    *Label
        modes:     *ComboBox
        filter:    *EditBox
        back:      *IconButton
        forward:   *IconButton
        up:        *IconButton
        refresh:   *IconButton
        panels:    *IconButton
        list:      *ListCtrl
        scroll:    *ScrollWnd
        grid:      *ExplorerGrid
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
    preview:         ExplorerPreview
    generation:      u64
    selected:        u64 = Swag.U64.Max
    pendingOpen:     u64 = Swag.U64.Max
    temporaryFiles:  Array'ExplorerTemporary
    cached:          Array'u64
    sortColumn:      u32
    descending:      bool
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
                    line.setItem(2, entry.directory ? String{} : StrConv.toDisplaySize(entry.size))
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

        with .pathLabel = Label.create(navigation, "", {}, null, .Ellipsis)
        {
            .dockStyle = .Center
            .margin.x  = 12
            .setTextAlignment(.Left, .Center)
        }

        with .modes = ComboBox.create(.bar, {0, 0, 184, 36})
        {
            .dockStyle  = .Right
            .sigChanged += func|view = me|(_, index) { view.setMode(cast(ExplorerMode, index)) }
        }

        with .filter = EditBox.create(.bar, "", {}, flags: .ClearButton)
        {
            .dockStyle = .Center
            .margin    = {4, 4, 16, 0}
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
            .navigate(.listing.path, parent.count ? Format.toString("%/", parent) : String{})
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
        let path = .displayPath(.listing.path)
        let name = Path.fileName(path) orelse path
        .pathLabel.setText(.folder.isEmpty() ? String.from(name) : Format.toString("% / %", name, .folder))
        .pathLabel.toolTip = path

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
        if .preview.started and .preview.generation == .generation and .preview.index < .entries.count do
            .entries[.preview.index].attempted = false
        .preview.task.cancel()
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
        if .preview.started and not .preview.opening
        {
            let range   = .grid.visibleRange()
            var visible = false
            for row in range.first until range.end where .shown[row] == .preview.index do
                visible = true
            if not visible do
                .suspend()
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

    // Only visible tiles are decoded, one at a time, with at most 128 uploaded thumbnails.
    mtd requestPreview()
    {
        if .preview.started or .load.started or not .isVisible() do
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
                if not .entries[index].directory and not .entries[index].attempted
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
        .pendingOpen         = Swag.U64.Max
        .preview.path        = entry.path
        .preview.index       = wanted
        .preview.generation  = .generation
        .preview.opening     = opening
        .preview.archivePath = .listing.isArchive ? .listing.path : String{}
        if .listing.isArchive do
            .preview.entry = .listing.archive.entries[entry.archiveIndex]
        entry.attempted = true
        .preview.start(me)
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
        elif .preview.claim(evt)
        {
            .preview.wait()
            if .preview.generation != .generation and not .preview.temporary.isEmpty()
            {
                catch File.delete(.preview.temporary)
                .preview.temporary.clear()
            }

            if not .preview.temporary.isEmpty()
            {
                let title = Format.toString("% / %", .displayPath(.preview.archivePath), .preview.path)
                .temporaryFiles.add({#move .preview.temporary, title})
            }

            if .preview.generation == .generation
            {
                if .preview.opening
                {
                    if .preview.error.isEmpty() and not .temporaryFiles.isEmpty() do
                        .window.queueFile(.temporaryFiles.back().file, remember: false)
                    else do
                        .status.setText(.preview.error)
                }
                elif .preview.image.isValid()
                {
                    if .cached.count >= 128
                    {
                        let old = .cached[0]
                        .app().renderer.removeTexture(&.entries[old].texture)
                        .entries[old].attempted = false
                        .cached.removeAtOrdered(0)
                    }

                    .entries[.preview.index].texture = .app().renderer.addImage(.preview.image)
                    .cached.add(.preview.index)
                    .grid.invalidate()
                }
            }

            .requestPreview()
        }
        else
        {
            evt.accepted = false
        }
    }

    mtd impl onDestroyEvent(_: *DestroyEvent)
    {
        .preview.task.cancel()
        .preview.wait()
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
}

impl ExplorerGrid
{
    mtd refreshLayout()
    {
        let width: f32 = .explorer.mode == .Small ? 112.0 : (.explorer.mode == .Large ? 240.0 : 168.0)
        .cell    = {width, width * 0.72 + 48}
        .columns = Math.max(1'u64, cast(u64, Math.max(0.0, .clientRect().width - 24) / width))
        let rows = (.explorer.shown.count + .columns - 1) / .columns
        .explorer.scroll.setScrollSize(0, cast(f32, rows) * .cell.y + 24)
        .invalidate()
    }

    mtd visibleRange()->{first: u64, end: u64}
    {
        let first = cast(u64, Math.max(0.0, .scrollPos.y - 12) / .cell.y) * .columns
        let rows  = cast(u64, Math.max(0.0, .clientRect().height) / .cell.y) + 2
        return {Math.min(first, .explorer.shown.count), Math.min(first + rows * .columns, .explorer.shown.count)}
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
        for row in range.first until range.end
        {
            let index = .explorer.shown[row]
            let entry = &.explorer.entries[index]
            var rect  = Math.Rectangle{12 + cast(f32, row % .columns) * .cell.x,
                                       12 + cast(f32, row / .columns) * .cell.y, .cell.x - 8, .cell.y - 8}
            if .explorer.selected == index do
                .theme().drawSubRect(painter, rect, &.themeRects().selectionBox_Bk, .themeColors().listItem_SelectedBk)
            let preview = Math.Rectangle{rect.x + 8, rect.y + 8, rect.width - 16, rect.height - 40}
            if entry.texture.isValid()
            {
                let scale  = Math.min(preview.width / cast(f32, entry.texture.width), preview.height / cast(f32, entry.texture.height))
                let width  = cast(f32, entry.texture.width) * scale
                let height = cast(f32, entry.texture.height) * scale
                painter.drawTexture({preview.horzCenter() - width / 2, preview.vertCenter() - height / 2, width, height}, entry.texture)
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
            painter.drawRichString({rect.x + 4, rect.bottom() - 28, rect.width - 8, 24}, &name, format)
        }

        .explorer.requestPreview()
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if (evt.kind != .Pressed and evt.kind != .DoubleClick) or evt.button != .Left
        {
            evt.accepted = false
            return
        }

        let point = .surfaceToLocal(evt.surfacePos) + .scrollPos - Math.Point{12, 12}
        if point.x < 0 or point.y < 0 do
            return
        let column = cast(u64, point.x / .cell.x)
        if column >= .columns do
            return
        let row = cast(u64, point.y / .cell.y) * .columns + column
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
