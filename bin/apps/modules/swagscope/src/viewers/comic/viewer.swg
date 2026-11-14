#global internal
#global namespace Viewers.Comic

using Core, Pixel, Gui

// Offers a sequence of image pages for a comic-book ZIP file.
func viewerPlugin()->Viewer.Plugin
{
    with var result: #returntype
    {
        .key          = "comic"
        .staticName   = "Comic book"
        .resolveName  = func()->string => texts().ui_Name
        .attach       = &registerTexts
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32, ViewerIcons.Comic)
        .create       = &createViewer
        .thumbnail    = &loadThumbnail
        .smokeFixture = "viewer.comic.cbz"
        .addSelectors(".cbz")
    }
    return result
}

// The same first page the comic reader opens supplies the Explorer cover.
private func loadThumbnail(fileName: string, maxSide: u32)->Image fail
{
    let book  = try Book.load(fileName)
    let entry = &book.archive.entries[book.pages[0]]
    if entry.uncompressedSize > 32 * 1024 * 1024'u64 do
        fail Errors.UnsupportedFormatError{"comic page exceeds the thumbnail budget"}

    let bytes = try Archive.Zip.loadEntry(fileName, entry)
    if Path.lowercaseExtension(entry.path) == ".svg"
    {
        let drawing = try Svg.Drawing.parse(cast(string, bytes.toSlice()))
        let largest = Math.max(drawing.width, drawing.height, 1)
        let scale   = Math.min(cast(f32, maxSide) / largest, 1)
        return drawing.rasterize(cast(s32, Math.max(Math.round(drawing.width * scale), 1)),
                                 cast(s32, Math.max(Math.round(drawing.height * scale), 1)), 2)
    }

    var image = try Image.decode(entry.path, bytes.toSlice())
    image.orient(Exif.orientationOf(image.metadata.toSlice()))
    let largest = Math.max(image.width, image.height)
    if largest > maxSide
    {
        let scale = cast(f32, maxSide) / cast(f32, largest)
        image.resize(Math.max(1, cast(s32, cast(f32, image.width) * scale)),
                     Math.max(1, cast(s32, cast(f32, image.height) * scale)), .Bilinear)
    }
    return image
}

// The archive and its image entries in natural reading order.
struct Book
{
    archive: Archive.Zip
    pages:   Array'u64
}

impl Book
{
    // Lists decodable images; non-image members of the archive are not reading pages.
    func load(fileName: string)->Book fail
    {
        var result: #returntype
        result.archive = try Archive.Zip.load(fileName)
        for &entry, index in result.archive.entries where not entry.isDirectory and
                                                    (Image.canLoad(entry.path) or Path.lowercaseExtension(entry.path) == ".svg") do
            result.pages.add(index)
        if result.pages.isEmpty() do
            fail Errors.InvalidFormatError{texts().err_NoPages}

        let archive = &result.archive
        result.pages.sort(func|archive|(a, b)->s32 => Latin1.compareNatural(archive.entries[a].path, archive.entries[b].path))
        return result
    }
}

// Shows one extracted image through the ordinary image viewer and keeps its temporary file owned.
struct Panel
{
    using wnd: Wnd

    book:               Book
    load:               Viewer.BackgroundLoad'Book
    extract:            Archive.ZipEntryExtract
    late embedded:      Viewer.Embedded
    sourceFile:         String
    previewFile:        String
    services:           Viewer.HostServices
    pendingPage:        u64 = Swag.U64.Max
    activePage:         u64 = Swag.U64.Max
    awaitingRetirement: bool
    retiring:           bool
    retryTimer:         *Timer?

    late
    {
        status:         *Label
        previousButton: *IconButton
        nextButton:     *IconButton
        pageLabel:      *IconButton
    }
}

private impl IWnd for Panel
{
    mtd impl onTaskEvent(evt: *TaskEvent)
    {
        if .extract.claim(evt)
        {
            .continuePage()
            return
        }
        if not .load.claim(evt)
        {
            evt.accepted = false
            return
        }

        let failure = .load.finish(&.book)
        if not failure.isEmpty()
        {
            .services.failed(me, failure)
            return
        }

        .refreshNavigation()
        .showPage(0)
        .services.loadingChanged(me)
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .retryTimer
        {
            evt.accepted = false
            return
        }
        .stopTimer(&.retryTimer)
        .continuePage()
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind != .Pressed or evt.modifiers != .None
        {
            evt.accepted = false
            return
        }

        switch evt.key
        {
        case .Left:  .turn(-1)
        case .Right: .turn(1)
        default:     evt.accepted = false
        }
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged
        {
            .previousButton.toolTip = texts().ui_Previous
            .nextButton.toolTip     = texts().ui_Next
            .refreshNavigation()
        }
        .wnd.IWnd.onNotifyEvent(evt)
    }
}

private impl Panel
{
    mtd refreshNavigation()
    {
        let page = .pendingPage != Swag.U64.Max ? .pendingPage : .activePage
        let hasPage = page != Swag.U64.Max
        .previousButton.enable(hasPage and page > 0)
        .nextButton.enable(hasPage and page + 1 < .book.pages.count)
        .pageLabel.setText(hasPage ? Format.toString("% / %", page + 1, .book.pages.count) : "")
        if hasPage do
            .services.showDetails(me, Format.toString(texts().ui_Details, page + 1, .book.pages.count))
    }

