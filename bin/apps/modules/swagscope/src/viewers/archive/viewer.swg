#global internal

using Core, Gui

private const ArchiveTreeWidth = 380.0

// Orders archive tree rows with directories before files at every level, then by natural name.
//
// Directory rows carry no entry payload, including empty explicit directories.
func compareArchiveTreeLines(a, b: *ListLine?, column: u32, descending: bool)->s32
{
    if not a or not b do
        return 0

    let aFolder = a.userData0 == null
    let bFolder = b.userData0 == null
    if aFolder != bFolder do
        return aFolder ? -1 : 1

    let sortColumn = column < a.items.count and column < b.items.count ? column : 0
    let aItem      = a.itemAt(sortColumn)
    let bItem      = b.itemAt(sortColumn)
    let aText      = aItem.sortKey.isEmpty() ? &aItem.name.raw : &aItem.sortKey
    let bText      = bItem.sortKey.isEmpty() ? &bItem.name.raw : &bItem.sortKey
    var result     = Latin1.compareNatural(aText[], bText[])
    if descending do
        result *= -1
    return result
}

// Reports whether the content is a ZIP container, whatever the format built on it is called.
//
// An archive opens either on the header of its first entry or, when it holds nothing at all, on
// its end record.
private func archivePluginProbe(content: Viewer.ProbeContent)->bool
{
    if not content.startsWith("PK") or content.head.count < 4 do
        return false
    return (content.head[2] == 3 and content.head[3] == 4) or (content.head[2] == 5 and content.head[3] == 6)
}

// Describes the ZIP archive viewer to the host.
func archiveViewerPlugin()->Viewer.Plugin
{
    with var result: retval
    {
        .key          = "archive"
        .staticName   = "Archive"
        .resolveName  = func()->string => archiveStrings().ui_Name
        .attach       = &registerArchiveStrings
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32) ViewerIcons.Archive
        .create       = &createArchiveViewer
        .probe        = &archivePluginProbe
        .smokeFixture = "viewer.archive.zip"
        .addSelectors(".zip;.jar;.war;.apk;.aar;.epub;.whl;.nupkg;.vsix;.crx;.xpi;.docx;.xlsx;.pptx;.odt;.ods;.odp")
    }

    return result
}

// Extracts one archive entry to a disposable preview file away from the GUI thread.
struct ZipEntryExtract
{
    using operation: Viewer.BackgroundOperation
    archiveFileName: String
    entry:           ZipEntry
    destination:     String
    error:           any?
}

impl ZipEntryExtract
{
    mtd start(archiveFileName: string, entry: const *ZipEntry, destination: string)
    {
        Swag.assert(not .started)
        .archiveFileName = archiveFileName
        .entry           = entry[]
        .destination     = destination
        .error           = null
        .started         = true

        let operation = me
        .task.submit(func|operation|()
        {
            catch extractZipEntry(operation.archiveFileName.toString(), &operation.entry, operation.destination.toString()) as extractError
            operation.error = extractError
        })
    }

    mtd finish()->String
    {
        Swag.assert(.isDone())
        .wait()
        let result = Errors.message(.error)
        .error = null
        return result
    }

    mtd retire()->bool
    {
        if not .started do
            return true
        if not .isDone() do
            return false
        .wait()
        return true
    }

    mtd opDrop()
    {
        .wait()
    }
}

// Shows the entries of a ZIP archive as a folder tree beside a preview of the selected file.
//
// The preview opens the extracted entry through the ordinary viewer registry.
struct ArchiveViewer
{
    using wnd: Wnd

    late
    {
        splitter:      *SplitterCtrl
        treePane:      *Wnd
        list:          *ListCtrl
        previewPane:   *Wnd
        previewStatus: *Label
    }

    late embedded:        Viewer.Embedded
    archive:              ZipArchive
    entryLines:           Array'(*ListLine?)
    load:                 Viewer.BackgroundLoad'ZipArchive
    extract:              ZipEntryExtract
    loadTimer:            *Timer?
    previewTimer:         *Timer?
    pendingPreview = Swag.U64.Max
    activePreview  = Swag.U64.Max
    previewFile:          String
    sourceFile:           String
    reportFailure:        Viewer.ReportFailure?
    reportDetails:        Viewer.ReportDetails?
    reportLoadingChanged: Viewer.ReportLoadingChanged?
    failureReason:        String
}

