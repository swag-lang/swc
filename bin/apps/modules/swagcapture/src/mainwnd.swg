// The main window once [[MainWnd.create]] has run. Headless fixtures that build a panel on its
// own leave it null.
var g_Main: *MainWnd?

const ClipboardFormat        = "Swag.Capture"
const CaptureFileMetadataTag = "Swag.Capture.File"
const IconsSvg               = #include("../datas/icons.svg")
const AppIcon                = #include("../datas/appicon.png")

// The editor tool, which decides what a drag on the capture creates.
enum EditMode { Shape, Arrow, Line, Polygon, Text, Favorites, Draw, Highlight, Selection, Step, Image, PixSel, Callout }

impl EditMode
{
    // Returns the name of the tool, as the inspector heads the properties it edits.
    func name(me)->string
    {
        switch #complete me
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

    // Returns the glyph of the tool, as the dock and the layers of the inspector show it.
    func glyph(me)->CaptureIcons
    {
        switch #complete me
        {
        case .Shape:     return CaptureIcons.Shape
        case .Arrow:     return CaptureIcons.Arrow
        case .Line:      return CaptureIcons.Line
        case .Polygon:   return CaptureIcons.Polygon
        case .Text:      return CaptureIcons.Text
        case .Callout:   return CaptureIcons.Callout
        case .Draw:      return CaptureIcons.Draw
        case .Highlight: return CaptureIcons.Highlight
        case .Step:      return CaptureIcons.Step
        case .Image:     return CaptureIcons.Image
        case .PixSel:    return CaptureIcons.PixSel
        case .Favorites: return CaptureIcons.Favorites
        case .Selection: return CaptureIcons.Select
        }
    }

    // Returns what the tool does, as the tooltip of its command says it.
    func tip(me)->string
    {
        switch #complete me
        {
        case .Shape:     return appStrings().tip_ToolShape
        case .Arrow:     return appStrings().tip_ToolArrow
        case .Line:      return appStrings().tip_ToolLine
        case .Polygon:   return appStrings().tip_ToolPolygon
        case .Text:      return appStrings().tip_ToolText
        case .Callout:   return appStrings().tip_ToolCallout
        case .Draw:      return appStrings().tip_ToolDraw
        case .Highlight: return appStrings().tip_ToolHighlight
        case .Step:      return appStrings().tip_ToolStep
        case .Image:     return appStrings().tip_ToolImage
        case .PixSel:    return appStrings().tip_ToolPixSel
        case .Favorites: return appStrings().tip_ToolFavorites
        case .Selection: return appStrings().tip_ToolSelect
        }
    }

    // Returns the command that takes the tool in hand.
    func command(me)->WndId
    {
        switch #complete me
        {
        case .Shape:     return ActionToolMode.Shape
        case .Arrow:     return ActionToolMode.Arrow
        case .Line:      return ActionToolMode.Line
        case .Polygon:   return ActionToolMode.Poly
        case .Text:      return ActionToolMode.Text
        case .Callout:   return ActionToolMode.Callout
        case .Draw:      return ActionToolMode.Draw
        case .Highlight: return ActionToolMode.Highlight
        case .Step:      return ActionToolMode.Step
        case .Image:     return ActionToolMode.Img
        case .PixSel:    return ActionToolMode.PixSel
        case .Favorites: return ActionToolMode.Favorites
        case .Selection: return ActionToolMode.Selection
        }
    }
}

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

// The most recent captures the lens shows as pictures.
const MaxLensRecents = 6

// Register each command once; the lens and its optional application menu use the same entries.
const CaptureModeIds   = [ActionCapture.LastArea, ActionCapture.FullScreen, ActionCapture.ActiveWnd]
const CaptureDelayIds  = [ActionCaptureDelay.Delay0, ActionCaptureDelay.Delay3, ActionCaptureDelay.Delay5, ActionCaptureDelay.Delay10]
const CaptureOptionIds = [ActionCapture.HideEditor, ActionCapture.CaptureCursor, ActionCapture.ToInPlace, ActionCapture.ToEditor, ActionCapture.ToClipboard]
const FileStartIds     = [ActionFile.NewImage, ActionFile.NewFromClipboard, ActionFile.OpenImage]
const FileLinkedIds    = [ActionFile.SaveAsLinkedImage, ActionFile.UpdateLinkedImage, ActionFile.UnlinkImage]
const FileCaptureIds   = [ActionFile.DupCapture, ActionFile.RenameCapture, ActionFile.DeleteCapture,
                          ActionFile.CaptureFileLocation, ActionFile.LinkedFileLocation, ActionFile.FileDetails]
const EditHistoryIds   = [ActionUndo.DoUndo, ActionUndo.DoRedo]
const EditClipboardIds = [ActionCopyPaste.Copy, ActionCopyPaste.Cut, ActionCopyPaste.Paste, ActionCopyPaste.Duplicate]
const EditObjectIds    = [ActionSelection.DeleteSelection, ActionEdit.EditText, ActionEdit.Bold, ActionEdit.Italic,
                          ActionEdit.ResetSteps, ActionCopyPaste.PasteImageInside, ActionEdit.ClearImageInside]
const EditorSelectionIds = [ActionSelection.SelectAll, ActionSelection.SelectSameAll, ActionSelection.DeSelectAll,
                            ActionSelection.InvertSelection, ActionGroup.Group, ActionGroup.Ungroup,
                            ActionEdit.ResetRotation, ActionSelection.Freeze, ActionSelection.Snap]
const PixelSelectionIds = [ActionPixSel.Fill, ActionPixSel.SmartFill, ActionPixSel.Clear, ActionPixSel.SmartMove]
const AlignMenuIds      = [ActionAlign.AlignLeft, ActionAlign.AlignCenter, ActionAlign.AlignRight,
                           ActionAlign.AlignTop, ActionAlign.AlignMiddle, ActionAlign.AlignBottom]
const ArrangeMenuIds   = [ActionAlign.SendToFront, ActionAlign.SendToBack, ActionAlign.MoveForward, ActionAlign.MoveBackward]
const ImageGeometryIds = [ActionImage.RestoreOrg, ActionImage.ResizeImage, ActionImage.ExpandImage,
                          ActionImage.ExpandCapture, ActionImage.TrimCapture]
const ImageFlattenIds   = [ActionFlatten.Flatten, ActionFlatten.FlattenAll]
const ImageTransformIds = [ActionImage.FlipImage, ActionImage.MirrorImage, ActionImage.RotateImageRight, ActionImage.RotateImageLeft]
const ToolMenuIds       = [ActionToolMode.Selection, ActionToolMode.Shape, ActionToolMode.Arrow, ActionToolMode.Line, ActionToolMode.Poly,
                           ActionToolMode.Text, ActionToolMode.Callout, ActionToolMode.Draw, ActionToolMode.Highlight, ActionToolMode.Step,
                           ActionToolMode.Img, ActionToolMode.PixSel, ActionToolMode.Favorites, ActionQuickStyle.Reset]
const ViewPanelIds  = [ActionView.Inspector, ActionView.Recent]
const ViewZoomIds   = [ActionZoom.ZoomIn, ActionZoom.ZoomOut, ActionZoom.Zoom1, ActionZoom.ZoomFit]
const RecentSizeIds = [ActionRecentSize.RecentSmall, ActionRecentSize.RecentMedium, ActionRecentSize.RecentBig]

// Paints the preview of a recent capture into a picture of the lens, filling it.
func paintLensRecent(painter: *Painter, rect: Math.Rectangle, preview: Texture)
{
    if not preview.isValid() do
        return
    let ratio = Math.max(rect.width / preview.width, rect.height / preview.height)
    let w     = preview.width * ratio
    let h     = preview.height * ratio
    painter.setInterpolationMode(.Linear)
    painter.drawTexture(Math.Rectangle{rect.horzCenter() - w * 0.5, rect.vertCenter() - h * 0.5, w, h}, preview)
}

// The room the floating parts of the editor take over the edges of the work.
struct FloatingInsets
{
    left:  f32     // Taken over the leading edge, by the dock.
    right: f32     // Taken over the trailing edge, by the unfolded inspector.
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
        miniBar:             *SelectionBar
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

