const MaxRecent = 15

// Air between two thumbnails, and around the strip. It holds the selection ring the shared
// file tile draws outside the picture (`fileTile_RingWidth` and `fileTile_RingGap`).
const RecentPadding = 8.0

// The linked-image badge, at the inline-badge size of the application chart.
const LinkBadgeSize  = 16.0
const LinkBadgeGlyph = 12.0

// One thumbnail of the recent strip: the capture file, its linked image, and its preview.
struct RecentItem
{
    file:           String
    linked:         String
    linkedUpToDate: bool
    duration:       u64     // Length of an animation, in microseconds; zero for a picture.
    preview:        Texture
    ownerApp:       *Application?
    rect:           Math.Rectangle
    zoom:           f32
}

impl RecentItem
{
    mtd opDrop()
    {
        if .ownerApp do
            .ownerApp.renderer.removeTexture(&.preview)
    }
}

// The state a capture thumbnail is painted in.
struct RecentInfos
{
    hot:            bool
    selected:       bool
    loading:        bool
    linkedUpToDate: bool
    linked:         String
    showLinked:     bool = true
    duration:       u64     // Length of an animation, in microseconds; zero for a picture.
}

// The thumbnails of the recent strip, which open and select captures.
struct RecentView
{
    using wnd: Wnd

    late main:      *MainWnd
    late recentWnd: *RecentWnd
    items:          ArrayPtr'RecentItem
    selected:       u64 = Swag.U64.Max
    hotItem:        u64 = Swag.U64.Max
}

impl RecentView
{
    mtd showContextMenu(pos: Math.Point)
    {
        with let menu = MenuCtrl.createPopup(me)
        {
            .addItem(ActionFile.UpdateLinkedImage)
            .addSeparator()
            .addItem(ActionFile.DupCapture)
            .addItem(ActionFile.RenameCapture)
            .addItem(ActionFile.DeleteCapture)
            .addSeparator()
            .addItem(ActionCopyPaste.CopyAsImage)
            .addSeparator()
            .addItem(ActionFile.CaptureFileLocation)
            .addItem(ActionFile.LinkedFileLocation)
            .addSeparator()
            .addItem(ActionFile.FileDetails)
        }

        discard menu.doModal(pos, autoDestroy: true)
    }

    // Opens `capture`, loaded for item `idx`, in the editor at the zoom the item last had.
    // The outgoing capture has already been snapshotted by the recent window.
    private mtd selectLoaded(idx: u64, capture: *Capture)->*Capture?
    {
        if idx >= .items.count
        {
            Memory.delete(capture)
            return null
        }

        let view = .main.editWnd.editView

        // Save current zoom
        if .selected < .items.count
        {
            let sel = unwrap .items[.selected]
            sel.zoom = view.zoom
        }

        // Only commit the selection once the capture has actually loaded,
        // otherwise .selected would point at an item never shown in the view.
        .selected = idx
        let outgoing = view.replaceCapture(capture)
        let item = unwrap .items[idx]
        if item.zoom == 0 do
            view.zoomToFit(false)
        else do
            view.setZoom(item.zoom)
        view.main.freezeSelection(false)
        .invalidate()
        return outgoing
    }

    // A pointer or lens selection keeps the current editor responsive while the next capture
    // decodes. The popup is shown only after the clicked capture becomes the active one.
    mtd requestSelect(idx: u64, contextMenu = false, pos: Math.Point = {})
    {
        if idx >= .items.count do
            return
        if .selected == idx
        {
            .recentWnd.cancelRequestedSelection()
            if contextMenu do
                .showContextMenu(pos)
            return
        }

        let item = unwrap .items[idx]
        .recentWnd.requestSelection(item.file, contextMenu, pos)
    }

