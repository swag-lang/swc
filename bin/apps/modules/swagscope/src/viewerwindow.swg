using Core, Pixel, Gui

// One file's explicit viewer choice, retained only by this window for its current session.
struct ViewerFileChoice
{
    file:   String
    viewer: String
}

// One recently viewed folder and the last file that made it current.
struct ViewerFolderHistory
{
    folder: String
    file:   String
}

// The durable bookmark registry is a bounded least-recently-stored list.
internal const ViewerTextBookmarkFileLimit = 64'u64
internal const ViewerTextBookmarkLimit     = 64'u64

// The durable text bookmarks kept for one file identity.
internal struct ViewerTextBookmarkFile
{
    path:      String
    identity:  String
    bookmarks: Array'Viewers.PlainText.Bookmark
}

// Returns the application window that hosts `view`.
func viewerWindowFor(view: *Wnd)->*ViewerWindow => unwrap view.ancestorByType'ViewerWindow()

// Replaces a viewer that failed after creation with the standard error surface.
func reportViewerFailure(view: *Wnd, reason: string) { viewerWindowFor(view).replaceFailedViewer(view, reason) }

// The main window of Swag Scope: the document and nothing else on screen.
//
// Everything the window can do is an entry of its lens, which `Ctrl Space` opens; what
// it knows about the open file is in the sheet `I` opens. Viewers can contribute contextual
// controls and readings around their document, while search floats at the top when asked for and
// the lens lists the files beside the open one on demand.
struct ViewerWindow
{
    using wnd: Wnd

    late
    {
        searchBar:                   *FloatingPanel
        searchGroup:                 *Wnd
        searchNavigation:            *Wnd
        searchBox:                   *EditBox
        searchCountLabel:            *Label
        searchPrevious:              *IconButton
        searchNext:                  *IconButton
        searchCancelButton:          *IconButton
        searchCloseButton:           *IconButton
        searchOptionsButton:         *IconButton
        appearanceButton:            *AppearanceButton
        outlineCaptionButton:        *CaptionButton
        returnExplorerCaptionButton: *CaptionButton
        backCaptionButton:           *CaptionButton
        forwardCaptionButton:        *CaptionButton
        upCaptionButton:             *CaptionButton
        refreshCaptionButton:        *CaptionButton
        findCaptionButton:           *CaptionButton
        fullScreenCaptionButton:     *CaptionButton
        informationCaptionButton:    *CaptionButton
        viewerCaptionButton:         *CaptionButton
        lens:                        *Lens.View
        lensLauncher:                *Lens.Launcher
        information:                 *ViewerInformation
        infoSheet:                   *InfoSheet
        hintLine:                    *HintLine
        readingLine:                 *ViewerReadingLine
        documentHost:                *Wnd
        documentPanel:               *Wnd
        mainSplitter:                *SplitterCtrl
        outlinePanelPlaceholder:     *Wnd
        sidePanelPlaceholder:        *Wnd
        loadingOverlay:              *ViewerLoadingOverlay
        searchOverlay:               *ViewerSearchOverlay
        dropHighlight:               *FileDropHighlight
        viewerBar:                   *FloatingPanel
        cellCaption:                 *FloatingPanel
        cellCaptionTitle:            *Label
        cellCaptionClose:            *IconButton
        home:                        *ViewerHome
    }

    workspace:          *ViewerWorkspace?
    thumbnailMode:      bool
    explorerActive:     bool
    explorerTransition: bool     // Keep the folder visible until the file viewer can replace it.
    explorer:           *Explorer?

    index:                   ViewerPluginRegistry
    pluginIcons:             Array'ViewerPluginIcons
    currentView:             *Wnd?
    currentActions:          *Wnd?
    currentInfo:             *Wnd?
    currentCommands:         *Wnd?
    currentSidePanelHost:    *Wnd?
    currentSidePanelButton:  *IconButton?
    outgoingView:            *Wnd?
    outgoingActions:         *Wnd?
    outgoingInfo:            *Wnd?
    outgoingCommands:        *Wnd?
    outgoingSidePanelHost:   *Wnd?
    outgoingSidePanelButton: *IconButton?
    choices:                 Array'ViewerPluginChoice
    instances:               Array'ViewerSession
    activeChoiceIndex:       u32  = Swag.U32.Max
    startupTimer:            *Timer?
    awaitingRetirement:      bool     // A viewer is still retiring; the next task event below the window asks it again.
    searchTimer:             *Timer?
    searchBoundsTimer:       *Timer?
    loadingTimer:            *Timer?
    loadingWantedSince:      u64     // Monotonic microseconds at which the current wait began asking for the mark; zero outside a wait.
    loadingShownSince:       u64     // Monotonic microseconds at which the mark was shown; zero while it is hidden.
    choiceLoad:              ViewerChoiceLoad
    smokeTimer:              *Timer?
    searchStream:            File.FileStream
    searchQuery:             String
    searchToolTip:           String
    searchError:             String
    searchCarry:             String
    searchCarryBase:         u64
    searchByteRange:         Viewer.SearchByteRange
    searchBytesRead:         u64
    searchProcessed:         u64
    searchProgress:          u64
    searchTotalBytes:        u64
    searchSpan:              u64
    searchMatches:           Array'Viewer.SearchMatch
    searchIndex:             u64  = Swag.U64.Max
    searchMatch:             u64  = Swag.U64.Max
    searchComplete:          bool
    searchSelectLast:        bool
    searchKeepPosition:      bool
    searchMatchesCapped:     bool
    searchCancelled:         bool
    searchMatchCaseOption:   bool
    searchWholeWordOption:   bool
    searchRegexOption:       bool
    searchFilterMode:        bool
    pendingFile:             String
    pendingEmpty:            String
    pendingRemember:         bool = true
    pendingForgetMissing:    bool
    fileWatch:               ViewerFileWatch
    privacy:                 ViewerPrivacy
    historyCleanup:          ViewerHistoryCleanup
    privacyTimer:            *Timer?
    fileWatchTimer:          *Timer?
    readingState:            ViewerReadingState
    reloading:               bool
    currentFile:             String
    currentFileSize:         String
    folderFiles:             Array'String
    siblings:                Array'String
    siblingIndex:            u64
    siblingsDirty:           bool = true

    // Whether next/previous keep only the neighbours the current file's
    // viewer would open, so a reader flips through the pictures of a folder without landing on
    // the notes stored beside them.
    folderSameKind: bool

    // The play mode and what it needs: the slideshow pace, the timer counting it down, the view
    // that reported a still picture for it to count, and the files already read in the current
    // folder round. The same round state drives shuffle choice.
    playMode:            Viewer.PlayMode
    sceneAutoPlay:       bool
    sceneSlidesPaused:   bool
    slideSeconds:        f32 = Viewer.SlideDefaultSeconds
    slideTimer:          *Timer?
    stillView:           *Wnd?
    folderReadingMode:   Viewer.PlayMode
    folderReadingFolder: String
    folderReadingFiles:  Array'String

    // Guards the one nested dispatch [[ViewerWindow.forwardKeyToViewer]] makes, so a key the viewer
    // declines falls back to file navigation instead of being offered again.
    forwardingViewerKey:       bool
    playPauseKeyDown:          bool
    recent:                    Array'String
    recentOpened:              Array'u64     // Local ticks each entry of `recent` was last opened at, in the same order; zero when unknown.
    folderHistory:             Array'ViewerFolderHistory
    internal
    {
        textBookmarkFiles: Array'ViewerTextBookmarkFile
        textTabWidth:       s32 = 4
        codeTabWidth:       s32 = 4
    }
    resumePoints:              Array'ViewerResumePoint     // Where the files of the history were left, most recent first.
    exploredFolders:           Array'String     // Directories explored lately, most recent first.
    folderViews:               Array'ExplorerFolderState
    systemPlaces:              Array'String     // The system's own folders a first launch offers to explore.
    fileViewerChoices:         Array'ViewerFileChoice
    musicChoices:              Array'MusicChoice
    onlineMovies:              bool = true
    onlineMusic:               bool = true
    leftPanelWidth:            f32
    rightPanelWidth:           f32
    fileDlgState:              FileDlgState
    themeIndex:                u32  = cast(u32, AppearanceTheme.Document)
    language:                  String
    updatingReadingAppearance: bool

    // A monitor-sized presentation is transient: what the window was before entering it is what
    // leaving it restores, placement, maximized state, and surface flags alike.
    fullScreen: bool
    fullScreenWasMaximized:    bool
    fullScreenRestorePosition: Math.Rectangle
    fullScreenRestoreFlags:    SurfaceFlags

