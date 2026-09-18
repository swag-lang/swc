using Core, Pixel, Gui

const ViewerActionBarHeight                   = 42.0
const ViewerBarHeight                         = 48.0
const ViewerInfoHeight                        = 40.0
const ViewerMinWidth                          = 880
const ViewerSearchChunkSize                   = 256 * 1024'u64
const ViewerSearchFieldWidth                  = 180.0
const ViewerSearchNoOptionsFieldWidth         = 256.0
const ViewerSearchCountWidth                  = 52.0
const ViewerSearchGroupSpacing                = 16.0
const ViewerInfoGroupSpacing                  = 16.0
const ViewerInfoFileSpacing                   = 8.0
const ViewerInfoSideButtonSpacing             = 8.0
const ViewerSearchCarryMargin                 = 4'u64
const ViewerErrorTextWidth                    = 512.0
const ViewerFullScreenRevealEdge              = 32.0
const ViewerRetirePollInterval: Time.Duration = 16'ms
const ViewerLoadingSpinnerSize                = 56.0
const ViewerLoadingSpinnerMinRadius           = 15.0
const ViewerLoadingSpinnerMaxRadius           = 21.0
const ViewerLoadingSpinnerMinSweep            = 58.0
const ViewerLoadingSpinnerMaxSweep            = 232.0

// How long a viewer may keep the window waiting before the activity mark appears, how long the
// mark then stays once it has, and how often the wait is looked at.
//
// A file that arrives inside the delay was never a wait, and the document before it stays on
// screen for that long anyway: showing the mark would only announce a pause nobody felt. A mark
// that appears and leaves within one frame is a flicker over the document, so once shown it
// lingers past the end of the wait. Both thresholds are what keep a fast file change reading as
// instantaneous.
const ViewerLoadingShowDelayMicroseconds       = 400_000'u64
const ViewerLoadingMinVisibleMicroseconds      = 500_000'u64
const ViewerLoadingPollInterval: Time.Duration = 50'ms
const ViewerLoadingFadeIn:       Time.Duration = 120'ms
const ViewerSearchMarkPadX                     = 5.0
const ViewerSearchMarkPadY                     = 2.0
const ViewerSearchMarkRadius                   = 4.0
const ViewerSearchMarkEdge                     = 1.0
const ViewerSearchGlowReach                    = 5.0
const ViewerSearchGlowSteps                    = 4'u32
const ViewerSearchOverlayInsetX                = ViewerSearchMarkPadX + ViewerSearchGlowReach
const ViewerSearchOverlayInsetY                = ViewerSearchMarkPadY + ViewerSearchGlowReach
const ViewerSearchGlowPeriod:    f32           = 1.35
const ViewerSearchBoundsPoll:    Time.Duration = 16'ms
const ViewerSmokeStepLimit                     = 300'u32
const ViewerSmokeExposureSteps                 = 25'u32
const ViewerSmokeMinimumSteps                  = 2'u32

func viewerLoadingSpinnerGeometry(phase: f32)->{radius, start, sweep: f32}
{
    let pulse = 0.5'f32 - 0.5'f32 * Math.cos(phase * Math.ConstF32.TwoPi)

    var result: retval
    result.radius = Math.lerp(ViewerLoadingSpinnerMinRadius, ViewerLoadingSpinnerMaxRadius, pulse)
    result.sweep  = Math.lerp(ViewerLoadingSpinnerMinSweep, ViewerLoadingSpinnerMaxSweep, pulse)
    result.start  = phase * 540 - 90 - result.sweep * 0.5
    return result
}

const ViewerFullScreenRemovedFlags = SurfaceFlags.LargeCaption | SurfaceFlags.SmallCaption | SurfaceFlags.MinimizeButton | SurfaceFlags.MaximizeButton | SurfaceFlags.CloseButton | SurfaceFlags.Border | SurfaceFlags.Resizable
const ViewerFullScreenAddedFlags   = SurfaceFlags.NoShadow | SurfaceFlags.TopMost

// The panel that lists what is beside the current file, and what was read before it.
const ViewerPanelWidth   = 276.0
const ViewerRecentHeight = 188.0
const ViewerPaneMinSize  = 88.0

// Files the recent list keeps. Long enough to cross a working session, short enough that the list
// stays something a reader scans rather than searches.
const ViewerRecentCount        = 12'u64
const ViewerFolderHistoryCount = 8'u64

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
func reportViewerFailure(view: *Wnd, reason: string)
{
    viewerWindowFor(view).replaceFailedViewer(view, reason)
}

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
    // that reported a still picture for it to count, and the files the shuffle has already
    // continued from in its folder, so that every file gets its turn before any comes again.
    playMode:      Viewer.PlayMode
    slideSeconds:  f32 = Viewer.SlideDefaultSeconds
    slideTimer:    *Timer?
    stillView:     *Wnd?
    shuffleFolder: String
    shufflePlayed: Array'String

    // Guards the one nested dispatch [[ViewerWindow.forwardKeyToViewer]] makes, so a key the viewer
    // declines falls back to file navigation instead of being offered again.
    forwardingViewerKey: bool
    playPauseKeyDown:    bool
    recent:              Array'String
    folderHistory:       Array'ViewerFolderHistory
    preferences:         Array'ViewerPreference
    panelVisible:        bool
    recentPaneSize = ViewerRecentHeight
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
    let window = viewerWindowFor(view)
    window.commitViewerTransition(view)
    window.updateLoadingIndicator()
}

impl IWnd for ViewerWindow
{
    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if evt.kind == .Move or evt.kind == .Enter do
            .updateFullScreenChrome(evt.surfacePos)
        evt.accepted = false
    }

    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        discard evt
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

        if evt.key == .F11 and evt.modifiers == .None do
            .setFullScreen(not .fullScreen)
        elif evt.key == .Escape and evt.modifiers == .None and .fullScreen do
            .setFullScreen(false)
        elif evt.key == .O and evt.modifiers.has(.Control) do
            .chooseFile()
        elif evt.key == .F and evt.modifiers.has(.Control) do
            .showSearch()
        elif evt.key == .F3 and evt.modifiers.has(.Shift) do
            .findPrevious()
        elif evt.key == .F3 and evt.modifiers == .None do
            .findNext()
        elif (evt.key == .Left or evt.key == .Right) and evt.modifiers == .None
        {
            if .forwardingViewerKey or not .forwardKeyToViewer(evt) do
                evt.accepted = false
        }
        elif evt.key == .F5 and not .currentFile.isEmpty() do
            .reloadCurrentFile()
        else do
            evt.accepted = false
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

            if .fileWatch.poll(.currentFile.toString()) do
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
            .removeTimer(evt.timer)
            .loadingTimer = null
            .updateLoadingIndicator()
            return
        }

        if evt.timer == .searchTimer
        {
            .removeTimer(evt.timer)
            .searchTimer = null
            .searchStep()
            return
        }

        if evt.timer == .searchBoundsTimer
        {
            .removeTimer(evt.timer)
            .searchBoundsTimer = null
            .refreshSearchHighlight()
            return
        }

        if evt.timer == .slideTimer
        {
            .removeTimer(evt.timer)
            .slideTimer = null
            .continueSlide()
            return
        }

        if evt.timer != .startupTimer
        {
            evt.accepted = false
            return
        }

        .removeTimer(.startupTimer!)
        .startupTimer = null
        if not .pendingFile.isEmpty() do
            .processQueuedFile()
        elif not .pendingEmpty.isEmpty()
        {
            let message = #move .pendingEmpty
            .showEmpty(message.toString())
        }
    }

    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        if .fullScreen do
            .setFullScreen(false)
        catch .saveState()
        .stopSearch()
        .stopLoadingIndicator()
        .stopSlide()
        if .fileWatchTimer
        {
            .removeTimer(.fileWatchTimer)
            .fileWatchTimer = null
        }

        for &set in .pluginIcons do
            set.icons.free()
        if .startupTimer
        {
            .removeTimer(.startupTimer)
            .startupTimer = null
        }
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
        catch evt.serializer.serialize("ViewerWindow.videoSubtitles", &g_VideoSubtitleSettings)
        catch evt.serializer.serialize("ViewerWindow.markdown", &g_MarkdownViewerSettings)
        if evt.serializer.isReading()
        {
            .themeIndex     = Math.min(.themeIndex, cast(u32) AppearanceTheme.Dark)
            .recentPaneSize = Math.max(.recentPaneSize, ViewerPaneMinSize)
            if not .filePanel.items.isEmpty() do
                .filePanel.items[0]!.size = .recentPaneSize
            while .recent.count > ViewerRecentCount do
                .recent.removeAtOrdered(.recent.count - 1)
            while .folderHistory.count > ViewerFolderHistoryCount do
                .folderHistory.removeAtOrdered(.folderHistory.count - 1)
            .folderHistoryButton.enable(not .folderHistory.isEmpty())
            .searchBox.setValidator(.searchBox.validator)
            if cast(u32) .playMode > cast(u32) Viewer.PlayMode.Shuffle do
                .playMode = .Once
            .slideSeconds = Math.clamp(.slideSeconds, Viewer.SlideMinSeconds, Viewer.SlideMaxSeconds)
            g_VideoSubtitleSettings.delay        = Math.clamp(g_VideoSubtitleSettings.delay, -60, 60)
            g_MarkdownViewerSettings.themeIndex  = Math.min(g_MarkdownViewerSettings.themeIndex, 5)
            g_MarkdownViewerSettings.widthIndex  = Math.min(g_MarkdownViewerSettings.widthIndex, 3)
            g_MarkdownViewerSettings.zoomPercent = Math.clamp(g_MarkdownViewerSettings.zoomPercent, 50'u32, 300'u32)
        }
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged
        {
            .retranslate()
            .dropHighlight.retranslate()
        }
        elif evt.kind == .ThemeChanged
        {
            for &instance in .instances where instance.view and not instance.failureReason.isEmpty() do
                (cast #assume(*ViewerErrorView) instance.view).refreshTheme()
            .refreshArtwork()
            .refreshEmptyArtwork()
            .dropHighlight.refreshTheme()
        }

        .wnd.IWnd.onNotifyEvent(evt)
    }
}