    // The resident home, centered or opened beside the pointer.
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
                ResidentPanel.open(me, .AtPointer)
            elif evt.trayAction == .Activate and .editorOptions.startup == .Editor do
                .showWindow()
            elif evt.trayAction == .Activate do
                ResidentPanel.open(me, .Centered)

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
            .startImageWrite(capture, destination)
            return
        }
        .saveLoadedAsImage(capture, destination, linked)
    }

    // Composes `capture` here, where its forms can use the renderer, then encodes and writes
    // the picture to `destination` on a worker.
    internal mtd startImageWrite(capture: *Capture, destination: String)
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
    mtd queueCaptureMetadata(file: String, title: string? = null, tags: const *Array'String? = null, favorite: const *bool? = null, rating: const *u8? = null, unlink = false)
    {
        if title == null and not tags and not favorite and not rating and not unlink do
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
        job.unlink = unlink
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
            catch Capture.updateFileMetadata(job.file, title, tags, favorite, rating, job.unlink) as job.error
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
            discard .dock.selectTool(.editMode.command())
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

        if surface.wnd.name.text != title do
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

    // Ends `menu` with capture delays and an optional cursor toggle on the same centered row.
    //
    // A wait typed in the options that is none of the choices is named above them. The choices
    // post their command to this window, whatever surface the menu stands on.
    mtd addDelayChoices(menu: *MenuCtrl, includeCursor = false)
    {
        let main         = me
        let currentDelay = main.captureOptions.delay
        var isPreset     = false
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

        if includeCursor
        {
            with let cursor = IconButton.create(delayChoices,
                                                main.icon(.Select, metrics.menuPopup_IconSize),
                                                {0, 0, 0, metrics.menuPopup_ItemHeight - metrics.menuPopup_SpaceLines * 0.75},
                                                flags: .Toggle)
            {
                .preferredSize.x = 0
                .padding         = metrics.btnIcon_Padding * 0.5
                .setIconSize(metrics.menuPopup_IconSize, metrics.menuPopup_IconSize)
                .setText(appStrings().ui_AimCursor)
                .setTextPosition(.Right)
                .setForm(.RoundedRectangle)
                .setCheckIndicator(.Frame)
                .setChecked(main.captureOptions.captureCursor)
                .toolTip = appStrings().act_CaptureCursor
                .sigCheckedChanged += func|main|(_) { main.postCommandEvent(ActionCapture.CaptureCursor) }
            }
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
                    if child is IconButton as other where other.flags.has(.Radio) do
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
            .inspector.setTitle(.getEditMode().name(), appStrings().ui_NextObjects)
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
                .inspector.setTitle(EditMode.PixSel.name(), Format.toString("% × %", base.w, base.h))
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
                .inspector.setTitle(formToolMode(form).name(), appStrings().ui_OneObject)
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

        // A laptop has no keypad: the zoom also answers the keys of the main row.
        .registerKeyShortcut(.Control, .OemPlus, ActionZoom.ZoomIn)
        .registerKeyShortcut(.Control, .OemMinus, ActionZoom.ZoomOut)
        .registerKeyShortcut(.Control, .D0, ActionZoom.Zoom1)

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

    // The repeated capture and output gestures, in the top strip over the editor and the library.
    //
    // It is built once the library exists, so that it stands in front of both pages.
    mtd createTaskStrip()
    {
        .taskStrip = TaskStrip.create(me)
    }

    // Speech-bubble glyph drawn for the Callout tool: the icon sheet has no sprite for this
    // tool, so it paints its own rounded body plus a small tail. Its round corners are deliberate:
    // the glyph depicts a shape the user draws, not chrome.
    func drawCalloutGlyph(btn: *IconButton, bc: *PaintContext, pos: Math.Rectangle, _: PaintItemFlags)
    {
        bc.painter.setParams(.Antialiased)
        let col = btn.isChecked ? btn.themeColors().btnIcon_CheckedIcon : btn.themeColors().btnIcon_Icon

        // A custom painter is handed the whole content rectangle, not the icon extent, so the
        // glyph places itself where a sprite of the set would have landed: centred in its cell.
        let glyphSize = btn.themeMetrics().toolDock_Glyph
        let box       = Math.Rectangle{pos.horzCenter() - glyphSize * 0.5, pos.vertCenter() - glyphSize * 0.5, glyphSize, glyphSize}

        // The sprites of the set are outlines on about three fifths of their box; the bubble
        // matches that weight so the dock reads as one column of glyphs.
        var body = box
        body.inflate(-box.width * 0.18, -box.height * 0.22)
        body.height *= 0.72

        let stroke = 1.4'f32
        let tx     = body.x + body.width * 0.28
        let tip    = body.bottom() + box.height * 0.18
        bc.painter.drawLine(tx, body.bottom(), tx, tip, col, stroke)
        bc.painter.drawLine(tx, tip, tx + body.width * 0.28, body.bottom(), col, stroke)
        bc.painter.drawRoundRect(body, 3, 3, col, stroke)
    }

    // The work area: the capture on the ground, and the floating parts that serve it.
    //
    // The editor takes the whole window, under the strip too; the dock, the inspector, the
    // mini-bar and the hint line float over it and take no room from it.
    mtd createEditArea()
    {
        with .editArea = Wnd.create'Wnd(me)
        {
            .dockStyle       = .Center
            .backgroundStyle = .Window

            // Floating shadows need to reach across the edge where the recent strip begins.
            .wndFlags.remove(.ClipChildren)
        }

        with .editWnd = EditWnd.create(me, me.editArea)
        {
            .dockStyle                = .Center
            .backgroundStyle          = .Transparent
            .sigScrollSizeChanged     += func|main = me|(_, _, _) { main.updateReading() }
            .sigScrollPositionChanged += func|main = me|(_, _, _) { main.placeMiniBar() }
        }
    }

    // The tools, in a floating column at the leading edge of the work. A tool is a command like
    // any other: its button posts it, and the command state checks the tool in use.
    mtd createDock()
    {
        .dock = ToolDock.create(.editArea)

        // Eight cells, as the pictures; a cell with a mark stands for a group of tools, each of
        // which keeps its command and its key.
        .dock.addTool(.toolIcon(.Select), ActionToolMode.Selection)
        let shape = .dock.addTool(.toolIcon(.Shape), ActionToolMode.Shape)
        .dock.addToGroup(shape, .toolIcon(.Polygon), ActionToolMode.Poly)
        let arrow = .dock.addTool(.toolIcon(.Arrow), ActionToolMode.Arrow)
        .dock.addToGroup(arrow, .toolIcon(.Line), ActionToolMode.Line)
        .dock.addTool(.toolIcon(.Text), ActionToolMode.Text)

        // The callout has no sprite of its own: its cell draws the bubble.
        let callout = .dock.addTool(.toolIcon(.Text), ActionToolMode.Callout)
        callout.iconPainter = func(btn, bc, pos, flags) { drawCalloutGlyph(btn, bc, pos, flags) }

        let draw = .dock.addTool(.toolIcon(.Draw), ActionToolMode.Draw)
        .dock.addToGroup(draw, .toolIcon(.Highlight), ActionToolMode.Highlight)
        .dock.addTool(.toolIcon(.Step), ActionToolMode.Step)
        let image = .dock.addTool(.toolIcon(.Image), ActionToolMode.Img)
        .dock.addToGroup(image, .toolIcon(.PixSel), ActionToolMode.PixSel)
        .dock.addToGroup(image, .toolIcon(.Favorites), ActionToolMode.Favorites)
    }

    // The properties of the selection, or of the tool when nothing is selected: the quick styles
    // of its kind above the settings the property panel generates for it.
    mtd createInspector()
    {
        .inspector = Inspector.create(.editArea)
        .inspector.topOffset      = .themeMetrics().floating_Inset
        .inspector.sigFoldChanged += func|main = me|(inspector)
        {
            main.inspectorFolded = inspector.folded
            main.fillHintLine()
            let view = main.editWnd.editView
            view.setZoom(view.zoom)
            main.placeMiniBar()
            if main.taskStrip != null do
                main.taskStrip.itf.onLayout()
        }

        with let body = Wnd.create'Wnd(.inspector)
        {
            .backgroundStyle = .Transparent
        }

        with .quickWnd = QuickWnd.create(body, me)
        {
            .dockStyle = .Top
            // Keep the six-chip row centred in the content column; the scroll gutter
            // belongs to the property view below it.
            let gutter = .themeMetrics().scrollBar_HitSize + .themeMetrics().scrollBar_EdgeInset
            .margin.x = gutter * 0.5
            .margin.z = gutter * 1.5
        }

        with .propWnd = PropWnd.create(body, me)
        {
            .dockStyle = .Center
        }

        .inspector.setContent(body)
    }

    // The bar that stands next to the selection, carrying what applies to it.
    mtd createMiniBar()
    {
        .miniBar = SelectionBar.create(me, .editArea)
    }

    // Fills the mini-bar from the selection and places it beside it.
    mtd updateMiniBar()
    {
        if .miniBar == null do
            return
        .miniBar.refresh()
        .placeMiniBar()
    }

    // Returns the room the dock and the unfolded inspector take over the leading and the trailing
    // edges of the work, which the capture is centred between.
    mtd floatingInsets()->FloatingInsets
    {
        var result: FloatingInsets
        if .dock != null and .dock.isLocallyVisible() do
            result.left = .dock.position.right()
        if .inspector != null and .inspector.isLocallyVisible() and not .inspector.folded do
            result.right = Math.max(.editArea.position.width - .inspector.position.x, 0)
        return result
    }

    // Returns the face, the size, the style and the horizontal alignment of the selected text or callout.
    mtd selectedTextStyle()->{found: bool, type: typeinfo, face: string, size: f32, style: FontFamilyStyle, align: FormTextAlign, alignVert: FormTextAlign}
    {
        switch .getCapture()?.getSelectedBaseForm()
        {
        case FormText as text:       return {true, FormText, text.fontName.toString(), text.fontSize, text.fontStyle, text.alignHorz, text.alignVert}
        case FormCallout as callout: return {true, FormCallout, callout.fontName.toString(), callout.fontSize, callout.fontStyle, callout.alignHorz, callout.alignVert}
        }

        return {false, FormText, "", 0, .Regular, .Center, .Center}
    }

    // Sets the face of the selected texts to `face`, the interface face when empty, as one step
    // of the history; the style of each stays.
    mtd setSelectedFace(face: string)
    {
        let capture = .getCapture()
        let style   = .selectedTextStyle()
        if not capture or not style.found or face == style.face do
            return

        with let undo = capture.newUndo(.SetFont)
        {
            .text      = face
            .fontStyle = style.style
        }

        capture.pushUndo(undo)
        capture.selectionHasChanged()
    }

    // Places the mini-bar beside the selection, or hides it when nothing is selected.
    mtd placeMiniBar()
    {
        if .miniBar == null do
            return

        let capture = .getCapture()
        if .miniBar.shownKind == .None or not capture or capture.selection.isEmpty()
        {
            discard .app().animator.leave(.miniBar)
            return
        }

        let view    = .editWnd.editView
        let place   = view.getCaptureRect()
        let surface = .selectionSurfaceRect()
        let local   = .editArea.surfaceToLocal(surface.topLeft())
        let rect    = Math.Rectangle{local.x, local.y, surface.width, surface.height}

        // The bar keeps clear of the dock and of the inspector, and goes below the words being
        // typed in place, where the reader is not looking.
        let insets = .floatingInsets()
        var room   = .editArea.clientRect()
        room.x     += insets.left
        room.width -= insets.left + insets.right

        // The caption strip covers the editor's top edge. Keep the bar below it
        // when choosing which side of the selection has room.
        let stripInset = .editArea.stripInset()
        room.y      += stripInset
        room.height -= stripInset

        // Across, it stands within the picture when the picture is wide enough for it, so that it
        // never straddles a side edge of the capture: a gap of the bar's own distance is the most
        // it reaches past the edge, which the bar keeps clear of anyway.
        let gap     = .themeMetrics().miniBar_Distance
        let corner  = .editArea.surfaceToLocal(view.localToSurface(Math.Point{place.x - view.scrollPos.x, place.y - view.scrollPos.y}))
        let picture = Math.Rectangle{corner.x, corner.y, place.width, place.height}
        if picture.width >= .miniBar.bodySize().x
        {
            let left  = Math.max(room.x, picture.x - gap)
            let right = Math.min(room.right(), picture.right() + gap)
            if right - left >= .miniBar.bodySize().x + 2 * gap
            {
                room.x     = left
                room.width = right - left
            }
        }

        .miniBar.showNear(.miniBarAnchor(rect, place, view), below: view.isEditingText(), room: room)
    }

    // Returns the bounds of the selection in surface coordinates. The selection is measured in
    // capture pixels: the view places the capture at its zoom, and scrolls it.
    mtd selectionSurfaceRect()->Math.Rectangle
    {
        let capture = .getCapture()
        if not capture or capture.selection.isEmpty() do
            return {}
        let view   = .editWnd.editView
        let bound  = capture.getSelectionBoundRect()
        let place  = view.getCaptureRect()
        let zoom   = view.zoom
        let corner = view.localToSurface(Math.Point{place.x + bound.x * zoom - view.scrollPos.x, place.y + bound.y * zoom - view.scrollPos.y})
        return Math.Rectangle{corner.x, corner.y, bound.width * zoom, bound.height * zoom}
    }

    // Returns the rectangle the mini-bar stands next to, for a selection at `rect`: the
    // selection, reaching out to an edge of the capture when the bar would otherwise straddle that
    // edge, so the bar stands either inside the capture or wholly outside it.
    mtd miniBarAnchor(rect: Math.Rectangle, place: Math.Rectangle, view: *EditView)->Math.Rectangle
    {
        let metrics = .themeMetrics()
        let reach   = metrics.miniBar_Distance + .miniBar.bodySize().y
        let corner  = .editArea.surfaceToLocal(view.localToSurface(Math.Point{place.x - view.scrollPos.x, place.y - view.scrollPos.y}))
        let top     = corner.y
        let bottom  = corner.y + place.height

        var result = rect
        if result.y - reach < top and result.y > top
        {
            result.height += result.y - top
            result.y      = top
        }

        if result.bottom() + reach > bottom and result.bottom() < bottom do
            result.height = bottom - result.y
        return result
    }

    // The faint line at the foot of the work: the size and zoom of the capture, then the key
    // that opens everything else.
    mtd createHintLine()
    {
        .hintLine = HintLine.create(.editArea)
        with .sizeReading = IconButton.createQuiet(.editArea)
        {
            .style.setFont(.theme().createDefaultFontFs(.themeMetrics().hintLine_FontSize), .Regular)
            .setArrowPosition(.RightUpward)
            .sigPressed += func|main = me|(button) { main.showSizeMenu(button) }
        }

        with .zoomReading = IconButton.createQuiet(.editArea)
        {
            .style.setFont(.theme().createDefaultFontFs(.themeMetrics().hintLine_FontSize), .Regular)
            .setArrowPosition(.RightUpward)
            .sigPressed += func|main = me|(button) { main.showZoomMenu(button) }
        }

        .hintLine.setReading(null)
        .updateReading()
        .fillHintLine()

        .timeline = TimelineBar.create(me, .editArea)
        .timeline.panel.hide()
    }

    // Shows the timeline above the hint line while a timed capture is edited, and hides it
    // otherwise.
    mtd placeTimeline()
    {
        let timeline = .timeline
        if not timeline do
            return

        let capture = .getCapture()
        if .libraryMode or not capture or not capture.isTimed() or not capture.frames
        {
            if timeline.isPlaying() do
                timeline.stop()
            timeline.panel.hide()
            if .toast != null do
                .toast.keepAbove(0)
            return
        }

        // The panel keeps the air of the other floating parts from the dock and the inspector.
        let metrics = .themeMetrics()
        let insets  = .floatingInsets()
        let room    = .editArea.clientRect()
        let left    = insets.left + metrics.floating_Inset
        let width   = Math.max(room.width - left - insets.right - metrics.floating_Inset, 0)
        let bottom  = room.bottom() - metrics.hintLine_Bottom - metrics.hintLine_Height - TimelineGap
        timeline.panel.setPosition({left, bottom - TimelineHeight, width, TimelineHeight})
        timeline.panel.show()
        timeline.invalidate()

        // A confirmation stands above the timeline rather than over its track.
        if .toast != null do
            .toast.keepAbove(timeline.panel.surfaceRect().y - .surfaceRect().y)
    }

    // Reserves the first part of the hint line for the two readings and puts each menu anchor
    // on the same baseline as the line's words.
    mtd placeReadings()
    {
        if .hintLine == null or .sizeReading == null do
            return

        let metrics = .themeMetrics()
        let insets  = .floatingInsets()
        var x       = insets.left
        let y       = Math.round(.editArea.clientRect().bottom() - metrics.hintLine_Bottom - metrics.hintLine_Height)

        if .sizeReading.isLocallyVisible()
        {
            .sizeReading.setPosition(Math.Rectangle{x, y, .sizeReading.position.width, metrics.hintLine_Height})
            x += .sizeReading.position.width + metrics.hintLine_GroupGap

            .zoomReading.setPosition(Math.Rectangle{x, y, .zoomReading.position.width, metrics.hintLine_Height})
            x += .zoomReading.position.width + metrics.hintLine_GroupGap
        }

        .hintLine.margin = {x, 0, insets.right, 0}
        .hintLine.setReading(null)
        .placeTimeline()
    }

    // Reports whether the selection is one pixel selection, a region of the picture.
    mtd isPixelSelection()->bool
    {
        let capture = .getCapture()
        if not capture or capture.selection.count != 1 do
            return false
        let base: *BaseForm = capture.forms[capture.selection[0]]
        return base.subKind == .PixSel
    }

    // Writes the foot line: what the tool in hand does, the key of the inspector while it is
    // folded, and the searchable lens.
    mtd fillHintLine()
    {
        if .hintLine == null do
            return

        // The line stands in the room the dock and the inspector leave, never under them.
        .placeReadings()
        .hintLine.clearHints()
        if .editWnd != null and .editWnd.editView.isEditingText()
        {
            // The keys come first: a line cut by a narrow room loses the advice, not the keys.
            let view = .editWnd.editView
            .hintLine.addHint(view.textSpec.step ? strings().key_Enter : strings().key_CtrlEnter, appStrings().hint_KeepText)
            .hintLine.addHint(strings().key_Escape, appStrings().hint_Cancel)
            if not view.textSpec.step do
                .hintLine.addHint(strings().key_Enter, appStrings().hint_NewLine)
            if view.textEditForm() is FormCallout do
                .hintLine.addHint("", appStrings().hint_CalloutTail)
            return
        }

        // With a selection, the line teaches its keys: nudge, duplicate, then the words of a shape
        // that has some, or delete; four keys are what the room beside the inspector holds. Without
        // one, what the tool in hand does, and the lens.
        let capture  = .getCapture()
        let selected = not .libraryMode and capture and not capture.selection.isEmpty()
        if selected
        {
            // A pixel selection is a region, not an object: it is not duplicated.
            .hintLine.addHint(appStrings().key_Arrows, appStrings().hint_Nudge)
            if not .isPixelSelection() do
                .hintLine.addHint(Input.formatKeyShortcut(.Control, .D), appStrings().hint_Duplicate)
            if capture!.selection.count == 1 and inlineTextOf(capture.forms[capture.selection[0]]).found do
                .hintLine.addHint(strings().key_Enter, appStrings().hint_TypeWords)
            else do
                .hintLine.addHint(Input.formatKeyShortcut(.None, .Delete), appStrings().hint_Delete)
        }
        else
        {
            let tool = .toolHint()
            if not tool.isEmpty() do
                .hintLine.addHint("", tool)
        }

        if .inspector != null and .inspector.folded do
            .hintLine.addHint(.inspector.foldKey, appStrings().hint_AllProperties)
        if not selected do
            .hintLine.addHint(Input.formatKeyShortcut(.Control, .Space), appStrings().hint_Space)
    }

    // Returns what the tool in hand does, in a few words.
    mtd toolHint()->String
    {
        let texts = appStrings()
        switch #complete .editMode
        {
        case .Selection:
            return texts.hint_ToolSelect

        case .Shape:
            return texts.hint_ToolShape

        case .Arrow:
            return texts.hint_ToolArrow

        case .Line:
            return texts.hint_ToolLine

        case .Polygon:
            return texts.hint_ToolPolygon

        case .Text:
            return texts.hint_ToolText

        case .Callout:
            return texts.hint_ToolCallout

        case .Draw:
            return texts.hint_ToolDraw

        case .Highlight:
            return texts.hint_ToolHighlight

        case .Image:
            return texts.hint_ToolImage

        case .PixSel:
            return texts.hint_ToolPixSel

        case .Favorites:
            return texts.hint_ToolFavorites

        case .Step:
            let capture = .getCapture()
            return Format.toString(texts.hint_ToolStep, capture ? capture.nextStepIndex : 1)
        }
    }

    // Every command, recent capture and appearance choice has a route through the lens. At rest
    // capture and output keep their positions, followed by selection actions and recent captures.
    mtd createLens()
    {
        with .lens = Lens.View.create(me)
        {
            .addRestSource(func|main = me|(results) { main.describeLensContext(results) })
            .addRestSource(func|main = me|(results) { main.describeRecentCaptures(results) })
            .addSource(.None, func|main = me|(results) { main.describeRecentCaptures(results) })
            .addSource(.None, func|main = me|(results)
            {
                if main.libraryMode do
                    main.libWnd.describeLens(results)
            })
            .addCommand(func()->string => appStrings().ui_MenuCapture, ActionCapture.Area, func()->string => appStrings().search_Capture)
            .addCommand(func()->string => appStrings().ui_MenuCapture, ActionCapture.DoIt, inMenu: false)
            .addCommands(func()->string => appStrings().ui_MenuCapture, CaptureModeIds)
            for idx in me.monitors.count do
                .addCommand(func()->string => appStrings().ui_MenuCapture, ActionCapture.screenId(idx))
            .addCommand(func()->string => appStrings().ui_MenuCapture, ActionCapture.RecordVideo, menuSection: 1)
            .addCommand(func()->string => appStrings().ui_MenuCapture, ActionCapture.RecordScreen, menuSection: 1)
            .addCommand(func()->string => appStrings().ui_MenuCapture, ActionCapture.RecordActiveWindow, menuSection: 1)
            for idx in me.monitors.count do
                .addCommand(func()->string => appStrings().ui_MenuCapture, ActionCapture.recordScreenId(idx), menuSection: 1)
            .addCommand(func()->string => appStrings().ui_MenuCapture, ActionCapture.Record, menuSection: 2)
            .addCommands(func()->string => appStrings().ui_MenuCapture, CaptureDelayIds, menuGroup: func()->string => appStrings().act_DelayBefore)
            .addCommands(func()->string => appStrings().ui_MenuCapture, CaptureOptionIds, menuGroup: func()->string => appStrings().ui_MenuCaptureSetup)
            .addCommand(func()->string => appStrings().ui_MenuFile, ActionFile.SaveAsImage, func()->string => appStrings().search_Export)
            .addCommands(func()->string => appStrings().ui_MenuFile, FileStartIds)
            .addCommands(func()->string => appStrings().ui_MenuFile, FileLinkedIds, menuGroup: func()->string => appStrings().ui_MenuLinkedImage)
            .addCommands(func()->string => appStrings().ui_MenuFile, FileCaptureIds, menuGroup: func()->string => appStrings().ui_MenuCaptureFile)
            .addCommands(func()->string => appStrings().ui_MenuEdit, EditHistoryIds)
            .addCommands(func()->string => appStrings().ui_MenuEdit, EditClipboardIds, menuSection: 1)
            .addCommands(func()->string => appStrings().ui_MenuEdit, EditObjectIds, menuGroup: func()->string => appStrings().ui_MenuObject)
            .addCommands(func()->string => appStrings().ui_MenuEdit, EditorSelectionIds, menuGroup: func()->string => appStrings().lens_Selection)
            .addCommands(func()->string => appStrings().ui_MenuEdit, PixelSelectionIds, inMenu: false)
            .addCommands(func()->string => appStrings().ui_MenuAlign, AlignMenuIds, menuFamily: func()->string => appStrings().ui_MenuEdit, menuGroup: func()->string => appStrings().ui_MenuAlign)
            .addCommands(func()->string => appStrings().ui_MenuArrange, ArrangeMenuIds, menuFamily: func()->string => appStrings().ui_MenuEdit, menuGroup: func()->string => appStrings().ui_MenuArrange)
            .addCommand(func()->string => appStrings().ui_MenuImage, ActionCopyPaste.CopyAsImage)
            .addCommands(func()->string => appStrings().ui_MenuImage, ImageGeometryIds, menuSection: 1)
            .addCommands(func()->string => appStrings().ui_MenuImage, ImageFlattenIds, menuSection: 2)
            .addCommands(func()->string => appStrings().ui_MenuImage, ImageTransformIds, menuSection: 3)
            .addCommands(func()->string => appStrings().lens_Tools, ToolMenuIds, inMenu: false)
            .addCommands(func()->string => appStrings().ui_MenuView, ViewPanelIds)
            .addCommand(func()->string => appStrings().act_Library, ActionGlobal.ShowLibrary, func()->string => appStrings().search_Library, menuFamily: func()->string => appStrings().ui_MenuView)
            .addCommands(func()->string => appStrings().ui_MenuView, ViewZoomIds, menuSection: 1)
            .addCommands(func()->string => appStrings().lens_Recent, RecentSizeIds, inMenu: false)
            .addCommand(func()->string => appStrings().ui_MenuView, ActionView.Clip, inMenu: false)
            .addCommand(func()->string => strings().lens_Application, ActionOptions.Options)
            .addCommand(func()->string => strings().lens_Application, ActionGlobal.Minimize, inMenu: false)
            .addCommand(func()->string => strings().lens_Application, ActionGlobal.ShowHub, inMenu: false)
        }

        // The appearance button answers About in the lens, as in every application; the command
        // keeps its place in the command menu only.
        .appearanceButton.addToLens(.lens)
        with .lens
        {
            .addCommand(func()->string => strings().lens_Application, ActionAbout.About, menuSection: 2, inLens: false)
            .addCommand(func()->string => strings().lens_Application, ActionGlobal.Exit, menuSection: 3)
        }
    }

    // Keeps the capture and output actions in stable positions while a selection changes.
    mtd describeLensContext(results: *Lens.Results)
    {
        if .libraryMode
        {
            .libWnd.describeLensRest(results)
            return
        }

        let capture = results.addSection(appStrings().ui_MenuCapture)
        .lens.addCommandRows(capture, [ActionCapture.Area, ActionCapture.Record, ActionCapture.RecordVideo, ActionCapture.RecordScreen, ActionCapture.RecordActiveWindow, ActionCapture.LastArea, ActionFile.OpenImage, ActionGlobal.ShowLibrary])

        let edited = .getCapture()
        let mediaName = edited and edited.media == .Video ? appStrings().ui_MediaVideo :
                        edited and edited.media == .Animation ? appStrings().ui_MediaAnimation :
                        appStrings().ui_MenuImage
        let image = results.addSection(mediaName)
        .lens.addCommandRows(image, [ActionFile.SaveAsImage, ActionCopyPaste.CopyAsImage])

        // A recording offers playback and the time span of the selected forms.
        if edited and edited.isTimed()
        {
            let timeline = results.addSection(appStrings().lens_Timeline)
            .lens.addCommandRows(timeline, [ActionTimeline.Play, ActionTimeline.PrevFrame, ActionTimeline.NextFrame,
                                            ActionTimeline.ShowFrom, ActionTimeline.ShowUntil, ActionTimeline.ShowAlways,
                                            ActionTimeline.TrimStart, ActionTimeline.TrimEnd, ActionTimeline.KeepAll])
        }

        let selection = results.addSection(appStrings().lens_Selection)
        .lens.addCommandRows(selection,
                             [ActionEdit.EditText, ActionCopyPaste.Duplicate, ActionCopyPaste.Copy, ActionSelection.DeleteSelection,
                              ActionAlign.SendToFront, ActionAlign.SendToBack, ActionGroup.Group, ActionGroup.Ungroup, ActionEdit.ResetRotation],
                             enabledOnly: true)
    }

    // Answers the lens with the recent captures whose name matches the query, as a strip of
    // pictures closing the results, then the way to the library.
    mtd describeRecentCaptures(results: *Lens.Results)
    {
        if .recentWnd == null or .libraryMode do
            return

        let view = .recentWnd.recentView
        var section: *Lens.Section?
        for item, index in view.items
        {
            if section and section.pictures.count == MaxLensRecents do
                break
            let name = Path.fileName(item!.file) orelse ""
            if results.query.count and not Lens.match(results.query, name).matched do
                continue
            if not section do
                section = results.addSection(appStrings().lens_Recent)
            with let picture = section.addPicture(name)
            {
                .run   = func|main = me, index|() { main.openRecent(index) }
                .paint = func|item = unwrap item|(painter, rect) { paintLensRecent(painter, rect, item.preview) }
            }
        }

        if section do
            section.setLink(appStrings().lens_LibraryLink, func|main = me|() { main.postCommandEvent(ActionGlobal.ShowLibrary) })
    }

    // Opens the recent capture `index` in the editor, leaving the library if it is on screen.
    mtd openRecent(index: u64)
    {
        if .libraryMode do
            .swapLibraryMode()
        .recentWnd.recentView.requestSelect(index)
        .updateState()
    }

    // The strip of recent captures, shown on demand at the foot of the window. Its preview size
    // is a View choice in the strip and lens; its captures are also lens entries.
    mtd createRecentBar()
    {
        let gutter = .themeMetrics().panel_GutterSize
        let barRoom = .themeMetrics().scrollBar_HitSize + .themeMetrics().scrollBar_EdgeInset
        with .recentBar = Wnd.create'Wnd(me, {0, 0, 0, 136 + barRoom - 12})
        {
            .dockStyle       = .Bottom
            .backgroundStyle = .Panel
            .padding         = Math.Vector4{gutter, gutter, gutter, barRoom}
            .wndFlags.add(.Hidden)
        }

        with let sizes = StackLayoutCtrl.create(.recentBar, .Left)
        {
            .dockStyle = .Top
            .spacing   = .themeMetrics().tabItem_WordGap
        }

        .recentSmall  = IconButton.createQuiet(sizes, ActionRecentSize.RecentSmall, menu: false)
        .recentMedium = IconButton.createQuiet(sizes, ActionRecentSize.RecentMedium, menu: false)
        .recentBig    = IconButton.createQuiet(sizes, ActionRecentSize.RecentBig, menu: false)

        with .recentWnd = RecentWnd.create(me.recentBar, me)
        {
            .dockStyle = .Center
        }
    }

    // Shows or hides the strip of recent captures. Shown, it opens to its height as a panel
    // changing the layout does; hidden, the work takes the room back at once.
    mtd showRecentBar(show: bool)
    {
        .showRecent = show
        let visible = show and not .libraryMode
        if visible and not .recentBar.isLocallyVisible()
        {
            .recentBar.resize(.recentBar.position.width, 0)
            .recentBar.show()
            .applyLayout()
            discard .app().animator.animateLayoutHeight(.recentBar, .bottomHeight())
            return
        }

        .recentBar.show(visible)
        .applyLayout()
    }

    // The appearance owner of the application: the theme and the language it applies and
    // persists, and About. Its choices are lens entries, so its caption button stays hidden.
    mtd createAppearanceButton()
    {
        with .appearanceButton = AppearanceButton.create(unwrap .surface, "capture.appearance")
        {
            .hide()
            .sigThemeChanged += func|main = me|(button)
            {
                main.editorOptions.theme = button.appearanceTheme
                main.editWnd.getCapture()?.invalidateAllFormCaches()
                main.saveAppState()
            }

            .sigLanguageChanged += func|main = me|(button)
            {
                if button.language.isEmpty() do
                    main.editorOptions.language = .System
                elif button.language == "fr" do
                    main.editorOptions.language = .French
                else do
                    main.editorOptions.language = .English
                main.saveAppState()

                // The inspector title, the hint line and the commands of the strip are written
                // from the state of the editor: write them again in the new language now.
                main.updateState()
            }

            .sigAboutRequested += func|main = me|(_)
            {
                main.postCommandEvent(ActionAbout.About)
            }
        }
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
