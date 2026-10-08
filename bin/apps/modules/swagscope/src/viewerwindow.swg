using Core, Pixel, Gui

// One remembered answer to "which viewer opens a file of this kind".
//
// A reader who turns to the bytes of one picture is telling the application what to do with the
// next one, so the choice is kept against the viewer the file would have opened in rather than
// against its extension: every video reaches the byte view through one decision, not one per
// container.
struct ViewerPreference
{
    kind:   String     // Stable key of the viewer a file of this kind opens in by default.
    viewer: String     // Stable key of the viewer the reader chose for it instead.
}

// One recently viewed folder and the last file that made it current.
struct ViewerFolderHistory
{
    folder: String
    file:   String
}

// Returns the application window that hosts `view`.
func viewerWindowFor(view: *Wnd)->*ViewerWindow => view.ancestorByType'ViewerWindow()!

// Replaces a viewer that failed after creation with the standard error surface.
func reportViewerFailure(view: *Wnd, reason: string) { viewerWindowFor(view).replaceFailedViewer(view, reason) }

// The main window of Swag Scope: the command, information, and viewer bars around the document,
// the file panel beside it, and every viewer session opened for the current file.
struct ViewerWindow
{
    using wnd: Wnd

    late
    {
        commandBar:          *ViewerActionBar
        commandButtons:      *IconBar
        kindButton:          *IconButton
        openButton:          *IconButton
        closeButton:         *IconButton
        openDefaultButton:   *IconButton
        filesButton:         *IconButton
        fullScreenButton:    *IconButton
        searchGroup:         *StackLayoutCtrl
        searchNavigation:    *StackLayoutCtrl
        searchBox:           *EditBox
        searchCountLabel:    *Label
        searchPrevious:      *IconButton
        searchNext:          *IconButton
        searchOptionsButton: *IconButton
        viewerCombo:         *ComboBox
        appearanceButton:    *AppearanceButton
        accentRail:          *Separator
        infoBarHost:         *Wnd
        infoBar:             *ViewerInfoBar
        infoContentGroup:    *ViewerInfoLayout
        infoFileGroup:       *StackLayoutCtrl
        infoIconLabel:       *Label
        infoNameLabel:       *Label
        infoStatsLabel:      *Label
        infoSizeLabel:       *Label
        documentHost:        *Wnd
        documentPanel:       *Wnd
        loadingOverlay:      *ViewerLoadingOverlay
        searchOverlay:       *ViewerSearchOverlay
        dropHighlight:       *ViewerDropHighlight
        viewerBar:           *ViewerActionBar
        emptyView:           *StackLayoutCtrl
        emptyIconLabel:      *Label
        emptyLabel:          *Label
        emptyHintLabel:      *Label
        filePanelHost:       *Wnd
        filePanel:           *SplitterCtrl
        recentPane:          *Wnd
        recentLabel:         *Label
        recentClearButton:   *IconButton
        recentList:          *ListCtrl
        folderPane:          *Wnd
        folderHistoryButton: *IconButton
        folderLabel:         *Label
        folderList:          *ListCtrl
    }

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
    activeChoiceIndex             = Swag.U32.Max
    startupTimer:            *Timer?
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
    searchProcessed:         u64
    searchProgress:          u64
    searchSpan:              u64
    searchMatches:           Array'Viewer.SearchMatch
    searchIndex:             u64  = Swag.U64.Max
    searchMatch:             u64  = Swag.U64.Max
    searchComplete:          bool
    searchSelectLast:        bool
    searchMatchCaseOption:   bool
    searchWholeWordOption:   bool
    searchRegexOption:       bool
    searchFilterMode:        bool
    pendingFile:             String
    pendingEmpty:            String
    pendingRemember:         bool = true
    fileWatch:               ViewerFileWatch
    fileWatchTimer:          *Timer?
    readingState:            ViewerReadingState
    reloading:               bool
    currentFile:             String
    currentFileSize:         String
    folderFiles:             Array'String
    siblings:                Array'String
    siblingIndex:            u64
    siblingsDirty                 = true

    // Whether next/previous and the folder list keep only the neighbours the current file's
    // viewer would open, so a reader flips through the pictures of a folder without landing on
    // the notes stored beside them.
    folderSameKind: bool

