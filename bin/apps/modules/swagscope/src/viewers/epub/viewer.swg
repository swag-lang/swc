#global internal
#global namespace Viewers.Epub

using Core, Gui

// Offers the book's declared chapter order before the generic archive structure.
func viewerPlugin()->Viewer.Plugin
{
    with var result: #returntype
    {
        .key          = "epub"
        .staticName   = "EPUB"
        .resolveName  = func()->string => texts().ui_Name
        .attach       = &registerTexts
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32, ViewerIcons.Epub)
        .create       = &createViewer
        .smokeFixture = "viewer.epub"
        .thumbnail    = &loadThumbnail
        .addSelectors(".epub")
    }

    return result
}

// The cover the package names supplies the Explorer preview, read without extracting the book. A
// book that names none answers an empty image and keeps the shared preview.
private func loadThumbnail(fileName: string, maxSide: u32)->Image fail
{
    let cover = try loadCover(fileName)
    if cover.bytes.isEmpty() do
        return {}
    if Path.lowercaseExtension(cover.path) == ".svg"
    {
        let drawing = try Svg.Drawing.parse(cast(string, cover.bytes.toSlice()))
        let largest = Math.max(drawing.width, drawing.height, 1)
        let scale   = Math.min(cast(f32, maxSide) / largest, 1)
        return drawing.rasterize(cast(s32, Math.max(Math.round(drawing.width * scale), 1)),
                                 cast(s32, Math.max(Math.round(drawing.height * scale), 1)),
                                 2)
    }

    var image   = try Image.decode(cover.path, cover.bytes.toSlice())
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

enum ReadingColumn { Compact, Comfortable, Wide }

struct ReadingVisit
{
    chapter:  u64
    position: HtmlReadingPosition
    fragment: String
}

impl Panel
{
    // Describes the book in the information sheet: its chapters, then what its package says of it.
    internal mtd describeInformation(sheet: *InfoSheet)
    {
        if not .book.chapters.count do
            return
        var data: MediaInfoData
        let count = .book.chapters.count
        data.addFigure(.Sections, count == 1 ? String.from(texts().ui_OneChapter) : Format.toString(texts().ui_Chapters, count))
        let metadata = &.book.metadata
        data.add(.Document, group: true)
        if not metadata.title.isEmpty() do
            data.add(.Title, metadata.title)
        if not metadata.creators.isEmpty() do
            data.add(.Author, metadata.creators)
        let language = knownLanguage(metadata.language)
        if not language.isEmpty() do
            data.add(.Language, language)
        if not metadata.publisher.isEmpty() do
            data.add(.Publisher, metadata.publisher)
        if not metadata.date.isEmpty() do
            data.add(.Published, metadata.date)
        data.describe(sheet)
    }
}

// Owns book navigation while the HTML control streams the selected chapter and its resources.
struct Panel
{
    using wnd: Wnd

    book:            Book
    load:            Viewer.BackgroundLoad'Book
    services:        Viewer.HostServices
    chapter:         u64 = Swag.U64.Max
    view:            *HtmlView?
    contents:        Array'NavigationEntry
    zoomPercent:     u32 = 100
    readingColumn:   ReadingColumn = .Comfortable
    history:         Viewer.History'ReadingVisit
    pendingPosition: HtmlReadingPosition
    fragment:        String

    late
    {
        outline:        *DocumentOutline
        status:         *Label
        previousButton: *IconButton
        nextButton:     *IconButton
        chapterLabel:   *Label
        zoomLabel:      *IconButton
    }
}

private impl IWnd for Panel
{
    mtd impl onTaskEvent(evt: *TaskEvent)
    {
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

        .publishContents()
        .showChapter(0)
        .services.loadingChanged(me)
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if .handleHistoryKey(evt) do
            return
        let direction = Viewer.pageKeyDirection(evt)
        if direction
        {
            .turn(direction)
            return
        }

        evt.accepted = false
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
    mtd publishContents()
    {
        .contents.clear()
        for entry in .book.navigation.entries where entry.chapter != Swag.U64.Max do
            .contents.add(entry)
        if .contents.isEmpty()
        {
            for chapter, index in .book.chapters
            {
                var entry: NavigationEntry
                entry.title   = chapter.id
                entry.path    = chapter.path
                entry.chapter = index
                .contents.add(#move entry)
            }
        }

        var headings: Array'DocumentHeading
        for entry, index in .contents do
            headings.add(DocumentHeading{entry.title, entry.level, index})
        .outline.publish(headings.toSlice())
        .outline.failure = .book.navigation.failure
        .outline.refresh()
    }

    mtd refreshNavigation()
    {
        let hasChapter = .chapter < .book.chapters.count
        .previousButton.enable(hasChapter and .chapter > 0)
        .nextButton.enable(hasChapter and .chapter + 1 < .book.chapters.count)
        .chapterLabel.setText(hasChapter ? Viewer.pageText(.chapter, .book.chapters.count) : "")
        if hasChapter do
            .services.showDetails(me, Format.toString(texts().ui_Details, .chapter + 1, .book.chapters.count))
    }

    internal mtd turn(delta: s32)
    {
        if .chapter >= .book.chapters.count do
            return
        if delta < 0 and .chapter > 0 do
            .showChapter(.chapter - 1)
        elif delta > 0 and .chapter + 1 < .book.chapters.count do
            .showChapter(.chapter + 1)
    }

    internal mtd selectContents(index: u64)
    {
        if index >= .contents.count do
            return
        let entry = &.contents[index]
        .showChapter(entry.chapter, entry.fragment)
    }

    mtd readingStyle()->HtmlStyle
    {
        var result = HtmlStyle.theme()
        result.bodyFontSize    = cast(u32, Math.max(Math.round(18.0 * cast(f32, .zoomPercent) / 100), 1))
        result.codeFontSize    = cast(u32, Math.max(Math.round(14.0 * cast(f32, .zoomPercent) / 100), 1))
        result.maxContentWidth = .readingColumn == .Compact ? 520 : (.readingColumn == .Wide ? 900 : 680)
        return result
    }

    internal mtd showChapter(index: u64, fragment: string = "", remember = true)
    {
        if index >= .book.chapters.count or fragment.count > 4096 do
            return
        if index == .chapter and .view
        {
            let previous = .currentVisit()
            if .view.navigateToFragment(Format.toString("#%", fragment))
            {
                if remember do
                    .history.visit(previous)

                .fragment        = fragment
                .pendingPosition = {}
                .followReading()
            }

            return
        }

        if remember and .view and .chapter < .book.chapters.count do
            .history.visit(.currentVisit())

        .pendingPosition = {}
        .fragment        = fragment

        .view?.hide()
        .view?.destroy()
        .chapter = index
        let path  = Path.combine(.book.root, .book.chapters[index].path)
        let inset = .themeMetrics().floating_Inset
        with .view = HtmlView.createFile(me, path, .readingStyle())
        {
            .dockStyle   = .Center
            .margin      = {x: inset, y: inset, z: inset, w: inset}
            .linkHandler = func|panel = me|(_, url)->bool
            {
                panel.followLink(url)
                return true
            }

            .sigDocumentChanged += func|panel = me|(_)
            {
                panel.restorePendingPosition()
                panel.followReading()
            }

            // Only an open outline follows the reading as it moves; a closed one catches up as it opens.
            .sigScrolled += func|panel = me|(_)
            {
                panel.outline.followOpenReading()
            }

            .sigLoadFailed += func|panel = me|(_, reason)
            {
                panel.services.failed(panel, reason)
            }
        }

        if not .view.failureReason.isEmpty()
        {
            .services.failed(me, .view.failureReason)
            return
        }

        .status.hide()
        .applyLayout()
        discard .view.navigateToFragment(Format.toString("#%", fragment))
        .refreshNavigation()
        .followReading()
    }

    // Marks in the outline the contents entry being read: the last one in an earlier chapter, at
    // the start of this one, or at a fragment of this one standing at or before the text at the
    // top of the view. A fragment not read yet does not count.
    //
    // At the end of a chapter a passage cannot rise to the top, so the one the reader went to
    // counts as read there.
    mtd followReading()
    {
        if not .view or .chapter >= .book.chapters.count do
            return

        let reading = .view.readingOffset()
        let atEnd   = .view.readingProgress() >= 1
        var entry   = Swag.U64.Max
        for content, index in .contents
        {
            if content.chapter < .chapter or (content.chapter == .chapter and content.fragment.isEmpty())
            {
                entry = index
                continue
            }

            if content.chapter != .chapter do
                continue
            if atEnd and content.fragment == .fragment
            {
                entry = index
                continue
            }

            let offset = reading != Swag.U64.Max ? .view.fragmentOffset(content.fragment) : Swag.U64.Max
            if offset != Swag.U64.Max and offset <= reading do
                entry = index
        }

        if entry != Swag.U64.Max do
            .outline.markReading(entry, atEnd: atEnd)
    }

    // A book link stays inside its spine. External URLs and escaping paths never reach the OS.
    internal mtd followLink(reference: string)
    {
        if .chapter >= .book.chapters.count do
            return
        let target = NavigationEntry.resolve(.book.chapters[.chapter].path, reference)
        for chapter, index in .book.chapters where chapter.path == target.path
        {
            .showChapter(index, target.fragment)
            return
        }
    }

    mtd currentVisit()->ReadingVisit
    {
        var result: ReadingVisit
        result.chapter  = .chapter
        result.fragment = .fragment
        if .pendingPosition.isValid() do
            result.position = .pendingPosition
        elif .view do
            result.position = .view.readingPosition()
        return result
    }

    mtd restorePendingPosition()
    {
        if not .pendingPosition.isValid() or not .view do
            return
        if .view.restoreReadingPosition(.pendingPosition) or not .view.isLoading() do
            .pendingPosition = {}
    }

    mtd restoreVisit(visit: ReadingVisit)
    {
        .showChapter(visit.chapter, visit.fragment, false)
        .pendingPosition = visit.position
        .restorePendingPosition()
    }

    internal mtd goBack()
    {
        if .history.canGoBack() do
            .restoreVisit(.history.back(.currentVisit()))
    }

    internal mtd goForward()
    {
        if .history.canGoForward() do
            .restoreVisit(.history.forward(.currentVisit()))
    }

    mtd handleHistoryKey(evt: const *KeyEvent)->bool
    {
        let direction = Viewer.historyKeyDirection(evt)
        if direction < 0 do
            .goBack()
        elif direction > 0 do
            .goForward()
        return direction != 0
    }

    mtd applyReadingStyle()
    {
        if not .view do
            return
        let passage = .view.readingPosition()
        .view.setDocumentStyle(.readingStyle())
        discard .view.restoreReadingPosition(passage)
    }

    internal mtd setZoom(percent: u32)
    {
        .zoomPercent = Viewer.clampZoom(percent)
        .applyReadingStyle()
        .zoomLabel.setText(Viewer.zoomText(.zoomPercent))
    }

    // Offers the zoom levels beside the zoom readout, with the one in force checked.
    mtd showZoomMenu()
    {
        let percent = Viewer.pickZoom(me, .zoomLabel, .zoomPercent)
        if percent do
            .setZoom(percent)
    }

    internal mtd setReadingColumn(column: ReadingColumn)
    {
        if .readingColumn == column do
            return
        .readingColumn = column
        .applyReadingStyle()
    }

    mtd describeLens(entries: *Viewer.LensEntries)
    {
        // `:` and a chapter number go to that chapter of the spine.
        if entries.results.prefix == .Line
        {
            let typed = Latin1.trim(entries.query.toString())
            for c in typed where not Latin1.isDigit(c) do
                return
            let chapter = catch StrConv.toU64(typed) { return; }
            if not chapter or chapter > .book.chapters.count do
                return
            let entry = entries.add(Format.toString(appStrings().lens_GoToChapter, chapter), .GoTo, func|view = me, chapter|() { view.showChapter(chapter - 1) })
            if entry do
                entry.lead = Format.toString("%", chapter)
            return
        }

        entries.add(texts().ui_Back, .ChevronLeft, func|view = me|() { view.goBack() }, disabled: not .history.canGoBack(), shortcut: Input.formatKeyShortcut(.Alt, .Left))
        entries.add(texts().ui_Forward, .ChevronRight, func|view = me|() { view.goForward() }, disabled: not .history.canGoForward(), shortcut: Input.formatKeyShortcut(.Alt, .Right))
        entries.add(texts().ui_Previous, .ChevronLeft, func|view = me|() { view.turn(-1) }, disabled: not .previousButton.isEnabled(), shortcut: Input.formatKeyShortcut(.Control, .PageUp))
        entries.add(texts().ui_Next, .ChevronRight, func|view = me|() { view.turn(1) }, disabled: not .nextButton.isEnabled(), shortcut: Input.formatKeyShortcut(.Control, .PageDown))
        entries.addZoom(.In, .zoomPercent, func|view = me|() { view.setZoom(Viewer.zoomIn(view.zoomPercent)) })
        entries.addZoom(.Out, .zoomPercent, func|view = me|() { view.setZoom(Viewer.zoomOut(view.zoomPercent)) })
        entries.addZoom(.Reset, .zoomPercent, func|view = me|() { view.setZoom(100) })
        entries.add(appStrings().cmd_ZoomMenu, .ZoomIn, func|view = me|() { view.showZoomMenu() })
        entries.add(texts().ui_CompactColumn, .Wrap, func|view = me|() { view.setReadingColumn(.Compact) }, checked: .readingColumn == .Compact)
        entries.add(texts().ui_ComfortableColumn, .Wrap, func|view = me|() { view.setReadingColumn(.Comfortable) }, checked: .readingColumn == .Comfortable)
        entries.add(texts().ui_WideColumn, .Wrap, func|view = me|() { view.setReadingColumn(.Wide) }, checked: .readingColumn == .Wide)
    }

    internal mtd retire()->bool => .load.retire()

    func create(host: Viewer.Host)->*Panel
    {
        with let result = Wnd.create'Panel(host.contentParent(), "scope.epub")
        {
            .backgroundStyle = .View
            .focusPolicy     = .Tab
            .services        = host.services()
        }

        let info       = host.createCommandGroup(Viewer.pageControlWidth(result.themeMetrics()))
        let actionSize = themeActionButtonSize(result.themeMetrics())
        with result.previousButton = Viewer.createPageStep(info, -1)
        {
            .dockStyle       = .Left
            .preferredSize.x = actionSize
            .toolTip         = texts().ui_Previous
            .sigPressed      += func|view = result|(_) { view.turn(-1) }
        }

        result.chapterLabel = Viewer.createPageLabel(info)
        with result.nextButton = Viewer.createPageStep(info, 1)
        {
            .dockStyle       = .Left
            .preferredSize.x = actionSize
            .toolTip         = texts().ui_Next
            .sigPressed      += func|view = result|(_) { view.turn(1) }
        }

        with result.zoomLabel = Viewer.createZoomButton(host.createInfoGroup(Viewer.ZoomSlotWidth), "scope.epub.zoom", appStrings().cmd_ZoomMenu)
        {
            .sigPressed += func|view = result|(_) { view.showZoomMenu() }
        }

        result.zoomLabel.setText(Viewer.zoomText(result.zoomPercent))
        with result.status = Label.create(result, texts().ui_Preparing, {}, null, .WordWrap)
        {
            .dockStyle       = .Center
            .backgroundStyle = .View
            .setTextAlignment(.Center, .Center)
        }

        result.hookOnChildEvent = func|result|(_, evt)
        {
            if evt is KeyEvent as key
            {
                if result.handleHistoryKey(key) do
                    return true
                let direction = Viewer.pageKeyDirection(key)
                if direction
                {
                    result.turn(direction)
                    return true
                }

                if Viewer.isZoomKey(key)
                {
                    result.setZoom(Viewer.zoomAfterKey(key, result.zoomPercent))
                    return true
                }
            }

            return false
        }

        result.refreshNavigation()
        result.applyLayout()
        return result
    }
}

func createViewer(host: Viewer.Host)
{
    let view = Panel.create(host)
    host.attachView(view)
    view.outline             = DocumentOutline.create(host)
    view.outline.sigSelected += func|view|(_, target) { view.selectContents(target) }
    view.outline.follow      = func|view|() { view.followReading() }
    view.load.start(host.fileName(), &Book.load, view)
    host.setLensSource(func|view|(entries) { view.describeLens(entries) })
    host.setInformation(func|view|(sheet) { view.describeInformation(sheet) })
    with var lifecycle: Viewer.LifecycleApi
    {
        .isLoading = func|view|()->bool => view.load.isPending() or (view.view?.isLoading() orelse false)
        .needsLoadingOverlay = func|view|()->bool => view.load.isPending()
        .retire    = func|view|()->bool => view.retire()
    }

    host.setLifecycle(lifecycle)
}
