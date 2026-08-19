using Core, Pixel, Gui

const ViewerBarHeight       = 48.0
const ViewerInfoHeight      = 36.0
const ViewerGlyphSize       = 20.0
const ViewerMinWidth        = 1200
const ViewerSearchChunkSize = 256 * 1024'u64
const ViewerErrorTextWidth  = 512.0

// The panel that lists what is beside the current file, and what was read before it.
const ViewerPanelWidth   = 268.0
const ViewerPanelLabel   = 26.0
const ViewerRecentHeight = 188.0
const ViewerPaneMinSize  = 88.0

// Files the recent list keeps. Long enough to cross a working session, short enough that the list
// stays something a reader scans rather than searches.
const ViewerRecentCount = 12'u64

struct ViewerInstance
{
    view:          #null *Wnd
    commands:      #null *Wnd
    revealMatch:   #null ViewerRevealMatch
    findText:      #null ViewerFindText
    isLoading:     #null ViewerIsLoading
    details:       String
    failureReason: String
}

// Host-owned presentation for every plugin failure.
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

func reportViewerFailure(view: *Wnd, reason: string)
{
    let window = cast(*ViewerWindow) view.parent!
    window.reportPluginFailure(view, reason)
}

struct ViewerWindow
{
    using wnd: Wnd

    #[Swag.Late]
    {
        commandBar:       *Wnd
        previousButton:   *IconButton
        nextButton:       *IconButton
        kindButton:       *IconButton
        openButton:       *IconButton
        filesButton:      *IconButton
        searchBox:        *EditBox
        viewerCombo:      *ComboBox
        appearanceButton: *AppearanceButton
        infoBar:          *Wnd
        infoNameLabel:    *Label
        infoStatsLabel:   *Label
        loadingSpinner:   *Spinner
        emptyLabel:       *Label
        filePanel:        *SplitterCtrl
        recentPane:       *Wnd
        recentLabel:      *Label
        recentList:       *ListCtrl
        folderPane:       *Wnd
        folderLabel:      *Label
        folderList:       *ListCtrl
    }

    index:           ViewerPluginIndex
    plugins:         ViewerPluginManager
    currentView:     #null *Wnd
    currentCommands: #null *Wnd
    choices:         Array'ViewerChoice
    instances:       Array'ViewerInstance
    activeChoiceIndex    = Swag.U32.Max
    startupTimer:    #null *Timer
    searchTimer:     #null *Timer
    loadingTimer:    #null *Timer
    searchStream:    File.FileStream
    searchQuery:     String
    searchCarry:     String
    searchOffset:    u64
    searchMatch:     u64 = Swag.U64.Max
    searchWrapped:   bool
    pendingFile:     String
    currentFile:     String
    siblings:        Array'String
    siblingIndex:    u64
    siblingsDirty        = true

    // Whether next/previous and the folder list keep only the neighbours the current file's
    // viewer would open, so a reader flips through the pictures of a folder without landing on
    // the notes stored beside them.
    folderSameKind: bool

    // Guards the one nested dispatch [[forwardKeyToViewer]] makes, so a key the viewer
    // declines falls back to file navigation instead of being offered again.
    forwardingViewerKey: bool
    recent:          Array'String
    panelVisible:    bool
    recentPaneSize       = ViewerRecentHeight
    refreshingLists: bool
    fileDlgState:    FileDlgState
    themeIndex:      u32
    language:        String
}

