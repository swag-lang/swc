impl ViewerWindow
{
    mtd isExploring()->bool => .explorerActive and .explorer and .explorer.isLocallyVisible()

    mtd showsCaptionTitle()->bool =>
        (.workspace?.scenes.count orelse 0) < 2 and
        ((.workspace?.documentCount() orelse 0) > 1 or not .isExploring() and not .isEdgeToEdge())

    // Reports whether the selected plugin explicitly requests an edge-to-edge presentation.
    mtd isEdgeToEdge()->bool
    {
        if .isExploring() or .activeChoiceIndex >= .choices.count do
            return false
        return .index.plugins[.choices[.activeChoiceIndex].pluginIndex].edgeToEdge
    }

    // Reports whether the selected viewer asks for the host's line of readings at the document foot.
    mtd canShowReadingLine()->bool
    {
        if .isExploring() do
            return true
        if .activeChoiceIndex >= .choices.count do
            return true
        if .currentView is Viewers.Film.Panel and (.workspace?.isTiled() orelse false) do
            return false
        return .index.plugins[.choices[.activeChoiceIndex].pluginIndex].showReadingLine
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
        .refreshReadingAppearance()

        // A document that takes the whole window writes its title itself, over its picture.
        if .isWorkspaceActive() do
            .surface?.wnd.showTitle(.showsCaptionTitle())
        .updateDocumentInsets()
        let wasVisible = .readingLine.isLocallyVisible()
        .readingLine.show(.readingLine.hasContent() and
                          .canShowReadingLine() and
                          not .fullScreen and
                          not .isEdgeToEdge())
        .readingLine.computeLayout()
        if wasVisible != .readingLine.isLocallyVisible() do
            .applyLayout()
        else do
            .documentHost.applyLayout()
        .layoutViewerBar()
    }

    // Resolves the appearance from the current reader's canvas, or from the desktop.
    mtd refreshReadingAppearance()
    {
        if .updatingReadingAppearance or not .isWorkspaceActive() do
            return
        .updatingReadingAppearance = true
        defer .updatingReadingAppearance = false

        let active         = not .isExploring()
        let markdown       = active ? (catch cast(*Markdown.View?, .currentView) orelse null) : null
        let customMarkdown = markdown and Viewers.MarkdownText.g_ViewerSettings.themeIndex != 0
        let background     = active ? .authoredReadingBackground() : Color{}
        var documentTheme  = AppearanceTheme.System
        if customMarkdown do
            documentTheme = appearanceForGround(markdown!.themeColors().view_Bk)
        elif background.a == 255 do
            documentTheme = appearanceForGround(background)
        if .workspace and .workspace.documentCount() > 1
        {
            .appearanceButton.setDocumentTheme(.System)
            .surface?.wnd.setChromePalette(null)
            return
        }
        .appearanceButton.setDocumentTheme(documentTheme)

        // A Markdown sheet also sets the inks for its own reading surface.
        if customMarkdown and .appearanceButton.appearanceTheme == .Document
        {
            let colors   = markdown!.themeColors()
            var document = documentTheme == .Light ? ThemeColors.papierPalette() : ThemeColors.encrePalette()
            document.ground    = colors.view_Bk
            document.text      = colors.label_Text
            document.softText  = colors.label_TextLight
            document.faintText = colors.label_TextFaint
            .surface?.wnd.setChromePalette(&document)
            .style.setStyleSheetColors(Format.toString("ground 0x%{X08}", document.ground.argb))
        }
        else
        {
            .surface?.wnd.setChromePalette(null)
            .style.clearStyleSheetColors()
        }

        .computeStyle()
        .invalidate()
    }

    private mtd authoredReadingBackground()->Color
    {
        switch .currentView
        {
        case Viewers.Html.Panel as page: return page.view.authoredCanvasBackground()
        case Viewers.Epub.Panel as book: return book.view?.authoredCanvasBackground() orelse Color{}
        case Viewers.Docx.Panel as word: return word.view?.authoredCanvasBackground() orelse Color{}
        case Viewers.Odt.Panel as word:  return word.view?.authoredCanvasBackground() orelse Color{}
        case Viewers.Rtf.Panel as rich:  return rich.view?.authoredCanvasBackground() orelse Color{}
        case Viewers.Pptx.Panel as deck: return deck.view?.authoredCanvasBackground() orelse Color{}
        case Viewers.PdfDocument.Panel:  return Color.fromArgb(Argb.White)
        case Viewers.Xlsx.Panel as workbook where workbook.grid: return Color.fromArgb(Argb.White)
        default: return {}
        }
    }

    private func appearanceForGround(ground: Color)->AppearanceTheme
    {
        let light = ground.contrastRatio(ThemeColors.papierPalette().ground)
        let dark  = ground.contrastRatio(ThemeColors.encrePalette().ground)
        return light <= dark ? .Light : .Dark
    }

    // Puts `fileName` at the head of the recent list, keeping it free of repeats and bounded.
    mtd rememberRecent(fileName: string)
    {
        if not .privacy.mayRemember(fileName) do
            return
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

    // Puts an explored directory at the head of the folders the home offers.
    mtd rememberExplored(location: string)
    {
        if .thumbnailMode or not .privacy.mayRemember(location) or not Directory.exists(location) do
            return
        for one, index in .exploredFolders where Utf8.compare(one.toSlice(), location, .Latin1NoCase) == 0
        {
            .exploredFolders.removeAtOrdered(index)
            break
        }

        .exploredFolders.insertAt(0, location)
        while .exploredFolders.count > FolderHistoryCount do
            .exploredFolders.removeBack()
    }

    // Puts the file's folder at the head of the bounded folder history.
    mtd rememberFolder(fileName: string)
    {
        if not .privacy.mayRemember(fileName) do
            return
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
    }

    // Shows what the open file offers, wherever the reader pointed at it.
    //
    // The history entries stay out: a file is not taken out of the list of what was read from the
    // place that is reading it.
    mtd showCurrentFileActions(position: Math.Point)
    {
        if .currentFile.isEmpty() do
            return
        .showFileActions(.currentFile, position)
    }

    // Keeps file actions on the selection while the Explorer is on screen.
    mtd fileActionPath()->string
    {
        if not .isExploring() do
            return .currentFile
        let explorer = unwrap .explorer
        if explorer.listing.isArchive or
           explorer.load.started or
           explorer.selected >= explorer.entries.count do
            return ""
        let item = &explorer.entries[explorer.selected]
        return item.directory ? "" : item.path.toString()
    }

    // Builds what one file offers, wherever the reader pointed at it.
    internal mtd createFileActionsMenu()->*MenuCtrl
    {
        let texts = appStrings()
        let menu  = MenuCtrl.createPopup(me, owner: me)
        menu.addItem(texts.ui_MenuLocate, ViewerCommands.Locate, .theme().icon(.OpenFile, themeRowIconSize(.themeMetrics())))
        menu.addItem(texts.ui_MenuOpenDefault, ViewerCommands.OpenDefault, .theme().icon(.OpenExternal, themeRowIconSize(.themeMetrics())))
        menu.addItem(texts.ui_MenuOpenWith, ViewerCommands.OpenWith, .theme().icon(.OpenExternal, themeRowIconSize(.themeMetrics())))
        menu.addSeparator()
        menu.addItem(texts.ui_MenuCopyPath, ViewerCommands.CopyPath, .theme().icon(.Copy, themeRowIconSize(.themeMetrics())))
        menu.addItem(texts.ui_MenuCopyName, ViewerCommands.CopyName, .theme().icon(.Copy, themeRowIconSize(.themeMetrics())))

        return menu
    }

    // Shows what one file offers, wherever the reader pointed at it.
    internal mtd showFileActions(fileName: string, position: Math.Point)
    {
        let menu = .createFileActionsMenu()

        let chosen = menu.doModal(position, autoDestroy: true, dispatchCommand: false)
        if not chosen do
            return

        discard .runCommand(chosen, contextPath: fileName)
    }

    internal mtd runFileAction(chosen: WndId, fileName: string)
    {
        switch chosen
        {
        case ViewerCommands.Locate:      Env.showInFileExplorer(fileName)
        case ViewerCommands.OpenDefault: Env.openFile(fileName)
        case ViewerCommands.OpenWith:    Env.openFileWith(fileName)
        case ViewerCommands.CopyPath:    Clipboard.setString(fileName)
        case ViewerCommands.CopyName:    Clipboard.setString(Path.fileName(fileName) orelse fileName)
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

    // Empties the history and the folders explored with it. What is open stays open: the list
    // says what was read, not what is.
    mtd clearRecent()
    {
        .recent.clear()
        .recentOpened.clear()
        .exploredFolders.clear()
        .historyChanged()
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
        .historyCleanup.start(me)
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
    mtd historyChanged()
    {
        .pruneResume()
        .refreshHome()
        catch .saveState()
    }

    // Confirms the destructive history action before applying it.
    mtd confirmClearRecent()
    {
        if MessageDlg.confirm(unwrap .surface, appStrings().ui_ConfirmClearHistory) == Dialog.BtnYes do
            .clearRecent()
    }

    // Offers to forget a file that disappeared after it was added to the history.
    mtd confirmForgetMissingRecent(fileName: string)
    {
        let file = String.from(fileName)
        if not .recent.contains(file) do
            return

        let texts = appStrings()
        var options: MessageDlgOptions
        options.title = texts.home_MissingTitle
        if MessageDlg.confirm(unwrap .surface,
                              texts.ui_FailureNotFound,
                              texts.home_AskForgetMissing,
                              options: options) == Dialog.BtnYes do
            .forgetRecent(file)
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
        .siblingsDirty  = true
        catch .saveState()
    }

    // Opens the file `delta` steps away, wrapping around at either end. Image controls stay on
    // files named for the image viewer even when general navigation includes every file kind.
    mtd navigate(delta: s32, imagesOnly: bool = false)
    {
        if .currentFile.isEmpty() do
            return

        if imagesOnly
        {
            let files = .imageSiblings()
            var current: u64
            for file, index in files where file[] == .currentFile
            {
                current = index
                break
            }

            .navigateAmong(delta, files.toSlice(), current)
            return
        }

        if .siblingsDirty do
            .rebuildSiblings()
        .navigateAmong(delta, .siblings.toSlice(), .siblingIndex)
    }

    private mtd navigateAmong(delta: s32, files: const [..] String, current: u64)
    {
        if files.count <= 1 do
            return

        var index = cast(s64, current) + delta
        if index < 0 do
            index = cast(s64, files.count) - 1
        elif index >= cast(s64, files.count) do
            index = 0
        .queueFile(files[cast(u64, index)])
    }

    // Returns the files of the current file's folder that its viewer opens, in folder order and
    // whatever the navigation filter says: a play mode walks the movies of a folder past the notes
    // stored beside them, whether or not ordinary navigation includes those notes.
    mtd kindSiblings()->Array'String
    {
        var result: #returntype
        if .activeChoiceIndex >= .choices.count do
            return result
        let activeKey = .choices[.activeChoiceIndex].key
        for file in .folderFiles
        {
            let choices = .index.choices(file[])
            for choice in choices where choice.key == activeKey
            {
                result.add(file[])
                break
            }
        }

        return result
    }

    // Returns only folder entries whose names select the image viewer.
    private mtd imageSiblings()->Array'String
    {
        var result: #returntype
        for file in .folderFiles
        {
            var pluginIndex: u64
            if .index.namePlugin(file[], &pluginIndex) and .index.plugins[pluginIndex].key == "image" do
                result.add(file[])
        }

        return result
    }
}