impl ViewerWindow
{
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
        .themeIndex = Math.min(index, cast(u32) AppearanceTheme.Dark)
        .appearanceButton.setAppearanceTheme(cast(AppearanceTheme) .themeIndex)
    }

    mtd applyLanguage()
    {
        discard catch .appearanceButton.setAppearanceLanguage(.language.toString())
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
        .viewerBar.position.height = .currentCommands ? ViewerBarHeight : .themeMetrics().panel_GutterSize
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

        let srfn = .surface!
        if enabled
        {
            .fullScreenRestorePosition = srfn.isMaximized ? srfn.restoredPosition : srfn.position
            .fullScreenRestoreFlags    = srfn.flags
            .fullScreenWasMaximized    = srfn.isMaximized
            if srfn.isMaximized do
                srfn.showNormal()

            .fullScreen = true
            srfn.updateFlags(add: ViewerFullScreenAddedFlags, remove: ViewerFullScreenRemovedFlags)
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
            .applyLayout()
            srfn.setPosition(Env.monitorForRectangle(.fullScreenRestorePosition).physicalBounds)
        }
        else
        {
            .fullScreen = false
            srfn.updateFlags(add: .fullScreenRestoreFlags & (ViewerFullScreenRemovedFlags | ViewerFullScreenAddedFlags), remove: (ViewerFullScreenRemovedFlags | ViewerFullScreenAddedFlags) & ~.fullScreenRestoreFlags)
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
            .applyLayout()
            srfn.setPosition(.fullScreenRestorePosition)
            if .fullScreenWasMaximized do
                srfn.showMaximized()
        }

        srfn.invalidate()
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
        let top    = position.y <= ViewerFullScreenRevealEdge or (.fullScreenTopVisible and position.y <= ViewerActionBarHeight + .infoBarHost.position.height)
        let bottom = position.y >= height - ViewerFullScreenRevealEdge or (.fullScreenBottomVisible and position.y >= height - ViewerBarHeight)
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
            .commandBar.setPosition({rect.x, rect.y, rect.width, ViewerActionBarHeight}, computeLayout: false)
            .infoBarHost.setPosition({rect.x, rect.y + ViewerActionBarHeight, rect.width, .infoBarHost.position.height}, computeLayout: false)
            .commandBar.applyLayout()
            .infoBarHost.applyLayout()
            .commandBar.bringToFront()
            .infoBarHost.bringToFront()
        }

        if .fullScreenBottomVisible and .currentCommands
        {
            .viewerBar.setPosition({rect.x, rect.bottom() - ViewerBarHeight, rect.width, ViewerBarHeight}, computeLayout: false)
            .viewerBar.applyLayout()
            .viewerBar.bringToFront()
        }
    }

    private mtd createAppearanceChrome()
    {
        .appearanceButton = AppearanceButton.create(.surface!, "scope.appearance")
        .appearanceButton.sigThemeChanged += func|window = me|(button)
        {
            window.themeIndex = cast(u32) button.appearanceTheme
            catch window.saveState()
        }

        .appearanceButton.sigLanguageChanged += func|window = me|(button)
        {
            window.language = button.language
            catch window.saveState()
        }

        .appearanceButton.sigAboutRequested += func|window = me|(button)
        {
            discard button
            window.showAbout()
        }

        .accentRail = Separator.create(me, .Top, .Accent)
    }

    private mtd createCommandBar()
    {
        .commandBar = ViewerActionBar.create(me)
        let actionSize            = themeActionButtonSize(.themeMetrics())
        let dropDownWidth         = themeDropDownButtonWidth(.themeMetrics())
        let searchNavigationWidth = 2 * actionSize + ViewerSearchCountWidth + 8
        let searchBarWidth        = dropDownWidth + ViewerSearchFieldWidth + searchNavigationWidth + 2 * ViewerSearchGroupSpacing

        with .commandButtons = IconBar.create(.commandBar, themeActionIconSize(.themeMetrics()), itemPadding: .themeMetrics().btnIcon_Padding)
        {
            .dockStyle = .Left
        }

        with .openButton = .commandButtons.addButton(.theme().icon(.OpenFile, themeActionIconSize(.themeMetrics())))
        {
            .toolTip    = appStrings().ui_Open
            .sigPressed += func|window = me|(button)
            {
                discard button
                window.chooseFile()
            }
        }

        with .openDefaultButton = .commandButtons.addButton(.theme().icon(.OpenExternal, themeActionIconSize(.themeMetrics())))
        {
            .toolTip = appStrings().ui_OpenDefault
            .enable(false)
            .sigPressed += func|window = me|(button)
            {
                discard button
                window.openCurrentFileDefault()
            }
        }

        with .closeButton = .commandButtons.addButton(.theme().icon(.WndClose, themeActionIconSize(.themeMetrics())))
        {
            .toolTip = appStrings().ui_CloseFile
            .enable(false)
            .sigPressed += func|window = me|(button)
            {
                discard button
                window.closeFile()
            }
        }

        with .fullScreenButton = .commandButtons.addToggleButton(.theme().icon(.FullScreen, themeActionIconSize(.themeMetrics())))
        {
            .toolTip = appStrings().ui_FullScreen
            .sigCheckedChanged += func|window = me|(button)
            {
                window.setFullScreen(button.isChecked)
            }
        }

        with .searchGroup = StackLayoutCtrl.create(.commandBar, .Center, {0, 0, searchBarWidth, actionSize})
        {
            .backgroundStyle = .Transparent
            .spacing         = ViewerSearchGroupSpacing
            .hide()
        }

        .commandBar.centerGroup = .searchGroup

        with .searchOptionsButton = IconButton.create(.searchGroup, .theme().icon(.Options, themeActionIconSize(.themeMetrics())), {0, 0, dropDownWidth, actionSize}, flags: .CenterContent)
        {
            .layoutSpec.alignY = .Center
            .toolTip = appStrings().ui_SearchOptions
            .setArrowPosition(.RightDownward)
            .sigPressed += func|window = me|(button)
            {
                discard button
                window.showSearchOptionsMenu()
            }
        }

        with .searchBox = EditBox.create(.searchGroup, "", {0, 0, ViewerSearchFieldWidth, 36}, flags: .ClearButton)
        {
            .setIcon(me.theme().icon(.Search, themeActionIconSize(me.themeMetrics())))
            .setPlaceholder(appStrings().ui_Search)
            .setValidator(func|window = me|(edit)->EditBoxCheckResult => window.validateSearchEdit(edit))
            .sigTextChanged += func|window = me|(edit)
            {
                discard edit
                window.restartSearch()
            }

            .sigSubmitted += func|window = me|(edit)
            {
                discard edit
                window.findNext()
            }

            .sigCancelled += func|window = me|(edit)
            {
                discard edit
                window.hideSearch()
            }

            .enable(false)
        }

        with .searchNavigation = StackLayoutCtrl.create(.searchGroup, .Center, {0, 0, searchNavigationWidth, actionSize})
        {
            .backgroundStyle = .Transparent
            .spacing         = 0
        }

        with .searchPrevious = IconButton.create(.searchNavigation, .theme().icon(.SearchPrevious, themeActionIconSize(.themeMetrics())), {0, 0, actionSize, actionSize})
        {
            .layoutSpec.alignY = .Center
            .toolTip           = appStrings().ui_SearchPrevious
            .sigPressed        += func|window = me|(button)
            {
                discard button
                window.findPrevious()
            }

            .enable(false)
        }

        with .searchNext = IconButton.create(.searchNavigation, .theme().icon(.SearchNext, themeActionIconSize(.themeMetrics())), {0, 0, actionSize, actionSize})
        {
            .layoutSpec.alignY = .Center
            .toolTip           = appStrings().ui_SearchNext
            .sigPressed        += func|window = me|(button)
            {
                discard button
                window.findNext()
            }

            .enable(false)
        }

        with .searchCountLabel = Label.create(.searchNavigation, "", {0, 0, ViewerSearchCountWidth, 36}, null, .SecondaryText)
        {
            .margin.x = 8
            .style.setFont(me.theme().createDefaultFontFs(12), .Regular)
            .setTextAlignment(.Left, .OpticalCenter)
        }

        .commandBar.centerContent()

        // Wide enough for the longest viewer name a shipped viewer registers beside its glyph.
        // Viewer commands have their own row, so this selector can close the global bar's right edge.
        with .viewerCombo = ComboBox.create(.commandBar, {0, 0, 180, 36})
        {
            .dockStyle = .Right
            .toolTip   = appStrings().ui_Viewer
            .hide()
            .sigChanged += func|window = me|(combo, index)
            {
                discard combo
                window.selectViewer(index)
            }
        }
    }

    private mtd createInfoBar(panelGutter: f32)
    {
        // File identity and content statistics are read before the document. The information
        // surface follows the same panel composition as both side panes: a rounded semantic
        // ground inside one shared chrome seam. Viewer tools belong to the dedicated band below.
        with .infoBarHost = Wnd.create'Wnd(me, {0, 0, 0, ViewerInfoHeight + panelGutter * 2})
        {
            .dockStyle       = .Top
            .backgroundStyle = .ToolBar
            .padding         = {panelGutter, panelGutter, panelGutter, panelGutter}
        }

        with .infoBar = Wnd.create'ViewerInfoBar(.infoBarHost)
        {
            .dockStyle       = .Center
            .backgroundStyle = .InformationPanel
            .padding         = {8, 2, 8, 2}
        }

        with .infoContentGroup = Wnd.create'ViewerInfoLayout(.infoBar, {0, 0, 0, 36})
        {
            .dockStyle       = .Center
            .backgroundStyle = .Transparent
        }

        with .filesButton = IconButton.create(.infoContentGroup, .theme().icon(.History, themeActionIconSize(.themeMetrics())), {0, 0, themeActionButtonSize(.themeMetrics()), themeActionButtonSize(.themeMetrics())}, flags: .Toggle)
        {
            .toolTip = appStrings().ui_Files
            .setCheckIndicator(.Frame)
            .sigCheckedChanged += func|window = me|(button)
            {
                window.setFilePanelVisible(button.isChecked)
                catch window.saveState()
            }
        }

        .infoContentGroup.filesButton = .filesButton

        with .infoFileGroup = StackLayoutCtrl.create(.infoContentGroup, .Left, {0, 0, 0, 36})
        {
            .backgroundStyle = .Transparent
            .spacing         = 0
        }

        with .infoIconLabel = Label.create(.infoFileGroup, "", {0, 0, 24, 36})
        {
            .margin.z = me.themeMetrics().btnIcon_SpacingIcon
            .setIconAlignment(.Center, .Center)
        }

        with .infoNameLabel = Label.create(.infoFileGroup, "", {0, 0, 0, 36}, null, .Ellipsis)
        {
            .layoutSpec.policyX = .Expand
            .layoutSpec.weightX = 0
            .style.setFont(me.theme().createDefaultFont(13, .Bold), .Regular)
            .setTextAlignment(.Left, .OpticalCenter)
        }

        with .infoSizeLabel = Label.create(.infoFileGroup, "", {0, 0, 0, 36}, null, .SecondaryText)
        {
            .margin.x = 8
            .style.setFont(me.theme().createDefaultFontFs(12), .Regular)
            .setTextAlignment(.Left, .OpticalCenter)
        }

        with .infoStatsLabel = Label.create(.infoContentGroup, "", {0, 0, 0, 36}, null, .SecondaryText | .Ellipsis)
        {
            .style.setFont(me.theme().createDefaultFontFs(12), .Regular)
            .setTextAlignment(.Right, .OpticalCenter)
        }

        .infoContentGroup.fileGroup    = .infoFileGroup
        .infoContentGroup.generalLabel = .infoStatsLabel
    }

    private mtd createViewerBar()
    {
        with .viewerBar = Wnd.create'ViewerActionBar(me, {0, 0, 0, ViewerBarHeight})
        {
            .dockStyle       = .Bottom
            .backgroundStyle = .ToolBar
            .padding         = {12, 6, 12, 6}
            .fillCenterGroup = true
        }
    }

    private mtd createFilePanel(panelGutter: f32)
    {
        // The toolbar-colored lane is the static seam shared with the application chrome. The
        // rounded structural panel sits inside it, so the lists read as one integrated surface
        // instead of a square block divided from the document by an unrelated rule.
        with .filePanelHost = Wnd.create'Wnd(me, {0, 0, ViewerPanelWidth + panelGutter, 0})
        {
            .dockStyle       = .Left
            .backgroundStyle = .ToolBar

            // The information lane supplies the upper seam and the viewer bar supplies the
            // lower chrome. Only the exposed outer edges need their own integration gutter.
            .padding = {panelGutter, 0, 0, 0}
            .hide()
        }

        with .filePanel = SplitterCtrl.create(.filePanelHost, {0, 0, ViewerPanelWidth, 0}, vertical: true)
        {
            .dockStyle       = .Center
            .minSize.x       = ViewerPanelWidth
            .maxSize.x       = ViewerPanelWidth
            .backgroundStyle = .Transparent
        }

        with .recentPane = Wnd.create'Wnd(.filePanel)
        {
            .backgroundStyle = .Panel
            .padding         = {0, 8, 0, 8}
        }

        with let recentHeader = Wnd.create'Wnd(.recentPane, {0, 0, 0, themeCompactButtonSize(.themeMetrics())})
        {
            .dockStyle       = .Top
            .backgroundStyle = .Transparent
            .margin          = {10, 0, 10, 0}
        }

        with .recentClearButton = IconButton.create(recentHeader, .theme().icon(.RemoveAll, themeRowIconSize(.themeMetrics())), {0, 0, themeCompactButtonSize(.themeMetrics()), themeCompactButtonSize(.themeMetrics())})
        {
            .dockStyle  = .Right
            .toolTip    = appStrings().ui_ClearHistory
            .sigPressed += func|window = me|(button)
            {
                discard button
                window.confirmClearRecent()
            }
        }

        with .recentLabel = Label.create(recentHeader, appStrings().ui_Recent, {0, 0, 0, themeCompactButtonSize(.themeMetrics())}, null, .SecondaryText)
        {
            .dockStyle = .Center
            .style.setFont(me.theme().createDefaultFontFs(12), .Regular)
            .setTextAlignment(.Left, .Center)
        }

        with .recentList = ListCtrl.createSimple(.recentPane)
        {
            .dockStyle = .Center
            .setIconSize(themeRowIconSize(me.themeMetrics()))
            .setSelectionMode(.Single)
            .updateFlags(.HotTrack | .Ellipsis)
            .scrollWnd.padding.x = 0
            .scrollWnd.padding.z = 0
            .scrollWnd.updateFlags(.DisableHorizontal)
            .sigSelectionChanged += func|window = me|(list)
            {
                window.openListSelection(list, window.recent.toSlice())
            }

            .sigRightClicked += func|window = me|(list, position)
            {
                window.showFileMenu(list, window.recent.toSlice(), list.listView.localToSurface(position))
            }
        }

        with .folderPane = Wnd.create'Wnd(.filePanel)
        {
            .backgroundStyle = .Panel
            .padding         = {0, 8, 0, 8}
        }

        // The header carries the filter beside the folder name: the toggle changes what this
        // list holds, and the next/previous arrows walk the same list.
        with let folderHeader = Wnd.create'Wnd(.folderPane, {0, 0, 0, themeCompactButtonSize(.themeMetrics())})
        {
            .dockStyle       = .Top
            .backgroundStyle = .Transparent
            .margin          = {10, 0, 10, 0}
        }

        with .kindButton = IconButton.create(folderHeader, .theme().icon(.Filter, themeRowIconSize(.themeMetrics())), {0, 0, themeCompactButtonSize(.themeMetrics()), themeCompactButtonSize(.themeMetrics())}, flags: .Toggle)
        {
            .dockStyle = .Right
            .toolTip   = appStrings().ui_SameKind
            .setCheckIndicator(.Frame)
            .sigCheckedChanged += func|window = me|(button)
            {
                window.setFolderSameKind(button.isChecked)
            }
        }

        with .folderHistoryButton = IconButton.create(folderHeader, .theme().icon(.History, themeRowIconSize(.themeMetrics())), {0, 0, themeDropDownButtonWidth(.themeMetrics()), themeCompactButtonSize(.themeMetrics())}, flags: .CenterContent)
        {
            .dockStyle = .Right
            .margin.z  = 8
            .toolTip   = appStrings().ui_FolderHistory
            .setArrowPosition(.RightDownward)
            .enable(false)
            .sigPressed += func|window = me|(button)
            {
                discard button
                window.showFolderHistory()
            }
        }

        with .folderLabel = Label.create(folderHeader, appStrings().ui_Folder, {0, 0, 0, themeCompactButtonSize(.themeMetrics())}, null, .SecondaryText | .Ellipsis)
        {
            .dockStyle = .Center
            .style.setFont(me.theme().createDefaultFontFs(12), .Regular)
            .setTextAlignment(.Left, .Center)
        }

        with .folderList = ListCtrl.createSimple(.folderPane)
        {
            .dockStyle = .Center
            .setIconSize(themeRowIconSize(me.themeMetrics()))
            .setSelectionMode(.Single)
            .updateFlags(.HotTrack | .Ellipsis)
            .scrollWnd.padding.x = 0
            .scrollWnd.padding.z = 0
            .scrollWnd.updateFlags(.DisableHorizontal)
            .sigSelectionChanged += func|window = me|(list)
            {
                window.openListSelection(list, window.siblings.toSlice())
            }

            .sigRightClicked += func|window = me|(list, position)
            {
                window.showFileMenu(list, window.siblings.toSlice(), list.listView.localToSurface(position))
            }
        }

        with let recentItem = .filePanel.addPane(.recentPane, ViewerRecentHeight)
        {
            .minimumSize  = ViewerPaneMinSize
            .preserveSize = true
        }

        .filePanel.addPane(.folderPane).minimumSize = ViewerPaneMinSize
    }

    private mtd createDocumentPanel(panelGutter: f32)
    {
        // The document is the middle panel of the same composition. It owns the seams on both
        // sides, so showing either optional side panel never doubles the four-pixel rhythm.
        with .documentHost = Wnd.create'Wnd(me)
        {
            .dockStyle       = .Center
            .backgroundStyle = .ToolBar
            .padding         = {panelGutter, 0, panelGutter, 0}
        }

        with .documentPanel = Wnd.create'Wnd(.documentHost)
        {
            .dockStyle       = .Center
            .backgroundStyle = .Panel
            .style.addStyleSheetColors("wnd_Bk $view_Bk")
        }

        with .emptyView = StackLayoutCtrl.create(.documentPanel, .VerticalCenter)
        {
            .dockStyle       = .Center
            .backgroundStyle = .Transparent
            .padding         = {48, 48, 48, 48}
            .spacing         = 12
        }

        with .emptyIconLabel = Label.create(.emptyView, "", {0, 0, 48, 48})
        {
            .layoutSpec.alignX = .Center
            .setIconAlignment(.Center, .Center)
        }

        with .emptyLabel = Label.create(.emptyView, Format.toString("<b>%</b>", appStrings().ui_DropTitle), {0, 0, 480, 0}, null, .WordWrap | .AutoHeight)
        {
            .layoutSpec.alignX = .Center
            .setTextAlignment(.Center, .Center)
        }

        with .emptyHintLabel = Label.create(.emptyView, appStrings().ui_DropHint, {0, 0, 480, 0}, null, .WordWrap | .AutoHeight | .SecondaryText)
        {
            .layoutSpec.alignX = .Center
            .setTextAlignment(.Center, .Center)
        }

        .loadingOverlay = ViewerLoadingOverlay.create(.documentPanel)
        .searchOverlay  = ViewerSearchOverlay.create(.documentPanel)
        .dropHighlight  = ViewerDropHighlight.create(.documentPanel)
    }

    private mtd hookChildEvents()
    {
        .hookOnChildEvent = func|window = me|(wnd, evt)
        {
            discard wnd
            switch evt
            {
            case KeyEvent as key where window.routePlaybackKey(key):         return true
            case KeyEvent as key where window.routeSearchNavigationKey(key): return true
            case MouseEvent as mouse where mouse.kind == .Move or mouse.kind == .Enter: window.updateFullScreenChrome(mouse.surfacePos)
            }

            return false
        }
    }

    func create(parent: *Wnd, index: ViewerPluginRegistry)->*ViewerWindow
    {
        let result = Wnd.create'ViewerWindow(parent, "scope.main")
        result.surface!.setView(result)
        result.surface.minSize = {ViewerMinWidth, 420}
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
        let dlg         = AboutDlg.createApplication(.surface!, {
            productName: ProductName,
            version: version orelse liveVersion.toString(),
            buildDate: buildDate,
            sourceUrl: "https://github.com/swag-lang/swc/tree/master/bin/apps/modules/swagscope",
            copyrightHolder: "Christophe Beaudet"})

        // The registry remains the source of the compact capability line, but extension details
        // stay out of the identity box: the viewer names communicate the supported content
        // families without turning About into a file-association inventory.
        let viewers = .aboutViewerList()
        dlg.addSection(appStrings().ui_AboutViewers, viewers.toString())
        return dlg
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

    // Reloads the current path while retaining the active reading session.
    mtd reloadCurrentFile()
    {
        if .currentFile.isEmpty() or not .pendingFile.isEmpty() or .activeChoiceIndex >= .instances.count do
            return
        .readingState.capture(&.instances[.activeChoiceIndex], .choices[.activeChoiceIndex].key.toString(), .searchBox.text())
        .queueFile(.currentFile.toString(), remember: false, preserveReading: true)
    }

    // Opens `fileName` after the surface has had a chance to paint its first frame.
    mtd queueFile(fileName: string, remember = true, preserveReading = false)
    {
        .reloading = preserveReading
        if not preserveReading do
            .readingState = {}

        // A query belongs to the document it was started against. Stop its file stream as soon as
        // another document is requested instead of letting it scan the old file while the new one
        // is being classified.
        .stopSearch()
        .searchBox.setText("", notify: false)
        .searchQuery.clear()
        .searchMatches.clear()
        .searchIndex    = Swag.U64.Max
        .searchMatch    = Swag.U64.Max
        .searchComplete = false
        .refreshSearchReadout()
        .stopSlide()
        .stillView = null

        .pendingFile = fileName
        .closeButton.enable(true)
        .pendingEmpty.clear()
        .pendingRemember = remember

        // The hint to drop a file is not what a window opening one should paint first: hidden
        // now, the first frame shows the surface the document is about to fill, and the hint's
        // glyph is never rasterized for a launch that names its file.
        .emptyView.hide()
        .updateLoadingIndicator()
        if not .startupTimer do
            .startupTimer = .addTimer(1'ms)
    }

    // Advances one asynchronous file classification and publishes it only after the preceding
    // viewer has retired. Every filesystem probe stays on the worker side of this boundary.
    private mtd processQueuedFile()
    {
        if .choiceLoad.started
        {
            if not .choiceLoad.isDone()
            {
                .startupTimer = .addTimer(ViewerRetirePollInterval)
                return
            }

            if .choiceLoad.fileName != .pendingFile
            {
                discard .choiceLoad.finish()
                .choiceLoad.start(&.index, .pendingFile.toString(), .recent.toSlice())
                .startupTimer = .addTimer(ViewerRetirePollInterval)
                return
            }

            // A save can temporarily remove the path. Keep the current document and retry.
            if .reloading and not .choiceLoad.result.exists
            {
                discard .choiceLoad.finish()
                .pendingFile.clear()
                .reloading = false
                .updateLoadingIndicator()
                return
            }

            .stopSearch()
            .searchMatch = Swag.U64.Max
            .searchQuery.clear()
            if not .destroyInstances(preserveVisible: true)
            {
                .startupTimer = .addTimer(ViewerRetirePollInterval)
                return
            }

            let remember   = .pendingRemember
            let classified = .choiceLoad.finish()
            .pendingFile.clear()
            if not classified.exists
            {
                .showEmpty(appStrings().ui_OpenStopped)
                return
            }

            .openClassifiedFile(#move classified, remember)
            return
        }

        .choiceLoad.start(&.index, .pendingFile.toString(), .recent.toSlice())
        .startupTimer = .addTimer(ViewerRetirePollInterval)
    }

    // Starts the application smoke review. Each registered viewer owns one immutable fixture;
    // the real window opens them in registry order and explicitly selects the owner, including
    // the Binary and Hexadecimal viewers that normally appear as alternatives.
    mtd reviewSmokeFixtures(directory: string)
    {
        var absolute = catch Path.absolute(directory) as pathError
        if pathError != null or not Directory.exists(absolute)
        {
            .finishSmokeReview(1, Format.toString("Swag Scope smoke fixture directory is missing: %", directory).toString())
            return
        }

        .smokeDirectory = #move absolute
        .smokeSpecIndex = 0
        .smokeWaitSteps = 0
        .smokeOpened    = false
        .smokeSelected  = false
        .smokeRunning   = true

        // A 10 ms cadence leaves the viewers' own 4-8 ms progressive timers a dispatch turn
        // between readiness checks instead of letting the review timer dominate a smoke loop.
        .smokeTimer = .addTimer(10'ms)
    }

    private mtd finishSmokeReview(exitCode: s32, message: string)
    {
        if message.count do
            Console.println(message)
        if .smokeTimer
        {
            .removeTimer(.smokeTimer)
            .smokeTimer = null
        }

        .smokeRunning = false
        .app().postQuitEvent(exitCode)
    }

    private mtd waitForSmokeViewer(key, fileName: string)
    {
        .smokeWaitSteps += 1
        if .smokeWaitSteps <= ViewerSmokeStepLimit do
            return

        .finishSmokeReview(1, Format.toString("Swag Scope smoke viewer '%' did not finish '%' after % readiness checks", key, fileName, ViewerSmokeStepLimit).toString())
    }

    private mtd reviewSmokeStep()
    {
        if .smokeSpecIndex >= .index.plugins.count
        {
            .finishSmokeReview(0, Format.toString("Swag Scope smoke reviewed % viewer plugins", .index.plugins.count).toString())
            return
        }

        let plugin  = &.index.plugins[.smokeSpecIndex]
        let key     = plugin.key
        let fixture = plugin.smokeFixture

        let fileName = Path.combine(.smokeDirectory.toString(), fixture.toString())
        if not File.exists(fileName)
        {
            .finishSmokeReview(1, Format.toString("Swag Scope smoke fixture is missing: %", fileName).toString())
            return
        }

        var absolute = catch Path.absolute(fileName) as pathError
        if pathError != null
        {
            .finishSmokeReview(1, Format.toString("Swag Scope smoke cannot resolve fixture path: %", fileName).toString())
            return
        }

        if not .smokeOpened
        {
            .smokeOpened = true
            .queueFile(absolute.toString(), remember: false)
            return
        }

        if .currentFile != absolute
        {
            .waitForSmokeViewer(key.toString(), fileName.toString())
            return
        }

        if not .smokeSelected
        {
            var selected = Swag.U32.Max
            for choice, index in .choices where choice.key == key
            {
                selected = cast(u32) index
                break
            }

            if selected == Swag.U32.Max
            {
                .finishSmokeReview(1, Format.toString("Swag Scope smoke fixture '%' has no '%' viewer", fileName, key).toString())
                return
            }

            if not .activateChoice(selected)
            {
                .waitForSmokeViewer(key.toString(), fileName.toString())
                return
            }

            .smokeSelected  = true
            .smokeWaitSteps = 0
        }

        if .activeChoiceIndex >= .instances.count
        {
            .waitForSmokeViewer(key.toString(), fileName.toString())
            return
        }

        let instance = &.instances[.activeChoiceIndex]
        if not instance.failureReason.isEmpty()
        {
            .finishSmokeReview(1, Format.toString("Swag Scope smoke viewer '%' cannot open '%': %", key, fileName, instance.failureReason).toString())
            return
        }

        let loading  = instance.view and instance.isLoading and instance.isLoading(instance.view)
        let blocking = loading and instance.needsLoadingOverlay and instance.needsLoadingOverlay(instance.view!)

        // Streaming text already has a presentable first chunk while it continues reading. Keep
        // it visible for a bounded interval so late errors cross the viewer contract; only a
        // viewer that says it has no presentable content (video before its first frame) blocks the
        // review until ready.
        if .smokeWaitSteps < ViewerSmokeMinimumSteps or (loading and (blocking or .smokeWaitSteps < ViewerSmokeExposureSteps))
        {
            .waitForSmokeViewer(key.toString(), fileName.toString())
            return
        }

        Console.println("Swag Scope smoke reviewed '", key, "' with '", fixture, "'")
        .smokeSpecIndex += 1
        .smokeWaitSteps = 0
        .smokeOpened    = false
        .smokeSelected  = false
    }

    mtd chooseFile()
    {
        with var options: FileDlgOptions
        {
            .state             = &me.fileDlgState
            .mode              = .SelectFile
            .title             = appStrings().dlg_TitleOpen
            .confirmButtonText = appStrings().dlg_ButtonOpen
            .filters.add({appStrings().dlg_AllFiles, ""})
        }

        let dialog = FileDlg.create(.surface!, options)
        if dialog.doModal() == Dialog.BtnOk do
            .queueFile(dialog.selectedPath())
    }

    mtd closeFile()
    {
        .pendingFile.clear()
        .pendingEmpty.clear()
        .reloading    = false
        .readingState = {}
        .stopSlide()
        .stillView = null
        if .fileWatchTimer
        {
            .removeTimer(.fileWatchTimer)
            .fileWatchTimer = null
        }

        .searchBox.setText("", notify: false)
        .closeButton.enable(false)
        .showEmpty(appStrings().ui_DropTitle)
        .openButton.setFocus()
    }

    mtd showEmpty(message: string)
    {
        .stopSearch()
        .searchQuery.clear()
        .searchMatches.clear()
        .searchIndex    = Swag.U64.Max
        .searchMatch    = Swag.U64.Max
        .searchComplete = false
        let retired = .destroyInstances()
        if not retired or (.choiceLoad.started and not .choiceLoad.isDone())
        {
            .pendingEmpty = message
            if not .startupTimer do
                .startupTimer = .addTimer(ViewerRetirePollInterval)
            return
        }

        if .choiceLoad.started do
            discard .choiceLoad.finish()
        .stopLoadingIndicator()

        .emptyLabel.setText(Format.toString("<b>%</b>", message))
        .emptyView.show()
        .refreshEmptyArtwork()
        .currentFile.clear()
        .currentFileSize.clear()
        .choices.clear()
        .viewerCombo.clear()
        .viewerCombo.hide()
        .openDefaultButton.enable(false)
        .closeButton.enable(false)
        .activeChoiceIndex = Swag.U32.Max
        .folderFiles.clear()
        .siblings.clear()
        .siblingsDirty = true
        .infoNameLabel.setText("")
        .infoNameLabel.toolTip = ""
        .infoStatsLabel.setText("")
        .infoStatsLabel.toolTip = ""
        .infoSizeLabel.setText("")
        .infoSizeLabel.toolTip = ""
        .layoutFileInfo()
        .infoIconLabel.setIcon({})
        .infoBarHost.show(not .fullScreen or .fullScreenTopVisible)
        .updateViewerBar()
        .surface!.setTitle(appStrings().ui_WindowTitle)
        .updateSearchAvailability()
        if .panelVisible do
            .refreshFileLists()
        .applyLayout()
    }

    // Cooperatively retires every viewer without waiting on the GUI thread.
    mtd destroyInstances(preserveVisible = false)->bool
    {
        if not preserveVisible do
            .discardOutgoingViewer()

        for &instance in .instances
        {
            if not instance.retireView() do
                return false
        }

        let keepCurrent = preserveVisible and .currentView != null
        for &instance in .instances
        {
            if keepCurrent and instance.view == .currentView
            {
                .outgoingView            = instance.view
                .outgoingActions         = instance.actions
                .outgoingInfo            = instance.info
                .outgoingCommands        = instance.commands
                .outgoingSidePanelHost   = instance.sidePanelHost
                .outgoingSidePanelButton = instance.sidePanelButton
                instance.view            = null
                instance.actions         = null
                instance.info            = null
                instance.commands        = null
                instance.sidePanelHost   = null
                instance.sidePanel       = null
                instance.sidePanelButton = null
            }
            else do
                instance.destroyWindows()
        }

        .instances.clear()
        if not keepCurrent
        {
            .currentActions  = null
            .currentInfo     = null
            .currentCommands = null
            .currentView     = null
            .setCurrentSidePanel(null, null)
            .updateViewerBar()
        }

        return true
    }

    // Moves the host-owned panel action with the viewer it belongs to. The action remains on the
    // information edge while its panel occupies the matching right-side lane.
    private mtd setCurrentSidePanel(panel: *Wnd?, button: *IconButton?)
    {
        .currentSidePanelHost?.hide()
        .currentSidePanelButton?.hide()
        .currentSidePanelHost        = panel
        .currentSidePanelButton      = button
        .infoContentGroup.sideButton = button

        if button and not .fullScreen
        {
            button.show()
            panel?.show(button.isChecked)
        }

        .layoutFileInfo()
    }

    // Releases the retired presentation once its replacement is ready to cover it.
    private mtd discardOutgoingViewer()
    {
        if not .outgoingView do
            return
        let oldView            = .outgoingView
        let oldActions         = .outgoingActions
        let oldInfo            = .outgoingInfo
        let oldCommands        = .outgoingCommands
        let oldSidePanelHost   = .outgoingSidePanelHost
        let oldSidePanelButton = .outgoingSidePanelButton
        .outgoingView            = null
        .outgoingActions         = null
        .outgoingInfo            = null
        .outgoingCommands        = null
        .outgoingSidePanelHost   = null
        .outgoingSidePanelButton = null
        if .currentView == oldView do
            .currentView = null
        if oldCommands and .currentCommands == oldCommands do
            .currentCommands = null
        if oldActions and .currentActions == oldActions do
            .currentActions = null
        if oldInfo and .currentInfo == oldInfo do
            .currentInfo = null
        if oldSidePanelHost and .currentSidePanelHost == oldSidePanelHost do
            .setCurrentSidePanel(null, null)
        oldActions?.destroy()
        oldInfo?.destroy()
        oldCommands?.destroy()
        oldSidePanelButton?.destroy()
        oldSidePanelHost?.destroy()
        oldView.destroy()
    }

    // Swaps presentations only after the incoming progressive viewer has something to show.
    mtd commitViewerTransition(expected: *Wnd? = null)
    {
        if not .outgoingView or .activeChoiceIndex >= .instances.count do
            return
        let instance = &.instances[.activeChoiceIndex]
        if not instance.view or (expected and instance.view != expected) do
            return
        if instance.needsLoadingOverlay and instance.needsLoadingOverlay(instance.view) do
            return

        .discardOutgoingViewer()
        .currentView     = instance.view
        .currentActions  = instance.actions
        .currentInfo     = instance.info
        .currentCommands = instance.commands
        .setCurrentSidePanel(instance.sidePanelHost, instance.sidePanelButton)
        .armSlide()
        .currentView!.dockStyle = .Center
        if .currentCommands do
            .currentCommands.dockStyle = .None
        .currentView.show()
        .currentInfo?.show()
        .currentCommands?.show()
        .updateViewerBar()
        .updateFileInfo(instance.details.toString())
        .updateSearchAvailability()
        .applyLayout()
        .invalidate()
    }

    // Replaces a viewer that stopped after creation with the application's standard error surface.
    mtd replaceFailedViewer(view: *Wnd, reason: string)
    {
        var message = String.from(reason)
        if message.isEmpty() do
            message = appStrings().ui_OpenStopped

        for &instance, index in .instances where instance.view == view
        {
            if not instance.retireView() do
                return
            instance.destroyWindows()
            instance[] = {}

            let errorView = ViewerErrorView.create(.documentPanel, message.toString())
            errorView.dockStyle    = .Center
            instance.view          = errorView
            instance.failureReason = #move message

            if index != .activeChoiceIndex
            {
                errorView.hide()
                return
            }

            if .outgoingView
            {
                .commitViewerTransition(errorView)
                .updateLoadingIndicator()
                return
            }

            .stopLoadingIndicator()
            .currentView     = errorView
            .currentActions  = null
            .currentInfo     = null
            .currentCommands = null
            .setCurrentSidePanel(null, null)
            .updateViewerBar()
            .updateFileInfo("")
            .updateSearchAvailability()
            .applyLayout()
            .invalidate()
            return
        }
    }

    // Discards a hidden progressive view before opening another renderer. HTML and Markdown
    // otherwise keep parsing and laying out a document the reader can no longer see.
    private mtd retireActiveLoadingChoice(nextIndex: u32)->bool
    {
        if .activeChoiceIndex == nextIndex or .activeChoiceIndex >= .instances.count do
            return true
        let instance = &.instances[.activeChoiceIndex]
        if not instance.view or not instance.isLoading or not instance.isLoading(instance.view) do
            return true

        if not instance.retireView() do
            return false
        instance.destroyWindows()
        instance[] = {}
        .currentView     = null
        .currentActions  = null
        .currentInfo     = null
        .currentCommands = null
        .setCurrentSidePanel(null, null)
        .updateViewerBar()
        return true
    }

    // Ends the wait presentation at once, whatever its clocks say: the document it announced is gone.
    mtd stopLoadingIndicator()
    {
        if .loadingTimer
        {
            .removeTimer(.loadingTimer)
            .loadingTimer = null
        }

        .loadingWantedSince = 0
        .hideLoadingOverlay()
    }

    mtd hideLoadingOverlay()
    {
        .loadingShownSince = 0
        .loadingOverlay.conceal()
    }

    // Decides whether the wait deserves its mark right now, and keeps looking while it lasts.
    //
    // The mark appears only once the viewer has kept the window waiting for
    // [[ViewerLoadingShowDelayMicroseconds]], and once shown it stays for
    // [[ViewerLoadingMinVisibleMicroseconds]] even when the wait ends before that. The poll
    // timer runs for as long as either clock has something left to decide.
    mtd updateLoadingIndicator()
    {
        .commitViewerTransition()
        let pending     = not .pendingFile.isEmpty() or not .pendingEmpty.isEmpty()
        var loading     = pending
        var wantOverlay = pending and .currentView != null
        if not loading and .activeChoiceIndex < .instances.count
        {
            let instance = &.instances[.activeChoiceIndex]
            loading     = instance.view and instance.isLoading and instance.isLoading(instance.view)
            wantOverlay = loading and instance.needsLoadingOverlay and instance.needsLoadingOverlay(instance.view!)
        }

        let now = Time.monotonicMicroseconds()
        var lingering: bool
        if wantOverlay and .currentView
        {
            if not .loadingWantedSince do
                .loadingWantedSince = now
            if .loadingShownSince or now - .loadingWantedSince >= ViewerLoadingShowDelayMicroseconds
            {
                if not .loadingShownSince
                {
                    .loadingShownSince = now
                    .loadingOverlay.reveal()
                }

                .loadingOverlay.cover(.currentView.position)
                .loadingOverlay.bringToFront()
                .layoutFullScreenChrome()
            }
        }
        else
        {
            .loadingWantedSince = 0
            lingering = .loadingShownSince != 0 and .currentView != null and now - .loadingShownSince < ViewerLoadingMinVisibleMicroseconds
            if lingering do
                .loadingOverlay.cover(.currentView!.position)
            else do
                .hideLoadingOverlay()
        }

        let watching = loading or lingering
        if watching and not .loadingTimer do
            .loadingTimer = .addTimer(ViewerLoadingPollInterval)
        elif not watching and .loadingTimer
        {
            .removeTimer(.loadingTimer)
            .loadingTimer = null
        }
    }

    mtd activateChoice(index: u32)->bool
    {
        if index >= .choices.count do
            return false

        let choice   = &.choices[index]
        let instance = &.instances[index]
        if instance.view
        {
            if not .retireActiveLoadingChoice(index) do
                return false
            .currentActions?.hide()
            .currentInfo?.hide()
            .currentCommands?.hide()
            .currentView?.hide()
            .currentView     = instance.view
            .currentActions  = instance.actions
            .currentInfo     = instance.info
            .currentCommands = instance.commands
            .setCurrentSidePanel(instance.sidePanelHost, instance.sidePanelButton)
            .currentView!.show()
            .currentInfo?.show()
            .currentCommands?.show()
            .updateViewerBar()
            .activeChoiceIndex = index
            .viewerCombo.setSelectedIndex(index, notify: false)
            .updateFileInfo(instance.details.toString())
            .updateSearchAvailability()
            .applyLayout()
            .updateLoadingIndicator()
            .invalidate()
            return true
        }

        if choice.pluginIndex >= .index.plugins.count do
            return false

        var next: ViewerSession
        let plugin     = &.index.plugins[choice.pluginIndex]
        let actionIcon = .pluginIcon(plugin, themeActionIconSize(.themeMetrics()))
        var pluginHost = ViewerPluginHost{
            session: &next,
            documentParent: .documentPanel,
            sidePanelParent: me,
            actionParent: .commandBar,
            infoParent: .infoContentGroup,
            commandParent: .viewerBar,
            sourceFileName: .currentFile.toString(),
            pluginIcon: actionIcon,
            window: me,
            hostServices: {
                reportFailure: &reportViewerFailure,
                reportDetails: &reportViewerDetails,
                reportChromeChanged: &reportViewerChromeChanged,
                reportLoadingChanged: &reportViewerLoadingChanged,
                navigateFile: &navigateViewerFile,
                reportFinished: &reportViewerFinished,
                reportShown: &reportViewerShown,
                playback: {readSettings: &readViewerPlayback, writeSettings: &writeViewerPlayback}}}
        let host: Viewer.Host = &pluginHost
        catch next.create(plugin, host) as viewerError
        if viewerError != null
        {
            next.failureReason = Errors.message(viewerError)
            if next.failureReason.isEmpty() do
                next.failureReason = appStrings().ui_OpenStopped
        }

        // A rejected or failed viewer keeps its explanation and nothing else: the session becomes
        // the standard error surface.
        if not next.failureReason.isEmpty()
        {
            if next.view and next.retire do
                discard next.retire(next.view)
            let reason = #move next.failureReason
            next.destroyWindows()
            next               = {}
            next.failureReason = #move reason
            next.view          = ViewerErrorView.create(.documentPanel, next.failureReason.toString())
        }

        if not next.view
        {
            next.destroyWindows()
            return false
        }

        if not .retireActiveLoadingChoice(index)
        {
            if next.retire do
                discard next.retire(next.view)
            next.destroyWindows()
            return false
        }

        let stage = .outgoingView != null
        if stage
        {
            next.view.dockStyle = .None
            next.view.setPosition(.outgoingView!.position, computeLayout: false)
            next.actions?.hide()
            next.info?.hide()
            if next.commands
            {
                next.commands.dockStyle = .None
                if .outgoingCommands do
                    next.commands.setPosition(.outgoingCommands.position, computeLayout: false)
            }

            .outgoingView.bringToFront()
            .outgoingActions?.bringToFront()
            .outgoingInfo?.bringToFront()
            .outgoingCommands?.bringToFront()
            .outgoingSidePanelHost?.bringToFront()
            .outgoingSidePanelButton?.bringToFront()
        }
        else
        {
            .currentActions?.hide()
            .currentInfo?.hide()
            .currentCommands?.hide()
            .currentView?.hide()
            .currentView     = next.view
            .currentActions  = next.actions
            .currentInfo     = next.info
            .currentCommands = next.commands
            .setCurrentSidePanel(next.sidePanelHost, next.sidePanelButton)
            .currentInfo?.show()
            next.view.dockStyle = .Center
            if next.commands do
                next.commands.dockStyle = .None
            .updateViewerBar()
        }

        .activeChoiceIndex = index
        instance[]         = #move next
        .viewerCombo.setSelectedIndex(index, notify: false)
        .updateFileInfo(instance.details.toString())
        .updateSearchAvailability()
        if stage do
            .commitViewerTransition(instance.view)
        else do
            .applyLayout()
        .updateLoadingIndicator()
        .invalidate()
        return true
    }

    mtd findNext()
    {
        .navigateSearch(1)
    }

    mtd findPrevious()
    {
        .navigateSearch(-1)
    }

    private mtd searchOptions()->Viewer.SearchOptions =>
    {
        matchCase: .searchMatchCaseOption,
        wholeWord: .searchWholeWordOption,
        regularExpression: .searchRegexOption}

    private mtd showSearchOptionsMenu()
    {
        const SearchModeId = "scope.search.mode.search"
        const FilterModeId = "scope.search.mode.filter"
        const MatchCaseId  = "scope.search.matchCase"
        const WholeWordId  = "scope.search.wholeWord"
        const RegExpId     = "scope.search.regularExpression"

        let texts     = appStrings()
        let menu      = MenuCtrl.createPopup(me, owner: me)
        let canFilter = .activeChoiceIndex < .instances.count and .instances[.activeChoiceIndex].filterSearch != null
        if canFilter
        {
            menu.addRadioItem(texts.ui_SearchMode, SearchModeId, checked: not .searchFilterMode)
            menu.addRadioItem(texts.ui_FilterMode, FilterModeId, checked: .searchFilterMode)
            menu.addSeparator()
        }

        menu.addItem(texts.ui_SearchMatchCase, MatchCaseId, checked: .searchMatchCaseOption)
        menu.addItem(texts.ui_SearchWholeWord, WholeWordId, checked: .searchWholeWordOption)
        menu.addItem(texts.ui_SearchRegularExpression, RegExpId, checked: .searchRegexOption)

        switch menu.doModal(.searchOptionsButton, autoDestroy: true) orelse ""
        {
        case SearchModeId:
            if not .searchFilterMode do
                return
            .searchFilterMode = false

        case FilterModeId:
            if .searchFilterMode do
                return
            .searchFilterMode = true

        case MatchCaseId:
            .searchMatchCaseOption = not .searchMatchCaseOption

        case WholeWordId:
            .searchWholeWordOption = not .searchWholeWordOption

        case RegExpId:
            .searchRegexOption = not .searchRegexOption

        default:
            return
        }

        // A query that was literal may be incomplete regexp syntax, and vice versa. Re-run the
        // field validator before deciding whether there is work to schedule.
        .searchBox.setValidator(.searchBox.validator)
        .refreshSearchPresentation()
        .restartSearch()
        catch .saveState()
    }

    private mtd validateSearchEdit(edit: *EditBox)->EditBoxCheckResult
    {
        if not (edit.text()).count do
            return .Valid
        if .activeChoiceIndex < .instances.count
        {
            let instance = &.instances[.activeChoiceIndex]
            if instance.view and instance.prepareSearch
            {
                var plan: Viewer.SearchPlan
                return instance.prepareSearch(instance.view, edit.text(), &plan)
            }
        }

        return Viewer.patternIsValid(edit.text(), .searchOptions()) ? .Valid : .InvalidVisible
    }

    private mtd refreshSearchPresentation()
    {
        var presentation: Viewer.SearchPresentation
        presentation.placeholder = appStrings().ui_Search
        if .activeChoiceIndex < .instances.count
        {
            let instance = &.instances[.activeChoiceIndex]
            if instance.view and instance.describeSearch do
                instance.describeSearch(instance.view, &presentation)
        }

        if not presentation.canFilter do
            .searchFilterMode = false

        if .searchFilterMode
        {
            .searchToolTip = #move presentation.filterToolTip
            .searchBox.setPlaceholder(presentation.filterPlaceholder.toString())
        }
        else
        {
            .searchToolTip = #move presentation.toolTip
            .searchBox.setPlaceholder(presentation.placeholder.toString())
        }

        .searchBox.toolTip = .searchToolTip
        .searchOptionsButton.show(presentation.useTextOptions or presentation.canFilter)
        if presentation.canFilter
        {
            .searchOptionsButton.setIcon(.theme().icon(.searchFilterMode ? .Filter : .Search, themeActionIconSize(.themeMetrics())))
            .searchBox.setIcon({})
        }
        else
        {
            .searchOptionsButton.setIcon(.theme().icon(.Options, themeActionIconSize(.themeMetrics())))
            .searchBox.setIcon(.theme().icon(.Search, themeActionIconSize(.themeMetrics())))
        }

        .searchOptionsButton.toolTip = presentation.canFilter ? (.searchFilterMode ? appStrings().ui_FilterMode : appStrings().ui_SearchMode) : appStrings().ui_SearchOptions

        // With no options button, let the enlarged field meet navigation directly. Keeping the
        // usual inter-group gap as well would leave an empty button-sized visual group.
        let hasMenu = presentation.useTextOptions or presentation.canFilter
        .searchGroup.spacing = hasMenu ? ViewerSearchGroupSpacing : 0
        .searchBox.resize(hasMenu ? ViewerSearchFieldWidth : ViewerSearchNoOptionsFieldWidth, 36)
        .searchBox.setValidator(.searchBox.validator)
        .searchGroup.computeLayout()
        .commandBar.centerContent()
    }

    mtd restartSearch(selectLast = false)
    {
        .stopSearch()
        .searchMatches.clear()
        .searchIndex      = Swag.U64.Max
        .searchMatch      = Swag.U64.Max
        .searchComplete   = false
        .searchSelectLast = selectLast
        .searchQuery      = .searchBox.text()
        .searchSpan       = Math.max(.searchQuery.length, 1)
        .searchError.clear()
        .refreshSearchReadout()

        if not .searchBox.isEnabled() or .currentFile.isEmpty() or .activeChoiceIndex >= .instances.count do
            return

        let instance = &.instances[.activeChoiceIndex]
        if .searchFilterMode and instance.filterSearch and instance.view
        {
            var options = .searchOptions()
            var expression: Parser.RegExp
            if options.regularExpression
            {
                catch expression.compile(.searchQuery.toString(), ignoreCase: not options.matchCase) as expressionError
                if expressionError != null
                {
                    .searchComplete = true
                    .refreshSearchReadout()
                    return
                }

                options.expression = &expression
            }

            instance.filterSearch(instance.view, .searchQuery.toString(), options)
            .searchComplete = true
            .refreshSearchReadout()
            return
        }

        // Leaving filter mode restores the complete report before the same field starts finding
        // occurrences in it. An empty filter is also delivered above, so clearing the field is an
        // immediate return to the unfiltered tree.
        if instance.filterSearch and instance.view do
            instance.filterSearch(instance.view, "", .searchOptions())

        if .searchQuery.isEmpty() do
            return

        if not .searchBox.isValid() and not (instance.prepareSearch and instance.view)
        {
            .searchComplete = true
            .refreshSearchReadout()
            return
        }

        if instance.collectMatches and instance.view
        {
            .searchProgress = 0
            if .collectViewerMatches() do
                .finishSearch()
            else do
                .continueViewerSearch()
            return
        }

        if instance.prepareSearch and instance.view
        {
            var plan: Viewer.SearchPlan
            let state = instance.prepareSearch(instance.view, .searchQuery.toString(), &plan)
            if state != .Valid
            {
                .searchComplete = true
                if state == .InvalidVisible do
                    .searchError = #move plan.error
                .refreshSearchReadout()
                return
            }

            .searchSpan = Math.max(plan.span, 1)
        }

        if instance.useSearchMatches and instance.view do
            instance.useSearchMatches(instance.view, &.searchMatches)

        .beginSearch()
    }

    // Asks the active viewer for the matches it can answer for now, and reports whether it has
    // answered for the whole document.
    //
    // A viewer that extracts its text in the background answers a page at a time. Its first match
    // is revealed as soon as it exists rather than once the last page has been read, and the rest
    // of the document keeps being read behind it.
    private mtd collectViewerMatches()->bool
    {
        let instance = &.instances[.activeChoiceIndex]
        var options  = .searchOptions()
        var expression: Parser.RegExp
        if options.regularExpression
        {
            catch expression.compile(.searchQuery.toString(), ignoreCase: not options.matchCase) as expressionError
            if expressionError != null do
                return true
            options.expression = &expression
        }

        let complete = instance.collectMatches!(instance.view!, .searchQuery.toString(), options, &.searchProgress, &.searchMatches)
        if not complete and not .searchSelectLast and .searchIndex >= .searchMatches.count and not .searchMatches.isEmpty()
        {
            .searchIndex = 0
            .revealCurrentSearchMatch()
        }

        return complete
    }

    // Comes back to a viewer still reading its document from the search timer.
    private mtd continueViewerSearch()
    {
        .searchTimer = .addTimer(Viewer.BackgroundPollInterval)
        .refreshSearchReadout()
    }

    private mtd navigateSearch(direction: s32)
    {
        if not .searchBox.isEnabled() or not (.searchBox.text()).count do
            return
        if .searchQuery != .searchBox.text()
        {
            .restartSearch(selectLast: direction < 0)
            return
        }

        if .searchMatches.isEmpty() do
            return

        if direction < 0 do
            .searchIndex = .searchIndex ? .searchIndex - 1 : .searchMatches.count - 1
        else do
            .searchIndex = (.searchIndex + 1) % .searchMatches.count
        .revealCurrentSearchMatch()
    }

    private mtd refreshSearchReadout()
    {
        if .searchFilterMode
        {
            .searchCountLabel.setText("")
            .searchCountLabel.toolTip = ""
            .searchPrevious.enable(false)
            .searchNext.enable(false)
            .searchBox.toolTip = .searchToolTip
            return
        }

        if .searchQuery.isEmpty()
        {
            .searchCountLabel.setText("")
            .searchCountLabel.toolTip = ""
        }
        elif not .searchError.isEmpty()
        {
            .searchCountLabel.setText("!")
            .searchCountLabel.toolTip = .searchError
        }
        elif not .searchBox.isValid()
        {
            .searchCountLabel.setText("0/0")
            .searchCountLabel.toolTip = appStrings().ui_SearchInvalidRegularExpression
        }
        elif not .searchComplete
        {
            // A viewer still reading its document counts what it has found so far.
            if .searchIndex < .searchMatches.count do
                .searchCountLabel.setText(Format.toString("%/%…", .searchIndex + 1, .searchMatches.count))
            else do
                .searchCountLabel.setText("…")
            .searchCountLabel.toolTip = appStrings().ui_Searching
        }
        elif .searchMatches.isEmpty()
        {
            .searchCountLabel.setText("0/0")
            .searchCountLabel.toolTip = appStrings().ui_NoMatch
        }
        else
        {
            .searchCountLabel.setText(Format.toString("%/%", .searchIndex + 1, .searchMatches.count))
            .searchCountLabel.toolTip = .searchCountLabel.text()
        }

        let canNavigate = not .searchMatches.isEmpty()
        .searchPrevious.enable(canNavigate)
        .searchNext.enable(canNavigate)
        .searchBox.toolTip = .searchError.isEmpty() ? .searchToolTip.toString() : .searchError.toString()
    }

    private mtd revealCurrentSearchMatch()
    {
        if .searchIndex >= .searchMatches.count or .activeChoiceIndex >= .instances.count do
            return
        let instance = &.instances[.activeChoiceIndex]
        if not instance.revealMatch or not instance.view do
            return

        // Revealing may legitimately focus a document when invoked outside the search bar. Live
        // typing is different: the viewer scrolls and selects behind the field, while the caret
        // stays in the query so the next letter extends it instead of going into the document.
        let preserveSearchFocus = .searchBox.hasFocus()
        defer if preserveSearchFocus do
            .searchBox.setFocus()

        let match = .searchMatches[.searchIndex]
        if not instance.revealMatch(instance.view, match, .searchQuery.toString()) do
            return
        .searchMatch = match.offset
        .refreshSearchReadout()
        .refreshSearchHighlight()
    }

    private mtd refreshSearchHighlight()
    {
        if .searchIndex >= .searchMatches.count or .activeChoiceIndex >= .instances.count
        {
            .searchOverlay.hide()
            return
        }

        let instance = &.instances[.activeChoiceIndex]
        if not instance.view or not instance.searchBounds
        {
            .searchOverlay.hide()
            return
        }

        var bounds: Math.Rectangle
        if instance.searchBounds(instance.view, .searchMatches[.searchIndex], &bounds)
        {
            let viewport = instance.view.surfaceRect()
            bounds.intersect(viewport)
            if not bounds.isEmpty() do
                .searchOverlay.showMatch(bounds)
            else do
                .searchOverlay.hide()
        }
        else do
            .searchOverlay.hide()

        // Animation advances on the host timer, outside painting. Invalidating from inside a
        // translucent paint pass can enqueue another partial pass before the backing content has
        // been restored, which accumulates alpha and leaves trails around the word.
        .searchOverlay.phase = Math.fract(.searchOverlay.phase + cast(f32) ViewerSearchBoundsPoll.seconds / ViewerSearchGlowPeriod)
        .searchOverlay.invalidate()

        // A streamed document can materialize the result after revealMatch returns, and any
        // viewer can still adjust its scroll or layout. Follow the geometry for as long as this
        // occurrence is current rather than freezing an overlay at yesterday's coordinates.
        if not .searchBoundsTimer do
            .searchBoundsTimer = .addTimer(ViewerSearchBoundsPoll)
    }

    private mtd finishSearch()
    {
        .stopSearch(clearPresentation: false)
        .searchComplete = true
        if .searchIndex >= .searchMatches.count and not .searchMatches.isEmpty()
        {
            .searchIndex = .searchSelectLast ? .searchMatches.count - 1 : 0
            .revealCurrentSearchMatch()
        }

        .refreshSearchReadout()
    }

    mtd showSearch()
    {
        if not .searchBox.isEnabled() do
            return
        .searchBox.setFocus()
    }

    mtd hideSearch()
    {
        .viewerFocusTarget()?.setFocus()
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

    // Keeps document navigation available while the search field owns the keyboard. Page keys
    // also work from the rest of the action bar; when focus is already inside the viewer the
    // forwarding helper declines and the original event follows its normal path.
    mtd routeSearchNavigationKey(evt: *KeyEvent)->bool
    {
        if .forwardingViewerKey or evt.kind != .Pressed or .searchIndex >= .searchMatches.count do
            return false

        let pageKey         = evt.modifiers == .None and (evt.key == .PageUp or evt.key == .PageDown)
        let focused         = .focusedWindow()
        let inSearchField   = focused and (focused == .searchBox or .searchBox.isOwnerOf(focused))
        let fieldNavigation = inSearchField and ((evt.modifiers == .None and (evt.key == .Up or evt.key == .Down)) or (evt.modifiers == .Control and (evt.key == .Home or evt.key == .End)))
        if not pageKey and not fieldNavigation do
            return false

        return .forwardKeyToViewer(evt, takeFocus: false)
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

    mtd updateSearchAvailability()
    {
        let active         = .activeChoiceIndex < .instances.count
        let available      = active and .instances[.activeChoiceIndex].revealMatch != null
        let focused        = .focusedWindow()
        let searchHadFocus = focused and (focused == .searchGroup or .searchGroup.isOwnerOf(focused))

        .refreshSearchPresentation()
        .searchBox.enable(available)
        .searchOptionsButton.enable(available)
        .searchGroup.show(available)
        let actionsBesideSearch = .currentActions and .currentActions.dockStyle != .None
        .currentActions?.show(not available or actionsBesideSearch)
        .commandBar.centerGroup = available ? .searchGroup : (actionsBesideSearch ? null : .currentActions)
        .commandBar.centerContent()
        .restartSearch()
        if not available and searchHadFocus do
            .viewerFocusTarget()?.setFocus()
    }

    mtd stopSearch(clearPresentation = true)
    {
        if .searchTimer
        {
            .removeTimer(.searchTimer)
            .searchTimer = null
        }

        .searchStream.close()
        .searchCarry.clear()
        if clearPresentation and .activeChoiceIndex < .instances.count
        {
            let instance = &.instances[.activeChoiceIndex]
            if instance.view and instance.useSearchMatches do
                instance.useSearchMatches(instance.view, null)
            if instance.view and instance.clearSearch do
                instance.clearSearch(instance.view)
        }

        if .searchBoundsTimer
        {
            .removeTimer(.searchBoundsTimer)
            .searchBoundsTimer = null
        }

        .searchOverlay.hide()
    }

    mtd beginSearch()
    {
        .searchStream = catch File.openReadLive(.currentFile.toString()) as openError
        if openError != null
        {
            .finishSearch()
            return
        }

        .searchCarryBase = 0
        .searchProcessed = 0
        .searchCarry.clear()
        .searchTimer = .addTimer(1'ms)
    }

    mtd searchStep()
    {
        if .activeChoiceIndex < .instances.count and .instances[.activeChoiceIndex].collectMatches and .instances[.activeChoiceIndex].view
        {
            if .collectViewerMatches() do
                .finishSearch()
            else do
                .continueViewerSearch()
            return
        }

        if not .searchStream.isOpen() do
            return

        var bytes: Array'u8
        bytes.resize(ViewerSearchChunkSize)
        let count = catch .searchStream.read(bytes.toSlice()) as readError
        if readError != null
        {
            .finishSearch()
            return
        }

        bytes.resize(count)
        .searchCarry += cast(string) bytes.toSlice()
        let eof      = count == 0
        let instance = &.instances[.activeChoiceIndex]

        // A regular expression may span an arbitrary number of chunks, and ^/$ refer to the
        // document rather than to an implementation buffer. Keep reading incrementally so the
        // interface remains responsive, then evaluate once against the complete source.
        if .searchRegexOption and not instance.collectFileMatches and not eof
        {
            .searchTimer = .addTimer(1'ms)
            return
        }

        let deferSize = .searchSpan + ViewerSearchCarryMargin
        let stableEnd = eof ? .searchCarry.length : (.searchCarry.length > deferSize ? .searchCarry.length - deferSize : 0)

        var candidates: Array'Viewer.SearchMatch
        if instance.collectFileMatches and instance.view do
            instance.collectFileMatches(instance.view, .searchCarry.toString(), .searchCarryBase, &candidates)
        else do
            Viewer.collectTextMatches(.searchCarry.toString(), .searchQuery.toString(), .searchOptions(), 0, 0, .searchCarryBase, &candidates)
        for match in candidates where match.offset >= .searchProcessed and (eof or match.offset < .searchCarryBase + stableEnd) do
            .searchMatches.add(match)

        .searchProcessed = .searchCarryBase + stableEnd
        if eof
        {
            .finishSearch()
            return
        }

        let retainStart = stableEnd > ViewerSearchCarryMargin ? stableEnd - ViewerSearchCarryMargin : 0
        .searchCarryBase += retainStart
        .searchCarry     = String.from(.searchCarry.toString()[retainStart to])
        .searchTimer     = .addTimer(1'ms)
    }

    mtd updateFileInfo(details: string)
    {
        let baseName = Path.fileName(.currentFile.toString()) orelse .currentFile.toString()

        .infoNameLabel.setText(baseName)
        .infoNameLabel.toolTip = .currentFile
        .infoStatsLabel.setText(details)
        .infoStatsLabel.toolTip = details
        .infoSizeLabel.setText(.currentFileSize.toString())
        .infoSizeLabel.toolTip = .currentFileSize.toString()
        if .activeChoiceIndex < .choices.count do
            .infoIconLabel.setIcon(.choiceIcon(.activeChoiceIndex))
        .infoIconLabel.setIconColor(.themeColors().label_TextFaint)
        .layoutFileInfo()
        .infoBarHost.show(not .fullScreen or .fullScreenTopVisible)
    }

    // Measures the identity row again after asynchronous metadata changes. Text widths are
    // rounded outward because the stack places children on whole logical units; rounding a
    // fractional glyph extent down is enough to paint an ellipsis on an otherwise complete line.
    private mtd layoutFileInfo()
    {
        .infoNameLabel.preferredSize.x  = Math.ceil(.infoNameLabel.itf.measureContent({}).x)
        .infoStatsLabel.preferredSize.x = Math.ceil(.infoStatsLabel.itf.measureContent({}).x)
        .infoContentGroup.computeLayout()
        .infoFileGroup.computeLayout()
    }

    mtd selectViewer(index: u32)
    {
        .readingState.restoring = false
        if index == .activeChoiceIndex do
            return
        if not .activateChoice(index)
        {
            if .activeChoiceIndex != Swag.U32.Max do
                .viewerCombo.setSelectedIndex(.activeChoiceIndex, notify: false)
            return
        }

        .rememberPreferredViewer(index)
    }

    // Records which viewer the reader picked for the kind of file that is open.
    //
    // Only a choice made at the selector reaches this: a viewer the application fell back to
    // because the preferred one refused the file is an accident of that file, and remembering it
    // would answer for every file of the kind.
    private mtd rememberPreferredViewer(index: u32)
    {
        if index >= .choices.count do
            return

        // A kind opening in its own viewer is what the application does anyway, so choosing it
        // back is the removal of a decision rather than one more.
        let kind      = .choices[0].key.toString()
        let viewer    = .choices[index].key.toString()
        let isDefault = kind == viewer

        for &one, entry in .preferences where one.kind == kind
        {
            if one.viewer == viewer do
                return
            if isDefault do
                .preferences.removeAtOrdered(entry)
            else do
                one.viewer = viewer
            catch .saveState()
            return
        }

        if isDefault do
            return
        .preferences.add(ViewerPreference{String.from(kind), String.from(viewer)})
        catch .saveState()
    }

    // Returns the viewer the reader last chose for the kind of the open file, or the first one.
    private mtd preferredChoiceIndex()->u32
    {
        if .choices.isEmpty() do
            return 0

        let kind = .choices[0].key.toString()
        for one in .preferences where one.kind == kind
        {
            for choice, index in .choices where choice.key == one.viewer do
                return cast(u32) index
            break
        }

        return 0
    }

    mtd openFile(fileName: string, remember = true)
    {
        .queueFile(fileName, remember)
    }

    private mtd openClassifiedFile(classified: ViewerClassifiedFile, remember: bool)
    {
        .fileWatch.current       = #move classified.metadata
        .fileWatch.hasCandidate  = false
        .fileWatch.ignorePending = .fileWatch.load.started
        if not .fileWatchTimer do
            .fileWatchTimer = .addTimer(250'ms)
        .currentFile     = #move classified.absoluteFileName
        .currentFileSize = #move classified.fileSize
        .choices         = #move classified.choices
        .folderFiles     = #move classified.folderFiles
        .recent          = #move classified.recent
        .siblingsDirty   = true
        .rebuildSiblings()
        .instances.resize(.choices.count)
        .viewerCombo.clear()
        for choice in .choices
        {
            let plugin = &.index.plugins[choice.pluginIndex]
            .viewerCombo.addItem(plugin.displayName(), icon: .pluginIcon(plugin, themeRowIconSize(.themeMetrics())))
        }

        .viewerCombo.show()
        .openDefaultButton.enable(true)

        var selected = .preferredChoiceIndex()
        if .reloading
        {
            for choice, index in .choices where choice.key == .readingState.viewer do
                selected = cast(u32) index
        }

        if not .activateChoice(selected)
        {
            selected = Swag.U32.Max
            for choice, index in .choices where choice.key == TextViewerKey
            {
                discard choice
                selected = cast(u32) index
                break
            }

            if selected == Swag.U32.Max or not .activateChoice(selected)
            {
                .showEmpty(appStrings().ui_Unsupported)
                return
            }
        }

        if .reloading
        {
            if .choices[selected].key == .readingState.viewer
            {
                .readingState.applySettings(&.instances[selected])
                discard .readingState.restore(&.instances[selected])
                .searchBox.setText(.readingState.query.toString(), notify: false)
                .restartSearch()
            }

            .reloading = false
        }

        .emptyView.hide()

        if remember
        {
            .rememberRecent(.currentFile.toString())
            .rememberFolder(.currentFile.toString())
        }

        if .panelVisible do
            .refreshFileLists()

        .applyLayout()
        .invalidate()
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
            (cast #assume(*ViewerErrorView) instance.view).retranslate()
        if .currentFile.isEmpty()
        {
            .folderLabel.setText(texts.ui_Folder)
            .emptyLabel.setText(Format.toString("<b>%</b>", texts.ui_DropTitle))
            .emptyHintLabel.setText(texts.ui_DropHint)
            .infoStatsLabel.setText("")
        }

        .invalidate()
    }

    // Shows or hides the panel listing what is beside the current file.
    mtd toggleFilePanel()
    {
        .setFilePanelVisible(not .panelVisible)
        catch .saveState()
    }

    mtd setFilePanelVisible(visible: bool)
    {
        .panelVisible = visible
        .filesButton.setChecked(visible)
        if visible
        {
            .refreshFileLists()
            .filePanelHost.show()
        }
        else do
            .filePanelHost.hide()

        .applyLayout()
        .invalidate()
    }

    // Puts `fileName` at the head of the recent list, keeping it free of repeats and bounded.
    mtd rememberRecent(fileName: string)
    {
        for one, index in .recent where one[] == fileName
        {
            .recent.removeAtOrdered(index)
            break
        }

        .recent.insertAt(0, String.from(fileName))
        while .recent.count > ViewerRecentCount do
            .recent.removeAtOrdered(.recent.count - 1)
    }

    // Puts the file's folder at the head of the bounded folder history.
    mtd rememberFolder(fileName: string)
    {
        let folder = Path.directoryName(fileName)
        if not folder do
            return

        for one, index in .folderHistory where Utf8.compare(one.folder.toSlice(), folder, .Latin1NoCase) == 0
        {
            .folderHistory.removeAtOrdered(index)
            break
        }

        .folderHistory.insertAt(0, {String.from(folder), String.from(fileName)})
        while .folderHistory.count > ViewerFolderHistoryCount do
            .folderHistory.removeAtOrdered(.folderHistory.count - 1)
        .folderHistoryButton.enable(true)
    }

    // Fills one list with file names, selecting the row that names the current file.
    private mtd fillFileList(list: *ListCtrl, files: const [..] String)
    {
        let scrollPosition = list.scrollWnd.scrollPosition()
        list.clear()
        for one, index in files
        {
            let name        = one[].toString()
            var pluginIndex = Swag.U64.Max
            var icon: Icon
            if .index.namePlugin(name, &pluginIndex)
            {
                let plugin = &.index.plugins[pluginIndex]
                icon = .pluginIcon(plugin, themeRowIconSize(.themeMetrics()))
            }

            discard list.createLine(Path.fileName(name) orelse name, icon)
            if .currentFile == name do
                list.selectLine(cast(u32) index)
        }

        list.computeLayout()
        list.scrollWnd.setScrollPos(scrollPosition)
    }

    // Rebuilds both sections of the panel from what the window already knows.
    mtd refreshFileLists()
    {
        if .siblingsDirty do
            .rebuildSiblings()

        .refreshingLists = true
        defer .refreshingLists = false

        .fillFileList(.recentList, .recent.toSlice())
        .fillFileList(.folderList, .siblings.toSlice())

        let hasRecent = not .recent.isEmpty()
        .filePanel.setPaneVisible(0, hasRecent)
        .folderLabel.setText(.currentFile.isEmpty() ? appStrings().ui_Folder : (Path.fileName(Path.directoryName(.currentFile.toString())) orelse appStrings().ui_Folder))
        .filePanel.applyLayout()
    }

    // Shows what a panel row offers for the file it names.
    //
    // The right click has already put the row under the pointer in the selection, silently: the
    // list moves its own selection for the button without announcing a choice, so pointing at a
    // file to act on it never opens it.
    mtd showFileMenu(list: *ListCtrl, files: const [..] String, position: Math.Point)
    {
        let line = list.selectedLine()
        if not line do
            return
        let index = line.index
        if index >= files.count do
            return

        // The actions below outlive the list they were asked from: forgetting a file rebuilds
        // both lists, and the row that named it is gone by then.
        let fileName = String.from(files[index].toString())

        // Only the history is a list the reader owns. The folder list is what the folder holds,
        // and an entry leaves it by leaving the disk.
        .showFileActions(fileName.toString(), position, history: list == .recentList)
    }

    // Shows what the open file offers, from the band that names it.
    //
    // The history entries stay out: the band says what is being read, and a file is not taken out
    // of the list of what was read from the place that is reading it.
    mtd showCurrentFileActions(position: Math.Point)
    {
        if .currentFile.isEmpty() do
            return
        .showFileActions(.currentFile.toString(), position, history: false)
    }

    // Opens the current file with the handler registered by the operating system.
    mtd openCurrentFileDefault()
    {
        if not .currentFile.isEmpty() do
            discard Env.openFile(.currentFile.toString())
    }

    // Opens the bounded folder history and returns to the last file viewed in the chosen folder.
    mtd showFolderHistory()
    {
        let menu = MenuCtrl.createPopup(me, owner: me)
        for one in .folderHistory where Directory.exists(one.folder.toString()) and File.exists(one.file.toString())
        {
            var name = Path.fileName(one.folder.toString()) orelse one.folder.toString()
            if not name.count do
                name = one.folder.toString()
            var icon = .app().directoryIcon(one.folder.toString(), true)
            icon.color = .themeColors().label_Text
            discard menu.addItem(name, one.folder.toString(), icon)
        }

        if menu.items.isEmpty()
        {
            menu.destroy()
            return
        }

        let folder = menu.doModal(.folderHistoryButton, autoDestroy: true) orelse ""
        if not folder.count do
            return
        for one in .folderHistory where one.folder == folder
        {
            .queueFile(one.file.toString())
            return
        }
    }

    // Builds what one file offers, wherever the reader pointed at it.
    private mtd createFileActionsMenu(history: bool)->*MenuCtrl
    {
        let texts = appStrings()
        let menu  = MenuCtrl.createPopup(me, owner: me)
        menu.addItem(texts.ui_MenuLocate, "scope.file.locate", .theme().icon(.OpenFile, themeRowIconSize(.themeMetrics())))
        menu.addItem(texts.ui_MenuOpenDefault, "scope.file.openDefault", .theme().icon(.OpenExternal, themeRowIconSize(.themeMetrics())))
        menu.addItem(texts.ui_MenuOpenWith, "scope.file.openWith", .theme().icon(.OpenExternal, themeRowIconSize(.themeMetrics())))
        menu.addSeparator()
        menu.addItem(texts.ui_MenuCopyPath, "scope.file.copyPath", .theme().icon(.Copy, themeRowIconSize(.themeMetrics())))
        menu.addItem(texts.ui_MenuCopyName, "scope.file.copyName", .theme().icon(.Copy, themeRowIconSize(.themeMetrics())))
        if history
        {
            menu.addSeparator()
            menu.addItem(texts.ui_MenuForget, "scope.file.forget", .theme().icon(.Remove, themeRowIconSize(.themeMetrics())))
        }

        return menu
    }

    // Shows what one file offers, wherever the reader pointed at it.
    private mtd showFileActions(fileName: string, position: Math.Point, history: bool)
    {
        let menu = .createFileActionsMenu(history)

        let chosen = menu.doModal(position, .TopLeft, autoDestroy: true)
        if not chosen do
            return

        switch chosen
        {
        case "scope.file.locate":      Env.showInFileExplorer(fileName)
        case "scope.file.openDefault": Env.openFile(fileName)
        case "scope.file.openWith":    Env.openFileWith(fileName)
        case "scope.file.copyPath":    Clipboard.setString(fileName)
        case "scope.file.copyName":    Clipboard.setString(Path.fileName(fileName) orelse fileName)
        case "scope.file.forget":      .forgetRecent(fileName)
        }
    }

    // Drops one file from the history, keeping the rest of it in order.
    mtd forgetRecent(fileName: string)
    {
        for one, index in .recent where one[] == fileName
        {
            .recent.removeAtOrdered(index)
            break
        }

        .refreshFileLists()
        catch .saveState()
    }

    // Empties the history. What is open stays open: the list says what was read, not what is.
    mtd clearRecent()
    {
        .recent.clear()
        .refreshFileLists()
        catch .saveState()
    }

    // Confirms the destructive history action before applying it.
    mtd confirmClearRecent()
    {
        if MessageDlg.confirm(.surface!, appStrings().ui_ConfirmClearHistory) == Dialog.BtnYes do
            .clearRecent()
    }

    // Opens the file a panel row names, unless the row was selected by the refresh itself.
    private mtd openListSelection(list: *ListCtrl, files: const [..] String)
    {
        if .refreshingLists do
            return
        let selected = list.selectedLines()
        if selected.isEmpty() or not selected[0] do
            return
        let index = selected[0]!.index
        if index >= files.count do
            return
        let fileName = files[index].toString()
        if .currentFile != fileName do
            .queueFile(fileName, remember: list != .recentList)
    }

    mtd rebuildSiblings()
    {
        .siblings.clear()
        .siblingIndex = 0
        for file in .folderFiles
        {
            if .folderSameKind and not .index.sharesViewer(.currentFile.toString(), file[].toString()) do
                continue
            .siblings.add(file[])
        }

        for i in .siblings.count where .siblings[i] == .currentFile
        {
            .siblingIndex = i
            break
        }

        .siblingsDirty = false
    }

    // Applies the folder-navigation filter and refreshes what depends on it.
    mtd setFolderSameKind(value: bool)
    {
        if .folderSameKind == value do
            return
        .folderSameKind = value
        .kindButton.setChecked(value)
        .siblingsDirty = true
        if .panelVisible and not .currentFile.isEmpty() do
            .refreshFileLists()
        catch .saveState()
    }

    mtd navigate(delta: s32)
    {
        if .currentFile.isEmpty() do
            return
        if .siblingsDirty do
            .rebuildSiblings()
        if .siblings.count <= 1 do
            return

        var index = cast(s64) .siblingIndex + delta
        if index < 0 do
            index = cast(s64) .siblings.count - 1
        elif index >= cast(s64) .siblings.count do
            index = 0
        .queueFile(.siblings[cast(u64) index].toString())
    }

    // Returns the files of the current file's folder that its viewer opens, in folder order and
    // whatever the panel filter says: a play mode walks the movies of a folder past the notes
    // stored beside them, whether or not the list shows those notes.
    mtd kindSiblings()->Array'String
    {
        var result: retval
        for file in .folderFiles where .index.sharesViewer(.currentFile.toString(), file[].toString()) do
            result.add(file[])
        return result
    }

    // Queues the file that follows the current one in `mode` among those its viewer opens, and
    // reports whether there was one to queue.
    //
    // A file that a play mode brings up is not one the reader chose, so it joins neither the
    // recent list nor the folder history.
    mtd continueFile(mode: Viewer.PlayMode)->bool
    {
        if .currentFile.isEmpty() do
            return false
        let files = .kindSiblings()
        if files.count <= 1 do
            return false

        var next: String
        switch #complete mode
        {
        case .Once, .Repeat:
            return false

        case .Folder:
            var index = 0'u64
            for i in files.count where files[i] == .currentFile
            {
                index = i
                break
            }

            next = files[(index + 1) % files.count]

        case .Shuffle:
            next = .pickShuffled(files.toSlice())
        }

        .queueFile(next.toString(), remember: false)
        return true
    }

    // Picks a file the shuffle has not yet continued from in this folder, starting a new round
    // once every file has had its turn.
    //
    // The file that has just ended is the one that must not come straight back, so a new round
    // starts with it already taken. The round is not persisted: a shuffle is a walk through a
    // folder, not a property of it.
    mtd pickShuffled(files: const [..] String)->String
    {
        let folder = Path.directoryName(.currentFile.toString()) orelse ""
        if Utf8.compare(.shuffleFolder.toString(), folder, .Latin1NoCase) != 0
        {
            .shuffleFolder = folder
            .shufflePlayed.clear()
        }

        if not .shufflePlayed.contains(.currentFile) do
            .shufflePlayed.add(.currentFile)

        var candidates: Array'u64
        for one, index in files where not .shufflePlayed.contains(one[]) do
            candidates.add(index)
        if candidates.isEmpty()
        {
            .shufflePlayed.clear()
            .shufflePlayed.add(.currentFile)
            for one, index in files where one[] != .currentFile do
                candidates.add(index)
        }

        return files[candidates[Random.shared().nextU64(0, candidates.count)]]
    }

    // Answers a viewer that has finished presenting its file with what the play mode calls for.
    //
    // Only the current view has a say: one on its way out reports the end of a file the window
    // has already left. A folder mode brings up the file that follows and tells the viewer to
    // stay as it is; a file alone of its kind in its folder is the whole playlist, so those modes
    // have it presented again.
    mtd continueAfter(view: *Wnd)->Viewer.Continuation
    {
        if view != .currentView do
            return .Stop
        switch #complete .playMode
        {
        case .Once:   return .Stop
        case .Repeat: return .Replay
        case .Folder, .Shuffle: return .continueFile(.playMode) ? .Next : .Replay
        }
    }

    // Starts the slideshow pace for a view showing content with no end of its own.
    //
    // A progressive viewer may report before the window has committed to it; the commit then
    // starts the count, so the order of the two does not matter.
    mtd showStill(view: *Wnd)
    {
        .stillView = view
        .armSlide()
    }

    // Counts the slideshow pace down for a still picture while a folder mode is on, and stops
    // counting otherwise.
    mtd armSlide()
    {
        .stopSlide()
        if not .stillView or .stillView != .currentView do
            return
        if .playMode != .Folder and .playMode != .Shuffle do
            return
        .slideTimer = .addTimer(Time.Duration.fromSeconds(.slideSeconds))
    }

    mtd stopSlide()
    {
        if not .slideTimer do
            return
        .removeTimer(.slideTimer)
        .slideTimer = null
    }

    // Moves the slideshow on once its pace has elapsed on the picture that started it.
    mtd continueSlide()
    {
        if not .stillView or .stillView != .currentView do
            return
        discard .continueFile(.playMode)
    }

    mtd setPlayMode(mode: Viewer.PlayMode)
    {
        if .playMode == mode do
            return
        .playMode = mode
        .armSlide()
        catch .saveState()
    }

    mtd setSlideSeconds(seconds: f32)
    {
        .slideSeconds = Math.clamp(seconds, Viewer.SlideMinSeconds, Viewer.SlideMaxSeconds)
        .armSlide()
        catch .saveState()
    }
}