impl IWnd for ViewerWindow
{
    mtd impl onDragDropEvent(evt: *DragDropEvent)
    {
        let fileName = evt.data.singleFile()
        if !fileName
        {
            evt.accepted = false
            return
        }

        if evt.kind == .Drop do
            .openFile(fileName)
        evt.effect = pickDropEffect(evt.allowed & (DropEffect.Copy | DropEffect.Link), evt.modifiers)
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind != .Pressed
        {
            evt.accepted = false
            return
        }

        if evt.key == .O and evt.modifiers.has(.Control) do
            .chooseFile()
        elif evt.key == .F and evt.modifiers.has(.Control) do
            .showSearch()
        elif evt.key == .F3 and evt.modifiers == .None do
            .findNext()
        elif evt.key == .Left and evt.modifiers == .None do
            .navigateOrForward(-1, evt)
        elif evt.key == .Right and evt.modifiers == .None do
            .navigateOrForward(1, evt)
        elif evt.key == .F5 and !.currentFile.isEmpty() do
            .openFile(.currentFile.toString())
        else do
            evt.accepted = false
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
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

        if evt.timer != .startupTimer
        {
            evt.accepted = false
            return
        }

        .removeTimer(.startupTimer!)
        .startupTimer = null
        if !.pendingFile.isEmpty()
        {
            let fileName = #move .pendingFile
            .openFile(fileName.toString())
        }
    }

    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        catch g_App.saveState()
        .stopSearch()
        .stopLoadingIndicator()
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
        catch evt.serializer.serialize("ViewerWindow.panelVisible", &me.panelVisible)
        catch evt.serializer.serialize("ViewerWindow.recentPaneSize", &me.recentPaneSize)
        catch evt.serializer.serialize("ViewerWindow.folderSameKind", &me.folderSameKind)
        if evt.serializer.isReading()
        {
            .themeIndex     = Math.min(.themeIndex, 1)
            .recentPaneSize = Math.max(.recentPaneSize, ViewerPaneMinSize)
            if .filePanel.items.count do
                .filePanel.items[0]!.size = .recentPaneSize
            while .recent.count > ViewerRecentCount do
                .recent.removeAtOrdered(.recent.count - 1)
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
        }

        .wnd.IWnd.onNotifyEvent(evt)
    }
}

impl ViewerWindow
{
    mtd applyTheme(index: u32)
    {
        .themeIndex = Math.min(index, 1)
        .appearanceButton.setAppearanceTheme(.themeIndex ? .Light : .Dark)
    }

    mtd applyLanguage()
    {
        discard catch .appearanceButton.setAppearanceLanguage(.language.toString())
    }

