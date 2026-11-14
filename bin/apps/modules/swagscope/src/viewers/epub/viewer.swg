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

// Hosts one XHTML spine document at a time, preserving extracted local resources.
struct Panel
{
    using wnd: Wnd

    book:               Book
    load:               Viewer.BackgroundLoad'Book
    late embedded:      Viewer.Embedded
    services:           Viewer.HostServices
    chapter:            u64 = Swag.U64.Max
    pendingChapter:     u64 = Swag.U64.Max
    awaitingRetirement: bool
    retiring:           bool
    retryTimer:         *Timer?

    late
    {
        status:         *Label
        previousButton: *IconButton
        nextButton:     *IconButton
        chapterLabel:   *Label
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

        .showChapter(0)
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
        .continueChapter()
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
        let current    = .pendingChapter != Swag.U64.Max ? .pendingChapter : .chapter
        let hasChapter = current != Swag.U64.Max
        .previousButton.enable(hasChapter and current > 0)
        .nextButton.enable(hasChapter and current + 1 < .book.chapters.count)
        .chapterLabel.setText(hasChapter ? Viewer.pageText(current, .book.chapters.count) : "")
        if hasChapter do
            .services.showDetails(me, Format.toString(texts().ui_Details, current + 1, .book.chapters.count))
    }

    internal mtd turn(delta: s32)
    {
        let current = .pendingChapter != Swag.U64.Max ? .pendingChapter : .chapter
        if current == Swag.U64.Max do
            return
        if delta < 0 and current > 0 do
            .showChapter(current - 1)
        elif delta > 0 and current + 1 < .book.chapters.count do
            .showChapter(current + 1)
    }

    mtd showChapter(index: u64)
    {
        if index >= .book.chapters.count or index == .chapter or index == .pendingChapter do
            return
        .pendingChapter = index
        .status.setText(texts().ui_Preparing)
        .status.show()
        .status.bringToFront()
        .refreshNavigation()
        .continueChapter()
    }

    mtd continueChapter()
    {
        if .retiring or .pendingChapter == Swag.U64.Max do
            return
        if not .embedded.retire()
        {
            .awaitingRetirement = true
            return
        }

        .chapter        = .pendingChapter
        .pendingChapter = Swag.U64.Max
        let entry = &.book.chapters[.chapter]
        let path  = Path.combine(.book.root, entry.path)
        catch .embedded.open(path, entry.path)
        {
            .services.failed(me, Viewer.failureText(Swag.err))
            return
        }

        .status.hide()
        .refreshNavigation()
    }

    mtd retryChapter()
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
        if not .load.retire() or not .embedded.retire() do
            return false
        .stopTimer(&.retryTimer)
        return true
    }

    mtd describeLens(entries: *Viewer.LensEntries)
    {
        entries.add(texts().ui_Previous, .ChevronLeft, func|view = me|() { view.turn(-1) }, shortcut: Input.formatKeyShortcut(.Control, .PageUp))
        entries.add(texts().ui_Next, .ChevronRight, func|view = me|() { view.turn(1) }, shortcut: Input.formatKeyShortcut(.Control, .PageDown))
    }

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
            .toolTip         = appStrings().ui_PreviousPage
            .sigPressed      += func|view = result|(_) { view.turn(-1) }
        }

        result.chapterLabel = Viewer.createPageLabel(info)
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
                result.retryChapter()
            return false
        }

        result.refreshNavigation()
        result.load.start(host.fileName(), &Book.load, result)
        result.applyLayout()
        return result
    }
}

func createViewer(host: Viewer.Host)
{
    let view = Panel.create(host)
    host.attachView(view)
    host.setLensSource(func|view|(entries) { view.describeLens(entries) })
    with var lifecycle: Viewer.LifecycleApi
    {
        .isLoading = func|view|()->bool => view.load.isPending() or view.embedded.isLoading()
        .needsLoadingOverlay = func|view|()->bool => view.load.isPending()
        .retire    = func|view|()->bool => view.retire()
    }

    host.setLifecycle(lifecycle)
}
