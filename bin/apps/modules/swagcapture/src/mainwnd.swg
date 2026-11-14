// The main window once [[MainWnd.create]] has run. Headless fixtures that build a panel on its
// own leave it null.
var g_Main: *MainWnd?

const ClipboardFormat        = "Swag.Capture"
const CaptureFileMetadataTag = "Swag.Capture.File"
const IconsSvg               = #include("../datas/icons.svg")
const AppIcon                = #include("../datas/appicon.png")

// The editor tool, which decides what a drag on the capture creates.
enum EditMode { Shape, Arrow, Line, Polygon, Text, Favorites, Draw, Highlight, Selection, Step, Image, PixSel, Callout }

// What the mini-bar beside the selection carries: nothing without a selection, the colour of one
// object, the face of a text, the counter of a step, or the alignment of several objects.
enum MiniBarKind { None, Single, Text, Step, Multi }

// Identifies a glyph of the application icon set (`datas/icons.svg`), in the grid
// order of the document. The set is rasterized on demand per size and scale through
// [[Gui.IconSet]], so every glyph stays sharp at any display density.
enum CaptureIcons
{
    Shape               // Shape tool.
    Line                // Line tool.
    Polygon             // Polygon tool.
    Arrow               // Arrow tool.
    Text                // Text tool.
    Favorites           // Quick-style favorites.
    Capture             // Capture trigger.
    Draw                // Free-hand draw tool.
    Library             // Capture library.
    Highlight           // Highlight tool.
    Select              // Selection tool.
    Step                // Numbered-step tool.
    Image               // Image effect.
    Blur                // Blur effect.
    Pixelate            // Pixelate effect.
    Zoom                // Zoom effect.
    PixSel              // Pixel-selection tool.
    Cube                // Capture-content effect.
    Circle              // Circle shape.
    Rect                // Rectangle outline shape.
    ViewSmall           // Small recent view.
    ViewMedium          // Medium recent view.
    ViewBig             // Big recent view.
    Calendar            // Library date grouping.
    Archive             // Library all-captures entry.
    Monitor             // Capture one monitor.
    FullScreen          // Capture the full screen.
    CaptureArea         // Capture a picked area.
    ActiveWindow        // Capture the active window.
    LastArea            // Capture the previous area again.
    SquareFill          // Filled badge square.
    TextAlignLeft       // Left text alignment.
    TextAlignCenter     // Centered text alignment.
    TextAlignRight      // Right text alignment.
    AlignTop            // Top vertical alignment.
    AlignMiddle         // Middle vertical alignment.
    AlignBottom         // Bottom vertical alignment.
    RatingStar          // Capture rating.
    Callout             // Callout action glyph.
    Bold                // Bold action glyph.
    Italic              // Italic action glyph.
    Group               // Group action glyph.
    Ungroup             // Ungroup action glyph.
    Flatten             // Flatten action glyph.
    Resize              // Resize action glyph.
    Expand              // Expand action glyph.
    Crop                // Crop action glyph.
    Flip                // Flip action glyph.
    Mirror              // Mirror action glyph.
    RotateRight         // RotateRight action glyph.
    RotateLeft          // RotateLeft action glyph.
    Snap                // Snap action glyph.
    InvertSelection     // InvertSelection action glyph.
    Delay3              // Clock hand pointing to three for the three-second delay.
    Delay5              // Clock hand pointing to five for the five-second delay.
    Delay10             // Clock hand pointing to ten for the ten-second delay.
    Video               // Video camera.
    TimelineStart       // Start boundary and the retained timeline after it.
    TimelineEnd         // End boundary and the retained timeline before it.
    Resident            // Puts the capture window in the notification area.
}

// The application icon document and the frames rasterized from it, shared by the main window
// and the headless test fixtures; parsed and rasterized once per process.
var g_CaptureIcons:       Gui.IconAtlas
var g_CaptureIconsParsed: bool

