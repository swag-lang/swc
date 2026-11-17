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

// The same first page the comic reader opens supplies the Explorer cover. A cover needs only the
// page order, so what the book says of itself is not read.
private func loadThumbnail(fileName: string, maxSide: u32)->Image fail
{
    let book  = try Book.loadPages(fileName)
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
                                 cast(s32, Math.max(Math.round(drawing.height * scale), 1)),
                                 2)
    }

    var image = try Image.decode(entry.path, bytes.toSlice())
    image.orient(Exif.orientationOf(image.metadata.toSlice()))
    let largest = Math.max(image.width, image.height)
    if largest > maxSide
    {
        let scale = cast(f32, maxSide) / cast(f32, largest)
        image.resize(Math.max(1, cast(s32, cast(f32, image.width) * scale)),
                     Math.max(1, cast(s32, cast(f32, image.height) * scale)),
                     .Bilinear)
    }

    return image
}

// What the `ComicInfo.xml` of a book says of it: the common fields, as written.
struct ComicInfo
{
    title:       String
    series:      String
    number:      String
    volume:      String
    writer:      String
    penciller:   String
    publisher:   String
    year:        String
    rightToLeft: bool     // The book is a manga read from right to left.
}

impl ComicInfo
{
    // Reads the fields of a `ComicInfo.xml` document; an unknown or damaged element is passed over.
    func read(source: string)->ComicInfo
    {
        var result: #returntype
        var scanner = Package.Scanner.create(source)
        var token:  Package.Token
        var depth   = 0'u32
        var field:  String
        while scanner.next(&token)
        {
            switch token.kind
            {
            case .Start:
                if token.empty do
                    break
                depth += 1
                if depth == 2 do
                    field = #move token.name

            case .End:
                if depth do
                    depth -= 1
                field.clear()

            case .Text:
                if depth != 2 or field.isEmpty() do
                    break
                let text = Latin1.trim(token.text.toString())
                switch field.toString()
                {
                case "Title":     result.title = text
                case "Series":    result.series = text
                case "Number":    result.number = text
                case "Volume":    result.volume = text
                case "Writer":    result.writer = text
                case "Penciller": result.penciller = text
                case "Publisher": result.publisher = text
                case "Year":      result.year = text
                case "Manga":     result.rightToLeft = text == "YesAndRightToLeft"
                }
            }
        }

        return result
    }

    // Reports whether the book says nothing the sheet writes.
    mtd const isEmpty()->bool
    {
        for value in [.title.toString(), .series.toString(), .number.toString(), .volume.toString(), .writer.toString(), .penciller.toString(), .publisher.toString(), .year.toString()] where value.count do
            return false
        return true
    }

    // Appends what the book says of itself to the information sheet, under its own names.
    mtd const describe(data: *MediaInfoData)
    {
        if not .title.isEmpty() do
            data.add(.Title, .title)
        if not .writer.isEmpty() do
            data.add(.Author, .writer)
        for row in [{name: "Series", value: .series.toString()}, {name: "Number", value: .number.toString()}, {name: "Volume", value: .volume.toString()},
                    {name: "Penciller", value: .penciller.toString()}] where row.value.count do
            data.addText(row.name, row.value)
        if not .publisher.isEmpty() do
            data.add(.Publisher, .publisher)
        if not .year.isEmpty() do
            data.add(.Published, .year)
    }
}

// The largest `ComicInfo.xml` read; the metadata of a book is a few kilobytes.
const ComicInfoLimit = 256'u64 * 1024

// The archive and its image entries in natural reading order, with what the book says of itself.
struct Book
{
    archive: Archive.Zip
    pages:   Array'u64
    info:    ComicInfo
}

impl Book
{
    // Lists decodable images; non-image members of the archive are not reading pages. What the
    // book says of itself is left empty: `Book.load` reads it too.
    func loadPages(fileName: string)->Book fail
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

    // Lists the reading pages, then reads what the book says of itself: a `ComicInfo.xml` at the
    // root of the book describes it; one that cannot be read says nothing.
    func load(fileName: string)->Book fail
    {
        var result = try Book.loadPages(fileName)
        for &entry in result.archive.entries where not entry.isDirectory and
                                                   entry.uncompressedSize <= ComicInfoLimit and
                                                   Utf8.compare(entry.path, "ComicInfo.xml", .Latin1NoCase) == 0
        {
            let bytes = catch Archive.Zip.loadEntry(fileName, entry) { break }
            result.info = ComicInfo.read(cast(string, bytes.toSlice()))
            break
        }

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
    rightToLeft:        bool
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

        // A manga that says it reads from right to left turns its pages that way from the start.
        if .book.info.rightToLeft do
            .rightToLeft = true
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
        let direction = Viewer.pageKeyDirection(evt)
        if direction
        {
            .turn(direction)
            return
        }

        if evt.kind != .Pressed or evt.modifiers != .None
        {
            evt.accepted = false
            return
        }

        switch evt.key
        {
        case .Left:  .turn(.rightToLeft ? 1 : -1)
        case .Right: .turn(.rightToLeft ? -1 : 1)
        default:     evt.accepted = false
        }
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged
        {
            .previousButton.toolTip = appStrings().ui_PreviousPage
            .nextButton.toolTip     = appStrings().ui_NextPage
            .refreshNavigation()
        }

        .wnd.IWnd.onNotifyEvent(evt)
    }
}