    // The viewer's commands float over the foot of the document while the pointer moves, and
    // leave once it rests; the search floats at the top while it is asked for.
    viewerBarShown:  bool
    lensBytes:       Array'u8      // The open file as the lens searches it, read on its first question.
    lensBytesFile:   String        // The file `lensBytes` holds.
    lensLineStarts:  Array'u64     // Offset in `lensBytes` of the start of each line.
    viewerBarTimer:  *Timer?
    pointerPosition: Math.Point
    searchShown:     bool
    smokeDirectory:  String
    smokeSpecIndex:  u64
    smokeWaitSteps:  u32
    smokeOpened:     bool
    smokeSelected:   bool
    smokeRunning:    bool
}

// Records the format summary a viewer reported after creation, and shows it while that viewer is active.
func reportViewerDetails(view: *Wnd, details: string)
{
    let window = viewerWindowFor(view)
    for &instance, index in window.instances where instance.view == view
    {
        // Pointer probes and timers repeat a summary that has not moved. The line already shows
        // it, and laying the line out or describing an open sheet again would only cost a frame.
        if instance.details == details do
            return
        instance.details = details
        if index == window.activeChoiceIndex do
            window.updateFileInfo(details)
        return
    }
}

// Describes the open information sheet again when the viewer whose contribution changed is the
// one it describes.
func reportViewerInformationChanged(view: *Wnd)
{
    let window = viewerWindowFor(view)
    window.workspace?.comparisonSheet?.refresh()
    if window.activeChoiceIndex >= window.instances.count or window.instances[window.activeChoiceIndex].view != view do
        return
    if view is Markdown.View do
        window.layoutFileInfo()
    else do
        window.refreshReadingAppearance()
    if window.infoSheet.isLocallyVisible() do
        window.refreshInformation()
}

// Re-measures viewer-owned chrome after a compact value or action group changes shape.
func reportViewerChromeChanged(view: *Wnd)
{
    let window = viewerWindowFor(view)
    if window.currentView != view do
        return
    if view is Viewers.Film.Panel as film
    {
        if film.veilsShown do
            window.revealViewerBar()
        return
    }

    window.layoutViewerBar()
    window.layoutFileInfo()
    window.refreshExplorerCaption()
    window.applyLayout()
}

// Opens a neighboring file for the viewer that chose to own directional navigation.
func navigateViewerFile(view: *Wnd, delta: s32)
{
    viewerWindowFor(view).navigate(delta, imagesOnly: true)
}

// Answers a viewer that has finished presenting its file with what the play mode calls for.
func reportViewerFinished(view: *Wnd)->Viewer.Continuation => viewerWindowFor(view).continueAfter(view)

// Starts the slideshow pace for a viewer showing content with no end of its own.
func reportViewerShown(view: *Wnd)
{
    viewerWindowFor(view).showStill(view)
}

// Reads the shared playback policy without creating viewer chrome.
func readViewerPlayback(view: *Wnd)->Viewer.PlaybackSettings
{
    let window = viewerWindowFor(view)
    return Viewer.PlaybackSettings{window.playMode, window.slideSeconds}
}

// Applies playback preferences chosen by a viewer-owned control.
func writeViewerPlayback(view: *Wnd, settings: Viewer.PlaybackSettings)
{
    let window = viewerWindowFor(view)
    window.setPlayMode(settings.mode)
    if window.slideSeconds != settings.slideSeconds do
        window.setSlideSeconds(settings.slideSeconds)
}

// Lets a viewer wake the generic wait presentation when work starts again after being idle.
func reportViewerLoadingChanged(view: *Wnd)
{
    with let window = viewerWindowFor(view)
    {
        .commitViewerTransition(view)
        .updateLoadingIndicator()
        .workspace?.refreshComparison()
        let comparisonSheet = .workspace?.comparisonSheet
        if comparisonSheet and comparisonSheet.panel.isLocallyVisible() do
            comparisonSheet.refresh()
        .workspace?.updateMediaViewport(window)
        if .currentView == view
        {
            if .sceneSlidesPaused and view is Viewers.Picture.Panel do
                .setPicturePlaying(false)
            .workspace?.updateMedia()
            .finishReadingRestore()
        }
    }
}

// Returns the services a viewer of the main window reaches its host through.
func viewerHostServices()->Viewer.HostServices
{
    with var result: #returntype
    {
        .reportFailure            = &reportViewerFailure
        .reportDetails            = &reportViewerDetails
        .reportInformationChanged = &reportViewerInformationChanged
        .reportChromeChanged      = &reportViewerChromeChanged
        .reportLoadingChanged     = &reportViewerLoadingChanged
        .navigateFile             = &navigateViewerFile
        .reportFinished           = &reportViewerFinished
        .reportShown              = &reportViewerShown
        .playback.readSettings    = &readViewerPlayback
        .playback.writeSettings   = &writeViewerPlayback
    }

    return result
}

