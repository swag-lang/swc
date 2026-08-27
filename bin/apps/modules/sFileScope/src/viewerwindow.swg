using Core, Pixel, Gui

const ViewerBarHeight                         = 48.0
const ViewerInfoHeight                        = 40.0
const ViewerGlyphSize                         = 20.0
const ViewerRowGlyphSize                      = 16.0
const ViewerMinWidth                          = 880
const ViewerSearchChunkSize                   = 256 * 1024'u64
const ViewerSearchBarWidth                    = 364.0
const ViewerSearchFieldWidth                  = 180.0
const ViewerSearchCountWidth                  = 52.0
const ViewerSearchButtonSize                  = 28.0
const ViewerSearchCarryMargin                 = 4'u64
const ViewerErrorTextWidth                    = 512.0
const ViewerInfoStatsMaxWidth                 = 560.0
const ViewerFullScreenRevealEdge              = 32.0
const ViewerRetirePollInterval: Time.Duration = 16'ms
const ViewerLoadingSpinnerSize                = 56.0
const ViewerLoadingSpinnerRadius              = 20.0
const ViewerLoadingSpinnerSweep               = 150.0
const ViewerSearchGlowInset                   = 7.0
const ViewerSearchTextMargin                  = 3.0
const ViewerSearchOverlayInset                = ViewerSearchGlowInset + ViewerSearchTextMargin
const ViewerSearchGlowPeriod:   f32           = 1.35
const ViewerSearchBoundsPoll:   Time.Duration = 16'ms
const ViewerSmokeStepLimit                    = 300'u32
const ViewerSmokeExposureSteps                = 25'u32
const ViewerSmokeMinimumSteps                 = 2'u32

const ViewerFullScreenRemovedFlags = SurfaceFlags.LargeCaption | SurfaceFlags.SmallCaption | SurfaceFlags.MinimizeButton | SurfaceFlags.MaximizeButton | SurfaceFlags.CloseButton | SurfaceFlags.Border | SurfaceFlags.Resizable
const ViewerFullScreenAddedFlags   = SurfaceFlags.NoShadow | SurfaceFlags.TopMost

// The panel that lists what is beside the current file, and what was read before it.
const ViewerPanelWidth   = 268.0
const ViewerPanelLabel   = 26.0
const ViewerRecentHeight = 188.0
const ViewerPaneMinSize  = 88.0

// Files the recent list keeps. Long enough to cross a working session, short enough that the list
// stays something a reader scans rather than searches.
const ViewerRecentCount = 12'u64

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

struct ViewerInstance
{
    view:                #null *Wnd
    commands:            #null *Wnd
    revealMatch:         #null ViewerRevealMatch
    searchBounds:        #null ViewerSearchBounds
    clearSearch:         #null ViewerClearSearch
    collectMatches:      #null ViewerCollectMatches
    isLoading:           #null ViewerIsLoading
    needsLoadingOverlay: #null ViewerNeedsLoadingOverlay
    retire:              #null ViewerRetire
    details:             String
    failureReason:       String
}

// Keeps the search group centered on the complete action bar, independently of the file actions
// and viewer selector docked at its edges.
struct ViewerActionBar
{
    using wnd:   Wnd
    searchGroup: #null *Wnd
}

impl IWnd for ViewerActionBar
{
    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        discard evt
        .centerSearchGroup()
    }
}

impl ViewerActionBar
{
    func create(parent: *Wnd)->*ViewerActionBar
    {
        let result = Wnd.create'ViewerActionBar(parent, {0, 0, 0, ViewerBarHeight})
        result.dockStyle       = .Top
        result.backgroundStyle = .Window
        result.padding         = {12, 6, 12, 6}
        return result
    }

    mtd centerSearchGroup()
    {
        if !.searchGroup do
            return
        let client = .paddedClientRect()
        .searchGroup!.setPosition({client.horzCenter() - ViewerSearchBarWidth * 0.5, client.vertCenter() - 18, ViewerSearchBarWidth, 36}, computeLayout: false)
        .searchGroup!.applyLayout()
    }
}

impl ViewerInstance
{
    // Requests resource release and reports whether GUI destruction may proceed.
    mtd retireView()->bool
    {
        if !.view or !.retire do
            return true
        if !.retire!(.view!) do
            return false
        .retire = null
        return true
    }
}

// Application-owned presentation for every viewer failure.
struct ViewerErrorView
{
    using wnd: Wnd

    #[Swag.Late]
    {
        summaryLabel: *Label
        reasonLabel:  *Label
        iconLabel:    *Label
    }
}

// Keeps the animated repaint local to the activity mark. The host covers the whole document, so
// animating the host itself would repaint every visible viewer subtree on every frame.
struct ViewerLoadingSpinner
{
    using wnd: Wnd

    animationPhase: f32
}

// Application-owned wait surface shared by every progressive viewer.
//
// A renderer only reports whether it is waiting; it neither chooses nor paints the feedback.
// The transparent host leaves the document exactly as it was and adds only the activity mark,
// so loading HTML or a picture cannot appear to change the document background.
struct ViewerLoadingOverlay
{
    using wnd: Wnd

    #[Swag.Late]
    spinner: *ViewerLoadingSpinner
}

// One application-owned marker for every current occurrence. Viewers report only the surface
// bounds of what they revealed; this layer supplies the themed band, crisp edge and quiet electric
// pulse, so PDF text and a byte in the hexadecimal view speak exactly the same visual language.
struct ViewerSearchOverlay
{
    using wnd: Wnd
    phase:     f32
}

impl IWnd for ViewerSearchOverlay
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let colors  = .themeColors()
        let pulse   = 0.5'f32 + 0.5'f32 * Math.sin(.phase * Math.ConstF32.TwoPi)
        let rect    = .clientRect()
        var marked  = rect
        marked.applyPadding({ViewerSearchGlowInset, ViewerSearchGlowInset, ViewerSearchGlowInset, ViewerSearchGlowInset})

        var glow = colors.searchMatch_Glow
        glow.a = cast(u8) (cast(f32) glow.a * (0.45 + pulse * 0.55))

        // Crisp pixel-aligned strokes avoid the renderer's antialiased no-overlap scratch pass on
        // this translucent top layer; that pass is appropriate for opaque silhouettes, but here
        // it can leave cleared-alpha seams while the pulse changes intensity.
        painter.setAntialiased(false)
        painter.drawRect(marked, glow, 5)
        painter.fillRect(marked, colors.searchMatch_Bk)
        painter.drawRect(marked, colors.searchMatch_Border, 2)
    }
}

impl ViewerSearchOverlay
{
    func create(parent: *Wnd)->*ViewerSearchOverlay
    {
        let result = Wnd.create'ViewerSearchOverlay(parent, "sFileScope.search.highlight")
        result.wndFlags        |= WndFlags.TopMost | WndFlags.Disabled
        result.backgroundStyle = .Transparent
        result.hide()
        return result
    }

    // Follows a surface-coordinate match without entering the viewer's own layout or hit testing.
    mtd showMatch(bounds: Math.Rectangle)
    {
        let parent  = .parent!
        let topLeft = parent.surfaceToLocal(Math.Point{bounds.x, bounds.y})
        .setPosition({topLeft.x - ViewerSearchOverlayInset, topLeft.y - ViewerSearchOverlayInset,
                      bounds.width + ViewerSearchOverlayInset * 2, bounds.height + ViewerSearchOverlayInset * 2},
                     computeLayout: false)
        .show()
        .bringToFront()
    }
}

impl IWnd for ViewerLoadingSpinner
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let center  = .clientRect().center()
        let start   = .animationPhase * 360 - 90
        let end     = start + ViewerLoadingSpinnerSweep

        painter.setAntialiased(true)
        painter.drawArc(center.x, center.y, ViewerLoadingSpinnerRadius, Math.Angle.fromDegrees(start), Math.Angle.fromDegrees(end), Ink, 9)
        painter.drawArc(center.x, center.y, ViewerLoadingSpinnerRadius, Math.Angle.fromDegrees(start), Math.Angle.fromDegrees(end), Voltage, 5)

        .animationPhase = Math.fract(.animationPhase + .timing().deltaSeconds * 0.8)
        .invalidate()
    }
}

impl ViewerLoadingOverlay
{
    func create(parent: *Wnd)->*ViewerLoadingOverlay
    {
        let result = Wnd.create'ViewerLoadingOverlay(parent, "sFileScope.loading")
        result.wndFlags                |= WndFlags.TopMost | WndFlags.Disabled
        result.backgroundStyle         = .Transparent
        result.spinner                 = Wnd.create'ViewerLoadingSpinner(result, {0, 0, ViewerLoadingSpinnerSize, ViewerLoadingSpinnerSize})
        result.spinner.backgroundStyle = .Transparent
        result.hide()
        return result
    }