    // Paints the mark of a capture linked to an image file at the top-left corner of `rect`: on the
    // ground when the image is up to date, on yellow when it is not.
    // Marks a capture linked to an image file, inside the leading top corner of its picture `rect`:
    // a chip on the floating ground, which reads over any picture, with a soft link while the
    // image matches the capture and a caution link once the capture changed since the image was
    // written. Caution is a state, not the accent: the yellow of the window stays the primary
    // action's.
    func paintLinkBadge(parent: *Wnd, painter: *Painter, rect: Math.Rectangle, infos: RecentInfos, corner: f32)
    {
        if not infos.showLinked or infos.linked.isEmpty() do
            return

        let colors = parent.themeColors()
        let gap    = parent.themeMetrics().fileTile_NameGap
        if rect.width < LinkBadgeSize + 2 * gap or rect.height < LinkBadgeSize + 2 * gap do
            return

        let chip = Math.Rectangle{rect.x + gap, rect.y + gap, LinkBadgeSize, LinkBadgeSize}
        let ink  = infos.linkedUpToDate ? colors.softText : colors.caution
        painter.fillRoundRect(chip, corner, corner, colors.surface)

        var icon = parent.theme().icon(.Link)
        icon.sizeX, icon.sizeY = LinkBadgeGlyph
        let inset = (LinkBadgeSize - LinkBadgeGlyph) * 0.5
        icon.paint(painter, chip.x + inset, chip.y + inset, ink)
    }

    // Marks an animation inside the trailing bottom corner of its picture `rect`: a chip on the
    // floating ground, which reads over any picture, with a play glyph and the length in the
    // fixed-width family.
    func paintDurationBadge(parent: *Wnd, painter: *Painter, rect: Math.Rectangle, infos: RecentInfos, corner: f32)
    {
        if not infos.duration do
            return

        let colors  = parent.themeColors()
        let metrics = parent.themeMetrics()
        let gap     = metrics.fileTile_NameGap
        let font    = parent.theme().createDefaultFontFs(metrics.defaultFontSize - 2)
        let text    = Capture.clockText(infos.duration)
        let width   = LinkBadgeSize + Painter.measureString(text, font).width + gap
        if rect.width < width + 2 * gap or rect.height < LinkBadgeSize + 2 * gap do
            return

        let chip = Math.Rectangle{rect.right() - gap - width, rect.bottom() - gap - LinkBadgeSize, width, LinkBadgeSize}
        painter.fillRoundRect(chip, corner, corner, colors.surface)

        var icon = parent.theme().icon(.Play)
        icon.sizeX, icon.sizeY = LinkBadgeGlyph
        let inset = (LinkBadgeSize - LinkBadgeGlyph) * 0.5
        icon.paint(painter, chip.x + inset, chip.y + inset, colors.softText)
        painter.drawString(chip.x + LinkBadgeSize, font.opticalLineTop(chip.vertCenter()), text, font, colors.text)
    }

    // Paints one capture of the recent strip in the cell `rect`.
    //
    // It is a file tile without a caption, as the library and the lens draw their captures: the
    // picture fills the cell around its centre, so a row of pictures of several shapes keeps one
    // rhythm; a strong hairline marks it under the pointer, and the capture being edited is ringed
    // in Arc outside its picture, which stays intact.
    func paintRecent(parent: *Wnd, painter: *Painter, texture: Texture, rect: Math.Rectangle, infos: RecentInfos)
    {
        var content: Gui.FileTile.Content
        content.texture = texture
        content.icon    = parent.theme().icon(.FileImage, parent.themeMetrics().menuPopup_IconSize)
        if infos.loading do
            content.badge = appStrings().ui_Loading

        var options: Gui.FileTile.Options
        options.fit         = .Cover
        options.hovered     = infos.hot or infos.loading
        options.selected    = infos.selected
        options.showCaption = false
        Gui.FileTile.paint(parent, painter, rect, &content, options)

        paintLinkBadge(parent, painter, rect, infos, parent.themeMetrics().corner_Chip)
        paintDurationBadge(parent, painter, rect, infos, parent.themeMetrics().corner_Chip)
    }
}

impl IWnd for RecentView
{
    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if evt.kind == .Wheel do
            evt.accepted = false

        var pos = .surfaceToLocal(evt.surfacePos)
        pos += .recentWnd.scrollPosition()

        // Hit test
        var ht = Swag.U64.Max
        for i, idx in .items
        {
            if i!.rect.contains(pos)
            {
                ht = idx
                break
            }
        }

