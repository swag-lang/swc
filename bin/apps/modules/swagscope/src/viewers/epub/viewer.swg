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
        .addSelectors(".epub")
    }

    return result
}

enum ReadingColumn { Compact, Comfortable, Wide }

// Owns book navigation while the HTML control streams the selected chapter and its resources.
struct Panel
{
    using wnd: Wnd

    book:          Book
    load:          Viewer.BackgroundLoad'Book
    services:      Viewer.HostServices
    chapter:       u64 = Swag.U64.Max
    view:          *HtmlView?
    contents:      Array'NavigationEntry
    zoomPercent:   u32 = 100
    readingColumn: ReadingColumn = .Comfortable

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

    internal mtd showChapter(index: u64, fragment: string = "")
    {
        if index >= .book.chapters.count do
            return
        if index == .chapter and .view
        {
            discard .view.navigateToFragment(Format.toString("#%", fragment))
            return
        }

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

    internal mtd setReadingColumn(column: ReadingColumn)
    {
        if .readingColumn == column do
            return
        .readingColumn = column
        .applyReadingStyle()
    }

    mtd describeLens(entries: *Viewer.LensEntries)
    {
        entries.add(texts().ui_Previous, .ChevronLeft, func|view = me|() { view.turn(-1) }, shortcut: Input.formatKeyShortcut(.Control, .PageUp))
        entries.add(texts().ui_Next, .ChevronRight, func|view = me|() { view.turn(1) }, shortcut: Input.formatKeyShortcut(.Control, .PageDown))
        entries.addZoom(.In, .zoomPercent, func|view = me|() { view.setZoom(Viewer.zoomIn(view.zoomPercent)) })
        entries.addZoom(.Out, .zoomPercent, func|view = me|() { view.setZoom(Viewer.zoomOut(view.zoomPercent)) })
        entries.addZoom(.Reset, .zoomPercent, func|view = me|() { view.setZoom(100) })
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
            .sigPressed += func|view = result|(_)
            {
                let percent = Viewer.pickZoom(view, view.zoomLabel, view.zoomPercent)
                if percent do
                    view.setZoom(percent)
            }
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
    view.outline = DocumentOutline.create(host)
    view.outline.sigSelected += func|view|(_, target) { view.selectContents(target) }
    view.load.start(host.fileName(), &Book.load, view)
    host.setLensSource(func|view|(entries) { view.describeLens(entries) })
    with var lifecycle: Viewer.LifecycleApi
    {
        .isLoading = func|view|()->bool => view.load.isPending() or (view.view?.isLoading() orelse false)
        .needsLoadingOverlay = func|view|()->bool => view.load.isPending()
        .retire    = func|view|()->bool => view.retire()
    }

    host.setLifecycle(lifecycle)
}