    // Covers `rect`, expressed in the shared parent coordinates; painting centers the activity mark.
    mtd cover(rect: Math.Rectangle)
    {
        .setPosition(rect, computeLayout: false)
        .spinner.setPosition({(rect.width - ViewerLoadingSpinnerSize) * 0.5, (rect.height - ViewerLoadingSpinnerSize) * 0.5, ViewerLoadingSpinnerSize, ViewerLoadingSpinnerSize}, computeLayout: false)
    }
}

impl ViewerErrorView
{
    func create(parent: *Wnd, reason: string)->*ViewerErrorView
    {
        let result = Wnd.create'ViewerErrorView(parent, "sFileScope.error")
        result.backgroundStyle = .View

        with let stack = StackLayoutCtrl.create(result, .VerticalCenter)
        {
            .dockStyle = .Center
            .padding   = {48, 48, 48, 48}
            .spacing   = 8

            with result.iconLabel = Label.create(stack, "", {0, 0, 48, 48})
            {
                .layoutSpec.alignX = .Center
                .setIcon(result.theme().icon(.Critical, 48))
                .setIconColor(result.themeColors().error)
            }

            with result.summaryLabel = Label.create(stack, appStrings().ui_ViewerError, {0, 0, ViewerErrorTextWidth, 0}, null, .WordWrap | .AutoHeight | .SecondaryText)
            {
                .layoutSpec.alignX = .Center
                .setTextAlignment(.Center, .Center)
            }

            with result.reasonLabel = Label.create(stack, reason, {0, 0, ViewerErrorTextWidth, 0}, null, .WordWrap | .AutoHeight)
            {
                .layoutSpec.alignX = .Center
                .setTextAlignment(.Center, .Center)
            }
        }

        result.applyLayout()
        return result
    }

    mtd retranslate()
    {
        .summaryLabel.setText(appStrings().ui_ViewerError)
    }

    mtd refreshTheme()
    {
        .iconLabel.setIcon(.theme().icon(.Critical, 48))
        .iconLabel.setIconColor(.themeColors().error)
    }
}

// The document header that names the open file, and answers for it.
//
// The panel is closed by default and the file being read is the one an action is wanted for most,
// so the header carries the same menu a panel row does.
struct ViewerInfoBar
{
    using wnd: Wnd
}

impl IWnd for ViewerInfoBar
{
    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        // The labels the band holds decline the button, so the press arrives here having crossed
        // whichever one the pointer was over.
        if evt.kind != .Released or evt.button != .Right
        {
            evt.accepted = false
            return
        }

        (cast(*ViewerWindow) .parent!).showCurrentFileActions(evt.surfacePos)
    }
}

func reportViewerFailure(view: *Wnd, reason: string)
{
    let window = cast(*ViewerWindow) view.parent!
    window.replaceFailedViewer(view, reason)
}

struct ViewerClassifiedFile
{
    absoluteFileName: String
    fileSize:         String
    choices:          Array'ViewerChoice
    folderFiles:      Array'String
    recent:           Array'String
    exists:           bool
}

// Classifies one requested file without making the GUI thread open or probe it.
struct ViewerChoiceLoad
{
    job:           Jobs.Job
    index:         #null *ViewerIndex
    fileName:      String
    basicTextName: String
    recent:        Array'String
    result:        ViewerClassifiedFile
    started:       bool
}

impl ViewerChoiceLoad
{
    mtd start(index: *ViewerIndex, fileName, basicTextName: string, recent: const [..] String)
    {
        Debug.assert(!.started)
        .index         = index
        .fileName      = fileName
        .basicTextName = basicTextName
        .recent        = recent
        .job.lambda    = func(data: #null *void)
        {
            let operation = cast(*ViewerChoiceLoad) data!
            var absolute  = catch Path.absolute(operation.fileName.toString()) as pathError
            if pathError != null do
                absolute = operation.fileName
            operation.result.absoluteFileName = #move absolute
            operation.result.exists           = File.exists(operation.result.absoluteFileName.toString())
            if operation.result.exists
            {
                operation.result.choices = operation.index!.choices(operation.result.absoluteFileName.toString(), operation.basicTextName.toString())
                let info = catch File.info(operation.result.absoluteFileName.toString()) as infoError
                if infoError == null do
                    operation.result.fileSize = StrConv.toDisplaySize(info.size)
            }

            for one in operation.recent where File.exists(one[].toString()) do
                operation.result.recent.add(one[])

            let folder = Path.directoryName(operation.result.absoluteFileName.toString())
            if !folder do
                return
            let files = catch Directory.enumerateFiles(folder) as listError
            if listError != null do
                return
            for file in files
            {
                if file.isDirectory() do
                    continue
                operation.result.folderFiles.add(file.fullname)
            }

            operation.result.folderFiles.sort(func(a, b) { return Utf8.compare(a.toSlice(), b.toSlice(), .Latin1NoCase) })
        }
        .job.data = me
        .started  = true
        Jobs.schedule(&.job)
    }

    mtd const isDone()->bool => .started and Jobs.isDone(&.job)

    mtd finish()->ViewerClassifiedFile
    {
        Debug.assert(.isDone())
        Jobs.wait(&.job)
        .started = false
        return #move .result
    }

    mtd opDrop()
    {
        if .started do
            Jobs.wait(&.job)
    }
}

struct ViewerWindow
{
    using wnd: Wnd

    #[Swag.Late]
    {
        commandBar:        *ViewerActionBar
        kindButton:        *IconButton
        openButton:        *IconButton
        filesButton:       *IconButton
        fullScreenButton:  *IconButton
        searchGroup:       *StackLayoutCtrl
        searchBox:         *EditBox
        searchCountLabel:  *Label
        searchPrevious:    *IconButton
        searchNext:        *IconButton
        searchMatchCase:   *IconButton
        searchWholeWord:   *IconButton
        viewerCombo:       *ComboBox
        appearanceButton:  *AppearanceButton
        accentRail:        *Separator
        infoBar:           *ViewerInfoBar
        infoFileGroup:     *StackLayoutCtrl
        infoIconLabel:     *Label
        infoNameLabel:     *Label
        infoStatsLabel:    *Label
        infoSizeLabel:     *Label
        loadingOverlay:    *ViewerLoadingOverlay
        searchOverlay:     *ViewerSearchOverlay
        viewerBar:         *Wnd
        emptyView:         *StackLayoutCtrl
        emptyIconLabel:    *Label
        emptyLabel:        *Label
        emptyHintLabel:    *Label
        filePanel:         *SplitterCtrl
        recentPane:        *Wnd
        recentLabel:       *Label
        recentClearButton: *IconButton
        recentList:        *ListCtrl
        folderPane:        *Wnd
        folderLabel:       *Label
        folderList:        *ListCtrl
    }

    index:                 ViewerIndex
    icons:                 IconSet
    currentView:           #null *Wnd
    currentCommands:       #null *Wnd
    outgoingView:          #null *Wnd
    outgoingCommands:      #null *Wnd
    choices:               Array'ViewerChoice
    instances:             Array'ViewerInstance
    activeChoiceIndex           = Swag.U32.Max
    startupTimer:          #null *Timer
    searchTimer:           #null *Timer
    searchBoundsTimer:     #null *Timer
    loadingTimer:          #null *Timer
    choiceLoad:            ViewerChoiceLoad
    smokeTimer:            #null *Timer
    searchStream:          File.FileStream
    searchQuery:           String
    searchCarry:           String
    searchCarryBase:       u64
    searchProcessed:       u64
    searchMatches:         Array'ViewerSearchMatch
    searchIndex:           u64  = Swag.U64.Max
    searchMatch:           u64  = Swag.U64.Max
    searchComplete:        bool
    searchSelectLast:      bool
    searchMatchCaseOption: bool
    searchWholeWordOption: bool
    pendingFile:           String
    pendingEmpty:          String
    pendingRemember:       bool = true
    currentFile:           String
    currentFileSize:       String
    folderFiles:           Array'String
    siblings:              Array'String
    siblingIndex:          u64
    siblingsDirty               = true

    // Whether next/previous and the folder list keep only the neighbours the current file's
    // viewer would open, so a reader flips through the pictures of a folder without landing on
    // the notes stored beside them.
    folderSameKind: bool

