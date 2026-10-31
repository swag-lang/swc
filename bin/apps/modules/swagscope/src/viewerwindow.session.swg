impl ViewerWindow
{
    // Reloads the current path while retaining the active reading session.
    mtd reloadCurrentFile()
    {
        if .currentFile.isEmpty() or
           not .pendingFile.isEmpty() or
           .activeChoiceIndex >= .instances.count do
            return
        .readingState.capture(&.instances[.activeChoiceIndex], .choices[.activeChoiceIndex].key, .searchBox.text())
        .queueFile(.currentFile, remember: false, preserveReading: true)
    }

    // Opens `fileName` after the surface has had a chance to paint its first frame.
    mtd queueFile(fileName: string,
                  remember = true,
                  preserveReading = false,
                  offerForgetMissing = false)
    {
        .reloading = preserveReading
        if not preserveReading do
            .readingState = {}

        // A query belongs to the document it was started against. Stop its file stream as soon as
        // another document is requested instead of letting it scan the old file while the new one
        // is being classified.
        .forgetSearch()
        .searchBox.setText("", notify: false)
        .refreshSearchReadout()
        .stopSlide()
        .stillView = null

        .pendingFile = fileName
        .pendingEmpty.clear()
        .pendingRemember = remember
        .pendingForgetMissing = offerForgetMissing

        // Normal opens hide the home before the first frame. A recent-row open keeps it in place
        // while the file is checked, so a missing file can prompt without revealing it mid-open.
        if not offerForgetMissing
        {
            .home.hide()
            .hintLine.hide()
        }
        if .explorer
        {
            .explorer.leave()
            .explorer.setShown(false)
        }

        .updateLoadingIndicator()
        if not .startupTimer do
            .startupTimer = .addTimer(1'ms)
    }

    // Takes the queued file, or the queued empty state, one step further once what it waited for
    // has happened: the first frame, the classification, or the retirement of the viewer before it.
    mtd continueStartup()
    {
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

    // Asks a retiring viewer again, now that a task below the window has ended.
    //
    // The event that says so is still on its way to its window, which the answer may destroy, so
    // the question waits for the next turn of the event loop.
    mtd retryRetirement()
    {
        if not .awaitingRetirement do
            return
        .awaitingRetirement = false
        if not .startupTimer do
            .startupTimer = .addTimer(1'ms)
    }

    // Advances one asynchronous file classification and publishes it only after the preceding
    // viewer has retired. Every filesystem probe stays on the worker side of this boundary.
    //
    // Nothing here polls: the classification ends with a task event to this window, and a viewer
    // that is still retiring ends its work with a task event below it.
    private mtd processQueuedFile()
    {
        if .choiceLoad.started
        {
            if not .choiceLoad.isDone() do
                return

            if .choiceLoad.fileName != .pendingFile
            {
                discard .choiceLoad.finish()
                .choiceLoad.start(&.index, .pendingFile, me, includeNeighbors: not .thumbnailMode)
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
                .awaitingRetirement = true
                return
            }

            let remember   = .pendingRemember
            let offerForgetMissing = .pendingForgetMissing
            let requested  = String.from(.pendingFile)
            var classified = .choiceLoad.finish()
            .pendingFile.clear()
            if not classified.exists
            {
                .showEmpty(appStrings().ui_DropTitle)
                if offerForgetMissing do
                    .confirmForgetMissingRecent(requested)
                return
            }

            var archive = not classified.choices.isEmpty() and classified.choices[0].key == "archive"
            for preference in .preferences where preference.kind == "archive" and preference.viewer != "archive" do
                archive = false
            if not .thumbnailMode and (classified.isDirectory or archive)
            {
                .home.hide()
                .hintLine.hide()
                if archive and remember
                {
                    .rememberRecent(classified.absoluteFileName)
                    .rememberFolder(classified.absoluteFileName)
                }

                .openExplorer(classified.absoluteFileName)
                return
            }

            .openClassifiedFile(#move classified, remember)
            return
        }

        .choiceLoad.start(&.index, .pendingFile, me, includeNeighbors: not .thumbnailMode)
    }

    mtd chooseFile()
    {
        with var options: FileDlgOptions
        {
            .state = &me.fileDlgState
            .mode  = .SelectFile
            .title = appStrings().dlg_TitleOpen
            .confirmButtonText = appStrings().dlg_ButtonOpen
            .filters.add({name: appStrings().dlg_AllFiles, extensions: ""})
        }

        let dialog = FileDlg.create(unwrap .surface, options)
        if dialog.doModal() == Dialog.BtnOk do
            .queueFile(dialog.selectedPath())
    }

    // Closes the current file and forgets its reading state, stops the slide show and the change
    // watch, and returns to the empty window with focus on the open button.
    mtd closeFile()
    {
        if .explorer and .explorer.isLocallyVisible()
        {
            .explorerActive = false
            .explorer.leave()
            .explorer.setShown(false)
        }

        .pendingFile.clear()
        .pendingEmpty.clear()
        .reloading    = false
        .readingState = {}
        .resetFolderReading()
        .stopSlide()
        .stillView = null
        .stopTimer(&.fileWatchTimer)

        .searchBox.setText("", notify: false)
        .showEmpty(appStrings().ui_DropTitle)
        if .explorerActive do
            .explorer!.focusContent()
    }

    // Returns the window to its empty state with `message`. While a viewer is still retiring or a
    // classification is running, the request is kept in `pendingEmpty` until that work ends.
    mtd showEmpty(message: string)
    {
        .forgetSearch()
        let retired = .destroyInstances()
        if not retired or (.choiceLoad.started and not .choiceLoad.isDone())
        {
            .pendingEmpty = message
            if not retired do
                .awaitingRetirement = true
            return
        }

        if .choiceLoad.started do
            discard .choiceLoad.finish()
        .stopLoadingIndicator()

        .home.setMessage(message == appStrings().ui_DropTitle ? "" : message)
        .home.show()
        .home.refresh()
        .hintLine.show()
        .currentFile.clear()
        .explorer?.releasePreviews()
        .currentFileSize.clear()
        .choices.clear()
        .activeChoiceIndex = Swag.U32.Max
        .folderFiles.clear()
        .siblings.clear()
        .siblingsDirty = true
        .resetFolderReading()
        .showFileInfo("", "")
        .layoutFileInfo()
        .closeInformation()
        .updateViewerBar()
        if .explorerActive
        {
            .home.hide()
            .hintLine.hide()
            .explorer!.setShown(true)
        }

        .refreshTitle()

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
            else
            {
                instance.destroyWindows()
            }
        }

        .instances.clear()
        if not keepCurrent do
            .resetCurrentViewer()

        return true
    }

    // Hides the windows of the viewer the window presents.
    private mtd hideCurrentSession()
    {
        .currentActions?.hide()
        .currentInfo?.hide()
        .currentCommands?.hide()
        .currentView?.hide()
    }

    // Makes the windows of `session` the presentation of the window.
    //
    // Showing them is left to the caller: a staged transition keeps them behind the outgoing
    // viewer until it has something to show.
    private mtd adoptSession(session: *ViewerSession)
    {
        .currentView     = session.view
        .currentActions  = session.actions
        .currentInfo     = session.info
        .currentCommands = session.commands
        .setCurrentSidePanel(session.sidePanelHost, session.sidePanelButton)
    }

    // Presents `view` alone, without the actions, information, commands, or side panel of a
    // viewer.
    private mtd resetCurrentViewer(view: *Wnd? = null)
    {
        .currentView     = view
        .currentActions  = null
        .currentInfo     = null
        .currentCommands = null
        .setCurrentSidePanel(null, null)
        .updateViewerBar()
    }

    // Moves the host-owned panel toggle with the viewer it belongs to. The toggle stays off the
    // window: the lens names it after its panel and turns it, and its panel takes the right-side
    // lane while it is on. An outline also has a direct action in the caption strip.
    private mtd setCurrentSidePanel(panel: *Wnd?, button: *IconButton?)
    {
        .currentSidePanelHost?.hide()
        .currentSidePanelButton?.hide()
        .currentSidePanelHost   = panel
        .currentSidePanelButton = button
        if button and button.id == OutlineToggleId do
            .refreshOutlineCaption()
        .outlineCaptionButton.show(button and button.id == OutlineToggleId and not .fullScreen)
        .updateDocumentInsets()

        let visible = button and button.isChecked and not .fullScreen
        .mainSplitter.items[2]!.view = panel orelse .sidePanelPlaceholder
        .mainSplitter.items[2]!.view.show(visible)
        .mainSplitter.setPaneVisible(2, visible)
        if visible do
            .mainSplitter.setPaneSize(2, .mainSplitter.items[2]!.size)
        .mainSplitter.applyLayout()
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
        if instance.needsLoadingOverlay and instance.needsLoadingOverlay() do
            return

        .discardOutgoingViewer()
        .adoptSession(instance)
        .armSlide()
        .currentView!.dockStyle = .Center
        if .currentCommands do
            .currentCommands.dockStyle = .None
        .currentView.show()
        .currentInfo?.show()
        .currentCommands?.show()
        .updateViewerBar()
        .updateFileInfo(instance.details)
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

            let errorView = ViewerErrorView.create(.documentPanel, message)
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
            .resetCurrentViewer(errorView)
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
        if not instance.view or not instance.isLoading or not instance.isLoading() do
            return true

        if not instance.retireView() do
            return false
        instance.destroyWindows()
        instance[] = {}
        .resetCurrentViewer()
        return true
    }

    // Ends the wait presentation at once, whatever its clocks say: the document it announced is gone.
    mtd stopLoadingIndicator()
    {
        .stopTimer(&.loadingTimer)

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
    // [[LoadingShowDelayMicroseconds]], and once shown it stays for
    // [[LoadingMinVisibleMicroseconds]] even when the wait ends before that. The poll
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
            loading     = instance.view and instance.isLoading and instance.isLoading()
            wantOverlay = loading and instance.needsLoadingOverlay and instance.needsLoadingOverlay()
        }

        let now = Time.monotonicMicroseconds()
        var lingering: bool
        if wantOverlay and .currentView
        {
            if not .loadingWantedSince do
                .loadingWantedSince = now
            if .loadingShownSince or now - .loadingWantedSince >= LoadingShowDelayMicroseconds
            {
                if not .loadingShownSince
                {
                    .loadingShownSince = now
                    .loadingOverlay.reveal()
                }

                .loadingOverlay.cover(.currentView.position)
                .loadingOverlay.bringToFront()
                .layoutFloatingParts()
            }
        }
        else
        {
            .loadingWantedSince = 0
            lingering = .loadingShownSince != 0 and
                        .currentView != null and
                        now - .loadingShownSince < LoadingMinVisibleMicroseconds
            if lingering do
                .loadingOverlay.cover(.currentView!.position)
            else do
                .hideLoadingOverlay()
        }

        let watching = loading or lingering
        if watching and not .loadingTimer
        {
            .loadingTimer = .addTimer(LoadingPollInterval)
        }
        elif not watching and .loadingTimer
        {
            .stopTimer(&.loadingTimer)
        }
    }

    // Brings back the session of `index`, created by an earlier visit, without loading it again.
    mtd showCreatedChoice(index: u32)->bool
    {
        if not .retireActiveLoadingChoice(index) do
            return false

        let instance = &.instances[index]
        .hideCurrentSession()
        .adoptSession(instance)
        .currentView!.show()
        .currentInfo?.show()
        .currentCommands?.show()
        .updateViewerBar()
        .activeChoiceIndex = index
        .updateFileInfo(instance.details)
        .updateSearchAvailability()
        .applyLayout()
        .updateLoadingIndicator()
        .invalidate()
        return true
    }

    // Lays the incoming session under the outgoing one, at its place, so the transition reveals it
    // without a frame where neither shows.
    mtd stageIncoming(next: *ViewerSession)
    {
        let view = unwrap next.view
        view.dockStyle = .None
        view.setPosition(.outgoingView!.position, computeLayout: false)
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

    // Shows the viewer of `choices[index]`, creating its session on first use; a viewer that fails
    // becomes the standard failure surface. Returns false when no view could be shown or the
    // loading viewer could not be retired yet.
    mtd activateChoice(index: u32)->bool
    {
        if index >= .choices.count do
            return false

        let choice   = &.choices[index]
        let instance = &.instances[index]
        if instance.view do
            return .showCreatedChoice(index)

        if choice.pluginIndex >= .index.plugins.count do
            return false

        var next: ViewerSession
        let plugin   = &.index.plugins[choice.pluginIndex]
        let splitter = me.mainSplitter
        with var pluginHost: ViewerPluginHost
        {
            .thumbnail       = me.thumbnailMode
            .session         = &next
            .documentParent  = me.documentPanel
            .sidePanelParent = splitter
            .sideSplitter    = splitter
            .sidePaneIndex   = 2
            .actionParent    = me.readingLine
            .infoParent      = me.readingLine
            .commandParent   = me.viewerBar
            .sourceFileName  = me.currentFile
            .pluginIcon      = me.pluginIcon(plugin, themeActionIconSize(me.themeMetrics()))
            .window          = me
            .hostServices    = viewerHostServices()
        }

        let host: Viewer.Host = &pluginHost
        catch next.create(plugin, host)
        {
            next.failureReason = Viewer.failureText(Swag.err)
            if next.failureReason.isEmpty() do
                next.failureReason = appStrings().ui_OpenStopped
        }

        // A rejected or failed viewer keeps its explanation and nothing else: the session becomes
        // the standard error surface.
        if not next.failureReason.isEmpty()
        {
            if next.view and next.retire do
                discard next.retire()
            next.replaceWithFailure(.documentPanel)
        }

        if not next.view
        {
            next.destroyWindows()
            return false
        }

        if not .retireActiveLoadingChoice(index)
        {
            if next.retire do
                discard next.retire()
            next.destroyWindows()
            return false
        }

        let stage = .outgoingView != null
        if stage
        {
            .stageIncoming(&next)
        }
        else
        {
            next.view.dockStyle = .Center
            if next.commands do
                next.commands.dockStyle = .None
            .hideCurrentSession()
            .adoptSession(&next)
            .currentInfo?.show()
            .updateViewerBar()
        }

        .activeChoiceIndex = index
        instance[]         = #move next
        .updateFileInfo(instance.details)
        .updateSearchAvailability()
        if stage do
            .commitViewerTransition(instance.view)
        else do
            .applyLayout()
        .updateLoadingIndicator()
        .invalidate()
        return true
    }

    mtd selectViewer(index: u32)
    {
        .readingState.restoring = false
        if not .thumbnailMode and index < .choices.count and .choices[index].key == "archive"
        {
            .rememberPreferredViewer(index)
            .openExplorer(.currentFile)
            return
        }

        if index == .activeChoiceIndex do
            return
        if not .activateChoice(index) do
            return
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
        .preferences.add(ViewerPreference{kind, viewer})
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
                return cast(u32, index)
            break
        }

        return 0
    }

    mtd openFile(fileName: string, remember = true)
    {
        .queueFile(fileName, remember)
    }

    // Opens a file whose classification has finished: watches it for changes, fills the viewer
    // selector, and activates the preferred viewer, or the one of the reloaded reading state, with
    // plain text as the fallback. `remember` records it in the recent files and folders.
    private mtd openClassifiedFile(classified: #move ViewerClassifiedFile, remember: bool)
    {
        .home.hide()
        .hintLine.hide()

        .fileWatch.current       = #move classified.metadata
        .fileWatch.hasCandidate  = false
        .fileWatch.ignorePending = .fileWatch.load.started
        if not .fileWatchTimer do
            .fileWatchTimer = .addTimer(250'ms)
        .currentFile     = #move classified.absoluteFileName
        .currentFileSize = #move classified.fileSize
        .choices         = #move classified.choices
        .folderFiles     = #move classified.folderFiles
        if .explorer and .explorer.displayPath(.currentFile) != .currentFile.toString() do
            .folderFiles.clear()
        .siblingsDirty = true
        .rebuildSiblings()
        .trackFolderReading(.playMode)
        .instances.resize(.choices.count)

        var selected = .preferredChoiceIndex()
        if .reloading
        {
            for choice, index in .choices where choice.key == .readingState.viewer do
                selected = cast(u32, index)
        }

        if not .activateChoice(selected)
        {
            selected = Swag.U32.Max
            for choice, index in .choices where choice.key == Viewers.PlainText.ViewerKey
            {
                selected = cast(u32, index)
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
                .searchBox.setText(.readingState.query, notify: false)
                .restartSearch()
            }

            .reloading = false
        }

        if remember
        {
            .rememberRecent(.currentFile)
            .rememberFolder(.currentFile)
        }

        if .panelVisible do
            .refreshFileLists()

        .applyLayout()
        .invalidate()
    }
}