        if ht != .hotItem
        {
            .invalidate()
            .hotItem = ht
        }

        if evt.kind == .Pressed and .hotItem != Swag.U64.Max
        {
            if evt.button == .Left or evt.button == .Right
            {
                .requestSelect(.hotItem, evt.button == .Right, evt.surfacePos)
            }
        }
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter    = evt.paintContext.painter
        let clientRect = .paddedClientRect()

        var x = clientRect.x
        for item, idx in .items
        {
            let it = unwrap item
            let w  = clientRect.height * 4.0 / 3

            let rect = Math.Rectangle{x, clientRect.y, w, clientRect.height}
            it.rect = rect

            with var infos: RecentInfos
            {
                .hot            = idx == me.hotItem
                .selected       = idx == me.selected
                .loading        = me.recentWnd.requestedFile == it.file
                .linkedUpToDate = it.linkedUpToDate
                .linked         = it.linked
                .duration       = it.duration
            }

            RecentView.paintRecent(me, painter, it.preview, rect, infos)
            x = rect.right() + RecentPadding
        }

        .recentWnd.setScrollSize(x, 0)
    }
}

// The scrolling recent strip, which loads its thumbnails a few at a time.
struct RecentWnd
{
    using scrollWnd:    ScrollWnd
    late main:          *MainWnd
    late recentView:    *RecentView
    timer:              *Gui.Timer?
    loadTimer:          *Gui.Timer?
    selectionTimer:     *Gui.Timer?
    loadJob:            *CaptureLoadJob?
    captureCache:       RecentCaptureCache
    readyCapture:       *Capture?
    readyFile:          String
    readyRevision:      File.FileInfo
    activeCapture:      *Capture?
    activeRevision:     File.FileInfo
    requestedFile:      String
    requestedMenu:      bool
    requestedMenuPos:   Math.Point
    returnToEditor:     bool
    startupSelection:   String
    initialSelectionTried: bool
    pendingRecentFiles: Array'String
    pendingRecentIndex: u64
    loadDone:           bool
    prepareLoadRecent:  bool
}

impl IWnd for RecentWnd
{
    mtd impl onDestroyEvent(_: *DestroyEvent)
    {
        .stopTimer(&.timer)
        .stopTimer(&.loadTimer)
        .stopTimer(&.selectionTimer)
        if .readyCapture do
            Memory.delete(.readyCapture)

        if .loadJob
        {
            let job = .loadJob
            .loadJob = null
            job.task.cancel()
            job.task.wait()
            if job.capture do
                Memory.delete(job.capture)
            Memory.delete(job)
        }

        // The automatic save owns no window: land it before the strip that schedules
        // and collects it goes away.
        discard g_CaptureSaves.flush()
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer == .selectionTimer
        {
            .stopTimer(&.selectionTimer)
            .startRequestedSelection()
            return
        }

        // The scroll window has its own timer, which lets the bar fade once the strip is still.
        if evt.timer != .loadTimer and evt.timer != .timer
        {
            .scrollWnd.IWnd.onTimerEvent(evt)
            return
        }

        if evt.timer == .loadTimer
        {
            .stopTimer(&.loadTimer)
            if .prepareLoadRecent
            {
                .prepareLoadRecent = false
                .loadRecent()
            }
            else
            {
                .loadNextRecent()
            }

            return
        }

        // The one-second timer drives the deferred save, which lands in the background.
        // Keep the timer alive while a save is still writing, then surface its outcome
        // before scheduling the next one.
        let failedSave = g_CaptureSaves.collect()
        if not failedSave.isEmpty() do
            MessageDlg.error(unwrap .main.surface, Format.toString(appStrings().msg_FailedSaveCapture, failedSave))
        if g_CaptureSaves.busy() do
            return

        let capture = .main.editWnd.getCapture()
        if capture and capture.changed
        {
            // The one-second arm can predate a drag; rebuilding the preview now
            // would freeze the gesture mid-move, so just try again on the next tick.
            if capture.interactiveMove or capture.mouseMode != .None do
                return

            // The 1s save timer isn't cancelled when the selection is cleared
            // (e.g. onDeleteFile sets .selected to the Max sentinel), so only save
            // into a valid recent item to avoid indexing out of range.
            if .recentView.selected < .recentView.items.count
            {
                capture.computePreview()
                let item = unwrap .recentView.items[.recentView.selected]
                if item.ownerApp do
                    item.ownerApp.renderer.removeTexture(&item.preview)
                item.ownerApp = .app()
                item.preview = .app().renderer.addImage(capture.preview)
                .invalidateRecentViews()

                .main.libWnd.view.updateRecent(capture)

                // The snapshot happens now; a worker produces the file and
                // atomically replaces it, and the next tick collects the outcome.
                catch capture.scheduleSave() do
                    MessageDlg.error(unwrap .main.surface, Format.toString(appStrings().msg_FailedSaveCapture, capture.file))
                return
            }
        }

        .stopTimer(&.timer)
    }