    // Guards the one nested dispatch [[forwardKeyToViewer]] makes, so a key the viewer
    // declines falls back to file navigation instead of being offered again.
    forwardingViewerKey:       bool
    playPauseKeyDown:          bool
    recent:                    Array'String
    preferences:               Array'ViewerPreference
    panelVisible:              bool
    recentPaneSize = ViewerRecentHeight
    refreshingLists:           bool
    fileDlgState:              FileDlgState
    themeIndex:                u32
    language:                  String
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

func reportViewerDetails(view: *Wnd, details: string)
{
    let window = cast(*ViewerWindow) view.parent!
    for &instance, index in window.instances where instance.view == view
    {
        instance.details = details
        if index == window.activeChoiceIndex do
            window.updateFileInfo(details)
        return
    }
}

// Opens a neighboring file for the viewer that chose to own directional navigation.
func navigateViewerFile(view: *Wnd, delta: s32)
{
    (cast(*ViewerWindow) view.parent!).navigate(delta)
}

// Lets a viewer wake the generic wait presentation when work starts again after being idle.
func reportViewerLoadingChanged(view: *Wnd)
{
    let window = cast(*ViewerWindow) view.parent!
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
        let fileName = evt.data.singleFile()
        if !fileName
        {
            evt.accepted = false
            return
        }

        // The system holds the whole drag — the source window's own loop included — until this
        // returns, so a drop only records the file. Reading a header, building a viewer and
        // decoding a first picture happen on the next turn of the event loop, by which time the
        // drag is over and both windows can paint again.
        if evt.kind == .Drop do
            .queueFile(fileName)
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
            .setFullScreen(!.fullScreen)
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
            if .forwardingViewerKey or !.forwardKeyToViewer(evt) do
                evt.accepted = false
        }
        elif evt.key == .F5 and !.currentFile.isEmpty() do
            .queueFile(.currentFile.toString())
        else do
            evt.accepted = false
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
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

        if evt.timer != .startupTimer
        {
            evt.accepted = false
            return
        }

        .removeTimer(.startupTimer!)
        .startupTimer = null
        if !.pendingFile.isEmpty() do
            .processQueuedFile()
        elif !.pendingEmpty.isEmpty()
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
        .icons.free()
        if .startupTimer
        {
            .removeTimer(.startupTimer!)
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
        evt.accepted = true
    }

    mtd impl onSerializeStateEvent(evt: *SerializeStateEvent)
    {
        if !evt.serializer.isReading() and .filePanel.items.count do
            .recentPaneSize = .filePanel.items[0]!.size

        catch evt.serializer.serialize("ViewerWindow.fileDlgState", &me.fileDlgState)
        catch evt.serializer.serialize("ViewerWindow.themeIndex", &me.themeIndex)
        catch evt.serializer.serialize("ViewerWindow.language", &me.language)
        catch evt.serializer.serialize("ViewerWindow.recent", &me.recent)
        catch evt.serializer.serialize("ViewerWindow.preferences", &me.preferences)
        catch evt.serializer.serialize("ViewerWindow.panelVisible", &me.panelVisible)
        catch evt.serializer.serialize("ViewerWindow.recentPaneSize", &me.recentPaneSize)
        catch evt.serializer.serialize("ViewerWindow.folderSameKind", &me.folderSameKind)
        catch evt.serializer.serialize("ViewerWindow.searchMatchCase", &me.searchMatchCaseOption)
        catch evt.serializer.serialize("ViewerWindow.searchWholeWord", &me.searchWholeWordOption)
        if evt.serializer.isReading()
        {
            .themeIndex     = Math.min(.themeIndex, 1)
            .recentPaneSize = Math.max(.recentPaneSize, ViewerPaneMinSize)
            if .filePanel.items.count do
                .filePanel.items[0]!.size = .recentPaneSize
            while .recent.count > ViewerRecentCount do
                .recent.removeAtOrdered(.recent.count - 1)
            .searchMatchCase.setChecked(.searchMatchCaseOption)
            .searchWholeWord.setChecked(.searchWholeWordOption)
        }
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged do
            .retranslate()
        elif evt.kind == .ThemeChanged
        {
            for &instance in .instances where instance.view and !instance.failureReason.isEmpty() do
                (cast(*ViewerErrorView) instance.view!).refreshTheme()
            .refreshArtwork()
        }

        .wnd.IWnd.onNotifyEvent(evt)
    }
}

impl ViewerWindow
{
    // Creates an icon descriptor for an application glyph at `size` logical pixels.
    mtd icon(idx: ViewerIcons, size = ViewerRowGlyphSize)->Icon
    {
        return .icons.icon(cast(s32) idx, size, .theme().res.atlasScale)
    }

    mtd applyTheme(index: u32)
    {
        .themeIndex = Math.min(index, 1)
        .appearanceButton.setAppearanceTheme(.themeIndex ? .Light : .Dark)
    }

    mtd applyLanguage()
    {
        discard catch .appearanceButton.setAppearanceLanguage(.language.toString())
    }

    // Keeps the few decorative glyphs aligned with the active palette and document kind.
    mtd refreshArtwork()
    {
        .emptyIconLabel.setIcon(.theme().icon(.OpenFile, 48))
        .emptyIconLabel.setIconColor(.themeColors().label_TextFaint)
        .infoIconLabel.setIconColor(.themeColors().label_TextFaint)
        .searchPrevious.setIcon(.theme().icon(.SearchPrevious, 16))
        .searchNext.setIcon(.theme().icon(.SearchNext, 16))
        if .activeChoiceIndex < .choices.count do
            .infoIconLabel.setIcon(.icon(.choices[.activeChoiceIndex].icon))
    }

    // A monitor-sized full-screen placement is transient and must never replace the saved
    // window placement. Closing first restores the regular placement, then persists it.
    private mtd saveState() fail
    {
        if .fullScreen do
            return
        try g_App.saveState()
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
            srfn.setPosition(Env.monitorForRectangle(.fullScreenRestorePosition).physicalBounds)
            .accentRail.hide()
            .commandBar.dockStyle = .None
            .infoBar.dockStyle    = .None
            .viewerBar.dockStyle  = .None
            .commandBar.hide()
            .infoBar.hide()
            .viewerBar.hide()
            .filePanel.hide()
            .fullScreenTopVisible    = false
            .fullScreenBottomVisible = false
            .applyLayout()
        }
        else
        {
            .fullScreen = false
            srfn.updateFlags(add: .fullScreenRestoreFlags & (ViewerFullScreenRemovedFlags | ViewerFullScreenAddedFlags), remove: (ViewerFullScreenRemovedFlags | ViewerFullScreenAddedFlags) & ~.fullScreenRestoreFlags)
            srfn.setPosition(.fullScreenRestorePosition)
            if .fullScreenWasMaximized do
                srfn.showMaximized()
            .accentRail.show()
            .commandBar.dockStyle = .Top
            .infoBar.dockStyle    = .Top
            .viewerBar.dockStyle  = .Bottom
            .commandBar.show()
            .infoBar.show()
            .viewerBar.show(.currentCommands != null)
            .filePanel.show(.panelVisible)
            .fullScreenTopVisible    = false
            .fullScreenBottomVisible = false
            .applyLayout()
        }

        .fullScreenButton.setChecked(.fullScreen)
        .fullScreenButton.setIcon(.theme().icon(.fullScreen ? .ExitFullScreen : .FullScreen, ViewerGlyphSize))
        .fullScreenButton.toolTip = .fullScreen ? appStrings().ui_ExitFullScreen : appStrings().ui_FullScreen
    }

    // Reveals full-screen chrome only while the pointer is at the corresponding screen edge.
    mtd updateFullScreenChrome(position: Math.Point)
    {
        if !.fullScreen do
            return
        let height = .clientRect().height
        let top    = position.y <= ViewerFullScreenRevealEdge or (.fullScreenTopVisible and position.y <= ViewerBarHeight + ViewerInfoHeight)
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
        if !.fullScreen do
            return
        let rect = .clientRect()
        .commandBar.show(.fullScreenTopVisible)
        .infoBar.show(.fullScreenTopVisible)
        .viewerBar.show(.fullScreenBottomVisible and .currentCommands != null)
        if .fullScreenTopVisible
        {
            .commandBar.setPosition({rect.x, rect.y, rect.width, ViewerBarHeight}, computeLayout: false)
            .infoBar.setPosition({rect.x, rect.y + ViewerBarHeight, rect.width, ViewerInfoHeight}, computeLayout: false)
            .commandBar.applyLayout()
            .infoBar.applyLayout()
            .commandBar.bringToFront()
            .infoBar.bringToFront()
        }

        if .fullScreenBottomVisible
        {
            .viewerBar.setPosition({rect.x, rect.bottom() - ViewerBarHeight, rect.width, ViewerBarHeight}, computeLayout: false)
            .viewerBar.applyLayout()
            .viewerBar.bringToFront()
        }
    }