    func create(parent: *Wnd, index: ViewerPluginIndex)->*ViewerWindow
    {
        let result = Wnd.create'ViewerWindow(parent, "sFileScope.main")
        result.surface!.setView(result)
        result.surface!.minSize = {ViewerMinWidth, 420}
        result.backgroundStyle  = .View
        result.index            = #move index
        result.language         = Gui.ReferenceLanguage

        result.appearanceButton                 = AppearanceButton.create(result.surface!, "sFileScope.appearance")
        result.appearanceButton.sigThemeChanged += func|window = result|(button)
        {
            window.themeIndex = button.appearanceTheme == .Light ? 1 : 0
            catch g_App.saveState()
        }
        result.appearanceButton.sigLanguageChanged += func|window = result|(button)
        {
            window.language = button.language
            catch g_App.saveState()
        }

        Separator.create(result, .Top, .Accent)

        with result.commandBar = Wnd.create'Wnd(result, {0, 0, 0, ViewerBarHeight})
        {
            .dockStyle       = .Top
            .backgroundStyle = .Window
            .padding         = {12, 6, 12, 6}
        }

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
                catch g_App.saveState()
            }
        }

        with result.searchBox = EditBox.create(result.commandBar, "", {0, 0, 240, 36})
        {
            .dockStyle = .Left
            .margin.x  = 12
            .setIcon(result.theme().icon(.Search, 18))
            .setPlaceholder(appStrings().ui_Search)
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

        with result.previousButton = IconButton.create(result.commandBar, result.theme().icon(.ChevronLeft, ViewerGlyphSize), {0, 0, 36, 36})
        {
            .dockStyle = .Left
            .toolTip   = appStrings().ui_Previous
            .enable(false)
            .sigPressed += func|window = result|(button)
            {
                discard button
                window.navigate(-1)
            }
        }

        with result.nextButton = IconButton.create(result.commandBar, result.theme().icon(.ChevronRight, ViewerGlyphSize), {0, 0, 36, 36})
        {
            .dockStyle = .Left
            .toolTip   = appStrings().ui_Next
            .enable(false)
            .sigPressed += func|window = result|(button)
            {
                discard button
                window.navigate(1)
            }
        }

        // Wide enough for the longest viewer name a shipped plugin registers, so the selector
        // never cuts the one word that says which viewer is showing the file.
        with result.viewerCombo = ComboBox.create(result.commandBar, {0, 0, 156, 36})
        {
            .dockStyle = .Left
            .margin.x  = 12
            .toolTip   = appStrings().ui_Viewer
            .hide()
            .sigChanged += func|window = result|(combo, index)
            {
                discard combo
                window.selectViewer(index)
            }
        }

        // File identity belongs to a quiet, compact band under the document. The only band above
        // the content is the contextual action bar shared by navigation, viewer choice and tools.
        with result.infoBar = Wnd.create'Wnd(result, {0, 0, 0, ViewerInfoHeight})
        {
            .dockStyle       = .Bottom
            .backgroundStyle = .Window
            .padding         = {14, 4, 14, 4}
        }

        with result.infoStatsLabel = Label.create(result.infoBar, appStrings().ui_Ready, {0, 0, 280, 28}, null, .SecondaryText)
        {
            .dockStyle = .Right
            .style.setFont(result.theme().createDefaultFontFS(12), .Regular)
            .setTextAlignment(.Right, .Center)
        }

        with result.loadingSpinner = Spinner.create(result.infoBar, {0, 0, 18, 18})
        {
            .dockStyle = .Right
            .margin.x  = 8
            .hide()
        }

        with result.infoNameLabel = Label.create(result.infoBar, "", {0, 0, 0, 28})
        {
            .dockStyle = .Center
            .style.setFont(result.theme().createDefaultFontFS(result.themeMetrics().defaultFixedFontSize), .Regular)
            .setTextAlignment(.Left, .Center)
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
            .padding         = {10, 8, 10, 8}
        }

        with result.recentLabel = Label.create(result.recentPane, appStrings().ui_Recent, {0, 0, 0, ViewerPanelLabel}, null, .SecondaryText)
        {
            .dockStyle = .Top
            .style.setFont(result.theme().createDefaultFontFS(12), .Regular)
            .setTextAlignment(.Left, .Center)
        }

        with result.recentList = ListCtrl.createSimple(result.recentPane)
        {
            .dockStyle = .Center
            .setSelectionMode(.Single)
            .updateFlags(.HotTrack | .Ellipsis)
            .scrollWnd.updateFlags(.DisableHorizontal)
            .sigSelectionChanged += func|window = result|(list)
            {
                window.openListSelection(list, window.recent.toSlice())
            }
        }

        with result.folderPane = Wnd.create'Wnd(result.filePanel)
        {
            .backgroundStyle = .Window
            .padding         = {10, 8, 10, 8}
        }

        // The header carries the filter beside the folder name: the toggle changes what this
        // list holds, and the next/previous arrows walk the same list.
        with let folderHeader = Wnd.create'Wnd(result.folderPane, {0, 0, 0, ViewerPanelLabel})
        {
            .dockStyle       = .Top
            .backgroundStyle = .Window
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
            .setSelectionMode(.Single)
            .updateFlags(.HotTrack | .Ellipsis)
            .scrollWnd.updateFlags(.DisableHorizontal)
            .sigSelectionChanged += func|window = result|(list)
            {
                window.openListSelection(list, window.siblings.toSlice())
            }
        }

        with let recentItem = result.filePanel.addPane(result.recentPane, ViewerRecentHeight)
        {
            .minimumSize  = ViewerPaneMinSize
            .preserveSize = true
        }

        result.filePanel.addPane(result.folderPane).minimumSize = ViewerPaneMinSize

        with result.emptyLabel = Label.create(result, Format.toString("<b>%</b>", appStrings().ui_DropTitle), {}, null, .WordWrap)
        {
            .dockStyle = .Center
            .padding   = {48, 48, 48, 48}
            .setTextAlignment(.Center, .Center)
        }

        result.applyLanguage()
        result.applyLayout()
        return result
    }

    // Opens `fileName` after the surface has had a chance to paint its first frame.
    mtd queueFile(fileName: string)
    {
        .pendingFile = fileName
        if !.startupTimer do
            .startupTimer = .addTimer(1'ms)
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
            .openFile(dialog.selectedPath())
    }

    mtd showEmpty(message: string)
    {
        .stopSearch()
        .searchQuery.clear()
        .searchMatch = Swag.U64.Max
        .destroyInstances()

        .emptyLabel.setText(message)
        .emptyLabel.show()
        .currentFile.clear()
        .choices.clear()
        .viewerCombo.clear()
        .viewerCombo.hide()
        .activeChoiceIndex = Swag.U32.Max
        .siblings.clear()
        .siblingsDirty = true
        .infoNameLabel.setText("")
        .infoNameLabel.toolTip = ""
        .infoStatsLabel.setText(appStrings().ui_Ready)
        .surface!.setTitle(appStrings().ui_WindowTitle)
        .previousButton.enable(false)
        .nextButton.enable(false)
        .searchBox.enable(false)
        .applyLayout()
    }

    mtd destroyInstances()
    {
        .stopLoadingIndicator()
        for &instance in .instances
        {
            instance.commands?.destroy()
            instance.view?.destroy()
        }

        .instances.clear()
        .currentCommands = null
        .currentView     = null
    }

    // Replaces a plugin view that stopped after creation with the host's standard error surface.
    mtd reportPluginFailure(view: *Wnd, reason: string)
    {
        var message = String.from(reason)
        if message.isEmpty() do
            message = appStrings().ui_OpenStopped

        for &instance, index in .instances where instance.view == view
        {
            instance.commands?.destroy()
            instance.view?.destroy()

            let errorView = ViewerErrorView.create(me, message.toString())
            errorView.dockStyle    = .Center
            instance.view          = errorView
            instance.commands      = null
            instance.revealMatch   = null
            instance.findText      = null
            instance.isLoading     = null
            instance.failureReason = #move message
            instance.details.clear()

            if index != .activeChoiceIndex
            {
                errorView.hide()
                return
            }

            .stopLoadingIndicator()
            .currentView     = errorView
            .currentCommands = null
            .updateFileInfo("")
            .updateSearchAvailability()
            .applyLayout()
            .invalidate()
            return
        }
    }

    // Discards a hidden progressive view before opening another renderer. HTML and Markdown
    // otherwise keep parsing and laying out a document the reader can no longer see.
    private mtd retireActiveLoadingChoice(nextIndex: u32)
    {
        if .activeChoiceIndex == nextIndex or .activeChoiceIndex >= .instances.count do
            return
        let instance = &.instances[.activeChoiceIndex]
        if !instance.view or !instance.isLoading or !instance.isLoading!(instance.view!) do
            return

        instance.commands?.destroy()
        instance.view!.destroy()
        instance.view        = null
        instance.commands    = null
        instance.revealMatch = null
        instance.findText    = null
        instance.isLoading   = null
        instance.details.clear()
        .currentView     = null
        .currentCommands = null
    }

    mtd stopLoadingIndicator()
    {
        if .loadingTimer
        {
            .removeTimer(.loadingTimer!)
            .loadingTimer = null
        }

        .loadingSpinner.hide()
    }

    mtd updateLoadingIndicator()
    {
        var loading: bool
        if .activeChoiceIndex < .instances.count
        {
            let instance = &.instances[.activeChoiceIndex]
            loading = instance.view and instance.isLoading and instance.isLoading!(instance.view!)
        }

        .loadingSpinner.show(loading)
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
            .retireActiveLoadingChoice(index)
            .currentCommands?.hide()
            .currentView?.hide()
            .currentView     = instance.view
            .currentCommands = instance.commands
            .currentView!.show()
            .currentCommands?.show()
            .activeChoiceIndex = index
            .viewerCombo.setSelectedIndex(index, notify: false)
            .updateFileInfo(instance.details.toString())
            .updateSearchAvailability()
            .updateLoadingIndicator()
            .applyLayout()
            .invalidate()
            return true
        }

        var next: ViewerResult
        if choice.kind == .BasicText
        {
            let basic = BasicTextView.create(me, .commandBar, .currentFile.toString())
            next.view        = basic
            next.commands    = basic.commands
            next.revealMatch = &basicTextRevealMatch
            next.isLoading   = &basicTextIsLoading
            next.details     = "UTF-8 · streamed"
        }
        else
        {
            let spec    = &.index.specs[choice.specIndex]
            let request = ViewerRequest{ViewerPluginApiVersion, me, .commandBar, .currentFile.toString(), &reportViewerFailure}
            catch .plugins.createView(&request, &next, spec, .index.directory.toString()) as pluginError
            if pluginError != null
            {
                next.failureReason = Errors.message(pluginError)
                if next.failureReason.isEmpty() do
                    next.failureReason = appStrings().ui_OpenStopped
            }

            if !next.failureReason.isEmpty()
            {
                next.commands?.destroy()
                next.view?.destroy()
                next.commands    = null
                next.view        = ViewerErrorView.create(me, next.failureReason.toString())
                next.revealMatch = null
                next.findText    = null
                next.isLoading   = null
                next.details.clear()
            }
        }

        if !next.view do
            return false

        .retireActiveLoadingChoice(index)
        .currentCommands?.hide()
        .currentView?.hide()
        .currentView            = next.view
        .currentCommands        = next.commands
        .activeChoiceIndex      = index
        .currentView!.dockStyle = .Center
        if .currentCommands do
            .currentCommands!.dockStyle = .Right
        instance.view          = .currentView
        instance.commands      = .currentCommands
        instance.revealMatch   = next.revealMatch
        instance.findText      = next.findText
        instance.isLoading     = next.isLoading
        instance.details       = #move next.details
        instance.failureReason = #move next.failureReason
        .viewerCombo.setSelectedIndex(index, notify: false)
        .updateFileInfo(instance.details.toString())
        .updateSearchAvailability()
        .updateLoadingIndicator()
        .applyLayout()
        .invalidate()
        return true
    }

    mtd findNext()
    {
        if !.searchBox.isEnabled() do
            return
        let text = .searchBox.text()
        if !@countof(text) or .currentFile.isEmpty() do
            return

        // A viewer that owns its search replaces the raw byte scan entirely: it knows what its
        // document's text looks like where the file's bytes do not show it.
        if .activeChoiceIndex < .instances.count
        {
            let instance = &.instances[.activeChoiceIndex]
            if instance.findText and instance.view
            {
                .stopSearch()
                if instance.findText!(instance.view!, text) do
                    .updateFileInfo(instance.details.toString())
                else do
                    .infoStatsLabel.setText(appStrings().ui_NoMatch)
                return
            }
        }

        let sameQuery = .searchQuery == text
        .stopSearch()
        .searchWrapped = false
        let offset = sameQuery and .searchMatch != Swag.U64.Max ? .searchMatch + @countof(text) : 0
        if !sameQuery
        {
            .searchQuery = text
            .searchMatch = Swag.U64.Max
        }

        .beginSearch(offset)
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

    // Gives the active viewer the first say on a bare navigation key, wherever the focus sits.
    //
    // A viewer that turns pages with the arrows keeps them even while a toolbar button holds
    // the keyboard; only a key the viewer declines falls back to the previous or next file.
    mtd navigateOrForward(delta: s32, evt: *KeyEvent)
    {
        if !.forwardingViewerKey and .forwardKeyToViewer(evt) do
            return
        .navigate(delta)
    }

    private mtd forwardKeyToViewer(evt: *KeyEvent)->bool
    {
        let target = .viewerFocusTarget()
        if !target do
            return false

        // A key the viewer's key owner already saw and declined must not be offered twice.
        let focused = .focusedWindow()
        if focused and (focused! == target! or target!.isOwnerOf(focused!)) do
            return false

        let view = .currentView
        var copy = KeyEvent{kind: evt.kind, key: evt.key, modifiers: evt.modifiers}
        .forwardingViewerKey = true
        defer .forwardingViewerKey = false
        target!.sendEvent(&copy)

        // A declined key bubbles back here and navigates to another file, which destroys the
        // viewer the key was offered to; only a viewer that is still showing takes the keyboard.
        if copy.accepted and .currentView == view do
            target!.setFocus()
        return copy.accepted
    }

    mtd updateSearchAvailability()
    {
        let active    = .activeChoiceIndex < .instances.count
        let available = active and (.instances[.activeChoiceIndex].revealMatch != null or .instances[.activeChoiceIndex].findText != null)
        .searchBox.enable(available)
        if !available
        {
            .stopSearch()
            .searchMatch = Swag.U64.Max
        }
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
    }

    mtd beginSearch(offset: u64)
    {
        .searchStream = catch File.openRead(.currentFile.toString()) as openError
        if openError != null
        {
            .infoStatsLabel.setText(appStrings().ui_NoMatch)
            return
        }

        discard catch .searchStream.seek(.Begin, offset)
        .searchOffset = offset
        .searchCarry.clear()
        .infoStatsLabel.setText(appStrings().ui_Searching)
        .searchTimer = .addTimer(1'ms)
    }

    mtd searchStep()
    {
        if !.searchStream.isOpen() do
            return
        let before = catch .searchStream.position() as positionError
        if positionError != null
        {
            .stopSearch()
            .infoStatsLabel.setText(appStrings().ui_NoMatch)
            return
        }

        var bytes: Array'u8
        bytes.resize(ViewerSearchChunkSize)
        let count = catch .searchStream.read(bytes.toSlice()) as readError
        if readError != null
        {
            .stopSearch()
            .infoStatsLabel.setText(appStrings().ui_NoMatch)
            return
        }

        bytes.resize(count)

        let carryLength = .searchCarry.length
        .searchCarry += @mkstring(bytes.buffer!, bytes.count)
        let found = Utf8.indexOf(.searchCarry.toString(), .searchQuery.toString(), 0, .Latin1NoCase)
        if found != Swag.U64.Max
        {
            .searchMatch = before - carryLength + found
            .stopSearch()
            if .activeChoiceIndex < .instances.count
            {
                let instance = &.instances[.activeChoiceIndex]
                if instance.revealMatch and instance.view and instance.revealMatch!(instance.view!, .searchMatch, .searchQuery.toString())
                {
                    .updateFileInfo(instance.details.toString())
                    return
                }
            }

            .infoStatsLabel.setText(appStrings().ui_NoMatch)
            return
        }

        if !count
        {
            .stopSearch()
            if !.searchWrapped and .searchOffset
            {
                .searchWrapped = true
                .beginSearch(0)
                return
            }

            .infoStatsLabel.setText(appStrings().ui_NoMatch)
            return
        }

        let keep = Math.min(.searchQuery.length ? .searchQuery.length - 1 : 0, .searchCarry.length)
        .searchCarry = String.from(.searchCarry.toString()[.searchCarry.length - keep to])
        .searchTimer = .addTimer(1'ms)
    }

    mtd updateFileInfo(details: string)
    {
        let baseName = Path.fileName(.currentFile.toString()) orelse .currentFile.toString()
        var stats    = String.from(details)
        let fileInfo = catch File.info(.currentFile.toString()) as infoError
        if infoError == null
        {
            let size = StrConv.toDisplaySize(fileInfo.size)
            stats = stats.isEmpty() ? String.from(size) : Format.toString("%  ·  %", stats, size)
        }

        .infoNameLabel.setText(baseName)
        .infoNameLabel.toolTip = .currentFile
        .infoStatsLabel.setText(stats)
        .infoStatsLabel.toolTip = stats
    }

    mtd selectViewer(index: u32)
    {
        if index == .activeChoiceIndex do
            return
        if !.activateChoice(index) and .activeChoiceIndex != Swag.U32.Max do
            .viewerCombo.setSelectedIndex(.activeChoiceIndex, notify: false)
    }

    mtd openFile(fileName: string, remember = true)
    {
        .stopSearch()
        .searchMatch = Swag.U64.Max
        .searchQuery.clear()
        if !File.exists(fileName)
        {
            .showEmpty(appStrings().ui_OpenStopped)
            return
        }

        .destroyInstances()
        var absolute = catch Path.absolute(fileName) as pathError
        if pathError != null do
            absolute = fileName
        .currentFile = #move absolute
        .choices     = .index.choices(.currentFile.toString())
        .instances.resize(.choices.count)
        .viewerCombo.clear()
        for choice in .choices do
            .viewerCombo.addItem(choice.name.toString())
        .viewerCombo.show()

        var selected = 0'u32
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

        .emptyLabel.hide()

        .siblingsDirty = true
        if remember do
            .rememberRecent(.currentFile.toString())
        if .panelVisible do
            .refreshFileLists()

        .previousButton.enable(true)
        .nextButton.enable(true)
        .applyLayout()
        .invalidate()
    }

    mtd retranslate()
    {
        let texts = appStrings()
        .surface?.setTitle(texts.ui_WindowTitle)
        .openButton.toolTip     = texts.ui_Open
        .filesButton.toolTip    = texts.ui_Files
        .previousButton.toolTip = texts.ui_Previous
        .nextButton.toolTip     = texts.ui_Next
        .kindButton.toolTip     = texts.ui_SameKind
        .viewerCombo.toolTip    = texts.ui_Viewer
        .searchBox.setPlaceholder(texts.ui_Search)
        .recentLabel.setText(texts.ui_Recent)
        for &instance in .instances where instance.view and !instance.failureReason.isEmpty() do
            (cast(*ViewerErrorView) instance.view!).retranslate()
        if .currentFile.isEmpty() do
            .folderLabel.setText(texts.ui_Folder)
        if .currentFile.isEmpty()
        {
            .emptyLabel.setText(Format.toString("<b>%</b>", texts.ui_DropTitle))
            .infoStatsLabel.setText(texts.ui_Ready)
        }

        .invalidate()
    }

    // Shows or hides the panel listing what is beside the current file.
    mtd toggleFilePanel()
    {
        .setFilePanelVisible(!.panelVisible)
        catch g_App.saveState()
    }

    mtd setFilePanelVisible(visible: bool)
    {
        .panelVisible = visible
        .filesButton.setChecked(visible)
        if visible
        {
            .refreshFileLists()
            .filePanel.show()
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
            let name = one[].toString()
            discard list.createLine(Path.fileName(name) orelse name)
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

        // A file read yesterday may be gone today, and a list offering it would be a list of
        // dead ends. The check costs one stat per row and only runs when the panel is opened.
        var alive: Array'String
        for one in .recent where File.exists(one[].toString()) do
            alive.add(one[])
        .recent = #move alive

        .fillFileList(.recentList, .recent.toSlice())
        .fillFileList(.folderList, .siblings.toSlice())

        let hasRecent = !.recent.isEmpty()
        .filePanel.setPaneVisible(0, hasRecent)
        .folderLabel.setText(Path.fileName(Path.directoryName(.currentFile.toString())) orelse appStrings().ui_Folder)
        .filePanel.applyLayout()
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
            .openFile(fileName, remember: list != .recentList)
    }

    mtd rebuildSiblings()
    {
        .siblings.clear()
        .siblingIndex = 0
        let folder = Path.directoryName(.currentFile.toString())
        if !folder do
            return

        let files = catch Directory.enumerateFiles(folder) as listError
        if listError != null do
            return
        for file in files
        {
            if file.isDirectory() do
                continue
            if .folderSameKind and !.index.sharesViewer(.currentFile.toString(), file.fullname.toString()) do
                continue
            .siblings.add(file.fullname)
        }

        .siblings.sort(func(a, b) { return Utf8.compare(a.toSlice(), b.toSlice(), .Latin1NoCase) })

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
        catch g_App.saveState()
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
        .openFile(.siblings[cast(u64) index].toString())
    }
}