private impl IWnd for ArchiveViewer
{
    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer == .loadTimer
        {
            if not .load.isDone() do
                return
            .removeTimer(evt.timer)
            .loadTimer     = null
            .failureReason = .load.finish(&.archive)
            if not .failureReason.isEmpty()
            {
                if .reportFailure do
                    .reportFailure(me, .failureReason.toString())
                return
            }

            .publishArchive()
            if .reportLoadingChanged do
                .reportLoadingChanged(me)
            return
        }

        if evt.timer == .previewTimer
        {
            if .extract.started and not .extract.isDone() do
                return
            .continuePreview()
            return
        }

        evt.accepted = false
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged
        {
            .retranslate()
            if not .archive.entries.isEmpty() do
                .publishArchiveDetails()
        }

        .wnd.IWnd.onNotifyEvent(evt)
    }
}

private impl ArchiveViewer
{
    mtd publishArchiveDetails()
    {
        if not .reportDetails do
            return
        let text = Format.toString(archiveStrings().ui_Details,
                                   .archive.entries.count,
                                   StrConv.toDisplaySize(.archive.uncompressedSize),
                                   StrConv.toDisplaySize(.archive.compressedSize))
        .reportDetails(me, text.toString())
    }

    mtd fileIcon(entry: const *ZipEntry)->Icon
    {
        if entry.isDirectory do
            return .app().directoryIcon(entry.path.toString(), true)
        return .app().fileIcon(entry.path.toString(), true)
    }

    mtd publishArchive()
    {
        .list.clear()
        .entryLines.clear()
        .entryLines.resize(.archive.entries.count)

        var folders: HashTable'(String, *ListLine)
        for &entry, entryIndex in .archive.entries
        {
            let parts = Tokenize.split(entry.path.toString(), '/'rune)
            var prefix: String
            var parent: *ListLine?
            for part, partIndex in parts
            {
                if not part.count do
                    continue
                if not prefix.isEmpty() do
                    prefix += '/'u8
                prefix += part
                let isLeaf = partIndex + 1 == parts.count
                if not isLeaf or entry.isDirectory
                {
                    let found = folders.tryFind(prefix)
                    if found
                    {
                        parent = found.value
                        continue
                    }

                    let line = .list.createLine(part, .app().directoryIcon(prefix.toString(), true), parent)
                    folders.add(prefix, line)
                    parent = line
                    if isLeaf do
                        .entryLines[entryIndex] = line
                    continue
                }

                let line = .list.createLine(parent)
                line.setItem(0, part, .fileIcon(entry))
                line.setItem(1, StrConv.toDisplaySize(entry.uncompressedSize).toString())
                line.userData0 = cast(*void?) (entryIndex + 1)
                .entryLines[entryIndex] = line
            }
        }

        var roots: Array'(*ListLine)
        let rootCount = .list.lineCount()
        for index in rootCount
        {
            let line = .list.lineAt(index)
            if line!.canExpand() do
                roots.add(line)
        }

        for line in roots do
            .list.expand(line)
        .list.sort(0, persistent: true)
        .list.computeLayout()
        if .archive.entries.isEmpty() do
            .showPreviewStatus(archiveStrings().ui_Empty)
        else do
            .showPreviewStatus(archiveStrings().ui_Select)
        .publishArchiveDetails()
    }

    mtd selectedEntryIndex()->u64
    {
        let line = .list.selectedLine()
        if not line or not line.userData0 do
            return Swag.U64.Max
        return cast(u64) line.userData0 - 1
    }

    mtd previewSelectedEntry()
    {
        let index = .selectedEntryIndex()
        if index != Swag.U64.Max do
            .requestPreview(index)
    }

    mtd requestPreview(index: u64)
    {
        if index >= .archive.entries.count or .archive.entries[index].isDirectory do
            return
        if index == .pendingPreview or index == .activePreview do
            return
        .pendingPreview = index
        .showPreviewStatus(archiveStrings().ui_Previewing)
        if not .previewTimer do
            .previewTimer = .addTimer(Viewer.BackgroundPollInterval)
        .continuePreview()
    }

    mtd clearPreviewFile()
    {
        if .previewFile.isEmpty() do
            return
        catch File.delete(.previewFile.toString())
        .previewFile.clear()
        .activePreview = Swag.U64.Max
    }