impl IWnd for ViewerWindow
{
    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if evt.kind == .Move or evt.kind == .Enter do
            .notePointer(evt.surfacePos)
        evt.accepted = false
    }

    // The document keeps clear of the window chrome floating over the top of the window, and the
    // floating parts follow the document.
    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        // The window is resized while it is being built, before the parts below exist.
        if .lens == null do
            return
        ViewerWindow.fitDocumentPanes(.mainSplitter, .clientRect().width)
        .updateDocumentInsets()
        .layoutFloatingParts()
    }

    mtd impl onDragDropEvent(evt: *DragDropEvent)
    {
        if .workspace
        {
            evt.accepted = false
            return
        }

        if evt.kind == .Leave
        {
            .dropHighlight.hide()
            evt.accepted = true
            return
        }

        let fileName = evt.data.singleFile()
        if not fileName
        {
            .dropHighlight.hide()
            evt.accepted = false
            return
        }

        .dropHighlight.showTarget(not .home.isLocallyVisible())

        // The system holds the whole drag — the source window's own loop included — until this
        // returns, so a drop only records the file. Reading a header, building a viewer and
        // decoding a first picture happen on the next turn of the event loop, by which time the
        // drag is over and both windows can paint again.
        if evt.kind == .Drop
        {
            .dropHighlight.hide()
            .queueFile(fileName)
        }

        evt.effect = pickDropEffect(evt.allowed & (DropEffect.Copy | DropEffect.Link), evt.modifiers)
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if .routePlaybackKey(evt) do
            return
        if evt.kind != .Pressed
        {
            evt.accepted = false
            return
        }

        // An editor inserts letters on the character event. Its preceding key-down must not run a viewer shortcut.
        if .focusedWindow() is EditBox and (evt.modifiers == .None or evt.modifiers == .Shift)
        {
            switch evt.key
            {
            case .A, .B, .C, .D, .E, .F, .G, .H, .I, .J, .K, .L, .M,
                 .N, .O, .P, .Q, .R, .S, .T, .U, .V, .W, .X, .Y, .Z:
                evt.accepted = true
                return
            default: break
            }
        }

        // Commands use registered shortcuts, after the focused control has had the key.
        let plain = evt.modifiers == .None
        switch evt.key
        {
        case .Left, .Right where plain: evt.accepted = not .forwardingViewerKey and .forwardKeyToViewer(evt)
        default: evt.accepted = false
        }
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer == .privacyTimer
        {
            discard .privacy.refresh()
            .privacy.refreshIndicator()
            if .privacy.dirty
            {
                .refreshHome()
                catch .saveState()
            }

            .privacy.clearCaches()
            return
        }

        if evt.timer == .fileWatchTimer
        {
            if not .pendingFile.isEmpty() or .currentFile.isEmpty() do
                return
            if .readingState.restoring
            {
                .finishReadingRestore()
                return
            }

            if .fileWatch.poll(.currentFile) do
                .reloadCurrentFile()
            return
        }

        if evt.timer == .smokeTimer
        {
            .reviewSmokeStep()
            return
        }

        if evt.timer == .loadingTimer
        {
            .stopTimer(&.loadingTimer)
            .updateLoadingIndicator()
            return
        }

        if evt.timer == .searchTimer
        {
            .stopTimer(&.searchTimer)
            .searchStep()
            return
        }

        if evt.timer == .searchBoundsTimer
        {
            .stopTimer(&.searchBoundsTimer)
            .refreshSearchHighlight()
            return
        }

        if evt.timer == .slideTimer
        {
            .stopTimer(&.slideTimer)
            .continueSlide()
            return
        }

        if evt.timer == .viewerBarTimer
        {
            .concealViewerBar()
            return
        }

        if evt.timer != .startupTimer
        {
            evt.accepted = false
            return
        }

        .continueStartup()
    }

    // The classification of a queued file ended.
    mtd impl onTaskEvent(evt: *TaskEvent)
    {
        if .privacy.scan.claim(evt)
        {
            .privacy.finishScan()
            .refreshHome()
            return
        }

        if .historyCleanup.claim(evt)
        {
            .historyCleanup.finish(me)
            return
        }

        if not .choiceLoad.claim(evt)
        {
            evt.accepted = false
            return
        }

        .continueStartup()
    }

    mtd impl onDestroyEvent(_: *DestroyEvent)
    {
        .showPointer()
        if .fullScreen and .isWorkspacePrimary() do
            .setFullScreen(false)
        if .isWorkspacePrimary() do
            catch .saveState()
        .stopSearch()
        .stopLoadingIndicator()
        .stopSlide()
        .stopTimer(&.privacyTimer)
        .privacy.flush()
        .historyCleanup.task.cancel()
        .historyCleanup.wait()
        .privacy.destroyIndicator()
        .stopTimer(&.fileWatchTimer)
        .stopTimer(&.viewerBarTimer)

        for &set in .pluginIcons do
            set.icons.free()
        .stopTimer(&.startupTimer)
    }

    mtd impl onStateEvent(evt: *StateEvent)
    {
        if evt.kind != .Init
        {
            evt.accepted = false
            return
        }

        if .thumbnailMode or not .isWorkspacePrimary() do
            return
        catch .app().loadState()
        .applyTheme(.themeIndex)
        .applyLanguage()
        .surface?.constrainPositionToScreen(topLeft: true, margin: 10)
        .refreshHome()
        evt.accepted = true
    }

    mtd impl onSerializeStateEvent(evt: *SerializeStateEvent)
    {
        if not .isWorkspacePrimary() do
            return
        .workspace?.serializeScenes(evt.serializer)

        if not evt.serializer.isReading() and .currentSidePanelHost
        {
            let splitter = assume cast(*SplitterCtrl, .currentSidePanelHost.parent)
            for index in splitter.items.count
            {
                let item = unwrap splitter.items[index]
                if item.view == .currentSidePanelHost
                {
                    let width = item.size - .themeMetrics().floating_Inset
                    if .currentSidePanelButton?.id == OutlineToggleId do
                        .leftPanelWidth = width
                    else do
                        .rightPanelWidth = width
                }
            }
        }

        if not evt.serializer.isReading()
        {
            .rememberTextBookmarkSessions()
            .textTabWidth = Viewers.PlainText.defaultTabWidth()
            .codeTabWidth = Viewers.Code.defaultTabWidth()
            .explorer?.rememberView()
            .privacy.sanitize()
            .captureResume()
        }

        .privacy.serializeState(evt.serializer)
        catch evt.serializer.serialize("ViewerWindow.textTabWidth", &me.textTabWidth)
        catch evt.serializer.serialize("ViewerWindow.codeTabWidth", &me.codeTabWidth)
        catch evt.serializer.serialize("ViewerWindow.themeIndex", &me.themeIndex)
        catch evt.serializer.serialize("ViewerWindow.language", &me.language)
        catch evt.serializer.serialize("ViewerWindow.onlineMovies", &me.onlineMovies)
        catch evt.serializer.serialize("ViewerWindow.onlineMusic", &me.onlineMusic)
        catch evt.serializer.serialize("ViewerWindow.leftPanelWidth", &me.leftPanelWidth)
        catch evt.serializer.serialize("ViewerWindow.rightPanelWidth", &me.rightPanelWidth)
        catch evt.serializer.serialize("ViewerWindow.folderSameKind", &me.folderSameKind)
        catch evt.serializer.serialize("ViewerWindow.playMode", &me.playMode)
        catch evt.serializer.serialize("ViewerWindow.slideSeconds", &me.slideSeconds)
        catch evt.serializer.serialize("ViewerWindow.searchMatchCase", &me.searchMatchCaseOption)
        catch evt.serializer.serialize("ViewerWindow.searchWholeWord", &me.searchWholeWordOption)
        catch evt.serializer.serialize("ViewerWindow.searchRegularExpression", &me.searchRegexOption)
        catch evt.serializer.serialize("ViewerWindow.videoSubtitles", &Viewers.Film.g_SubtitleSettings)
        catch evt.serializer.serialize("ViewerWindow.videoHintUses", &Viewers.Film.g_PlaybackHintUses)
        catch evt.serializer.serialize("ViewerWindow.movieDetection", &Viewers.Film.g_MovieDetectionSettings)
        catch evt.serializer.serialize("ViewerWindow.markdown", &Viewers.MarkdownText.g_ViewerSettings)
        catch evt.serializer.serialize("ViewerWindow.midi", &Viewers.Midi.g_ViewerSettings)
        if evt.serializer.isReading()
        {
            Viewers.Film.g_MovieDetectionSettings.sanitize()
            if .textTabWidth != 2 and .textTabWidth != 4 and .textTabWidth != 8 do
                .textTabWidth = 4
            if .codeTabWidth != 2 and .codeTabWidth != 4 and .codeTabWidth != 8 do
                .codeTabWidth = 4
            Viewers.PlainText.setDefaultTabWidth(.textTabWidth)
            Viewers.Code.setDefaultTabWidth(.codeTabWidth)
            .themeIndex = Math.min(.themeIndex, cast(u32, AppearanceTheme.Document))
            if .rightPanelWidth > 0 do
                .rightPanelWidth = Math.clamp(.rightPanelWidth, RightPanelMinWidth, RightPanelMaxWidth)
            if .leftPanelWidth > 0 do
                .leftPanelWidth = Math.clamp(.leftPanelWidth, RightPanelMinWidth, RightPanelMaxWidth)
            if .mainSplitter.items.count > 2
            {
                if .rightPanelWidth > 0
                {
                    let rightWidth = .rightPanelWidth + .themeMetrics().floating_Inset
                    if .mainSplitter.items[2]!.view.isLocallyVisible()
                        do
                        .mainSplitter.setPaneSize(2, rightWidth)
                    else do
                        .mainSplitter.items[2]!.size = rightWidth
                }

                if .leftPanelWidth > 0
                {
                    let leftWidth = .leftPanelWidth + .themeMetrics().floating_Inset
                    if .mainSplitter.items[0]!.view.isLocallyVisible()
                        do
                        .mainSplitter.setPaneSize(0, leftWidth)
                    else do
                        .mainSplitter.items[0]!.size = leftWidth
                }

                .mainSplitter.sendResizeEvent()
            }

            while .recent.count > RecentCount do
                .recent.removeAtOrdered(.recent.count - 1)
            .recentOpened.resize(.recent.count)
            .privacy.sanitize()
            .pruneResume()
            while .exploredFolders.count > FolderHistoryCount do
                .exploredFolders.removeBack()
            while .folderHistory.count > FolderHistoryCount do
                .folderHistory.removeAtOrdered(.folderHistory.count - 1)
            discard .searchBox.revalidate()
            if cast(u32, .playMode) > cast(u32, Viewer.PlayMode.Shuffle) do
                .playMode = .Once
            .slideSeconds = Math.clamp(.slideSeconds, Viewer.SlideMinSeconds, Viewer.SlideMaxSeconds)
            Viewers.MarkdownText.g_ViewerSettings.sanitize()
            Viewers.Midi.g_ViewerSettings.sanitize()
        }
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        switch evt.kind
        {
        case .LanguageChanged:
            .retranslate()
            .dropHighlight.setPrompt(appStrings().ui_DropTitle)

        case .ThemeChanged:
            for &instance in .instances where instance.view and not instance.failureReason.isEmpty() do
                assume cast(*ViewerErrorView, instance.view).refreshTheme()
            .refreshArtwork()
            .refreshHome()
            .dropHighlight.refreshTheme()
            .layoutFloatingParts()

        case .ChildFocusChanged, .PressedElsewhere, .KeyboardLayoutChanged, .ShortcutsChanged:
            break
        }

        .wnd.IWnd.onNotifyEvent(evt)
    }

    mtd impl onComputeStateEvent(evt: *CommandStateEvent)
    {
        if not .computeCommandState(evt) do
            evt.accepted = false
    }

    mtd impl onCommandEvent(evt: *CommandEvent)
    {
        evt.accepted = .runCommand(evt.id)
    }
}

impl ViewerWindow
{
    // The floating bar of the viewer's commands, the band an embedded viewer keeps its title in,
    // and the narrowest window.
    const BarHeight = 44.0
    const MinWidth  = 880