    mtd impl onTaskEvent(evt: *TaskEvent)
    {
        let job = .loadJob
        if not job or evt.task != &job.task
        {
            evt.accepted = false
            return
        }

        .loadJob = null
        let loaded  = job.capture
        let failure = #move job.error
        let file = job.file
        let revision = job.revision
        Memory.delete(job)

        // A later click, a deletion, or an immediate programmatic selection supersedes this
        // result. The worker never touches the current editor or its selection.
        if .requestedFile != file
        {
            if loaded do
                Memory.delete(loaded)
            .startRequestedSelection()
            return
        }

        if loaded
        {
            .readyCapture = loaded
            .readyFile    = file
            .readyRevision = revision
            .finishRequestedSelection()
            return
        }

        if .returnToEditor and .main.libraryMode and not g_UpdatingLib do
            .main.libWnd.view.imgSpin.hide()
        .requestedFile.clear()
        .requestedMenu = false
        .returnToEditor = false
        .invalidateRecentViews()
        if .startupSelection == file
        {
            .startupSelection.clear()
            .initialSelectionTried = false
            var afterFailed = false
            for it in .recentView.items
            {
                if afterFailed
                {
                    .requestSelection(it!.file, false, {}, startup: true)
                    return
                }
                if it!.file == file do
                    afterFailed = true
            }
            return
        }

        MessageDlg.error(unwrap .main.surface, Format.toString(appStrings().msg_FailedLoadFile, file), failure)
    }
}

impl RecentWnd
{
    private mtd discardReadyCapture()
    {
        if .readyCapture do
            Memory.delete(.readyCapture)
        .readyCapture = null
        .readyFile.clear()
        .readyRevision = {}
    }

    mtd cancelRequestedSelection()
    {
        .loadJob?.task.cancel()
        .discardReadyCapture()
        if .returnToEditor and .main.libraryMode and not g_UpdatingLib do
            .main.libWnd.view.imgSpin.hide()
        if not .startupSelection.isEmpty() do
            .initialSelectionTried = false
        .startupSelection.clear()
        .requestedFile.clear()
        .requestedMenu = false
        .returnToEditor = false
        .stopTimer(&.selectionTimer)
        .invalidateRecentViews()
    }

    mtd requestSelection(file: string, contextMenu: bool, pos: Math.Point, startup = false, returnToEditor = false)
    {
        if .loadJob and .loadJob.file != file do
            .loadJob.task.cancel()
        if .readyCapture and .readyFile != file do
            .discardReadyCapture()
        .initialSelectionTried = true
        .startupSelection = startup ? file : ""
        .requestedFile    = file
        .requestedMenu    = contextMenu
        .requestedMenuPos = pos
        .returnToEditor  = returnToEditor
        if returnToEditor and .main.libraryMode do
            .main.libWnd.view.imgSpin.show()
        .invalidateRecentViews()
        .startRequestedSelection()
    }

