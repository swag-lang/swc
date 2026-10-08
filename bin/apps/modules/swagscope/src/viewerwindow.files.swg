impl ViewerWindow
{
    // Fills the three readouts of the information bar; each one carries its full text as tooltip.
    mtd showFileInfo(name, path, details, size: string)
    {
        .infoNameLabel.setText(name)
        .infoNameLabel.toolTip = path
        .infoStatsLabel.setText(details)
        .infoStatsLabel.toolTip = details
        .infoSizeLabel.setText(size)
        .infoSizeLabel.toolTip = size
    }

    mtd updateFileInfo(details: string)
    {
        .showFileInfo(Path.fileName(.currentFile) orelse .currentFile, .currentFile, details, .currentFileSize)
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
        .filesButton.setChecked(visible)
        if visible
        {
            .refreshFileLists()
            .filePanelHost.show()
        }
        else
        {
            .filePanelHost.hide()
        }

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

        .recent.insertAt(0, fileName)
        while .recent.count > RecentCount do
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

        .folderHistory.insertAt(0, {folder, fileName})
        while .folderHistory.count > FolderHistoryCount do
            .folderHistory.removeAtOrdered(.folderHistory.count - 1)
        .folderHistoryButton.enable(true)
    }

    // Fills one list with file names, selecting the row that names the current file, and returns
    // that row index. A folder round keeps its already-read rows secondary until the next round.
    private mtd fillFileList(list: *ListCtrl, files: const [..] String)->u32
    {
        let scrollPosition = list.scrollWnd.scrollPosition()
        var currentIndex   = Swag.U32.Max
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

            let line = list.createLine(Path.fileName(name) orelse name, icon)
            if list == .folderList and .isFolderReading() and .folderReadingFiles.contains(one[]) do
                line.colorFg = .themeColors().label_TextLight
            if .currentFile == name
            {
                currentIndex = cast(u32, index)
                list.selectLine(cast(u32, index))
            }
        }

        list.computeLayout()
        list.scrollWnd.setScrollPos(scrollPosition)
        return currentIndex
    }

    // Rebuilds both sections of the panel from what the window already knows.
    mtd refreshFileLists()
    {
        if .siblingsDirty do
            .rebuildSiblings()

        .refreshingLists = true
        defer .refreshingLists = false

        discard .fillFileList(.recentList, .recent.toSlice())
        let currentIndex = .fillFileList(.folderList, .siblings.toSlice())

        let hasRecent = not .recent.isEmpty()
        .filePanel.setPaneVisible(0, hasRecent)
        let folder = .currentFile.isEmpty() ? null : Path.directoryName(.currentFile)
        .folderLabel.setText(Path.fileName(folder) orelse folder orelse appStrings().ui_Folder)
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
        let line = list.selectedLine()
        if not line do
            return
        let index = line.index
        if index >= files.count do
            return

        // The actions below outlive the list they were asked from: forgetting a file rebuilds
        // both lists, and the row that named it is gone by then.
        let fileName = String.from(files[index])

        // Only the history is a list the reader owns. The folder list is what the folder holds,
        // and an entry leaves it by leaving the disk.
        .showFileActions(fileName, position, history: list == .recentList)
    }

    // Shows what the open file offers, from the band that names it.
    //
    // The history entries stay out: the band says what is being read, and a file is not taken out
    // of the list of what was read from the place that is reading it.
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
            var icon = .app().directoryIcon(one.folder, true)
            icon.color = .themeColors().label_Text
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
            .queueFile(one.file)
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
        var result: retval
        for file in .folderFiles where .index.sharesViewer(.currentFile, file[]) do
            result.add(file[])
        return result
    }
}