    mtd continuePreview()
    {
        if .extract.started
        {
            if not .extract.isDone() do
                return
            let error = .extract.finish()
            if not error.isEmpty()
            {
                .clearPreviewFile()
                .showPreviewStatus(Format.toString("%\n%", archiveStrings().ui_PreviewError, error).toString())
                return
            }

            if .pendingPreview != Swag.U64.Max and .pendingPreview != .activePreview
            {
                .clearPreviewFile()
            }
            else
            {
                let entry = &.archive.entries[.activePreview]
                catch .embedded.open(.previewFile.toString(), entry.path.toString()) as openError
                if openError != null
                {
                    .showPreviewStatus(Format.toString("%\n%", archiveStrings().ui_PreviewError, Errors.message(openError)).toString())
                    return
                }

                .previewStatus.hide()
            }
        }

        if .pendingPreview == Swag.U64.Max
        {
            if .previewTimer
            {
                .removeTimer(.previewTimer)
                .previewTimer = null
            }

            return
        }

        if not .embedded.retire() do
            return

        .clearPreviewFile()
        let index = .pendingPreview
        .pendingPreview = Swag.U64.Max
        .activePreview  = index
        let entry     = &.archive.entries[index]
        var extension = String.from(Path.extension(entry.path.toString()) orelse ".bin")
        let safeName  = Format.toString("entry%", extension)
        if extension.length > 24 or not Path.isValidFileName(safeName.toString()) do
            extension = ".bin"
        var tempName = Format.toString("swagscope-archive-%", Guid64.random())
        tempName     += extension
        .previewFile = Path.combine(Env.getSpecialDirectory(.Temp).toString(), tempName.toString())
        .extract.start(.sourceFile.toString(), entry, .previewFile.toString())
    }

    mtd showPreviewStatus(text: string)
    {
        .previewStatus.setText(text)
        .previewStatus.show()
        .previewStatus.bringToFront()
    }

    mtd revealEntry(match: Viewer.SearchMatch)->bool
    {
        if match.major >= .entryLines.count do
            return false
        let line = .entryLines[match.major]
        if not line do
            return false

        var chain: Array'(*ListLine)
        var parent = line.parent
        while parent
        {
            chain.add(parent)
            parent = parent.parent
        }

        for folder in chain.reversed() do
            .list.expand(folder)

        for index in .list.lineCount() where .list.lineAt(index) == line
        {
            .list.unselectAll()
            .list.selectLine(index)
            .list.setFocusedIndex(index)
            return true
        }

        return false
    }

    // Reports the bounds of the focused match, marked on the entry name its row shows.
    //
    // A query matches an entry's whole path, and what the reader can see of that path is the
    // name in the tree.
    mtd searchBounds(result: *Math.Rectangle)->bool
    {
        if .list.focusIndex >= .list.lineCount() do
            return false
        let line = .list.lineAt(.list.focusIndex)
        if not line or line.items.isEmpty() do
            return false
        let name = Pixel.RichString.plainText(line.items[0]!.name.raw.toString())
        return Viewer.listCellMatchBounds(.list, .list.focusIndex, 0, name.toString(), 0, name.length, result)
    }

