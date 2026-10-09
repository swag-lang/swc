#global internal
#global namespace Viewers.Archive

using Core, Gui

private const TreeWidth = 380.0

// Orders archive tree rows with directories before files at every level, then by natural name.
//
// Directory rows carry no entry payload, including empty explicit directories.
func compareTreeLines(a, b: *ListLine?, column: u32, descending: bool)->s32
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
private func pluginProbe(content: Viewer.ProbeContent)->bool
{
    if not content.startsWith("PK") or content.head.count < 4 do
        return false
    return (content.head[2] == 3 and content.head[3] == 4) or (content.head[2] == 5 and content.head[3] == 6)
}

// Describes the ZIP archive viewer to the host.
func viewerPlugin()->Viewer.Plugin
{
    with var result: retval
    {
        .key          = "archive"
        .staticName   = "Archive"
        .resolveName  = func()->string => texts().ui_Name
        .attach       = &registerTexts
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32, ViewerIcons.Archive)
        .create       = &createViewer
        .probe        = &pluginProbe
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
    error:           String
}

impl ZipEntryExtract
{
    // Extracts `entry` of the archive to `destination` on the worker task. The caller polls for
    // completion and then reads `error`.
    mtd start(archiveFileName: string, entry: const *ZipEntry, destination: string)
    {
        Swag.assert(not .started)
        .archiveFileName = archiveFileName
        .entry           = entry[]
        .destination     = destination
        .error.clear()
        .started = true

        let operation = me
        .task.submit(func|operation|()
        {
            catch Zip.extractEntry(operation.archiveFileName, &operation.entry, operation.destination) as extractError
            operation.error = Viewer.failureText(extractError)
        })
    }

    mtd finish()->String
    {
        Swag.assert(.isDone())
        .wait()
        return #move .error
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
struct Panel
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

    late embedded:  Viewer.Embedded
    archive:        Zip
    entryLines:     Array'(*ListLine?)
    load:           Viewer.BackgroundLoad'Zip
    extract:        ZipEntryExtract
    previewTimer:   *Timer?
    pendingPreview: u64 = Swag.U64.Max
    activePreview:  u64 = Swag.U64.Max
    previewFile:    String
    sourceFile:     String
    services:       Viewer.HostServices
    failureReason:  String
}

private impl IWnd for Panel
{
    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer == .load.timer
        {
            if not .load.poll() do
                return
            .failureReason = .load.finish(&.archive)
            if not .failureReason.isEmpty()
            {
                .services.failed(me, .failureReason)
                return
            }

            .publishArchive()
            .services.loadingChanged(me)
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

private impl Panel
{
    mtd publishArchiveDetails()
    {
        let text = Format.toString(texts().ui_Details,
                                   .archive.entries.count,
                                   StrConv.toDisplaySize(.archive.uncompressedSize),
                                   StrConv.toDisplaySize(.archive.compressedSize))
        .services.showDetails(me, text)
    }

    mtd fileIcon(entry: const *ZipEntry)->Icon
    {
        if entry.isDirectory do
            return .app().directoryIcon(entry.path, true)
        return .app().fileIcon(entry.path, true)
    }

    // Fills the entry tree from the archive listing, creating each folder once even when the
    // archive records only the files inside it, then expands the top-level folders and sorts by
    // name.
    mtd publishArchive()
    {
        .list.clear()
        .entryLines.clear()
        .entryLines.resize(.archive.entries.count)

        var folders: HashTable'(String, *ListLine)
        for &entry, entryIndex in .archive.entries
        {
            let parts = Tokenize.split(entry.path, '/'rune)
            var prefix: String
            var parent: *ListLine?
            for part, partIndex in parts where part.count
            {
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

                    let line = .list.createLine(part, .app().directoryIcon(prefix, true), parent)
                    folders.add(prefix, line)
                    parent = line
                    if isLeaf do
                        .entryLines[entryIndex] = line
                    continue
                }

                let line = .list.createLine(parent)
                line.setItem(0, part, .fileIcon(entry))
                line.setItem(1, StrConv.toDisplaySize(entry.uncompressedSize))
                line.userData0 = cast(*void?, entryIndex + 1)
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
            .showPreviewStatus(texts().ui_Empty)
        else do
            .showPreviewStatus(texts().ui_Select)
        .publishArchiveDetails()
    }

    mtd selectedEntryIndex()->u64
    {
        let line = .list.selectedLine()
        if not line or not line.userData0 do
            return Swag.U64.Max
        return cast(u64, line.userData0) - 1
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
        .showPreviewStatus(texts().ui_Previewing)
        if not .previewTimer do
            .previewTimer = .addTimer(Viewer.BackgroundPollInterval)
        .continuePreview()
    }

    mtd clearPreviewFile()
    {
        if .previewFile.isEmpty() do
            return
        catch File.delete(.previewFile)
        .previewFile.clear()
        .activePreview = Swag.U64.Max
    }

    // Advances the preview from the preview timer: opens the extracted entry once its extraction
    // finishes, then retires the previous embedded viewer and extracts the next pending entry to a
    // temporary file. A newer selection supersedes the extraction in flight.
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
                .showPreviewStatus(Format.toString("%\n%", texts().ui_PreviewError, error))
                return
            }

            if .pendingPreview != Swag.U64.Max and .pendingPreview != .activePreview
            {
                .clearPreviewFile()
            }
            else
            {
                let entry = &.archive.entries[.activePreview]
                catch .embedded.open(.previewFile, entry.path) as openError
                if openError != null
                {
                    .showPreviewStatus(Format.toString("%\n%", texts().ui_PreviewError, Viewer.failureText(openError)))
                    return
                }

                .previewStatus.hide()
            }
        }

        if .pendingPreview == Swag.U64.Max
        {
            .stopTimer(&.previewTimer)

            return
        }

        if not .embedded.retire() do
            return

        .clearPreviewFile()
        let index = .pendingPreview
        .pendingPreview = Swag.U64.Max
        .activePreview  = index
        let entry     = &.archive.entries[index]
        var extension = String.from(Path.extension(entry.path) orelse ".bin")
        let safeName  = Format.toString("entry%", extension)
        if extension.length > 24 or not Path.isValidFileName(safeName) do
            extension = ".bin"
        var tempName = Format.toString("swagscope-archive-%", Guid64.random())
        tempName     += extension
        .previewFile = Path.combine(Env.getSpecialDirectory(.Temp), tempName)
        .extract.start(.sourceFile, entry, .previewFile)
    }