    // The play mode and what it needs: the slideshow pace, the timer counting it down, the view
    // that reported a still picture for it to count, and the files already read in the current
    // folder round. The same round state drives shuffle choice and the file-panel progress.
    playMode:            Viewer.PlayMode
    slideSeconds:        f32 = Viewer.SlideDefaultSeconds
    slideTimer:          *Timer?
    stillView:           *Wnd?
    folderReadingMode:   Viewer.PlayMode
    folderReadingFolder: String
    folderReadingFiles:  Array'String

    // Guards the one nested dispatch [[ViewerWindow.forwardKeyToViewer]] makes, so a key the viewer
    // declines falls back to file navigation instead of being offered again.
    forwardingViewerKey: bool
    playPauseKeyDown:    bool
    recent:              Array'String
    folderHistory:       Array'ViewerFolderHistory
    preferences:         Array'ViewerPreference
    panelVisible:        bool
    recentPaneSize = RecentHeight
    refreshingLists:     bool
    fileDlgState:        FileDlgState
    themeIndex:          u32
    language:            String

    // A monitor-sized presentation is transient: what the window was before entering it is what
    // leaving it restores, placement, maximized state, and surface flags alike.
    fullScreen:                bool
    fullScreenWasMaximized:    bool
    fullScreenRestorePosition: Math.Rectangle
    fullScreenRestoreFlags:    SurfaceFlags
    fullScreenTopVisible:      bool
    fullScreenBottomVisible:   bool
    smokeDirectory:            String
    smokeSpecIndex:            u64
    smokeWaitSteps:            u32
    smokeOpened:               bool
    smokeSelected:             bool
    smokeRunning:              bool
}

// Records the format summary a viewer reported after creation, and shows it while that viewer is active.
func reportViewerDetails(view: *Wnd, details: string)
{
    let window = viewerWindowFor(view)
    for &instance, index in window.instances where instance.view == view
    {
        instance.details = details
        if index == window.activeChoiceIndex do
            window.updateFileInfo(details)
        return
    }
}

// Re-measures viewer-owned chrome after a compact value or action group changes shape.
func reportViewerChromeChanged(view: *Wnd)
{
    let window = viewerWindowFor(view)
    if window.currentView != view do
        return
    window.commandBar.centerContent()
    window.viewerBar.centerContent()
    window.layoutFileInfo()
    window.applyLayout()
}

// Opens a neighboring file for the viewer that chose to own directional navigation.
func navigateViewerFile(view: *Wnd, delta: s32)
{
    viewerWindowFor(view).navigate(delta)
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
    return {window.playMode, window.slideSeconds}
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
    }
}

// Returns the services a viewer of the main window reaches its host through.
func viewerHostServices()->Viewer.HostServices
{
    with var result: retval
    {
        .reportFailure          = &reportViewerFailure
        .reportDetails          = &reportViewerDetails
        .reportChromeChanged    = &reportViewerChromeChanged
        .reportLoadingChanged   = &reportViewerLoadingChanged
        .navigateFile           = &navigateViewerFile
        .reportFinished         = &reportViewerFinished
        .reportShown            = &reportViewerShown
        .playback.readSettings  = &readViewerPlayback
        .playback.writeSettings = &writeViewerPlayback
    }

    return result
}