    // Room the hint line needs under the rows of a listing it teaches.
    const HintRoom = 72.0

    // How long the viewer's commands stay after the pointer last moved.
    const ViewerBarLinger: Time.Duration = 2500'ms

    // The document and its viewer-specific side panel.
    const DocumentMinWidth       = 320.0
    const LeftPanelIndex         = 0
    const DocumentPanelIndex     = 1
    const RightPanelIndex        = 2
    const RightPanelMinWidth     = 220.0
    const RightPanelMaxWidth     = 600.0
    const RightPanelDefaultWidth = 368.0

    // Files the recent list keeps. Long enough to cross a working session, short enough that the
    // list stays something a reader scans rather than searches.
    const RecentCount        = 12'u64
    const FolderHistoryCount = 8'u64

    // The search group of the floating find bar.
    const SearchFieldWidth          = 180.0
    const SearchNoOptionsFieldWidth = 256.0
    const SearchCountWidth          = 52.0
    const SearchGroupSpacing        = 8.0

    // Search reads the file one chunk at a time. A match that may continue into the next chunk
    // waits for it, so each chunk keeps the query span plus this margin of the one before.
    const SearchChunkSize   = 256 * 1024'u64
    const SearchCarryMargin = 4'u64
    const SearchMatchLimit  = 100_000'u64

    // How often the current match follows a moving or progressively loaded view.
    const SearchBoundsPoll: Time.Duration = 16'ms

    // How long a viewer may keep the window waiting before the activity mark appears, how long the
    // mark then stays once it has, and how often the wait is looked at.
    //
    // A file that arrives inside the delay was never a wait, and the document before it stays on
    // screen for that long anyway: showing the mark would only announce a pause nobody felt. A mark
    // that appears and leaves within one frame is a flicker over the document, so once shown it
    // lingers past the end of the wait. Both thresholds are what keep a fast file change reading as
    // instantaneous.
    const LoadingShowDelayMicroseconds       = 400_000'u64
    const LoadingMinVisibleMicroseconds      = 500_000'u64
    const LoadingPollInterval: Time.Duration = 50'ms

    // In full screen the surface loses its frame and stays above other windows.
    const FullScreenRemovedFlags = SurfaceFlags.LargeCaption |
                                   SurfaceFlags.SmallCaption |
                                   SurfaceFlags.MinimizeButton |
                                   SurfaceFlags.MaximizeButton |
                                   SurfaceFlags.CloseButton |
                                   SurfaceFlags.Border |
                                   SurfaceFlags.Resizable
    const FullScreenAddedFlags = SurfaceFlags.NoShadow | SurfaceFlags.TopMost

    // The smoke review gives a viewer at most `SmokeStepLimit` readiness checks, keeps every viewer
    // on screen for `SmokeMinimumSteps`, and one that is still loading for `SmokeExposureSteps`.
    const SmokeStepLimit     = 300'u32
    const SmokeExposureSteps = 25'u32
    const SmokeMinimumSteps  = 2'u32

    // Rasterizes one glyph of a plugin-owned vector document through this window's renderer.
    //
    // A plugin names the document it embeds and the cell it wants; the frame textures belong to
    // the host, which keeps one set per document and releases them with the window.
    mtd pluginIcon(plugin: const *Viewer.Plugin, size = 0.0)->Icon
    {
        if not plugin.iconAtlas do
            return {}
        let resolvedSize = size ? size : themeRowIconSize(.themeMetrics())
        for &set in .pluginIcons where set.atlas == plugin.iconAtlas do
            return set.icons.icon(plugin.iconIndex, resolvedSize, .theme().res.atlasScale)

        let added = .pluginIcons.emplaceInitAddress()
        added.atlas = plugin.iconAtlas
        added.icons.setup(.app().renderer, plugin.iconAtlas)
        return added.icons.icon(plugin.iconIndex, resolvedSize, .theme().res.atlasScale)
    }

    // Resolves one descriptor-owned glyph without leaking plugin metadata into the window.
    private mtd choiceIcon(index: u32, size = 0.0)->Icon
    {
        if index >= .choices.count do
            return {}
        let choice = &.choices[index]
        if choice.pluginIndex >= .index.plugins.count do
            return {}
        return .pluginIcon(&.index.plugins[choice.pluginIndex], size)
    }

    mtd applyTheme(index: u32)
    {
        .themeIndex = Math.min(index, cast(u32, AppearanceTheme.Document))
        let theme = .themeIndex == cast(u32, AppearanceTheme.Document) ? AppearanceTheme.Document : AppearanceThemeValues[.themeIndex]
        .appearanceButton.setAppearanceTheme(theme)
        .layoutFileInfo()
    }

    mtd applyLanguage()
    {
        discard catch .appearanceButton.setAppearanceLanguage(.language)
    }

    // Keeps the few decorative glyphs aligned with the active palette and document kind.
    mtd refreshArtwork()
    {
        .outlineCaptionButton.button.setIcon(.theme().icon(.Outline, .themeMetrics().wnd_CaptionButtonGlyph))
        .returnExplorerCaptionButton.button.setIcon(.theme().icon(.ChevronLeft, .themeMetrics().wnd_CaptionButtonGlyph))
        .searchPrevious.setIcon(.theme().icon(.SearchPrevious, themeActionIconSize(.themeMetrics())))
        .searchNext.setIcon(.theme().icon(.SearchNext, themeActionIconSize(.themeMetrics())))
        .searchCancelButton.setIcon(.theme().icon(.Stop, themeActionIconSize(.themeMetrics())))
        .refreshSearchPresentation()
        .refreshExplorerCaption()
    }

    mtd refreshOutlineCaption()
    {
        if not .isWorkspaceActive() do
            return
        let toggle = .currentSidePanelButton
        .outlineCaptionButton.show(not .fullScreen and toggle and toggle.id == OutlineToggleId)
        .outlineCaptionButton.toolTip = Format.toString("% (%)", .captionFileAction(outlineTitle()), Input.formatKeyShortcut(Input.KeyModifiers.Control | .Shift, .O))
        .updateOutlineCaptionState()
    }

    private mtd captionFileAction(action: string)->String
    {
        if (.workspace?.documentCount() orelse 0) > 1 and not .currentFile.isEmpty() do
            return Format.toString("% · %", action, Path.fileName(.currentFile) orelse .currentFile)
        return action
    }

    mtd updateOutlineCaptionState()
    {
        if not .isWorkspaceActive() do
            return
        let toggle = .currentSidePanelButton
        .outlineCaptionButton.setChecked(toggle and toggle.id == OutlineToggleId and toggle.isChecked)
    }

    mtd refreshExplorerCaption()
    {
        if not .isWorkspaceActive() do
            return
        .privacy.refreshIndicator()
        .refreshOutlineCaption()
        let text = appStrings()
        .returnExplorerCaptionButton.toolTip = text.cmd_ReturnToExplorer
        .returnExplorerCaptionButton.show(.canReturnToExplorer() and not .fullScreen)

        .explorer?.address.show(.isExploring())
        .surface?.wnd.showTitle(.showsCaptionTitle())
        let exploring = .isExploring() and not .fullScreen
        .backCaptionButton.show(exploring)
        .forwardCaptionButton.show(exploring)
        .upCaptionButton.show(exploring)
        .refreshCaptionButton.show(exploring)
        .findCaptionButton.hide()
        .fullScreenCaptionButton.show(not .fullScreen)
        .informationCaptionButton.show((.isExploring() or not .currentFile.isEmpty()) and not .fullScreen)
        let archiveFile = exploring and .explorer and .explorer.listing.isArchive
        let openFile    = not .isExploring() and not .currentFile.isEmpty()
        .viewerCaptionButton.show((openFile or archiveFile) and not .fullScreen)
        var alternateViewer = openFile and .activeChoiceIndex < .choices.count and .activeChoiceIndex != 0
        if archiveFile
        {
            let choices = .index.choices((unwrap .explorer).listing.path)
            alternateViewer = not choices.isEmpty() and choices[0].key != "archive"
        }

        .viewerCaptionButton.setIconColor(alternateViewer ? .themeColors().signature : Color{})
        .backCaptionButton.toolTip        = text.explore_Back
        .forwardCaptionButton.toolTip     = text.explore_Forward
        .upCaptionButton.toolTip          = text.explore_Up
        .refreshCaptionButton.toolTip     = text.explore_Refresh
        .findCaptionButton.toolTip        = text.ui_FilterFiles
        .fullScreenCaptionButton.toolTip  = Format.toString("% (%)", text.cmd_FullScreen, Input.formatKeyShortcut(.None, .F11))
        .informationCaptionButton.toolTip = (.workspace?.wantsComparisonSheet() orelse false) ?
                                             String.from(text.scene_ComparisonSheet) : .captionFileAction(text.cmd_Information)
        .viewerCaptionButton.toolTip      = .captionFileAction(text.lens_ViewAs)
        .fullScreenCaptionButton.setChecked(.fullScreen)
        .informationCaptionButton.setChecked(.informationOpen())
        if .workspace and .workspace.tabs != null
        {
            .workspace.refreshCloseFileButton()
            .workspace.tabs.layoutTabs()
        }
        if not .explorer do
            return

        .backCaptionButton.enable(.explorer.history.canGoBack())
        .forwardCaptionButton.enable(.explorer.history.canGoForward())
        .upCaptionButton.enable(.explorer.canGoUp())
    }