    mtd showPreviewStatus(text: string)
    {
        .previewStatus.setText(text)
        .previewStatus.show()
        .previewStatus.bringToFront()
    }

    // Selects the entry line of `match`, expanding the folders above it. Returns false when the
    // entry has no line in the tree.
    mtd revealMatch(match: Viewer.SearchMatch, _: string)->bool
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
        let name = Pixel.RichString.plainText(line.items[0]!.name.raw)
        return Viewer.listCellMatchBounds(.list, .list.focusIndex, 0, name, 0, name.length, result)
    }

    mtd collectMatches(text: string, options: Viewer.SearchOptions, result: *Array'Viewer.SearchMatch)
    {
        for &entry, index in .archive.entries do
            Viewer.collectTextMatches(entry.path, text, options, index, 0, 0, result)
    }

    mtd clearSearch()
    {
        .list.unselectAll()
    }

    mtd describeSearch(result: *Viewer.SearchPresentation)
    {
        result.placeholder = texts().ui_SearchPlaceholder
        result.canFilter   = false
    }

    mtd retranslate()
    {
        .list.header.itemAt(0).name = texts().ui_ColName
        .list.header.itemAt(1).name = texts().ui_ColSize
        .list.header.invalidate()
        if .activePreview == Swag.U64.Max and not .extract.started do
            .showPreviewStatus(.archive.entries.isEmpty() and not .load.isPending() ? texts().ui_Empty : texts().ui_Select)
    }

    mtd retire()->bool
    {
        if not .load.retire() or not .extract.retire() or not .embedded.retire() do
            return false
        .stopTimer(&.previewTimer)

        .clearPreviewFile()
        return true
    }

    // Builds the archive panel: a splitter holding the entry tree and the preview pane. Loads the
    // archive listing in the background.
    func create(host: Viewer.Host)->*Panel
    {
        let services = host.services()

        with let result = Wnd.create'Panel(host.contentParent(), "scope.archive")
        {
            .backgroundStyle = .View
            .sourceFile      = host.fileName()
            .services        = services
        }

        result.splitter = SplitterCtrl.create(result)
        result.splitter.dockStyle = .Center
        result.createEntryTree()
        result.createPreviewPane(host)

        with let treeItem = result.splitter.addPane(result.treePane, TreeWidth)
        {
            .size         = TreeWidth
            .minimumSize  = 260
            .maximumSize  = 560
            .preserveSize = true
        }

        result.splitter.addPane(result.previewPane).minimumSize = 320
        result.load.startPolled(result, host.fileName(), &Zip.load)
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
            .compareLines = &compareTreeLines
            .setSelectionMode(.Single)
            .setIconSize(themeRowIconSize(me.themeMetrics()))
            .updateFlags(.HotTrack | .Ellipsis)
            .scrollWnd.updateFlags(.DisableHorizontal)
            .header.form = .Transparent
            .addColumn(texts().ui_ColName, 170)
            .addColumn(texts().ui_ColSize, 60)
            .sigSelectionChanged += func|viewer = me|(_)
            {
                viewer.previewSelectedEntry()
            }

            .sigLeftDoubleClicked += func|viewer = me|(_, _)
            {
                viewer.previewSelectedEntry()
            }

            .sigKeyPressed += func|viewer = me|(_, event)
            {
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
        with .previewStatus = Label.create(me.previewPane, texts().ui_Select, {}, null, .WordWrap)
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
func createViewer(host: Viewer.Host)
{
    let view = Panel.create(host)
    host.attachView(view)

    var search = Viewer.searchApi(view)
    search.describe = func|view|(presentation) => view.describeSearch(presentation)
    host.setSearch(search)

    with var lifecycle: Viewer.LifecycleApi
    {
        .isLoading = func|view|()->bool => view.load.isPending() or view.extract.started or view.embedded.isLoading()
        .needsLoadingOverlay = func|view|()->bool => view.load.isPending()
        .retire    = func|view|()->bool => view.retire()
    }

    host.setLifecycle(lifecycle)
}