    func create(parent: *Wnd, index: ViewerIndex)->*ViewerWindow
    {
        let result = Wnd.create'ViewerWindow(parent, "sFileScope.main")
        result.surface!.setView(result)
        result.surface!.minSize = {ViewerMinWidth, 420}
        result.backgroundStyle  = .View
        result.index            = #move index
        result.language         = Gui.ReferenceLanguage
        result.icons.setup(result.app().renderer, viewerIcons())

        result.appearanceButton                 = AppearanceButton.create(result.surface!, "sFileScope.appearance")
        result.appearanceButton.sigThemeChanged += func|window = result|(button)
        {
            window.themeIndex = button.appearanceTheme == .Light ? 1 : 0
            catch window.saveState()
        }
        result.appearanceButton.sigLanguageChanged += func|window = result|(button)
        {
            window.language = button.language
            catch window.saveState()
        }
        result.appearanceButton.sigAboutRequested += func|window = result|(button)
        {
            discard button
            window.showAbout()
        }

        result.accentRail = Separator.create(result, .Top, .Accent)

        result.commandBar = ViewerActionBar.create(result)

        with result.openButton = IconButton.create(result.commandBar, result.theme().icon(.OpenFile, ViewerGlyphSize), {0, 0, 36, 36})
        {
            .dockStyle  = .Left
            .margin.z   = 8
            .toolTip    = appStrings().ui_Open
            .sigPressed += func|window = result|(button)
            {
                discard button
                window.chooseFile()
            }
        }

        with result.filesButton = IconButton.create(result.commandBar, result.theme().icon(.History, ViewerGlyphSize), {0, 0, 36, 36}, flags: .Toggle)
        {
            .dockStyle = .Left
            .margin.z  = 8
            .toolTip   = appStrings().ui_Files
            .setCheckIndicator(.Frame)
            .sigCheckedChanged += func|window = result|(button)
            {
                window.setFilePanelVisible(button.isChecked)
                catch window.saveState()
            }
        }

        with result.fullScreenButton = IconButton.create(result.commandBar, result.theme().icon(.FullScreen, ViewerGlyphSize), {0, 0, 36, 36}, flags: .Toggle)
        {
            .dockStyle = .Right
            .toolTip   = appStrings().ui_FullScreen
            .setCheckIndicator(.Frame)
            .sigCheckedChanged += func|window = result|(button)
            {
                window.setFullScreen(button.isChecked)
            }
        }

        with result.searchGroup = StackLayoutCtrl.create(result.commandBar, .Center, {0, 0, ViewerSearchBarWidth, 36})
        {
            .backgroundStyle = .Transparent
            .spacing         = 0
            .hide()
        }

        result.commandBar.searchGroup = result.searchGroup

        with result.searchMatchCase = IconButton.create(result.searchGroup, {}, {0, 0, ViewerSearchButtonSize, ViewerSearchButtonSize}, flags: .Toggle | .CenterContent)
        {
            .layoutSpec.alignY = .Center
            .toolTip           = appStrings().ui_SearchMatchCase
            .setText("Aa")
            .setCheckIndicator(.Frame)
            .sigCheckedChanged += func|window = result|(button)
            {
                window.searchMatchCaseOption = button.isChecked
                window.restartSearch()
                catch window.saveState()
            }
        }

        with result.searchWholeWord = IconButton.create(result.searchGroup, {}, {0, 0, ViewerSearchButtonSize, ViewerSearchButtonSize}, flags: .Toggle | .CenterContent)
        {
            .layoutSpec.alignY = .Center
            .toolTip           = appStrings().ui_SearchWholeWord
            .setText("ab")
            .setCheckIndicator(.Frame)
            .sigCheckedChanged += func|window = result|(button)
            {
                window.searchWholeWordOption = button.isChecked
                window.restartSearch()
                catch window.saveState()
            }
        }

        with result.searchBox = EditBox.create(result.searchGroup, "", {0, 0, ViewerSearchFieldWidth, 36}, flags: .ClearButton)
        {
            .setIcon(result.theme().icon(.Search, 18))
            .setPlaceholder(appStrings().ui_Search)
            .sigTextChanged += func|window = result|(edit)
            {
                discard edit
                window.restartSearch()
            }
            .sigSubmitted += func|window = result|(edit)
            {
                discard edit
                window.findNext()
            }
            .sigCancelled += func|window = result|(edit)
            {
                discard edit
                window.hideSearch()
            }
            .enable(false)
        }

        with result.searchPrevious = IconButton.create(result.searchGroup, result.theme().icon(.SearchPrevious, 16), {0, 0, ViewerSearchButtonSize, ViewerSearchButtonSize})
        {
            .layoutSpec.alignY = .Center
            .toolTip           = appStrings().ui_SearchPrevious
            .sigPressed        += func|window = result|(button)
            {
                discard button
                window.findPrevious()
            }
            .enable(false)
        }

        with result.searchNext = IconButton.create(result.searchGroup, result.theme().icon(.SearchNext, 16), {0, 0, ViewerSearchButtonSize, ViewerSearchButtonSize})
        {
            .layoutSpec.alignY = .Center
            .toolTip           = appStrings().ui_SearchNext
            .sigPressed        += func|window = result|(button)
            {
                discard button
                window.findNext()
            }
            .enable(false)
        }

        with result.searchCountLabel = Label.create(result.searchGroup, "", {0, 0, ViewerSearchCountWidth, 36}, null, .SecondaryText)
        {
            .margin.x = 8
            .style.setFont(result.theme().createDefaultFontFS(12), .Regular)
            .setTextAlignment(.Left, .OpticalCenter)
        }

        result.commandBar.centerSearchGroup()

        // Wide enough for the longest viewer name a shipped viewer registers beside its glyph.
        // Viewer commands now have their own row, so this global bar stays compact at every width.
        with result.viewerCombo = ComboBox.create(result.commandBar, {0, 0, 180, 36})
        {
            .dockStyle = .Right
            .margin.z  = 12
            .toolTip   = appStrings().ui_Viewer
            .hide()
            .sigChanged += func|window = result|(combo, index)
            {
                discard combo
                window.selectViewer(index)
            }
        }

        // File identity and content statistics are read before the document. Viewer tools belong
        // to the dedicated band below it, where a transport can spend the width it needs.
        with result.infoBar = Wnd.create'ViewerInfoBar(result, {0, 0, 0, ViewerInfoHeight})
        {
            .dockStyle       = .Top
            .backgroundStyle = .View
            .padding         = {14, 4, 14, 4}
        }

        with result.infoStatsLabel = Label.create(result.infoBar, "", {0, 0, 0, 32}, null, .SecondaryText | .Ellipsis)
        {
            .dockStyle = .Right
            .maxSize.x = ViewerInfoStatsMaxWidth
            .style.setFont(result.theme().createDefaultFontFS(12), .Regular)
            .setTextAlignment(.Right, .OpticalCenter)
        }

        with result.infoFileGroup = StackLayoutCtrl.create(result.infoBar, .Left, {0, 0, 0, 32})
        {
            .dockStyle       = .Center
            .backgroundStyle = .Transparent
            .spacing         = 0
        }

        with result.infoIconLabel = Label.create(result.infoFileGroup, "", {0, 0, 24, 32})
        {
            .margin.z = 4
            .setIconAlignment(.Center, .Center)
        }

        with result.infoNameLabel = Label.create(result.infoFileGroup, "", {0, 0, 0, 32}, null, .Ellipsis)
        {
            .layoutSpec.policyX = .Expand
            .layoutSpec.weightX = 0
            .style.setFont(result.theme().createDefaultFont(13, .Bold), .Regular)
            .setTextAlignment(.Left, .OpticalCenter)
        }

        with result.infoSizeLabel = Label.create(result.infoFileGroup, "", {0, 0, 0, 32}, null, .SecondaryText)
        {
            .margin.x = 8
            .style.setFont(result.theme().createDefaultFontFS(12), .Regular)
            .setTextAlignment(.Left, .OpticalCenter)
        }

        with result.viewerBar = Wnd.create'Wnd(result, {0, 0, 0, ViewerBarHeight})
        {
            .dockStyle       = .Bottom
            .backgroundStyle = .Window
            .padding         = {12, 6, 12, 6}
            .hide()
        }

        // What is beside the current file, and what was read before it. The panel is docked before
        // the document so the two lists take their width off the left edge, and it stays hidden
        // until a reader asks for it: the document keeps the whole surface by default.
        with result.filePanel = SplitterCtrl.create(result, {0, 0, ViewerPanelWidth, 0}, vertical: true)
        {
            .dockStyle       = .Left
            .minSize.x       = ViewerPanelWidth
            .maxSize.x       = ViewerPanelWidth
            .backgroundStyle = .Window
            .hide()
        }

        Separator.create(result.filePanel, .Right)

        with result.recentPane = Wnd.create'Wnd(result.filePanel)
        {
            .backgroundStyle = .Window
            .padding         = {0, 8, 0, 8}
        }

        with let recentHeader = Wnd.create'Wnd(result.recentPane, {0, 0, 0, ViewerPanelLabel})
        {
            .dockStyle       = .Top
            .backgroundStyle = .Window
            .margin          = {10, 0, 10, 0}
        }

        with result.recentClearButton = IconButton.create(recentHeader, result.theme().icon(.RemoveAll, 16), {0, 0, 24, 24})
        {
            .dockStyle  = .Right
            .toolTip    = appStrings().ui_ClearHistory
            .sigPressed += func|window = result|(button)
            {
                discard button
                window.confirmClearRecent()
            }
        }

        with result.recentLabel = Label.create(recentHeader, appStrings().ui_Recent, {0, 0, 0, ViewerPanelLabel}, null, .SecondaryText)
        {
            .dockStyle = .Center
            .style.setFont(result.theme().createDefaultFontFS(12), .Regular)
            .setTextAlignment(.Left, .Center)
        }

        with result.recentList = ListCtrl.createSimple(result.recentPane)
        {
            .dockStyle = .Center
            .setIconSize(ViewerRowGlyphSize)
            .setSelectionMode(.Single)
            .updateFlags(.HotTrack | .Ellipsis)
            .scrollWnd.padding.x = 0
            .scrollWnd.padding.z = 0
            .scrollWnd.updateFlags(.DisableHorizontal)
            .sigSelectionChanged += func|window = result|(list)
            {
                window.openListSelection(list, window.recent.toSlice())
            }
            .sigRightClicked += func|window = result|(list, position)
            {
                window.showFileMenu(list, window.recent.toSlice(), list.listView.localToSurface(position))
            }
        }

        with result.folderPane = Wnd.create'Wnd(result.filePanel)
        {
            .backgroundStyle = .Window
            .padding         = {0, 8, 0, 8}
        }

        // The header carries the filter beside the folder name: the toggle changes what this
        // list holds, and the next/previous arrows walk the same list.
        with let folderHeader = Wnd.create'Wnd(result.folderPane, {0, 0, 0, ViewerPanelLabel})
        {
            .dockStyle       = .Top
            .backgroundStyle = .Window
            .margin          = {10, 0, 10, 0}
        }

        with result.kindButton = IconButton.create(folderHeader, result.theme().icon(.Filter, 16), {0, 0, 24, 24}, flags: .Toggle)
        {
            .dockStyle = .Right
            .toolTip   = appStrings().ui_SameKind
            .setCheckIndicator(.Frame)
            .sigCheckedChanged += func|window = result|(button)
            {
                window.setFolderSameKind(button.isChecked)
            }
        }

        with result.folderLabel = Label.create(folderHeader, appStrings().ui_Folder, {0, 0, 0, ViewerPanelLabel}, null, .SecondaryText)
        {
            .dockStyle = .Center
            .style.setFont(result.theme().createDefaultFontFS(12), .Regular)
            .setTextAlignment(.Left, .Center)
        }

        with result.folderList = ListCtrl.createSimple(result.folderPane)
        {
            .dockStyle = .Center
            .setIconSize(ViewerRowGlyphSize)
            .setSelectionMode(.Single)
            .updateFlags(.HotTrack | .Ellipsis)
            .scrollWnd.padding.x = 0
            .scrollWnd.padding.z = 0
            .scrollWnd.updateFlags(.DisableHorizontal)
            .sigSelectionChanged += func|window = result|(list)
            {
                window.openListSelection(list, window.siblings.toSlice())
            }
            .sigRightClicked += func|window = result|(list, position)
            {
                window.showFileMenu(list, window.siblings.toSlice(), list.listView.localToSurface(position))
            }
        }

        with let recentItem = result.filePanel.addPane(result.recentPane, ViewerRecentHeight)
        {
            .minimumSize  = ViewerPaneMinSize
            .preserveSize = true
        }

        result.filePanel.addPane(result.folderPane).minimumSize = ViewerPaneMinSize

        with result.emptyView = StackLayoutCtrl.create(result, .VerticalCenter)
        {
            .dockStyle = .Center
            .padding   = {48, 48, 48, 48}
            .spacing   = 12
        }

        with result.emptyIconLabel = Label.create(result.emptyView, "", {0, 0, 48, 48})
        {
            .layoutSpec.alignX = .Center
            .setIconAlignment(.Center, .Center)
        }

        with result.emptyLabel = Label.create(result.emptyView, Format.toString("<b>%</b>", appStrings().ui_DropTitle), {0, 0, 480, 0}, null, .WordWrap | .AutoHeight)
        {
            .layoutSpec.alignX = .Center
            .setTextAlignment(.Center, .Center)
        }

        with result.emptyHintLabel = Label.create(result.emptyView, appStrings().ui_DropHint, {0, 0, 480, 0}, null, .WordWrap | .AutoHeight | .SecondaryText)
        {
            .layoutSpec.alignX = .Center
            .setTextAlignment(.Center, .Center)
        }

        result.loadingOverlay = ViewerLoadingOverlay.create(result)
        result.searchOverlay  = ViewerSearchOverlay.create(result)

        result.hookOnChildEvent = func|window = result|(wnd, evt)
        {
            discard wnd
            switch evt
            {
            case KeyEvent as key where window.routePlaybackKey(key):                    return true
            case KeyEvent as key where window.routeSearchNavigationKey(key):            return true
            case MouseEvent as mouse where mouse.kind == .Move or mouse.kind == .Enter: window.updateFullScreenChrome(mouse.surfacePos)
            }

            return false
        }

        result.applyLanguage()
        result.refreshArtwork()
        result.applyLayout()
        return result
    }

