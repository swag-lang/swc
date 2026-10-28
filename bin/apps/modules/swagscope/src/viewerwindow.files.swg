impl ViewerWindow
{
    mtd isExploring()->bool => .explorerActive and .explorer and .explorer.isLocallyVisible()

    // Reports whether the viewer in front takes the whole window, as a film does: its document
    // reaches under the strip and no line of readings stands over it.
    mtd isEdgeToEdge()->bool
    {
        if .isExploring() or .activeChoiceIndex >= .choices.count do
            return false
        return .index.plugins[.choices[.activeChoiceIndex].pluginIndex].edgeToEdge
    }

    mtd isArchivePreview()->bool => not .isExploring() and
                                    .explorer and
                                    .explorer.listing.isArchive and
                                    .explorer.displayPath(.currentFile) != .currentFile.toString()

    // Writes the details a viewer reports on the faint line of readings, with the size of the
    // file after them; the whole of it is the line's tooltip.
    mtd showFileInfo(details, size: string)
    {
        var line: String = details
        if size.count
        {
            if not line.isEmpty() do
                line += " · "
            line += size
        }

        .readingLine.details.setText(line)
        .readingLine.details.toolTip = line
    }

    mtd updateFileInfo(details: string)
    {
        // A picture is one of a series: its rank in the folder closes the line.
        var size: String = .currentFileSize
        if .activeChoiceIndex < .choices.count and .choices[.activeChoiceIndex].key == "image"
        {
            if .siblingsDirty do
                .rebuildSiblings()
            if .siblings.count > 1 do
                size += Format.toString(" · % / %", .siblingIndex + 1, .siblings.count)
        }

        .showFileInfo(details, size)
        .refreshTitle()
        .layoutFileInfo()
        if .infoSheet.isLocallyVisible() do
            .refreshInformation()
    }

    // Lays the line of readings out again after its details or a viewer contribution changed,
    // and shows it only while it has something to say.
    internal mtd layoutFileInfo()
    {
        .updateDocumentInsets()
        .readingLine.show(.readingLine.hasContent() and not .fullScreen and not .isEdgeToEdge())
        .readingLine.computeLayout()
        .documentHost.applyLayout()
        .layoutViewerBar()
    }

    // Shows or hides the panel listing what is beside the current file.
    mtd toggleFilePanel()
    {
        .setFilePanelVisible(not .panelVisible)
        catch .saveState()
    }

    // Shows or hides the file panel, refreshing its lists before it appears and keeping the files
    // toggle in step.
    mtd setFilePanelVisible(visible: bool)
    {
        .panelVisible = visible
        if visible
        {
            .refreshFileLists()
            .filePanelHost.show()
        }
        else
        {
            .filePanelHost.hide()
        }

        if not .mainSplitter.items.isEmpty() do
            .mainSplitter.setPaneVisible(0, visible)

        .applyLayout()
        .invalidate()
    }

    // Puts `fileName` at the head of the recent list, keeping it free of repeats and bounded.
    mtd rememberRecent(fileName: string)
    {
        .recentOpened.resize(.recent.count)
        for one, index in .recent where one[] == fileName
        {
            .recent.removeAtOrdered(index)
            .recentOpened.removeAtOrdered(index)
            break
        }

        .recent.insertAt(0, fileName)
        .recentOpened.insertAt(0, Time.Timestamp.now().ticks)
        while .recent.count > RecentCount
        {
            .recent.removeAtOrdered(.recent.count - 1)
            .recentOpened.removeAtOrdered(.recentOpened.count - 1)
        }
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

        .folderHistory.insertAt(0, ViewerFolderHistory{folder, fileName})
        while .folderHistory.count > FolderHistoryCount do
            .folderHistory.removeAtOrdered(.folderHistory.count - 1)
        .folderHistoryButton.enable(true)
    }

    // Fills one list with file names, selecting the row that names the current file, and returns
    // that row index. A folder round keeps its already-read rows secondary until the next round.
    private mtd fillFileList(list: *ListCtrl, files: const [..] String)->u32
    {
        let scrollPosition = list.scrollWnd.scrollPosition()
        let filter         = .folderFilter.toString()
        var currentIndex   = Swag.U32.Max
        list.clear()
        for one, index in files
        {
            let name        = one[].toString()
            let displayName = Path.fileName(name) orelse name
            if list == .folderList and
               not .folderFilter.isEmpty() and
               Utf8.indexOf(displayName, filter, comparisonType: .Latin1NoCase) == Swag.U64.Max do
                continue

            var pluginIndex = Swag.U64.Max
            var icon: Icon
            if .index.namePlugin(name, &pluginIndex)
            {
                let plugin = &.index.plugins[pluginIndex]
                icon = .pluginIcon(plugin, themeRowIconSize(.themeMetrics()))
            }

            let line = list.createLine(displayName, icon)
            if list == .folderList do
                line.userData0 = cast(*void, index + 1)
            if list == .folderList and .isFolderReading() and .folderReadingFiles.contains(one[]) do
                line.colorFg = .themeColors().label_TextLight
            if .currentFile == name
            {
                currentIndex = line.index
                list.selectLine(line.index)
            }
        }

        list.computeLayout()
        list.scrollWnd.setScrollPos(scrollPosition)
        return currentIndex
    }

    // Rebuilds the folder list when its name filter changes, keeping the filter local to this pane.
    mtd setFolderFilter(filter: string)
    {
        if .folderFilter == filter do
            return
        .folderFilter = filter
        if .panelVisible do
            .refreshFileLists()
    }

    // Rebuilds both sections of the panel from what the window already knows.
    mtd refreshFileLists()
    {
        if .siblingsDirty do
            .rebuildSiblings()

        .refreshingLists = true
        defer .refreshingLists = false

        discard .fillFileList(.recentList, .recent.toSlice())
        var currentIndex = Swag.U32.Max
        .folderFilterBox.show(not .isExploring())
        if (.isExploring() or .isArchivePreview()) and .explorer
        {
            .folderList.clear()
            for &entry, index in .explorer.entries where entry.directory == .isExploring()
            {
                if not .isExploring() and
                   not .folderFilter.isEmpty() and
                   Utf8.indexOf(entry.name, .folderFilter, comparisonType: .Latin1NoCase) == Swag.U64.Max do
                    continue
                let line = .folderList.createLine(entry.name, .explorer.entryIcon(index))
                line.userData0 = cast(*void, index + 1)
                if .isArchivePreview() and index == .explorer.selected do
                    .folderList.selectLine(line.index)
            }

            .folderList.computeLayout()
        }
        else
        {
            currentIndex = .fillFileList(.folderList, .siblings.toSlice())
        }

        let hasRecent = not .recent.isEmpty()
        .filePanel.setPaneVisible(0, hasRecent)
        let folder = .currentFile.isEmpty() ? null : Path.directoryName(.explorer ? .explorer.displayPath(.currentFile) : .currentFile.toString())
        .folderLabel.setText(String.toUpper(.isExploring() ? appStrings().explore_Folders : (Path.fileName(folder) orelse folder orelse appStrings().ui_Folder), .Unicode))
        .filePanel.applyLayout()
        if .isFolderReading() and currentIndex != Swag.U32.Max do
            .folderList.ensureVisibleLine(currentIndex)
    }

    // Shows what a panel row offers for the file it names.
    //
    // The right click has already put the row under the pointer in the selection, silently: the
    // list moves its own selection for the button without announcing a choice, so pointing at a
    // file to act on it never opens it.
    mtd showFileMenu(list: *ListCtrl, files: const [..] String, position: Math.Point)
    {
        if list == .folderList and (.isExploring() or .isArchivePreview()) do
            return
        let line = list.selectedLine()
        if not line do
            return
        var index = line.index
        if list == .folderList and line.userData0 do
            index = cast(u32, cast(u64, line.userData0) - 1)
        if index >= files.count do
            return

        // The actions below outlive the list they were asked from: forgetting a file rebuilds
        // both lists, and the row that named it is gone by then.
        let fileName = String.from(files[index])

        // Only the history is a list the reader owns. The folder list is what the folder holds,
        // and an entry leaves it by leaving the disk.
        .showFileActions(fileName, position, history: list == .recentList)
    }

    // Shows what the open file offers, wherever the reader pointed at it.
    //
    // The history entries stay out: a file is not taken out of the list of what was read from the
    // place that is reading it.
    mtd showCurrentFileActions(position: Math.Point)
    {
        if .currentFile.isEmpty() do
            return
        .showFileActions(.currentFile, position, history: false)
    }

    // Opens the current file with the handler registered by the operating system.
    mtd openCurrentFileDefault()
    {
        if not .currentFile.isEmpty() do
            discard Env.openFile(.currentFile)
    }

    // Opens the bounded folder history and returns to the last file viewed in the chosen folder.
    mtd showFolderHistory()
    {
        let menu = MenuCtrl.createPopup(me, owner: me)
        for one in .folderHistory where Directory.exists(one.folder) and File.exists(one.file)
        {
            var name = Path.fileName(one.folder) orelse one.folder.toString()
            if not name.count do
                name = one.folder.toString()
            var icon = .theme().fileGlyph(one.folder, true, themeRowIconSize(.themeMetrics()))
            if icon.color.a == 0 do
                icon.color = .themeColors().softText
            discard menu.addItem(name, one.folder, icon)
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
            if .isExploring() do
                .openExplorer(one.folder)
            else do
                .queueFile(one.file)
            return
        }
    }

    // Builds what one file offers, wherever the reader pointed at it.
    internal mtd createFileActionsMenu(history: bool)->*MenuCtrl
    {
        let texts = appStrings()
        let menu  = MenuCtrl.createPopup(me, owner: me)
        menu.addItem(texts.ui_MenuLocate, ViewerCommands.Locate, .theme().icon(.OpenFile, themeRowIconSize(.themeMetrics())))
        menu.addItem(texts.ui_MenuOpenDefault, ViewerCommands.OpenDefault, .theme().icon(.OpenExternal, themeRowIconSize(.themeMetrics())))
        menu.addItem(texts.ui_MenuOpenWith, ViewerCommands.OpenWith, .theme().icon(.OpenExternal, themeRowIconSize(.themeMetrics())))
        menu.addSeparator()
        menu.addItem(texts.ui_MenuCopyPath, ViewerCommands.CopyPath, .theme().icon(.Copy, themeRowIconSize(.themeMetrics())))
        menu.addItem(texts.ui_MenuCopyName, ViewerCommands.CopyName, .theme().icon(.Copy, themeRowIconSize(.themeMetrics())))
        if history
        {
            menu.addSeparator()
            menu.addItem(texts.ui_MenuForget, ViewerCommands.Forget, .theme().icon(.Remove, themeRowIconSize(.themeMetrics())))
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
        case ViewerCommands.Locate:      Env.showInFileExplorer(fileName)
        case ViewerCommands.OpenDefault: Env.openFile(fileName)
        case ViewerCommands.OpenWith:    Env.openFileWith(fileName)
        case ViewerCommands.CopyPath:    Clipboard.setString(fileName)
        case ViewerCommands.CopyName:    Clipboard.setString(Path.fileName(fileName) orelse fileName)
        case ViewerCommands.Forget:      .forgetRecent(fileName)
        }
    }

    // Drops one file from the history, keeping the rest of it in order.
    mtd forgetRecent(fileName: string)
    {
        .recentOpened.resize(.recent.count)
        for one, index in .recent where one[] == fileName
        {
            .recent.removeAtOrdered(index)
            .recentOpened.removeAtOrdered(index)
            break
        }

        .historyChanged()
    }

    // Empties the history. What is open stays open: the list says what was read, not what is.
    mtd clearRecent()
    {
        .recent.clear()
        .recentOpened.clear()
        .historyChanged()
    }

    // Counts the files of the history that are gone from the disk.
    //
    // The reader asks for it, opening the clear menu: a handful of probes, once.
    mtd missingRecentCount()->u64
    {
        var result = 0'u64
        for one in .recent where not File.exists(one[]) do
            result += 1
        return result
    }

    // Counts the files of the history last opened more than a month ago.
    mtd olderRecentCount()->u64
    {
        let limit  = .monthAgo()
        var result = 0'u64
        for i in .recent.count where i >= .recentOpened.count or .recentOpened[i] < limit do
            result += 1
        return result
    }

    // Takes the files that are gone from the disk out of the history.
    mtd removeMissingRecent()
    {
        .recentOpened.resize(.recent.count)
        for i in reversed(.recent.count) where not File.exists(.recent[i])
        {
            .recent.removeAtOrdered(i)
            .recentOpened.removeAtOrdered(i)
        }

        .historyChanged()
    }

    // Takes the files last opened more than a month ago out of the history.
    mtd removeOlderRecent()
    {
        .recentOpened.resize(.recent.count)
        let limit = .monthAgo()
        for i in reversed(.recent.count) where .recentOpened[i] < limit
        {
            .recent.removeAtOrdered(i)
            .recentOpened.removeAtOrdered(i)
        }

        .historyChanged()
    }

    private mtd monthAgo()->u64
    {
        var limit = Time.Timestamp.now()
        limit.addMonths(-1)
        return limit.ticks
    }

    // Shows the history as it now stands, and keeps it.
    private mtd historyChanged()
    {
        .refreshFileLists()
        .refreshHome()
        catch .saveState()
    }

    // Confirms the destructive history action before applying it.
    mtd confirmClearRecent()
    {
        if MessageDlg.confirm(unwrap .surface, appStrings().ui_ConfirmClearHistory) == Dialog.BtnYes do
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
        var index = selected[0]!.index
        if list == .folderList and selected[0]!.userData0 do
            index = cast(u32, cast(u64, selected[0]!.userData0) - 1)
        if list == .folderList and (.isExploring() or .isArchivePreview()) and .explorer
        {
            .explorer.selected = index
            .explorer.activate(index)
            return
        }

        if index >= files.count do
            return
        let fileName = files[index].toString()
        if .currentFile != fileName do
            .queueFile(fileName, remember: list != .recentList)
    }

    // Rebuilds the list the next and previous commands walk: the folder's files, or only those
    // sharing the current file's viewer when the same-kind filter is on.
    mtd rebuildSiblings()
    {
        .siblings.clear()
        .siblingIndex = 0
        for file in .folderFiles where not .folderSameKind or .index.sharesViewer(.currentFile, file[])
        {
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

    // Opens the file `delta` steps away in the sibling list, wrapping around at either end.
    mtd navigate(delta: s32)
    {
        if .currentFile.isEmpty() do
            return
        if .siblingsDirty do
            .rebuildSiblings()
        if .siblings.count <= 1 do
            return

        var index = cast(s64, .siblingIndex) + delta
        if index < 0 do
            index = cast(s64, .siblings.count) - 1
        elif index >= cast(s64, .siblings.count) do
            index = 0
        .queueFile(.siblings[cast(u64, index)])
    }

    // Returns the files of the current file's folder that its viewer opens, in folder order and
    // whatever the panel filter says: a play mode walks the movies of a folder past the notes
    // stored beside them, whether or not the list shows those notes.
    mtd kindSiblings()->Array'String
    {
        var result: #returntype
        for file in .folderFiles where .index.sharesViewer(.currentFile, file[]) do
            result.add(file[])
        return result
    }
}