func captureIcons()->*Gui.IconAtlas
{
    if not g_CaptureIconsParsed
    {
        expect g_CaptureIcons.setup(cast(string, IconsSvg))
        expect g_CaptureIcons.setRaster(32, expect Image.decode(".png", #include("../datas/icons.32px.png")))
        expect g_CaptureIcons.setRaster(40, expect Image.decode(".png", #include("../datas/icons.40px.png")))
        g_CaptureIconsParsed = true
    }

    return &g_CaptureIcons
}

// The size of the thumbnails in the recent strip.
enum BottomSize
{
    Small
    Medium
    Big
}

// The application window: the capture on the ground with the tool dock, the inspector, the
// mini-bar and the hint line floating over it, or the library; the lens over both.
struct MainWnd
{
    using wnd: Wnd

    late
    {
        editArea, recentBar: *Wnd
        taskStrip:           *TaskStrip
        editWnd:             *EditWnd
        dock:                *ToolDock
        inspector:           *Inspector
        miniBar:             *MiniBar
        hintLine:            *HintLine
        recentSmall, recentMedium, recentBig: *IconButton
        sizeReading:         *IconButton
        zoomReading:         *IconButton
        toast:               *Toast
        lens:                *Lens.View
        menuLauncher:        *Lens.Launcher
        quickWnd:            *QuickWnd
        propWnd:             *PropWnd
        libWnd:              *LibraryWnd
        recentWnd:           *RecentWnd
        appearanceButton:    *AppearanceButton
    }

    takenHotKeys: Array'String      // Capture keys the desktop did not grant this process.

    // The timeline floating under the canvas while a timed capture is edited.
    timeline: *TimelineBar?

    // The hub or the menu of the notification-area icon, while one is on screen.
    residentPanel: *ResidentPanel?
    residentNotice: *TrayNotice?
    openHubAfterRecentLoad: bool
    metadataTimer: *Gui.Timer?
    copyTimer: *Gui.Timer?
    copyJob: *CaptureLoadJob?
    copyRequestedFile: String
    duplicateTimer: *Gui.Timer?
    duplicateJob: *CaptureDuplicateJob?
    duplicateSource: String
    exportTimer: *Gui.Timer?
    exportJob: *CaptureLoadJob?
    exportSource, exportDestination: String
    exportLinked: bool
    imageWriteJob: *CaptureImageWriteJob?
    videoCopyJobs: Array'(*CaptureVideoCopyJob)
    videoRecoveryJob: *CaptureVideoRecoveryJob?
    videoRecoveryFolder: String
    videoRecoveryCount: u64

    // The kind of selection the mini-bar was last built for, so it is rebuilt only when that changes.
    miniBarKind:       MiniBarKind = .None
    miniBarForm:       *BaseForm?              // The form the mini-bar was filled for, whose face, size and style it shows.
    miniBarFontFace:   *IconButton?            // Current text face, opened as a filtered choice popup.
    miniBarFontSize:   *IconButton?            // Current text size, opened through the same choice popup.
    textChoicePopover: *TextChoicePopover?     // Open face or size list, if any.

    icons:    IconSet
    appIcon:  ImageList
    monitors: Array'Env.Monitor

    // State
    editMode:      EditMode   = .Shape
    bottomSize:    BottomSize = .Medium
    pixSelFillCol: Color      = Argb.White
    inPlaceEdit, snap, freezeSel, libraryMode: bool
    showRecent, inspectorFolded: bool

    // The files saved during the session, which the "Show" of a toast opens the folder of.
    savedPaths: Array'String

    // What the action of the toast on screen runs.
    toastAction:           (func||())?
    recentColors:          Array'Color
    firstShow:             bool = true
    fileDlgState, fileDlgStateInPlace: FileDlgState
    libraryFolderDlgState: FileDlgState
    exportFolderDlgState:  FileDlgState
    libraryFolder:         String
    captureOptions:        CaptureOptions
    lastCapture:           String     // Command of the last capture taken, which the top strip offers again.
    editorOptions:         EditorOptions

    // Form models
    mdlFormShape:   FormShape
    mdlFormImage:   FormImage
    mdlFormStep:    FormStep
    mdlFormArrow:   FormArrow
    mdlFormLine:    FormLine
    mdlFormPolygon: FormPolygon
    mdlFormText:    FormText
    mdlFormDraw:    FormDraw
    mdlFormCallout: FormCallout

    // Set right after construction (create/test fixtures).
    late mdlHighlight, mdlPixSel, mdlFavorite: IForm

    // One interface per model field above, in FormRegistry order (see wrapper.swg)
    mdlByType: Array'IForm
}

impl IWnd for MainWnd
{
    mtd impl onTaskEvent(evt: *TaskEvent)
    {
        let job = .copyJob
        if job and evt.task == &job.task
        {
            .finishLibraryCopy(job)
            return
        }
        let duplicate = .duplicateJob
        if duplicate and evt.task == &duplicate.task
        {
            .finishDuplicateCapture(duplicate)
            return
        }
        let export = .exportJob
        if export and evt.task == &export.task
        {
            .finishLibraryExport(export)
            return
        }
        let imageWrite = .imageWriteJob
        if imageWrite and evt.task == &imageWrite.task
        {
            .finishLibraryImageWrite(imageWrite)
            return
        }
        for videoCopy in .videoCopyJobs where evt.task == &videoCopy.task
        {
            .finishVideoCopy(videoCopy)
            return
        }
        let recovery = .videoRecoveryJob
        if recovery and evt.task == &recovery.task
        {
            .finishVideoRecovery(recovery)
            return
        }
        evt.accepted = false
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer == .copyTimer
        {
            .stopTimer(&.copyTimer)
            .startLibraryCopy()
            return
        }
        if evt.timer == .duplicateTimer
        {
            .stopTimer(&.duplicateTimer)
            .startDuplicateCapture()
            return
        }
        if evt.timer == .exportTimer
        {
            .stopTimer(&.exportTimer)
            .startLibraryExport()
            return
        }
        if evt.timer != .metadataTimer
        {
            .wnd.IWnd.onTimerEvent(evt)
            return
        }
        let failed = g_CaptureSaves.collect()
        if not failed.isEmpty() do
            .reportFailure(Format.toString(appStrings().msg_FailedSaveCapture, failed))
        let job = g_CaptureSaves.metadataPending
        if job and job.task.isDone() do
            g_CaptureSaves.finishMetadata()
        if not g_CaptureSaves.metadataPending and g_CaptureSaves.metadataWaiting.isEmpty() do
            .stopTimer(&.metadataTimer)
    }

    mtd impl onSysUserEvent(evt: *SysUserEvent)
    {
        switch evt.kind
        {
        // Activating the icon opens what the application starts on; the hub stands in for
        // starting on nothing.
        case .TrayIcon:
            if evt.trayAction == .ContextMenu do
                ResidentPanel.open(me, .Menu)
            elif evt.trayAction == .Activate and .editorOptions.startup == .Editor do
                .showWindow()
            elif evt.trayAction == .Activate do
                ResidentPanel.open(me, .Hub)

        case .CustomMessage:
            if evt.messageId == OpenImageMessage and Clipboard.hasString() do
                .loadExternalImage(Clipboard.getString())
        }
    }

    // Takes an image dropped on the editor, from the desktop or from another application.
    //
    // Dropping a picture is the shortest way to open one, so it does exactly what the Open
    // command does — and a drag carrying several files opens one capture per file, which the
    // dialog cannot do at all. A drag that carries no file but carries a bitmap, the way an
    // image dragged out of a web page does, becomes a capture with nothing linked to it.
    mtd impl onDragDropEvent(evt: *DragDropEvent)
    {
        if not .hasDroppableImage(evt.data)
        {
            evt.accepted = false
            return
        }

        if evt.kind == .Drop do
            .openDroppedImages(evt.data)

        evt.effect = pickDropEffect(evt.allowed & (DropEffect.Copy | DropEffect.Link), evt.modifiers)
    }

    mtd impl onSysCommandEvent(evt: *SysCommandEvent)
    {
        evt.accepted = false
        if evt.kind == .Close
        {
            evt.accepted = true
            .saveAppState()
            if .editorOptions.hideOnClose
            {
                .surface?.hide()
                .noticeResident()
            }
            else do
                .postCommandEvent(ActionGlobal.Exit)
        }
    }

    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        // Without a strip to hold them, the task controls take a band of their own over the work.
        if .editArea != null do
            .editArea.margin.y = TaskStrip.bandHeight(me)
        if .miniBar != null do
            .placeMiniBar()
        if .sizeReading != null do
            .placeReadings()
    }

    mtd impl onDestroyEvent(_: *DestroyEvent)
    {
        for job in .videoCopyJobs
        {
            job.task.cancel()
            job.task.wait()
            Memory.delete(job)
        }
        .videoCopyJobs.clear()
        if .videoRecoveryJob
        {
            let job = .videoRecoveryJob
            .videoRecoveryJob = null
            job.task.cancel()
            job.task.wait()
            Memory.delete(job)
        }
        if .imageWriteJob
        {
            let job = .imageWriteJob
            .imageWriteJob = null
            job.task.cancel()
            job.task.wait()
            Memory.delete(job)
        }
        .stopTimer(&.exportTimer)
        if .exportJob
        {
            let job = .exportJob
            .exportJob = null
            job.task.cancel()
            job.task.wait()
            if job.capture do
                Memory.delete(job.capture)
            Memory.delete(job)
        }
        .stopTimer(&.duplicateTimer)
        if .duplicateJob
        {
            let job = .duplicateJob
            .duplicateJob = null
            job.task.cancel()
            job.task.wait()
            if job.snapshot do
                Memory.delete(job.snapshot)
            Memory.delete(job)
        }
        .stopTimer(&.copyTimer)
        if .copyJob
        {
            let job = .copyJob
            .copyJob = null
            job.task.cancel()
            job.task.wait()
            if job.capture do
                Memory.delete(job.capture)
            Memory.delete(job)
        }
        .stopTimer(&.metadataTimer)
        discard g_CaptureSaves.flush()
        .saveAppState()
        .icons.free()
        .appIcon.release(.app().renderer)
    }

    mtd impl onStateEvent(evt: *StateEvent)
    {
        switch evt.kind
        {
        case .Init:
            .restoreState()
            evt.accepted = true

        case .Show:
            evt.accepted = true

        case .Hide:
            .saveAppState()
        }
    }

    mtd impl onSerializeStateEvent(evt: *SerializeStateEvent)
    {
        if .inPlaceEdit do
            return

        let previousTheme    = .editorOptions.theme
        let previousLanguage = .editorOptions.language

        catch
        {
            with evt.serializer
            {
                try .serialize("MainWnd.editMode", &me.editMode)
                try .serialize("MainWnd.snap", &me.snap)
                try .serialize("MainWnd.bottomSize", &me.bottomSize)
                try .serialize("MainWnd.fileDlgState", &me.fileDlgState)
                try .serialize("MainWnd.fileDlgStateInPlace", &me.fileDlgStateInPlace)
                try .serialize("MainWnd.libraryFolderDlgState", &me.libraryFolderDlgState)
                try .serialize("MainWnd.exportFolderDlgState", &me.exportFolderDlgState)
                try .serialize("MainWnd.libraryFolder", &me.libraryFolder)
                try .serialize("MainWnd.librarySortMethod", &me.libWnd.sortMethod)
                try .serialize("MainWnd.libraryInvertSort", &me.libWnd.invertSort)
                try .serialize("MainWnd.libraryPreviewSize", &me.libWnd.previewSize)
                try .serialize("MainWnd.libraryContentFilter", &me.libWnd.contentFilter)
                try .serialize("MainWnd.libraryFavoritesOnly", &me.libWnd.favoritesOnly)
                try .serialize("MainWnd.libraryMinimumRating", &me.libWnd.minimumRating)
                try .serialize("MainWnd.libraryApplicationFilter", &me.libWnd.applicationFilter)
                try .serialize("MainWnd.libraryTagFilter", &me.libWnd.tagFilter)
                try .serialize("MainWnd.libraryShowLinked", &me.libWnd.showLinkedImage)
                try .serialize("MainWnd.libraryShowUnlinked", &me.libWnd.showUnLinkedImage)
                try .serialize("MainWnd.libraryShowCurrentLinked", &me.libWnd.showUpToDateLinkedImage)
                try .serialize("MainWnd.libraryShowChangedLinked", &me.libWnd.showUnSavedLinkedImage)
                try .serialize("MainWnd.libraryShowRatingOverlay", &me.libWnd.showRatingOverlay)
                try .serialize("MainWnd.libraryShowLinkOverlay", &me.libWnd.showLinkOverlay)
                try .serialize("MainWnd.showRecent", &me.showRecent)
                try .serialize("MainWnd.recentColors", &me.recentColors)
                try .serialize("MainWnd.inspectorFolded", &me.inspectorFolded)
                try .serialize("MainWnd.captureOptions", &me.captureOptions)
                try .serialize("MainWnd.lastCapture", &me.lastCapture)
                try .serialize("MainWnd.editorOptions", &me.editorOptions)
            }
        }

        if evt.serializer.isReading()
        {
            // Migrate the only legacy matte value: it used to be the default, before
            // transparent came to mean "follow the active palette".
            .migrateStoredOptions()

            if not .libraryFolder.isEmpty() do
                discard catch g_Library.setFolder(.libraryFolder)

            // Construction already applied these defaults. Reapplying an unchanged language
            // rebuilds localized controls throughout the tree during first-show restoration.
            if .editorOptions.theme != previousTheme do
                .setTheme()
            if .editorOptions.language != previousLanguage do
                .setLanguage()
            .setBottomSize(.bottomSize, animated: false)
            .showRecentBar(.showRecent)
            .inspector.setFolded(.inspectorFolded)
            .updateState()
        }
    }

    mtd impl onFrameEvent(evt: *FrameEvent)
    {
        if evt.firstFrame
        {
            .quickWnd.setDefault()
            .startVideoRecovery()
        }
    }
}

impl MainWnd
{
    // Recovers only this library's orphan video companions, one at a time on a worker.
    mtd startVideoRecovery()
    {
        if .videoRecoveryJob do
            return
        let folder = Library.getFolder()
        if .videoRecoveryFolder == folder or not Directory.exists(folder) do
            return
        .videoRecoveryFolder = folder
        let job = Memory.new'CaptureVideoRecoveryJob()
        job.folder = folder
        .videoRecoveryJob = job
        job.task.submit(func|job|()
        {
            catch { job.recovered = try Library.recoverOrphanVideos(job.folder) } as job.error
        }, .taskNotifier(&job.task))
    }

    private mtd finishVideoRecovery(job: *CaptureVideoRecoveryJob)
    {
        .videoRecoveryJob = null
        let count = job.recovered.count
        let current = Path.equals(job.folder, Library.getFolder())
        let failed = not job.error.isEmpty()
        Memory.delete(job)
        if not current do
            .videoRecoveryCount = 0
        if current and count
        {
            g_Library.fill()
            if .libraryMode do
                .libWnd.fill()
            .videoRecoveryCount += count
        }
        if current and count == VideoRecoveryBatchSize
        {
            .videoRecoveryFolder.clear()
            .startVideoRecovery()
            return
        }
        if .videoRecoveryCount
        {
            let total = .videoRecoveryCount
            .videoRecoveryCount = 0
            let message = total == 1 ? appStrings().msg_RecoveredVideo :
                                     Format.toString(appStrings().msg_RecoveredVideos, total)
            .confirm(message, "", appStrings().act_Library, func|main = me|()
            {
                if not main.libraryMode do
                    main.swapLibraryMode()
            })
        }
        if failed do
            .reportFailure(appStrings().msg_FailedRecoverVideos)
        .startVideoRecovery()
    }

    // Loads a library document on a worker after the destination has been chosen.
    mtd requestLibraryExport(source: String, destination: String, linked: bool)
    {
        if .exportJob or not .exportSource.isEmpty() or .imageWriteJob do
            return
        .exportSource = source
        .exportDestination = destination
        .exportLinked = linked
        .startLibraryExport()
    }

    private mtd startLibraryExport()
    {
        if .exportJob or .exportSource.isEmpty() do
            return
        let failed = g_CaptureSaves.collect()
        if not failed.isEmpty()
        {
            .reportFailure(Format.toString(appStrings().msg_FailedSaveCapture, failed))
            if failed == .exportSource
            {
                .exportSource.clear()
                return
            }
        }
        if g_CaptureSaves.writing(.exportSource)
        {
            if not .exportTimer do
                .exportTimer = .addTimer(16'ms)
            return
        }

        let job = Memory.new'CaptureLoadJob()
        job.file = .exportSource
        .exportJob = job
        job.task.submit(func|job|()
        {
            catch { job.capture = try Capture.load(job.file) } as job.error
        }, .taskNotifier(&job.task))
    }

    private mtd finishLibraryExport(job: *CaptureLoadJob)
    {
        .exportJob = null
        .exportSource.clear()
        let capture = job.capture
        let destination = String.from(.exportDestination)
        let linked = .exportLinked
        .exportDestination.clear()
        Memory.delete(job)
        if not capture
        {
            .reportFailure(appStrings().msg_FailedSaveFile, destination)
            return
        }

        defer Memory.delete(capture)
        capture.editView = .editWnd.editView
        if not linked and not capture.isTimed()
        {
            .startLibraryImageWrite(capture, destination)
            return
        }
        .saveLoadedAsImage(capture, destination, linked)
    }

    private mtd startLibraryImageWrite(capture: *Capture, destination: String)
    {
        var image = capture.toImage()
        if not image.isValid()
        {
            .reportFailure(appStrings().msg_FailedSaveFile, destination)
            return
        }
        let job = Memory.new'CaptureImageWriteJob()
        job.image  = #move image
        job.source = capture.file
        job.target = destination
        .imageWriteJob = job
        job.task.submit(func|job|()
        {
            catch saveCaptureImageFile(&job.image, job.source, job.target) as job.error
        }, .taskNotifier(&job.task))
    }

    private mtd finishLibraryImageWrite(job: *CaptureImageWriteJob)
    {
        .imageWriteJob = null
        let destination = String.from(job.target)
        let failed = not job.error.isEmpty()
        Memory.delete(job)
        if failed do
            .reportFailure(appStrings().msg_FailedSaveFile, destination)
        else do
            .confirmSaved(destination)
    }

    mtd startVideoCopy(source: String, destination: String)
    {
        let job = Memory.new'CaptureVideoCopyJob()
        job.source = source
        job.target = destination
        .videoCopyJobs.add(job)
        job.task.submit(func|job|()
        {
            catch exportOriginalVideo(job.source, job.target) as job.error
        }, .taskNotifier(&job.task))
    }

    private mtd finishVideoCopy(job: *CaptureVideoCopyJob)
    {
        for item, index in .videoCopyJobs where item == job
        {
            .videoCopyJobs.removeAtOrdered(index)
            break
        }
        let destination = String.from(job.target)
        let failed = not job.error.isEmpty()
        Memory.delete(job)
        if failed do
            .reportFailure(appStrings().msg_FailedSaveFile, destination)
        else do
            .confirmSaved(destination)
    }

    // Restores the saved state, once: the options, the placement of the window and the recent
    // captures.
    //
    // The first show of the window asks for it; an application that starts behind its hub or its
    // notification-area icon asks for it itself, because its options say what it starts on and
    // its window may not be shown for a long time.
    mtd restoreState()
    {
        if not .firstShow do
            return

        // Recent captures load on deferred event-loop turns, so a start is never held by them.
        .firstShow = false
        catch g_App.loadState()
        .surface?.constrainPositionToScreen(topLeft: true, margin: 10)
        .recentWnd.scheduleLoadRecent()
    }

    // Shows the notification-area reminder after the last application window leaves the screen.
    // A saved count from older versions never silently disables it.
    #[Swag.Discardable]
    mtd noticeResident()->bool
    {
        if not .editorOptions.showResidentNotice do
            return false

        .residentNotice?.close()
        let texts = appStrings()
        let notice = TrayNotice.open(unwrap .surface, texts.msg_ResidentTitle, texts.msg_ResidentText,
                                     texts.ui_DoNotShowResidentAgain)
        if not notice do
            return false
        .residentNotice = notice
        notice.sigOptionChanged += func|main = me|(_, checked)
        {
            main.editorOptions.showResidentNotice = not checked
            main.saveAppState()
        }
        notice.sigDismissed += func|main = me|(dismissed)
        {
            if main.residentNotice == dismissed do
                main.residentNotice = null
        }
        return true
    }

    // Puts the window on screen, in front of the others.
    mtd showWindow()
    {
        .residentNotice?.close()
        with let surface = unwrap .surface
        {
            if .isMinimized do
                .showNormal()
            else do
                .show()
            .bringToFront()
            #static if #os == Swag.TargetOs.Windows
            {
                if .win32Handle() do
                    discard Win32.SetForegroundWindow(.win32Handle())
            }
        }
    }

    // Migrates values whose historical default would otherwise pin an old visual choice
    // forever. User-picked colors are left untouched.
    mtd migrateStoredOptions()
    {
        if cast(u32, .editorOptions.theme) > cast(u32, AppearanceTheme.System) do
            .editorOptions.theme = .Dark
        if .editorOptions.editBackColor == 0xFF2E2E2E'u32 do
            .editorOptions.editBackColor = 0
    }

    mtd saveAppState()
    {
        if not .firstShow do
            catch g_App.saveState()
    }

    mtd saveCapture(capture: *Capture)
    {
        // A queued write to this capture must land before the explicit save.
        .flushCaptureSave(capture.file)
        catch capture.save() do
            MessageDlg.error(unwrap .surface, Format.toString(appStrings().msg_FailedSaveCapture, capture.file))
    }

    // Waits for the background save targeting `file` (any when null) and reports its
    // failure, which the timer that scheduled it can no longer do.
    mtd flushCaptureSave(file: string? = null)
    {
        let failed = g_CaptureSaves.flush(file)
        if not failed.isEmpty() do
            MessageDlg.error(unwrap .surface, Format.toString(appStrings().msg_FailedSaveCapture, failed))
    }

    // All library metadata writes share the automatic save's single file-writer lane.
    mtd queueCaptureMetadata(file: String, title: string? = null, tags: const *Array'String? = null, favorite: const *bool? = null, rating: const *u8? = null)
    {
        if title == null and not tags and not favorite and not rating do
            return
        let job = Memory.new'CaptureMetadataJob()
        job.owner = me
        job.file = file
        if title != null
        {
            job.title = title
            job.hasTitle = true
        }
        if tags
        {
            job.tags = tags[]
            job.hasTags = true
        }
        if favorite
        {
            job.favorite = favorite[]
            job.hasFavorite = true
        }
        if rating
        {
            job.rating = rating[]
            job.hasRating = true
        }
        g_CaptureSaves.adoptMetadata(job)
        if not .metadataTimer do
            .metadataTimer = .addTimer(30'ms)
    }

    mtd startMetadataTask(job: *CaptureMetadataJob)
    {
        job.task.submit(func|job|()
        {
            let title: string? = job.hasTitle ? job.title : null
            let tags: const *Array'String? = job.hasTags ? &job.tags : null
            let favorite: const *bool? = job.hasFavorite ? &job.favorite : null
            let rating: const *u8? = job.hasRating ? &job.rating : null
            catch Capture.updateFileMetadata(job.file, title, tags, favorite, rating) as job.error
        })
    }

    // Changes the user-defined name of a capture and persists it. An inactive capture's SCC
    // model and header are rewritten without decoding its background image.
    mtd setCaptureTitle(file: String, title: String)
    {
        let editCapture = .editWnd.getCapture()
        if editCapture and editCapture.file == file
        {
            editCapture.title   = title
            editCapture.changed = true
            .saveCapture(editCapture)
        }
        else do
            .queueCaptureMetadata(file, title: title)

        // Reflect the new title on the library preview(s) that reference this file.
        if .libWnd != null and .libWnd.view != null
        {
            for it in .libWnd.view.items where it.capture and it.fi.fullName == file do
                it.capture.title = title
            .libWnd.view.invalidate()
        }
    }

    // Requests a stored capture for the clipboard. The worker decodes it, then the interface
    // composes it through the editor's render context without changing the active selection.
    mtd copyLibraryImage(file: String)
    {
        .copyRequestedFile = file
        .startLibraryCopy()
    }

    private mtd startLibraryCopy()
    {
        if .copyJob or .copyRequestedFile.isEmpty() do
            return
        let failed = g_CaptureSaves.collect()
        if not failed.isEmpty() do
            .reportFailure(Format.toString(appStrings().msg_FailedSaveCapture, failed))
        if g_CaptureSaves.writing(.copyRequestedFile)
        {
            if not .copyTimer do
                .copyTimer = .addTimer(16'ms)
            return
        }

        let job = Memory.new'CaptureLoadJob()
        job.file = .copyRequestedFile
        .copyJob = job
        job.task.submit(func|job|()
        {
            catch { job.capture = try Capture.load(job.file) } as job.error
        }, .taskNotifier(&job.task))
    }

    private mtd finishLibraryCopy(job: *CaptureLoadJob)
    {
        .copyJob = null
        let loaded = job.capture
        let file   = job.file
        Memory.delete(job)
        if .copyRequestedFile != file
        {
            if loaded do
                Memory.delete(loaded)
            .startLibraryCopy()
            return
        }

        .copyRequestedFile.clear()
        if not loaded
        {
            .reportFailure(appStrings().msg_FailedCopyCapture, file)
            return
        }

        defer Memory.delete(loaded)
        loaded.editView = .editWnd.editView
        catch loaded.copyAll()
        {
            .reportFailure(appStrings().msg_FailedCopyCapture, file)
            return
        }
        .confirm(appStrings().msg_Copied)
    }

    // Duplicates the stored document on a worker, preserving its encoded images.
    mtd requestDuplicateCapture(source: String)
    {
        if .duplicateJob or not .duplicateSource.isEmpty() do
            return
        .duplicateSource = source
        .startDuplicateCapture()
    }

    mtd requestDuplicateActiveCapture(capture: *Capture)
    {
        if .duplicateJob or not .duplicateSource.isEmpty() do
            return
        let target = Library.newFileName()
        let snapshot = catch capture.snapshotDuplicate(target)
        {
            .reportFailure(appStrings().msg_FailedDuplicate, capture.file)
            return
        }
        let job = Memory.new'CaptureDuplicateJob()
        job.source = capture.file
        job.target = target
        job.snapshot = snapshot
        .duplicateJob = job
        job.task.submit(func|job|()
        {
            catch Capture.duplicateSnapshot(job.source, unwrap job.snapshot) as job.error
        }, .taskNotifier(&job.task))
    }

    private mtd startDuplicateCapture()
    {
        if .duplicateJob or .duplicateSource.isEmpty() do
            return
        let failed = g_CaptureSaves.collect()
        if not failed.isEmpty()
        {
            .reportFailure(Format.toString(appStrings().msg_FailedSaveCapture, failed))
            if failed == .duplicateSource
            {
                .duplicateSource.clear()
                return
            }
        }
        if g_CaptureSaves.writing(.duplicateSource)
        {
            if not .duplicateTimer do
                .duplicateTimer = .addTimer(16'ms)
            return
        }

        let job = Memory.new'CaptureDuplicateJob()
        job.source = .duplicateSource
        job.target = Library.newFileName()
        .duplicateJob = job
        job.task.submit(func|job|()
        {
            catch Capture.duplicateDocument(job.source, job.target) as job.error
        }, .taskNotifier(&job.task))
    }

    private mtd finishDuplicateCapture(job: *CaptureDuplicateJob)
    {
        .duplicateJob = null
        .duplicateSource.clear()
        let source = job.source
        let target = job.target
        let failed = not job.error.isEmpty()
        if job.snapshot do
            Memory.delete(job.snapshot)
        Memory.delete(job)
        if failed
        {
            .reportFailure(appStrings().msg_FailedDuplicate, source)
            return
        }

        g_Library.addFile(target)
        if .libraryMode do
            .libWnd.fill()
        catch
        {
            Memory.delete(try .recentWnd.addRecent(target))
            .recentWnd.recentView.requestSelect(0)
        }
        {
            .reportFailure(Format.toString(appStrings().msg_FailedLoadFile, target))
        }
    }

    // Opens the image file `arg`: the capture it was exported from when Swag Capture wrote it,
    // otherwise a new capture linked to the file.
    mtd loadExternalImage(arg: String)
    {
        // An animated picture opens as an animation, its frames kept in the library.
        let surface   = unwrap .surface
        let animation = catch Capture.importAnimation(arg)
        {
            MessageDlg.error(surface, Format.toString(appStrings().msg_FailedLoadFile, arg), Swag.err)
            return
        }

        if animation
        {
            .newCapture(animation.backImg, "", animation)
            return
        }

        let imgToLoad = catch Image.load(arg)
        {
            MessageDlg.error(surface, Format.toString(appStrings().msg_FailedLoadFile, arg), Swag.err)
            return
        }

        // A picture Swag Capture exported names the capture it came from: open that one instead.
        var done = false
        for md in imgToLoad.metadata where md.isTag(CaptureFileMetadataTag)
        {
            let linkedCapture = catch .recentWnd.addRecent(cast(string, md.toSlice())) { break }
            let linkedFile = String.from(linkedCapture.file)
            Memory.delete(linkedCapture)
            let active = .editWnd.getCapture()
            if not active or active.file != linkedFile do
                .recentWnd.requestSelection(linkedFile, false, {}, returnToEditor: .libraryMode)
            elif .libraryMode
            {
                .swapLibraryMode()
                .updateState()
            }
            done = true
            break
        }

        if not done do
            .newCapture(imgToLoad, arg)

        if .libraryMode and not done
        {
            .swapLibraryMode()
            .updateState()
        }

        .surface?.bringToFront()
    }

    // Returns the tool the editor acts as: the active one, or under the selection tool, the one
    // the selected forms belong to.
    mtd getEditMode()->EditMode
    {
        switch .editMode
        {
        case .Selection:
            .editMode = .Shape
            .getCapture()?.updateEditModeFromSelection()
            let edMode = .editMode
            .editMode = .Selection
            return edMode

        case .Favorites:
            return formToEditMode(.mdlFavorite)

        case .Highlight:
            return formToEditMode(.mdlHighlight)

        case .PixSel:
            return formToEditMode(.mdlPixSel)
        }

        return .editMode
    }

    // Freezes the forms the capture holds now, so the mouse only reaches forms drawn after them,
    // or makes them reachable again. A small status beside the inspector stays visible until then.
    mtd freezeSelection(freeze: bool)
    {
        if freeze == .freezeSel do
            return

        if freeze
        {
            // Nothing to freeze without a capture (the Freeze command is disabled in
            // that case, but guard here too so no code path can fault on getCapture()).
            let capture = .getCapture()
            if not capture do
                return

            capture.selection.clear()
            capture.selectionHasChanged()
            .freezeSel = true

            for it in capture.forms do
                it.freeze = true
        }
        else do
            .freezeSel = false

        if .taskStrip != null do
            .taskStrip.showFrozen(.freezeSel)
        .updateCommandState()
    }

    mtd updateState()
    {
        .updateWindowTitle()

        // The tool in use stands in the dock, in the cell of its group when it has one.
        if .dock != null do
            discard .dock.selectTool(toolCommand(.editMode))
        .updateCommandState()
        if .taskStrip != null
        {
            .taskStrip.showOutput(not .libraryMode)
            .taskStrip.itf.onLayout()
        }

        // The library owns its selection and controls. Rebuild the editor when it
        // becomes visible again, not while its whole subtree is hidden.
        if .libraryMode do
            return

        // The selection tool has no model to edit until an object is chosen. Leave the canvas
        // clear instead of showing the Shape model as though it belonged to the selection.
        let capture       = .getCapture()
        let showInspector = .editMode != .Selection or (capture and not capture.selection.isEmpty())
        if .inspector != null and .inspector.isLocallyVisible() != showInspector
        {
            .inspector.show(showInspector)
            let view = .editWnd.editView
            view.setZoom(view.zoom)
            if .taskStrip != null do
                .taskStrip.itf.onLayout()
        }

        if showInspector do
            .updateInspectorTitle()
        .fillHintLine()
        if .propWnd != null and showInspector do
            .propWnd.selectionHasChanged()
        if .quickWnd != null do
            .quickWnd.updateQuickStyles()
        .updateMiniBar()
    }

    // Names the window after the capture on screen, as the strip, the task bar and the window
    // switcher show it; after the application in the library or without a capture.
    mtd updateWindowTitle()
    {
        let surface = .surface
        if not surface do
            return

        var title: String = ProductName
        let capture       = .editWnd.getCapture()
        if capture and not .libraryMode
        {
            let name = capture.displayName()
            if not name.isEmpty() do
                title = name
        }

        if surface.wnd.name.raw != title do
            surface.setTitle(title)
    }

    mtd captureHasChanged()
    {
        .updateReading()
        .placeTimeline()
        if .recentWnd != null
        {
            .updateCommandState()
            .updateRecent()
        }
    }

    // Closes the frame file of the edited or focused capture stored in `file`, so the library can
    // move or delete it.
    mtd releaseCaptureMedia(file: string)
    {
        .timeline?.releaseCaptureMedia(file)
        let edited = .editWnd.getCapture()
        if edited and edited.isStoredIn(file) do
            edited.closeMedia()
        if .libraryMode
        {
            let focused = .libWnd.getCapture()
            if focused and focused.isStoredIn(file) do
                focused.closeMedia()
        }

        .placeTimeline()
    }

    mtd getCapture()->*Capture?
    {
        if .libraryMode do
            return .libWnd.getCapture()
        return .editWnd.getCapture()
    }

    mtd updateRecent()
    {
        if .recentWnd != null do
            .recentWnd.updateRecent()
    }

    // Writes the size and zoom as quiet menu controls at the head of the hint line.
    mtd updateReading()
    {
        if .hintLine == null or .sizeReading == null do
            return

        let capture = .editWnd.getCapture()
        if not capture or .libraryMode
        {
            .sizeReading.hide()
            .zoomReading.hide()
            .placeReadings()
            return
        }

        // The percent sign is appended rather than formatted: '%' is the placeholder itself.
        .sizeReading.show()
        .zoomReading.show()
        .sizeReading.setQuietText(Format.toString("% × %", capture.width, capture.height))
        .zoomReading.setQuietText(Format.toString("% %", cast(s32, Math.round(.editWnd.editView.zoom * 100)), "%"))
        .placeReadings()
        .fillHintLine()
    }

    // Offers the capture modes and screen-reading options before taking a screenshot.
    mtd showCaptureMenu(button: *IconButton)
    {
        let main      = me
        with let menu = MenuCtrl.createPopup(me)
        {
            .addItem(ActionCapture.Area)
            .addItem(ActionCapture.ActiveWnd)
            .addItem(ActionCapture.FullScreen)
            .addItem(ActionCapture.LastArea)
            for index in 0 until main.monitors.count do
                .addItem(ActionCapture.screenId(index))

            .addSeparator()
            .addItem(ActionCapture.RecordVideo)
            .addItem(ActionCapture.RecordActiveWindow)
            .addItem(ActionCapture.RecordScreen)
            for index in 0 until main.monitors.count do
                .addItem(ActionCapture.recordScreenId(index))
            .addSeparator()
            .addItem(ActionCapture.Record)
            .addSeparator()
            .addItem(ActionCapture.CaptureCursor)
        }

        menu.addSeparator()
        .addDelayChoices(menu)
        discard menu.doModal(button, autoDestroy: true)
    }

    // Ends `menu` with the waits before a capture, as one centred row of exclusive choices.
    //
    // A wait typed in the options that is none of the choices is named above them. The choices
    // post their command to this window, whatever surface the menu stands on.
    mtd addDelayChoices(menu: *MenuCtrl)
    {
        let main         = me
        let currentDelay = main.captureOptions.delay
        var isPreset = false
        for choice in CaptureDelays where choice.seconds == currentDelay do
            isPreset = true
        if not isPreset do
            menu.addNote(Format.toString(appStrings().act_DelayDuration, captureDelayName(currentDelay)))

        let metrics = main.themeMetrics()
        with let delayChoices = StackLayoutCtrl.create(menu, .HorizontalCenter)
        {
            .backgroundStyle = .Transparent
            .spacing         = metrics.menuPopup_SpaceLines
        }

        for choice in CaptureDelays
        {
            var glyph = CaptureIcons.Capture
            switch choice.seconds
            {
            case 3:  glyph = .Delay3
            case 5:  glyph = .Delay5
            case 10: glyph = .Delay10
            }
            with let delayButton = IconButton.create(delayChoices,
                                                     main.icon(glyph, metrics.menuPopup_IconSize),
                                                     {0, 0, 0, metrics.menuPopup_ItemHeight - metrics.menuPopup_SpaceLines * 0.75},
                                                     flags: .Radio)
            {
                .preferredSize.x = 0
                .padding         = metrics.btnIcon_Padding * 0.5
                .setIconSize(metrics.menuPopup_IconSize, metrics.menuPopup_IconSize)
                .setText(Format.toString("% s", choice.seconds))
                .setTextPosition(.Right)
                .setForm(.RoundedRectangle)
                .setCheckIndicator(.Frame)
                .setChecked(choice.seconds == currentDelay)
                .toolTip = captureDelayName(choice.seconds)
            }

            delayButton.sigCheckedChanged += func|main, toolbar = delayChoices, id = choice.id|(wnd)
            {
                let selected = assume cast(*IconButton, wnd)
                for child in toolbar.children
                {
                    if child is IconButton as other do
                        other.setChecked(other == selected)
                }
                main.postCommandEvent(id)
            }
        }
        menu.addWidget(delayChoices, fullWidth: true)
    }

    // Explains which desktop capture keys were unavailable at startup, beside Capture itself.
    mtd showUnavailableShortcuts(button: *IconButton)
    {
        let main = me
        with let menu = MenuCtrl.createPopup(me)
        {
            .addLabel(appStrings().ui_CaptureShortcuts)
            for key in main.takenHotKeys do
                .addNote(key.toString())
            .addSeparator()
            .addNote(appStrings().msg_ShortcutsUnavailableHelp)
        }

        discard menu.doModal(button, autoDestroy: true)
    }

    // Opens the existing image-size commands from the size shown on the editor.
    mtd showSizeMenu(button: *IconButton)
    {
        with let menu = MenuCtrl.createPopup(me)
        {
            .addItem(ActionImage.ResizeImage)
            .addItem(ActionImage.ExpandImage)
            .addItem(ActionImage.ExpandCapture)
            .addItem(ActionImage.TrimCapture)
        }

        discard menu.doModal(button, autoDestroy: true)
    }

    // Opens the existing camera commands from the zoom shown on the editor.
    mtd showZoomMenu(button: *IconButton)
    {
        with let menu = MenuCtrl.createPopup(me)
        {
            .addItem(ActionZoom.ZoomFit)
            .addItem(ActionZoom.Zoom1)
            .addSeparator()
            .addItem(ActionZoom.ZoomIn)
            .addItem(ActionZoom.ZoomOut)
        }

        discard menu.doModal(button, autoDestroy: true)
    }

    // Returns the name of a tool, as the inspector heads the properties it edits.
    // Reports whether `title` fits the head of the inspector before its actions.
    mtd titleFits(title: string)->bool
    {
        let metrics = .themeMetrics()
        let theme   = .theme()
        let words   = Painter.measureString(title, theme.createDefaultFont(metrics.inspector_TitleFontSize, .Bold)).width
        let small   = theme.createDefaultFont(metrics.defaultFontSize - 1)
        let actions = 2 * (metrics.menuPopup_IconSize + 2 * metrics.btnIcon_Padding) + Painter.measureString(" · ", small).width
        let room    = metrics.inspector_Width - 2 * metrics.inspector_Padding - actions - metrics.iconText_Margin
        return words <= room
    }

    // Returns the words counting one kind of object, from a table of "singular|plural" words.
    func countWords(table: string, count: u64)->String
    {
        let parts = Tokenize.split(table, '|'u8, removeEmpty: false)
        let words = (count == 1 or parts.count < 2) ? parts[0] : parts[1]
        return Format.toString(words, count)
    }

    // Returns the words counting each kind of the selected objects, in the order they first come,
    // such as "2 rectangles · 1 text".
    func describeKinds(capture: *Capture)->String
    {
        var tables: Array'string
        var counts: Array'u64
        for index in capture.selection
        {
            let table = kindCountTable(capture.forms[index])
            var found = false
            for t, i in tables where t == table
            {
                counts[i] += 1
                found     = true
            }

            if not found
            {
                tables.add(table)
                counts.add(1)
            }
        }

        var result: String
        for t, i in tables
        {
            if i do
                result += " · "
            result += countWords(t, counts[i])
        }

        return result
    }

    // Returns the "singular|plural" words counting objects of the kind of `form`.
    func kindCountTable(form: IForm)->string
    {
        let texts = appStrings()
        let base: *BaseForm = form
        if base.subKind == .Highlight do
            return texts.count_Highlight
        if base.subKind == .PixSel do
            return texts.count_PixSel

        switch form
        {
        case FormShape as shape: return shape.kind == .Ellipse ? texts.count_Ellipse : texts.count_Rectangle
        case FormArrow:          return texts.count_Arrow
        case FormLine:           return texts.count_Line
        case FormPolygon:        return texts.count_Polygon
        case FormText:           return texts.count_Text
        case FormCallout:        return texts.count_Callout
        case FormDraw:           return texts.count_Draw
        case FormStep:           return texts.count_Step
        case FormImage:          return texts.count_Image
        }

        return texts.count_Object
    }

    func editModeName(mode: EditMode)->string
    {
        switch #complete mode
        {
        case .Shape:     return appStrings().act_Shape
        case .Arrow:     return appStrings().act_Arrow
        case .Line:      return appStrings().act_Line
        case .Polygon:   return appStrings().act_Polygon
        case .Text:      return appStrings().act_Text
        case .Callout:   return appStrings().act_Callout
        case .Draw:      return appStrings().act_Draw
        case .Highlight: return appStrings().act_Highlight
        case .Step:      return appStrings().act_Step
        case .Image:     return appStrings().ui_MenuImage
        case .PixSel:    return appStrings().act_PixSel
        case .Favorites: return appStrings().act_Favorites
        case .Selection: return appStrings().act_Select
        }
    }

    // Confirms what the hand just did in a toast at the foot of the window: `message`, a name or
    // a path in `detail`, and an `action` word that runs `onAction` when clicked.
    mtd confirm(message: string, detail: string = "", action: string = "", onAction: (func||())? = null)
    {
        if .toast == null do
            return
        .toastAction = onAction
        .toast.show(message, detail, .Done, action)
    }

    // Says in a toast with a critical dot that `message` could not be done.
    mtd reportFailure(message: string, detail: string = "", action: string = "", onAction: (func||())? = null)
    {
        if .toast == null do
            return
        .toastAction = onAction
        .toast.show(message, detail, .Failure, action)
    }

    // Keeps the location of an interrupted video available from its failure toast.
    mtd reportRetainedVideo(path: String)
    {
        .savedPaths.add(path)
        let index = .savedPaths.count - 1
        .reportFailure(appStrings().msg_VideoKeptAfterError, Path.fileName(path) orelse "",
                       appStrings().act_Show, func|main = me, index|()
        {
            discard Env.showInFileExplorer(main.savedPaths[index])
        })
    }

    // Briefly names an operation that continues after its initiating gesture returns.
    mtd reportProgress(message: string)
    {
        if .toast == null do
            return
        .toastAction = null
        .toast.show(message, tone: .None)
    }

    // Returns the glyph of a tool, as the dock and the layers of the inspector show it.
    func editModeIcon(mode: EditMode)->CaptureIcons
    {
        switch #complete mode
        {
        case .Shape:     return .Shape
        case .Arrow:     return .Arrow
        case .Line:      return .Line
        case .Polygon:   return .Polygon
        case .Text:      return .Text
        case .Callout:   return .Text
        case .Draw:      return .Draw
        case .Highlight: return .Highlight
        case .Step:      return .Step
        case .Image:     return .Image
        case .PixSel:    return .PixSel
        case .Favorites: return .Favorites
        case .Selection: return .Select
        }
    }

    // Names what the inspector edits: the selected objects and their count, or the tool whose
    // next objects take these settings; and offers Duplicate and Delete for a selection.
    mtd updateInspectorTitle()
    {
        if .inspector == null do
            return

        .inspector.clear()
        let capture = .getCapture()
        let count   = capture ? capture.selection.count : 0
        if count == 0
        {
            .inspector.setTitle(editModeName(.getEditMode()), appStrings().ui_NextObjects)
            return
        }

        // One object is named by the tool that draws it: a highlighter stroke is a highlight and a
        // pixel selection a pixel selection, though they are a drawing and a shape underneath.
        var duplicates = true
        if count == 1
        {
            // A pixel selection is a region of the picture, not an object: it is measured, not
            // counted, and duplicating it means nothing.
            let form = capture!.forms[capture.selection.back()]
            let base: *BaseForm = form
            if .isPixelSelection()
            {
                .inspector.setTitle(editModeName(.PixSel), Format.toString("% × %", base.w, base.h))
                duplicates = false
            }
            elif form is FormImage as image where image.kind != .Image
            {
                // An image that hides or magnifies what it covers is named by what it does: a
                // blur, a pixelation, a magnifier, a snapshot.
                .inspector.setTitle(quickStyleKindName(image.kind), appStrings().ui_OneObject)
            }
            else
            {
                .inspector.setTitle(editModeName(formToolMode(form)), appStrings().ui_OneObject)
            }
        }
        else
        {
            // Several objects are named by what they are, "2 rectangles · 1 text", when that fits
            // before the actions of the head; otherwise by how many they are.
            let kinds = describeKinds(unwrap capture)
            if .titleFits(kinds) do
                .inspector.setTitle(kinds)
            else do
                .inspector.setTitle(Format.toString(appStrings().ui_Objects, count))
        }

        // Bind the inspector to the same wording, glyph and destructive state as every command presenter.
        for id in [ActionCopyPaste.Duplicate, ActionSelection.DeleteSelection]
        {
            if id == ActionCopyPaste.Duplicate and not duplicates do
                continue
            let state  = .sendComputeCommandStateEvent(id)
            let button = .inspector.addAction(state.name, id)
            let size   = .themeMetrics().menuPopup_IconSize
            button.setIconSize(size, size)
            button.updateFlags(add: .IconOnly)
            button.toolTip = state.name
            button.setQuietText(state.name)
        }
    }

    // Registers every command family of the editor.
    mtd registerActions()
    {
        .registerAction'ActionMoveSel()
        .registerAction'ActionTimeline()
        .registerAction'ActionUndo()
        .registerAction'ActionCaptureDelay()
        .registerAction'ActionPixSel()
        .registerAction'ActionCapture()
        .registerAction'ActionAlign()
        .registerAction'ActionGroup()
        .registerAction'ActionToolMode()
        .registerAction'ActionCopyPaste()
        .registerAction'ActionFile()
        .registerAction'ActionZoom()
        .registerAction'ActionImage()
        .registerAction'ActionSelection()
        .registerAction'ActionFlatten()
        .registerAction'ActionRecentSize()
        .registerAction'ActionQuickStyle()
        .registerAction'ActionEdit()
        .registerAction'ActionGlobal()
        .registerAction'ActionAbout()
        .registerAction'ActionOptions()
        .registerAction'ActionView()
    }

    // Binds the keyboard shortcuts of the editor to their commands.
    mtd registerShortcuts()
    {
        // Standard shortcuts
        .registerKeyShortcut(.Control, .C, ActionCopyPaste.Copy)
        .registerKeyShortcut(.Control, .X, ActionCopyPaste.Cut)
        .registerKeyShortcut(.Control, .V, ActionCopyPaste.Paste)
        .registerKeyShortcut(.Control, .Insert, ActionCopyPaste.Copy)
        .registerKeyShortcut(.Shift, .Insert, ActionCopyPaste.Paste)
        .registerKeyShortcut(.Control, .Z, ActionUndo.DoUndo)
        .registerKeyShortcut(.Control, .Y, ActionUndo.DoRedo)
        .registerKeyShortcut(.None, .Delete, ActionSelection.DeleteSelection)
        .registerKeyShortcut(.CtrlShift, .A, ActionCopyPaste.CopyAsImage)
        .registerKeyShortcut(.Control, .A, ActionSelection.SelectAll)
        .registerKeyShortcut(.None, .Escape, ActionSelection.DeSelectAll)
        .registerKeyShortcut(.Control, .D, ActionCopyPaste.Duplicate)
        .registerKeyShortcut(.CtrlShift, .D, ActionFile.DupCapture)
        .registerKeyShortcut(.CtrlShift, .I, ActionSelection.InvertSelection)
        .registerKeyShortcut(.Control, .L, ActionSelection.Freeze)
        .registerKeyShortcut(.CtrlShift, .T, ActionFlatten.FlattenAll)
        .registerKeyShortcut(.Alt, .F4, ActionGlobal.Exit)
        .registerKeyShortcut(.Control, .N, ActionFile.NewImage)
        .registerKeyShortcut(.CtrlShift, .N, ActionFile.NewFromClipboard)
        .registerKeyShortcut(.CtrlShift, .S, ActionFile.SaveAsImage)
        .registerKeyShortcut(.Control, .S, ActionFile.UpdateLinkedImage)
        .registerKeyShortcut(.Control, .O, ActionFile.OpenImage)
        .registerKeyShortcut(.None, .F2, ActionEdit.EditText)
        .registerKeyShortcut(.CtrlAlt, .O, ActionOptions.Options)
        .registerKeyShortcut(.Control, .G, ActionGroup.Group)
        .registerKeyShortcut(.CtrlShift, .G, ActionGroup.Ungroup)

        // ] and [ bring an object forward or back a step, with Ctrl to the front or the back.
        .registerKeyShortcut(.None, .Oem6, ActionAlign.MoveForward)
        .registerKeyShortcut(.None, .Oem4, ActionAlign.MoveBackward)
        .registerKeyShortcut(.Control, .Oem6, ActionAlign.SendToFront)
        .registerKeyShortcut(.Control, .Oem4, ActionAlign.SendToBack)
        .registerKeyShortcut(.None, .Space, ActionTimeline.Play)
        .registerKeyShortcut(.None, .OemComma, ActionTimeline.PrevFrame)
        .registerKeyShortcut(.None, .OemPeriod, ActionTimeline.NextFrame)
        .registerKeyShortcut(.Shift, .Oem4, ActionTimeline.ShowFrom)
        .registerKeyShortcut(.Shift, .Oem6, ActionTimeline.ShowUntil)
        .registerKeyShortcut(.Shift, .I, ActionTimeline.TrimStart)
        .registerKeyShortcut(.Shift, .O, ActionTimeline.TrimEnd)
        .registerKeyShortcut(.None, .Home, ActionAlign.SendToFront)
        .registerKeyShortcut(.None, .End, ActionAlign.SendToBack)
        .registerKeyShortcut(.None, .PageUp, ActionAlign.MoveForward)
        .registerKeyShortcut(.None, .PageDown, ActionAlign.MoveBackward)

        // The arrows nudge the selection a pixel, ten with Shift.
        .registerKeyShortcut(.None, .Left, ActionMoveSel.Left1)
        .registerKeyShortcut(.None, .Up, ActionMoveSel.Top1)
        .registerKeyShortcut(.None, .Right, ActionMoveSel.Right1)
        .registerKeyShortcut(.None, .Down, ActionMoveSel.Bottom1)
        .registerKeyShortcut(.Shift, .Left, ActionMoveSel.Left)
        .registerKeyShortcut(.Shift, .Up, ActionMoveSel.Top)
        .registerKeyShortcut(.Shift, .Right, ActionMoveSel.Right)
        .registerKeyShortcut(.Shift, .Down, ActionMoveSel.Bottom)
        .registerKeyShortcut(.Control, .Add, ActionZoom.ZoomIn)
        .registerKeyShortcut(.Control, .Subtract, ActionZoom.ZoomOut)
        .registerKeyShortcut(.Control, .NumPad0, ActionZoom.Zoom1)

        // Each tool answers a letter, the one the dock and the lens name: inside a field the
        // letter is typed, so a field keeps it.
        .registerKeyShortcut(.None, .V, ActionToolMode.Selection)
        .registerKeyShortcut(.None, .R, ActionToolMode.Shape)
        .registerKeyShortcut(.None, .P, ActionToolMode.Poly)
        .registerKeyShortcut(.None, .A, ActionToolMode.Arrow)
        .registerKeyShortcut(.None, .L, ActionToolMode.Line)
        .registerKeyShortcut(.None, .T, ActionToolMode.Text)
        .registerKeyShortcut(.None, .C, ActionToolMode.Callout)
        .registerKeyShortcut(.None, .D, ActionToolMode.Draw)
        .registerKeyShortcut(.None, .H, ActionToolMode.Highlight)
        .registerKeyShortcut(.None, .N, ActionToolMode.Step)
        .registerKeyShortcut(.None, .M, ActionToolMode.Img)
        .registerKeyShortcut(.None, .X, ActionToolMode.PixSel)
        .registerKeyShortcut(.None, .F, ActionToolMode.Favorites)

        // The searchable lens keeps its chord so Space remains available to the work and text fields.
        .registerKeyShortcut(.Control, .Space, ActionView.Lens)
        .registerKeyShortcut(.None, .I, ActionView.Inspector)
        .registerKeyShortcut(.CtrlShift, .H, ActionView.Recent)

        // Keep failed registrations by Capture, where their absence affects the user.
        .takenHotKeys.clear()

        #[Swag.Mixin]
        mtd registerHotKey(modifiers: Input.KeyModifiers, key: Input.Key, wndId: WndId)
        {
            catch .app().registerHotKey(modifiers, key, wndId, me) do
                .takenHotKeys.add(Input.formatKeyShortcut(modifiers, key))
        }

        .registerHotKey(.None, .PrintScreen, ActionCapture.Area)
        .registerHotKey(.Shift, .PrintScreen, ActionCapture.Record)
        .registerHotKey(.CtrlShift, .PrintScreen, ActionCapture.LastArea)
        .registerHotKey(.Control, .PrintScreen, ActionCapture.FullScreen)
        .registerHotKey(.Alt, .PrintScreen, ActionCapture.ActiveWnd)
        .registerHotKey(.CtrlShift, .F10, ActionCapture.RecordVideo)

        if .taskStrip != null do
            .taskStrip.showUnavailableShortcuts(not .takenHotKeys.isEmpty())
    }

    mtd setTheme()
    {
        .appearanceButton.setAppearanceTheme(.editorOptions.theme)

        // Pixel-selection forms borrow a theme color, so their retained renderings
        // follow the switch.
        if .editWnd != null do
            .editWnd.getCapture()?.invalidateAllFormCaches()
    }

    // Applies the language selected in the options to every string table.
    //
    // The tables always resolve, so a failure can only be an incomplete installation;
    // the interface then simply stays on the reference English wording.
    mtd setLanguage()
    {
        var tag: string = Gui.ReferenceLanguage
        switch #complete .editorOptions.language
        {
        case .System:  tag = ""
        case .French:  tag = "fr"
        case .English: break
        }

        discard catch .appearanceButton.setAppearanceLanguage(tag)
    }

    // Creates the glyph of a tool, at the size the dock draws it.
    mtd toolIcon(idx: CaptureIcons)->Icon => .icon(idx, .themeMetrics().toolDock_Glyph)

    // Creates an icon descriptor for an application glyph at `size` logical pixels.
    mtd icon(idx: CaptureIcons, size = 0.0)->Icon
    {
        let resolvedSize = size ? size : themeActionIconSize(.themeMetrics())
        return .icons.icon(cast(s32, idx), resolvedSize, .theme().res.atlasScale)
    }

    // Builds the main window: the work area with its dock, inspector, mini-bar and hint line,
    // the recent strip it shows on demand, the library hidden until it is asked for, and the
    // lens that reaches every command.
    func create(parent: *Wnd, testMonitors: *Array'Env.Monitor? = null)->*MainWnd
    {
        let srf = unwrap parent.surface
        srf.minSize = {1024, 512}

        let renderer = parent.app().renderer

        with let result = Wnd.create'MainWnd(parent, "capture.mainwnd")
        {
            result.surface!.setView(result)
            .icons.setup(renderer, captureIcons())
            #static if #command == Swag.CompilerCommand.Test do
                .appIcon.set(renderer.addImage(Image.create(512, 512, .RGBA8)))
            else do
                .appIcon.set(renderer.addImage(parent.app().appIcon))
            .backgroundStyle = .Window
            .mdlFavorite     = &result.mdlFormShape
            .mdlHighlight    = &result.mdlFormShape
            .mdlPixSel       = &result.mdlFormShape
            .monitors        = Env.getMonitors()
        }

        // Tests inject their display geometry before lens and menu commands are built.
        if testMonitors
        {
            result.monitors.clear()
            for monitor in testMonitors[] do
                result.monitors.add(monitor)
        }

        // Establish defaults before constructing localized controls, so they do not need
        // to rebuild immediately after construction. Saved preferences are applied on show.
        result.createAppearanceButton()
        result.setTheme()
        result.setLanguage()
        result.createRecentBar()
        result.createEditArea()
        result.createDock()
        result.createInspector()
        result.createMiniBar()
        result.createHintLine()
        result.toast = Toast.create(result)
        result.toast.sigAction += func|main = result|(_)
        {
            if main.toastAction do
                main.toastAction()
        }

        with result
        {
            .registerActions()
            .registerShortcuts()
            .setBottomSize(.Medium, animated: false)
            .libWnd = LibraryWnd.create(result)
            .libWnd.hide()
            .createTaskStrip()
            .createLens()
            .menuLauncher = Lens.Launcher.createMenu(result, .lens)
            .updateReading()
            .updateState()
        }

        // The ground around the picture moves the window, as the strip does.
        result.surface!.wnd.groundHitTest = func|result|(pos) => result.editWnd.editView.isWindowGround(pos)

        g_Main = result
        return result
    }
}