    internal mtd turn(delta: s32)
    {
        let page = .pendingPage != Swag.U64.Max ? .pendingPage : .activePage
        if page == Swag.U64.Max do
            return
        if delta < 0 and page > 0 do
            .showPage(page - 1)
        elif delta > 0 and page + 1 < .book.pages.count do
            .showPage(page + 1)
    }

    mtd showPage(index: u64)
    {
        if index >= .book.pages.count or index == .pendingPage or index == .activePage do
            return
        .pendingPage = index
        .status.setText(texts().ui_Preparing)
        .status.show()
        .status.bringToFront()
        .refreshNavigation()
        .continuePage()
    }

    mtd clearPreviewFile()
    {
        if .previewFile.isEmpty() do
            return
        discard catch File.delete(.previewFile)
        .previewFile.clear()
        .activePage = Swag.U64.Max
    }

    // Retires an old embedded page before extracting a new one; task notifications drive each step.
    mtd continuePage()
    {
        if .retiring do
            return

        if .extract.started
        {
            if not .extract.isDone() do
                return
            let failure = .extract.finish()
            if not failure.isEmpty()
            {
                .previewFile.clear()
                .status.setText(failure)
                .services.failed(me, failure)
                return
            }

            if .pendingPage == Swag.U64.Max or .pendingPage == .activePage
            {
                let entry = &.book.archive.entries[.book.pages[.activePage]]
                catch .embedded.open(.previewFile, entry.path)
                {
                    .services.failed(me, Viewer.failureText(Swag.err))
                    return
                }
                .status.hide()
                .services.loadingChanged(me)
                return
            }
        }

        if .pendingPage == Swag.U64.Max do
            return
        if not .embedded.retire()
        {
            .awaitingRetirement = true
            return
        }

        .clearPreviewFile()
        .activePage  = .pendingPage
        .pendingPage = Swag.U64.Max
        let entry    = &.book.archive.entries[.book.pages[.activePage]]
        let extension = Path.lowercaseExtension(entry.path)
        var name = Format.toString("swagscope-comic-%", Guid64.random())
        name += extension
        .previewFile = Path.combine(Env.getSpecialDirectory(.Temp), name)
        .extract.start(.sourceFile, entry, .previewFile, me)
        .refreshNavigation()
    }

    mtd retryPreview()
    {
        if not .awaitingRetirement do
            return
        .awaitingRetirement = false
        if not .retryTimer do
            .retryTimer = .addTimer(1'ms)
    }

    mtd retire()->bool
    {
        .retiring = true
        if not .load.retire() or not .extract.retire() or not .embedded.retire() do
            return false
        .stopTimer(&.retryTimer)
        .clearPreviewFile()
        return true
    }

    mtd describeLens(entries: *Viewer.LensEntries)
    {
        entries.add(texts().ui_Previous, .ChevronLeft, func|view = me|() { view.turn(-1) }, shortcut: Input.formatKeyShortcut(.None, .Left))
        entries.add(texts().ui_Next, .ChevronRight, func|view = me|() { view.turn(1) }, shortcut: Input.formatKeyShortcut(.None, .Right))
    }

    func create(host: Viewer.Host)->*Panel
    {
        let services = host.services()
        with let result = Wnd.create'Panel(host.contentParent(), "scope.comic")
        {
            .backgroundStyle = .View
            .sourceFile      = host.fileName()
            .services        = services
        }

        let info = host.createInfoGroup(168)
        let actionSize = themeActionButtonSize(result.themeMetrics())
        with result.previousButton = Viewer.createActionButton(info, .ChevronLeft)
        {
            .dockStyle       = .Left
            .preferredSize.x = actionSize
            .toolTip         = texts().ui_Previous
            .sigPressed      += func|view = result|(_) { view.turn(-1) }
        }
        with result.pageLabel = IconButton.create(info, {}, {0, 0, 80, 32}, "scope.comic.page", .CenterContent)
        {
            .dockStyle       = .Left
            .preferredSize.x = 80
            .margin.x        = 8
            .setForm(.Rectangle)
        }
        with result.nextButton = Viewer.createActionButton(info, .ChevronRight)
        {
            .dockStyle       = .Left
            .preferredSize.x = actionSize
            .toolTip         = texts().ui_Next
            .sigPressed      += func|view = result|(_) { view.turn(1) }
        }

        result.embedded = host.createEmbedded(result)
        with result.status = Label.create(result, texts().ui_Preparing, {}, null, .WordWrap)
        {
            .dockStyle       = .Center
            .wndFlags        |= .TopMost
            .backgroundStyle = .View
            .setTextAlignment(.Center, .Center)
        }
        result.hookOnChildEvent = func|result|(_, evt)
        {
            if evt is TaskEvent do
                result.retryPreview()
            return false
        }

        result.refreshNavigation()
        result.load.start(host.fileName(), &Book.load, result)
        result.applyLayout()
        return result
    }
}

// Creates the sequential comic-book reader.
func createViewer(host: Viewer.Host)
{
    let view = Panel.create(host)
    host.attachView(view)
    host.setLensSource(func|view|(entries) { view.describeLens(entries) })
    with var lifecycle: Viewer.LifecycleApi
    {
        .isLoading = func|view|()->bool => view.load.isPending() or view.extract.started or view.embedded.isLoading()
        .needsLoadingOverlay = func|view|()->bool => view.load.isPending()
        .retire = func|view|()->bool => view.retire()
    }
    host.setLifecycle(lifecycle)
}