    // Lays the home out again for the history, the theme or the language in force.
    private mtd refreshHome()
    {
        if .home.isVisible() do
            .home.refresh()
    }

    // Saves the regular placement even during full screen. Privacy changes must reach disk
    // immediately without changing the presentation the reader currently sees.
    mtd saveState() fail
    {
        if .thumbnailMode do
            return
        if not .isWorkspacePrimary()
        {
            try .workspace!.primary.saveState()
            return
        }
        let surface           = unwrap .surface
        let presentation      = surface.state
        let presentationFlags = surface.flags
        defer if .fullScreen
        {
            surface.state = presentation
            surface.flags = presentationFlags
        }

        if .fullScreen
        {
            surface.flags            = .fullScreenRestoreFlags
            surface.position         = .fullScreenRestorePosition
            surface.restoredPosition = .fullScreenRestorePosition
            surface.isMaximized      = .fullScreenWasMaximized
        }

        try .app().saveState()
        .privacy.dirty = false
    }

    // Puts the commands of the active viewer in the floating bar, or empties it.
    mtd updateViewerBar()
    {
        if .usesTimedViewerBar()
        {
            .stopTimer(&.viewerBarTimer)
            .viewerBarShown = false
            if .isWorkspaceActive() and not .thumbnailMode
            {
                .revealViewerBar()
                return
            }
        }

        if not .currentCommands do
            .viewerBarShown = false
        .layoutViewerBar()
    }

    mtd overlaysViewerBar()->bool => .fullScreen or .usesTimedViewerBar()

    mtd usesTimedViewerBar()->bool
    {
        if .currentView is Viewers.Film.Panel do
            return true
        return (.workspace?.usesCellCaptions() orelse false) and
               (.currentView is Viewers.Sound.Panel or .currentView is Viewers.Picture.Panel)
    }

    // The explorer remains the place to return to while a file opened from it is being read.
    mtd canReturnToExplorer()->bool => .explorerActive and
                                       .explorer != null and
                                       not .currentFile.isEmpty() and
                                       not .explorer.isLocallyVisible()

    // Shows the viewer's commands for as long as the pointer keeps moving.
    mtd revealViewerBar()
    {
        if not .currentCommands do
            return
        .showPointer()
        .viewerBarShown = true
        .layoutViewerBar()
        .stopTimer(&.viewerBarTimer)
        .viewerBarTimer = .addTimer(ViewerBarLinger)
    }

    // Lets the viewer's commands go when the pointer, keyboard and modal controls have left.
    mtd concealViewerBar()
    {
        .stopTimer(&.viewerBarTimer)
        let focused = .focusedWindow()
        let timed    = .usesTimedViewerBar()
        let hovering = not timed and .viewerBar.surfaceRect().contains(.pointerPosition)
        let keyboard = (not timed or .app().focusVisible) and .viewerBar.isAncestorOf(focused)
        let captured = .mouseCapture()
        let held    = hovering or keyboard or .viewerBar.isAncestorOf(captured) or
                      .cellCaption.isAncestorOf(captured) or
                      .app().isInModalLoop() or
                      .lens.isOpen()
        if held and .viewerBarShown and .isVisible()
        {
            .viewerBarTimer = .addTimer(ViewerBarLinger)
            return
        }

        .viewerBarShown = false
        .layoutViewerBar()
        if .currentView is Viewers.Film.Panel as film do
            film.hideVeils()
        if .fullScreen and ((.workspace?.documentCount() orelse 0) <= 1 or .workspace!.isHoveredDocument(me)) do
            .setPointerHidden(true)
    }

    // Remembers where the pointer is, and brings the viewer's commands back.
    mtd notePointer(position: Math.Point, moved = false)
    {
        if not moved and position == .pointerPosition do
            return
        .pointerPosition = position
        .showPointer()
        .revealViewerBar()
    }

    // Hides the system pointer with the resting viewer chrome, then restores it on activity.
    mtd setPointerHidden(hidden: bool)
    {
        .app().setCursorHidden(hidden)
    }

    mtd showPointer()
    {
        .app().setCursorHidden(false)
    }

    // Places the floating bar of the viewer's commands at the foot of the document, as wide as
    // the commands ask and never wider than the document.
    mtd layoutViewerBar()
    {
        let commands = .currentCommands
        let compact  = .compactVideoCell()
        let media    = .currentView is Viewers.Film.Panel or .currentView is Viewers.Sound.Panel or .currentView is Viewers.Picture.Panel
        let visible  = commands != null and (not .overlaysViewerBar() or .viewerBarShown)
        .showViewerOverlay(.viewerBar, visible, animate: media and commands != null)
        .layoutCellCaption()
        defer
        {
            if .isWorkspaceActive() do
                .workspace?.layoutMaximizedHint()
        }
        if not commands do
            return

        let metrics = .themeMetrics()
        let area    = .documentArea()
        let inset   = compact ? metrics.miniBar_Distance : metrics.floating_Inset
        let pad     = .viewerBar.padding
        let room    = Math.max(area.width - 2 * inset - pad.x - pad.z, 0)
        let wanted  = commands.preferredSize.x > 0 ? commands.preferredSize.x : room
        let width   = Math.min(wanted, room)
        let height  = commands.position.height + pad.y + pad.w
        let bottom  = area.bottom() + .documentPanel.margin.w - (.readingLine.isLocallyVisible() ? metrics.miniBar_Distance : inset)
        .viewerBar.setPosition(Math.Rectangle{Math.round(area.horzCenter() - (width + pad.x + pad.z) * 0.5), bottom - height, width + pad.x + pad.z, height}, computeLayout: false)
        commands.dockStyle = .None
        commands.setPosition(Math.Rectangle{pad.x, pad.y, width, commands.position.height}, computeLayout: false)
        commands.applyLayout()
        if .currentView is Viewers.Film.Panel as film
        {
            let top = film.surfaceToLocal({0, .viewerBar.surfaceRect().y}).y
            film.layoutAroundTransport(visible ? Math.max(0, film.clientRect().bottom() - top) : 0)
        }
    }

    // Returns the rectangle the document takes in the window, below the strip and beside the
    // panels shown with it.
    mtd documentArea()->Math.Rectangle
    {
        var result = .documentPanel.surfaceRect()
        let origin = .surfaceToLocal(Math.Point{result.x, result.y})
        result.x = origin.x
        result.y = origin.y
        return result
    }

    // Places the floating commands and hint, then sizes the reserved search strip.
    mtd layoutFloatingParts()
    {
        .layoutViewerBar()
        .layoutSearchBar()
        .explorer?.layoutTools()
    }