    mtd collectMatches(text: string, options: Viewer.SearchOptions, result: *Array'Viewer.SearchMatch)
    {
        for &entry, index in .archive.entries do
            Viewer.collectTextMatches(entry.path.toString(), text, options, index, 0, 0, result)
    }

    mtd clearSearch()
    {
        .list.unselectAll()
    }

    mtd describeSearch(result: *Viewer.SearchPresentation)
    {
        result.placeholder = archiveStrings().ui_SearchPlaceholder
        result.canFilter   = false
    }

    mtd retranslate()
    {
        .list.header.itemAt(0).name = archiveStrings().ui_ColName
        .list.header.itemAt(1).name = archiveStrings().ui_ColSize
        .list.header.invalidate()
        if .activePreview == Swag.U64.Max and not .extract.started do
            .showPreviewStatus(.archive.entries.isEmpty() and not .loadTimer ? archiveStrings().ui_Empty : archiveStrings().ui_Select)
    }

    mtd retire()->bool
    {
        if not .load.retire() or not .extract.retire() or not .embedded.retire() do
            return false
        if .loadTimer
        {
            .removeTimer(.loadTimer)
            .loadTimer = null
        }

        if .previewTimer
        {
            .removeTimer(.previewTimer)
            .previewTimer = null
        }

        .clearPreviewFile()
        return true
    }

    func create(host: Viewer.Host)->*ArchiveViewer
    {
        let services    = host.services()
        with let result = Wnd.create'ArchiveViewer(host.contentParent(), "scope.archive")
        {
            .backgroundStyle      = .View
            .sourceFile           = host.fileName()
            .reportFailure        = services.reportFailure
            .reportDetails        = services.reportDetails
            .reportLoadingChanged = services.reportLoadingChanged
        }

        result.splitter = SplitterCtrl.create(result)
        result.splitter.dockStyle = .Center
        result.createEntryTree()
        result.createPreviewPane(host)

        with let treeItem = result.splitter.addPane(result.treePane, ArchiveTreeWidth)
        {
            .size         = ArchiveTreeWidth
            .minimumSize  = 260
            .maximumSize  = 560
            .preserveSize = true
        }

        result.splitter.addPane(result.previewPane).minimumSize = 320
        result.load.start(host.fileName(), &loadZipArchive)
        result.loadTimer = result.addTimer(Viewer.BackgroundPollInterval)
        result.applyLayout()
        return result
    }

    // Creates the entry tree, which previews the file a reader selects, double-clicks, or confirms with Enter.
    mtd createEntryTree()
    {
        with .treePane = Wnd.create'Wnd(me.splitter)
        {
            .backgroundStyle = .Panel
            .padding         = {8, 8, 8, 8}
        }

        with .list = ListCtrl.createMultiColumns(me.treePane)
        {
            .dockStyle    = .Center
            .compareLines = &compareArchiveTreeLines
            .setSelectionMode(.Single)
            .setIconSize(themeRowIconSize(me.themeMetrics()))
            .updateFlags(.HotTrack | .Ellipsis)
            .scrollWnd.updateFlags(.DisableHorizontal)
            .header.form = .Transparent
            .addColumn(archiveStrings().ui_ColName, 170)
            .addColumn(archiveStrings().ui_ColSize, 60)
            .sigSelectionChanged += func|viewer = me|(list)
            {
                discard list
                viewer.previewSelectedEntry()
            }

            .sigLeftDoubleClicked += func|viewer = me|(list, point)
            {
                discard list
                discard point
                viewer.previewSelectedEntry()
            }

            .sigKeyPressed += func|viewer = me|(list, event)
            {
                discard list
                if event.key == .Enter and event.modifiers == .None
                {
                    viewer.previewSelectedEntry()
                    event.accepted = true
                }
            }
        }
    }

    // Creates the preview pane, which hosts the embedded viewer under a status label.
    mtd createPreviewPane(host: Viewer.Host)
    {
        with .previewPane = Wnd.create'Wnd(me.splitter)
        {
            .backgroundStyle = .View
        }

        .embedded = host.createEmbedded(.previewPane)
        with .previewStatus = Label.create(me.previewPane, archiveStrings().ui_Select, {}, null, .WordWrap)
        {
            .dockStyle       = .Center
            .wndFlags        |= .TopMost
            .backgroundStyle = .View
            .padding         = {48, 48, 48, 48}
            .setTextAlignment(.Center, .Center)
        }
    }
}

// Creates the integrated archive viewer and connects its search and lifecycle to the host.
func createArchiveViewer(host: Viewer.Host)
{
    let view = ArchiveViewer.create(host)
    host.attachView(view)
    host.setSearch({
        collectMatches: func(wnd, text, options, progress, matches)->bool
    {
        discard progress
        (cast #assume (*ArchiveViewer) wnd).collectMatches(text, options, matches)
        return true
    },
        revealMatch: func(wnd, match, text)->bool
    {
        discard text
        return (cast #assume (*ArchiveViewer) wnd).revealEntry(match)
    },
        matchBounds: func(wnd, match, bounds)->bool
    {
        discard match
        return (cast #assume (*ArchiveViewer) wnd).searchBounds(bounds)
    },
        clear: func(wnd) { (cast #assume (*ArchiveViewer) wnd).clearSearch() },
        describe: func(wnd, presentation) { (cast #assume (*ArchiveViewer) wnd).describeSearch(presentation) }})
    host.setLifecycle({
        isLoading: func(wnd)->bool
    {
        let viewer = cast #assume (*ArchiveViewer) wnd
        return viewer.loadTimer != null or viewer.extract.started or viewer.embedded.isLoading()
    },
        needsLoadingOverlay: func(wnd)->bool => (cast #assume (*ArchiveViewer) wnd).loadTimer != null,
        retire: func(wnd)->bool => (cast #assume (*ArchiveViewer) wnd).retire()})
}