private impl Panel
{
    mtd refreshNavigation()
    {
        let page    = .pendingPage != Swag.U64.Max ? .pendingPage : .activePage
        let hasPage = page != Swag.U64.Max
        .previousButton.enable(hasPage and page > 0)
        .nextButton.enable(hasPage and page + 1 < .book.pages.count)
        .pageLabel.setText(hasPage ? Viewer.pageText(page, .book.pages.count) : "")
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

    mtd toggleReadingDirection()
    {
        .rightToLeft = not .rightToLeft
    }

    internal mtd goToTypedPage(text: string)->bool
    {
        var parseErrorOutcome: Swag.Error
        var parsed: #decltype(expect StrConv.parseU64(text))
        catch { parsed = try StrConv.parseU64(text) } as parseErrorOutcome
        let parseError = parseErrorOutcome.value()
        if parseError != null or
           parsed.eat != text.count or
           parsed.ovf or
           not parsed.value or
           parsed.value > .book.pages.count do
            return false
        .showPage(parsed.value - 1)
        return true
    }

    mtd promptGoToPage()
    {
        if not .surface or .book.pages.isEmpty() do
            return
        var options: EditDlgOptions
        options.title   = texts().ui_GoToPage
        options.message = Format.toString(texts().ui_PageRange, .book.pages.count).toString()
        options.text    = Format.toString("%", .activePage + 1).toString()
        let dialog = EditDlg.createSingleLine(.surface, options)
        if dialog.doModal() != Dialog.BtnOk do
            return
        discard .goToTypedPage(dialog.text())
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
        let entry     = &.book.archive.entries[.book.pages[.activePage]]
        let extension = Path.lowercaseExtension(entry.path)
        var name      = Format.toString("swagscope-comic-%", Guid64.random())
        name         += extension
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
        // `:` and a page number go to that page.
        if entries.results.prefix == .Line
        {
            let typed = Latin1.trim(entries.query.toString())
            let page  = catch StrConv.toU64(typed) { return; }
            for c in typed where not Latin1.isDigit(c) do
                return
            if not page or page > .book.pages.count do
                return
            let entry = entries.add(Format.toString(appStrings().lens_GoToPage, page), .GoTo, func|view = me, page|() { view.showPage(page - 1) })
            if entry do
                entry.lead = Format.toString("%", page)
            return
        }

        entries.add(texts().ui_Previous, .ChevronLeft, func|view = me|() { view.turn(-1) }, shortcut: Input.formatKeyShortcut(.None, .Left))
        entries.add(texts().ui_Next, .ChevronRight, func|view = me|() { view.turn(1) }, shortcut: Input.formatKeyShortcut(.None, .Right))
        entries.add(texts().ui_GoToPage, .GoTo, func|view = me|() { view.promptGoToPage() })
        entries.add(texts().ui_RightToLeft, .Sort, func|view = me|() { view.toggleReadingDirection() }, checked: .rightToLeft, shortcut: Input.formatKeyShortcut(.Control, .R))
    }

    // Describes the book in the information sheet: its pages, then what its `ComicInfo.xml` says.
    internal mtd describeInformation(sheet: *InfoSheet)
    {
        if not .book.pages.count do
            return
        var data: MediaInfoData
        data.addFigure(.Pages, .book.pages.count == 1 ? String.from(texts().ui_OnePage) : Format.toString(texts().ui_Pages, .book.pages.count))
        if not .book.info.isEmpty()
        {
            data.add(.Document, group: true)
            .book.info.describe(&data)
        }

        data.describe(sheet)
    }

    func create(host: Viewer.Host)->*Panel
    {
        let services    = host.services()
        with let result = Wnd.create'Panel(host.contentParent(), "scope.comic")
        {
            .backgroundStyle = .View
            .focusPolicy     = .Tab
            .sourceFile      = host.fileName()
            .services        = services
        }

        let info       = host.createCommandGroup(Viewer.pageControlWidth(result.themeMetrics()))
        let actionSize = themeActionButtonSize(result.themeMetrics())
        with result.previousButton = Viewer.createPageStep(info, -1)
        {
            .dockStyle       = .Left
            .preferredSize.x = actionSize
            .toolTip         = appStrings().ui_PreviousPage
            .sigPressed      += func|view = result|(_) { view.turn(-1) }
        }

        with result.pageLabel = Viewer.createPageReadout(info, "scope.comic.page", texts().ui_GoToPage)
        {
            .sigPressed += func|view = result|(_) { view.promptGoToPage() }
        }

        with result.nextButton = Viewer.createPageStep(info, 1)
        {
            .dockStyle       = .Left
            .preferredSize.x = actionSize
            .toolTip         = appStrings().ui_NextPage
            .sigPressed      += func|view = result|(_) { view.turn(1) }
        }

        result.embedded = host.createEmbedded(result, host.createInfoGroup(256))
        with result.status = Label.create(result, texts().ui_Preparing, {}, null, .WordWrap)
        {
            .dockStyle       = .Center
            .wndFlags        |= .TopMost
            .backgroundStyle = .View
            .setTextAlignment(.Center, .Center)
        }

        result.hookOnChildEvent = func|result|(_, evt)
        {
            if evt is KeyEvent as key
            {
                let direction = Viewer.pageKeyDirection(key)
                if direction
                {
                    result.turn(direction)
                    return true
                }
            }

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
    host.setInformation(func|view|(sheet) { view.describeInformation(sheet) })
    with var lifecycle: Viewer.LifecycleApi
    {
        .isLoading = func|view|()->bool => view.load.isPending() or view.extract.started or view.embedded.isLoading()
        .needsLoadingOverlay = func|view|()->bool => view.load.isPending()
        .retire    = func|view|()->bool => view.retire()
    }

    host.setLifecycle(lifecycle)
}
