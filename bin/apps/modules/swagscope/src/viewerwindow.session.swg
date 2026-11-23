impl ViewerWindow
{
    // Copies bookmarks from every text session before the host discards or persists them.
    internal mtd rememberTextBookmarkSessions()
    {
        for instance in .instances
        {
            if instance.view is Viewers.PlainText.Panel as view do
                .rememberTextBookmarks(view)
        }
    }

    private mtd rememberTextBookmarks(view: *Viewers.PlainText.Panel)
    {
        if not view.bookmarksPersistable do
            return
        var path = catch Path.absolute(view.fileName) { return; }
        Path.normalize(&path)

        .privacy.track(path)
        .storeTextBookmarkFile(path, view.bookmarkIdentity, view.bookmarks.toSlice())
    }

    internal mtd storeTextBookmarkFile(path: string, identity: string, bookmarks: const [..] Viewers.PlainText.Bookmark)
    {
        if not path.count or not identity.count do
            return
        var found = Swag.U64.Max
        for record, index in .textBookmarkFiles where Path.equals(record.path, path) do
            found = index

        if not bookmarks.count
        {
            if found != Swag.U64.Max do
                .textBookmarkFiles.removeAtOrdered(found)
            return
        }

        var record: ViewerTextBookmarkFile
        record.path = String.from(path)
        record.identity = String.from(identity)
        let first = bookmarks.count > ViewerTextBookmarkLimit ? bookmarks.count - ViewerTextBookmarkLimit : 0
        for index in first until bookmarks.count do
            record.bookmarks.add(bookmarks[index])

        if found != Swag.U64.Max
        {
            .textBookmarkFiles.removeAtOrdered(found)
        }
        elif .textBookmarkFiles.count >= ViewerTextBookmarkFileLimit
        {
            .textBookmarkFiles.removeAtOrdered(0)
        }
        .textBookmarkFiles.add(#move record)
    }

    // Restores by path so changed metadata remains visible as a stale bookmark for the user.
    private mtd restoreTextBookmarks(view: *Viewers.PlainText.Panel)
    {
        var path = catch Path.absolute(view.fileName) { return; }
        Path.normalize(&path)
        if not .privacy.mayRemember(path)
        {
            view.bookmarksPersistable = false
            return
        }
        for record in .textBookmarkFiles where Path.equals(record.path, path)
        {
            view.restoreBookmarks(record.bookmarks.toSlice(), record.identity)
            return
        }
    }

    // Reloads the current path while retaining the active reading session.
    mtd reloadCurrentFile()
    {
        if .currentFile.isEmpty() or
           not .pendingFile.isEmpty() or
           .activeChoiceIndex >= .instances.count do
            return
        .readingState.capture(&.instances[.activeChoiceIndex], .choices[.activeChoiceIndex].key, .searchBox.text())
        .readingState.captureSearchSettings(me)
        .queueFile(.currentFile, remember: false, preserveReading: true)
    }

    mtd finishReadingRestore()
    {
        if .readingState.restoring and
           .activeChoiceIndex < .instances.count and
           .pendingFile.isEmpty() and
           .readingState.restore(&.instances[.activeChoiceIndex]) do
            .readingState.restoring = false
    }

    // Queues `fileName`, giving the window a chance to paint its first frame on startup.
    mtd queueFile(fileName: string,
                  remember = true,
                  preserveReading = false,
                  offerForgetMissing = false,
                  autoplayScene = false)
    {
        .sceneAutoPlay = autoplayScene
        .rememberTextBookmarkSessions()
        .captureResume()
        if .isExploring() and not preserveReading do
            .explorerTransition = true
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

        if .workspace and me == .workspace.primary and not .smokeRunning do
            .workspace.adoptPrimary(fileName)
        .pendingFile = fileName
        .pendingEmpty.clear()
        .pendingRemember      = remember
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
            if not .explorerTransition do
                .explorer.setShown(false)
        }

        .updateLoadingIndicator()
        if .startupTimer do
            return

        // Start the JPEG classification while the outgoing view is still on screen.
        if .currentView and
           not .choiceLoad.started and
           not .awaitingRetirement and
           Viewers.Picture.isJpegExtension(Path.lowercaseExtension(.pendingFile)) do
            .choiceLoad.start(&.index, .pendingFile, me, includeNeighbors: not .thumbnailMode)
        else do
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

            let remember           = .pendingRemember
            let offerForgetMissing = .pendingForgetMissing
            let requested          = String.from(.pendingFile)
            var classified         = .choiceLoad.finish()
            .pendingFile.clear()
            .privacy.track(classified.absoluteFileName, classified.privacy)
            if not classified.exists
            {
                .showEmpty(appStrings().ui_DropTitle)
                if offerForgetMissing do
                    .confirmForgetMissingRecent(requested)
                return
            }

            var archive      = not classified.choices.isEmpty() and classified.choices[0].key == "archive"
            let chosenViewer = .preferredFileViewer(classified.absoluteFileName)
            for choice in classified.choices where choice.key == chosenViewer do
                archive = chosenViewer == "archive"
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
            .openFile(dialog.selectedPath())
    }

    // Closes the current file and forgets its reading state, stops the slide show and the change
    // watch, and returns to the empty window or its explorer without choosing a control.
    mtd closeFile(forExplorer = false)
    {
        .sceneAutoPlay = false
        .captureResume()
        .showPointer()
        .surface?.clearFocus()
        .explorerTransition = false
        if .explorer and .explorer.isLocallyVisible()
        {
            if not forExplorer do
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
    }

    // Returns the window to its empty state with `message`. While a viewer is still retiring or a
    // classification is running, the request is kept in `pendingEmpty` until that work ends.
    mtd showEmpty(message: string)
    {
        .sceneAutoPlay = false
        .explorerTransition = false
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
        if not .explorerActive do
            .closeInformation()
        .updateViewerBar()
        if .explorerActive
        {
            .home.hide()
            .hintLine.hide()
            .searchBox.setText(.explorer!.filter.text(), notify: false)
            .explorer.setShown(true)
            if .infoSheet.isLocallyVisible() do
                .refreshInformation()
        }

        .refreshTitle()

        .updateSearchAvailability()

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

    // Moves the host-owned panel toggle with the viewer it belongs to. The lens names it after
    // its panel and turns it on; the outline uses the left lane while other viewer panels use the
    // right lane.
    private mtd setCurrentSidePanel(panel: *Wnd?, button: *IconButton?)
    {
        if .currentSidePanelButton
        {
            let oldLeft        = .currentSidePanelButton.id == OutlineToggleId
            let oldIndex       = oldLeft ? LeftPanelIndex : RightPanelIndex
            let oldPlaceholder = oldLeft ? .outlinePanelPlaceholder : .sidePanelPlaceholder
            .mainSplitter.items[oldIndex]!.view.hide()
            .mainSplitter.items[oldIndex]!.view = oldPlaceholder
            .mainSplitter.setPaneVisible(oldIndex, false)
        }

        .currentSidePanelHost?.hide()
        .currentSidePanelButton?.hide()
        .currentSidePanelHost   = panel
        .currentSidePanelButton = button
        .refreshExplorerCaption()
        .updateDocumentInsets()

        let visible     = button and button.isChecked and not .fullScreen
        let left        = button and button.id == OutlineToggleId
        let index       = left ? LeftPanelIndex : RightPanelIndex
        let placeholder = left ? .outlinePanelPlaceholder : .sidePanelPlaceholder
        .mainSplitter.items[index]!.view = panel orelse placeholder
        .mainSplitter.items[index]!.view.show(visible)
        .mainSplitter.setPaneVisible(index, visible)
        if visible do
            .mainSplitter.setPaneSize(index, .mainSplitter.items[index]!.size)
        .mainSplitter.applyLayout()
        .layoutFileInfo()
    }

    // A new document starts with no selected action when the previous one owned the keyboard.
    private mtd clearFocusIn(roots: const [..] (*Wnd?))
    {
        let focus = .focusedWindow()
        if not focus do
            return
        for root in roots where root and (root == focus or root.isOwnerOf(focus))
        {
            .surface?.clearFocus()
            return
        }
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
        .clearFocusIn([oldView, oldActions, oldInfo, oldCommands, oldSidePanelHost, oldSidePanelButton])
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
        if (not .outgoingView and not .explorerTransition) or .activeChoiceIndex >= .instances.count do
            return
        let instance = &.instances[.activeChoiceIndex]
        if not instance.view or (expected and instance.view != expected) do
            return
        if instance.needsLoadingOverlay and instance.needsLoadingOverlay() do
            return

        if .outgoingView do
            .discardOutgoingViewer()
        if .explorerTransition
        {
            .clearFocusIn([.explorer])
            .explorer?.setShown(false)
            .explorerTransition = false
            .refreshExplorerCaption()
        }

        .adoptSession(instance)
        .armSlide()
        .currentView!.dockStyle = .Center
        if .currentCommands do
            .currentCommands.dockStyle = .None
        .currentView.show()
        .currentInfo?.show()
        .currentCommands?.show()
        .workspace?.updateMediaViewport(me)
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
            errorView.offer(me, cast(u32, index))

            if index != .activeChoiceIndex
            {
                errorView.hide()
                return
            }

            .sceneAutoPlay = false
            if .outgoingView or .explorerTransition
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
        if .outgoingView do
            view.setPosition(.outgoingView.position, computeLayout: false)
        elif .explorerTransition do
            view.setPosition(.explorer!.position, computeLayout: false)
        next.actions?.hide()
        next.info?.hide()
        if next.commands
        {
            next.commands.dockStyle = .None
            if .outgoingCommands do
                next.commands.setPosition(.outgoingCommands.position, computeLayout: false)
        }

        if .outgoingView
        {
            .outgoingView.bringToFront()
            .outgoingActions?.bringToFront()
            .outgoingInfo?.bringToFront()
            .outgoingCommands?.bringToFront()
            .outgoingSidePanelHost?.bringToFront()
            .outgoingSidePanelButton?.bringToFront()
        }
        elif .explorerTransition
        {
            .explorer!.bringToFront()
        }
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
            .embedded        = false
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
            .sceneAutoPlay = false
            if next.view and next.retire do
                discard next.retire()
            next.replaceWithFailure(.documentPanel)
            assume cast(*ViewerErrorView, next.view).offer(me, index)
        }

        if not next.view
        {
            next.destroyWindows()
            return false
        }

        if next.view is Viewers.PlainText.Panel as textView do
            .restoreTextBookmarks(textView)

        if not .retireActiveLoadingChoice(index)
        {
            if next.retire do
                discard next.retire()
            next.destroyWindows()
            return false
        }

        let stage = .outgoingView != null or .explorerTransition
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
            .rememberFileViewer(index)
            .openExplorer(.currentFile)
            return
        }

        if index == .activeChoiceIndex
        {
            .rememberFileViewer(index)
            return
        }

        let newSession = index < .instances.count and not .instances[index].view
        if not .activateChoice(index) do
            return
        .rememberFileViewer(index)
        if newSession do
            .workspace?.registerReadingLinks(me)
        .workspace?.updateMediaViewport(me)
        .workspace?.refreshComparison()
        .workspace?.comparisonSheet?.refresh()
    }

    // Only explicit selector choices belong to this file's session; automatic fallbacks do not.
    private mtd rememberFileViewer(index: u32)
    {
        if index < .choices.count do
            .setFileViewer(.currentFile, .choices[0].key, .choices[index].key)
    }

    // Choosing the default removes the exception. No viewer association reaches saved state.
    mtd setFileViewer(file, defaultViewer, viewer: string)
    {
        var path = String.from(file)
        Path.normalize(&path)
        for &one, entry in .fileViewerChoices where Path.equals(one.file, path)
        {
            if viewer == defaultViewer do
                .fileViewerChoices.removeAtOrdered(entry)
            else do
                one.viewer = viewer
            return
        }

        if viewer != defaultViewer do
            .fileViewerChoices.add(ViewerFileChoice{#move path, viewer})
    }

    mtd const fileViewer(file: string)->string
    {
        var path = String.from(file)
        Path.normalize(&path)
        for &one in .fileViewerChoices where Path.equals(one.file, path) do
            return one.viewer.toString()
        return ""
    }

    private mtd const preferredFileViewer(file: string)->string
    {
        if .reloading and .readingState.useSavedViewer and not .readingState.viewer.isEmpty() do
            return .readingState.viewer
        return .fileViewer(file)
    }

    // A missing or no-longer-applicable session choice leaves the classified default in charge.
    private mtd preferredChoiceIndex()->u32
    {
        let viewer = .preferredFileViewer(.currentFile)
        for choice, index in .choices where choice.key == viewer do
            return cast(u32, index)
        return 0
    }

    mtd openFile(fileName: string, remember = true)
    {
        if .workspace do
            .workspace.openDocument(fileName, remember)
        else do
            .queueFile(fileName, remember)
    }

    // Opens a file whose classification has finished: watches it for changes, fills the viewer
    // selector, and activates this file's session choice or its default, with plain text as the
    // fallback. `remember` records it in the recent files and folders.
    private mtd openClassifiedFile(classified: #move ViewerClassifiedFile, remember: bool)
    {
        .home.hide()
        .hintLine.hide()

        .fileWatch.current       = #move classified.metadata
        .fileWatch.hasCandidate  = false
        .fileWatch.ignorePending = .fileWatch.load.started
        if not .fileWatchTimer do
            .fileWatchTimer = .addTimer(250'ms)
        .currentFile = #move classified.absoluteFileName
        .workspace?.updateDocumentPath(me)
        .currentFileSize = #move classified.fileSize
        .choices         = #move classified.choices
        .folderFiles     = #move classified.folderFiles
        .forgetLensFile()
        if .explorer and .explorer.displayPath(.currentFile) != .currentFile.toString() do
            .folderFiles.clear()
        .siblingsDirty = true
        .rebuildSiblings()
        .trackFolderReading(.playMode)
        .instances.resize(.choices.count)

        var selected = .preferredChoiceIndex()

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

        .workspace?.updateMediaViewport(me)
        if .reloading
        {
            if .choices[selected].key == .readingState.viewer
            {
                .readingState.applySettings(&.instances[selected])
                .readingState.restoreSearch(me)
                .finishReadingRestore()
            }

            .reloading = false
        }

        if remember
        {
            .rememberRecent(.currentFile)
            .rememberFolder(.currentFile)
            if .workspace and not .isWorkspacePrimary() and .privacy.mayRemember(.currentFile)
            {
                .workspace.primary.rememberRecent(.currentFile)
                .workspace.primary.rememberFolder(.currentFile)
            }
        }

        .applyLayout()
        .invalidate()
        .workspace?.refreshComparison()
        .workspace?.registerReadingLinks(me)
    }
}