    // Aligns the query and its controls to the document's right edge, above its viewport.
    mtd layoutSearchBar()
    {
        let sheetMetrics  = .themeMetrics()
        let sheetArea     = .documentArea()
        let strip         = .stripInset()
        let sheetTop      = Math.max(sheetArea.y, strip) + sheetMetrics.floating_Inset
        let workBottom    = .overlaysViewerBar() and .currentCommands ? Math.min(sheetArea.bottom(), .viewerBar.position.y) : sheetArea.bottom()
        let sheetBottom   = Math.max(.clientRect().bottom() - workBottom, 0)
        let sheetBase     = sheetTop - Math.max(sheetMetrics.floating_Inset, .stripInset())
        let bottomChanged = .infoSheet.margin.w != sheetBottom
        .infoSheet.margin.w = sheetBottom
        if .isExploring()
        {
            .searchBar.hide()
            .explorer!.layoutTools()
            let tools       = .explorer.tools.surfaceRect()
            let toolsBottom = .surfaceToLocal(Math.Point{tools.x, tools.bottom()}).y
            let sheetInset  = Math.max(sheetBase, toolsBottom + sheetMetrics.floating_Inset - Math.max(sheetMetrics.floating_Inset, .stripInset()))
            if .infoSheet.margin.y != sheetInset or bottomChanged
            {
                .infoSheet.margin.y = sheetInset
                .infoSheet.itf.onLayout()
            }

            return
        }

        .searchGroup.setParent(.searchBar)
        .searchCloseButton.show()

        let metrics = .themeMetrics()
        let inset   = metrics.floating_Inset
        let height  = themeActionButtonSize(metrics)
        var area    = .documentArea()
        let pad       = .searchBar.padding
        let fullWidth = Math.min(720'f32, Math.max(area.width - 2 * inset, 0))
        let compact   = fullWidth - pad.x - pad.z < 400 and .searchNavigation.isLocallyVisible()
        var sheetBelowSearch = false
        if .infoSheet.isLocallyVisible()
        {
            let beside = Math.max(Math.min(area.right(), .infoSheet.position.x - inset) - area.x, 0)
            sheetBelowSearch = beside < 320
            if not sheetBelowSearch do
                area.width = beside
        }

        let width         = Math.min(720'f32, Math.max(area.width - 2 * inset, 0))
        let innerWidth    = Math.max(width - pad.x - pad.z, 0)
        let top           = strip + inset * 0.5
        let rowY          = compact ? height + SearchGroupSpacing : 0
        let contentHeight = height + rowY
        let totalHeight   = contentHeight + pad.y + pad.w
        let resized       = .searchBar.position.height != totalHeight
        let sheetInset    = Math.max(sheetBase, sheetBelowSearch and .searchBar.isLocallyVisible() ? totalHeight + inset : 0)
        if .infoSheet.margin.y != sheetInset or bottomChanged
        {
            .infoSheet.margin.y = sheetInset
            .infoSheet.itf.onLayout()
        }

        .searchBar.setPosition({area.right() - inset - width, top, width, totalHeight}, computeLayout: false)
        .searchGroup.setPosition({pad.x, pad.y, innerWidth, contentHeight}, computeLayout: false)

        var right = compact ? innerWidth : innerWidth - height - SearchGroupSpacing
        .searchCloseButton.setPosition({x: innerWidth - height, y: 0, width: height, height: height}, computeLayout: false)
        if .searchOptionsButton.isLocallyVisible()
        {
            let options = themeDropDownButtonWidth(metrics)
            right -= options + SearchGroupSpacing
            .searchOptionsButton.setPosition({right, rowY, options, height}, computeLayout: false)
        }

        if .searchNavigation.isLocallyVisible()
        {
            let count = Math.max(SearchCountWidth,
                                 Painter.measureString(.searchCountLabel.text(), unwrap .searchCountLabel.font().regular).width + SearchGroupSpacing)
            let cancelWidth = .searchCancelButton.isLocallyVisible() ? height + SearchGroupSpacing : 0
            let navigation  = count + 2 * height + cancelWidth
            right -= navigation + SearchGroupSpacing
            .searchNavigation.setPosition({right, rowY, navigation, height}, computeLayout: false)
            .searchCountLabel.setPosition({0, 0, count, height}, computeLayout: false)
            .searchPrevious.setPosition({x: count, y: 0, width: height, height: height}, computeLayout: false)
            .searchNext.setPosition({x: count + height, y: 0, width: height, height: height}, computeLayout: false)
            if .searchCancelButton.isLocallyVisible()
            {
                .searchCancelButton.setPosition({x: count + 2 * height + SearchGroupSpacing,
                                                 y: 0,
                                                 width: height,
                                                 height: height},
                                                computeLayout: false)
            }
        }

        let fieldWidth = compact ? innerWidth - height - SearchGroupSpacing : right - SearchGroupSpacing
        .searchBox.setPosition({0, 0, Math.max(fieldWidth, 0), height})
        if .searchBar.isLocallyVisible()
        {
            .searchBar.bringToFront()
            if resized
            {
                .updateDocumentInsets()
                .documentHost.applyLayout()
            }
        }
    }

    // Enters or leaves a borderless monitor-sized presentation without losing the reader's
    // previous window placement or maximized state.
    mtd setFullScreen(enabled: bool)
    {
        let workspace = .workspace
        if workspace and workspace.primary != me
        {
            workspace.primary.setFullScreen(enabled)
            return
        }

        if .fullScreen == enabled do
            return

        let surface = unwrap .surface
        if enabled
        {
            .fullScreenRestorePosition = surface.isMaximized ? surface.restoredPosition : surface.position
            .fullScreenRestoreFlags    = surface.flags
            .fullScreenWasMaximized    = surface.isMaximized
            surface.updateFlags(add: FullScreenAddedFlags, remove: FullScreenRemovedFlags)
        }
        else
        {
            let transitionFlags = FullScreenRemovedFlags | FullScreenAddedFlags
            let flagsToAdd      = .fullScreenRestoreFlags & transitionFlags
            let flagsToRemove   = transitionFlags & ~.fullScreenRestoreFlags
            surface.updateFlags(add: flagsToAdd, remove: flagsToRemove)
        }

        .applyFullScreenPresentation(enabled)
        if workspace and not workspace.isPendingDestroy
        {
            if let scene = workspace.scene()
            {
                for view in scene.views where view.document and view.document != me do
                    view.document.applyFullScreenPresentation(enabled)
            }
        }

        // Apply the chrome before changing the native size. Restore directly to the
        // desired state so the window never visits its normal bounds on the way to maximized.
        if enabled do
            surface.showNormalAt(Env.monitorForRectangle(.fullScreenRestorePosition).physicalBounds)
        elif .fullScreenWasMaximized do
            surface.showMaximized(.fullScreenRestorePosition)
        else do
            surface.showNormalAt(.fullScreenRestorePosition)

        if workspace and not workspace.isPendingDestroy do
            workspace.layoutScene()
        else
        {
            .applyLayout()
            .layoutFloatingParts()
        }
    }

    // Updates a document's chrome for the presentation of its shared window.
    mtd applyFullScreenPresentation(enabled: bool)
    {
        if .fullScreen == enabled do
            return
        .fullScreen = enabled
        .documentPanel.backgroundStyle = .View
        if enabled
        {
            .readingLine.hide()
            .mainSplitter.setPaneVisible(LeftPanelIndex, false)
            .mainSplitter.setPaneVisible(RightPanelIndex, false)
        }
        else
        {
            .readingLine.show(.readingLine.hasContent() and .canShowReadingLine() and not .isEdgeToEdge())
            let left        = .currentSidePanelButton and .currentSidePanelButton.id == OutlineToggleId
            let index       = left ? LeftPanelIndex : RightPanelIndex
            let placeholder = left ? .outlinePanelPlaceholder : .sidePanelPlaceholder
            .mainSplitter.items[index]!.view = .currentSidePanelHost orelse placeholder
            .mainSplitter.items[index]!.view.show(.currentSidePanelButton?.isChecked orelse false)
            .mainSplitter.setPaneVisible(index, .currentSidePanelButton?.isChecked orelse false)
        }

        .updateDocumentInsets()
        .refreshExplorerCaption()
        .refreshReadingAppearance()
    }

    mtd isWorkspacePrimary()->bool => not .workspace or .workspace.primary == null or .workspace.primary == me

    mtd isWorkspaceActive()->bool => not .workspace or .workspace.primary == null or .workspace.activeDocument() == me

    mtd captionDocument()->*ViewerWindow
    {
        if .workspace and .workspace.primary != null do
            return .workspace.activeDocument()
        return me
    }

    // Builds the main window around the viewer registry `index`: the document
    // and the parts floating over it, then the lens that reaches every command.
    func create(parent: *Wnd, index: #move ViewerPluginRegistry, workspace: *ViewerWorkspace? = null)->*ViewerWindow
    {
        let result = Wnd.create'ViewerWindow(parent, "scope.main")
        result.workspace = workspace
        if not workspace do
            result.surface!.setView(result)
        result.surface!.minSize = {MinWidth, 420}
        result.backgroundStyle = .Application
        result.index           = #move index
        result.language        = Gui.ReferenceLanguage
        if result.isWorkspacePrimary() do
            result.index.attachTo(result.app())
        if result.isWorkspacePrimary()
        {
            with result.returnExplorerCaptionButton = CaptionButton.createLeading(result.surface, .ChevronLeft, ViewerCommands.ReturnToExplorer)
            {
                .toolTip    = appStrings().cmd_ReturnToExplorer
                .sigPressed += func|window = result|(_) { window.captionDocument().closeFile() }
                .hide()
            }

            with result.backCaptionButton = CaptionButton.createLeading(result.surface, .ChevronLeft, ViewerCommands.Back)
            {
                .toolTip    = appStrings().explore_Back
                .sigPressed += func|window = result|(_) { discard window.captionDocument().runCommand(ViewerCommands.Back) }
                .hide()
            }

            with result.forwardCaptionButton = CaptionButton.createLeading(result.surface, .ChevronRight, ViewerCommands.Forward)
            {
                .toolTip    = appStrings().explore_Forward
                .sigPressed += func|window = result|(_) { discard window.captionDocument().runCommand(ViewerCommands.Forward) }
                .hide()
            }

            with result.upCaptionButton = CaptionButton.createLeading(result.surface, .ParentFolder, ViewerCommands.Up)
            {
                .toolTip    = appStrings().explore_Up
                .sigPressed += func|window = result|(_) { discard window.captionDocument().runCommand(ViewerCommands.Up) }
                .hide()
            }

            with result.refreshCaptionButton = CaptionButton.createLeading(result.surface, .Update, ViewerCommands.Refresh)
            {
                .toolTip    = appStrings().explore_Refresh
                .sigPressed += func|window = result|(_) { discard window.captionDocument().runCommand(ViewerCommands.Refresh) }
                .hide()
            }

            with result.findCaptionButton = CaptionButton.createLeading(result.surface, .Search, ViewerCommands.Find)
            {
                .toolTip    = appStrings().ui_FilterFiles
                .sigPressed += func|window = result|(_) { discard window.captionDocument().runCommand(ViewerCommands.Find) }
                .hide()
            }

            with result.outlineCaptionButton = CaptionButton.createLeading(result.surface, .Outline, ViewerCommands.Outline)
            {
                .updateFlags(.Toggle)
                .setCheckIndicator(.Frame)
                .sigPressed += func|window = result|(_) { window.captionDocument().postCommandEvent(ViewerCommands.Outline) }
                .hide()
            }

            // Trailing actions are registered from the window controls toward the title.
            result.createAppearanceChrome()
            with result.fullScreenCaptionButton = CaptionButton.create(result.surface, .FullScreen, ViewerCommands.FullScreen)
            {
                .updateFlags(.Toggle)
                .setCheckIndicator(.Frame)
                .sigPressed += func|window = result|(_) { window.captionDocument().postCommandEvent(ViewerCommands.FullScreen) }
            }

            with result.informationCaptionButton = CaptionButton.create(result.surface, .Information, ViewerCommands.Information)
            {
                .toolTip = appStrings().cmd_Information
                .updateFlags(.Toggle)
                .setCheckIndicator(.Frame)
                .sigCheckedChanged += func|window = result|(_) { discard window.captionDocument().runCommand(ViewerCommands.Information) }
                .hide()
            }

            with result.viewerCaptionButton = CaptionButton.create(result.surface, .Duplicate, "scope.viewer.choices")
            {
                .toolTip = appStrings().lens_ViewAs
                .setIconColor(Color{})
                .sigPressed += func|window = result|(_) { window.captionDocument().showViewerChoicesMenu() }
                .hide()
            }

        }
        else
        {
            let primary = workspace!.primary
            result.returnExplorerCaptionButton = primary.returnExplorerCaptionButton
            result.backCaptionButton = primary.backCaptionButton
            result.forwardCaptionButton = primary.forwardCaptionButton
            result.upCaptionButton = primary.upCaptionButton
            result.refreshCaptionButton = primary.refreshCaptionButton
            result.findCaptionButton = primary.findCaptionButton
            result.outlineCaptionButton = primary.outlineCaptionButton
            result.appearanceButton = primary.appearanceButton
            result.fullScreenCaptionButton = primary.fullScreenCaptionButton
            result.informationCaptionButton = primary.informationCaptionButton
            result.viewerCaptionButton = primary.viewerCaptionButton
        }

        with result.mainSplitter = SplitterCtrl.create(result)
        {
            .dockStyle       = .Center
            .backgroundStyle = .Transparent
            .flags           = .HideDividers
        }

        result.createDocumentPanel()
        result.createSearchBar()
        result.createViewerBar()
        result.createSheetAndHint()
        result.dropHighlight = FileDropHighlight.create(result, appStrings().ui_DropTitle, "scope.drop.highlight")
        result.createLens()
        if result.isWorkspacePrimary()
        {
            result.lensLauncher = Lens.Launcher.create(result, ViewerCommands.Lens)
            result.lensLauncher.captionButton.hide()
        }
        else
        {
            result.lensLauncher = workspace!.primary.lensLauncher
        }

        result.privacy.window = result
        if result.isWorkspacePrimary() do
            result.privacy.createIndicator()
        result.privacyTimer = result.addTimer(250'ms)
        result.hookChildEvents()

        if result.isWorkspacePrimary() do
            result.applyLanguage()
        result.refreshArtwork()
        result.updateViewerBar()
        result.updateDocumentInsets()
        result.applyLayout()
        result.layoutFloatingParts()
        return result
    }

    // Creates the about box with the product identity and the list of supported viewers. `version`
    // replaces the running compiler's version when given.
    mtd createAboutDialog(buildDate: Time.DateTime, version: string? = null)->*AboutDlg
    {
        let liveVersion = Format.toString("%.%.%", #swcversion, #swcrevision, #swcbuildnum)

        with var about: ApplicationAboutDlgParams
        {
            .productName     = ProductName
            .version         = version orelse liveVersion.toString()
            .buildDate       = buildDate
            .sourceUrl       = "https://github.com/swag-lang/swc/tree/master/bin/apps/modules/swagscope"
            .copyrightHolder = "Christophe Beaudet"
        }

        // The registry remains the source of the compact capability line, but extension details
        // stay out of the identity box: the viewer names communicate the supported content
        // families without turning About into a file-association inventory.
        let dialog = AboutDlg.createApplication(unwrap .surface, about)
        dialog.addSection(appStrings().ui_AboutViewers, .aboutViewerList())
        const TmdbLogo = #include("../datas/tmdb.svg")
        let logoDrawing = expect Svg.Drawing.parse(Swag.makeString(TmdbLogo.buffer, TmdbLogo.count))
        dialog.addSectionImage(logoDrawing.rasterize(138, 100), 138, 100)
        dialog.addSection("TMDB / Apple / Wikipedia / Wikidata", appStrings().ui_AboutWikiNotice)
        return dialog
    }

    // Opens the standard product identity and provenance dialog.
    mtd showAbout()
    {
        const BuildDate = #run Time.DateTime.now()
        discard .createAboutDialog(BuildDate).doModal()
    }

    // Returns every registered viewer name in selection order, as one compact capability line.
    //
    // The names carry the content families without repeating the registry's extension inventory.
    // The line is an inline markup sentence, as an about section expects.
    mtd const aboutViewerList()->String
    {
        var result: #returntype
        for plugin in .index.plugins
        {
            // The no-break spaces keep each separator with the name before it, so a line never
            // opens on one.
            if not result.isEmpty() do
                result += "\u00A0\u00A0·  "
            result += Format.toString("<b>%</b>", RichString.escape(plugin.displayName()))
        }

        return result
    }

    // Returns the window of the active viewer that owns the keyboard, or the viewer itself when
    // it declares no traversal stop. A composite stop hands out its focus delegate, which is
    // the window that actually reads the keys.
    mtd viewerFocusTarget()->*Wnd?
    {
        let view = .currentView
        if not view do
            return null
        let order = FocusOrder.collect(view)
        let stop  = order.stops.isEmpty() ? view : order.stops[0]
        return stop.focusTarget()
    }

    // Routes playback keys before a focused child can consume them. One physical press toggles
    // once even when the operating system emits repeated pressed transitions while it is held.
    mtd routePlaybackKey(evt: *KeyEvent)->bool
    {
        if .forwardingViewerKey do
            return false
        if evt.kind == .Pressed and evt.key == .Tab and not evt.modifiers.has(.Control) and .usesTimedViewerBar()
        {
            .revealViewerBar()
            return false
        }

        let arrowKey  = evt.key == .Left or evt.key == .Right
        let rateStep  = evt.modifiers == .Shift and arrowKey
        let frameStep = evt.modifiers == .Control and arrowKey
        let timeJump  = evt.modifiers == .Control and evt.key == .G
        if evt.modifiers != .None and not rateStep and not frameStep and not timeJump do
            return false

        let toggle = evt.key == .Space or evt.key == .MediaPlayPause
        if toggle and evt.kind == .Released
        {
            let handled = .playPauseKeyDown
            .playPauseKeyDown = false
            return handled
        }

        if evt.kind != .Pressed or .lens.isOpen() do
            return false
        let editing = evt.target is EditBox or .focusedWindow() is EditBox
        if editing and evt.key != .MediaPlayPause and evt.key != .MediaStop and evt.key != .VolumeMute do
            return false
        if .activeChoiceIndex >= .choices.count do
            return false
        let key = .choices[.activeChoiceIndex].key.toString()
        let playbackViewer = key == "video" or key == "sound" or key == "image"
        if not playbackViewer do
            return false

        if rateStep and key == "sound" do
            return .forwardKeyToViewer(evt, skipFocused: false, takeFocus: false)
        if rateStep or frameStep or timeJump
        {
            if key != "video" do
                return false
            return .forwardKeyToViewer(evt, skipFocused: false, takeFocus: false)
        }

        if toggle
        {
            if .playPauseKeyDown do
                return true
            let handled = .forwardKeyToViewer(evt, skipFocused: false, takeFocus: false)
            .playPauseKeyDown = handled
            if handled and .usesTimedViewerBar() do
                .revealViewerBar()
            return handled
        }

        if evt.key != .MediaStop and evt.key != .VolumeMute and evt.key != .M do
            return false
        return .forwardKeyToViewer(evt, skipFocused: false, takeFocus: false)
    }

    // Offers a key the window received to the active viewer, unless the viewer already declined it,
    // and returns whether the viewer accepted it. `takeFocus` gives the keyboard to a viewer that
    // accepted the key.
    private mtd forwardKeyToViewer(evt: *KeyEvent, skipFocused = true, takeFocus = true)->bool
    {
        let target = .viewerFocusTarget()
        if not target do
            return false

        // A key the viewer's key owner already saw and declined must not be offered twice.
        let focused = .focusedWindow()
        if skipFocused and focused and (focused == target or target.isOwnerOf(focused)) do
            return false

        let view = .currentView
        var copy = KeyEvent{kind: evt.kind, key: evt.key, modifiers: evt.modifiers}
        .forwardingViewerKey = true
        defer .forwardingViewerKey = false
        target.sendEvent(&copy)

        // A declined key bubbles back here and navigates to another file, which destroys the
        // viewer the key was offered to; only a viewer that is still showing takes the keyboard.
        if takeFocus and
           copy.accepted and
           .currentView == view and
           target.focusPolicy != .None do
            target.setFocus()
        return copy.accepted
    }

    // Applies the current language to the window's own texts and tooltips, to failure views, and to
    // the empty state when no file is open.
    mtd retranslate()
    {
        let texts = appStrings()
        .refreshTitle()
        .teachHints(.isExploring())
        .searchPrevious.toolTip     = texts.ui_SearchPrevious
        .searchNext.toolTip         = texts.ui_SearchNext
        .searchCancelButton.toolTip = texts.ui_SearchCancel
        .refreshExplorerCaption()
        .searchOptionsButton.toolTip = texts.ui_SearchOptions
        .searchCloseButton.toolTip   = texts.ui_CloseSearch
        .refreshOutlineCaption()
        .refreshSearchPresentation()
        .refreshSearchReadout()
        for &instance in .instances where instance.view and not instance.failureReason.isEmpty() do
            assume cast(*ViewerErrorView, instance.view).retranslate()
        if .currentFile.isEmpty()
        {
            .refreshHome()
        }

        if .infoSheet.isLocallyVisible() do
            .refreshInformation()
        .invalidate()
    }

    // Writes the keys the hint line teaches: those of a listing while a folder is explored,
    // otherwise only the door; the line shows on the home and on a listing.
    mtd teachHints(exploring: bool)
    {
        let texts   = appStrings()
        let metrics = .themeMetrics()
        .hintLine.margin.w = .readingLine.isLocallyVisible() ?
                             .readingLine.position.height + metrics.floating_Inset : 0
        let inset = metrics.floating_Inset
        let sheetWidth = Math.min(metrics.infoSheet_Width, Math.max(.clientRect().width - 2 * inset, 0))
        .hintLine.margin.z = exploring and .infoSheet.isLocallyVisible() ? sheetWidth + inset : 0
        .hintLine.clearHints()

        // The keys of an explored page are taught while what it shows leaves its foot free: an
        // archive's way in and out, a folder's filter.
        let roomy = exploring and
                    .explorer and
                    .explorer.scroll.scrollSize.y + HintRoom < .explorer.scroll.clientRect().height
        let archive = roomy and .explorer!.listing.isArchive
        if archive
        {
            .hintLine.addHint(Gui.strings().key_Enter, texts.hint_Open)
            .hintLine.addHint(texts.hint_KeyBack, texts.hint_Parent)
        }

        // Music is opened and played from its page; pictures use the common grid.
        let board = roomy and not archive ? .explorer!.grid.board : ExplorerBoard.Grid
        if board == .Covers
        {
            .hintLine.addHint(Gui.strings().key_Enter, texts.hint_Open)
            .hintLine.addHint("P", texts.hint_PlayAlbum)
        }
        elif board == .Album
        {
            .hintLine.addHint(Gui.strings().key_Enter, texts.hint_Play)
        }

        .hintLine.addHint(Input.formatKeyShortcut(.Control, .Space), texts.ui_HintLens)
        if roomy and not archive and (board == .Grid or board == .Posters) do
            .hintLine.addHint("/", texts.hint_Filter)
        .hintLine.show(roomy or (not exploring and .home.isLocallyVisible()))
    }

    // Names what the window shows in its title: the open file, followed by the viewer when the
    // reader chose another than the one the file opens in; the explored folder; or the product.
    mtd refreshTitle()
    {
        let surface = .surface
        if not surface do
            return
        if not .isWorkspaceActive() do
            return
        .refreshExplorerCaption()

        let scene = .workspace?.scene()
        if scene and scene.views.count > 1
        {
            surface.setTitle(.workspace!.sceneName(scene))
            return
        }

        if .isExploring()
        {
            let path = .explorer!.listing.path
            surface.setTitle(Path.fileName(path) orelse path)
            return
        }

        if .currentFile.isEmpty()
        {
            surface.setTitle(ProductName)
            return
        }

        let path = .explorer ? .explorer.logicalPath(.currentFile) : .currentFile.toString()
        var title: String = Path.fileName(path) orelse path
        if .activeChoiceIndex > 0 and .activeChoiceIndex < .choices.count
        {
            title += " · "
            title += .index.plugins[.choices[.activeChoiceIndex].pluginIndex].displayName()
        }

        surface.setTitle(title)
    }
}

impl ViewerWindow
{
    // Enters exploration explicitly; opening one ordinary file never creates an explorer.
    mtd exploreFolder()
    {
        if .explorerActive and
           .explorer and
           not .explorer.isLocallyVisible() and
           .explorer.displayPath(.currentFile) != .currentFile.toString()
        {
            .closeFile()
            return
        }

        if not .currentFile.isEmpty()
        {
            let folder = Path.directoryName(.currentFile) orelse ""
            if folder.count
            {
                if .explorerActive and .explorer and .explorer.listing.path == folder do
                    .closeFile()
                else do
                    .openExplorer(folder)
            }

            return
        }

        let folder = .selectExplorerFolder()
        if not folder.isEmpty() do
            .openExplorer(folder)
    }

    mtd selectExplorerFolder(initialFolder: string = "")->String
    {
        with var options: FileDlgOptions
        {
            .mode          = .SelectFolder
            .initialFolder = initialFolder
            .state         = &me.fileDlgState
        }

        let dialog = FileDlg.create(unwrap .surface, options)
        if dialog.doModal() != Dialog.BtnOk do
            return {}
        return dialog.selectedPath()
    }

    mtd openExplorer(path: string)
    {
        // Own the path before retiring the viewer whose currentFile may have supplied it.
        let source = String.from(path)
        if .isWorkspaceActive() do
            .surface?.clearFocus()
        if not .explorer do
            .explorer = Explorer.create(.documentPanel, me)
        .explorer.history.push(Format.toString("%\n", source))
        .explorerActive = true
        .privacy.track(source)
        .rememberExplored(source)
        .closeFile(forExplorer: true)
        .home.hide()
        .searchBox.setText(.explorer.filter.text(), notify: false)
        .explorer.setShown(true)
        .explorer.navigate(source)
        .workspace?.updateMedia()
        if .isWorkspaceActive() do
            .surface?.clearFocus()
        .refreshTitle()
        .applyLayout()
    }
}