    private mtd startRequestedSelection()
    {
        if .requestedFile.isEmpty() do
            return
        if .readyCapture
        {
            .finishRequestedSelection()
            return
        }
        if .loadJob do
            return

        let file = String.from(.requestedFile)
        var found = false
        for it in .recentView.items where it!.file == file
        {
            found = true
            break
        }
        if not found
        {
            .cancelRequestedSelection()
            return
        }

        // Reading a file while its automatic save replaces it can return stale content.
        // Poll that one writer instead of joining it on the interface thread.
        if g_CaptureSaves.writing(file)
        {
            if g_CaptureSaves.busy()
            {
                if not .selectionTimer do
                    .selectionTimer = .addTimer(16'ms)
                return
            }
            .main.flushCaptureSave(file)
            if .requestedFile != file
            {
                .startRequestedSelection()
                return
            }
        }

        let cached = .captureCache.take(file, &.readyRevision)
        if cached
        {
            .readyCapture = cached
            .readyFile    = file
            .finishRequestedSelection()
            return
        }

        let job  = Memory.new'CaptureLoadJob()
        job.file = file
        .loadJob = job
        job.task.submit(func|job|()
        {
            let before = catch File.info(job.file)
            catch { job.capture = try Capture.load(job.file) } as job.error
            let after = catch File.info(job.file)
            if RecentCaptureCache.sameRevision(before, after) do
                job.revision = after
        }, .taskNotifier(&job.task))
    }

    // A decoded capture waits for the outgoing document's save slot without joining a writer
    // on the interface thread. The outgoing snapshot is taken before the editor releases it.
    private mtd finishRequestedSelection()
    {
        let loaded = .readyCapture
        if not loaded do
            return
        if .requestedFile != .readyFile
        {
            .discardReadyCapture()
            .startRequestedSelection()
            return
        }

        if not .readyRevision.fullName.isEmpty() and
           not RecentCaptureCache.sameRevision(.readyRevision, catch File.info(.readyFile))
        {
            .discardReadyCapture()
            .startRequestedSelection()
            return
        }

        var idx = Swag.U64.Max
        for it, i in .recentView.items where it!.file == .readyFile
        {
            idx = i
            break
        }
        if idx == Swag.U64.Max
        {
            .cancelRequestedSelection()
            return
        }

        let outgoing = .main.editWnd.getCapture()
        if outgoing and outgoing.changed
        {
            if g_CaptureSaves.busy()
            {
                if not .selectionTimer do
                    .selectionTimer = .addTimer(16'ms)
                return
            }

            let failed = g_CaptureSaves.collect()
            if not failed.isEmpty() do
                .main.reportFailure(Format.toString(appStrings().msg_FailedSaveCapture, failed))
            catch outgoing.scheduleSave()
            {
                .main.reportFailure(Format.toString(appStrings().msg_FailedSaveCapture, outgoing.file))
                .cancelRequestedSelection()
                return
            }
        }

        let loadedRevision = .readyRevision
        .readyCapture = null
        .readyFile.clear()
        .readyRevision = {}
        .stopTimer(&.selectionTimer)
        .requestedFile.clear()
        .startupSelection.clear()
        let openMenu = .requestedMenu
        .requestedMenu = false
        let returnToEditor = .returnToEditor
        .returnToEditor = false
        .invalidateRecentViews()

        let previous = .recentView.selectLoaded(idx, loaded)
        if previous
        {
            if previous == .activeCapture do
                .captureCache.put(previous, .activeRevision)
            else do
                Memory.delete(previous)
        }
        .activeCapture  = loaded
        .activeRevision = loadedRevision
        if returnToEditor and .main.libraryMode
        {
            .main.swapLibraryMode()
            .main.updateState()
        }
        if openMenu do
            .recentView.showContextMenu(.requestedMenuPos)
    }

    // The strip and the detached hub paint the same items on different surfaces.
    private mtd invalidateRecentViews()
    {
        .invalidate()
        .main.residentPanel?.recents?.invalidate()
    }

    // Builds the recent strip: a horizontal scroll of capture thumbnails.
    func create(parent: *Wnd, main: *MainWnd)->*RecentWnd
    {
        let metrics = parent.themeMetrics()
        let barRoom = metrics.scrollBar_HitSize + metrics.scrollBar_EdgeInset
        with let recent = Wnd.create'RecentWnd(parent, {0, 0, 0, PreviewHeight + RecentPadding * 2 + barRoom})
        {
            .backgroundStyle = .Panel
            .main = main

            .recentView           = recent.createView'RecentView()
            .recentView.padding   = RecentPadding
            .recentView.main      = main
            .recentView.recentWnd = recent
            .view.backgroundStyle = .Transparent
        }

        return recent
    }

    mtd scheduleLoadRecent()
    {
        if .loadDone or .loadTimer do
            return
        .prepareLoadRecent = true
        .loadTimer         = .addTimer(1'ms)
    }

    // The hub can size itself once a first valid recent item is present or every candidate
    // has been tried. A damaged first file must not make the hub grow a moment later.
    mtd hubSizeReady()->bool => .loadDone and
                               (not .recentView.items.isEmpty() or .pendingRecentIndex >= .pendingRecentFiles.count)

    private mtd openPendingHub()
    {
        if not .main.openHubAfterRecentLoad or not .hubSizeReady() do
            return
        .main.openHubAfterRecentLoad = false
        ResidentPanel.open(.main, .Hub)
    }

    // Drops `file` from the recent strip once the library deleted it.
    mtd onLibraryFileDeleted(file: String)
    {
        .captureCache.invalidate(file)
        if .requestedFile == file do
            .cancelRequestedSelection()
        for it, i in .recentView.items
        {
            if it!.file == file
            {
                // Remove from recent
                .recentView.items.destroy(it)
                .recentView.items.removeAtOrdered(i)

                // Select new one
                if .recentView.selected == i
                {
                    .recentView.selected = Swag.U64.Max
                    if not .recentView.items.isEmpty() do
                        .recentView.requestSelect(Math.min(i, .recentView.items.count - 1))
                }
                // A removal before the selected item shifts everything after it
                // down by one, so decrement the index to keep tracking the same item.
                elif .recentView.selected != Swag.U64.Max and i < .recentView.selected
                {
                    .recentView.selected -= 1
                }

                .invalidateRecentViews()
                break
            }
        }
    }

    // Lists the newest captures of the library for the strip, once, and starts loading them one
    // at a time.
    mtd loadRecent()
    {
        if .loadDone do
            return
        .loadDone = true

        g_Library.onDeleteFile += func|recent = me|(file) { recent.onLibraryFileDeleted(file) }

        // The recent strip needs only the newest capture names. Validating every SCC in the
        // library here would open the complete collection before the first thumbnail could
        // appear, so that index stays lazy: each recent candidate is validated as it is loaded.
        var result = catch Directory.enumerateFiles(Library.getFolder())
        result.sort(func(a, b) => b.lastWriteTime <=> a.lastWriteTime)

        // The application state is an SCC container too, but never a capture to open.
        let state = Library.getStatePath()
        for r in result where Capture.isFileName(r.fullName) and not Path.equals(r.fullName, state) do
            .pendingRecentFiles.add(r.fullName)

        // Enumeration already runs on the deferred startup turn. Show the first preview
        // now; another timer would allow a redundant empty-editor frame in between.
        .loadNextRecent()
        .openPendingHub()
    }

    mtd scheduleLoadNextRecent()
    {
        if .loadTimer or
           .recentView.items.count >= MaxRecent or
           .pendingRecentIndex >= .pendingRecentFiles.count do
            return
        .prepareLoadRecent = false
        .loadTimer         = .addTimer(1'ms)
    }

    // Loads the next preview into the strip, one per call; the first valid item starts a
    // separate full decode for the editor.
    mtd loadNextRecent()
    {
        if .recentView.items.count >= MaxRecent or .pendingRecentIndex >= .pendingRecentFiles.count do
            return

        let file = .pendingRecentFiles[.pendingRecentIndex]
        catch
        {
            let capture = try Capture.load(file, preview: true)
            defer Memory.delete(capture)
            .addRecent(capture.file, capture.preview, front: false, linkedUpToDate: capture.linkedUpToDate, linked: capture.linkedImage, duration: capture.keptDuration())
            g_Library.addFile(capture.file)

            if not .initialSelectionTried and not .main.editWnd.editView.capture do
                .requestSelection(capture.file, false, {}, startup: true)
        }

        .pendingRecentIndex += 1
        .scheduleLoadNextRecent()
        .openPendingHub()
    }

    // Refreshes the selected item of the strip from the capture being edited, and restarts the
    // timer that renews its thumbnail.
    mtd updateRecent()
    {
        if .recentView.selected >= .recentView.items.count do
            return

        .stopTimer(&.timer)
        .timer = .addTimer(1's)

        let capture = .main.editWnd.getCapture()
        if not capture do
            return

        with let item = unwrap .recentView.items[.recentView.selected]
        {
            .linked         = capture.linkedImage
            .linkedUpToDate = capture.linkedUpToDate
            .duration       = capture.keptDuration()
        }

        .invalidateRecentViews()
    }

    mtd removeRecent()
    {
        if .recentView.selected >= .recentView.items.count do
            return

        let item = unwrap .recentView.items[.recentView.selected]

        // Be sure there's no pending save
        .stopTimer(&.timer)
        .timer = null

        // Delete file
        g_Library.removeFile(item.file)
    }

    mtd addRecent(file: String, front = true, sel = false)->*Capture fail
    {
        // The strip shows thumbnails: a preview load reads the SCC header and the
        // preview chunk alone, never the image payloads. The full capture is loaded
        // by the recent window's background task when an item becomes the edited one.
        let loaded = try Capture.load(file, preview: true)
        .addRecent(loaded.file, loaded.preview, front, sel, loaded.linkedUpToDate, loaded.linkedImage, loaded.keptDuration())
        return loaded
    }

    // Adds `file` to the recent strip, or moves it to the front when it is already there, and keeps
    // the strip within `MaxRecent` items.
    mtd addRecent(file: String, preview: Image, front = true, sel = false, linkedUpToDate = true, linked: string = "", duration: u64 = 0)
    {
        .captureCache.invalidate(file)
        // Already there ?
        for it, i in .recentView.items
        {
            let itn = unwrap it
            if itn.file == file
            {
                var idxSel = i

                // Move the item to the first position, shifting items 0..i-1 down by one.
                // swap() would dump the old first item into slot i and scramble MRU order,
                // so relocate the (owned) pointer slot instead without freeing the item.
                if front and i
                {
                    let oldSelected = .recentView.selected
                    .recentView.items.removeAtOrdered(i)
                    .recentView.items.insertAt(0, it)
                    idxSel = 0

                    if oldSelected == i do
                        .recentView.selected = 0
                    elif oldSelected < i do
                        .recentView.selected = oldSelected + 1
                }

                if sel do
                    .recentView.requestSelect(idxSel)

                if itn.ownerApp do
                    itn.ownerApp.renderer.removeTexture(&itn.preview)
                itn.ownerApp = .app()
                itn.preview = .app().renderer.addImage(preview)
                itn.linked   = linked
                itn.linkedUpToDate = linkedUpToDate
                itn.duration = duration
                .invalidateRecentViews()
                return
            }
        }

        with let item = .recentView.items.allocate()
        {
            .preview        = me.app().renderer.addImage(preview)
            .ownerApp       = me.app()
            .file           = file
            .linked         = linked
            .linkedUpToDate = linkedUpToDate
            .duration       = duration
        }

        if front
        {
            if .recentView.selected < .recentView.items.count do
                .recentView.selected += 1
            .recentView.items.insertAt(0, item)
            if sel
            {
                .recentView.requestSelect(0)
                .setScrollPos(0, 0)
            }
        }
        else
        {
            .recentView.items.add(item)
            if sel do
                .recentView.requestSelect(.recentView.items.count - 1)
        }

        // Captures created from the clipboard reach this overload directly, without loading a
        // file first. Enforce the same MRU bound for both paths so thumbnail textures cannot
        // accumulate for the whole application lifetime.
        if front and .recentView.items.count > MaxRecent
        {
            if .recentView.selected == .recentView.items.count - 1 do
                .recentView.selected = Swag.U64.Max
            let back = unwrap .recentView.items.back()
            .captureCache.invalidate(back.file)
            .recentView.items.destroy(back)
            .recentView.items.count -= 1
        }

        .invalidateRecentViews()
    }
}