    // Opens the standard product identity and provenance dialog.
    mtd showAbout()
    {
        const BuildDate = #run Time.DateTime.now()
        let version = Format.toString("%.%.%", #swcversion, #swcrevision, #swcbuildnum)
        let dlg     = AboutDlg.createApplication(.surface!, {
            productName: "sFileScope",
            version: version.toString(),
            buildDate: BuildDate,
            sourceUrl: "https://github.com/swag-lang/swc/tree/master/bin/apps/modules/sFileScope",
            copyrightHolder: "Christophe Beaudet"})
        discard dlg.doModal()
    }

    // Opens `fileName` after the surface has had a chance to paint its first frame.
    mtd queueFile(fileName: string, remember = true)
    {
        .pendingFile = fileName
        .pendingEmpty.clear()
        .pendingRemember = remember
        .updateLoadingIndicator()
        if !.startupTimer do
            .startupTimer = .addTimer(1'ms)
    }

    // Advances one asynchronous file classification and publishes it only after the preceding
    // viewer has retired. Every filesystem probe stays on the worker side of this boundary.
    private mtd processQueuedFile()
    {
        if .choiceLoad.started
        {
            if !.choiceLoad.isDone()
            {
                .startupTimer = .addTimer(ViewerRetirePollInterval)
                return
            }

            if .choiceLoad.fileName != .pendingFile
            {
                discard .choiceLoad.finish()
                .choiceLoad.start(&.index, .pendingFile.toString(), appStrings().ui_BasicText, .recent.toSlice())
                .startupTimer = .addTimer(ViewerRetirePollInterval)
                return
            }

            .stopSearch()
            .searchMatch = Swag.U64.Max
            .searchQuery.clear()
            if !.destroyInstances(preserveVisible: true)
            {
                .startupTimer = .addTimer(ViewerRetirePollInterval)
                return
            }

            let remember   = .pendingRemember
            let classified = .choiceLoad.finish()
            .pendingFile.clear()
            if !classified.exists
            {
                .showEmpty(appStrings().ui_OpenStopped)
                return
            }

            .openClassifiedFile(#move classified, remember)
            return
        }

        .choiceLoad.start(&.index, .pendingFile.toString(), appStrings().ui_BasicText, .recent.toSlice())
        .startupTimer = .addTimer(ViewerRetirePollInterval)
    }

    // Starts the application smoke review. Each registered viewer owns one immutable fixture;
    // the real window opens them in registry order and explicitly selects the owner, including
    // the Binary and Hexadecimal viewers that normally appear as alternatives.
    mtd reviewSmokeFixtures(directory: string)
    {
        var absolute = catch Path.absolute(directory) as pathError
        if pathError != null or !Directory.exists(absolute)
        {
            .finishSmokeReview(1, Format.toString("sFileScope smoke fixture directory is missing: %", directory).toString())
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
        if @countof(message) do
            Console.println(message)
        if .smokeTimer
        {
            .removeTimer(.smokeTimer!)
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

        .finishSmokeReview(1, Format.toString("sFileScope smoke viewer '%' did not finish '%' after % readiness checks", key, fileName, ViewerSmokeStepLimit).toString())
    }

    private mtd reviewSmokeStep()
    {
        if .smokeSpecIndex > .index.specs.count
        {
            .finishSmokeReview(0, Format.toString("sFileScope smoke reviewed % viewers", .index.specs.count + 1).toString())
            return
        }

        let basicText = .smokeSpecIndex == .index.specs.count
        var key       = String.from(BasicTextViewerKey)
        var fixture   = String.from(BasicTextSmokeFixture)
        if !basicText
        {
            key     = .index.specs[.smokeSpecIndex].key
            fixture = .index.specs[.smokeSpecIndex].smokeFixture
        }

        let fileName = Path.combine(.smokeDirectory.toString(), fixture.toString())
        if !File.exists(fileName)
        {
            .finishSmokeReview(1, Format.toString("sFileScope smoke fixture is missing: %", fileName).toString())
            return
        }

        var absolute = catch Path.absolute(fileName) as pathError
        if pathError != null
        {
            .finishSmokeReview(1, Format.toString("sFileScope smoke cannot resolve fixture path: %", fileName).toString())
            return
        }

        if !.smokeOpened
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

        if !.smokeSelected
        {
            var selected = Swag.U32.Max
            for choice, index in .choices where choice.key == key and (basicText ? choice.kind == .BasicText : choice.kind == .Viewer)
            {
                selected = cast(u32) index
                break
            }

            if selected == Swag.U32.Max
            {
                .finishSmokeReview(1, Format.toString("sFileScope smoke fixture '%' has no '%' viewer", fileName, key).toString())
                return
            }

            if !.activateChoice(selected)
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
        if !instance.failureReason.isEmpty()
        {
            .finishSmokeReview(1, Format.toString("sFileScope smoke viewer '%' cannot open '%': %", key, fileName, instance.failureReason).toString())
            return
        }

        let loading  = instance.view and instance.isLoading and instance.isLoading!(instance.view!)
        let blocking = loading and instance.needsLoadingOverlay and instance.needsLoadingOverlay!(instance.view!)

        // Streaming text already has a presentable first chunk while it continues reading. Keep
        // it visible for a bounded interval so late errors cross the viewer contract; only a
        // viewer that says it has no presentable content (video before its first frame) blocks the
        // review until ready.
        if .smokeWaitSteps < ViewerSmokeMinimumSteps or (loading and (blocking or .smokeWaitSteps < ViewerSmokeExposureSteps))
        {
            .waitForSmokeViewer(key.toString(), fileName.toString())
            return
        }

        Console.println("sFileScope smoke reviewed '", key, "' with '", fixture, "'")
        .smokeSpecIndex += 1
        .smokeWaitSteps = 0
        .smokeOpened    = false
        .smokeSelected  = false
    }

    mtd chooseFile()
    {
        var options: FileDlgOptions
        options.state             = &.fileDlgState
        options.mode              = .SelectFile
        options.title             = appStrings().dlg_TitleOpen
        options.confirmButtonText = appStrings().dlg_ButtonOpen
        options.filters.add({appStrings().dlg_AllFiles, ""})

        let dialog = FileDlg.create(.surface!, options)
        if dialog.doModal() == Dialog.BtnOk do
            .queueFile(dialog.selectedPath())
    }

    mtd showEmpty(message: string)
    {
        .stopSearch()
        .searchQuery.clear()
        .searchMatches.clear()
        .searchIndex    = Swag.U64.Max
        .searchMatch    = Swag.U64.Max
        .searchComplete = false
        if !.destroyInstances()
        {
            .pendingEmpty = message
            if !.startupTimer do
                .startupTimer = .addTimer(ViewerRetirePollInterval)
            return
        }

        .stopLoadingIndicator()

        .emptyLabel.setText(Format.toString("<b>%</b>", message))
        .emptyView.show()
        .currentFile.clear()
        .currentFileSize.clear()
        .choices.clear()
        .viewerCombo.clear()
        .viewerCombo.hide()
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
        .infoBar.show(!.fullScreen or .fullScreenTopVisible)
        .viewerBar.hide()
        .surface!.setTitle(appStrings().ui_WindowTitle)
        .updateSearchAvailability()
        .applyLayout()
    }

    // Cooperatively retires every viewer without waiting on the GUI thread.
    mtd destroyInstances(preserveVisible = false)->bool
    {
        if !preserveVisible do
            .discardOutgoingViewer()

        for &instance in .instances
        {
            if !instance.retireView() do
                return false
        }

        let keepCurrent = preserveVisible and .currentView != null
        for &instance in .instances
        {
            if keepCurrent and instance.view == .currentView
            {
                .outgoingView     = instance.view
                .outgoingCommands = instance.commands
                instance.view     = null
                instance.commands = null
            }
            else
            {
                instance.commands?.destroy()
                instance.view?.destroy()
            }
        }

        .instances.clear()
        if !keepCurrent
        {
            .currentCommands = null
            .currentView     = null
            .viewerBar.hide()
        }

        return true
    }

    // Releases the retired presentation once its replacement is ready to cover it.
    private mtd discardOutgoingViewer()
    {
        if !.outgoingView do
            return
        let oldView     = .outgoingView!
        let oldCommands = .outgoingCommands
        .outgoingView     = null
        .outgoingCommands = null
        if .currentView == oldView do
            .currentView = null
        if oldCommands and .currentCommands == oldCommands do
            .currentCommands = null
        oldCommands?.destroy()
        oldView.destroy()
    }

    // Swaps presentations only after the incoming progressive viewer has something to show.
    mtd commitViewerTransition(expected: #null *Wnd = null)
    {
        if !.outgoingView or .activeChoiceIndex >= .instances.count do
            return
        let instance = &.instances[.activeChoiceIndex]
        if !instance.view or (expected and instance.view != expected) do
            return
        if instance.needsLoadingOverlay and instance.needsLoadingOverlay!(instance.view!) do
            return

        .discardOutgoingViewer()
        .currentView            = instance.view
        .currentCommands        = instance.commands
        .currentView!.dockStyle = .Center
        if .currentCommands do
            .currentCommands!.dockStyle = .Center
        .currentView!.show()
        .currentCommands?.show()
        .viewerBar.show(.currentCommands != null and (!.fullScreen or .fullScreenBottomVisible))
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
            if !instance.retireView() do
                return
            instance.commands?.destroy()
            instance.view?.destroy()

            let errorView = ViewerErrorView.create(me, message.toString())
            errorView.dockStyle          = .Center
            instance.view                = errorView
            instance.commands            = null
            instance.revealMatch         = null
            instance.searchBounds        = null
            instance.clearSearch         = null
            instance.collectMatches      = null
            instance.isLoading           = null
            instance.needsLoadingOverlay = null
            instance.retire              = null
            instance.failureReason       = #move message
            instance.details.clear()

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
            .currentCommands = null
            .viewerBar.hide()
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
        if !instance.view or !instance.isLoading or !instance.isLoading!(instance.view!) do
            return true

        if !instance.retireView() do
            return false
        instance.commands?.destroy()
        instance.view!.destroy()
        instance.view                = null
        instance.commands            = null
        instance.revealMatch         = null
        instance.searchBounds        = null
        instance.clearSearch         = null
        instance.collectMatches      = null
        instance.isLoading           = null
        instance.needsLoadingOverlay = null
        instance.retire              = null
        instance.details.clear()
        .currentView     = null
        .currentCommands = null
        .viewerBar.hide()
        return true
    }

    mtd stopLoadingIndicator()
    {
        if .loadingTimer
        {
            .removeTimer(.loadingTimer!)
            .loadingTimer = null
        }

        .loadingOverlay.hide()
    }

    mtd updateLoadingIndicator()
    {
        .commitViewerTransition()
        let pending     = !.pendingFile.isEmpty() or !.pendingEmpty.isEmpty()
        var loading     = pending
        var showOverlay = pending and .currentView != null
        if !loading and .activeChoiceIndex < .instances.count
        {
            let instance = &.instances[.activeChoiceIndex]
            loading     = instance.view and instance.isLoading and instance.isLoading!(instance.view!)
            showOverlay = loading and instance.needsLoadingOverlay and instance.needsLoadingOverlay!(instance.view!)
        }

        if showOverlay and .currentView
        {
            .loadingOverlay.cover(.currentView!.position)
            .loadingOverlay.show()
            .loadingOverlay.bringToFront()
            .layoutFullScreenChrome()
        }
        else do
            .loadingOverlay.hide()
        if loading and !.loadingTimer do
            .loadingTimer = .addTimer(50'ms)
        elif !loading and .loadingTimer
        {
            .removeTimer(.loadingTimer!)
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
            if !.retireActiveLoadingChoice(index) do
                return false
            .currentCommands?.hide()
            .currentView?.hide()
            .currentView     = instance.view
            .currentCommands = instance.commands
            .currentView!.show()
            .currentCommands?.show()
            .viewerBar.show(.currentCommands != null and (!.fullScreen or .fullScreenBottomVisible))
            .activeChoiceIndex = index
            .viewerCombo.setSelectedIndex(index, notify: false)
            .updateFileInfo(instance.details.toString())
            .updateSearchAvailability()
            .applyLayout()
            .updateLoadingIndicator()
            .invalidate()
            return true
        }

        var next: ViewerResult
        if choice.kind == .BasicText
        {
            let basic = BasicTextView.create(me, .viewerBar, .currentFile.toString(), &reportViewerDetails)
            next.view         = basic
            next.commands     = basic.commands
            next.revealMatch  = &basicTextRevealMatch
            next.searchBounds = &basicTextSearchBounds
            next.clearSearch  = &basicTextClearSearch
            next.isLoading    = &basicTextIsLoading
            next.details      = Format.toString(appStrings().ui_TextDetails, basic.encodingName())
        }
        else
        {
            let spec    = &.index.specs[choice.specIndex]
            let request = ViewerRequest{
                contentParent: me,
                commandParent: .viewerBar,
                fileName: .currentFile.toString(),
                reportFailure: &reportViewerFailure,
                reportDetails: &reportViewerDetails,
                reportLoadingChanged: &reportViewerLoadingChanged,
                navigateFile: &navigateViewerFile}
            catch spec.createView(&request, &next) as viewerError
            if viewerError != null
            {
                next.failureReason = Errors.message(viewerError)
                if next.failureReason.isEmpty() do
                    next.failureReason = appStrings().ui_OpenStopped
            }

            if !next.failureReason.isEmpty()
            {
                if next.view and next.retire do
                    discard next.retire!(next.view!)
                next.commands?.destroy()
                next.view?.destroy()
                next.commands            = null
                next.view                = ViewerErrorView.create(me, next.failureReason.toString())
                next.revealMatch         = null
                next.searchBounds        = null
                next.clearSearch         = null
                next.collectMatches      = null
                next.isLoading           = null
                next.needsLoadingOverlay = null
                next.retire              = null
                next.details.clear()
            }
        }

        if !next.view do
            return false

        if !.retireActiveLoadingChoice(index)
        {
            if next.retire do
                discard next.retire!(next.view!)
            next.commands?.destroy()
            next.view!.destroy()
            return false
        }

        let stage = .outgoingView != null
        if stage
        {
            next.view!.dockStyle = .None
            next.view!.setPosition(.outgoingView!.position, computeLayout: false)
            if next.commands
            {
                next.commands!.dockStyle = .None
                if .outgoingCommands do
                    next.commands!.setPosition(.outgoingCommands!.position, computeLayout: false)
            }

            .outgoingView!.bringToFront()
            .outgoingCommands?.bringToFront()
        }
        else
        {
            .currentCommands?.hide()
            .currentView?.hide()
            .currentView     = next.view
            .currentCommands = next.commands
        }

        .activeChoiceIndex = index
        if !stage do
            next.view!.dockStyle = .Center
        if next.commands
        {
            if !stage do
                next.commands!.dockStyle = .Center
            if !stage do
                .viewerBar.show(!.fullScreen or .fullScreenBottomVisible)
        }
        elif !stage do
            .viewerBar.hide()
        instance.view                = next.view
        instance.commands            = next.commands
        instance.revealMatch         = next.revealMatch
        instance.searchBounds        = next.searchBounds
        instance.clearSearch         = next.clearSearch
        instance.collectMatches      = next.collectMatches
        instance.isLoading           = next.isLoading
        instance.needsLoadingOverlay = next.needsLoadingOverlay
        instance.retire              = next.retire
        instance.details             = #move next.details
        instance.failureReason       = #move next.failureReason
        .viewerCombo.setSelectedIndex(index, notify: false)
        .updateFileInfo(instance.details.toString())
        .updateSearchAvailability()
        if stage do
            .commitViewerTransition(next.view)
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

    private mtd searchOptions()->ViewerSearchOptions => {.searchMatchCaseOption, .searchWholeWordOption}

    mtd restartSearch(selectLast = false)
    {
        .stopSearch()
        .searchMatches.clear()
        .searchIndex      = Swag.U64.Max
        .searchMatch      = Swag.U64.Max
        .searchComplete   = false
        .searchSelectLast = selectLast
        .searchQuery      = .searchBox.text()
        .refreshSearchReadout()

        if !.searchBox.isEnabled() or .searchQuery.isEmpty() or .currentFile.isEmpty() or .activeChoiceIndex >= .instances.count do
            return

        let instance = &.instances[.activeChoiceIndex]
        if instance.collectMatches and instance.view
        {
            instance.collectMatches!(instance.view!, .searchQuery.toString(), .searchOptions(), &.searchMatches)
            .finishSearch()
            return
        }

        .beginSearch()
    }

    private mtd navigateSearch(direction: s32)
    {
        if !.searchBox.isEnabled() or !@countof(.searchBox.text()) do
            return
        if .searchQuery != .searchBox.text()
        {
            .restartSearch(selectLast: direction < 0)
            return
        }

        if !.searchComplete or .searchMatches.isEmpty() do
            return

        if direction < 0 do
            .searchIndex = .searchIndex ? .searchIndex - 1 : .searchMatches.count - 1
        else do
            .searchIndex = (.searchIndex + 1) % .searchMatches.count
        .revealCurrentSearchMatch()
    }

    private mtd refreshSearchReadout()
    {
        if .searchQuery.isEmpty()
        {
            .searchCountLabel.setText("")
            .searchCountLabel.toolTip = ""
        }
        elif !.searchComplete
        {
            .searchCountLabel.setText("â€¦")
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

        let canNavigate = .searchComplete and !.searchMatches.isEmpty()
        .searchPrevious.enable(canNavigate)
        .searchNext.enable(canNavigate)
    }

    private mtd revealCurrentSearchMatch()
    {
        if .searchIndex >= .searchMatches.count or .activeChoiceIndex >= .instances.count do
            return
        let instance = &.instances[.activeChoiceIndex]
        if !instance.revealMatch or !instance.view do
            return

        // Revealing may legitimately focus a document when invoked outside the search bar. Live
        // typing is different: the viewer scrolls and selects behind the field, while the caret
        // stays in the query so the next letter extends it instead of going into the document.
        let preserveSearchFocus = .searchBox.hasFocus()
        defer if preserveSearchFocus do
            .searchBox.setFocus()

        let match = .searchMatches[.searchIndex]
        if !instance.revealMatch!(instance.view!, match, .searchQuery.toString()) do
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
        if !instance.view or !instance.searchBounds
        {
            .searchOverlay.hide()
            return
        }

        var bounds: Math.Rectangle
        if instance.searchBounds!(instance.view!, .searchMatches[.searchIndex], &bounds)
        {
            let viewport = instance.view!.surfaceRect()
            bounds.intersect(viewport)
            if !bounds.isEmpty() do
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
        if !.searchBoundsTimer do
            .searchBoundsTimer = .addTimer(ViewerSearchBoundsPoll)
    }

    private mtd finishSearch()
    {
        .stopSearch()
        .searchComplete = true
        if !.searchMatches.isEmpty()
        {
            .searchIndex = .searchSelectLast ? .searchMatches.count - 1 : 0
            .revealCurrentSearchMatch()
        }

        .refreshSearchReadout()
    }

    mtd showSearch()
    {
        if !.searchBox.isEnabled() do
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
    mtd viewerFocusTarget()->#null *Wnd
    {
        let view = .currentView
        if !view do
            return null
        let order = FocusOrder.collect(view!)
        let stop  = order.stops.isEmpty() ? view! : order.stops[0]!
        return stop!.focusTarget()
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
        let inSearchField   = focused and (focused! == .searchBox or .searchBox.isOwnerOf(focused!))
        let fieldNavigation = inSearchField and ((evt.modifiers == .None and (evt.key == .Up or evt.key == .Down)) or (evt.modifiers == .Control and (evt.key == .Home or evt.key == .End)))
        if !pageKey and !fieldNavigation do
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
        let key            = .choices[.activeChoiceIndex].key.toString()
        let playbackViewer = key == "video" or key == "sound" or key == "image"
        if !playbackViewer do
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
        if !target do
            return false

        // A key the viewer's key owner already saw and declined must not be offered twice.
        let focused = .focusedWindow()
        if skipFocused and focused and (focused! == target! or target!.isOwnerOf(focused!)) do
            return false

        let view = .currentView
        var copy = KeyEvent{kind: evt.kind, key: evt.key, modifiers: evt.modifiers}
        .forwardingViewerKey = true
        defer .forwardingViewerKey = false
        target!.sendEvent(&copy)

        // A declined key bubbles back here and navigates to another file, which destroys the
        // viewer the key was offered to; only a viewer that is still showing takes the keyboard.
        if takeFocus and copy.accepted and .currentView == view do
            target!.setFocus()
        return copy.accepted
    }

    mtd updateSearchAvailability()
    {
        let active         = .activeChoiceIndex < .instances.count
        let available      = active and .instances[.activeChoiceIndex].revealMatch != null
        let focused        = .focusedWindow()
        let searchHadFocus = focused and (focused! == .searchGroup or .searchGroup.isOwnerOf(focused!))

        .searchBox.enable(available)
        .searchMatchCase.enable(available)
        .searchWholeWord.enable(available)
        .searchGroup.show(available)
        if available do
            .commandBar.centerSearchGroup()
        .restartSearch()
        if !available and searchHadFocus do
            .viewerFocusTarget()?.setFocus()
    }

    mtd stopSearch()
    {
        if .searchTimer
        {
            .removeTimer(.searchTimer!)
            .searchTimer = null
        }

        .searchStream.close()
        .searchCarry.clear()
        if .activeChoiceIndex < .instances.count
        {
            let instance = &.instances[.activeChoiceIndex]
            if instance.view and instance.clearSearch do
                instance.clearSearch!(instance.view!)
        }

        if .searchBoundsTimer
        {
            .removeTimer(.searchBoundsTimer!)
            .searchBoundsTimer = null
        }

        .searchOverlay.hide()
    }

    mtd beginSearch()
    {
        .searchStream = catch File.openRead(.currentFile.toString()) as openError
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
        if !.searchStream.isOpen() do
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
        .searchCarry += @mkstring(bytes.buffer!, bytes.count)
        let eof       = count == 0
        let deferSize = .searchQuery.length + ViewerSearchCarryMargin
        let stableEnd = eof ? .searchCarry.length : (.searchCarry.length > deferSize ? .searchCarry.length - deferSize : 0)

        var candidates: Array'ViewerSearchMatch
        collectViewerTextMatches(.searchCarry.toString(), .searchQuery.toString(), .searchOptions(), 0, 0, .searchCarryBase, &candidates)
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
            .infoIconLabel.setIcon(.icon(.choices[.activeChoiceIndex].icon))
        .infoIconLabel.setIconColor(.themeColors().label_TextFaint)
        .layoutFileInfo()
        .infoBar.show(!.fullScreen or .fullScreenTopVisible)
    }

    // Measures the identity row again after asynchronous metadata changes. The file name is
    // rounded outward because the stack places children on whole logical units; rounding its
    // fractional glyph extent down is enough to paint an ellipsis on an otherwise complete name.
    private mtd layoutFileInfo()
    {
        .infoNameLabel.preferredSize.x = Math.ceil(.infoNameLabel.itf.measureContent({}).x)
        .infoBar.applyLayout()
    }

    mtd selectViewer(index: u32)
    {
        if index == .activeChoiceIndex do
            return
        if !.activateChoice(index)
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
        .currentFile     = #move classified.absoluteFileName
        .currentFileSize = #move classified.fileSize
        .choices         = #move classified.choices
        .folderFiles     = #move classified.folderFiles
        .recent          = #move classified.recent
        .siblingsDirty   = true
        .rebuildSiblings()
        .instances.resize(.choices.count)
        .viewerCombo.clear()
        for choice in .choices do
            .viewerCombo.addItem(choice.name.toString(), icon: .icon(choice.icon))
        .viewerCombo.show()

        var selected = .preferredChoiceIndex()
        if !.activateChoice(selected)
        {
            selected = Swag.U32.Max
            for choice, index in .choices where choice.kind == .BasicText
            {
                discard choice
                selected = cast(u32) index
                break
            }

            if selected == Swag.U32.Max or !.activateChoice(selected)
            {
                .showEmpty(appStrings().ui_Unsupported)
                return
            }
        }

        .emptyView.hide()

        if remember do
            .rememberRecent(.currentFile.toString())
        if .panelVisible do
            .refreshFileLists()

        .applyLayout()
        .invalidate()
    }

    mtd retranslate()
    {
        let texts = appStrings()
        .surface?.setTitle(texts.ui_WindowTitle)
        .openButton.toolTip        = texts.ui_Open
        .filesButton.toolTip       = texts.ui_Files
        .fullScreenButton.toolTip  = .fullScreen ? texts.ui_ExitFullScreen : texts.ui_FullScreen
        .kindButton.toolTip        = texts.ui_SameKind
        .recentClearButton.toolTip = texts.ui_ClearHistory
        .viewerCombo.toolTip       = texts.ui_Viewer
        .searchPrevious.toolTip    = texts.ui_SearchPrevious
        .searchNext.toolTip        = texts.ui_SearchNext
        .searchMatchCase.toolTip   = texts.ui_SearchMatchCase
        .searchWholeWord.toolTip   = texts.ui_SearchWholeWord
        .searchBox.setPlaceholder(texts.ui_Search)
        .refreshSearchReadout()
        .recentLabel.setText(texts.ui_Recent)
        for &instance in .instances where instance.view and !instance.failureReason.isEmpty() do
            (cast(*ViewerErrorView) instance.view!).retranslate()
        if .currentFile.isEmpty() do
            .folderLabel.setText(texts.ui_Folder)
        if .currentFile.isEmpty()
        {
            .emptyLabel.setText(Format.toString("<b>%</b>", texts.ui_DropTitle))
            .emptyHintLabel.setText(texts.ui_DropHint)
            .infoStatsLabel.setText("")
        }

        .invalidate()
    }

    // Shows or hides the panel listing what is beside the current file.
    mtd toggleFilePanel()
    {
        .setFilePanelVisible(!.panelVisible)
        catch .saveState()
    }

    mtd setFilePanelVisible(visible: bool)
    {
        .panelVisible = visible
        .filesButton.setChecked(visible)
        if visible and !.fullScreen
        {
            .refreshFileLists()
            .filePanel.show()

            // A splitter's first pane takes the whole client height it is added into, which is
            // nothing at all before the window has been laid out once, and a preserved pane then
            // holds that nothing for the rest of the session. The history section takes the height
            // it was given here instead, once the panel is on screen with a size to divide.
            .applyLayout()
            if .filePanel.isPaneVisible(0) and .filePanel.items[0]!.size != .recentPaneSize do
                .filePanel.setPaneSize(0, .recentPaneSize)
        }
        else do
            .filePanel.hide()

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

    // Fills one list with file names, selecting the row that names the current file.
    private mtd fillFileList(list: *ListCtrl, files: const [..] String)
    {
        let scrollPosition = list.scrollWnd.scrollPosition()
        list.clear()
        for one, index in files
        {
            let name               = one[].toString()
            var glyph: ViewerIcons = undefined
            let icon               = .index.nameIcon(name, &glyph) ? .icon(glyph) : Icon{}
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

        let hasRecent = !.recent.isEmpty()
        .filePanel.setPaneVisible(0, hasRecent)
        .folderLabel.setText(Path.fileName(Path.directoryName(.currentFile.toString())) orelse appStrings().ui_Folder)
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
        if !line do
            return
        let index = line!.index
        if index >= @countof(files) do
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

    // Shows what one file offers, wherever the reader pointed at it.
    private mtd showFileActions(fileName: string, position: Math.Point, history: bool)
    {
        let texts = appStrings()
        let menu  = MenuCtrl.createPopup(me, owner: me)
        menu.addItem(texts.ui_MenuLocate, "sFileScope.file.locate", .theme().icon(.OpenFile, ViewerRowGlyphSize))
        menu.addItem(texts.ui_MenuOpenWith, "sFileScope.file.openWith", .theme().icon(.Export, ViewerRowGlyphSize))
        menu.addSeparator()
        menu.addItem(texts.ui_MenuCopyPath, "sFileScope.file.copyPath", .theme().icon(.Copy, ViewerRowGlyphSize))
        menu.addItem(texts.ui_MenuCopyName, "sFileScope.file.copyName", .theme().icon(.Copy, ViewerRowGlyphSize))
        if history
        {
            menu.addSeparator()
            menu.addItem(texts.ui_MenuForget, "sFileScope.file.forget", .theme().icon(.Remove, ViewerRowGlyphSize))
        }

        let chosen = menu.doModal(position, .TopLeft, autoDestroy: true)
        if !chosen do
            return

        switch chosen!
        {
        case "sFileScope.file.locate":   Env.showInFileExplorer(fileName)
        case "sFileScope.file.openWith": Env.openFileWith(fileName)
        case "sFileScope.file.copyPath": Clipboard.addString(fileName)
        case "sFileScope.file.copyName": Clipboard.addString(Path.fileName(fileName) orelse fileName)
        case "sFileScope.file.forget":   .forgetRecent(fileName)
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
        if selected.isEmpty() or !selected[0] do
            return
        let index = selected[0]!.index
        if index >= @countof(files) do
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
            if .folderSameKind and !.index.sharesViewer(.currentFile.toString(), file[].toString()) do
                continue
            .siblings.add(file[])
        }

        for i in @countof(.siblings) where .siblings[i] == .currentFile
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
        if .panelVisible and !.currentFile.isEmpty() do
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
}