impl IWnd for ViewerWindow
{
    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if evt.kind == .Move or evt.kind == .Enter do
            .updateFullScreenChrome(evt.surfacePos)
        evt.accepted = false
    }

    mtd impl onResizeEvent(?: *ResizeEvent)
    {
        .layoutFullScreenChrome()
    }

    mtd impl onDragDropEvent(evt: *DragDropEvent)
    {
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

        .dropHighlight.showTarget(not .emptyView.isLocallyVisible())

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

        let plain = evt.modifiers == .None
        switch evt.key
        {
        case .F11 where plain:                     .setFullScreen(not .fullScreen)
        case .Escape where plain and .fullScreen:  .setFullScreen(false)
        case .O where evt.modifiers.has(.Control): .chooseFile()
        case .F where evt.modifiers.has(.Control): .showSearch()
        case .F3 where evt.modifiers.has(.Shift):  .findPrevious()
        case .F3 where plain:                      .findNext()
        case .F5 where not .currentFile.isEmpty(): .reloadCurrentFile()
        case .Left, .Right where plain:            evt.accepted = not .forwardingViewerKey and .forwardKeyToViewer(evt)
        default: evt.accepted = false
        }
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer == .fileWatchTimer
        {
            if not .pendingFile.isEmpty() or .currentFile.isEmpty() do
                return
            if .readingState.restoring and .activeChoiceIndex < .instances.count
            {
                if .searchTimer do
                    return
                if .readingState.restore(&.instances[.activeChoiceIndex]) do
                    .readingState.restoring = false
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

        if evt.timer != .startupTimer
        {
            evt.accepted = false
            return
        }

        .stopTimer(&.startupTimer)
        if not .pendingFile.isEmpty()
        {
            .processQueuedFile()
        }
        elif not .pendingEmpty.isEmpty()
        {
            let message = #move .pendingEmpty
            .showEmpty(message)
        }
    }

    mtd impl onDestroyEvent(?: *DestroyEvent)
    {
        if .fullScreen do
            .setFullScreen(false)
        catch .saveState()
        .stopSearch()
        .stopLoadingIndicator()
        .stopSlide()
        .stopTimer(&.fileWatchTimer)

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

        catch g_App.loadState()
        .applyTheme(.themeIndex)
        .applyLanguage()
        .kindButton.setChecked(.folderSameKind)
        .setFilePanelVisible(.panelVisible)
        .surface?.constrainPositionToScreen(topLeft: true, margin: 10)
        .refreshEmptyArtwork()
        evt.accepted = true
    }

    mtd impl onSerializeStateEvent(evt: *SerializeStateEvent)
    {
        if not evt.serializer.isReading() and not .filePanel.items.isEmpty() do
            .recentPaneSize = .filePanel.items[0]!.size

        catch evt.serializer.serialize("ViewerWindow.fileDlgState", &me.fileDlgState)
        catch evt.serializer.serialize("ViewerWindow.themeIndex", &me.themeIndex)
        catch evt.serializer.serialize("ViewerWindow.language", &me.language)
        catch evt.serializer.serialize("ViewerWindow.recent", &me.recent)
        catch evt.serializer.serialize("ViewerWindow.folderHistory", &me.folderHistory)
        catch evt.serializer.serialize("ViewerWindow.preferences", &me.preferences)
        catch evt.serializer.serialize("ViewerWindow.panelVisible", &me.panelVisible)
        catch evt.serializer.serialize("ViewerWindow.recentPaneSize", &me.recentPaneSize)
        catch evt.serializer.serialize("ViewerWindow.folderSameKind", &me.folderSameKind)
        catch evt.serializer.serialize("ViewerWindow.playMode", &me.playMode)
        catch evt.serializer.serialize("ViewerWindow.slideSeconds", &me.slideSeconds)
        catch evt.serializer.serialize("ViewerWindow.searchMatchCase", &me.searchMatchCaseOption)
        catch evt.serializer.serialize("ViewerWindow.searchWholeWord", &me.searchWholeWordOption)
        catch evt.serializer.serialize("ViewerWindow.searchRegularExpression", &me.searchRegexOption)
        catch evt.serializer.serialize("ViewerWindow.videoSubtitles", &Viewers.Film.g_SubtitleSettings)
        catch evt.serializer.serialize("ViewerWindow.markdown", &Viewers.MarkdownText.g_ViewerSettings)
        if evt.serializer.isReading()
        {
            .themeIndex     = Math.min(.themeIndex, cast(u32, AppearanceTheme.Dark))
            .recentPaneSize = Math.max(.recentPaneSize, PaneMinSize)
            if not .filePanel.items.isEmpty() do
                .filePanel.items[0]!.size = .recentPaneSize
            while .recent.count > RecentCount do
                .recent.removeAtOrdered(.recent.count - 1)
            while .folderHistory.count > FolderHistoryCount do
                .folderHistory.removeAtOrdered(.folderHistory.count - 1)
            .folderHistoryButton.enable(not .folderHistory.isEmpty())
            .searchBox.setValidator(.searchBox.validator)
            if cast(u32, .playMode) > cast(u32, Viewer.PlayMode.Shuffle) do
                .playMode = .Once
            .slideSeconds = Math.clamp(.slideSeconds, Viewer.SlideMinSeconds, Viewer.SlideMaxSeconds)
            Viewers.Film.g_SubtitleSettings.sanitize()
            Viewers.MarkdownText.g_ViewerSettings.sanitize()
        }
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        switch evt.kind
        {
        case .LanguageChanged:
            .retranslate()
            .dropHighlight.retranslate()

        case .ThemeChanged:
            for &instance in .instances where instance.view and not instance.failureReason.isEmpty() do
                assume cast(*ViewerErrorView, instance.view).refreshTheme()
            if .panelVisible and not .currentFile.isEmpty() do
                .refreshFileLists()
            .refreshArtwork()
            .refreshEmptyArtwork()
            .dropHighlight.refreshTheme()
        }

        .wnd.IWnd.onNotifyEvent(evt)
    }
}

impl ViewerWindow
{
    // The command, information, and action bars around the document, and the narrowest window
    // that still lays them out.
    const BarHeight       = 48.0
    const InfoHeight      = 40.0
    const ActionBarHeight = 42.0
    const MinWidth        = 880

    // The side panel that lists what is beside the current file, and what was read before it.
    const PanelWidth   = 276.0
    const RecentHeight = 188.0
    const PaneMinSize  = 88.0

    // Files the recent list keeps. Long enough to cross a working session, short enough that the
    // list stays something a reader scans rather than searches.
    const RecentCount        = 12'u64
    const FolderHistoryCount = 8'u64

    // The search group of the command bar.
    const SearchFieldWidth          = 180.0
    const SearchNoOptionsFieldWidth = 256.0
    const SearchCountWidth          = 52.0
    const SearchGroupSpacing        = 16.0

    // Search reads the file one chunk at a time. A match that may continue into the next chunk
    // waits for it, so each chunk keeps the query span plus this margin of the one before.
    const SearchChunkSize   = 256 * 1024'u64
    const SearchCarryMargin = 4'u64

    // How often the halo of the current match follows a moving view, and how long one pulse of its
    // glow lasts.
    const SearchBoundsPoll: Time.Duration = 16'ms
    const SearchGlowPeriod = 1.35'f32

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

    // How often a pending file change looks again for its classification and for the retirement of
    // the viewer before it.
    const RetirePollInterval: Time.Duration = 16'ms

    // In full screen the bars step aside; the pointer within this distance of an edge brings them
    // back. The surface loses its frame and stays above other windows.
    const FullScreenRevealEdge   = 32.0
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
        .themeIndex = Math.min(index, cast(u32, AppearanceTheme.Dark))
        .appearanceButton.setAppearanceTheme(cast(AppearanceTheme, .themeIndex))
    }

    mtd applyLanguage()
    {
        discard catch .appearanceButton.setAppearanceLanguage(.language)
    }

    // Keeps the few decorative glyphs aligned with the active palette and document kind.
    mtd refreshArtwork()
    {
        .infoIconLabel.setIconColor(.themeColors().label_TextFaint)
        .searchPrevious.setIcon(.theme().icon(.SearchPrevious, themeActionIconSize(.themeMetrics())))
        .searchNext.setIcon(.theme().icon(.SearchNext, themeActionIconSize(.themeMetrics())))
        .refreshSearchPresentation()
        if .activeChoiceIndex < .choices.count do
            .infoIconLabel.setIcon(.choiceIcon(.activeChoiceIndex))
    }

    // Gives the drop hint its glyph, but only while the hint is what the window shows.
    //
    // The glyph is the one large icon of the window, and an icon set rasterizes its whole sheet
    // at every size it is asked for: this one costs a third of a second and tens of megabytes
    // at a display scale of two. A launch that already names a file never shows the hint, so
    // it never pays for it; the hint takes its glyph the moment it is actually shown.
    private mtd refreshEmptyArtwork()
    {
        if not .emptyView.isVisible() do
            return
        .emptyIconLabel.setIcon(.theme().icon(.OpenFile, 48))
        .emptyIconLabel.setIconColor(.themeColors().label_TextFaint)
    }

    // A monitor-sized full-screen placement is transient and must never replace the saved
    // window placement. Closing first restores the regular placement, then persists it.
    private mtd saveState() fail
    {
        if .fullScreen do
            return
        try g_App.saveState()
    }

    // Keeps a four-pixel structural edge when the selected viewer has no command bar. Full screen
    // remains immersive and reveals the complete command bar only when the viewer owns one.
    private mtd updateViewerBar()
    {
        .viewerBar.centerGroup     = .currentCommands
        .viewerBar.position.height = .currentCommands ? BarHeight : .themeMetrics().panel_GutterSize
        if .fullScreen do
            .viewerBar.show(.fullScreenBottomVisible and .currentCommands != null)
        else do
            .viewerBar.show()
        .viewerBar.centerContent()
    }

    // Enters or leaves a borderless monitor-sized presentation without losing the reader's
    // previous window placement or maximized state.
    mtd setFullScreen(enabled: bool)
    {
        if .fullScreen == enabled do
            return

        let surface = .surface!
        if enabled
        {
            .fullScreenRestorePosition = surface.isMaximized ? surface.restoredPosition : surface.position
            .fullScreenRestoreFlags    = surface.flags
            .fullScreenWasMaximized    = surface.isMaximized
            .fullScreen = true
            surface.updateFlags(add: FullScreenAddedFlags, remove: FullScreenRemovedFlags)
            .documentHost.padding = {}
            .documentPanel.backgroundStyle = .View
            .accentRail.hide()
            .commandBar.dockStyle  = .None
            .infoBarHost.dockStyle = .None
            .viewerBar.dockStyle   = .None
            .commandBar.hide()
            .infoBarHost.hide()
            .viewerBar.hide()
            .filePanelHost.hide()
            .filesButton.hide()
            .currentSidePanelHost?.hide()
            .currentSidePanelButton?.hide()
            .infoContentGroup.sideButton = null
            .fullScreenTopVisible        = false
            .fullScreenBottomVisible     = false

            // Commit the final chrome and bounds together through the native placement path.
            surface.showNormalAt(Env.monitorForRectangle(.fullScreenRestorePosition).physicalBounds)
        }
        else
        {
            .fullScreen = false
            surface.updateFlags(add: .fullScreenRestoreFlags & (FullScreenRemovedFlags | FullScreenAddedFlags), remove: (FullScreenRemovedFlags | FullScreenAddedFlags) & ~.fullScreenRestoreFlags)
            let gutter = .themeMetrics().panel_GutterSize
            .documentHost.padding = {gutter, 0, gutter, 0}
            .documentPanel.backgroundStyle = .Panel
            .accentRail.show()
            .commandBar.dockStyle  = .Top
            .infoBarHost.dockStyle = .Top
            .viewerBar.dockStyle   = .Bottom
            .commandBar.show()
            .infoBarHost.show()
            .updateViewerBar()
            .filePanelHost.show(.panelVisible)
            .filesButton.show()
            .currentSidePanelButton?.show()
            .currentSidePanelHost?.show(.currentSidePanelButton?.isChecked orelse false)
            .infoContentGroup.sideButton = .currentSidePanelButton
            .fullScreenTopVisible        = false
            .fullScreenBottomVisible     = false

            // Going straight back to the maximized state keeps the window out of its restored
            // bounds, which would otherwise be shown for one transaction on the way.
            if .fullScreenWasMaximized do
                surface.showMaximized(.fullScreenRestorePosition)
            else do
                surface.showNormalAt(.fullScreenRestorePosition)
        }

        surface.invalidate()
        .fullScreenButton.setChecked(.fullScreen)
        .fullScreenButton.setIcon(.theme().icon(.fullScreen ? .ExitFullScreen : .FullScreen, themeActionIconSize(.themeMetrics())))
        .fullScreenButton.toolTip = .fullScreen ? appStrings().ui_ExitFullScreen : appStrings().ui_FullScreen
    }

    // Reveals full-screen chrome only while the pointer is at the corresponding screen edge.
    mtd updateFullScreenChrome(position: Math.Point)
    {
        if not .fullScreen do
            return
        let height = .clientRect().height
        let top    = position.y <= FullScreenRevealEdge or (.fullScreenTopVisible and position.y <= ActionBarHeight + .infoBarHost.position.height)
        let bottom = position.y >= height - FullScreenRevealEdge or (.fullScreenBottomVisible and position.y >= height - BarHeight)
        if top == .fullScreenTopVisible and bottom == .fullScreenBottomVisible do
            return
        .fullScreenTopVisible    = top
        .fullScreenBottomVisible = bottom
        .layoutFullScreenChrome()
    }

    // Positions the transient bars over the content without changing its full-screen rectangle.
    mtd layoutFullScreenChrome()
    {
        if not .fullScreen do
            return
        let rect = .clientRect()
        .commandBar.show(.fullScreenTopVisible)
        .infoBarHost.show(.fullScreenTopVisible)
        .updateViewerBar()
        if .fullScreenTopVisible
        {
            .commandBar.setPosition({rect.x, rect.y, rect.width, ActionBarHeight}, computeLayout: false)
            .infoBarHost.setPosition({rect.x, rect.y + ActionBarHeight, rect.width, .infoBarHost.position.height}, computeLayout: false)
            .commandBar.applyLayout()
            .infoBarHost.applyLayout()
            .commandBar.bringToFront()
            .infoBarHost.bringToFront()
        }

        if .fullScreenBottomVisible and .currentCommands
        {
            .viewerBar.setPosition({rect.x, rect.bottom() - BarHeight, rect.width, BarHeight}, computeLayout: false)
            .viewerBar.applyLayout()
            .viewerBar.bringToFront()
        }
    }

    func create(parent: *Wnd, index: ViewerPluginRegistry)->*ViewerWindow
    {
        let result = Wnd.create'ViewerWindow(parent, "scope.main")
        result.surface!.setView(result)
        result.surface.minSize = {MinWidth, 420}
        result.backgroundStyle = .Application
        result.index           = #move index
        result.language        = Gui.ReferenceLanguage
        result.index.attachTo(result.app())

        let panelGutter = result.themeMetrics().panel_GutterSize
        result.createAppearanceChrome()
        result.createCommandBar()
        result.createInfoBar(panelGutter)
        result.createViewerBar()
        result.createFilePanel(panelGutter)
        result.createDocumentPanel(panelGutter)
        result.hookChildEvents()

        result.applyLanguage()
        result.refreshArtwork()
        result.updateViewerBar()
        result.applyLayout()
        return result
    }

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
        let dialog = AboutDlg.createApplication(.surface!, about)
        dialog.addSection(appStrings().ui_AboutViewers, .aboutViewerList())
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
    mtd const aboutViewerList()->String
    {
        var result: retval
        for plugin in .index.plugins
        {
            if not result.isEmpty() do
                result += "  ·  "
            result += "<b>"
            result += plugin.displayName()
            result += "</b>"
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
        if .forwardingViewerKey or evt.modifiers != .None do
            return false

        let toggle = evt.key == .Space or evt.key == .MediaPlayPause
        if toggle and evt.kind == .Released
        {
            let handled = .playPauseKeyDown
            .playPauseKeyDown = false
            return handled
        }

        if evt.kind != .Pressed do
            return false
        if .activeChoiceIndex >= .choices.count do
            return false
        let key = .choices[.activeChoiceIndex].key.toString()
        let playbackViewer = key == "video" or key == "sound" or key == "image"
        if not playbackViewer do
            return false

        if toggle
        {
            if .playPauseKeyDown do
                return true
            let handled = .forwardKeyToViewer(evt, skipFocused: false, takeFocus: false)
            .playPauseKeyDown = handled
            return handled
        }

        if evt.key != .MediaStop and evt.key != .VolumeMute and evt.key != .M do
            return false
        return .forwardKeyToViewer(evt, skipFocused: false, takeFocus: false)
    }

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
        if takeFocus and copy.accepted and .currentView == view do
            target.setFocus()
        return copy.accepted
    }

    mtd retranslate()
    {
        let texts = appStrings()
        .surface?.setTitle(texts.ui_WindowTitle)
        .openButton.toolTip          = texts.ui_Open
        .closeButton.toolTip         = texts.ui_CloseFile
        .openDefaultButton.toolTip   = texts.ui_OpenDefault
        .filesButton.toolTip         = texts.ui_Files
        .kindButton.toolTip          = texts.ui_SameKind
        .folderHistoryButton.toolTip = texts.ui_FolderHistory
        .recentClearButton.toolTip   = texts.ui_ClearHistory
        .viewerCombo.toolTip         = texts.ui_Viewer
        .searchPrevious.toolTip      = texts.ui_SearchPrevious
        .searchNext.toolTip          = texts.ui_SearchNext
        .searchOptionsButton.toolTip = texts.ui_SearchOptions
        .refreshSearchPresentation()
        .refreshSearchReadout()
        .recentLabel.setText(texts.ui_Recent)
        for &instance in .instances where instance.view and not instance.failureReason.isEmpty() do
            assume cast(*ViewerErrorView, instance.view).retranslate()
        if .currentFile.isEmpty()
        {
            .folderLabel.setText(texts.ui_Folder)
            .emptyLabel.setText(Format.toString("<b>%</b>", texts.ui_DropTitle))
            .emptyHintLabel.setText(texts.ui_DropHint)
            .infoStatsLabel.setText("")
        }

        .invalidate()
    }
}
